// Instant replay: keeps the last ~30 seconds of the stream (video and audio exactly as the
// console sent them) in memory, so "Save clip" can write them to a file afterwards, like the
// PS5's Create button. Nothing is re-encoded, so it costs almost no CPU.
//
// A clip must start on a keyframe, so the buffer always begins with one and holds a little more
// than the window: everything from the newest keyframe that is at least `window` old.
#ifndef REPLAYBUFFER_H
#define REPLAYBUFFER_H

#include <QByteArray>
#include <QMutex>
#include <QString>

#include <cstdint>
#include <deque>
#include <functional>

#include "recorder.h"

class ReplayBuffer
{
public:
	ReplayBuffer(StreamRecorder::VideoCodec codec, int64_t window_us = 30 * 1000000LL, int64_t max_bytes = 400LL * 1024 * 1024);

	/// Called from the network thread for every sample. `at_us`: StreamRecorder::clockUs().
	void pushVideo(const uint8_t *buf, size_t size, int64_t at_us);
	void pushAudio(const uint8_t *buf, size_t size, int64_t at_us);
	void clear();

	/// Microseconds since the last keyframe arrived (or -1 if none yet).
	int64_t keyframeAgeUs(int64_t now_us) const;
	/// Seconds of video currently held, from the first keyframe.
	double seconds(int64_t now_us) const;
	int64_t bytes() const;

	/// Writes the buffered stream to `path` (MPEG-TS). Safe to call from any thread; the buffer
	/// keeps filling while it writes. Returns false with `error` set if there is nothing to save.
	bool save(const QString &path, int width, int height, int audio_channels, QString *error) const;

	struct Entry
	{
		bool video;
		bool key;
		int64_t at_us;
		QByteArray data;
	};
	/// A copy of the buffer that stays valid on its own (for saving on another thread).
	struct Snapshot
	{
		StreamRecorder::VideoCodec codec = StreamRecorder::VideoCodec::H264;
		std::deque<Entry> entries;
		QByteArray parameter_sets_sample;
	};
	Snapshot snapshot() const;
	static bool write(const Snapshot &snap, const QString &path, int width, int height, int audio_channels, QString *error);

private:
	void trimLocked();

	const StreamRecorder::VideoCodec codec;
	const int64_t window_us;
	const int64_t max_bytes;
	mutable QMutex mutex;
	std::deque<Entry> entries;
	int64_t total_bytes = 0;
	int64_t last_key_us = -1;
	QByteArray parameter_sets_sample; // latest sample carrying SPS/PPS(/VPS), for clips that start without them
};

#endif
