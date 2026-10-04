# shellcheck shell=bash
# Helpers for adding the SONGS partition to the image's MBR before it is written.
# Sourced by scripts/flash-sd.sh (Linux and macOS) and tests/test-songs-partition.sh.
#
# Card layout (same on every OS, and what the Pi's setup-partitions.sh expects):
#   1 bootfs  FAT32   from the image
#   2 rootfs  ext4    from the image; the Pi grows it into the gap on first boot
#   (gap)             up to ROOT_SIZE_GIB after the start of partition 2
#   3 SONGS   exFAT   from there to the end of the card

ROOT_SIZE_GIB=16
SECTOR=512

# Prints "start size" (in sectors) of partition 2 from a 512-byte MBR file.
mbr_root_extent() {
	# Entry 2 starts at byte 462; its LBA start and length are at +8 and +12
	od -An -tu4 -j470 -N8 "$1" | awk '{print $1, $2}'
}

# Prints a 32-bit little-endian value as printf escapes.
le32() {
	printf '\\x%02x\\x%02x\\x%02x\\x%02x' \
		$(($1 & 255)) $(($1 >> 8 & 255)) $(($1 >> 16 & 255)) $(($1 >> 24 & 255))
}

# Computes where SONGS goes on a card of the given size (in sectors).
# Prints "start size" (in sectors).
songs_extent() {
	local mbr="$1" card_sectors="$2" root_start root_size start size min_start
	read -r root_start root_size < <(mbr_root_extent "$mbr")
	start=$(( root_start + ROOT_SIZE_GIB * 1024 * 1024 * 1024 / SECTOR ))
	# Never overlap the system partition, and keep 1 MiB alignment
	min_start=$(( (root_start + root_size + 2047) / 2048 * 2048 ))
	[ "$start" -ge "$min_start" ] || start=$min_start
	size=$(( (card_sectors - start) / 2048 * 2048 ))
	echo "$start $size"
}

# Writes MBR entry 3 (type 0x07, exFAT) into a 512-byte MBR file.
mbr_add_songs_entry() {
	local mbr="$1" start="$2" size="$3" entry
	# status, CHS start (unused), type 0x07, CHS end (unused), LBA start, length
	entry="\\x00\\xfe\\xff\\xff\\x07\\xfe\\xff\\xff$(le32 "$start")$(le32 "$size")"
	# shellcheck disable=SC2059  # the format string is the escaped bytes
	printf "$entry" | dd of="$mbr" bs=1 seek=478 conv=notrunc 2>/dev/null
}

# Streams the image with a patched MBR adding SONGS for a card of the given
# size (in sectors). Usage: patched_image_stream card_sectors <cmd that prints the image...>
# Prints "start size" of SONGS to fd 3.
patched_image_stream() {
	local card_sectors="$1"; shift
	local tmp start size
	tmp="$(mktemp)"
	"$@" | head -c "$SECTOR" > "$tmp" || true
	if [ "$(wc -c < "$tmp" | tr -d ' ')" -ne "$SECTOR" ]; then
		echo "Could not read the image's partition table." >&2
		rm -f "$tmp"
		return 1
	fi
	read -r start size < <(songs_extent "$tmp" "$card_sectors")
	if [ "$size" -lt $(( 1024 * 1024 * 1024 / SECTOR )) ]; then
		echo "Card too small for a SONGS partition." >&2
		rm -f "$tmp"
		return 1
	fi
	mbr_add_songs_entry "$tmp" "$start" "$size"
	echo "$start $size" >&3
	cat "$tmp"
	"$@" | tail -c +$(( SECTOR + 1 ))
	rm -f "$tmp"
}
