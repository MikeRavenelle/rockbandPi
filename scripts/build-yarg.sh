#!/usr/bin/env bash
# Builds YARG from source (external/YARG + patches/YARG/) as a Linux x86_64
# IL2CPP player, in containers. Linux and macOS (Windows: scripts/build-yarg.ps1,
# which runs this in WSL).
#
#   scripts/build-yarg.sh
#
# Output: build/yarg/player/ (used by build-image.sh when YARG_SOURCE=local)
# Needs:  git, Podman or Docker, about 25 GB of free disk, and a Unity Personal
#         license file. Activate one by signing in to Unity Hub once; the file is
#         read from the first of:
#           $UNITY_LICENSE_FILE
#           ~/.config/unity3d/Unity/licenses/UnityEntitlementLicense.xml   (Hub 3, Linux)
#           ~/.var/app/com.unity.UnityHub/config/unity3d/Unity/licenses/
#             UnityEntitlementLicense.xml                                (Hub 3, Flatpak)
#           ~/.local/share/unity3d/Unity/Unity_lic.ulf                    (older Hub, Linux)
#           ~/.var/app/com.unity.UnityHub/data/unity3d/Unity/Unity_lic.ulf (older Hub, Flatpak)
#           /Library/Application Support/Unity/Unity_lic.ulf              (macOS)
#         It is only mounted into the build container, never copied or committed.
#         Hub 3 licenses are bound to /etc/machine-id, so they only work from a
#         Linux host.
# Env:    DOCKER=...      container command (default: podman, else docker)
#         UNITY_IMAGE=... Unity editor image (default: GameCI image matching
#                         YARG's Unity version)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/yarg"
UNITY_IMAGE="${UNITY_IMAGE:-docker.io/unityci/editor:ubuntu-6000.3.5f2-linux-il2cpp-3.2.2}"
DOTNET_IMAGE="mcr.microsoft.com/dotnet/sdk:8.0"

if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ] || [ -n "${DISTROBOX_ENTER_PATH:-}" ]; then
	echo "This shell is inside a container (toolbox/distrobox). The build starts its own" >&2
	echo "containers and can't run nested. Run it from a host terminal instead." >&2
	exit 1
fi

if [ -z "${DOCKER:-}" ]; then
	if command -v podman >/dev/null; then
		DOCKER=podman
	elif command -v docker >/dev/null; then
		DOCKER=docker
	else
		echo "Podman or Docker is required." >&2
		exit 1
	fi
fi

license="${UNITY_LICENSE_FILE:-}"
if [ -z "$license" ]; then
	for f in \
		"$HOME/.config/unity3d/Unity/licenses/UnityEntitlementLicense.xml" \
		"$HOME/.var/app/com.unity.UnityHub/config/unity3d/Unity/licenses/UnityEntitlementLicense.xml" \
		"$HOME/.local/share/unity3d/Unity/Unity_lic.ulf" \
		"$HOME/.var/app/com.unity.UnityHub/data/unity3d/Unity/Unity_lic.ulf" \
		"/Library/Application Support/Unity/Unity_lic.ulf"; do
		if [ -f "$f" ]; then
			license="$f"
			break
		fi
	done
fi
if [ -z "$license" ] || [ ! -f "$license" ]; then
	echo "No Unity license file found. Install Unity Hub, sign in and activate a free" >&2
	echo "Personal license, then run this again (or set UNITY_LICENSE_FILE)." >&2
	exit 1
fi
# Unity Hub 3 stores Personal licenses as an entitlement license bound to this
# machine's /etc/machine-id, so the container gets the same machine ID.
# Older Hubs write a Unity_lic.ulf instead.
case "$license" in
	*.xml)
		[ -r /etc/machine-id ] || {
			echo "$license is bound to /etc/machine-id, which this host doesn't have." >&2
			echo "Entitlement licenses only work from a Linux host; use a Unity_lic.ulf instead." >&2
			exit 1
		}
		license_mounts=(
			-v "$license:/root/.config/unity3d/Unity/licenses/UnityEntitlementLicense.xml:ro"
			-v /etc/machine-id:/etc/machine-id:ro
		)
		;;
	*)
		license_mounts=(-v "$license:/root/.local/share/unity3d/Unity/Unity_lic.ulf:ro")
		;;
esac
echo "==> Unity license: $license"

echo "==> Submodules"
git -C "$ROOT" submodule update --init external/YARG
# Unity's project version must match the editor image
unity_version="$(sed -n 's/^m_EditorVersion: //p' "$ROOT/external/YARG/ProjectSettings/ProjectVersion.txt")"
case "$UNITY_IMAGE" in
	*"-$unity_version-"*) ;;
	*)
		echo "YARG needs Unity $unity_version but UNITY_IMAGE is $UNITY_IMAGE." >&2
		echo "Pick the matching tag from https://hub.docker.com/r/unityci/editor/tags" >&2
		exit 1
		;;
esac

mkdir -p "$OUT"
# SELinux hosts (Fedora) would otherwise block the containers from reading the
# mounted repo and license
run=("$DOCKER" run --rm --security-opt label=disable)

echo "==> Preparing the YARG project in $OUT/project"
"${run[@]}" \
	-v "$ROOT:/repo" \
	"$DOTNET_IMAGE" bash /repo/scripts/lib/yarg-prepare.sh

echo "==> Building YARG with Unity $unity_version (IL2CPP; the first build takes an hour or more)"
"${run[@]}" \
	-v "$OUT:/build" \
	-v "$ROOT/scripts/lib/yarg-unity-build.sh:/yarg-unity-build.sh:ro" \
	"${license_mounts[@]}" \
	"$UNITY_IMAGE" bash /yarg-unity-build.sh

echo
echo "YARG player in $OUT/player"
echo "To use it in the image, set YARG_SOURCE=local in config/kiosk.conf and run scripts/build-image.sh"
