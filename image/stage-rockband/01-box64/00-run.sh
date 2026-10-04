#!/bin/bash -e
rm -rf "${ROOTFS_DIR}/usr/src/box64"
cp -a files/box64 "${ROOTFS_DIR}/usr/src/box64"
