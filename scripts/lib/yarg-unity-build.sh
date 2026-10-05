#!/usr/bin/env bash
# Runs inside the GameCI Unity editor container (started by
# scripts/build-yarg.sh) with build/yarg mounted at /build and the Unity
# license file mounted read-only. Builds the Linux x86_64 IL2CPP player into
# /build/player.
set -euo pipefail

# YARG stamps its version from git during the build; the project is owned by
# the host user
if command -v git >/dev/null; then
	git config --global --add safe.directory '*'
fi

rm -rf /build/player
mkdir -p /build/player

unity-editor -batchmode -nographics -quit -logFile - \
	-projectPath /build/project \
	-buildTarget Linux64 \
	-executeMethod Editor.LinuxIl2cppBuild.Build \
	-yargBuildPath /build/player/YARG

[ -x /build/player/YARG ] || { echo "Unity finished but /build/player/YARG is missing" >&2; exit 1; }
