#!/bin/bash

# -----------------------------
# Gluetun Watchdog Script
# -----------------------------

# Load variables
source /share/homes/manfred/scripts/gluetun_watchdog/gluetun_watchdog.env

# -----------------------------
# Log rotation
# -----------------------------
rotate_log() {
  if [ -f "$LOGFILE" ] && [ $(stat -c%s "$LOGFILE") -ge "$MAX_LOG_SIZE" ]; then
    mv "$LOGFILE" "${LOGFILE}_$(date '+%Y%m%d_%H%M%S')"
    touch "$LOGFILE"
  fi

  if [ "${CLEANUP_OLD_LOGS,,}" = "true" ]; then
    # Keep only the most recent $MAX_LOG_FILES rotated logs
    ls -1t "${LOGFILE}"_* 2>/dev/null | tail -n +"$((MAX_LOG_FILES+1))" | xargs -r rm
  fi
}

rotate_log

# -----------------------------
# Hardened PATH function
# -----------------------------
add_to_path() {
  cmd="$1"
  dir=$(dirname "$(command -v "$cmd" 2>/dev/null || echo '')")
  if [ -n "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
    PATH="$dir:$PATH"
  fi
}

# Add all required commands
for cmd in docker ping cat grep sleep date stat mv touch tail xargs rm; do
  add_to_path "$cmd"
done

# -----------------------------
# Logging function
# -----------------------------
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"
}

# -----------------------------
# Fail count functions
# -----------------------------
get_failcount() {
  if [ -f "$STATEFILE" ]; then
    cat "$STATEFILE"
  else
    echo 0
  fi
}

set_failcount() {
  echo "$1" > "$STATEFILE"
}

# -----------------------------
# Ping check
# -----------------------------
check_internet() {
  docker exec -t "$GLUETUN_CONTAINER" ping -c "$PING_COUNT" "$PING_TARGET" >/dev/null 2>&1
  return $?
}

# -----------------------------
# Watchdog logic
# -----------------------------
log "Starting Gluetun watchdog check..."

if check_internet; then
  log "Gluetun VPN is up and internet reachable."
  set_failcount 0
  exit 0
fi

failcount=$(get_failcount)
failcount=$((failcount + 1))
set_failcount "$failcount"

log "Gluetun VPN check failed ($failcount/$MAX_FAILURES). Current fail count: $failcount, Max allowed failures: $MAX_FAILURES."

if [ "$failcount" -lt "$MAX_FAILURES" ]; then
  log "Failure threshold not reached yet. No action taken."
  exit 1
fi

log "Failure threshold reached. Stopping Gluetun container..."
set_failcount 0

docker stop "$GLUETUN_CONTAINER" >> "$LOGFILE" 2>&1
log "Starting Gluetun container..."
docker start "$GLUETUN_CONTAINER" >> "$LOGFILE" 2>&1

log "Sleeping $SLEEP_AFTER_START seconds for VPN to initialize..."
sleep "$SLEEP_AFTER_START"

# -----------------------------
# Run remove/recreate scripts
# -----------------------------
if [ -x "$REMOVE_SCRIPT" ]; then
  log "===== BEGIN remove_gluetun_containers.sh ====="
  "$REMOVE_SCRIPT" >> "$LOGFILE" 2>&1
  log "===== END remove_gluetun_containers.sh ====="
else
  log "ERROR: Remove script not executable: $REMOVE_SCRIPT"
fi

if [ -x "$RECREATE_SCRIPT" ]; then
  log "===== BEGIN recreate_gluetun_containers.sh ====="
  "$RECREATE_SCRIPT" >> "$LOGFILE" 2>&1
  log "===== END recreate_gluetun_containers.sh ====="
else
  log "ERROR: Recreate script not executable: $RECREATE_SCRIPT"
fi

log "Gluetun recovery sequence finished."
