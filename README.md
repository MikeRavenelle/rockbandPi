# rockbandPi

A Raspberry Pi 5 that boots straight into Rock Band.

rockbandPi builds an SD card image that starts [YARG](https://github.com/YARC-Official/YARG) full screen at power on, with your own Rock Band 1 to 4 and DLC song library and your original instruments: Xbox 360 drums, Xbox guitars (including the PDP Riffmaster), USB microphones and Xbox controllers. There's no desktop, keyboard or mouse involved. Pick Quit in YARG and the Pi shuts down.

You bring the songs. Nothing in this repo contains or downloads song data.

## Contents

- [What you need](#what-you-need)
- [Setup on Linux](#setup-on-linux)
- [Setup on macOS](#setup-on-macos)
- [Setup on Windows](#setup-on-windows)
- [First boot](#first-boot)
- [Adding songs later](#adding-songs-later)
- [Remote access and debugging](#remote-access-and-debugging)
- [Controllers](#controllers)
- [How it works](#how-it-works)
- [Troubleshooting the build](#troubleshooting-the-build)
- [Repository layout](#repository-layout)
- [Status](#status)
- [License](#license)

## What you need

**Hardware**
- Raspberry Pi 5 (4 GB or more recommended) with its official power supply
- microSD card, 32 GB minimum. Size it to your library: 16 GB for the system plus your songs.
- HDMI TV or monitor
- Ethernet or Wi-Fi
- Your instruments (see [Controllers](#controllers))

**Songs**

Put your library in the [`songs/`](songs/README.md) folder of this repo. Any folder layout works. YARG reads these formats directly:
- extracted song folders (`song.ini` or `songs.dta`, `notes.mid`, audio stems)
- Xbox 360 CON/LIVE packages
- `.sng` files

The folder is part of the repo, but everything in it except its README is ignored by git, so your songs are never committed.

**A computer to build the image on.** The build runs Raspberry Pi's official image builder (pi-gen) in a container. It takes 1 to 3 hours, needs about 25 GB of free disk, and downloads roughly 2 GB.

## Setup on Linux

1. Install the tools. On Debian/Ubuntu:
   ```bash
   sudo apt install git rsync podman qemu-user-static binfmt-support exfatprogs
   ```
   - **Fedora:** `sudo dnf install git rsync podman qemu-user-static exfatprogs`
   - **Fedora Atomic desktops (Bazzite, Silverblue, Kinoite):** nothing to install; the host already includes all of these.
   - **Docker:** works instead of Podman.
2. Clone the repo with its submodules and create your config:
   ```bash
   git clone --recurse-submodules https://github.com/MikeRavenelle/rockbandPi.git
   cd rockbandPi
   cp config/kiosk.conf.example config/kiosk.conf
   ```
   Edit `config/kiosk.conf`: at least change the password. You can also add Wi-Fi and your SSH key there.
3. Copy your songs into `songs/`.
4. Build the image. Run it from a host terminal, not inside a toolbox or distrobox: the build starts its own container and can't run nested. It asks for your sudo password, because the container needs root to create disk images.
   ```bash
   scripts/build-image.sh
   ```
   The image ends up in `deploy/`.
5. Insert the SD card, find it with `lsblk`, and flash it:
   ```bash
   sudo scripts/flash-sd.sh /dev/sdX
   ```
   This writes the image, creates the SONGS partition and copies `songs/` onto it in one pass. It asks you to type the device name before erasing anything.

## Setup on macOS

1. Install the tools:
   - [Homebrew](https://brew.sh), then `brew install git rsync`
   - a container engine: [Docker Desktop](https://www.docker.com/products/docker-desktop/), or Podman (`brew install podman`, then `podman machine init --rootful && podman machine start`)
2. Clone the repo with its submodules and create your config:
   ```bash
   git clone --recurse-submodules https://github.com/MikeRavenelle/rockbandPi.git
   cd rockbandPi
   cp config/kiosk.conf.example config/kiosk.conf
   ```
   Edit `config/kiosk.conf`: at least change the password.
3. Copy your songs into `songs/`.
4. Build the image:
   ```bash
   scripts/build-image.sh
   ```
5. Insert the SD card, find it with `diskutil list external` (for example `/dev/disk4`), and flash it:
   ```bash
   sudo scripts/flash-sd.sh /dev/disk4
   ```
   This writes the image, creates the SONGS partition, formats it and copies `songs/` onto it. If macOS shows "The disk you inserted was not readable", click Ignore: that's the Linux system partition, which macOS can't read.

## Setup on Windows

The image builder needs Linux, so the build runs inside WSL. Flashing and copying songs run in normal PowerShell.

1. Install the tools:
   - WSL: open PowerShell as Administrator and run `wsl --install -d Ubuntu`, then restart
   - [Docker Desktop](https://www.docker.com/products/docker-desktop/) with "Use the WSL 2 based engine" and WSL integration for Ubuntu turned on
   - [Raspberry Pi Imager](https://www.raspberrypi.com/software/), used for writing the card
   - Inside Ubuntu (WSL): `sudo apt install git rsync qemu-user-static binfmt-support`
2. Clone the repo inside WSL. This is much faster than a clone on `C:\` and keeps Linux line endings intact:
   ```bash
   git clone --recurse-submodules https://github.com/MikeRavenelle/rockbandPi.git ~/rockbandPi
   cd ~/rockbandPi
   cp config/kiosk.conf.example config/kiosk.conf
   ```
   Edit `config/kiosk.conf`: at least change the password. In Explorer the folder is at `\\wsl$\Ubuntu\home\<you>\rockbandPi`.
3. Copy your songs into the repo's `songs\` folder through that Explorer path.
4. Build the image. Either run `scripts/build-image.sh` in the Ubuntu terminal, or from PowerShell:
   ```powershell
   cd \\wsl$\Ubuntu\home\<you>\rockbandPi
   .\scripts\build-image.ps1
   ```
5. Insert the SD card. In PowerShell **as Administrator**, find its disk number with `Get-Disk`, then flash it:
   ```powershell
   .\scripts\flash-sd.ps1 -DiskNumber 2
   ```
   This writes the image with Raspberry Pi Imager, creates and formats the SONGS partition, and copies the songs with robocopy. If Windows offers to format a drive afterwards, click Cancel: that's the Linux system partition.

If you clone on the Windows side instead of in WSL, run `git config --global core.autocrlf false` before cloning. The build refuses checkouts with Windows line endings.

## First boot

Put the card in the Pi, connect the TV, network and instruments, and power on. The first boot does three things:

1. It finishes the card layout: the system partition grows to 16 GB, and SONGS is mounted at `/srv/songs`.
2. YARG starts and scans the song library. With a few thousand songs this takes a while, but it only happens once.
3. SSH and the network share come up, so you can reach the Pi from another computer.

After that, power on goes straight to the YARG main menu in seconds.

## Adding songs later

Copy new songs into `songs/` on your computer, then pick one of these.

**With the card in your computer.** Pick Quit in YARG to shut the Pi down, move the card to your computer, and run:

| OS | Command |
|---|---|
| Linux / macOS | `scripts/copy-songs.sh` |
| Windows | `.\scripts\copy-songs.ps1` |

The SONGS partition shows up like a USB stick, so you can also just drag folders onto it.

**Over the network, with the Pi running:**

| OS | Command |
|---|---|
| Linux / macOS | `scripts/copy-songs.sh rockband@rockband.local` |
| Windows | `.\scripts\copy-songs.ps1 -Network rockband.local` |
| Any | open `\\rockband.local\songs` (Windows Explorer) or `smb://rockband.local/songs` (macOS Finder) and drag files in. Log in with the kiosk user and password. |

Then refresh the library in YARG under Settings > Songs.

The copy scripts only copy new or changed files, and never delete anything on the card.

## Remote access and debugging

SSH is always enabled. With the default config:

```bash
ssh rockband@rockband.local
```

The user, password and SSH key come from `config/kiosk.conf`. The kiosk only runs on the TV's console, so an SSH session is a normal shell with sudo.

| Task | Command |
|---|---|
| Check every controller layer (USB, drivers, bridge, what YARG sees, microphones) | `sudo /opt/rockband-kiosk/diag-controllers.sh` |
| YARG and session logs | `~/.local/state/yarg-kiosk/` (`session.log`, `player.log`) |
| Instrument bridge log, live | `journalctl -u rb-bridge -f` |
| First-boot partition setup log | `journalctl -u rockband-partitions` |
| Test one controller's raw input | `sudo evtest` |
| Restart YARG | `sudo systemctl restart getty@tty1` |
| Boot to a plain console instead of YARG | `touch ~/.kiosk-disable`, then reboot; delete the file to undo |

Settings on the Pi:
- `/etc/rockband-kiosk/kiosk.conf`
  - `YARG_RENDERER`: `vulkan` or `opengl`. If YARG keeps crashing at start on Vulkan, the kiosk switches to OpenGL by itself.
  - `ON_QUIT`: `poweroff` or `restart`.
- `/etc/rockband-kiosk/bridge.conf`: instrument bridge options (see below).

## Controllers

| Instrument | Connection | Shows up in YARG as |
|---|---|---|
| PDP Riffmaster (Xbox) | its USB dongle | Rock Band guitar: frets, solo frets, whammy, tilt, pickup switch; the joystick navigates menus |
| PDP Jaguar / MadCatz Stratocaster (Xbox One) | Xbox Wireless Adapter | Rock Band guitar |
| ION Drum Rocker and other Xbox 360 drum kits | USB | Rock Band drum kit: pads, cymbals, two kick pedals |
| Xbox 360 Rock Band guitars | USB | Rock Band guitar |
| Xbox 360 wireless instruments | Xbox 360 wireless receiver | handled by YARG directly |
| Xbox One / Series controllers | USB cable or Xbox Wireless Adapter | gamepad |
| PS3/PS4 instruments, Santroller, Roll Limitless in PS3/PS4 mode | USB | handled by YARG directly (Roll Limitless untested) |
| USB microphones | USB | microphone; pick it in your YARG profile |

Xbox controllers over Bluetooth aren't supported. Use a cable or the Xbox Wireless Adapter.

**Why a bridge is needed.** On Linux, YARG only talks to HID devices and the Xbox 360 wireless receiver. Linux exposes Xbox hardware as generic gamepads, which YARG ignores. The `rb-bridge` service (in `bridge/`) reads each Xbox device and presents it to YARG as an instrument YARG already supports:

| Real device | Presented to YARG as |
|---|---|
| guitars | Santroller guitars |
| drum kits | PS3 Rock Band kits |
| gamepads | DualShock 4 |

It recognises Xbox 360 instruments by the device type stored in their USB descriptors, so any wired 360 kit or guitar works, not only the ones listed.

**Bridge options** (`/etc/rockband-kiosk/bridge.conf`):
- `drums.mode = santroller` also passes hit velocity, for YARG's drum dynamics. The default (`ps3`) is the safer choice: see the notes in `bridge/rb_bridge/reports.py`.
- `gamepads.enabled = false` stops the bridge from handling Xbox gamepads.

## How it works

| Part | What it is | Why |
|---|---|---|
| OS | Raspberry Pi OS Lite 64-bit (Debian 13 "trixie"), built with pi-gen | Official kernel and firmware for the Pi 5 |
| Game | YARG v0.15.0, the official Linux x86_64 release, pinned by checksum | Full band with vocals and harmonies; reads Rock Band song files as they are |
| x86 emulation | Box64, built from source for the Pi 5 | YARG has no ARM build ([YARG#1269](https://github.com/YARC-Official/YARG/issues/1269)) |
| Kernel | `kernel8.img` (4K memory pages) | Box64 doesn't run on the Pi 5's default 16K-page kernel |
| Display | `cage` kiosk compositor with Xwayland | One full-screen app, no desktop |
| Audio | PipeWire | HDMI output and USB microphones at the same time |
| Drivers | `xone` (Xbox One/Series), `xpad-noone` (Xbox 360), built with DKMS | `xpad-noone` keeps Xbox 360 support while `xone` takes Xbox One devices; DKMS rebuilds both on kernel updates |
| Song share | Samba share `songs` | Copy songs from any OS over the network |

**SD card layout**

| # | Name | Filesystem | Size |
|---|---|---|---|
| 1 | bootfs | FAT32 | 512 MB |
| 2 | rootfs | ext4 | 16 GB |
| 3 | SONGS | exFAT | rest of the card |

SONGS is exFAT so Linux, macOS and Windows can all write to it. Its contents appear on the Pi at `/srv/songs`.

The flash scripts put SONGS 16 GB after the start of the system partition, and the Pi grows the system partition into that space on first boot. If a card is written with plain Raspberry Pi Imager instead of the scripts, the Pi creates SONGS itself on first boot.

## Troubleshooting the build

| Error | Cause | Fix |
|---|---|---|
| `This shell is inside a container (toolbox/distrobox)` or `cannot open sd-bus: No such file or directory` | The build was started inside a toolbox or distrobox. It starts its own privileged container and can't run nested. | Open a terminal on the host (no 📦 in the prompt) and run it there. |
| `qemu-aarch64 not found (please install qemu-user-binfmt)` | The host has no ARM64 emulation registered. | Debian/Ubuntu: `sudo apt install qemu-user-static binfmt-support`. Fedora: `sudo dnf install qemu-user-static`. Fedora hosts name the binary `qemu-aarch64-static`; `patches/pi-gen/` makes pi-gen accept that name. |
| `Container pigen_work already exists` | A previous build stopped partway. | Resume with `CONTINUE=1 scripts/build-image.sh`. Add `SKIP_STAGES="stage0 stage1 stage2 stage-rockband"` to reuse every stage that finished and redo only the image export. To start over instead: `sudo podman rm -v pigen_work`. |
| `mknod: invalid minor device number '/dev/loop0 (lost)'` | pi-gen bug in older checkouts: the host created a loop device after the build container started. | Fixed by `patches/pi-gen/0002`. If a build already got this far, resume with only the export: `CONTINUE=1 SKIP_STAGES="stage0 stage1 stage2 stage-rockband" scripts/build-image.sh` |
| `This checkout has Windows (CRLF) line endings` | The repo was cloned on Windows with automatic line-ending conversion. | Clone inside WSL, or run `git config --global core.autocrlf false` and clone again. |
| A failure in a later stage | pi-gen log | `build/pi-gen/deploy/build-docker.log` and `build/pi-gen/work/*/build.log` show the failing step. |

## Repository layout

```
config/kiosk.conf.example     build settings: user, password, Wi-Fi, SSH key, YARG version
songs/                        your song library (contents ignored by git)
scripts/
  build-image.sh / .ps1       build the image (Linux, macOS / Windows via WSL)
  flash-sd.sh / .ps1          write the card, create SONGS, copy songs (Linux, macOS / Windows)
  copy-songs.sh / .ps1        add songs later, to the card or over the network
  lib/songs-partition.sh      partition table helper used by flash-sd.sh
image/stage-rockband/         pi-gen stage: packages, Box64, drivers, YARG, kiosk setup
rootfs/                       files copied into the image as-is (systemd, udev, Samba, kiosk scripts)
bridge/                       rb-bridge instrument bridge (Python) and its tests
patches/                      changes to submodules, applied at build time
tests/                        host-side tests
docs/                         design notes and plans
external/                     submodules: pi-gen, box64, xone, xpad-noone
```

| Submodule | Source | Pinned at |
|---|---|---|
| `external/pi-gen` | [RPi-Distro/pi-gen](https://github.com/RPi-Distro/pi-gen), `arm64` branch | `2026-09-15-raspios-trixie-arm64` + `patches/pi-gen/` |
| `external/box64` | [ptitSeb/box64](https://github.com/ptitSeb/box64) | master, 2026-10-04 |
| `external/xone` | [dlundqvist/xone](https://github.com/dlundqvist/xone) | `v0.5.8` + `patches/xone/` |
| `external/xpad-noone` | [Jan200101/xpad-noone](https://github.com/Jan200101/xpad-noone) | kernel 7.0.12 sync |

The submodules are never edited directly. Changes live in `patches/<submodule>/` and are applied to a copy during the build:

| Patch | What it does |
|---|---|
| `patches/pi-gen/0001-build-docker-accept-qemu-aarch64-static.patch` | Lets the build run on Fedora-based hosts, which ship `qemu-aarch64-static` instead of `qemu-aarch64` |
| `patches/pi-gen/0002-ensure-next-loopdev-strip-lost-suffix.patch` | Fixes image export failing with `invalid minor device number '/dev/loop0 (lost)'` when the host creates a loop device after the build container started |
| `patches/xone/0001-pdp-jaguar-use-fret-bitmasks-add-pickup-and-riffmaster-joystick.patch` | Reads the Riffmaster's frets correctly and adds its pickup switch and joystick |

**Running the tests** (Linux host):
```bash
python3 -m unittest discover -s bridge/tests
bash tests/test-songs-partition.sh
STAGE_ONLY=1 scripts/build-image.sh     # prepares the build without running it
```

**Updating YARG.** Set `YARG_VERSION` and `YARG_SHA256` in `config/kiosk.conf` and rebuild. Get the checksum with `sha256sum` on the downloaded `Linux-x86_64.zip`.

## Status

**Tested on a Linux build machine:**
- both drivers compile
- the bridge unit tests pass
- the bridge's virtual instruments work through the real Linux kernel HID path with the identifiers YARG matches on
- the partition table changes produce the expected layout (tested on a scratch disk image)
- the build staging works

**Not yet confirmed on real hardware:**
- a complete image build
- YARG's speed under Box64 on the Pi 5
- each physical instrument end to end
- the macOS and Windows scripts on real Macs and PCs

**Performance.** YARG has no ARM64 build, so it runs under x86_64 emulation, and that's the biggest open question. [docs/yarg-native-arm64.md](docs/yarg-native-arm64.md) covers:
- how to measure performance
- tuning
- an ahead-of-time compiled (IL2CPP) build to speed up emulation
- what a native ARM64 build needs, and what currently blocks it on Unity's side

## License

The code in this repo is MIT licensed; see [LICENSE](LICENSE). The patches in `patches/xone/` are GPL-2.0-or-later, because they modify `xone`. The patches in `patches/pi-gen/` follow pi-gen's BSD 3-Clause license.

Third-party software keeps its own license:

| Component | License | How it's used |
|---|---|---|
| pi-gen | BSD 3-Clause | submodule; builds the image |
| Box64 | MIT | submodule; built into the image |
| xone | GPL-2.0-or-later | submodule; built into the image with DKMS |
| xpad-noone | GPL-2.0 | submodule; built into the image with DKMS |
| YARG | LGPL-3.0 (bundles third-party libraries under their own terms) | downloaded during the build |
| Raspberry Pi OS / Debian packages | various free software licenses | installed during the build |
| Xbox Wireless Adapter firmware | Microsoft terms of use | downloaded from Microsoft during the build |

Built images contain the Microsoft firmware and YARG's bundled third-party libraries, so don't publish them. Each user builds their own image from this repo.

This project is not affiliated with Harmonix, MTV Games, Mad Catz, PDP, ION, Microsoft or the YARG team. Rock Band is a trademark of Harmonix Music Systems. You need your own legally obtained song files.
