// Explains why no console can be found when the PC isn't on a normal home network,
// e.g. it is online only through a phone's USB tethering or a VPN.
#ifndef NETCHECK_H
#define NETCHECK_H

#include <QString>

namespace NetCheck {

/// Empty when the PC has an active wired / Wi-Fi network; otherwise a short user-facing
/// explanation. Only implemented on Windows; returns an empty string elsewhere.
QString localNetworkWarning();

}

#endif
