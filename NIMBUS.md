# Nimbus Remote

A PS5/PS4 Remote Play client for Windows, built on [chiaki-ng](https://github.com/streetpea/chiaki-ng) (GPL v3).
"Nimbus Remote" is a working name. Change it in `gui/include/appinfo.h`.

## Download

Get the latest `NimbusRemote-win64-*.zip` from this repository's **Releases** page, unzip it anywhere and run `chiaki.exe`.
No install is needed. Each PC keeps its own settings and console registration.

**Mac (Apple Silicon, M1 or later, macOS 15 or newer):** get `NimbusRemote-macos-arm64-*.dmg`, open it and drag **Nimbus Remote** into Applications. The app isn't signed by a registered Apple developer, so the first time, right-click it and choose **Open**. If macOS still refuses, go to System Settings > Privacy & Security and click **Open Anyway**. Allow **Local Network** access when asked, otherwise it can't find the console. Macs don't update themselves yet: the home screen says when a new version is out and **Download** opens it.

**Linux / Steam Deck:** get `NimbusRemote-linux-x86_64-*.AppImage`, make it executable (`chmod +x`, or Properties > Allow executing) and run it. On a Steam Deck, do this in Desktop Mode, then add it to Steam as a non-Steam game to use it in Game Mode.

**Android:** get `NimbusRemote-android-*.apk` on the phone and open it (allow installing from your browser or file manager when asked). The Android app is chiaki's Android app with our name: it plays **on your home Wi-Fi only** (no PSN internet play) and doesn't have the PS5-style screens or the extra features of the PC app. Registering needs your PSN Account ID, which the PC app shows under Settings > PSN & Internet.

**Updates are automatic on Windows** from `nimbus.5` on. Mac and Linux show a notice with a Download button. On launch the app checks for a newer release and downloads it in the background. Then either click **Restart & update** on the home screen, or just close the app and it installs on exit. It never updates during a stream. If an update fails, the details are in `%TEMP%\NimbusRemoteUpdate\install.log`. Set the environment variable `NIMBUS_NO_UPDATE=1` to turn updates off.

## Publishing a release

```powershell
powershell -ExecutionPolicy Bypass -File nimbus\release.ps1 -Number 6 -Notes "What changed"
```

This stamps the version into `gui/include/appinfo.h`, builds, packages, zips, commits, pushes and creates the GitHub release that installed copies update to.
Publishing the release starts `.github/workflows/nimbus-macos.yml`, which builds the Apple Silicon Mac version on GitHub's Macs (about 30 minutes) and attaches the `.dmg` to the same release. The workflow can also be run by hand from the Actions tab.
The same release also starts `nimbus-linux.yml` (AppImage, about 30-60 minutes) and `nimbus-android.yml` (APK).

**Android signing:** Android only installs an update over an older version signed with the same key. The key lives in `..\android-signing` (outside the repository; back that folder up). Run `powershell -ExecutionPolicy Bypass -File nimbus\set-android-signing-secrets.ps1` once to give it to GitHub as secrets. Until then each APK is signed with a throwaway key and the next version only installs after uninstalling the old one.

## What's different from chiaki-ng

| Feature | Where |
|---|---|
| **Stream presets** (Performance / Balanced / Quality) on the home screen: one click sets resolution, fps, bitrate and codec for home and away play | `gui/src/qml/StreamPresetBar.qml`, `gui/src/qml/presets.js` |
| **Per-console presets**: each registered console remembers its own preset and applies it on connect | `gui/src/qml/MainView.qml` (chip on each card) |
| **Console cards**: status pill (On / Rest mode / Internet / Not found), what's playing, and a main action (Play / Wake & Play / Register) | `gui/src/qml/MainView.qml` |
| **Empty state** that explains what to do when no console is found | `gui/src/qml/MainView.qml` |
| **Live ping** in the stream stats overlay, colour-coded | `lib/src/streamconnection.c`, `gui/src/streamsession.cpp`, `gui/src/qml/StreamView.qml` |
| **Screenshots**: F12 or the stream menu saves the current frame as PNG to `Pictures\Nimbus Remote`; HDR frames are tone-mapped | `gui/src/screenshot.cpp`, `gui/src/qmlmainwindow.cpp` |
| **Post-session advice**: after a session with high packet loss or ping, the home screen suggests a lighter preset | `gui/src/qml/Main.qml` |
| **Stream recording**: F9 or the stream menu records to `Videos\Nimbus Remote\*.ts`. It copies the console's H.264/H.265 and Opus without re-encoding, so it uses almost no CPU and loses no quality. A recording started mid-stream begins at the next keyframe, with the stream's SPS/PPS added so it plays. | `gui/src/recorder.cpp`, `gui/src/streamsession.cpp` |
| **Controller indicator** on the home screen (DualSense / Edge / other pads, or "keyboard + mouse") | `gui/src/qml/MainView.qml`, `gui/src/qmlcontroller.cpp` |
| **Last console preselected** when the app opens | `gui/src/qml/MainView.qml` |
| **Stream menu additions**: Stats overlay toggle, Snap (screenshot), Rec (recording) | `gui/src/qml/StreamView.qml` |
| **Discovery and registration work with VPNs installed**: Windows sends `255.255.255.255` out of the highest-priority adapter only, often a VPN (Radmin, Hamachi, ZeroTier). Broadcasts now also go to each active adapter's own subnet. | `lib/src/broadcast_win.c`, `lib/src/utils.h` |
| **Register over the internet**: PS5s on your PSN account are listed even before they're registered, and can be registered automatically over PSN. chiaki-ng hid them until they had been registered on the home network. | `gui/src/qmlbackend.cpp` (`updatePsnHosts`, `displayServerAt`, `autoRegister`, `finishAutoRegister`) |
| **Decoding on its own thread**: the network thread only queues video; a dedicated thread decodes, so heavy frames no longer stall the network. Recovery is gentle: Wi-Fi bursts of several frames are decoded through instead of dropped, a single bad frame doesn't throw away the frames after it, and only a PC that is hopelessly behind (~0.5 s) or keeps failing skips to a fresh keyframe. | `gui/src/asyncdecoder.cpp`, `gui/src/streamsession.cpp` |
| **Wi-Fi streaming mode**: while streaming, Windows' background Wi-Fi scans (a stutter about once a minute) are paused and the adapter is put in media streaming mode, like Moonlight does. Windows undoes it when the stream ends. | `gui/src/wifistreaming.cpp` |
| **PS5-style home screen**: a row of console tiles (left/right to move, the selected one grows), the console's name large underneath with a white Play button, a per-console quality selector, a clock, and controller button hints along the bottom. The whole screen scales with the window so it fills a large monitor. | `gui/src/qml/MainView.qml`, `gui/src/qml/StreamPresetBar.qml` |
| **Instant replay**: turn on "Replay" in the stream menu and the last ~30 s are kept in memory; F10 or "Save" writes them to `Videos\Nimbus Remote\Clip_*.ts` without re-encoding. While on, the app asks the console for a keyframe if none came for 20 s (clips must start on one), so it's off by default | `gui/src/replaybuffer.cpp`, `gui/src/streamsession.cpp`, `gui/src/qml/StreamMenuContent.qml` |
| **Lighter quality mid-stream**: after about 20 s of heavy packet loss or dropped frames the stream offers to reconnect one preset lighter (and remembers it for that console); the stream menu has the same "Switch to ..." card any time | `gui/src/qml/Main.qml`, `gui/src/qml/StreamView.qml` |
| **PSN sign-in encrypted**: PSN tokens are stored encrypted for your Windows user (DPAPI) instead of as plain text; older plain-text values are converted on start. Copying settings to another PC means signing in to PSN again there | `gui/src/settings.cpp` |
| **Motion: Smooth / Lowest latency** on the home screen. Smooth paces frames by their timestamps with vsync so Wi-Fi jitter doesn't show as hitches (about one frame of extra delay); Lowest latency shows each frame as soon as it's decoded. Switching restarts the app | `gui/src/qml/MainView.qml` |
| **Test connection**: streams for 12 s at the Quality preset, measures ping, packet loss, bitrate and dropped frames, ends without putting the console to sleep, and recommends Performance / Balanced / Quality for that console (one click to use it). Your settings are put back afterwards | `gui/src/qml/Main.qml`, `gui/src/qml/StreamView.qml` |
| **Copy diagnostics** (copy icon, top right): puts a short report on the clipboard: version, GPU and driver, key settings, network and Wi-Fi link (band, signal, link speed), and the last session's numbers including the decode thread. No IP addresses, console IDs or account data | `gui/src/qmlbackend.cpp`, `gui/src/wifistreaming.cpp`, `gui/src/streamsession.cpp` |
| **PS5-style in-game menu** (Ctrl+O or the controller combo): a control-center panel with large cards (Disconnect, Volume, Mic, Stats, Screenshot, Record, Picture quality, Zoom, Stretch, Display). Switched-on features are blue, the selected card has a white ring, and the connection (bitrate, ping, packet loss) is shown along the top | `gui/src/qml/StreamMenuContent.qml` |
| **PS5-style settings**: categories in a list down the left with a short description of each, settings in a panel on the right; L1/R1 switch category | `gui/src/qml/SettingsDialog.qml`, `gui/src/qml/DialogView.qml` |
| **Sized for big monitors**: on a 1440p or 4K screen left at 100% Windows scaling the whole interface is scaled up (up to 1.5x) so it isn't tiny. `NIMBUS_UI_SCALE=1.0` turns it off | `gui/src/main.cpp` |
| **Clearer stream overlay**: stats panel leads with a connection rating (Excellent / Good / Fair / Poor) and shows ping; the flashing Wi-Fi icon is replaced by a small "Unstable connection · x% packet loss" notice | `gui/src/qmlmainwindow.cpp`, `gui/src/qml/StreamView.qml` |
| **Stream socket receive buffer of 512 KB** (was 100 KB), so keyframe bursts aren't dropped on Wi-Fi | `lib/src/takion.c` |
| **Intel laptops tune themselves**: with the decoder on Auto, Intel integrated graphics use `d3d11va`, and the first stream switches High Quality render presets to Default | `gui/src/qmlbackend.cpp`, `gui/src/qmlmainwindow.cpp` |
| **Self-update** from GitHub releases: background download, "Restart & update" button or install on exit | `gui/src/updater.cpp`, `gui/src/qml/MainView.qml` |
| **Mac builds** for Apple Silicon (Intel Macs not yet), built on GitHub for every release, with a "new version available" notice | `.github/workflows/nimbus-macos.yml`, `gui/src/updater.cpp` |
| **Network hint**: when the PC is online only through phone USB tethering or VPNs, the home screen explains why no console can be found | `gui/src/netcheck.cpp`, `gui/src/qml/MainView.qml` |
| **Own logo** on the home screen (Settings > About still credits chiaki-ng) | `gui/res/nimbus-logo-white.svg` |
| **Own settings store**: on first launch it copies an existing chiaki-ng setup (consoles, PSN login, mappings, profiles) and never changes the original | `gui/src/main.cpp` |

Everything else (registration, PSN remote play, wake, controller mapping, DualSense haptics, libplacebo rendering) comes from chiaki-ng.

## Shortcuts while streaming

| Key | Action |
|---|---|
| F12 | Screenshot |
| F9 | Start / stop recording |
| F10 | Save the last ~30 s (instant replay must be on) |
| F11 | Fullscreen |
| Ctrl+O | Stream menu |
| Ctrl+M | Mute mic |
| Ctrl+S / Ctrl+Z | Stretch / zoom video |

## Building on Windows (MSYS2)

One-time setup: install [MSYS2](https://www.msys2.org/), then in the **MSYS2 MINGW64** shell:

Clone with submodules (`git clone --recurse-submodules ...`), then in the **MSYS2 MINGW64** shell, from the repository folder:

```bash
bash nimbus/setup-msys2.sh   # pacman packages (Qt 6, protobuf, opus, ...); run again if pacman updates itself
bash nimbus/build-deps.sh    # libplacebo, FFmpeg, SDL3 + sdl2-compat, hidapi
bash nimbus/build.sh         # -> build/gui/chiaki.exe
bash nimbus/deploy.sh        # -> ../dist (self-contained, ~300 MB); set DIST=... to change
```

**If the repository path contains a space** (for example `G:\PS5 Remote\chiaki-ng`):
- chiaki-ng's dependency scripts break on the space, so run `build-deps.sh` through a junction without one, for example `New-Item -ItemType Junction -Path G:\psremote -Target "G:\PS5 Remote"` (PowerShell).
- Run `build.sh` from the real path, **not** the junction, because the curl patch step's `git apply` refuses paths through one.

Tests:

```bash
bash nimbus/test-screenshot.sh   # colour conversion for NV12 / P010 HDR screenshots (8 checks)
bash nimbus/test-recorder.sh     # encodes H.264 + Opus, records mid-stream, decodes the file back (20 checks)
bash nimbus/test-asyncdecoder.sh # decode thread: order, Wi-Fi bursts, non-blocking queue, overflow recovery, errors (18 checks)
bash nimbus/test-replay.sh       # instant replay: 45 s in, ~35 s clip from a keyframe, decodes cleanly, memory cap (15 checks)
```

## Testing status

Tested against a real PS5: registration over PSN, streaming over PSN, the stats overlay, screenshots and recording.
The connection automatically retries once if the console doesn't answer the first PSN request.
Not yet tested against a real console: home-network discovery and streaming, per-console presets and post-session advice.
The screenshot colour conversion and the recorder's muxing are also covered by the tests above.

## License

GPL v3, same as chiaki-ng. See `COPYING`.
