// Puts Wi-Fi adapters into "media streaming" mode while a stream runs (Windows).
//
// Windows scans for other Wi-Fi networks in the background about once a minute (and whenever
// an app asks for the network list). During a scan the adapter leaves the channel for
// ~100-300 ms, which shows up as a burst of packet loss and dropped frames. Moonlight and Steam
// Link do the same thing: disable background scans and enable streaming mode for the session.
// Both settings belong to the WLAN handle and Windows undoes them when the handle is closed,
// also if the app crashes, so nothing is left changed afterwards.
#ifndef WIFISTREAMING_H
#define WIFISTREAMING_H

class WifiStreamingMode
{
public:
	WifiStreamingMode();
	~WifiStreamingMode();
	WifiStreamingMode(const WifiStreamingMode &) = delete;
	WifiStreamingMode &operator=(const WifiStreamingMode &) = delete;

	/// Number of connected Wi-Fi adapters the settings were applied to.
	int adapters() const { return adapters_; }

private:
	void *handle_ = nullptr;
	int adapters_ = 0;
};

#endif
