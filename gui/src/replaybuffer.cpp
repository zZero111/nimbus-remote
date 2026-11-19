#include "replaybuffer.h"

ReplayBuffer::ReplayBuffer(StreamRecorder::VideoCodec codec, int64_t window_us, int64_t max_bytes)
	: codec(codec), window_us(window_us), max_bytes(max_bytes)
{
}

void ReplayBuffer::pushVideo(const uint8_t *buf, size_t size, int64_t at_us)
{
	if(!buf || !size)
		return;
	const bool key = StreamRecorder::isKeyframe(buf, size, codec);
	const bool params = StreamRecorder::hasParameterSets(buf, size, codec);
	QMutexLocker locker(&mutex);
	if(params)
		parameter_sets_sample = QByteArray(reinterpret_cast<const char *>(buf), int(size));
	// Until the first keyframe there's nothing a clip could start from
	if(entries.empty() && !key)
		return;
	entries.push_back(Entry{true, key, at_us, QByteArray(reinterpret_cast<const char *>(buf), int(size))});
	total_bytes += int64_t(size);
	if(key)
		last_key_us = at_us;
	trimLocked();
}

void ReplayBuffer::pushAudio(const uint8_t *buf, size_t size, int64_t at_us)
{
	if(!buf || !size)
		return;
	QMutexLocker locker(&mutex);
	if(entries.empty())
		return; // audio only after the first keyframe, so it lines up with the video
	entries.push_back(Entry{false, false, at_us, QByteArray(reinterpret_cast<const char *>(buf), int(size))});
	total_bytes += int64_t(size);
	trimLocked();
}

void ReplayBuffer::trimLocked()
{
	if(entries.empty())
		return;
	const int64_t cutoff = entries.back().at_us - window_us;
	// Drop whole keyframe groups from the front while the next keyframe is still old enough
	// to cover the window (or while over the memory cap)
	for(;;)
	{
		size_t next_key = 0;
		for(size_t i = 1; i < entries.size(); i++)
		{
			if(entries[i].video && entries[i].key)
			{
				next_key = i;
				break;
			}
		}
		if(!next_key)
			break;
		const bool old_enough = entries[next_key].at_us <= cutoff;
		const bool too_big = total_bytes > max_bytes;
		if(!old_enough && !too_big)
			break;
		for(size_t i = 0; i < next_key; i++)
			total_bytes -= entries[i].data.size();
		entries.erase(entries.begin(), entries.begin() + long(next_key));
	}
	// No later keyframe and over the cap: start again from scratch at the next keyframe
	if(total_bytes > max_bytes)
	{
		entries.clear();
		total_bytes = 0;
	}
}

void ReplayBuffer::clear()
{
	QMutexLocker locker(&mutex);
	entries.clear();
	total_bytes = 0;
	last_key_us = -1;
}

int64_t ReplayBuffer::keyframeAgeUs(int64_t now_us) const
{
	QMutexLocker locker(&mutex);
	return last_key_us < 0 ? -1 : now_us - last_key_us;
}

double ReplayBuffer::seconds(int64_t now_us) const
{
	QMutexLocker locker(&mutex);
	return entries.empty() ? 0.0 : double(now_us - entries.front().at_us) / 1e6;
}

int64_t ReplayBuffer::bytes() const
{
	QMutexLocker locker(&mutex);
	return total_bytes;
}

ReplayBuffer::Snapshot ReplayBuffer::snapshot() const
{
	// QByteArray copies are shared, so this is cheap even for a full buffer
	QMutexLocker locker(&mutex);
	Snapshot s;
	s.codec = codec;
	s.entries = entries;
	s.parameter_sets_sample = parameter_sets_sample;
	return s;
}

bool ReplayBuffer::save(const QString &path, int width, int height, int audio_channels, QString *error) const
{
	return write(snapshot(), path, width, height, audio_channels, error);
}

bool ReplayBuffer::write(const Snapshot &snap, const QString &path, int width, int height, int audio_channels, QString *error)
{
	const auto codec = snap.codec;
	const std::deque<Entry> &copy = snap.entries;
	const QByteArray &params = snap.parameter_sets_sample;
	if(copy.empty())
	{
		if(error)
			*error = QStringLiteral("Nothing to save yet");
		return false;
	}
	StreamRecorder writer;
	if(!writer.start(path, codec, width, height, audio_channels, 48000, error, copy.front().at_us))
		return false;
	if(!params.isEmpty())
		writer.notePossibleParameterSets(reinterpret_cast<const uint8_t *>(params.constData()), size_t(params.size()), codec);
	for(const Entry &e : copy)
	{
		const auto *data = reinterpret_cast<const uint8_t *>(e.data.constData());
		if(e.video)
		{
			writer.notePossibleParameterSets(data, size_t(e.data.size()), codec);
			writer.writeVideo(data, size_t(e.data.size()), e.at_us);
		}
		else
			writer.writeAudio(data, size_t(e.data.size()), e.at_us);
	}
	const bool wrote = writer.bytesWritten() > 0;
	writer.stop();
	if(!wrote && error)
		*error = QStringLiteral("No video could be written");
	return wrote;
}
