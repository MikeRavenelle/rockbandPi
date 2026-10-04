#!/usr/bin/env bash
# Shows each layer of the controller stack. Run over SSH while plugging
# instruments in one at a time.
set -uo pipefail

echo "=== USB devices ==="
lsusb

echo
echo "=== Kernel drivers ==="
lsmod | grep -E '^(xpad|xone|uhid|hid_generic|hid_sony|hid_playstation)' || echo "(none loaded)"

echo
echo "=== Input devices (what the drivers report) ==="
grep -E '^(N|H):' /proc/bus/input/devices | paste - - | sed 's/N: Name=//; s/H: Handlers=/  -> /'

echo
echo "=== rb-bridge (physical -> virtual) ==="
journalctl -u rb-bridge -b --no-pager -o cat | grep -E '\->|removed' | tail -20

echo
echo "=== hidraw devices (what YARG sees) ==="
for h in /sys/class/hidraw/hidraw*; do
  [ -e "$h" ] || continue
  name=$(grep -m1 HID_NAME "$h/device/uevent" | cut -d= -f2)
  id=$(grep -m1 HID_ID "$h/device/uevent" | cut -d= -f2)
  ver=$(cat "$h"/device/input/input*/id/version 2>/dev/null | head -1)
  printf '/dev/%-8s %-40s id=%s rev=%s\n' "$(basename "$h")" "$name" "$id" "${ver:-?}"
done

echo
echo "=== Microphones ==="
arecord -l 2>/dev/null || echo "arecord not available"
