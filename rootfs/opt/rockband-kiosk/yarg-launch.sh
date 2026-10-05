#!/usr/bin/env bash
# Starts YARG (Linux x86_64 build) under Box64. Run by kiosk-session.sh inside
# cage; can also be run by hand from a desktop/X session for testing.
#   yarg-launch.sh [vulkan|opengl]
set -uo pipefail

RENDERER="${1:-vulkan}"
DISPLAY_MODE=1280x720
# shellcheck source=/dev/null
[ -r /etc/rockband-kiosk/kiosk.conf ] && . /etc/rockband-kiosk/kiosk.conf
# Highway render scale (patches/YARG/0007); only read by the IL2CPP build
[ -z "${YARG_HIGHWAY_SCALE:-}" ] || export YARG_HIGHWAY_SCALE
YARG_DIR=/opt/yarg
DATA_DIR="$HOME/.local/share/yarg"
LOG_DIR="$HOME/.local/state/yarg-kiosk"
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Box64 tuning for Unity games (each can be overridden in kiosk.conf)
export BOX64_LOG=0
export BOX64_NOBANNER=1
export BOX64_DYNAREC_BIGBLOCK="${BOX64_DYNAREC_BIGBLOCK:-2}"
export BOX64_DYNAREC_STRONGMEM="${BOX64_DYNAREC_STRONGMEM:-1}"
export BOX64_DYNAREC_FASTROUND="${BOX64_DYNAREC_FASTROUND:-1}"
export BOX64_DYNAREC_FASTNAN="${BOX64_DYNAREC_FASTNAN:-1}"
export BOX64_DYNAREC_CALLRET="${BOX64_DYNAREC_CALLRET:-1}"

# cage drives the TV at its preferred mode (often 4K) and ignores video= on
# the kernel command line, and YARG's full-screen window always uses the
# desktop size. Switch the output to DISPLAY_MODE before YARG starts.
if [ -n "$DISPLAY_MODE" ] && [ -n "${WAYLAND_DISPLAY:-}" ] && command -v wlr-randr >/dev/null; then
  output="$(wlr-randr | awk '/^[^ ]/ {print $1; exit}')"
  if [ -n "$output" ]; then
    wlr-randr --output "$output" --mode "${DISPLAY_MODE}@60.000000" ||
      echo "yarg-launch: the TV doesn't offer ${DISPLAY_MODE} at 60 Hz; keeping its preferred mode"
  fi
fi

# Unity's player supports Wayland via libdecor, but the x86 Wayland libraries
# are not wrapped by Box64; use Xwayland (provided by cage) instead.
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11

# Resolution follows the display mode (DISPLAY_MODE above); YARG's borderless
# full-screen window ignores -screen-width/-height.
args=(-screen-fullscreen 1 -persistent-data-path "$DATA_DIR" -logFile "$LOG_DIR/player.log")

if [ "$RENDERER" = "vulkan" ]; then
  # Needs the YARG from scripts/build-yarg.sh: the official v0.15.0 release
  # requests a D32_SFLOAT_S8 depth buffer the V3D GPU doesn't offer, so frames
  # fail to render (patches/YARG/0001 falls back to D24_UNORM_S8)
  args+=(-force-vulkan)
else
  # The Pi 5 GPU reports OpenGL 3.1; Unity requires a 3.2+ core profile
  export MESA_GL_VERSION_OVERRIDE=3.3
  export MESA_GLSL_VERSION_OVERRIDE=330
  args+=(-force-glcore)
fi

cd "$YARG_DIR" || exit 1
exec box64 "$YARG_DIR/YARG" "${args[@]}"
