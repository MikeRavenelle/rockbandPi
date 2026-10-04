# Put your songs here

Copy your song library into this folder. Everything here except this README is
git-ignored, so songs are never committed.

Any layout works: YARG scans every subfolder. For example:

```
songs/
├── Rock Band 1/
│   └── Artist - Song/        <- extracted song: song.ini + notes.mid + .ogg stems
├── Rock Band 2/
├── Rock Band 3/
├── Rock Band 4/
│   └── Artist - Song         <- Xbox 360 CON package (single file, no extension)
└── DLC/
```

Supported formats include extracted song folders (`song.ini`/`songs.dta` +
`notes.mid` + audio), Xbox 360 CON/LIVE packages, and `.sng` files.

The flash and copy scripts in `scripts/` copy this folder onto the SD card's
`SONGS` partition (or over the network). On the Pi it appears at `/srv/songs`.
