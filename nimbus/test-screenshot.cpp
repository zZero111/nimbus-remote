// Checks Screenshot::frameToImage colour conversion on synthetic frames with known colours.
// Build + run: bash tools/test-screenshot.sh
#include "screenshot.h"

#include <QColor>
#include <QCoreApplication>
#include <cstdio>
#include <cstdlib>

extern "C" {
#include <libavutil/frame.h>
}

static int failures = 0;

static void expect(const char *name, QRgb got, int r, int g, int b, int tol)
{
	const bool ok = std::abs(qRed(got) - r) <= tol && std::abs(qGreen(got) - g) <= tol && std::abs(qBlue(got) - b) <= tol;
	std::printf("%-34s got (%3d,%3d,%3d) want (%3d,%3d,%3d) %s\n", name, qRed(got), qGreen(got), qBlue(got), r, g, b, ok ? "OK" : "FAIL");
	if(!ok)
		failures++;
}

// Fills an NV12 frame (BT.709 limited range) with one Y/U/V value
static AVFrame *nv12(int Y, int U, int V)
{
	AVFrame *f = av_frame_alloc();
	f->format = AV_PIX_FMT_NV12;
	f->width = 64; f->height = 32;
	f->colorspace = AVCOL_SPC_BT709;
	f->color_range = AVCOL_RANGE_MPEG;
	av_frame_get_buffer(f, 32);
	for(int y = 0; y < f->height; y++)
		for(int x = 0; x < f->width; x++)
			f->data[0][y * f->linesize[0] + x] = uint8_t(Y);
	for(int y = 0; y < f->height / 2; y++)
		for(int x = 0; x < f->width / 2; x++)
		{
			f->data[1][y * f->linesize[1] + x * 2] = uint8_t(U);
			f->data[1][y * f->linesize[1] + x * 2 + 1] = uint8_t(V);
		}
	return f;
}

// P010 (10-bit in high bits), BT.2020 PQ, limited range
static AVFrame *p010(int Y, int U, int V)
{
	AVFrame *f = av_frame_alloc();
	f->format = AV_PIX_FMT_P010LE;
	f->width = 64; f->height = 32;
	f->colorspace = AVCOL_SPC_BT2020_NCL;
	f->color_range = AVCOL_RANGE_MPEG;
	f->color_trc = AVCOL_TRC_SMPTE2084;
	av_frame_get_buffer(f, 32);
	for(int y = 0; y < f->height; y++)
		for(int x = 0; x < f->width; x++)
			reinterpret_cast<uint16_t *>(f->data[0] + y * f->linesize[0])[x] = uint16_t(Y << 6);
	for(int y = 0; y < f->height / 2; y++)
		for(int x = 0; x < f->width / 2; x++)
		{
			uint16_t *uv = reinterpret_cast<uint16_t *>(f->data[1] + y * f->linesize[1]);
			uv[x * 2] = uint16_t(U << 6);
			uv[x * 2 + 1] = uint16_t(V << 6);
		}
	return f;
}

static QRgb convertAndSample(AVFrame *f)
{
	QString err;
	QImage img = Screenshot::frameToImage(f, &err);
	av_frame_free(&f);
	if(img.isNull())
	{
		std::printf("conversion failed: %s\n", qPrintable(err));
		failures++;
		return 0;
	}
	return img.pixel(10, 10);
}

int main(int argc, char **argv)
{
	QCoreApplication app(argc, argv);
	// BT.709 limited-range reference values
	expect("NV12 white", convertAndSample(nv12(235, 128, 128)), 255, 255, 255, 2);
	expect("NV12 black", convertAndSample(nv12(16, 128, 128)), 0, 0, 0, 2);
	expect("NV12 mid grey", convertAndSample(nv12(126, 128, 128)), 128, 128, 128, 3);
	expect("NV12 red", convertAndSample(nv12(63, 102, 240)), 255, 0, 0, 4);
	expect("NV12 green", convertAndSample(nv12(173, 42, 26)), 0, 255, 0, 4);
	expect("NV12 blue", convertAndSample(nv12(32, 240, 118)), 0, 0, 255, 4);
	// PQ: code 0.58 ~ 203 nits (HDR reference white) should map to near-white, black to black
	const int ref_white = int(64 + 0.58 * 876);
	expect("P010 PQ reference white", convertAndSample(p010(ref_white, 512, 512)), 255, 255, 255, 20);
	expect("P010 PQ black", convertAndSample(p010(64, 512, 512)), 0, 0, 0, 2);
	std::printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures, failures == 1 ? "" : "s");
	return failures ? 1 : 0;
}
