#!/usr/bin/env bash
# Checks the SONGS partition-table patch used by scripts/flash-sd.sh, using a
# sparse file as a fake 64 GB card. Needs sfdisk (util-linux); no root.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../scripts/lib/songs-partition.sh
. "$ROOT/scripts/lib/songs-partition.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Fake pi-gen image: 512 MB FAT boot + 6 GB ext4 root, like the real layout
truncate -s 6700M "$work/image.img"
sfdisk -q "$work/image.img" <<'EOF'
label: dos
label-id: 0x1234abcd
start=16384, size=1048576, type=c
start=1064960, size=12582912, type=83
EOF
printf 'IMAGE-PAYLOAD' | dd of="$work/image.img" bs=1 seek=4096 conv=notrunc 2>/dev/null

card_sectors=$(( 64 * 1024 * 1024 * 2 ))
truncate -s 64G "$work/card.img"
patched_image_stream "$card_sectors" cat "$work/image.img" 3>"$work/extent" |
	dd of="$work/card.img" bs=4M conv=notrunc 2>/dev/null

fail() { echo "FAIL: $*" >&2; sfdisk -l "$work/card.img" >&2; exit 1; }

read -r start size < "$work/extent"
expected_start=$(( 1064960 + 16 * 1024 * 1024 * 2 ))
[ "$start" -eq "$expected_start" ] || fail "SONGS start $start, expected $expected_start"
[ $(( start % 2048 )) -eq 0 ] || fail "SONGS start not 1 MiB aligned"
[ $(( start + size )) -le "$card_sectors" ] || fail "SONGS runs past the end of the card"

dump="$(sfdisk --dump "$work/card.img")"
grep -q 'label-id: 0x1234abcd' <<<"$dump" || fail "disk identifier changed (would break PARTUUID boot)"
grep -q "card.img1 : start=       16384, size=     1048576, type=c" <<<"$dump" || fail "boot partition changed"
grep -q "card.img2 : start=     1064960, size=    12582912, type=83" <<<"$dump" || fail "root partition changed"
grep -q "card.img3 : start= *$start, size= *$size, type=7" <<<"$dump" || fail "SONGS entry wrong"
cmp -s <(dd if="$work/card.img" bs=1 skip=4096 count=13 2>/dev/null) <(printf 'IMAGE-PAYLOAD') ||
	fail "image data after the MBR was not written intact"

# --skip-songs: the card's SONGS entry must match what a new image would write
[ "$(mbr_songs_entry "$work/card.img")" = "07 $start $size" ] ||
	fail "SONGS entry reads back as '$(mbr_songs_entry "$work/card.img")', expected '07 $start $size'"
other=$(( 128 * 1024 * 1024 * 2 ))
[ "07 $(songs_extent "$work/image.img" "$other")" != "07 $start $size" ] ||
	fail "a card of a different size matched this card's SONGS entry"

# --skip-songs: re-flashing a new image must leave the songs untouched
printf 'SONGS-DATA' | dd of="$work/card.img" bs=512 seek="$start" conv=notrunc 2>/dev/null
printf 'NEW-IMAGE-PAYLOAD' | dd of="$work/image.img" bs=1 seek=4096 conv=notrunc 2>/dev/null
patched_image_stream "$card_sectors" cat "$work/image.img" 3>/dev/null |
	dd of="$work/card.img" bs=4M conv=notrunc 2>/dev/null
cmp -s <(dd if="$work/card.img" bs=512 skip="$start" count=1 2>/dev/null | head -c 10) <(printf 'SONGS-DATA') ||
	fail "re-flashing the image overwrote the songs"
cmp -s <(dd if="$work/card.img" bs=1 skip=4096 count=17 2>/dev/null) <(printf 'NEW-IMAGE-PAYLOAD') ||
	fail "re-flashing did not write the new image"

# An 8 GB card has no room for the 16 GB system area plus SONGS: must refuse
small=$(( 8 * 1024 * 1024 * 2 ))
if patched_image_stream "$small" cat "$work/image.img" 3>/dev/null >/dev/null 2>&1; then
	fail "an 8 GB card was accepted"
fi

echo "OK: SONGS at sector $start ($(( size / 2 / 1024 / 1024 )) GiB), boot/root untouched, disk id kept, re-flash keeps songs"
