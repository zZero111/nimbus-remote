// Tests AsyncVideoDecoder with a fake decoder. Build + run: bash nimbus/test-asyncdecoder.sh
// Sample format: byte 0 = 'K' (keyframe) or 'P', bytes 1..4 = sequence number.
#include "asyncdecoder.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>
#include <vector>

using namespace std::chrono;

static int failures = 0;
static void check(bool ok, const char *what)
{
	std::printf("%-62s %s\n", what, ok ? "OK" : "FAIL");
	if(!ok)
		failures++;
}

static std::vector<uint8_t> sample(char type, uint32_t seq)
{
	std::vector<uint8_t> s(64, 0);
	s[0] = uint8_t(type);
	std::memcpy(&s[1], &seq, 4);
	return s;
}

struct Recorder
{
	std::mutex m;
	std::vector<uint32_t> seqs;
	std::vector<char> types;
	int64_t accounted = 0; // sum of (1 + frames_lost) over decoded samples
};

static bool isKey(const uint8_t *buf, size_t) { return buf[0] == 'K'; }

static uint32_t seqOf(const uint8_t *buf) { uint32_t v; std::memcpy(&v, buf + 1, 4); return v; }

int main()
{
	// 1. Fast decoder: everything decoded, in order, nothing skipped
	{
		Recorder r;
		std::atomic<int> requests{0};
		{
			AsyncVideoDecoder d(
				[&](const uint8_t *b, size_t, int32_t lost, bool) {
					std::lock_guard<std::mutex> l(r.m);
					r.seqs.push_back(seqOf(b));
					r.accounted += 1 + lost;
					return true;
				},
				[&] { requests++; }, isKey);
			for(uint32_t i = 0; i < 200; i++)
			{
				auto s = sample(i % 60 == 0 ? 'K' : 'P', i);
				d.push(s.data(), s.size(), 0, false);
				std::this_thread::sleep_for(microseconds(300));
			}
			std::this_thread::sleep_for(milliseconds(50));
			auto st = d.stats();
			check(st.decoded == 200 && st.skipped == 0 && st.overflows == 0, "fast decoder: all 200 decoded, none skipped");
		}
		bool ordered = true;
		for(size_t i = 0; i < r.seqs.size(); i++)
			if(r.seqs[i] != i) ordered = false;
		check(ordered && r.seqs.size() == 200, "fast decoder: decoded in order");
		check(requests == 0, "fast decoder: no keyframe requests");
	}

	// 1b. Wi-Fi burst: 8 frames arrive at once after a stall. They are all decoded (no skipping,
	// no keyframe request), because each later frame needs the earlier ones
	{
		Recorder r;
		std::atomic<int> requests{0};
		AsyncVideoDecoder::Stats st;
		{
			AsyncVideoDecoder::Options o;
			o.max_pending = 30;
			AsyncVideoDecoder d(
				[&](const uint8_t *b, size_t, int32_t lost, bool) {
					std::this_thread::sleep_for(milliseconds(3)); // hardware decode time
					std::lock_guard<std::mutex> l(r.m);
					r.seqs.push_back(seqOf(b));
					r.accounted += 1 + lost;
					return true;
				},
				[&] { requests++; }, isKey, o);
			uint32_t seq = 0;
			for(int round = 0; round < 5; round++)
			{
				for(int i = 0; i < 8; i++, seq++)
				{
					auto s = sample(seq == 0 ? 'K' : 'P', seq);
					d.push(s.data(), s.size(), 0, false);
				}
				std::this_thread::sleep_for(milliseconds(120)); // stall, then the next burst
			}
			st = d.stats();
		}
		check(st.decoded == 40 && st.skipped == 0, "wi-fi bursts: all 40 frames decoded, none skipped");
		check(requests == 0 && st.overflows == 0, "wi-fi bursts: no keyframe request, no overflow");
		check(st.bursts >= 5 && st.max_backlog >= 3, "wi-fi bursts: bursts detected and absorbed");
	}

	// 1c. A single decode error does not throw away the following frames
	{
		Recorder r;
		std::atomic<int> requests{0};
		{
			AsyncVideoDecoder d(
				[&](const uint8_t *b, size_t, int32_t, bool) {
					std::lock_guard<std::mutex> l(r.m);
					r.seqs.push_back(seqOf(b));
					return seqOf(b) != 5;
				},
				[&] { requests++; }, isKey);
			for(uint32_t i = 0; i < 20; i++)
			{
				auto s = sample(i == 0 ? 'K' : 'P', i);
				d.push(s.data(), s.size(), 0, false);
				std::this_thread::sleep_for(milliseconds(5));
			}
			std::this_thread::sleep_for(milliseconds(50));
		}
		check(requests == 0 && r.seqs.size() == 20, "isolated decode error: keeps decoding, no keyframe request");
	}

	// 2. Slow decoder: network thread never blocks, backlog is dropped, recovery at keyframe
	{
		Recorder r;
		std::atomic<int> requests{0};
		double worst_push_ms = 0;
		const uint32_t total = 300;
		AsyncVideoDecoder::Stats st;
		{
			AsyncVideoDecoder d(
				[&](const uint8_t *b, size_t, int32_t lost, bool) {
					std::this_thread::sleep_for(milliseconds(25)); // decoder much slower than 60 fps
					std::lock_guard<std::mutex> l(r.m);
					r.seqs.push_back(seqOf(b));
					r.types.push_back(char(b[0]));
					r.accounted += 1 + lost;
					return true;
				},
				[&] { requests++; }, isKey, [] { AsyncVideoDecoder::Options o; o.max_pending = 4; o.keyframe_retry = milliseconds(0); return o; }());
			for(uint32_t i = 0; i < total; i++)
			{
				// keyframe every 30 samples, plus the final sample so everything is accounted for
				auto s = sample((i % 30 == 0 || i == total - 1) ? 'K' : 'P', i);
				auto t0 = steady_clock::now();
				d.push(s.data(), s.size(), 0, false);
				worst_push_ms = std::max(worst_push_ms, duration<double, std::milli>(steady_clock::now() - t0).count());
				std::this_thread::sleep_for(microseconds(16000 / 8)); // arrivals 8x faster than real time
			}
			std::this_thread::sleep_for(milliseconds(400));
			st = d.stats();
		}
		std::printf("   slow decoder: decoded %llu, skipped %llu, overflows %llu, keyframe requests %d, worst push %.3f ms\n",
			(unsigned long long)st.decoded, (unsigned long long)st.skipped, (unsigned long long)st.overflows, requests.load(), worst_push_ms);
		check(worst_push_ms < 5.0, "slow decoder: push never blocks the network thread (<5 ms)");
		check(st.overflows > 0 && requests > 0, "slow decoder: overflow detected and keyframe requested");
		// After every gap in sequence numbers, decoding must resume on a keyframe
		bool resumes_on_key = true;
		for(size_t i = 1; i < r.seqs.size(); i++)
			if(r.seqs[i] != r.seqs[i - 1] + 1 && r.types[i] != 'K')
				resumes_on_key = false;
		check(resumes_on_key, "slow decoder: after skipping, decoding resumes on a keyframe");
		bool increasing = true;
		for(size_t i = 1; i < r.seqs.size(); i++)
			if(r.seqs[i] <= r.seqs[i - 1]) increasing = false;
		check(increasing, "slow decoder: never decodes out of order");
		check(r.accounted == int64_t(total), "slow decoder: every skipped frame is reported as lost");
		check(st.decoded + st.skipped == total, "slow decoder: decoded + skipped == pushed");
	}

	// 3. Repeated decode errors: later frames are skipped until the next keyframe
	{
		Recorder r;
		std::atomic<int> requests{0};
		{
			AsyncVideoDecoder d(
				[&](const uint8_t *b, size_t, int32_t lost, bool) {
					std::lock_guard<std::mutex> l(r.m);
					r.seqs.push_back(seqOf(b));
					r.types.push_back(char(b[0]));
					r.accounted += 1 + lost;
					return seqOf(b) < 3 || seqOf(b) > 5; // samples 3, 4 and 5 fail to decode
				},
				[&] { requests++; }, isKey);
			for(uint32_t i = 0; i < 20; i++)
			{
				auto s = sample(i == 0 || i == 12 ? 'K' : 'P', i);
				d.push(s.data(), s.size(), 0, false);
				std::this_thread::sleep_for(milliseconds(5));
			}
			std::this_thread::sleep_for(milliseconds(50));
		}
		bool skipped_6_to_11 = true;
		for(uint32_t s : r.seqs)
			if(s >= 6 && s <= 11) skipped_6_to_11 = false;
		check(requests == 1, "repeated decode errors: one keyframe request (rate-limited)");
		check(skipped_6_to_11, "repeated decode errors: frames 6-11 skipped until keyframe 12");
		check(!r.seqs.empty() && r.seqs.back() == 19, "repeated decode errors: decoding resumes after the keyframe");
	}

	// 4. stop() with a backlog returns promptly and stops decoding
	{
		std::atomic<int> decoded{0};
		auto t0 = steady_clock::now();
		{
			AsyncVideoDecoder d(
				[&](const uint8_t *, size_t, int32_t, bool) { std::this_thread::sleep_for(milliseconds(20)); decoded++; return true; },
				[] {}, isKey, [] { AsyncVideoDecoder::Options o; o.max_pending = 100; return o; }());
			for(uint32_t i = 0; i < 50; i++)
			{
				auto s = sample('P', i);
				d.push(s.data(), s.size(), 0, false);
			}
			d.stop();
			d.stop(); // twice is fine
		}
		double ms = duration<double, std::milli>(steady_clock::now() - t0).count();
		check(ms < 100.0 && decoded <= 2, "stop(): returns promptly and discards the backlog");
	}

	std::printf("%s (%d failure%s)\n", failures ? "FAILED" : "PASSED", failures, failures == 1 ? "" : "s");
	return failures ? 1 : 0;
}
