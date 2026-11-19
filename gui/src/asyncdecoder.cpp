#include "asyncdecoder.h"

AsyncVideoDecoder::AsyncVideoDecoder(DecodeFn decode, KeyframeRequestFn request_keyframe, KeyframeTestFn is_keyframe, size_t max_pending)
	: decode(std::move(decode)),
	request_keyframe(std::move(request_keyframe)),
	is_keyframe(std::move(is_keyframe)),
	max_pending(max_pending ? max_pending : 1)
{
	thread = std::thread(&AsyncVideoDecoder::run, this);
}

AsyncVideoDecoder::~AsyncVideoDecoder()
{
	stop();
}

void AsyncVideoDecoder::push(const uint8_t *buf, size_t size, int32_t frames_lost, bool recovered)
{
	if(!buf || !size)
		return;
	const bool key = is_keyframe ? is_keyframe(buf, size) : false;
	bool ask_keyframe = false;
	{
		std::lock_guard<std::mutex> lock(mutex);
		if(stopping)
			return;
		if(waiting_for_keyframe)
		{
			if(!key)
			{
				// Without its reference frames this sample would only decode as garbage
				counters.skipped++;
				carried_lost += 1 + frames_lost;
				return;
			}
			waiting_for_keyframe = false;
		}
		else if(queue.size() >= max_pending && !key)
		{
			// The decoder is too far behind: drop the backlog instead of letting it turn into
			// input delay, and resume cleanly from the next keyframe
			counters.overflows++;
			for(const Sample &s : queue)
				carried_lost += 1 + s.frames_lost;
			counters.skipped += queue.size() + 1;
			carried_lost += 1 + frames_lost;
			queue.clear();
			waiting_for_keyframe = true;
			ask_keyframe = true;
		}
		if(!ask_keyframe)
		{
			if(key && queue.size() >= max_pending)
			{
				// A keyframe makes everything queued before it unnecessary
				for(const Sample &s : queue)
					carried_lost += 1 + s.frames_lost;
				counters.skipped += queue.size();
				queue.clear();
			}
			queue.push_back(Sample{std::vector<uint8_t>(buf, buf + size), frames_lost + carried_lost, recovered});
			carried_lost = 0;
		}
	}
	if(ask_keyframe)
	{
		if(request_keyframe)
			request_keyframe();
	}
	else
		cond.notify_one();
}

void AsyncVideoDecoder::run()
{
	for(;;)
	{
		Sample sample;
		{
			std::unique_lock<std::mutex> lock(mutex);
			cond.wait(lock, [this] { return stopping || !queue.empty(); });
			if(stopping)
				return;
			sample = std::move(queue.front());
			queue.pop_front();
		}
		const bool ok = decode(sample.data.data(), sample.data.size(), sample.frames_lost, sample.recovered);
		bool ask_keyframe = false;
		{
			std::lock_guard<std::mutex> lock(mutex);
			counters.decoded++;
			if(!ok)
			{
				counters.decode_errors++;
				// Later frames depend on this one; skip them until a fresh keyframe arrives
				if(!waiting_for_keyframe)
				{
					for(const Sample &s : queue)
						carried_lost += 1 + s.frames_lost;
					counters.skipped += queue.size();
					queue.clear();
					waiting_for_keyframe = true;
					ask_keyframe = true;
				}
			}
		}
		if(ask_keyframe && request_keyframe)
			request_keyframe();
	}
}

void AsyncVideoDecoder::stop()
{
	{
		std::lock_guard<std::mutex> lock(mutex);
		if(stopping && !thread.joinable())
			return;
		stopping = true;
		queue.clear();
	}
	cond.notify_all();
	if(thread.joinable() && thread.get_id() != std::this_thread::get_id())
		thread.join();
}

AsyncVideoDecoder::Stats AsyncVideoDecoder::stats() const
{
	std::lock_guard<std::mutex> lock(mutex);
	return counters;
}
