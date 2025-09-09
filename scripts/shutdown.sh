#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
WAKE_HOUR=6
WAKE_MIN=30
CONFIRM_TIMEOUT=300   # seconds (5 minutes)

# Try to discover the currently active GUI user (Wayland/X11).
# Fallback to a specific username by setting GUI_USER="yourname" if needed.
GUI_USER="$(loginctl list-sessions --no-legend | awk '$5=="yes"{print $3; exit}')"
if [[ -z "${GUI_USER:-}" ]]; then
  # Fallback to the most recent non-root user on seat0 or display :0
  GUI_USER="$(who | awk '$2 ~ /:0/ {print $1; exit}')"
fi
if [[ -z "${GUI_USER:-}" || "${GUI_USER}" == "root" ]]; then
  # Last-resort fallback: set this to your desktop username if auto-detect fails.
  GUI_USER="$(getent passwd 1000 | cut -d: -f1 || true)"
fi

if [[ -z "${GUI_USER}" || "${GUI_USER}" == "root" ]]; then
  echo "ERROR: Could not determine a GUI user. Set GUI_USER in this script." >&2
  exit 1
fi

GUI_UID="$(id -u "${GUI_USER}")"

# Build DBUS path for the user session bus so zenity can show a window
DBUS_ADDR="unix:path=/run/user/${GUI_UID}/bus"

# Check RTC clock mode to use correct rtcwake flag (-u vs -l)
RTC_MODE_FLAG="-u"
if grep -q '^LOCAL' /etc/adjtime 2>/dev/null; then
  RTC_MODE_FLAG="-l"
fi

# Compute next 6:30 am (local time) epoch seconds
now_epoch="$(date +%s)"
today_target_epoch="$(date -d "$(date +%F) ${WAKE_HOUR}:${WAKE_MIN}:00" +%s)"
if (( now_epoch < today_target_epoch )); then
  wake_epoch="${today_target_epoch}"
else
  wake_epoch="$(date -d "tomorrow ${WAKE_HOUR}:${WAKE_MIN}:00" +%s)"
fi

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a /var/log/rtcwake-nightly.log; }

log "Preparing nightly shutdown check for GUI user: ${GUI_USER} (UID ${GUI_UID}). Wake at: $(date -d "@${wake_epoch}")"

# Show confirmation dialog (auto-accept after timeout to proceed with shutdown)
# Exit codes: 0=OK, 1=Cancel, 5=Timeout (for zenity --question)
ZENITY_CMD=(sudo -u "${GUI_USER}" env DISPLAY=":0" DBUS_SESSION_BUS_ADDRESS="${DBUS_ADDR}"
  zenity --question --title="Nightly Shutdown" --timeout="${CONFIRM_TIMEOUT}"
  --text="The system will shut down at 10:00 pm.\n\nClick **Cancel** to keep it on.\n\nIf you do nothing, it will power off and wake at $(date -d "@${wake_epoch}" '+%I:%M %p').\n\nProceed to shut down now?")

if "${ZENITY_CMD[@]}"; then
  RESP=0
else
  RESP=$?
fi

case "${RESP}" in
  1)
    log "User CANCELLED shutdown."
    exit 0
    ;;
  0|5)
    # 0: user clicked OK (shutdown now). 5: dialog timed out -> proceed.
    log "Proceeding with shutdown; scheduling RTC wake at $(date -d "@${wake_epoch}")"

    # Set RTC alarm without sleeping now (program the alarm)
    rtcwake ${RTC_MODE_FLAG} -m no -t "${wake_epoch}" || {
      log "ERROR: Failed to program RTC alarm."
      exit 1
    }

    # Power off cleanly
    systemctl poweroff
    ;;
  *)
    log "Unexpected zenity exit code: ${RESP}. Aborting."
    exit 1
    ;;
esac
