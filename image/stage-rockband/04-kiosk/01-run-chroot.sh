#!/bin/bash -e
. /tmp/kiosk.env
user="$(getent passwd 1000 | cut -d: -f1)"
home="$(getent passwd 1000 | cut -d: -f6)"

usermod -aG input,video,render,audio "$user"
chown -R "$user:$user" "$home"

# Samba login for the songs share uses the kiosk user's password
printf '%s\n%s\n' "$KIOSK_PASSWORD" "$KIOSK_PASSWORD" | smbpasswd -s -a "$user"

systemctl enable rb-bridge.service rockband-partitions.service
systemctl disable rpi-resize.service 2>/dev/null || true
systemctl set-default multi-user.target

rm -f /tmp/kiosk.env
