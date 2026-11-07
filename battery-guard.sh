#!/data/data/com.termux/files/usr/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${BATTERY_GUARD_CONFIG:-$SCRIPT_DIR/config.conf}"
STATE_DIR="${HOME}/.battery-guard"
STATE_FILE="${STATE_DIR}/state"
LOG_FILE="${STATE_DIR}/battery.log"
PID_FILE="${STATE_DIR}/battery-guard.pid"

mkdir -p "$STATE_DIR"

LOW_THRESHOLD=20
HIGH_THRESHOLD=80
CHECK_INTERVAL=60
HYSTERESIS=5
SERVER_MODE=false
ON_LOW_COMMAND=""
ENABLE_LOG=true
NOTIFY_ON_LOW=true
NOTIFY_ON_HIGH=true

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

C_RED='\033[0;31m'; C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'; C_BLUE='\033[0;34m'; C_RESET='\033[0m'

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo -e "${C_RED}[error]${C_RESET} '$1' not found. Install: pkg install $2"
        exit 1
    }
}

die() { echo -e "${C_RED}[error]${C_RESET} $*" >&2; exit 1; }
get_state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo "idle"; }
set_state() { echo "$1" > "$STATE_FILE"; }

notify() {
    command -v termux-notification >/dev/null 2>&1 || return 0
    termux-notification --title "$1" --content "$2" --priority "${3:-default}" >/dev/null 2>&1 || true
}

read_battery() {
    local json
    json="$(termux-battery-status 2>/dev/null)" || return 1
    [ -z "$json" ] && return 1
    PERCENTAGE=$(printf '%s' "$json" | jq -r '.percentage // empty')
    PLUGGED=$(printf '%s' "$json" | jq -r '.plugged // empty')
    STATUS=$(printf '%s' "$json" | jq -r '.status // empty')
    TEMPERATURE=$(printf '%s' "$json" | jq -r '.temperature // empty')
    CURRENT=$(printf '%s' "$json" | jq -r '.current // empty')
    [ -z "$PERCENTAGE" ] && return 1
    return 0
}

write_log() {
    [ "$ENABLE_LOG" = true ] || return 0
    printf '%s,%s,%s,%s,%s,%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "$PERCENTAGE" "$STATUS" "$PLUGGED" "$TEMPERATURE" "$CURRENT" >> "$LOG_FILE"
}

is_charging() { [ "$PLUGGED" != "UNPLUGGED" ]; }

check_once() {
    if ! read_battery; then
        echo -e "${C_YELLOW}[warn]${C_RESET} cannot read battery."
        return 1
    fi
    local state charging=false
    state=$(get_state)
    is_charging && charging=true

    if [ "$charging" = false ] && [ "$PERCENTAGE" -le "$LOW_THRESHOLD" ]; then
        if [ "$state" != "low_notified" ]; then
            [ "$NOTIFY_ON_LOW" = true ] && notify "Battery Low" "Battery ${PERCENTAGE}%. Plug in charger." high
            echo -e "${C_RED}[low]${C_RESET} ${PERCENTAGE}% - plug in charger"
            set_state "low_notified"; state="low_notified"
        fi
    fi
    if [ "$state" = "low_notified" ] && \
       { [ "$charging" = true ] || [ "$PERCENTAGE" -gt $((LOW_THRESHOLD + HYSTERESIS)) ]; }; then
        set_state "idle"; state="idle"
    fi

    if [ "$charging" = true ] && [ "$PERCENTAGE" -ge "$HIGH_THRESHOLD" ]; then
        if [ "$state" != "high_notified" ]; then
            [ "$NOTIFY_ON_HIGH" = true ] && notify "Battery Full" "Battery ${PERCENTAGE}%. Unplug to protect battery." high
            echo -e "${C_YELLOW}[high]${C_RESET} ${PERCENTAGE}% - unplug charger"
            set_state "high_notified"; state="high_notified"
        fi
    fi
    if [ "$state" = "high_notified" ] && \
       { [ "$charging" = false ] || [ "$PERCENTAGE" -lt $((HIGH_THRESHOLD - HYSTERESIS)) ]; }; then
        set_state "idle"; state="idle"
    fi

    if [ "$SERVER_MODE" = true ] && [ "$state" = "low_notified" ] \
       && [ -n "$ON_LOW_COMMAND" ] && [ ! -f "${STATE_DIR}/server_done" ]; then
        echo -e "${C_BLUE}[server]${C_RESET} $ON_LOW_COMMAND"
        bash -c "$ON_LOW_COMMAND" >> "${STATE_DIR}/server.log" 2>&1 || true
        touch "${STATE_DIR}/server_done"
    fi
    [ "$state" = "idle" ] && rm -f "${STATE_DIR}/server_done"

    write_log
    return 0
}

cmd_status() {
    read_battery || die "cannot read battery status"
    local c="No"; is_charging && c="Yes"
    echo -e "${C_BLUE}Battery Status${C_RESET}"
    echo "  Percentage : ${PERCENTAGE}%"
    echo "  Status     : ${STATUS}"
    echo "  Plugged    : ${PLUGGED}"
    echo "  Charging   : ${c}"
    echo "  Temperature: ${TEMPERATURE}C"
    echo "  Current    : ${CURRENT} mA"
    echo "  State      : $(get_state)"
    echo "  Config     : ${CONFIG_FILE}"
}

cmd_log() {
    [ -f "$LOG_FILE" ] || { echo "no log yet"; return; }
    echo "timestamp,percentage,status,plugged,temperature,current"
    tail -n "${1:-20}" "$LOG_FILE"
}

cmd_run() {
    trap 'echo; echo -e "${C_YELLOW}[stop]${C_RESET} stopped"; rm -f "$PID_FILE"; exit 0' INT TERM
    echo "$$" > "$PID_FILE"
    echo -e "${C_GREEN}[start]${C_RESET} battery-guard (PID $$)"
    echo "  Low=${LOW_THRESHOLD}% High=${HIGH_THRESHOLD}% Interval=${CHECK_INTERVAL}s"
    while true; do
        check_once
        sleep "$CHECK_INTERVAL"
    done
}

cmd_stop() {
    [ -f "$PID_FILE" ] || { echo "not running"; return; }
    local pid; pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        echo -e "${C_GREEN}[stop]${C_RESET} killed PID $pid"
    else
        echo "PID $pid not running"
    fi
    rm -f "$PID_FILE"
}

usage() {
    cat <<EOF
battery-guard - Battery lifecycle manager for Termux

Usage:
  battery-guard start       Run in background
  battery-guard run         Run monitor loop (foreground)
  battery-guard stop        Stop background process
  battery-guard status      Show current battery status
  battery-guard once        Single check
  battery-guard log [N]     Show last N log entries
EOF
}

need_cmd jq jq
need_cmd termux-battery-status termux-api

case "${1:-}" in
    run)    cmd_run ;;
    start)  nohup "$0" run > "${STATE_DIR}/daemon.log" 2>&1 & echo -e "${C_GREEN}[start]${C_RESET} PID $!" ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    once)   check_once ;;
    log)    shift; cmd_log "${1:-20}" ;;
    -h|--help|help|"") usage ;;
    *) usage; exit 1 ;;
esac
