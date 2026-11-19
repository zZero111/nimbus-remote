# Nimbus Remote

A PS5/PS4 Remote Play client for Windows, built on [chiaki-ng](https://github.com/streetpea/chiaki-ng) (GPL v3).
"Nimbus Remote" is a working name. Change it in `gui/include/appinfo.h`.

## Download

Get the latest `NimbusRemote-win64-*.zip` from this repository's **Releases** page, unzip it anywhere and run `chiaki.exe`.
No install is needed. Each PC keeps its own settings and console registration.

**Updates are automatic** from `nimbus.5` on. On launch the app checks for a newer release and downloads it in the background. Then either click **Restart & update** on the home screen, or just close the app and it installs on exit. It never updates during a stream. If an update fails, the details are in `%TEMP%\NimbusRemoteUpdate\install.log`. Set the environment variable `NIMBUS_NO_UPDATE=1` to turn updates off.

## Publishing a release

```powershell
powershell -ExecutionPolicy Bypass -File nimbus\release.ps1 -Number 6 -Notes "What changed"
```

This stamps the version into `gui/include/appinfo.h`, builds, packages, zips, commits, pushes and creates the GitHub release that installed copies update to.

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
| **Decoding on its own thread**: the network thread only queues video (at most about 66 ms); a dedicated thread decodes. Heavy frames no longer stall the network, and a PC that falls behind skips to a fresh keyframe instead of building up delay. | `gui/src/asyncdecoder.cpp`, `gui/src/streamsession.cpp` |
| **Stream socket receive buffer of 512 KB** (was 100 KB), so keyframe bursts aren't dropped on Wi-Fi | `lib/src/takion.c` |
| **Intel laptops tune themselves**: with the decoder on Auto, Intel integrated graphics use `d3d11va`, and the first stream switches High Quality render presets to Default | `gui/src/qmlbackend.cpp`, `gui/src/qmlmainwindow.cpp` |
| **Self-update** from GitHub releases: background download, "Restart & update" button or install on exit | `gui/src/updater.cpp`, `gui/src/qml/MainView.qml` |
| **Network hint**: when the PC is online only through phone USB tethering or VPNs, the home screen explains why no console can be found | `gui/src/netcheck.cpp`, `gui/src/qml/MainView.qml` |
| **Own logo** on the home screen (Settings > About still credits chiaki-ng) | `gui/res/nimbus-logo-white.svg` |
| **Own settings store**: on first launch it copies an existing chiaki-ng setup (consoles, PSN login, mappings, profiles) and never changes the original | `gui/src/main.cpp` |

Everything else (registration, PSN remote play, wake, controller mapping, DualSense haptics, libplacebo rendering) comes from chiaki-ng.

## Shortcuts while streaming

| Key | Action |
|---|---|
| F12 | Screenshot |
| F9 | Start / stop recording |
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
bash nimbus/test-asyncdecoder.sh # decode thread: order, non-blocking queue, overflow recovery, errors (14 checks)
```

## Testing status

Tested against a real PS5: registration over PSN, streaming over PSN, the stats overlay, screenshots and recording.
The connection automatically retries once if the console doesn't answer the first PSN request.
Not yet tested against a real console: home-network discovery and streaming, per-console presets and post-session advice.
The screenshot colour conversion and the recorder's muxing are also covered by the tests above.

## License

GPL v3, same as chiaki-ng. See `COPYING`.
