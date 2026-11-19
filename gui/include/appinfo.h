// Product identity for this fork. Changing APP_SETTINGS_* moves where settings are stored,
// which keeps this app's config separate from a stock chiaki-ng install on the same machine.
#ifndef APPINFO_H
#define APPINFO_H

#define APP_DISPLAY_NAME "Nimbus Remote"
#define APP_SETTINGS_ORG "NimbusRemote"
#define APP_SETTINGS_APP "NimbusRemote"

// Release this build belongs to; nimbus/release.ps1 bumps it. The updater compares it with
// the latest GitHub release of APP_UPDATE_REPO.
#define APP_RELEASE_TAG "v1.10.1-nimbus.10"
#define APP_UPDATE_REPO "zZero111/nimbus-remote"
// Release asset to download: the first whose name starts with this and ends in .zip
#define APP_UPDATE_ASSET_PREFIX "NimbusRemote-win64-"

#endif
