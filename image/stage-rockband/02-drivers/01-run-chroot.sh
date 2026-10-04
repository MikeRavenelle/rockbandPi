#!/bin/bash -e
# Build the out-of-tree drivers with DKMS for the 4K-page Pi kernel (kernel8.img).
# DKMS rebuilds them automatically when the kernel package is upgraded.
. /tmp/kiosk.env

KVER=$(find /lib/modules -mindepth 1 -maxdepth 1 -name '*-rpi-v8' -printf '%f\n' | sort -V | tail -1)
[ -n "$KVER" ] || { echo "No rpi-v8 kernel found in /lib/modules" >&2; exit 1; }
echo "Building drivers for kernel $KVER"

for mod in "xone/${XONE_VERSION}" "xpad-noone/${XPAD_NOONE_VERSION}"; do
	dkms add "$mod" || true
	dkms build "$mod" -k "$KVER"
	dkms install "$mod" -k "$KVER" --force
done

# Xbox Wireless Adapter firmware (downloaded from Microsoft, hash-checked)
cd "/usr/src/xone-${XONE_VERSION}"
bash install/firmware.sh --skip-disclaimer
rm -f driver.cab

rm -f /tmp/kiosk.env
