#!/usr/bin/env python3
"""Writes the rockband-invisible Xcursor theme (one fully transparent cursor
image, linked under every common cursor name) into the given icons folder.

    make-invisible-cursor.py rootfs/usr/share/icons

Run at image build time; the output is plain files, nothing is kept in git.
"""

import os
import struct
import sys

THEME = "rockband-invisible"
SIZE = 24  # nominal size; matches XCURSOR_SIZE in kiosk-session.sh

# Names used by wlroots/cage, Xwayland, GTK and Unity
NAMES = [
    "default", "left_ptr", "arrow", "top_left_arrow", "pointer", "hand", "hand1",
    "hand2", "pointing_hand", "text", "xterm", "ibeam", "wait", "watch",
    "progress", "left_ptr_watch", "crosshair", "cross", "move", "grab",
    "grabbing", "fleur", "not-allowed", "help", "question_arrow", "context-menu",
    "col-resize", "row-resize", "n-resize", "s-resize", "e-resize", "w-resize",
    "ne-resize", "nw-resize", "se-resize", "sw-resize", "ew-resize", "ns-resize",
    "nesw-resize", "nwse-resize", "all-scroll", "zoom-in", "zoom-out",
    "sb_h_double_arrow", "sb_v_double_arrow", "X_cursor", "pirate",
]


def xcursor_bytes(size):
    """Minimal Xcursor file: one image chunk of size x size transparent pixels."""
    header = struct.pack("<4sIII", b"Xcur", 16, 0x10000, 1)
    image_type = 0xFFFD0002
    toc = struct.pack("<III", image_type, size, 16 + 12)
    chunk = struct.pack("<IIIIIIIII", 36, image_type, size, 1, size, size, 0, 0, 0)
    pixels = b"\x00\x00\x00\x00" * (size * size)
    return header + toc + chunk + pixels


def main():
    icons = sys.argv[1]
    theme_dir = os.path.join(icons, THEME)
    cursors = os.path.join(theme_dir, "cursors")
    os.makedirs(cursors, exist_ok=True)
    with open(os.path.join(theme_dir, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=rockband-invisible\nComment=Transparent cursor for the kiosk\n")
    with open(os.path.join(cursors, "default"), "wb") as f:
        f.write(xcursor_bytes(SIZE))
    for name in NAMES:
        if name == "default":
            continue
        link = os.path.join(cursors, name)
        if os.path.lexists(link):
            os.remove(link)
        os.symlink("default", link)


if __name__ == "__main__":
    main()
