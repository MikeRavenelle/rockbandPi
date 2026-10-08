# Handoff: Rock Band on the ROG Ally X

Status as of 2026-10-07. This picks up from the work on the Bazzite desktop and continues on the MacBook Pro.

## Why the Ally X

The Pi 5 image works, but playing on it isn't fun:
- It renders at 720p on a 4K OLED.
- Input lags at times.

Both come from the Pi's limits: YARG is x86_64 and runs under Box64 emulation, the V3D GPU sits near 100%, and the compositor plus rb-bridge each add a step. Tuning can't remove those. Details are in `docs/performance.md`.

The ROG Ally X (24 GB, Ryzen Z1 Extreme, RDNA3 graphics) is x86_64, so YARG runs natively with no emulation and no Pi GPU workarounds. It should handle 4K60.

## Decisions so far

- **OS:** keep **Bazzite** on the Ally. Don't wipe it and don't build an image for it.
- **No kiosk mode.** YARG gets added as a **non-Steam game** and launched from Steam's game mode.
- **Songs:** reformat the SD card that held the Pi image as **one ext4 partition labelled `SONGS`**, copy the library with `rsync -rt --progress songs/ /run/media/$USER/SONGS/` (what `scripts/copy-songs.sh` does), and add that path in YARG under Settings → Songs.
- **Living-room setup:** an upright dock stand that holds the Ally by its USB-C port, with HDMI 2.0 (or 2.1), 100 W passthrough, Ethernet and enough USB-A ports for drums, two guitar dongles and the mic. The JSAUX 6-in-1 or 7-in-1 fit. ASUS's ROG Gaming Charger Dock only has one USB-A port, so it's too limited. A dock hasn't been bought yet.
- **The Pi image stays in the repo** as it is. Everything is committed and pushed (last commit `3af9994`).

## The next task: get the instruments working on Bazzite

Hardware:

| Device | USB | Linux driver | What YARG needs |
|---|---|---|---|
| ION Drum Rocker (wired Xbox 360) | Xbox 360 wired, XUSB subtype 0x08 | `xpad` | rb-bridge (shows it as a PS3 kit) |
| 2x PDP Riffmaster (049-034-BK) with dongles | `0e6f:0248`, Xbox One GIP | `xone` (`pdp_jaguar`) | our xone patch + rb-bridge |
| USB mic (Logitech) | USB audio | `snd-usb-audio` | nothing, YARG reads it directly |
| 2x Xbox One controllers | Xbox One GIP | `xone` or in-kernel `xpad` | rb-bridge (DualShock 4) or Steam Input |

### Why plain YARG on Linux isn't enough

YARG on Linux ignores evdev devices. Its HID layer (HIDrogen) drops every Linux input device and reads only hidraw, plus Xbox 360 wireless receivers through libusb. `xpad` and `xone` only create evdev devices, so YARG never sees wired Xbox 360 or Xbox One instruments. On the Pi, two pieces fix that:

1. **rb-bridge** (`bridge/`): a Python daemon that reads the evdev devices and re-creates each one through `/dev/uhid` as a HID instrument YARG recognises.
   - Classification: `bridge/rb_bridge/sources.py` (`XoneGuitar`, `X360Guitar`, `X360Drums`, `Gamepad`).
   - HID report layouts: `bridge/rb_bridge/reports.py`.
   - Config: `rootfs/etc/rockband-kiosk/bridge.conf`.
   - On the Pi it runs as root from `rootfs/etc/systemd/system/rb-bridge.service`.
   - It depends on `python3-evdev`.
2. **Driver patches** (`patches/`):
   - `patches/xone/0001-...`: the stock `pdp_jaguar` driver reads the Riffmaster frets from the shared flag bits, which is wrong. The patch reads the proper upper and lower fret bitmasks and adds the pickup switch (`ABS_RX`), the Riffmaster joystick (`ABS_HAT1X/Y`) and the joystick click (`BTN_THUMBL`). Without it the guitars don't work correctly.
   - `patches/xpad-noone/0001-...`: stops `xpad` from claiming Xbox One interfaces such as the Riffmaster dongle `0e6f:0248`. When `xpad` claims it, the dongle shows up as a "Generic X-Box pad" and `xone` never gets it.

udev rules the Pi image uses (they'll probably be needed on Bazzite too):
- `rootfs/etc/udev/rules.d/69-hid.rules`: hidraw access for the logged-in user (`uaccess`). It has to sort before `73-seat-late.rules`.
- `rootfs/etc/udev/rules.d/70-rockband-hidraw.rules`
- `rootfs/etc/udev/rules.d/99-yarg-libusb.rules`: Xbox 360 wireless receivers, which YARG reads over libusb.

### First step: test what works as-is (not done yet)

Do this before writing anything:
1. In Bazzite's desktop mode, get YARG v0.15.0 for Linux (official zip or the YARC Launcher) and add the `YARG` executable as a non-Steam game.
2. Dock to the OLED and add a few songs.
3. Plug in the drums, both Riffmaster dongles and the mic, and check what YARG lists in Profiles. The touchscreen works there.
4. Play a band song at 4K and judge the input lag.
5. Collect what the system sees:
   ```bash
   lsusb
   cat /proc/bus/input/devices
   lsmod | grep -E 'xone|xpad|gip'
   ls -l /dev/uhid /dev/hidraw*
   modinfo xone_gip 2>/dev/null | head; modinfo xpad | head
   ```

Expected results:
- **Mic:** works.
- **Drums:** probably missing.
- **Riffmasters:** missing, detected as a gamepad, or wrong frets.

### Likely plan: a small Bazzite setup script (not a kiosk)

Add something like `scripts/setup-bazzite.sh` that:
1. Installs rb-bridge to a fixed location (for example `/var/opt/rockband/bridge`, since `/usr` is read-only on Bazzite) with a systemd unit in `/etc/systemd/system/`, plus the udev rules in `/etc/udev/rules.d/`.
2. Gets `python3-evdev` without layering if possible: a venv next to the bridge (`pip install evdev`) is simplest. `rpm-ostree install python3-evdev` also works but needs a reboot.
3. Handles the driver side. This is the hard part, because Bazzite's root is read-only and it already ships `xone` and the in-kernel `xpad`:
   - Check whether Bazzite's bundled `xone` (a kmod built into the image) already has correct Riffmaster support. If it does, no driver work is needed.
   - If not, the options are: (a) build our patched `xone` as an out-of-tree module and load it in place of the bundled one, which has to be redone on every Bazzite kernel update; (b) open a PR upstream to `dlundqvist/xone` so Bazzite eventually picks it up; (c) skip the kernel driver for the Riffmaster and read its GIP packets from userspace over libusb inside rb-bridge, which avoids kernel modules on an immutable OS altogether but means writing a small GIP handshake.
   - The `xpad` vs `xone` claim on `0e6f:0248`: check which driver binds the dongle (`ls -l /sys/bus/usb/devices/*/driver` or `usb-devices`). If `xpad` grabs it, a udev rule or modprobe config to unbind it may be enough. No need for a patched `xpad`.
4. Must not touch Steam, game mode or the session. YARG stays a normal non-Steam game.

Watch out for Steam Input in game mode. It may grab the Xbox One controllers and present them as a virtual pad. Disable Steam Input for the YARG shortcut if the controllers or the bridged gamepads act up.

## Repo rules

- Outside projects are git submodules under `external/`, and our changes live as patches in `patches/<project>/`.
- `songs/` only holds its README. The songs themselves are git-ignored.
- Scripts come in versions for macOS, Linux and Windows where it makes sense. A Bazzite setup script only makes sense in bash, since it runs on the Ally.
- No GitHub Actions.
- Commit messages and docs must not mention any AI assistant, and must not carry co-author trailers or "generated with" lines.
- Write files with an editor, not with shell heredocs.

## Working from the MacBook

The Mac can edit the repo, run the bridge's unit tests (`python3 -m pytest bridge/tests`, needs `pip install evdev pytest`; `evdev` may not build on macOS, in which case the tests run on the Ally), and SSH into the Ally. The Linux drivers and the bridge itself can only run and be tested on the Ally. Enable SSH on Bazzite (`ujust toggle-ssh` or `sudo systemctl enable --now sshd`) to work on it from the Mac.

## Pi state, for reference

- Image builder: pi-gen in a container. YARG v0.15.0 is built from source as an IL2CPP player (`scripts/build-yarg.sh`, patches `patches/YARG/0001-0011` and `patches/YARG.Core/0001`) and runs under Box64.
- Measured: 72 FPS solo, 60 FPS with a full band at 720p.
- Patch `0011` (controller navigation on the Profiles screen) is built and committed but not installed on the Pi. It's useful on the Ally too: if the official YARG release turns out to lack controller navigation there, our IL2CPP build can be produced for x86_64 Linux and run natively without Box64.
- The Pi still has test tools installed (`grim`, `tesseract-ocr`, `linux-perf`). The SD card is about to be reformatted for the Ally anyway.
