// Asks Windows to treat the app as a real-time game while a stream runs, and undoes it after.
//
//  - 1 ms timer resolution: frame pacing and the network threads wake on time instead of being
//    rounded up to Windows' default ~15.6 ms timer tick.
//  - No power throttling ("efficiency mode"): Windows 11 can slow apps it thinks aren't important,
//    especially on laptops on battery or when another window has focus.
//  - Above-normal process priority: background programs can't delay the stream threads.
// The receive and decode threads also raise their own priority (lib/src/takion.c, asyncdecoder.cpp).
#ifndef PERFMODE_H
#define PERFMODE_H

#include <QString>

class StreamPerformanceMode
{
public:
	StreamPerformanceMode();
	~StreamPerformanceMode();
	StreamPerformanceMode(const StreamPerformanceMode &) = delete;
	StreamPerformanceMode &operator=(const StreamPerformanceMode &) = delete;

	/// What was applied, for diagnostics.
	QString summary() const;

private:
	bool timer_set = false;
	bool throttling_off = false;
	bool priority_raised = false;
	unsigned long previous_priority_class = 0;
};

/// Raises the calling thread's priority for latency-sensitive work (no-op outside Windows).
void RaiseCurrentThreadPriority(bool highest);
/// Makes the stream library raise its receive / input threads as they start (call once at startup).
void InstallStreamThreadPriorities();

#endif
