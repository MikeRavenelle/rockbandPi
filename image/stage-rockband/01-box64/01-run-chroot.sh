#!/bin/bash -e
# Build Box64 (x86_64 emulator) with Raspberry Pi 5 tuning from the pinned
# submodule source copied in by 00-run.sh.
cd /usr/src/box64
cmake -S . -B build -D RPI5ARM64=1 -D CMAKE_BUILD_TYPE=RelWithDebInfo
make -C build -j"$(nproc)"
make -C build install
rm -rf /usr/src/box64
box64 --version
