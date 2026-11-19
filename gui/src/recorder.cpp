#include "recorder.h"

#include <QDir>
#include <QFileInfo>

#include <chrono>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/mathematics.h>
}

namespace {

// Number of samples in one Opus packet, from its TOC byte (RFC 6716 section 3.1)
int opusPacketSamples(const uint8_t *buf, size_t size, int rate)
{
	if(size < 1)
		return 0;
	static const int silk_us[] = {10000, 20000, 40000, 60000};
	static const int celt_us[] = {2500, 5000, 10000, 20000};
	const int config = buf[0] >> 3;
	int frame_us;
	if(config < 12)
		frame_us = silk_us[config & 3];
	else if(config < 16)
		frame_us = (config & 1) ? 20000 : 10000;
	else
		frame_us = celt_us[config & 3];
	int frames;
	switch(buf[0] & 3)
	{
		case 0: frames = 1; break;
		case 1:
		case 2: frames = 2; break;
		default: frames = size >= 2 ? (buf[1] & 0x3f) : 0; break;
	}
	return int(int64_t(frames) * frame_us * rate / 1000000);
}

QString avError(int err)
{
	char buf[AV_ERROR_MAX_STRING_SIZE] = {};
	av_strerror(err, buf, sizeof(buf));
	return QString::fromUtf8(buf);
}

}

StreamRecorder::~StreamRecorder()
{
	stop();
}

int64_t StreamRecorder::nowUs() const
{
	return clockUs();
}

int64_t StreamRecorder::clockUs()
{
	return std::chrono::duration_cast<std::chrono::microseconds>(
		std::chrono::steady_clock::now().time_since_epoch()).count();
}

bool StreamRecorder::start(const QString &path, VideoCodec video_codec, int width, int height,
	int audio_channels, int rate, QString *error, int64_t start_at_us)
{
	QMutexLocker locker(&mutex);
	closeLocked();

	QDir().mkpath(QFileInfo(path).absolutePath());
	const QByteArray path_utf8 = path.toUtf8();
	int err = avformat_alloc_output_context2(&fmt, nullptr, "mpegts", path_utf8.constData());
	if(err < 0 || !fmt)
	{
		if(error) *error = QStringLiteral("could not create recording: %1").arg(avError(err));
		fmt = nullptr;
		return false;
	}

	video_stream = avformat_new_stream(fmt, nullptr);
	video_stream->time_base = AVRational{1, 90000};
	video_stream->codecpar->codec_type = AVMEDIA_TYPE_VIDEO;
	video_stream->codecpar->codec_id = video_codec == VideoCodec::H265 ? AV_CODEC_ID_HEVC : AV_CODEC_ID_H264;
	video_stream->codecpar->width = width;
	video_stream->codecpar->height = height;

	if(audio_channels > 0)
	{
		audio_stream = avformat_new_stream(fmt, nullptr);
		audio_stream->time_base = AVRational{1, 90000};
		audio_stream->codecpar->codec_type = AVMEDIA_TYPE_AUDIO;
		audio_stream->codecpar->codec_id = AV_CODEC_ID_OPUS;
		audio_stream->codecpar->sample_rate = 48000; // Opus always decodes at 48 kHz
		av_channel_layout_default(&audio_stream->codecpar->ch_layout, audio_channels);
	}

	if(!(fmt->oformat->flags & AVFMT_NOFILE))
	{
		err = avio_open(&fmt->pb, path_utf8.constData(), AVIO_FLAG_WRITE);
		if(err < 0)
		{
			if(error) *error = QStringLiteral("could not open %1: %2").arg(path, avError(err));
			avformat_free_context(fmt);
			fmt = nullptr;
			return false;
		}
	}
	err = avformat_write_header(fmt, nullptr);
	if(err < 0)
	{
		if(error) *error = QStringLiteral("could not start recording: %1").arg(avError(err));
		if(fmt->pb)
			avio_closep(&fmt->pb);
		avformat_free_context(fmt);
		fmt = nullptr;
		return false;
	}

	codec = video_codec;
	file_path = path;
	start_us = start_at_us >= 0 ? start_at_us : nowUs();
	got_keyframe = false;
	audio_samples = 0;
	last_video_pts = -1;
	last_audio_pts = -1;
	audio_rate = rate > 0 ? rate : 48000;
	return true;
}

void StreamRecorder::stop()
{
	QMutexLocker locker(&mutex);
	closeLocked();
}

void StreamRecorder::closeLocked()
{
	if(!fmt)
		return;
	av_write_trailer(fmt);
	if(fmt->pb)
		avio_closep(&fmt->pb);
	avformat_free_context(fmt);
	fmt = nullptr;
	video_stream = nullptr;
	audio_stream = nullptr;
}

bool StreamRecorder::isRecording() const
{
	QMutexLocker locker(&mutex);
	return fmt != nullptr;
}

QString StreamRecorder::path() const
{
	QMutexLocker locker(&mutex);
	return file_path;
}

double StreamRecorder::elapsedSeconds() const
{
	QMutexLocker locker(&mutex);
	return fmt ? (nowUs() - start_us) / 1e6 : 0.0;
}

qint64 StreamRecorder::bytesWritten() const
{
	QMutexLocker locker(&mutex);
	return (fmt && fmt->pb) ? avio_tell(fmt->pb) : 0;
}

namespace {

// Calls fn(nal_type) for each NAL unit after an Annex B start code; stops when fn returns true
template<typename Fn>
bool anyNal(const uint8_t *buf, size_t size, StreamRecorder::VideoCodec codec, Fn fn)
{
	for(size_t i = 0; i + 3 < size; i++)
	{
		if(buf[i] != 0 || buf[i + 1] != 0 || buf[i + 2] != 1)
			continue;
		const uint8_t h = buf[i + 3];
		const int type = codec == StreamRecorder::VideoCodec::H264 ? (h & 0x1f) : ((h >> 1) & 0x3f);
		if(fn(type))
			return true;
	}
	return false;
}

}

bool StreamRecorder::isKeyframe(const uint8_t *buf, size_t size, VideoCodec video_codec)
{
	// IDR slice (H.264 type 5) or IRAP picture (H.265 types 16-21)
	return anyNal(buf, size, video_codec, [video_codec](int type) {
		return video_codec == VideoCodec::H264 ? type == 5 : (type >= 16 && type <= 21);
	});
}

bool StreamRecorder::hasParameterSets(const uint8_t *buf, size_t size, VideoCodec video_codec)
{
	// SPS (H.264 type 7) or VPS / SPS (H.265 types 32, 33)
	return anyNal(buf, size, video_codec, [video_codec](int type) {
		return video_codec == VideoCodec::H264 ? type == 7 : (type == 32 || type == 33);
	});
}

void StreamRecorder::notePossibleParameterSets(const uint8_t *buf, size_t size, VideoCodec video_codec)
{
	if(!buf || !size || !hasParameterSets(buf, size, video_codec))
		return;
	// Keep only the part before the first picture slice: the parameter sets themselves
	size_t end = size;
	for(size_t i = 0; i + 3 < size; i++)
	{
		if(buf[i] != 0 || buf[i + 1] != 0 || buf[i + 2] != 1)
			continue;
		const uint8_t h = buf[i + 3];
		const int type = video_codec == VideoCodec::H264 ? (h & 0x1f) : ((h >> 1) & 0x3f);
		const bool is_slice = video_codec == VideoCodec::H264 ? (type >= 1 && type <= 5) : (type <= 31);
		if(is_slice)
		{
			end = (i > 0 && buf[i - 1] == 0) ? i - 1 : i; // include a 4-byte start code's leading zero
			break;
		}
	}
	QMutexLocker locker(&mutex);
	parameter_sets = QByteArray(reinterpret_cast<const char *>(buf), qsizetype(end));
}

void StreamRecorder::writeVideo(const uint8_t *buf, size_t size, int64_t at_us)
{
	if(!buf || !size)
		return;
	QMutexLocker locker(&mutex);
	if(!fmt || !video_stream)
		return;
	const bool key = isKeyframe(buf, size, codec);
	bool prepend_params = false;
	if(!got_keyframe)
	{
		if(!key)
			return; // a file must start on a keyframe to be playable
		got_keyframe = true;
		// Decoders need SPS/PPS before the first picture; mid-stream keyframes often lack them
		prepend_params = !parameter_sets.isEmpty() && !hasParameterSets(buf, size, codec);
	}
	const size_t prefix = prepend_params ? size_t(parameter_sets.size()) : 0;
	AVPacket *pkt = av_packet_alloc();
	if(!pkt)
		return;
	if(av_new_packet(pkt, int(prefix + size)) == 0)
	{
		if(prefix)
			memcpy(pkt->data, parameter_sets.constData(), prefix);
		memcpy(pkt->data + prefix, buf, size);
		pkt->stream_index = video_stream->index;
		// Clock-based, but never equal to or before the previous frame (the muxer rejects that)
		int64_t pts = av_rescale_q((at_us >= 0 ? at_us : nowUs()) - start_us, AVRational{1, 1000000}, video_stream->time_base);
		if(pts <= last_video_pts)
			pts = last_video_pts + 1;
		last_video_pts = pts;
		pkt->pts = pkt->dts = pts;
		if(key)
			pkt->flags |= AV_PKT_FLAG_KEY;
		av_interleaved_write_frame(fmt, pkt);
	}
	av_packet_free(&pkt);
}

void StreamRecorder::writeAudio(const uint8_t *buf, size_t size, int64_t at_us)
{
	if(!buf || !size)
		return;
	QMutexLocker locker(&mutex);
	if(!fmt || !audio_stream || !got_keyframe)
		return; // keep audio in step with video, which starts at the first keyframe
	int samples = opusPacketSamples(buf, size, 48000);
	if(samples <= 0)
		samples = audio_frame_samples;
	AVPacket *pkt = av_packet_alloc();
	if(!pkt)
		return;
	if(av_new_packet(pkt, int(size)) == 0)
	{
		memcpy(pkt->data, buf, size);
		pkt->stream_index = audio_stream->index;
		// Audio arrives at a steady rate, so count samples instead of using the clock.
		// If the clock runs more than 200 ms ahead (packets were lost), skip forward to it;
		// never move backwards.
		const int64_t clock_pts = (at_us >= 0 ? at_us : nowUs()) - start_us;
		int64_t sample_pts = audio_samples * 1000000 / 48000;
		if(clock_pts > sample_pts + 200000)
		{
			audio_samples = clock_pts * 48000 / 1000000;
			sample_pts = clock_pts;
		}
		int64_t pts = av_rescale_q(sample_pts, AVRational{1, 1000000}, audio_stream->time_base);
		if(pts <= last_audio_pts)
			pts = last_audio_pts + 1;
		last_audio_pts = pts;
		pkt->pts = pkt->dts = pts;
		pkt->duration = av_rescale_q(int64_t(samples) * 1000000 / 48000, AVRational{1, 1000000}, audio_stream->time_base);
		audio_samples += samples;
		av_interleaved_write_frame(fmt, pkt);
	}
	av_packet_free(&pkt);
}
