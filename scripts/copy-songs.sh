#!/usr/bin/env bash
# Copies ./songs onto the kiosk's SONGS partition, for adding songs after the
# card was flashed (flash-sd.sh already copies them the first time). Linux and
# macOS (Windows: scripts/copy-songs.ps1). Only new or changed files are
# copied and nothing on the card is deleted.
#
#   scripts/copy-songs.sh                       # card in this computer (auto-detects SONGS)
#   scripts/copy-songs.sh /Volumes/SONGS        # card mounted somewhere specific
#   scripts/copy-songs.sh rockband@rockband.local   # over the network (SSH)
#
# Second argument: songs folder (default ./songs). After copying over the
# network, refresh the library in YARG (Settings > Songs).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-}"
SONGS="${2:-$ROOT/songs}"

[ -d "$SONGS" ] || { echo "Songs folder $SONGS not found." >&2; exit 1; }

if [ -z "$DEST" ]; then
	for d in /Volumes/SONGS "/run/media/${USER:-}/SONGS" "/media/${USER:-}/SONGS" /media/SONGS; do
		[ -d "$d" ] && { DEST="$d"; break; }
	done
	[ -n "$DEST" ] || {
		echo "No SONGS volume found. Insert the card," >&2
		echo "or pass a destination: a mount point or user@host for the network." >&2
		exit 1
	}
fi

case "$DEST" in
	*@*)
		echo "Copying $SONGS -> $DEST:/srv/songs (over SSH)"
		# exFAT has no Unix permissions or owners, and 2-second timestamps
		rsync -rt --size-only --exclude /README.md --progress "$SONGS/" "$DEST:/srv/songs/"
		;;
	*)
		[ -d "$DEST" ] || { echo "$DEST is not a directory." >&2; exit 1; }
		echo "Copying $SONGS -> $DEST"
		rsync -rt --size-only --exclude /README.md --progress "$SONGS/" "$DEST/"
		sync
		echo "Done. Eject the card before removing it."
		;;
esac
