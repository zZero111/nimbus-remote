#include "wifistreaming.h"

#include <QLoggingCategory>

Q_LOGGING_CATEGORY(nimbusWifi, "nimbus.wifi")

#ifdef _WIN32
#include <windows.h>
#include <wlanapi.h>

WifiStreamingMode::WifiStreamingMode()
{
	DWORD negotiated = 0;
	HANDLE h = nullptr;
	if(WlanOpenHandle(2, nullptr, &negotiated, &h) != ERROR_SUCCESS)
		return; // no WLAN service (desktop without Wi-Fi): nothing to do
	handle_ = h;

	PWLAN_INTERFACE_INFO_LIST list = nullptr;
	if(WlanEnumInterfaces(h, nullptr, &list) != ERROR_SUCCESS || !list)
		return;
	for(DWORD i = 0; i < list->dwNumberOfItems; i++)
	{
		const WLAN_INTERFACE_INFO &info = list->InterfaceInfo[i];
		if(info.isState != wlan_interface_state_connected)
			continue;
		BOOL off = FALSE, on = TRUE;
		const DWORD scan = WlanSetInterface(h, &info.InterfaceGuid, wlan_intf_opcode_background_scan_enabled, sizeof(off), &off, nullptr);
		const DWORD stream = WlanSetInterface(h, &info.InterfaceGuid, wlan_intf_opcode_media_streaming_mode, sizeof(on), &on, nullptr);
		if(scan == ERROR_SUCCESS || stream == ERROR_SUCCESS)
			adapters_++;
		qCInfo(nimbusWifi).nospace() << "Wi-Fi streaming mode on "
			<< QString::fromWCharArray(info.strInterfaceDescription)
			<< ": background scan off=" << (scan == ERROR_SUCCESS)
			<< " streaming mode=" << (stream == ERROR_SUCCESS);
	}
	WlanFreeMemory(list);
}

WifiStreamingMode::~WifiStreamingMode()
{
	// Closing the handle restores background scanning and normal mode
	if(handle_)
		WlanCloseHandle(static_cast<HANDLE>(handle_), nullptr);
}

#else

WifiStreamingMode::WifiStreamingMode() {}
WifiStreamingMode::~WifiStreamingMode() {}

#endif
