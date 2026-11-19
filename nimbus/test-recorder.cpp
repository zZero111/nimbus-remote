// End-to-end test for StreamRecorder: encodes H.264 + Opus with FFmpeg, feeds the packets the way
// the console does (parameter sets once at stream start, recording started mid-stream), then
// demuxes and decodes the resulting .ts to check it is playable.
// Build + run: bash tools/test-recorder.sh
#include "recorder.h"

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
	std::vector<uint8_t> extradata;
	const int gop = 30;
	auto video = encodeVideo(120, gop, extradata);
	auto audio = encodeOpus(100);
	check(video.size() >= 100, "encoded H.264 test video");
	check(!audio.empty(), "encoded Opus test audio");
	if(video.empty())
		return 1;

	using VC = StreamRecorder::VideoCodec;
	check(!extradata.empty() && StreamRecorder::hasParameterSets(extradata.data(), extradata.size(), VC::H264), "stream header carries SPS/PPS");
	check(!StreamRecorder::isKeyframe(extradata.data(), extradata.size(), VC::H264), "header alone is not a keyframe");
	check(StreamRecorder::isKeyframe(video[0].data.data(), video[0].data.size(), VC::H264), "first packet is an IDR");
	check(!StreamRecorder::hasParameterSets(video[gop].data.data(), video[gop].data.size(), VC::H264), "mid-stream IDR has no SPS (console-like)");
	check(StreamRecorder::isKeyframe(video[gop].data.data(), video[gop].data.size(), VC::H264), "mid-stream IDR detected as keyframe");
	check(!StreamRecorder::isKeyframe(video[gop + 1].data.data(), video[gop + 1].data.size(), VC::H264), "P-frame not detected as keyframe");

	const QString path = QDir::temp().filePath("nimbus-recorder-test.ts");
	QFile::remove(path);
	StreamRecorder rec;
	// Stream starts: the session sees every packet, recording begins later (mid-GOP)
	size_t audio_i = 0;
	const int start_at = gop / 2;
	// videoreceiver.c sends the profile header through the sample callback first
	rec.notePossibleParameterSets(extradata.data(), extradata.size(), VC::H264);
	rec.writeVideo(extradata.data(), extradata.size()); // not recording yet: ignored
	for(size_t i = 0; i < video.size(); i++)
	{
		rec.notePossibleParameterSets(video[i].data.data(), video[i].data.size(), VC::H264);
		if(int(i) == start_at)
		{
			QString err;
			check(rec.start(path, VC::H264, 320, 180, 2, 48000, &err), "recorder starts");
		}
		rec.writeVideo(video[i].data.data(), video[i].data.size());
		QThread::usleep(16000); // console sends ~60 fps
		if(audio_i < audio.size())
		{
			rec.writeAudio(audio[audio_i].data.data(), audio[audio_i].data.size());
			audio_i++;
		}
	}
	rec.stop();
	check(!rec.isRecording(), "recorder stopped");
	check(QFileInfo(path).size() > 1000, "recording file written");

	// Demux + decode the recording
	AVFormatContext *in = nullptr;
	int r = avformat_open_input(&in, path.toUtf8().constData(), nullptr, nullptr);
	check(r == 0, "recording opens as a media file");
	if(r != 0)
		return 1;
	avformat_find_stream_info(in, nullptr);
	int vi = av_find_best_stream(in, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
	int ai = av_find_best_stream(in, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
	check(vi >= 0, "recording has a video stream");
	check(ai >= 0, "recording has an audio stream");
	check(vi >= 0 && in->streams[vi]->codecpar->codec_id == AV_CODEC_ID_H264, "video stream is H.264");
	check(ai >= 0 && in->streams[ai]->codecpar->codec_id == AV_CODEC_ID_OPUS, "audio stream is Opus");
	const AVCodec *dec = avcodec_find_decoder(AV_CODEC_ID_H264);
	AVCodecContext *dc = avcodec_alloc_context3(dec);
	avcodec_parameters_to_context(dc, in->streams[vi]->codecpar);
	avcodec_open2(dc, dec, nullptr);
	AVPacket *p = av_packet_alloc();
	AVFrame *f = av_frame_alloc();
	int decoded = 0, audio_pkts = 0, decode_errors = 0;
	while(av_read_frame(in, p) == 0)
	{
		if(p->stream_index == vi)
		{
			if(avcodec_send_packet(dc, p) < 0)
				decode_errors++;
			while(avcodec_receive_frame(dc, f) == 0)
				decoded++;
		}
		else if(p->stream_index == ai)
			audio_pkts++;
		av_packet_unref(p);
	}
	avcodec_send_packet(dc, nullptr);
	while(avcodec_receive_frame(dc, f) == 0)
		decoded++;
	// Recording started at frame 15, first keyframe at frame 30 -> frames 30..119 = 90 frames
	const int expected = int(video.size()) - gop;
	std::printf("decoded %d video frames (expected %d), %d audio packets, %d decode errors\n", decoded, expected, audio_pkts, decode_errors);
	check(decoded == expected, "every recorded video frame decodes");
	check(decode_errors == 0, "no decode errors");
	check(audio_pkts > 0, "audio packets present");
	av_frame_free(&f);
	av_packet_free(&p);
	avcodec_free_context(&dc);
	avformat_close_input(&in);
	QFile::remove(path);

	std::printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures, failures == 1 ? "" : "s");
	return failures ? 1 : 0;
}
