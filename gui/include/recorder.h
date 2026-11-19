// Stream recording: copies the console's encoded video (H.264/H.265) and Opus audio
// straight into an MPEG-TS file. No re-encoding, so it costs almost no CPU or quality.
#ifndef RECORDER_H
#define RECORDER_H

#include <QByteArray>
#include <QMutex>
#include <QString>

#include <cstdint>

struct AVFormatContext;
struct AVStream;

class StreamRecorder
{
public:
	enum class VideoCodec { H264, H265 };

	StreamRecorder() = default;
	~StreamRecorder();

	/// Opens `path` for writing. Video is written from the next keyframe on.
	bool start(const QString &path, VideoCodec codec, int width, int height, int audio_channels, int audio_rate, QString *error);
	/// Finishes the file. Safe to call when not recording.
	void stop();
	bool isRecording() const;
	QString path() const;
	/// Seconds since start, 0 when not recording
	double elapsedSeconds() const;
	/// Bytes written so far
	qint64 bytesWritten() const;

	/// One Annex B access unit from the console. Thread-safe.
	void writeVideo(const uint8_t *buf, size_t size);
	/// One Opus packet from the console. Thread-safe.
	void writeAudio(const uint8_t *buf, size_t size);

	/// Remembers the latest SPS/PPS(/VPS) seen in the stream. The console sends them once at
	/// stream start, so they're put in front of the first keyframe of a recording started later.
	/// Call for every video sample, recording or not. Thread-safe.
	void notePossibleParameterSets(const uint8_t *buf, size_t size, VideoCodec codec);

	/// True if `buf` (Annex B) contains an IDR / IRAP picture for `codec`.
	static bool isKeyframe(const uint8_t *buf, size_t size, VideoCodec codec);
	/// True if `buf` (Annex B) contains an SPS (H.264) or VPS/SPS (H.265).
	static bool hasParameterSets(const uint8_t *buf, size_t size, VideoCodec codec);

private:
	void closeLocked();
	int64_t nowUs() const;

	mutable QMutex mutex;
	AVFormatContext *fmt = nullptr;
	AVStream *video_stream = nullptr;
	AVStream *audio_stream = nullptr;
	VideoCodec codec = VideoCodec::H264;
	QString file_path;
	int64_t start_us = 0;
	bool got_keyframe = false;
	QByteArray parameter_sets;
	int64_t audio_samples = 0;
	int64_t last_video_pts = -1;
	int64_t last_audio_pts = -1;
	int audio_rate = 48000;
	int audio_frame_samples = 480;
};

#endif
