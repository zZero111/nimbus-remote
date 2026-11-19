#include "screenshot.h"
#include "appinfo.h"

#include <QDateTime>
#include <QDir>
#include <QStandardPaths>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>
#include <cmath>
#include <functional>

extern "C" {
#include <libavutil/frame.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
}

namespace {

struct Matrix { double kr, kb; };

Matrix matrixFor(const AVFrame *f)
{
	switch(f->colorspace)
	{
		case AVCOL_SPC_BT2020_NCL:
		case AVCOL_SPC_BT2020_CL:
			return { 0.2627, 0.0593 };
		case AVCOL_SPC_BT470BG:
		case AVCOL_SPC_SMPTE170M:
			return { 0.299, 0.114 };
		default:
			return { 0.2126, 0.0722 }; // BT.709, what the console sends for SDR
	}
}

// SMPTE ST 2084 (PQ) signal -> linear light, normalised so 1.0 = 10000 nits
double pqToLinear(double e)
{
	const double m1 = 2610.0 / 16384.0, m2 = 2523.0 / 4096.0 * 128.0;
	const double c1 = 3424.0 / 4096.0, c2 = 2413.0 / 4096.0 * 32.0, c3 = 2392.0 / 4096.0 * 32.0;
	const double p = std::pow(std::max(e, 0.0), 1.0 / m2);
	return std::pow(std::max(p - c1, 0.0) / (c2 - c3 * p), 1.0 / m1);
}

double linearToSrgb(double l)
{
	l = std::clamp(l, 0.0, 1.0);
	return l <= 0.0031308 ? 12.92 * l : 1.055 * std::pow(l, 1.0 / 2.4) - 0.055;
}

// BT.2020 -> BT.709 primaries, for linear light
void bt2020To709(double &r, double &g, double &b)
{
	const double r2 = 1.6605 * r - 0.5876 * g - 0.0728 * b;
	const double g2 = -0.1246 * r + 1.1329 * g - 0.0083 * b;
	const double b2 = -0.0182 * r - 0.1006 * g + 1.1187 * b;
	r = r2; g = g2; b = b2;
}

// Samples: luma at (x,y), chroma for that pixel, both normalised to 0..1 code values.
template<typename Sampler>
QImage convert(const AVFrame *f, int bit_depth, Sampler sample)
{
	const Matrix m = matrixFor(f);
	const double kg = 1.0 - m.kr - m.kb;
	const bool full = f->color_range == AVCOL_RANGE_JPEG;
	const bool pq = f->color_trc == AVCOL_TRC_SMPTE2084;
	const double max_code = double((1 << bit_depth) - 1);
	const double y_off = full ? 0.0 : 16.0 * (1 << (bit_depth - 8));
	const double y_scale = full ? max_code : 219.0 * (1 << (bit_depth - 8));
	const double c_scale = full ? max_code : 224.0 * (1 << (bit_depth - 8));
	const double c_mid = double(1 << (bit_depth - 1));

	// 203 nits is the reference white for HDR content (ITU-R BT.2408)
	const double hdr_white = 203.0 / 10000.0;

	QImage img(f->width, f->height, QImage::Format_RGB888);
	for(int y = 0; y < f->height; y++)
	{
		uchar *out = img.scanLine(y);
		for(int x = 0; x < f->width; x++)
		{
			double yc, cb, cr;
			sample(x, y, yc, cb, cr);
			const double Y = (yc - y_off) / y_scale;
			const double Pb = (cb - c_mid) / c_scale;
			const double Pr = (cr - c_mid) / c_scale;
			double r = Y + 2.0 * (1.0 - m.kr) * Pr;
			double b = Y + 2.0 * (1.0 - m.kb) * Pb;
			double g = (Y - m.kr * r - m.kb * b) / kg;
			if(pq)
			{
				r = pqToLinear(r) / hdr_white;
				g = pqToLinear(g) / hdr_white;
				b = pqToLinear(b) / hdr_white;
				bt2020To709(r, g, b);
				// Reinhard on each channel keeps highlights from clipping hard
				r = r / (1.0 + r); g = g / (1.0 + g); b = b / (1.0 + b);
				r = linearToSrgb(r * 2.0); g = linearToSrgb(g * 2.0); b = linearToSrgb(b * 2.0);
			}
			out[x * 3 + 0] = uchar(std::lround(std::clamp(r, 0.0, 1.0) * 255.0));
			out[x * 3 + 1] = uchar(std::lround(std::clamp(g, 0.0, 1.0) * 255.0));
			out[x * 3 + 2] = uchar(std::lround(std::clamp(b, 0.0, 1.0) * 255.0));
		}
	}
	(void)max_code;
	return img;
}

QImage convertSoftware(const AVFrame *f, QString *error)
{
	switch(f->format)
	{
		case AV_PIX_FMT_NV12:
			return convert(f, 8, [f](int x, int y, double &Y, double &U, double &V) {
				Y = f->data[0][y * f->linesize[0] + x];
				const uint8_t *uv = f->data[1] + (y / 2) * f->linesize[1] + (x / 2) * 2;
				U = uv[0]; V = uv[1];
			});
		case AV_PIX_FMT_YUV420P:
		case AV_PIX_FMT_YUVJ420P:
			return convert(f, 8, [f](int x, int y, double &Y, double &U, double &V) {
				Y = f->data[0][y * f->linesize[0] + x];
				U = f->data[1][(y / 2) * f->linesize[1] + x / 2];
				V = f->data[2][(y / 2) * f->linesize[2] + x / 2];
			});
		case AV_PIX_FMT_P010LE:
		case AV_PIX_FMT_P016LE:
			// 10-bit values stored in the high bits of 16-bit words
			return convert(f, 10, [f](int x, int y, double &Y, double &U, double &V) {
				const uint16_t *yl = reinterpret_cast<const uint16_t *>(f->data[0] + y * f->linesize[0]);
				const uint16_t *uv = reinterpret_cast<const uint16_t *>(f->data[1] + (y / 2) * f->linesize[1]);
				Y = yl[x] >> 6; U = uv[(x / 2) * 2] >> 6; V = uv[(x / 2) * 2 + 1] >> 6;
			});
		case AV_PIX_FMT_YUV420P10LE:
			return convert(f, 10, [f](int x, int y, double &Y, double &U, double &V) {
				Y = reinterpret_cast<const uint16_t *>(f->data[0] + y * f->linesize[0])[x];
				U = reinterpret_cast<const uint16_t *>(f->data[1] + (y / 2) * f->linesize[1])[x / 2];
				V = reinterpret_cast<const uint16_t *>(f->data[2] + (y / 2) * f->linesize[2])[x / 2];
			});
		default:
			if(error)
				*error = QStringLiteral("unsupported pixel format %1").arg(av_get_pix_fmt_name(AVPixelFormat(f->format)));
			return {};
	}
}

}

namespace Screenshot {

QImage frameToImage(const AVFrame *frame, QString *error)
{
	if(!frame || frame->width <= 0 || frame->height <= 0)
	{
		if(error)
			*error = QStringLiteral("no frame");
		return {};
	}
	if(!frame->hw_frames_ctx)
		return convertSoftware(frame, error);

	// Hardware frame (D3D11, Vulkan, VAAPI...): download to system memory first
	AVFrame *sw = av_frame_alloc();
	if(!sw)
		return {};
	QImage img;
	if(av_hwframe_transfer_data(sw, frame, 0) < 0)
	{
		if(error)
			*error = QStringLiteral("could not download hardware frame");
	}
	else
	{
		sw->colorspace = frame->colorspace;
		sw->color_range = frame->color_range;
		sw->color_trc = frame->color_trc;
		sw->color_primaries = frame->color_primaries;
		img = convertSoftware(sw, error);
	}
	av_frame_free(&sw);
	return img;
}

QString screenshotDir()
{
	QString base = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
	if(base.isEmpty())
		base = QDir::homePath();
	return QDir(base).filePath(APP_DISPLAY_NAME);
}

void saveAsync(AVFrame *frame, std::function<void(const QString &, const QString &)> done)
{
	(void)QtConcurrent::run([frame, done]() mutable {
		QString error;
		QImage img = frameToImage(frame, &error);
		av_frame_free(&frame);
		if(img.isNull())
		{
			done(QString(), error.isEmpty() ? QStringLiteral("conversion failed") : error);
			return;
		}
		QDir dir(screenshotDir());
		if(!dir.mkpath("."))
		{
			done(QString(), QStringLiteral("could not create %1").arg(dir.path()));
			return;
		}
		const QString path = dir.filePath(QStringLiteral("Screenshot_%1.png")
			.arg(QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss_zzz")));
		if(!img.save(path, "PNG"))
			done(QString(), QStringLiteral("could not write %1").arg(path));
		else
			done(path, QString());
	});
}

}
