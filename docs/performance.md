# Performance on the Raspberry Pi 5

How YARG went from 15-20 FPS to a steady 60 FPS in songs on a Pi 5, what each change was worth, and how it was measured. This covers Phases 0 to 2 of [yarg-native-arm64.md](yarg-native-arm64.md).

## Setup

| | |
|---|---|
| Board | Raspberry Pi 5, 8 GB |
| YARG | v0.15.0, IL2CPP build from `scripts/build-yarg.sh` with `patches/YARG/` 0001-0010 |
| Emulation | Box64 (`external/box64`), dynarec settings from `rootfs/opt/rockband-kiosk/yarg-launch.sh` |
| Renderer | Vulkan (Mesa V3DV), YARG Low quality |
| Display | cage + Xwayland, LG TV over HDMI |
| Test song | "Shape of You" (Ed Sheeran), played by YARG bots on Expert guitar |

## Results

| Change | Solo song | Notes |
|---|---|---|
| Official release behaviour, TV at its native 4K | ~15 FPS | YARG rendered 3840×2160 |
| Display forced to 1080p (`DISPLAY_MODE`) | 19-20 | GPU 99% busy |
| No SMAA on the highway camera (`0008`) | 28 | post-processing had cost ~23 ms per frame |
| + highway at 0.67 scale (`0007`) | 40 | |
| + no forced intermediate texture (`0009`) | 47.5 | |
| + highway at 0.5 scale | 57 | |
| + no tonemapping (`0010`) | ~60 | |
| Display 720p, highway scale 0.75 (the defaults) | 72 uncapped, 60 capped | GPU 58-68% busy |

| Four players (drums + 3 guitar bots), 720p, highway 0.75 | |
|---|---|
| With audio normalization | 50-53 FPS, CPU 86% busy on all cores |
| Normalization off (the image's default) | 60 FPS (cap), CPU 51%, GPU 68% |

## Effects back on (four players, 720p, highway 0.75)

| Effect | Band FPS | GPU | Kept? |
|---|---|---|---|
| None (baseline) | 59.9 | 68% | |
| YARG's default venue, 30 FPS cap, UltraPerformance | 59.9 (min 59.8) | 72% | yes |
| + bloom | 58.6 (min 52) | 79% | no: little visible difference without HDR |
| + venue at 60 FPS | 59.8 (min 58.5) | 75% | no: kept at 30 for steady gameplay; one setting (`VenueFpsCap`) |

With vocals (drums + 2 guitars + a vocals bot, venue at 30 FPS): 59.9 FPS over a minute of the song (minimum 59.4), GPU 91%, CPU 59%. The full-width vocals lane is expensive to fill; if a song dips, `YARG_HIGHWAY_SCALE=0.67` frees about 10% GPU. A real microphone adds pitch detection on the CPU (not measured; the bot doesn't use one).

The venue first rendered nothing and left the screen uncleared (UI piling up on itself): its post-processing pass needed an intermediate texture, which `0009` had turned off. That pass now requests one itself.

Not tried: High quality mode (MSAA, HDR, shadows, SMAA everywhere) and song background videos (decoded under emulation).

## What costs what

Per-pass GPU times at 1080p, highway scale 1.0, measured with the kernel's V3D trace events (each render pass is one V3D render job):

| Pass | Time | |
|---|---|---|
| Highway geometry | 8.5 ms | scales with highway resolution |
| Highway post-processing (fade mask, color) | 11.7 ms | with SMAA; mostly SMAA and tonemapping |
| Highway alpha mask | 4.0 ms | scales with highway resolution |
| Background camera clear | 1.3-1.7 ms | full screen |
| Screen-space UI | ~5 ms | full screen; HUD, lyrics, the highway image |
| cage compositing | 3-4 ms | full screen, every frame |

The compositor copy can't be avoided by switching to a bare X server: the Pi 5 renders on V3D but scans out from a separate display controller (vc4), so Xorg made the same ~3.3 ms copy. Rendering at 720p shrinks every full-screen cost to 44%.

On the CPU side, everything runs as x86 code under Box64. With a full band the main thread was not the limit; YARG's audio normalization was, decoding each song a second time in the background (`BassNormalizer.CalculateRms`).

## Tried, no gain

- `BOX64_DYNAREC_STRONGMEM=0`: about +5% with four players, within the variation between song sections; kept at 1 for safety.
- URP store actions set to Discard: no measurable change.
- Bare Xorg instead of cage: the per-frame copy remains (see above).
- Hiding the two invisible full-screen "Dimmer" UI images: about +1 FPS.

## How it was measured

All over SSH, with the TV off but connected:

- **Input:** a small python-evdev daemon created a virtual keyboard and absolute pointer to drive YARG's menus (the pointer must move before each click; YARG ignores the mouse after keyboard use until it moves).
- **FPS:** YARG's own FPS counter, read 10 times per run with `grim` + `tesseract`, averaged.
- **GPU load:** `drm-engine-render` time from `/proc/<pid>/fdinfo`.
- **GPU passes:** `v3d_submit_cl`, `v3d_submit_cl_ioctl` and `v3d_rcl_irq` trace events from `/sys/kernel/tracing`.
- **CPU hotspots:** `perf record` per thread with `BOX64_DYNAREC_PERFMAP=1`, offsets in `GameAssembly.so` resolved with the `GameAssembly.debug` symbols Unity writes next to the build.

## Next

- Vocals with a real microphone (pitch detection) haven't been measured yet.
- Custom per-song venues may cost more than the default one.
