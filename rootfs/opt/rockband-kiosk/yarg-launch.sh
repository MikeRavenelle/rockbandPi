#!/usr/bin/env bash
# Starts YARG (Linux x86_64 build) under Box64. Run by kiosk-session.sh inside
# cage; can also be run by hand from a desktop/X session for testing.
#   yarg-launch.sh [vulkan|opengl]
set -uo pipefail

RENDERER="${1:-vulkan}"
YARG_DIR=/opt/yarg
DATA_DIR="$HOME/.local/share/yarg"
LOG_DIR="$HOME/.local/state/yarg-kiosk"
mkdir -p "$DATA_DIR" "$LOG_DIR"

# Box64 tuning for Unity/Mono games
export BOX64_LOG=0
export BOX64_NOBANNER=1
export BOX64_DYNAREC_BIGBLOCK=2
export BOX64_DYNAREC_STRONGMEM=1
export BOX64_DYNAREC_FASTROUND=1
export BOX64_DYNAREC_FASTNAN=1
export BOX64_DYNAREC_CALLRET=1

# Unity's player supports Wayland via libdecor, but the x86 Wayland libraries
# are not wrapped by Box64; use Xwayland (provided by cage) instead.
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11

args=(-screen-fullscreen 1 -persistent-data-path "$DATA_DIR" -logFile "$LOG_DIR/player.log")
if [ "$RENDERER" = "opengl" ]; then
  # The Pi 5 GPU reports OpenGL 3.1; Unity requires a 3.2+ core profile
  export MESA_GL_VERSION_OVERRIDE=3.3
  export MESA_GLSL_VERSION_OVERRIDE=330
  args+=(-force-glcore)
else
  args+=(-force-vulkan)
fi

cd "$YARG_DIR" || exit 1
exec box64 "$YARG_DIR/YARG" "${args[@]}"
