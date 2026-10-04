#!/bin/bash -e
# Patched driver sources (see patches/) were staged by scripts/build-image.sh
. ../kiosk.env
rm -rf "${ROOTFS_DIR}/usr/src/xone-${XONE_VERSION}" "${ROOTFS_DIR}/usr/src/xpad-noone-${XPAD_NOONE_VERSION}"
cp -a files/xone "${ROOTFS_DIR}/usr/src/xone-${XONE_VERSION}"
cp -a files/xpad-noone "${ROOTFS_DIR}/usr/src/xpad-noone-${XPAD_NOONE_VERSION}"
sed -i "s/#VERSION#/${XONE_VERSION}/" "${ROOTFS_DIR}/usr/src/xone-${XONE_VERSION}/dkms.conf"
sed -i "s/^PACKAGE_VERSION=.*/PACKAGE_VERSION=\"${XPAD_NOONE_VERSION}\"/" \
	"${ROOTFS_DIR}/usr/src/xpad-noone-${XPAD_NOONE_VERSION}/dkms.conf"
cp ../kiosk.env "${ROOTFS_DIR}/tmp/kiosk.env"
