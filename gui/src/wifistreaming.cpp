#include "wifistreaming.h"

#include <QLoggingCategory>
#include <QStringList>

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

QString WifiStreamingMode::linkSummary()
{
	DWORD negotiated = 0;
	HANDLE h = nullptr;
	if(WlanOpenHandle(2, nullptr, &negotiated, &h) != ERROR_SUCCESS)
		return QStringLiteral("no Wi-Fi adapter");
	QStringList links;
	PWLAN_INTERFACE_INFO_LIST list = nullptr;
	if(WlanEnumInterfaces(h, nullptr, &list) == ERROR_SUCCESS && list)
	{
		for(DWORD i = 0; i < list->dwNumberOfItems; i++)
		{
			const WLAN_INTERFACE_INFO &info = list->InterfaceInfo[i];
			if(info.isState != wlan_interface_state_connected)
				continue;
			QString line = QString::fromWCharArray(info.strInterfaceDescription);
			DWORD size = 0;
			PWLAN_CONNECTION_ATTRIBUTES conn = nullptr;
			if(WlanQueryInterface(h, &info.InterfaceGuid, wlan_intf_opcode_current_connection, nullptr, &size,
					reinterpret_cast<PVOID *>(&conn), nullptr) == ERROR_SUCCESS && conn)
			{
				const auto &a = conn->wlanAssociationAttributes;
				QString phy;
				switch(a.dot11PhyType)
				{
					case dot11_phy_type_ht: phy = QStringLiteral("Wi-Fi 4"); break;
					case dot11_phy_type_vht: phy = QStringLiteral("Wi-Fi 5"); break;
					case 10: phy = QStringLiteral("Wi-Fi 6"); break; // dot11_phy_type_he
					case 11: phy = QStringLiteral("Wi-Fi 7"); break; // dot11_phy_type_eht
					default: phy = QStringLiteral("802.11 type %1").arg(static_cast<int>(a.dot11PhyType)); break;
				}
				line += QStringLiteral(", %1, signal %2%, link %3/%4 Mbps (rx/tx)")
					.arg(phy).arg(a.wlanSignalQuality).arg(a.ulRxRate / 1000).arg(a.ulTxRate / 1000);
				WlanFreeMemory(conn);
			}
			ULONG *channel = nullptr;
			size = 0;
			if(WlanQueryInterface(h, &info.InterfaceGuid, wlan_intf_opcode_channel_number, nullptr, &size,
					reinterpret_cast<PVOID *>(&channel), nullptr) == ERROR_SUCCESS && channel)
			{
				const ULONG ch = *channel;
				const QString band = ch <= 14 ? QStringLiteral("2.4 GHz") : (ch <= 177 ? QStringLiteral("5 GHz") : QStringLiteral("6 GHz"));
				line += QStringLiteral(", channel %1 (%2)").arg(ch).arg(band);
				WlanFreeMemory(channel);
			}
			links << line;
		}
		WlanFreeMemory(list);
	}
	WlanCloseHandle(h, nullptr);
	return links.isEmpty() ? QStringLiteral("not connected") : links.join(QStringLiteral("; "));
}

#else

WifiStreamingMode::WifiStreamingMode() {}
WifiStreamingMode::~WifiStreamingMode() {}
QString WifiStreamingMode::linkSummary() { return QStringLiteral("not available on this system"); }

#endif
