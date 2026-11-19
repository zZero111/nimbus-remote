#include "asyncdecoder.h"

#include <algorithm>

AsyncVideoDecoder::AsyncVideoDecoder(DecodeFn decode, KeyframeRequestFn request_keyframe, KeyframeTestFn is_keyframe, Options options)
	: decode(std::move(decode)),
	request_keyframe(std::move(request_keyframe)),
	is_keyframe(std::move(is_keyframe)),
	opt([&] { Options o = options; o.max_pending = std::max<size_t>(o.max_pending, 1); o.error_burst = std::max(o.error_burst, 1); return o; }())
{
	thread = std::thread(&AsyncVideoDecoder::run, this);
}

AsyncVideoDecoder::~AsyncVideoDecoder()
{
	stop();
}

bool AsyncVideoDecoder::keyframeRequestDueLocked()
{
	const auto now = Clock::now();
	if(last_keyframe_request != Clock::time_point{} && now - last_keyframe_request < opt.keyframe_retry)
		return false;
	last_keyframe_request = now;
	return true;
}

bool AsyncVideoDecoder::beginKeyframeWaitLocked()
{
	for(const Sample &s : queue)
		carried_lost += 1 + s.frames_lost;
	counters.skipped += queue.size();
	queue.clear();
	waiting_for_keyframe = true;
	in_burst = false;
	recent_errors.clear();
	return keyframeRequestDueLocked();
}

void AsyncVideoDecoder::push(const uint8_t *buf, size_t size, int32_t frames_lost, bool recovered)
{
	if(!buf || !size)
		return;
	const bool key = is_keyframe ? is_keyframe(buf, size) : false;
	bool ask_keyframe = false;
	bool queued = false;
	{
		std::lock_guard<std::mutex> lock(mutex);
		if(stopping)
			return;
		if(waiting_for_keyframe && !key)
		{
			// Without its reference frames this sample would only decode as garbage
			counters.skipped++;
			carried_lost += 1 + frames_lost;
			// The request (or the keyframe) may have been lost on the way: ask again now and then
			ask_keyframe = keyframeRequestDueLocked();
		}
		else
		{
			if(key)
			{
				// A keyframe makes everything still queued before it unnecessary
				waiting_for_keyframe = false;
				if(!queue.empty())
				{
					for(const Sample &s : queue)
						carried_lost += 1 + s.frames_lost;
					counters.skipped += queue.size();
					queue.clear();
				}
			}
			else if(queue.size() >= opt.max_pending)
			{
				// Hopelessly behind (the PC can't decode this stream in real time): drop the
				// backlog instead of letting it turn into seconds of input delay
				counters.overflows++;
				counters.skipped++;
				carried_lost += 1 + frames_lost;
				ask_keyframe = beginKeyframeWaitLocked();
			}
			if(!waiting_for_keyframe)
			{
				queue.push_back(Sample{std::vector<uint8_t>(buf, buf + size), frames_lost + carried_lost, recovered});
				carried_lost = 0;
				queued = true;
				counters.max_backlog = std::max(counters.max_backlog, queue.size());
				if(queue.size() >= 3 && !in_burst)
				{
					// Several frames arrived at once (typical on Wi-Fi): decode through them
					in_burst = true;
					counters.bursts++;
				}
			}
		}
	}
	if(ask_keyframe && request_keyframe)
		request_keyframe();
	if(queued)
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
			if(queue.empty())
				in_burst = false;
		}
		const bool ok = decode(sample.data.data(), sample.data.size(), sample.frames_lost, sample.recovered);
		bool ask_keyframe = false;
		{
			std::lock_guard<std::mutex> lock(mutex);
			counters.decoded++;
			if(!ok)
			{
				counters.decode_errors++;
				// One bad frame is usually repaired by the console's next frames; only give up on
				// the reference chain when errors keep coming
				const auto now = Clock::now();
				recent_errors.push_back(now);
				while(!recent_errors.empty() && now - recent_errors.front() > opt.error_window)
					recent_errors.pop_front();
				if(!waiting_for_keyframe && recent_errors.size() >= size_t(opt.error_burst))
				{
					counters.error_recoveries++;
					ask_keyframe = beginKeyframeWaitLocked();
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
