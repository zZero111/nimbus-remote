// End-to-end test for ReplayBuffer (instant replay): 45 s of console-like H.264 + Opus go in,
// the buffer keeps only the last ~30 s from a keyframe, and the saved clip must decode cleanly.
// Uses synthetic arrival times, so it runs in a second.
// Build + run: bash nimbus/test-replay.sh
#include "replaybuffer.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QThread>
#include <cstdio>
#include <vector>

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/opt.h>
}

static int failures = 0;
static void check(bool ok, const char *what)
{
	std::printf("%-58s %s\n", what, ok ? "OK" : "FAIL");
	if(!ok)
		failures++;
}

struct Packet { std::vector<uint8_t> data; };

// Encodes `count` 320x180 frames; keyframe every `gop` frames; SPS/PPS only in the very first packet
static std::vector<Packet> encodeVideo(int count, int gop, std::vector<uint8_t> &header_only)
{
	std::vector<Packet> out;
	const AVCodec *enc = avcodec_find_encoder_by_name("libx264");
	if(!enc)
		enc = avcodec_find_encoder(AV_CODEC_ID_H264);
	if(!enc)
		return out;
	AVCodecContext *c = avcodec_alloc_context3(enc);
	c->width = 320; c->height = 180;
	c->time_base = AVRational{1, 60};
	c->framerate = AVRational{60, 1};
	c->pix_fmt = AV_PIX_FMT_YUV420P;
	c->gop_size = gop;
	c->max_b_frames = 0;
	av_opt_set(c->priv_data, "preset", "ultrafast", 0);
	av_opt_set(c->priv_data, "tune", "zerolatency", 0);
	// Like the console: SPS/PPS come once as a separate header (extradata, Annex B), never in-band
	c->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
	av_opt_set(c->priv_data, "x264-params", "repeat-headers=0:annexb=1", 0);
	if(avcodec_open2(c, enc, nullptr) < 0)
		return out;
	AVFrame *f = av_frame_alloc();
	f->format = c->pix_fmt; f->width = c->width; f->height = c->height;
	av_frame_get_buffer(f, 32);
	AVPacket *p = av_packet_alloc();
	for(int i = 0; i <= count; i++)
	{
		if(i < count)
		{
			av_frame_make_writable(f);
			for(int y = 0; y < c->height; y++)
				for(int x = 0; x < c->width; x++)
					f->data[0][y * f->linesize[0] + x] = uint8_t(x + y + i * 3);
			for(int y = 0; y < c->height / 2; y++)
				for(int x = 0; x < c->width / 2; x++)
				{
					f->data[1][y * f->linesize[1] + x] = uint8_t(128 + y + i * 2);
					f->data[2][y * f->linesize[2] + x] = uint8_t(64 + x + i * 5);
				}
			f->pts = i;
			// Force IDRs on the gop boundary
			f->pict_type = (i % gop == 0) ? AV_PICTURE_TYPE_I : AV_PICTURE_TYPE_NONE;
			avcodec_send_frame(c, f);
		}
		else
			avcodec_send_frame(c, nullptr);
		while(avcodec_receive_packet(c, p) == 0)
		{
			out.push_back({std::vector<uint8_t>(p->data, p->data + p->size)});
			av_packet_unref(p);
		}
	}
	if(c->extradata_size > 0)
		header_only.assign(c->extradata, c->extradata + c->extradata_size);
	av_packet_free(&p);
	av_frame_free(&f);
	avcodec_free_context(&c);
	return out;
}

static std::vector<Packet> encodeOpus(int count)
{
	std::vector<Packet> out;
	const AVCodec *enc = avcodec_find_encoder_by_name("libopus");
	if(!enc)
		enc = avcodec_find_encoder(AV_CODEC_ID_OPUS);
	if(!enc)
		return out;
	AVCodecContext *c = avcodec_alloc_context3(enc);
	c->sample_rate = 48000;
	av_channel_layout_default(&c->ch_layout, 2);
	const void *fmts = nullptr;
	int nfmts = 0;
	avcodec_get_supported_config(c, enc, AV_CODEC_CONFIG_SAMPLE_FORMAT, 0, &fmts, &nfmts);
	c->sample_fmt = (fmts && nfmts > 0) ? static_cast<const AVSampleFormat *>(fmts)[0] : AV_SAMPLE_FMT_S16;
	c->bit_rate = 96000;
	if(avcodec_open2(c, enc, nullptr) < 0)
		return out;
	AVFrame *f = av_frame_alloc();
	f->format = c->sample_fmt; f->nb_samples = c->frame_size > 0 ? c->frame_size : 960;
	av_channel_layout_copy(&f->ch_layout, &c->ch_layout);
	f->sample_rate = 48000;
	av_frame_get_buffer(f, 0);
	AVPacket *p = av_packet_alloc();
	for(int i = 0; i < count; i++)
	{
		av_frame_make_writable(f);
		std::memset(f->data[0], 0, size_t(f->linesize[0]));
		f->pts = int64_t(i) * f->nb_samples;
		avcodec_send_frame(c, f);
		while(avcodec_receive_packet(c, p) == 0)
		{
			out.push_back({std::vector<uint8_t>(p->data, p->data + p->size)});
			av_packet_unref(p);
		}
	}
	av_packet_free(&p);
	av_frame_free(&f);
	avcodec_free_context(&c);
	return out;
}
int main(int argc, char **argv)
{
	QCoreApplication app(argc, argv);
	av_log_set_level(AV_LOG_QUIET);
	using VC = StreamRecorder::VideoCodec;
	const int fps = 60, seconds = 45, gop = 600; // keyframe every 10 s
	std::vector<uint8_t> extradata;
	auto video = encodeVideo(fps * seconds, gop, extradata);
	auto audio = encodeOpus(seconds * 50 + 10); // 20 ms packets
	check(int(video.size()) == fps * seconds, "encoded 45 s of H.264 test video");
	check(audio.size() >= size_t(seconds * 50), "encoded 45 s of Opus test audio");
	if(video.empty() || audio.empty())
		return 1;

	ReplayBuffer replay(VC::H264);
	const int64_t frame_us = 1000000 / fps;
	// The profile header (SPS/PPS) comes first, as from videoreceiver.c; it isn't a keyframe
	replay.pushVideo(extradata.data(), extradata.size(), 0);
	check(replay.seconds(0) == 0.0, "header alone is not buffered");
	size_t ai = 0;
	for(size_t i = 0; i < video.size(); i++)
	{
		const int64_t t = int64_t(i) * frame_us;
		replay.pushVideo(video[i].data.data(), video[i].data.size(), t);
		while(ai < audio.size() && int64_t(ai) * 20000 <= t)
		{
			replay.pushAudio(audio[ai].data.data(), audio[ai].data.size(), int64_t(ai) * 20000);
			ai++;
		}
	}
	const int64_t now = int64_t(video.size() - 1) * frame_us;
	const double held = replay.seconds(now);
	std::printf("   buffer holds %.1f s, %.1f MB, last keyframe %.1f s ago\n", held, replay.bytes() / 1048576.0, replay.keyframeAgeUs(now) / 1e6);
	// Newest keyframe at least 30 s old is at 10 s -> 35 s held (window + up to one keyframe gap)
	check(held >= 30.0 && held <= 40.0, "buffer keeps 30-40 s (from a keyframe at or before -30 s)");
	check(replay.keyframeAgeUs(now) >= 0 && replay.keyframeAgeUs(now) < 10 * 1000000LL, "keyframe age is tracked");

	const QString path = QDir::temp().filePath("nimbus-replay-test.ts");
	QFile::remove(path);
	QString err;
	check(replay.save(path, 320, 180, 2, &err), "clip saves");
	check(QFileInfo(path).size() > 1000, "clip file written");

	// The buffer keeps working while/after saving
	replay.pushVideo(video[1].data.data(), video[1].data.size(), now + frame_us);
	check(replay.seconds(now + frame_us) > 30.0, "buffer still filled after saving");

	AVFormatContext *in = nullptr;
	int r = avformat_open_input(&in, path.toUtf8().constData(), nullptr, nullptr);
	check(r == 0, "clip opens as a media file");
	if(r != 0)
		return 1;
	avformat_find_stream_info(in, nullptr);
	int vi = av_find_best_stream(in, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
	int au = av_find_best_stream(in, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
	check(vi >= 0 && au >= 0, "clip has video and audio");
	const AVCodec *dec = avcodec_find_decoder(AV_CODEC_ID_H264);
	AVCodecContext *dc = avcodec_alloc_context3(dec);
	avcodec_parameters_to_context(dc, in->streams[vi]->codecpar);
	avcodec_open2(dc, dec, nullptr);
	AVPacket *p = av_packet_alloc();
	AVFrame *f = av_frame_alloc();
	int decoded = 0, audio_pkts = 0, errors = 0;
	int64_t first_pts = -1, last_pts = -1;
	while(av_read_frame(in, p) == 0)
	{
		if(p->stream_index == vi)
		{
			if(first_pts < 0)
				first_pts = p->pts;
			last_pts = p->pts;
			if(avcodec_send_packet(dc, p) < 0)
				errors++;
			while(avcodec_receive_frame(dc, f) == 0)
				decoded++;
		}
		else if(p->stream_index == au)
			audio_pkts++;
		av_packet_unref(p);
	}
	avcodec_send_packet(dc, nullptr);
	while(avcodec_receive_frame(dc, f) == 0)
		decoded++;
	const double dur = (last_pts - first_pts) * av_q2d(in->streams[vi]->time_base);
	const int expected = int(video.size()) - gop; // from the keyframe at 10 s to the end
	std::printf("   clip: %d frames decoded (expected %d), %.1f s of video, %d audio packets, %d errors\n", decoded, expected, dur, audio_pkts, errors);
	check(decoded == expected, "every frame in the clip decodes");
	check(errors == 0, "no decode errors (clip starts on a keyframe with SPS/PPS)");
	check(dur > 33.0 && dur < 36.0, "clip timing matches the original (~35 s)");
	check(audio_pkts > 1500, "clip has its audio");
	av_frame_free(&f);
	av_packet_free(&p);
	avcodec_free_context(&dc);
	avformat_close_input(&in);
	QFile::remove(path);

	// Memory cap: a tiny cap must never let the buffer grow past it
	ReplayBuffer small(VC::H264, 30 * 1000000LL, 200 * 1024);
	int64_t worst = 0;
	for(size_t i = 0; i < video.size(); i++)
	{
		small.pushVideo(video[i].data.data(), video[i].data.size(), int64_t(i) * frame_us);
		worst = std::max(worst, small.bytes());
	}
	check(worst <= 200 * 1024 + 64 * 1024, "memory cap respected");

	std::printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures, failures == 1 ? "" : "s");
	return failures ? 1 : 0;
}
