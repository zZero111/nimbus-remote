// Runs video decoding on its own thread so the network receive thread never waits on the decoder.
//
// Previously the network thread called the decoder directly. While a big frame (fast motion,
// explosions) was being decoded nothing read the socket, so packets were lost or piled up as
// input delay. Now the network thread only copies the sample into a short queue.
#ifndef ASYNCDECODER_H
#define ASYNCDECODER_H

#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

class AsyncVideoDecoder
{
public:
	/// Decodes one Annex B access unit; returns false on a decode error.
	using DecodeFn = std::function<bool(const uint8_t *buf, size_t size, int32_t frames_lost, bool recovered)>;
	/// Asks the console for a new keyframe (called from the decoder or network thread).
	using KeyframeRequestFn = std::function<void()>;
	/// True if the sample is a keyframe (IDR/IRAP) or carries parameter sets.
	using KeyframeTestFn = std::function<bool(const uint8_t *buf, size_t size)>;

	/// `max_pending`: how many samples may wait before the decoder is considered too far behind.
	AsyncVideoDecoder(DecodeFn decode, KeyframeRequestFn request_keyframe, KeyframeTestFn is_keyframe, size_t max_pending = 4);
	~AsyncVideoDecoder();

	AsyncVideoDecoder(const AsyncVideoDecoder &) = delete;
	AsyncVideoDecoder &operator=(const AsyncVideoDecoder &) = delete;

	/// Called from the network thread. Copies the sample and returns immediately.
	void push(const uint8_t *buf, size_t size, int32_t frames_lost, bool recovered);
	/// Stops the thread and discards anything still queued. Safe to call more than once.
	void stop();

	struct Stats
	{
		uint64_t decoded = 0;        // samples handed to the decoder
		uint64_t skipped = 0;        // samples dropped because the decoder fell too far behind
		uint64_t overflows = 0;      // times the queue overflowed and a keyframe was requested
		uint64_t decode_errors = 0;  // samples the decoder rejected
	};
	Stats stats() const;

private:
	struct Sample
	{
		std::vector<uint8_t> data;
		int32_t frames_lost;
		bool recovered;
	};

	void run();

	DecodeFn decode;
	KeyframeRequestFn request_keyframe;
	KeyframeTestFn is_keyframe;
	const size_t max_pending;

	mutable std::mutex mutex;
	std::condition_variable cond;
	std::deque<Sample> queue;
	bool stopping = false;
	bool waiting_for_keyframe = false;
	int32_t carried_lost = 0; // frames skipped, reported to the decoder with the next sample
	Stats counters;
	std::thread thread;
};

#endif
