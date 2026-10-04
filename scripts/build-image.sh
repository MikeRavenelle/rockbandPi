#!/usr/bin/env bash
# Builds the flashable Raspberry Pi 5 image with pi-gen in a container.
# Linux and macOS (Windows: scripts/build-image.ps1, which runs this in WSL).
#
#   scripts/build-image.sh [config/kiosk.conf]
#
# Output: deploy/<date>-rockbandPi-rockband.img
# Needs:  git, rsync, and Podman or Docker. Linux hosts also need sudo and ARM64
#         binfmt (qemu-user-static); macOS needs Docker Desktop or a rootful
#         Podman machine.
# Env:    STAGE_ONLY=1  prepare build/pi-gen without running the build
#         CONTINUE=1    resume a failed build in the existing container
#         DOCKER=...    container command (default: "sudo podman" on Linux if
#                       Podman is installed, otherwise pi-gen picks docker)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${1:-$ROOT/config/kiosk.conf}"
[ -f "$CONF" ] || {
	echo "Missing $CONF. Start from: cp config/kiosk.conf.example config/kiosk.conf" >&2
	exit 1
}
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ] || [ -n "${DISTROBOX_ENTER_PATH:-}" ]; then
	echo "This shell is inside a container (toolbox/distrobox). The build starts its own" >&2
	echo "privileged container and can't run nested. Run it from a host terminal instead." >&2
	exit 1
fi
if grep -q $'\r' "$ROOT/scripts/build-image.sh" "$CONF"; then
	echo "This checkout has Windows (CRLF) line endings. Clone the repo inside WSL," >&2
	echo "or run: git config --global core.autocrlf false, then re-clone." >&2
	exit 1
fi
# shellcheck source=../config/kiosk.conf.example
. "$CONF"

BUILD="$ROOT/build/pi-gen"
STAGE="$BUILD/stage-rockband"

echo "==> Submodules"
git -C "$ROOT" submodule update --init

echo "==> Staging pi-gen in $BUILD"
if [ "${CONTINUE:-0}" != "1" ]; then
	rm -rf "$BUILD"
fi
mkdir -p "$BUILD"
rsync -a --delete --exclude .git --exclude work --exclude deploy \
	"$ROOT/external/pi-gen/" "$BUILD/"
for p in "$ROOT"/patches/pi-gen/*.patch; do
	[ -e "$p" ] || continue
	echo "    pi-gen: $(basename "$p")"
	# build/ lives inside this repo; stop git from treating it as part of it
	GIT_CEILING_DIRECTORIES="$ROOT/build" git -C "$BUILD" apply "$p"
done
# Only export our image, not the intermediate Lite image
rm -f "$BUILD/stage2/EXPORT_IMAGE"
rsync -a --delete "$ROOT/image/stage-rockband/" "$STAGE/"

echo "==> Staging sources and applying patches"
mkdir -p "$STAGE/01-box64/files" "$STAGE/02-drivers/files" "$STAGE/04-kiosk/files"
rsync -a --delete --exclude .git "$ROOT/external/box64/" "$STAGE/01-box64/files/box64/"
for src in xone xpad-noone; do
	rsync -a --delete --exclude .git "$ROOT/external/$src/" "$STAGE/02-drivers/files/$src/"
	for p in "$ROOT"/patches/"$src"/*.patch; do
		[ -e "$p" ] || continue
		echo "    $src: $(basename "$p")"
		# build/ lives inside this repo; stop git from treating it as part of it
		GIT_CEILING_DIRECTORIES="$STAGE/02-drivers/files" \
			git -C "$STAGE/02-drivers/files/$src" apply "$p"
	done
done
rsync -a --delete "$ROOT/rootfs/" "$STAGE/04-kiosk/files/rootfs/"
rsync -a --delete --exclude __pycache__ --exclude tests "$ROOT/bridge/" "$STAGE/04-kiosk/files/bridge/"

# Checkouts on Windows filesystems can lose execute bits; pi-gen skips
# stage scripts that aren't executable
find "$BUILD" -name '*.sh' -exec chmod +x {} +
chmod +x "$BUILD/build.sh" "$BUILD/build-docker.sh" "$STAGE/04-kiosk/files/bridge/rb-bridge"

XONE_VERSION="$(git -C "$ROOT/external/xone" describe --tags --always | sed 's/^v//')"
XPAD_NOONE_VERSION="$(git -C "$ROOT/external/xpad-noone" rev-parse --short HEAD)"

# Values for the stage scripts (pi-gen only exports its own variables)
cat > "$STAGE/kiosk.env" <<EOF
XONE_VERSION=$(printf %q "$XONE_VERSION")
XPAD_NOONE_VERSION=$(printf %q "$XPAD_NOONE_VERSION")
YARG_VERSION=$(printf %q "$YARG_VERSION")
YARG_SHA256=$(printf %q "$YARG_SHA256")
SONGS_DIR=/srv/songs
KIOSK_PASSWORD=$(printf %q "$KIOSK_PASSWORD")
WIFI_SSID=$(printf %q "${WIFI_SSID:-}")
WIFI_PSK=$(printf %q "${WIFI_PSK:-}")
EOF

cat > "$BUILD/config" <<EOF
IMG_NAME=rockbandPi
PI_GEN_RELEASE="rockbandPi"
RELEASE=trixie
DEPLOY_COMPRESSION=none
STAGE_LIST="stage0 stage1 stage2 stage-rockband"
TARGET_HOSTNAME=$(printf %q "$HOSTNAME")
FIRST_USER_NAME=$(printf %q "$KIOSK_USER")
FIRST_USER_PASS=$(printf %q "$KIOSK_PASSWORD")
DISABLE_FIRST_BOOT_USER_RENAME=1
ENABLE_SSH=1
PUBKEY_SSH_FIRST_USER=$(printf %q "${SSH_PUBKEY:-}")
LOCALE_DEFAULT=$(printf %q "$LOCALE")
TIMEZONE_DEFAULT=$(printf %q "$TIMEZONE")
KEYBOARD_LAYOUT=$(printf %q "$KEYBOARD_LAYOUT")
KEYBOARD_KEYMAP=$(printf %q "$KEYBOARD_KEYMAP")
WPA_COUNTRY=$(printf %q "$WIFI_COUNTRY")
EOF

if [ "${STAGE_ONLY:-0}" = "1" ]; then
	echo "STAGE_ONLY=1: staged in $BUILD, not building"
	exit 0
fi

echo "==> Building (this takes a while: Box64 and the drivers compile under emulation)"
cd "$BUILD"
if [ -z "${DOCKER:-}" ]; then
	if [ "$(uname -s)" = "Linux" ] && command -v podman >/dev/null; then
		# Loop devices and binfmt need a rootful container
		export DOCKER="sudo podman"
	elif ! command -v docker >/dev/null && command -v podman >/dev/null; then
		# macOS: the Podman machine must be rootful (podman machine set --rootful)
		export DOCKER="podman"
	fi
fi
./build-docker.sh

mkdir -p "$ROOT/deploy"
find "$BUILD/deploy" -maxdepth 1 -type f \( -name '*.img' -o -name '*.info' -o -name '*.log' \) \
	-exec mv -f {} "$ROOT/deploy/" \;
echo
echo "Image(s) in $ROOT/deploy:"
ls -lh "$ROOT/deploy"
