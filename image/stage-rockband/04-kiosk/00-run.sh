#!/bin/bash -e
# Kiosk: overlay files, input bridge, autologin into YARG, boot tweaks.
. ../kiosk.env

# Repository files (rootfs/ overlay and the bridge) staged by build-image.sh
cp -a files/rootfs/. "${ROOTFS_DIR}/"
mkdir -p "${ROOTFS_DIR}/opt/rockband-kiosk/bridge"
cp -a files/bridge/rb-bridge files/bridge/rb_bridge "${ROOTFS_DIR}/opt/rockband-kiosk/bridge/"
chmod 0755 "${ROOTFS_DIR}"/opt/rockband-kiosk/*.sh "${ROOTFS_DIR}/opt/rockband-kiosk/bridge/rb-bridge"
cp files/make-invisible-cursor.py "${ROOTFS_DIR}/tmp/"

user="${FIRST_USER_NAME}"
home="${ROOTFS_DIR}/home/${user}"

# Autologin on tty1
mkdir -p "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d"
cat > "${ROOTFS_DIR}/etc/systemd/system/getty@tty1.service.d/autologin.conf" <<UNIT
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${user} --noclear %I \$TERM
UNIT

# Start the kiosk from the physical console only (never over SSH)
cat >> "${home}/.profile" <<'PROFILE'

# rockband-kiosk
if [ -z "${SSH_CONNECTION:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
	/opt/rockband-kiosk/kiosk-session.sh
fi
PROFILE

# No mouse pointer on the TV: cage loads the cursor theme named "default", so
# point the kiosk user's default theme at the transparent one
mkdir -p "${home}/.icons/default"
printf '[Icon Theme]\nInherits=rockband-invisible\n' > "${home}/.icons/default/index.theme"

# YARG settings: point it at the song library, skip first-run dialogs, and
# start with the lightest graphics settings, since YARG runs under emulation.
# Each setting is stored as its plain value; YARG fills in defaults for the
# rest. VenueRenderingQuality 5 = UltraPerformance, VenueAntiAliasing 0 = None.
# Resolution: YARG renders at this size and scales up to the TV (unset = the
# TV's native resolution, 4K on many TVs, far too heavy under emulation).
resolution_json=""
case "${YARG_RESOLUTION}" in
	*x*)
		resolution_json="  \"Resolution\": { \"width\": ${YARG_RESOLUTION%x*}, \"height\": ${YARG_RESOLUTION#*x}, \"refreshRateRatio\": { \"numerator\": 60, \"denominator\": 1 } },"
		;;
esac
mkdir -p "${home}/.local/share/yarg"
cat > "${home}/.local/share/yarg/settings.json" <<JSON
{
  "SongFolders": ["${SONGS_DIR}"],
  "ShowAntiPiracyDialog": false,
${resolution_json}
  "LowQuality": true,
  "FpsStats": true,
  "VSync": false,
  "FpsCap": 60,
  "VenueFpsCap": 30,
  "VenueRenderingQuality": 5,
  "VenueAntiAliasing": 0,
  "VenuePostProcessing": false,
  "DisableBloom": true,
  "DisableFilmGrain": true,
  "DisableDefaultBackground": true,
  "DisableGlobalBackgrounds": true,
  "DisablePerSongBackgrounds": true
}
JSON

# Quit in YARG powers off without a password prompt
echo "${user} ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff" > "${ROOTFS_DIR}/etc/sudoers.d/rockband-kiosk"
chmod 0440 "${ROOTFS_DIR}/etc/sudoers.d/rockband-kiosk"

# Song library: exFAT partition labelled SONGS (created on first boot by
# rockband-partitions.service, or by scripts/flash-sd.sh on Linux)
mkdir -p "${ROOTFS_DIR}${SONGS_DIR}"
if ! grep -q 'LABEL=SONGS' "${ROOTFS_DIR}/etc/fstab"; then
	echo "LABEL=SONGS  ${SONGS_DIR}  exfat  defaults,nofail,uid=1000,gid=1000,umask=022,x-systemd.device-timeout=5s  0  0" \
		>> "${ROOTFS_DIR}/etc/fstab"
fi

# Samba share for copying songs over the network
sed -i "s/__KIOSK_USER__/${user}/g" "${ROOTFS_DIR}/etc/samba/smb.conf.d/rockband-songs.conf"
grep -q 'rockband-songs.conf' "${ROOTFS_DIR}/etc/samba/smb.conf" ||
	printf '\ninclude = /etc/samba/smb.conf.d/rockband-songs.conf\n' >> "${ROOTFS_DIR}/etc/samba/smb.conf"
cp ../kiosk.env "${ROOTFS_DIR}/tmp/kiosk.env"

# Boot: 4K-page kernel (Box64 does not run on the default 16K-page Pi 5
# kernel), no rainbow splash, quiet console
cfg="${ROOTFS_DIR}/boot/firmware/config.txt"
if ! grep -q '^# rockband-kiosk' "$cfg"; then
	cat >> "$cfg" <<CFG

# rockband-kiosk
[pi5]
kernel=kernel8.img
[all]
disable_splash=1
CFG
fi
cmdline="${ROOTFS_DIR}/boot/firmware/cmdline.txt"
# The stock first-boot resize would give the whole card to the system
# partition; rockband-partitions.service sizes it and adds SONGS instead.
sed -i 's/ resize\b//' "$cmdline"
for opt in quiet loglevel=3 logo.nologo vt.global_cursor_default=0 consoleblank=0; do
	grep -qw -- "$opt" "$cmdline" || sed -i "1 s/\$/ ${opt}/" "$cmdline"
done

# Optional Wi-Fi (NetworkManager)
if [ -n "${WIFI_SSID}" ]; then
	nm="${ROOTFS_DIR}/etc/NetworkManager/system-connections/kiosk-wifi.nmconnection"
	mkdir -p "$(dirname "$nm")"
	cat > "$nm" <<NM
[connection]
id=kiosk-wifi
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PSK}

[ipv4]
method=auto

[ipv6]
method=auto
NM
	chmod 0600 "$nm"
fi
