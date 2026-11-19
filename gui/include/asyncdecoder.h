// Runs video decoding on its own thread so the network receive thread never waits on the decoder.
//
// Previously the network thread called the decoder directly. While a big frame (fast motion,
// explosions) was being decoded nothing read the socket, so packets were lost or piled up as
// input delay. Now the network thread only copies the sample into a queue.
//
// Recovery is deliberately gentle. Wi-Fi often holds packets back for a moment and then
// delivers several frames at once, and a single damaged frame is normally repaired by the
// console itself (the receiver reports it and the console re-references a good frame).
// Throwing frames away and waiting for a keyframe turns those small hiccups into visible
// stalls, so the decoder:
//  - catches up on short bursts by decoding the backlog (the renderer shows the newest frame);
//  - only drops the backlog and waits for a keyframe when it is hopelessly behind
//    (more than `max_pending` samples), or when decode errors keep coming.
#ifndef ASYNCDECODER_H
#define ASYNCDECODER_H

#include <chrono>
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

	struct Options
	{
		/// Backlog above which the decoder is considered hopelessly behind (~0.5 s at 60 fps).
		size_t max_pending = 30;
		/// This many decode errors within `error_window` trigger keyframe recovery.
		int error_burst = 3;
		std::chrono::milliseconds error_window{1000};
		/// Keyframe requests are not repeated more often than this.
		std::chrono::milliseconds keyframe_retry{500};
	};

	AsyncVideoDecoder(DecodeFn decode, KeyframeRequestFn request_keyframe, KeyframeTestFn is_keyframe, Options options);
	AsyncVideoDecoder(DecodeFn decode, KeyframeRequestFn request_keyframe, KeyframeTestFn is_keyframe)
		: AsyncVideoDecoder(std::move(decode), std::move(request_keyframe), std::move(is_keyframe), Options()) {}
	~AsyncVideoDecoder();

	AsyncVideoDecoder(const AsyncVideoDecoder &) = delete;
	AsyncVideoDecoder &operator=(const AsyncVideoDecoder &) = delete;

	/// Called from the network thread. Copies the sample and returns immediately.
	void push(const uint8_t *buf, size_t size, int32_t frames_lost, bool recovered);
	/// Stops the thread and discards anything still queued. Safe to call more than once.
	void stop();

	struct Stats
	{
		uint64_t decoded = 0;         // samples handed to the decoder
		uint64_t skipped = 0;         // samples dropped (hopelessly behind, or broken until a keyframe)
		uint64_t overflows = 0;       // times the backlog passed max_pending
		uint64_t decode_errors = 0;   // samples the decoder rejected
		uint64_t error_recoveries = 0;// times repeated errors made us wait for a keyframe
		uint64_t bursts = 0;          // times a backlog built up and was decoded through
		size_t max_backlog = 0;       // deepest backlog seen
	};
	Stats stats() const;

private:
	using Clock = std::chrono::steady_clock;
	struct Sample
	{
		std::vector<uint8_t> data;
		int32_t frames_lost;
		bool recovered;
	};

	void run();
	/// Drops the queue and waits for a keyframe; returns true if a request should be sent now.
	bool beginKeyframeWaitLocked();
	bool keyframeRequestDueLocked();

	DecodeFn decode;
	KeyframeRequestFn request_keyframe;
	KeyframeTestFn is_keyframe;
	const Options opt;

	mutable std::mutex mutex;
	std::condition_variable cond;
	std::deque<Sample> queue;
	bool stopping = false;
	bool waiting_for_keyframe = false;
	bool in_burst = false;
	int32_t carried_lost = 0; // frames skipped, reported to the decoder with the next sample
	std::deque<Clock::time_point> recent_errors;
	Clock::time_point last_keyframe_request{};
	Stats counters;
	std::thread thread;
};

#endif
