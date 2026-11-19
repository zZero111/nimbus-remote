#include "netcheck.h"

#include <QCoreApplication>
#include <QStringList>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <cstdlib>
#endif

namespace NetCheck {

#ifdef _WIN32
namespace {

enum class Kind { Lan, Tether, Virtual };

Kind classify(const IP_ADAPTER_ADDRESSES *a)
{
	const QString desc = QString::fromWCharArray(a->Description).toLower();
	const QString name = QString::fromWCharArray(a->FriendlyName).toLower();
	static const QStringList tether = { "remote ndis", "rndis", "tether", "mobile usb", "android usb", "iphone", "apple mobile device" };
	static const QStringList virt = { "vpn", "hamachi", "zerotier", "radmin", "tap-windows", "wintun", "wireguard", "tailscale",
		"openvpn", "virtualbox", "vmware", "hyper-v", "vethernet", "npcap", "loopback", "tunnel" };
	for(const QString &t : tether)
		if(desc.contains(t))
			return Kind::Tether;
	if(a->IfType == IF_TYPE_TUNNEL || a->IfType == IF_TYPE_PPP)
		return Kind::Virtual;
	for(const QString &v : virt)
		if(desc.contains(v) || name.contains(v))
			return Kind::Virtual;
	return Kind::Lan;
}

}

QString localNetworkWarning()
{
	ULONG size = 16 * 1024;
	IP_ADAPTER_ADDRESSES *adapters = nullptr;
	ULONG ret = ERROR_BUFFER_OVERFLOW;
	for(int i = 0; i < 3 && ret == ERROR_BUFFER_OVERFLOW; i++)
	{
		std::free(adapters);
		adapters = static_cast<IP_ADAPTER_ADDRESSES *>(std::malloc(size));
		if(!adapters)
			return {};
		ret = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER, nullptr, adapters, &size);
	}
	if(ret != NO_ERROR)
	{
		std::free(adapters);
		return {};
	}
	bool lan = false, tether = false;
	for(IP_ADAPTER_ADDRESSES *a = adapters; a; a = a->Next)
	{
		if(a->OperStatus != IfOperStatusUp || a->IfType == IF_TYPE_SOFTWARE_LOOPBACK || !a->FirstUnicastAddress)
			continue;
		switch(classify(a))
		{
			case Kind::Lan: lan = true; break;
			case Kind::Tether: tether = true; break;
			case Kind::Virtual: break;
		}
	}
	std::free(adapters);
	if(lan)
		return {};
	if(tether)
		return QCoreApplication::translate("NetCheck",
			"This PC is online through a phone (USB tethering), so it can't see consoles on your home network.\n"
			"Connect the PC to the same router as your PS5 with a cable or Wi-Fi, or use Remote Play over PSN.");
	return QCoreApplication::translate("NetCheck",
		"This PC isn't connected to a local network (only VPN adapters are active).\n"
		"Connect it to the same router as your PS5, or use Remote Play over PSN.");
}
#else
QString localNetworkWarning()
{
	return {};
}
#endif

}
