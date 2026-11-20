.pragma library

// PS5 stream quality presets shared by the home-screen bar and the per-console chips.
// Resolution: 1=360p 2=540p 3=720p 4=1080p. Bitrate 0 = automatic for the resolution.
// Codec: 0=H264 1=H265 2=H265 HDR (HDR needs a non-OpenGL renderer, else falls back to H265).
var list = [
    {
        key: "performance",
        name: "Performance",
        hint: "Lowest latency: 720p at home, 540p away",
        local:  { res: 3, fps: 60, bitrate: 0, codec: 1 },
        remote: { res: 2, fps: 60, bitrate: 0, codec: 1 }
    },
    {
        key: "balanced",
        name: "Balanced",
        hint: "1080p at home, 720p away",
        local:  { res: 4, fps: 60, bitrate: 0, codec: 1 },
        remote: { res: 3, fps: 60, bitrate: 0, codec: 1 }
    },
    {
        key: "quality",
        name: "Quality",
        hint: "1080p, 40 Mbps, HDR when supported",
        local:  { res: 4, fps: 60, bitrate: 40000, codec: 2 },
        remote: { res: 4, fps: 60, bitrate: 0, codec: 1 }
    },
    {
        // A 30 fps game (GTA 6) streamed at 60 fps sends every frame twice, so network jitter
        // shows as uneven 1-2-3 frame timing, and frame generation has nothing new to work with.
        // Streaming at 30 fps sends each real frame once, with twice the data per frame.
        key: "fps30",
        name: "30 fps games",
        special: true,
        hint: "For 30 fps games like GTA 6: each real frame sent once, with more detail. Pair with AMD Fluid Motion Frames or Lossless Scaling for 60+ fps",
        local:  { res: 4, fps: 30, bitrate: 30000, codec: 1 },
        remote: { res: 4, fps: 30, bitrate: 0, codec: 1 }
    }
];

function byKey(key) {
    for (var i = 0; i < list.length; i++)
        if (list[i].key === key)
            return list[i];
    return null;
}

function codecFor(settings, c) {
    return (c === 2 && settings.rendererBackend === 1) ? 1 : c;
}

function matches(settings, p) {
    return settings.resolutionLocalPS5 === p.local.res && settings.fpsLocalPS5 === p.local.fps
        && settings.bitrateLocalPS5 === p.local.bitrate && settings.codecLocalPS5 === codecFor(settings, p.local.codec)
        && settings.resolutionRemotePS5 === p.remote.res && settings.fpsRemotePS5 === p.remote.fps
        && settings.bitrateRemotePS5 === p.remote.bitrate && settings.codecRemotePS5 === codecFor(settings, p.remote.codec);
}

function apply(settings, p) {
    settings.resolutionLocalPS5 = p.local.res;
    settings.fpsLocalPS5 = p.local.fps;
    settings.bitrateLocalPS5 = p.local.bitrate;
    settings.codecLocalPS5 = codecFor(settings, p.local.codec);
    settings.resolutionRemotePS5 = p.remote.res;
    settings.fpsRemotePS5 = p.remote.fps;
    settings.bitrateRemotePS5 = p.remote.bitrate;
    settings.codecRemotePS5 = codecFor(settings, p.remote.codec);
}

// Per-console choice, stored as JSON {consoleId: presetKey}; "" / missing = use current settings
function consoleId(host) {
    return host.mac ? "mac:" + host.mac : (host.duid ? "duid:" + host.duid : "name:" + (host.name || ""));
}

function nextKey(key) {
    if (!key)
        return list[0].key;
    for (var i = 0; i < list.length; i++)
        if (list[i].key === key)
            return i + 1 < list.length ? list[i + 1].key : "";
    return "";
}
