#!/usr/bin/env bash
# First boot: finish the card layout and mount the song library.
#
#   1 bootfs  FAT32
#   2 rootfs  ext4   grown here to fill the space before SONGS (16 GiB target)
#   3 SONGS   exFAT  mounted at /srv/songs
#
# The flash scripts normally create SONGS (and copy the songs onto it) before
# the first boot. If the card was written some other way (e.g. plain Raspberry
# Pi Imager), SONGS is created here in the free space instead. Replaces
# Raspberry Pi OS's own resize, which would give the whole card to rootfs.
set -euo pipefail

ROOT_SIZE_GIB=16
SONGS_LABEL=SONGS
MOUNTPOINT=/srv/songs
DONE_MARKER=/var/lib/rockband-kiosk/partitions-done

log() { echo "setup-partitions: $*"; }
sysblk() { cat "/sys/class/block/$1/$2"; }   # sizes are in 512-byte units

part_name() {  # part_name /dev/mmcblk0 3 -> /dev/mmcblk0p3
	case "$1" in
		*[0-9]) echo "${1}p$2" ;;
		*)      echo "$1$2" ;;
	esac
}

root_part=$(findmnt -no SOURCE /)
root_dev=$(basename "$root_part")
disk="/dev/$(lsblk -no PKNAME "$root_part")"
part_num=$(sysblk "$root_dev" partition)
songs_part=$(part_name "$disk" $(( part_num + 1 )))
songs_dev=$(basename "$songs_part")

root_start=$(sysblk "$root_dev" start)
root_size=$(sysblk "$root_dev" size)
disk_size=$(cat "/sys/block/$(basename "$disk")/size")

# Space available to rootfs: up to SONGS if it exists, else the 16 GiB target
target=$(( ROOT_SIZE_GIB * 1024 * 1024 * 1024 / 512 ))
if [ -e "/sys/class/block/$songs_dev" ]; then
	limit=$(( $(sysblk "$songs_dev" start) - root_start ))
else
	# Leave at least 1 GiB for SONGS on small cards
	limit=$(( disk_size - root_start - 2 * 1024 * 1024 ))
fi
[ "$target" -le "$limit" ] || target=$limit

if [ "$root_size" -lt "$target" ]; then
	log "growing $root_part to $(( target / 2 / 1024 / 1024 )) GiB"
	echo ",${target}" | sfdisk --force --no-reread -N "$part_num" "$disk"
	partx -u -n "$part_num" "$disk"
	resize2fs "$root_part"
fi

if ! blkid -L "$SONGS_LABEL" >/dev/null 2>&1; then
	if [ ! -e "/sys/class/block/$songs_dev" ]; then
		log "creating the $SONGS_LABEL partition in the remaining space"
		start=$(( root_start + $(sysblk "$root_dev" size) ))
		start=$(( (start + 2047) / 2048 * 2048 ))
		# Explicit start: --append alone would use the gap before the boot partition
		echo "start=${start}, type=7" | sfdisk --force --no-reread --append "$disk"
		partx -a -n $(( part_num + 1 )) "$disk"
		udevadm settle
	fi
	log "formatting $songs_part as exFAT ($SONGS_LABEL)"
	# Clear leftovers of an older layout; newer mkfs.exfat refuses to overwrite
	wipefs -a -f -q "$songs_part"
	mkfs.exfat -L "$SONGS_LABEL" "$songs_part"
	udevadm settle
fi

mkdir -p "$MOUNTPOINT" "$(dirname "$DONE_MARKER")"
mountpoint -q "$MOUNTPOINT" || mount "$MOUNTPOINT"
touch "$DONE_MARKER"
log "song library mounted at $MOUNTPOINT"
