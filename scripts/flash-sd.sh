#!/usr/bin/env bash
# Writes the rockbandPi image to an SD card, adds the exFAT SONGS partition,
# and copies ./songs onto it, all in one pass. Linux and macOS
# (Windows: scripts/flash-sd.ps1).
#
#   Linux:  sudo scripts/flash-sd.sh /dev/sdX   [image] [songs-dir]
#   macOS:  sudo scripts/flash-sd.sh /dev/diskN [image] [songs-dir]
#
# image defaults to the newest deploy/*.img (.img.xz / .img.zst also work);
# songs-dir defaults to ./songs. Everything on the card is erased.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/songs-partition.sh
. "$ROOT/scripts/lib/songs-partition.sh"

DEV="${1:?usage: sudo $0 <device> [image] [songs-dir]}"
IMG="${2:-$(ls -t "$ROOT"/deploy/*.img* 2>/dev/null | head -1 || true)}"
SONGS="${3:-$ROOT/songs}"
OS="$(uname -s)"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "No image found; run scripts/build-image.sh first." >&2; exit 1; }

decompress() {
	case "$IMG" in
		*.xz)  xz -dc "$IMG" ;;
		*.zst) zstd -dc "$IMG" ;;
		*)     cat "$IMG" ;;
	esac
}

has_songs=0
for f in "$SONGS"/* "$SONGS"/.[!.]*; do
	[ -e "$f" ] && [ "$(basename "$f")" != "README.md" ] && { has_songs=1; break; }
done
[ "$has_songs" = 1 ] || echo "Note: no songs in $SONGS; the card gets an empty SONGS partition."

copy_songs() {  # copy_songs <mountpoint>
	[ "$has_songs" = 1 ] || return 0
	echo "==> Copying songs (only new/changed files; can take a long time)"
	# exFAT has no Unix owners/permissions and 2-second timestamps
	rsync -rt --size-only --exclude /README.md --progress "$SONGS/" "$1/"
	sync
}

confirm() {
	echo "Device: $DEV  ($1)"
	echo "Image:  $IMG"
	echo "Songs:  $SONGS"
	echo
	read -r -p "ALL DATA ON $DEV WILL BE ERASED. Type the device name ($(basename "$DEV")) to continue: " answer
	[ "$answer" = "$(basename "$DEV")" ] || { echo "Aborted."; exit 1; }
}

extent_file="$(mktemp)"
trap 'rm -f "$extent_file"' EXIT

# --- macOS ---------------------------------------------------------------------
if [ "$OS" = "Darwin" ]; then
	case "$DEV" in
		/dev/disk[0-9]*) ;;
		*) echo "Use a whole disk like /dev/disk4 (see: diskutil list external)." >&2; exit 1 ;;
	esac
	info="$(diskutil info "$DEV")"
	boot_disk="$(diskutil info / | awk -F': *' '/Part of Whole/{print $2}')"
	[ "$(basename "$DEV")" != "$boot_disk" ] || { echo "$DEV is the startup disk. Refusing." >&2; exit 1; }
	if ! grep -Eq 'Removable Media: +(Removable|Yes)|Protocol: +(USB|Secure Digital)' <<<"$info"; then
		echo "$DEV doesn't look like an SD card or USB drive. Refusing." >&2
		exit 1
	fi
	card_bytes="$(diskutil info -plist "$DEV" | plutil -extract TotalSize raw -)"
	confirm "$(awk -F': *' '/Media Name|Disk Size/{printf "%s  ", $2}' <<<"$info")"

	diskutil unmountDisk "$DEV"
	echo "==> Writing image with the SONGS partition added (no progress bar; press Ctrl+T for status)"
	patched_image_stream $(( card_bytes / SECTOR )) decompress 3>"$extent_file" |
		dd of="${DEV/disk/rdisk}" bs=4m
	sync

	echo "==> Waiting for macOS to re-read the card"
	for _ in $(seq 1 30); do
		[ -e "${DEV}s3" ] && break
		sleep 1
	done
	[ -e "${DEV}s3" ] || {
		echo "The SONGS partition did not appear. Remove and reinsert the card, then run:" >&2
		echo "  sudo newfs_exfat -v SONGS ${DEV/disk/rdisk}s3 && scripts/copy-songs.sh" >&2
		exit 1
	}
	diskutil unmountDisk "$DEV" || true
	echo "==> Formatting SONGS (exFAT)"
	newfs_exfat -v SONGS "${DEV/disk/rdisk}s3"
	diskutil mount "${DEV}s3"
	mnt="$(diskutil info "${DEV}s3" | awk -F': *' '/Mount Point/{print $2}')"
	copy_songs "$mnt"
	diskutil eject "$DEV" || true
	echo
	echo "Done. Put the card in the Pi and power it on."
	exit 0
fi

# --- Linux ---------------------------------------------------------------------
[ -b "$DEV" ] || { echo "$DEV is not a block device." >&2; exit 1; }
if [ -n "$(lsblk -no PKNAME "$DEV" 2>/dev/null | head -1)" ]; then
	echo "$DEV is a partition; pass the whole disk (e.g. /dev/sdb, /dev/mmcblk0)." >&2
	exit 1
fi
if lsblk -nro MOUNTPOINT "$DEV" | grep -qx '/'; then
	echo "$DEV holds the running system. Refusing." >&2
	exit 1
fi
command -v mkfs.exfat >/dev/null || { echo "mkfs.exfat not found; install exfatprogs." >&2; exit 1; }

card_sectors=$(blockdev --getsz "$DEV")
if [ "$has_songs" = 1 ]; then
	songs_bytes=$(du -sb "$SONGS" | cut -f1)
	need=$(( songs_bytes + (ROOT_SIZE_GIB + 2) * 1024 * 1024 * 1024 ))
	if [ $(( card_sectors * SECTOR )) -lt "$need" ]; then
		echo "Card is $(( card_sectors * SECTOR / 1024**3 )) GiB; songs + system need $(( need / 1024**3 )) GiB." >&2
		exit 1
	fi
fi
confirm "$(lsblk -dno MODEL,SIZE "$DEV" | xargs)"

echo "==> Unmounting any mounted partitions"
lsblk -nro NAME,MOUNTPOINT "$DEV" | awk '$2 != "" {print "/dev/"$1}' | xargs -r umount

echo "==> Writing image with the SONGS partition added"
patched_image_stream "$card_sectors" decompress 3>"$extent_file" |
	dd of="$DEV" bs=4M conv=fsync status=progress
sync
blockdev --rereadpt "$DEV" || partprobe "$DEV" || true
udevadm settle

case "$(basename "$DEV")" in
	*[0-9]) P3="${DEV}p3" ;;
	*)      P3="${DEV}3" ;;
esac
echo "==> Formatting SONGS (exFAT)"
mkfs.exfat -L SONGS "$P3"

mnt="$(mktemp -d)"
trap 'umount "$mnt" 2>/dev/null; rmdir "$mnt" 2>/dev/null; rm -f "$extent_file"' EXIT
mount "$P3" "$mnt"
copy_songs "$mnt"
umount "$mnt"

echo
echo "Done. Put the card in the Pi and power it on."
