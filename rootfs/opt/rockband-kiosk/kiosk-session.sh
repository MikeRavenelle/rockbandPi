#!/usr/bin/env bash
# Started from the kiosk user's ~/.bash_profile after autologin on tty1.
# Runs YARG fullscreen in cage and relaunches it if it crashes. Quit in YARG
# powers off (or restarts YARG, see ON_QUIT in /etc/rockband-kiosk/kiosk.conf).
#
# Escape hatch: over SSH, `touch ~/.kiosk-disable` and reboot.
set -uo pipefail

YARG_RENDERER=vulkan
ON_QUIT=poweroff
# shellcheck source=/dev/null
[ -r /etc/rockband-kiosk/kiosk.conf ] && . /etc/rockband-kiosk/kiosk.conf

[ -e "$HOME/.kiosk-disable" ] && { echo "Kiosk disabled (~/.kiosk-disable exists)."; exit 0; }

# Fully transparent cursor theme: no mouse pointer on the TV
export XCURSOR_THEME=rockband-invisible
export XCURSOR_SIZE=24

LOG_DIR="$HOME/.local/state/yarg-kiosk"
mkdir -p "$LOG_DIR"
log() { echo "$(date -Is) $*" >>"$LOG_DIR/session.log"; }
display_connected() { grep -qx connected /sys/class/drm/card*-HDMI-A-*/status 2>/dev/null; }

renderer="$YARG_RENDERER"
quick_crashes=0
while true; do
  log "starting YARG (renderer=$renderer)"
  start=$(date +%s)
  cage -s -- /opt/rockband-kiosk/yarg-launch.sh "$renderer" >>"$LOG_DIR/session.log" 2>&1
  code=$?
  log "YARG exited with code $code"

  # Unplugging the TV (or a TV that drops HDMI when turned off) closes YARG's
  # window, and YARG then exits cleanly as if Quit was chosen. Don't power off
  # for that: wait for a display and start YARG again.
  if [ "$code" -eq 0 ] && ! display_connected; then
    log "YARG exited while no display is connected; waiting for one"
    until display_connected; do sleep 2; done
    quick_crashes=0
    continue
  fi

  if [ "$code" -eq 0 ]; then
    if [ "$ON_QUIT" = "poweroff" ]; then
      exec sudo /usr/bin/systemctl poweroff
    fi
    quick_crashes=0
    continue
  fi

  if [ $(( $(date +%s) - start )) -lt 30 ]; then
    quick_crashes=$((quick_crashes + 1))
  else
    quick_crashes=0
  fi

  # If Vulkan was chosen and keeps crashing, fall back to OpenGL once
  if [ "$quick_crashes" -ge 2 ] && [ "$renderer" = "vulkan" ]; then
    log "YARG keeps crashing on Vulkan; switching to OpenGL"
    renderer=opengl
    quick_crashes=0
  elif [ "$quick_crashes" -ge 5 ]; then
    log "YARG crashed 5 times in a row; giving up. Logs: $LOG_DIR"
    echo "YARG failed to start. Logs are in $LOG_DIR"
    exit 1
  fi
  sleep 2
done
