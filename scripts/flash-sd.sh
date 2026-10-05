#!/usr/bin/env bash
# Writes the rockbandPi image to an SD card, adds the exFAT SONGS partition,
# and copies ./songs onto it, all in one pass. Linux and macOS
# (Windows: scripts/flash-sd.ps1).
#
#   sudo scripts/flash-sd.sh                      # pick the card from a list
#   sudo scripts/flash-sd.sh /dev/sdX   [image] [songs-dir]     (Linux)
#   sudo scripts/flash-sd.sh /dev/diskN [image] [songs-dir]     (macOS)
#   sudo scripts/flash-sd.sh --songs-only [/dev/sdX] [songs-dir]
#   sudo scripts/flash-sd.sh --skip-songs [/dev/sdX] [image]
#
# image defaults to the newest deploy/*.img (.img.xz / .img.zst also work);
# songs-dir defaults to ./songs. Pass "" as the device to pick from the list
# while still giving an image or songs folder. Everything on the card is erased.
#
# --songs-only skips writing the image: it only formats the card's existing
# SONGS partition and copies the songs, for a card that already has the image
# (for example when a flash stopped after writing it). To add songs without
# erasing the ones on the card, use scripts/copy-songs.sh instead.
#
# --skip-songs updates the system on a card flashed by this script and keeps
# its SONGS partition and songs: it writes the new image and leaves SONGS
# alone. It refuses if SONGS isn't exactly where the new partition table
# puts it (a different card, or one set up another way).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/songs-partition.sh
. "$ROOT/scripts/lib/songs-partition.sh"

SONGS_ONLY=0
SKIP_SONGS=0
case "${1:-}" in
	--songs-only) SONGS_ONLY=1; shift ;;
	--skip-songs) SKIP_SONGS=1; shift ;;
esac

DEV="${1:-}"
if [ "$SONGS_ONLY" = 1 ]; then
	IMG=""
	SONGS="${2:-$ROOT/songs}"
else
	IMG="${2:-$(ls -t "$ROOT"/deploy/*.img* 2>/dev/null | head -1 || true)}"
	SONGS="${3:-$ROOT/songs}"
fi
OS="$(uname -s)"

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }

# True if anything on the disk (partitions, encrypted volumes...) is mounted
# outside the removable-media folders, i.e. it's part of the running system.
# Works on layouts where / isn't a plain partition (composefs, btrfs, LUKS).
is_system_disk() {
	local dev target
	while read -r dev; do
		while read -r target; do
			case "$target" in
				''|/run/media/*|/media/*|/mnt/*) ;;
				*) return 0 ;;
			esac
		done < <(findmnt -nro TARGET -S "$dev" 2>/dev/null || true)
	done < <(lsblk -nrpo NAME "$1" 2>/dev/null || true)
	return 1
}

# Lists removable drives (SD cards, USB) and lets the user pick one by number.
# Internal disks and the disk holding the running system are never offered.
choose_device() {
	local names=() descs=() name desc i choice
	if [ "$OS" = "Darwin" ]; then
		while read -r name; do
			desc="$(diskutil info "$name" | awk -F': *' '
				/Disk Size/ {split($2, s, " ("); size = s[1]}
				/Media Name/ {model = $2}
				END {print size "  " model}')"
			names+=("$name"); descs+=("$desc")
		done < <(diskutil list external physical | awk '/^\/dev\/disk[0-9]+/ {print $1}')
	else
		local line NAME SIZE TRAN RM MODEL labels
		while read -r line; do
			# lsblk -P prints KEY="value" pairs, so empty columns don't shift
			NAME="" SIZE="" TRAN="" RM="" MODEL=""
			eval "$line"
			[ "$RM" = "1" ] || [ "$TRAN" = "usb" ] || [ "$TRAN" = "mmc" ] || continue
			! is_system_disk "$NAME" || continue
			# Empty card-reader slots show up as 0-byte disks
			[ "$SIZE" != "0B" ] || continue
			desc="$SIZE  ${TRAN:-?}  $MODEL"
			labels="$(lsblk -nro LABEL "$NAME" | grep -v '^$' | paste -sd, - || true)"
			[ -z "$labels" ] || desc="$desc  [partitions: $labels]"
			names+=("$NAME"); descs+=("$desc")
		done < <(lsblk -dnpP -o NAME,SIZE,TRAN,RM,MODEL -e 7,11)
	fi

	if [ "${#names[@]}" -eq 0 ]; then
		echo "No SD card or USB drive found. Insert the card and try again." >&2
		exit 1
	fi
	echo "Removable drives:"
	for i in "${!names[@]}"; do
		printf '  %d) %-14s %s\n' $(( i + 1 )) "${names[$i]}" "${descs[$i]}"
	done
	echo
	read -r -p "Flash which drive? [1-${#names[@]}]: " choice
	case "$choice" in
		''|*[!0-9]*) echo "Aborted." >&2; exit 1 ;;
	esac
	if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#names[@]}" ]; then
		echo "Aborted." >&2
		exit 1
	fi
	DEV="${names[$(( choice - 1 ))]}"
}

if [ -z "$DEV" ]; then
	choose_device
fi
# Accept "sde" / "disk4" as well as "/dev/sde" / "/dev/disk4"
case "$DEV" in
	/*) ;;
	*) [ -e "/dev/$DEV" ] && DEV="/dev/$DEV" ;;
esac
if [ "$SONGS_ONLY" = 0 ]; then
	[ -n "$IMG" ] && [ -f "$IMG" ] || { echo "No image found; run scripts/build-image.sh first." >&2; exit 1; }
fi

decompress() {
	case "$IMG" in
		*.xz)  xz -dc "$IMG" ;;
		*.zst) zstd -dc "$IMG" ;;
		*)     cat "$IMG" ;;
	esac
}

has_songs=0
[ "$SKIP_SONGS" = 0 ] || SONGS="(kept on the card; --skip-songs)"
for f in "$SONGS"/* "$SONGS"/.[!.]*; do
	[ -e "$f" ] && [ "$(basename "$f")" != "README.md" ] && { has_songs=1; break; }
done
[ "$has_songs" = 1 ] || [ "$SKIP_SONGS" = 1 ] ||
	echo "Note: no songs in $SONGS; the card gets an empty SONGS partition."

# --skip-songs: refuses unless the card's SONGS partition (MBR entry 3, read
# from raw device $1) is exactly where the new image's partition table will
# put it, so writing the image can't touch the songs
check_songs_kept() {  # check_songs_kept <raw device> <card sectors>
	local card_mbr image_mbr have want
	card_mbr="$(mktemp)"
	image_mbr="$(mktemp)"
	dd if="$1" of="$card_mbr" bs=$SECTOR count=1 2>/dev/null
	decompress | head -c $SECTOR > "$image_mbr" || true
	have="$(mbr_songs_entry "$card_mbr")"
	want="07 $(songs_extent "$image_mbr" "$2")"
	rm -f "$card_mbr" "$image_mbr"
	if [ "$have" != "$want" ]; then
		echo "This card's SONGS partition isn't where the new image expects it" >&2
		echo "(card: type/start/size $have, expected $want)." >&2
		echo "Flash it without --skip-songs, then copy the songs again." >&2
		exit 1
	fi
}

copy_songs() {  # copy_songs <mountpoint>
	[ "$has_songs" = 1 ] || return 0
	echo "==> Copying songs (only new/changed files; can take a long time)"
	# exFAT has no Unix owners/permissions and 2-second timestamps
	rsync -rt --size-only --exclude /README.md --progress "$SONGS/" "$1/"
	sync
}

confirm() {
	local what="ALL DATA ON $DEV"
	echo "Device: $DEV  ($1)"
	if [ "$SONGS_ONLY" = 1 ]; then
		echo "Image:  (not written; --songs-only)"
		what="THE SONGS PARTITION ON $DEV"
	elif [ "$SKIP_SONGS" = 1 ]; then
		echo "Image:  $IMG"
		what="THE SYSTEM (EVERYTHING BUT SONGS) ON $DEV"
	else
		echo "Image:  $IMG"
	fi
	echo "Songs:  $SONGS"
	echo
	read -r -p "$what WILL BE ERASED. Type the device name ($(basename "$DEV")) to continue: " answer
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
	[ "$SKIP_SONGS" = 0 ] || check_songs_kept "${DEV/disk/rdisk}" $(( card_bytes / SECTOR ))
	confirm "$(awk -F': *' '/Media Name|Disk Size/{printf "%s  ", $2}' <<<"$info")"

	diskutil unmountDisk "$DEV"
	if [ "$SONGS_ONLY" = 0 ]; then
		echo "==> Writing image with the SONGS partition added (no progress bar; press Ctrl+T for status)"
		patched_image_stream $(( card_bytes / SECTOR )) decompress 3>"$extent_file" |
			dd of="${DEV/disk/rdisk}" bs=4m
		sync
	fi
	if [ "$SKIP_SONGS" = 1 ]; then
		diskutil eject "$DEV" || true
		echo
		echo "Done. SONGS and its songs were kept. Put the card in the Pi and power it on."
		exit 0
	fi

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
if is_system_disk "$DEV"; then
	echo "$DEV is mounted as part of the running system. Refusing." >&2
	exit 1
fi
command -v mkfs.exfat >/dev/null || { echo "mkfs.exfat not found; install exfatprogs." >&2; exit 1; }

card_sectors=$(blockdev --getsz "$DEV")
case "$(basename "$DEV")" in
	*[0-9]) P3="${DEV}p3" ;;
	*)      P3="${DEV}3" ;;
esac
if [ "$SONGS_ONLY" = 1 ]; then
	[ -b "$P3" ] || { echo "$DEV has no third (SONGS) partition; flash the image first (without --songs-only)." >&2; exit 1; }
elif [ "$SKIP_SONGS" = 1 ]; then
	check_songs_kept "$DEV" "$card_sectors"
elif [ "$has_songs" = 1 ]; then
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

if [ "$SONGS_ONLY" = 0 ]; then
	echo "==> Writing image with the SONGS partition added"
	patched_image_stream "$card_sectors" decompress 3>"$extent_file" |
		dd of="$DEV" bs=4M conv=fsync status=progress
	sync
	blockdev --rereadpt "$DEV" || partprobe "$DEV" || true
	udevadm settle
fi
if [ "$SKIP_SONGS" = 1 ]; then
	echo
	echo "Done. SONGS and its songs were kept. Put the card in the Pi and power it on."
	exit 0
fi

echo "==> Formatting SONGS (exFAT)"
# A previous flash leaves its SONGS filesystem at the same spot, which can
# look like a nested partition table; newer mkfs.exfat refuses to format
# over either
wipefs -a -f -q "$P3"
mkfs.exfat -L SONGS "$P3"

mnt="$(mktemp -d)"
trap 'umount "$mnt" 2>/dev/null; rmdir "$mnt" 2>/dev/null; rm -f "$extent_file"' EXIT
mount "$P3" "$mnt"
copy_songs "$mnt"
umount "$mnt"

echo
echo "Done. Put the card in the Pi and power it on."
