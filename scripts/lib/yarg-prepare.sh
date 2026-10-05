#!/usr/bin/env bash
# Runs inside a .NET SDK container (started by scripts/build-yarg.sh) with the
# repo mounted at /repo. Prepares /repo/build/yarg/project for Unity:
#   - a git checkout of the commit external/YARG is pinned to (a real repo, so
#     YARG's build can stamp its version from git)
#   - Git LFS files (textures, meshes, fonts)
#   - patches/YARG/ and patches/YARG.Core/ applied
#   - NuGet packages restored (YARG doesn't commit them), with ManagedBass
#     fixed for IL2CPP by patches/ManagedBass/
# Unity's Library/ folder is kept between runs, so later builds are faster.
set -euo pipefail

SRC=/repo/external/YARG
PROJ=/repo/build/yarg/project
UPSTREAM=https://github.com/YARC-Official/YARG.git

echo "    installing git-lfs"
apt-get update -qq
apt-get install -y -qq git git-lfs >/dev/null
git config --global --add safe.directory '*'
git config --global advice.detachedHead false

commit="$(git -C "$SRC" rev-parse HEAD)"
echo "    YARG $(git -C "$SRC" describe --tags --always) ($commit)"

if [ ! -d "$PROJ/.git" ]; then
	git clone -q --no-checkout "$SRC" "$PROJ"
fi
# LFS objects come from GitHub, not from the local submodule
git -C "$PROJ" remote set-url origin "$UPSTREAM"
git -C "$PROJ" fetch -q "$SRC" "$commit"
git -C "$PROJ" checkout -q -f "$commit"
# Keep Unity's import cache and the restored NuGet packages
git -C "$PROJ" clean -q -ffdx -e /Library -e /Assets/Packages -e /Assets/Packages.meta

echo "    fetching LFS files"
git -C "$PROJ" lfs install --local >/dev/null
git -C "$PROJ" lfs pull
# Hosts without git-lfs would otherwise fail on any git command in the project
git -C "$PROJ" lfs uninstall --local >/dev/null

echo "    fetching YARG.Core"
git -C "$PROJ" submodule update -q --init --force

for p in /repo/patches/YARG/*.patch; do
	[ -e "$p" ] || continue
	echo "    YARG: $(basename "$p")"
	git -C "$PROJ" apply "$p"
done
# YARG.Core is a submodule of YARG, so its patches apply inside it
for p in /repo/patches/YARG.Core/*.patch; do
	[ -e "$p" ] || continue
	echo "    YARG.Core: $(basename "$p")"
	git -C "$PROJ/YARG.Core" apply "$p"
done

echo "    restoring NuGet packages"
dotnet tool install -v q --tool-path /tmp/nugetforunity NuGetForUnity.Cli >/dev/null
/tmp/nugetforunity/nugetforunity restore "$PROJ"

# ManagedBass is a prebuilt NuGet DLL; patches/ManagedBass/ is a small tool
# that fixes it for IL2CPP (see Program.cs there)
echo "    ManagedBass: IL2CPP callback fix"
cp -r /repo/patches/ManagedBass /tmp/managedbass-fix
dotnet run -v q --project /tmp/managedbass-fix -- "$PROJ"/Assets/Packages/ManagedBass.*/lib/net45/ManagedBass.dll
