#!/bin/bash -e
. /tmp/kiosk.env
user="$(getent passwd 1000 | cut -d: -f1)"
home="$(getent passwd 1000 | cut -d: -f6)"

usermod -aG input,video,render,audio "$user"
chown -R "$user:$user" "$home"
# YARG writes into its own folder (song source icons, genre mappings)
chown -R "$user:$user" /opt/yarg

# Transparent cursor theme so no mouse pointer shows on the TV
python3 /tmp/make-invisible-cursor.py /usr/share/icons
rm -f /tmp/make-invisible-cursor.py

# Samba login for the songs share uses the kiosk user's password
printf '%s\n%s\n' "$KIOSK_PASSWORD" "$KIOSK_PASSWORD" | smbpasswd -s -a "$user"

systemctl enable rb-bridge.service rockband-partitions.service
systemctl disable rpi-resize.service 2>/dev/null || true
systemctl set-default multi-user.target

rm -f /tmp/kiosk.env
