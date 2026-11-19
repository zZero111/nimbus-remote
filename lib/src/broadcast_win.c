// SPDX-License-Identifier: LicenseRef-AGPL-3.0-only-OpenSSL
// Per-adapter broadcast for Windows; see chiaki_win_sendto_all_broadcasts in utils.h.

#ifdef _WIN32

// winsock2 must come before iphlpapi, or IP_ADAPTER_ADDRESSES is not declared
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <stdlib.h>

#include "utils.h"

int chiaki_win_sendto_all_broadcasts(ChiakiLog *log, chiaki_socket_t s, const void *msg, size_t len, int flags, const struct sockaddr_in *to)
{
	int r = -1;
	ULONG buf_size = 16 * 1024;
	IP_ADAPTER_ADDRESSES *adapters = NULL;
	ULONG ret = ERROR_BUFFER_OVERFLOW;
	for(int attempt = 0; attempt < 3 && ret == ERROR_BUFFER_OVERFLOW; attempt++)
	{
		free(adapters);
		adapters = (IP_ADAPTER_ADDRESSES *)malloc(buf_size);
		if(!adapters)
			break;
		ret = GetAdaptersAddresses(AF_INET,
			GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
			NULL, adapters, &buf_size);
	}
	if(adapters && ret == NO_ERROR)
	{
		for(IP_ADAPTER_ADDRESSES *a = adapters; a; a = a->Next)
		{
			if(a->OperStatus != IfOperStatusUp || a->IfType == IF_TYPE_SOFTWARE_LOOPBACK)
				continue;
			for(IP_ADAPTER_UNICAST_ADDRESS *u = a->FirstUnicastAddress; u; u = u->Next)
			{
				if(!u->Address.lpSockaddr || u->Address.lpSockaddr->sa_family != AF_INET)
					continue;
				const ULONG prefix = u->OnLinkPrefixLength;
				if(prefix < 1 || prefix > 30)
					continue;
				struct sockaddr_in bcast = *to;
				const uint32_t ip = ntohl(((struct sockaddr_in *)u->Address.lpSockaddr)->sin_addr.s_addr);
				const uint32_t mask = ~(0xffffffffu >> prefix);
				bcast.sin_addr.s_addr = htonl((ip & mask) | ~mask);
				char addr_buf[64];
				const char *addr_str = sockaddr_str((struct sockaddr *)&bcast, addr_buf, sizeof(addr_buf));
				CHIAKI_LOGV(log, "Broadcast to %s on %ls", addr_str ? addr_str : "(null)", a->FriendlyName);
				int sr = sendto(s, (const char *)msg, (int)len, flags, (struct sockaddr *)&bcast, sizeof(bcast));
				if(sr >= 0)
					r = sr;
			}
		}
	}
	else
		CHIAKI_LOGW(log, "GetAdaptersAddresses failed (%lu), broadcasting on the default adapter only", (unsigned long)ret);
	free(adapters);

	// Keep the plain limited broadcast too, exactly as before
	int sr = sendto(s, (const char *)msg, (int)len, flags, (const struct sockaddr *)to, sizeof(*to));
	if(sr >= 0)
		r = sr;
	return r;
}

#endif
