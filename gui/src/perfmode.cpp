#include "perfmode.h"

#include <QLoggingCategory>
#include <QStringList>

Q_LOGGING_CATEGORY(nimbusPerf, "nimbus.perf")

#ifdef _WIN32
#include <windows.h>
#include <timeapi.h>

namespace {
// Declared here so older MinGW headers aren't a problem (values from the Windows SDK)
struct PowerThrottlingState
{
	ULONG Version;
	ULONG ControlMask;
	ULONG StateMask;
};
constexpr ULONG kPowerThrottlingCurrentVersion = 1;
constexpr ULONG kPowerThrottlingExecutionSpeed = 0x1;
constexpr ULONG kPowerThrottlingIgnoreTimerResolution = 0x4;
constexpr int kProcessPowerThrottling = 4; // PROCESS_INFORMATION_CLASS value

bool SetProcessPowerThrottling(ULONG control, ULONG state)
{
	using SetInfo = BOOL (WINAPI *)(HANDLE, int, LPVOID, DWORD);
	static const auto set_info = reinterpret_cast<SetInfo>(reinterpret_cast<void *>(
		GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "SetProcessInformation")));
	if(!set_info)
		return false;
	PowerThrottlingState s { kPowerThrottlingCurrentVersion, control, state };
	return set_info(GetCurrentProcess(), kProcessPowerThrottling, &s, sizeof(s)) != 0;
}
}

StreamPerformanceMode::StreamPerformanceMode()
{
	timer_set = timeBeginPeriod(1) == TIMERR_NOERROR;
	// Control both flags, state 0 = "never throttle me, and honour my timer resolution"
	throttling_off = SetProcessPowerThrottling(kPowerThrottlingExecutionSpeed | kPowerThrottlingIgnoreTimerResolution, 0);
	previous_priority_class = GetPriorityClass(GetCurrentProcess());
	if(previous_priority_class == NORMAL_PRIORITY_CLASS)
		priority_raised = SetPriorityClass(GetCurrentProcess(), ABOVE_NORMAL_PRIORITY_CLASS) != 0;
	qCInfo(nimbusPerf).noquote() << "Streaming performance mode:" << summary();
}

StreamPerformanceMode::~StreamPerformanceMode()
{
	if(priority_raised)
		SetPriorityClass(GetCurrentProcess(), previous_priority_class);
	if(throttling_off)
		SetProcessPowerThrottling(0, 0); // back to letting Windows decide
	if(timer_set)
		timeEndPeriod(1);
}

QString StreamPerformanceMode::summary() const
{
	QStringList parts;
	parts << QStringLiteral("1 ms timers %1").arg(timer_set ? QStringLiteral("on") : QStringLiteral("unavailable"));
	parts << QStringLiteral("power throttling %1").arg(throttling_off ? QStringLiteral("off") : QStringLiteral("unchanged"));
	parts << QStringLiteral("priority %1").arg(priority_raised ? QStringLiteral("above normal") : QStringLiteral("unchanged"));
	return parts.join(QStringLiteral(", "));
}

void RaiseCurrentThreadPriority(bool highest)
{
	SetThreadPriority(GetCurrentThread(), highest ? THREAD_PRIORITY_HIGHEST : THREAD_PRIORITY_ABOVE_NORMAL);
}

#else

StreamPerformanceMode::StreamPerformanceMode() {}
StreamPerformanceMode::~StreamPerformanceMode() {}
QString StreamPerformanceMode::summary() const { return QStringLiteral("not used on this system"); }
void RaiseCurrentThreadPriority(bool) {}

#endif

#include <chiaki/thread.h>

// Called by the library at the start of each of its threads
static void StreamThreadStarted(ChiakiThreadName name, void *)
{
	switch(name)
	{
		case CHIAKI_THREAD_NAME_TAKION:     // receives the video, audio and haptics packets
		case CHIAKI_THREAD_NAME_FEEDBACK:   // sends controller input to the console
			RaiseCurrentThreadPriority(true);
			break;
		case CHIAKI_THREAD_NAME_TAKION_SEND:
		case CHIAKI_THREAD_NAME_CONGESTION:
		case CHIAKI_THREAD_NAME_GKCRYPT:    // prepares the keys that decrypt the incoming stream
		case CHIAKI_THREAD_NAME_CTRL:
			RaiseCurrentThreadPriority(false);
			break;
		default:
			break;
	}
}

void InstallStreamThreadPriorities()
{
	chiaki_thread_set_affinity_cb(StreamThreadStarted, nullptr);
}
