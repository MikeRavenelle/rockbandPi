#!/bin/bash -e
# Install YARG (the pinned release, or with YARG_SOURCE=local the IL2CPP build
# from scripts/build-yarg.sh) plus the x86_64 libraries it loads that Box64
# does not wrap natively (hidapi).
. ../kiosk.env

dl="$(mktemp -d)"
trap 'rm -rf "$dl"' EXIT

rm -rf "${ROOTFS_DIR}/opt/yarg"
mkdir -p "${ROOTFS_DIR}/opt/yarg"
if [ "${YARG_SOURCE}" = "local" ]; then
	cp -a files/yarg/. "${ROOTFS_DIR}/opt/yarg/"
else
	zip="YARG_${YARG_VERSION}-Linux-x86_64.zip"
	curl -fsSL --retry 3 -o "$dl/$zip" \
		"https://github.com/YARC-Official/YARG/releases/download/${YARG_VERSION}/${zip}"
	echo "${YARG_SHA256}  $dl/$zip" | sha256sum -c -
	bsdtar -xf "$dl/$zip" -C "${ROOTFS_DIR}/opt/yarg"
fi
chmod +x "${ROOTFS_DIR}/opt/yarg/YARG"

# libhidapi-hidraw0 (amd64) from the Debian release the image is built on.
# HIDrogen dlopens libhidapi-hidraw.so.0; Box64 runs it emulated and wraps
# its libudev calls natively.
mirror="http://deb.debian.org/debian"
curl -fsSL --retry 3 "$mirror/dists/${RELEASE}/main/binary-amd64/Packages.xz" | xz -dc > "$dl/Packages"
read -r deb_path deb_sha < <(awk '
	/^Package: /{p = ($2 == "libhidapi-hidraw0")}
	p && /^Filename: /{f = $2}
	p && /^SHA256: /{s = $2}
	/^$/{ if (p && f) { print f, s; exit } p = 0 }' "$dl/Packages")
[ -n "$deb_path" ] || { echo "libhidapi-hidraw0 (amd64) not found in Debian ${RELEASE}" >&2; exit 1; }
curl -fsSL --retry 3 -o "$dl/hidapi.deb" "$mirror/$deb_path"
echo "$deb_sha  $dl/hidapi.deb" | sha256sum -c -
dpkg-deb -x "$dl/hidapi.deb" "$dl/hidapi"

x86_libs="${ROOTFS_DIR}/usr/lib/box64-x86_64-linux-gnu"
mkdir -p "$x86_libs"
cp -a "$dl"/hidapi/usr/lib/x86_64-linux-gnu/libhidapi-hidraw.so.0* "$x86_libs/"
