#!/usr/bin/env bash
# ===========================================================
# SMART TERMINAL COMPANION v2.1 — Clean & Interactive
# Usage: Save as stc.sh, chmod +x stc.sh, ./stc.sh
# ===========================================================

set -o nounset
set -o pipefail

# ----------------------------
# Configuration
# ----------------------------
HISTORY_FILE="${HOME}/.bash_history"
DATA_DIR="${HOME}/.stc"
BACKUP_DIR="${HOME}/.stc_backups"
LOG_FILE="${DATA_DIR}/daily_log.txt"
CACHE="${DATA_DIR}/history_cache.txt"
ERROR_LOG="${DATA_DIR}/error_log.txt"
MAX_HISTORY_LINES=20000

mkdir -p "$DATA_DIR" "$BACKUP_DIR"

# ----------------------------
# Colors & Symbols
# ----------------------------
if [ -t 1 ]; then
  RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"
  CYAN="\e[36m"; MAGENTA="\e[35m"; BOLD="\e[1m"; RESET="\e[0m"
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; MAGENTA=""; BOLD=""; RESET=""
fi

_msg() { printf "%b\n" "$1"; }
_info() { _msg "${CYAN}ℹ ${RESET}$1"; }
_ok() { _msg "${GREEN}✓${RESET} $1"; }
_warn() { _msg "${YELLOW}⚠${RESET} $1"; }
_err() { _msg "${RED}✗${RESET} $1"; }
_header() { echo; _msg "${BOLD}${BLUE}━━━ $1 ━━━${RESET}"; }

# ----------------------------
# Helpers
# ----------------------------
_refresh_cache() {
  if [ -f "$HISTORY_FILE" ]; then
    tail -n "$MAX_HISTORY_LINES" "$HISTORY_FILE" > "$CACHE" 2>/dev/null || cp "$HISTORY_FILE" "$CACHE" 2>/dev/null || : 
  else
    : > "$CACHE"
  fi
}

# ----------------------------
# Username greeting
# ----------------------------
_ask_username() {
  local username
  echo -e "${BOLD}${MAGENTA}"
  echo "╔════════════════════════════════════════╗"
  echo "║   SMART TERMINAL COMPANION v2.1        ║"
  echo "╚════════════════════════════════════════╝"
  echo -e "${RESET}"
  read -rp "$(echo -e ${CYAN}What should I call you?${RESET} )" username
  if [ -z "$username" ]; then
    username="User"
  fi
  echo "$username" > "$DATA_DIR/username.txt"
  echo
  _ok "Welcome, ${BOLD}$username${RESET}!"
  _info "Type ${BOLD}'help'${RESET} to see available commands."
  echo
}

_load_username() {
  if [ -f "$DATA_DIR/username.txt" ]; then
    username=$(cat "$DATA_DIR/username.txt")
  else
    _ask_username
    username=$(cat "$DATA_DIR/username.txt")
  fi
  username=${username:-User}
}

# ----------------------------
# Top commands
# ----------------------------
_get_top_commands() {
  _header "Your Top 15 Commands"
  _refresh_cache
  
  if [ ! -s "$CACHE" ]; then
    _warn "No command history found"
    return
  fi
  
  awk '{print $1}' "$CACHE" | grep -v '^#' | sort | uniq -c | sort -rn | head -n 15 | \
  while read -r count cmd; do
    printf "  ${YELLOW}%5s${RESET} × %s\n" "$count" "$cmd"
  done
}

# ----------------------------
# Alias suggestions
# ----------------------------
_suggest_aliases() {
  _header "Smart Alias Suggestions"
  _refresh_cache
  
  if [ ! -s "$CACHE" ]; then
    _warn "No command history found"
    return
  fi
  
  _info "Finding frequently used long commands..."
  echo
  
  grep -v '^#' "$CACHE" | sort | uniq -c | sort -rn | \
  awk '$1>=3 && length($0)>30 {$1=""; sub(/^ +/,""); print}' | head -n 10 | \
  awk '{
    cmd=$0
    gsub(/[^a-zA-Z0-9]/, "", cmd)
    alias_name = tolower(substr(cmd, 1, 8))
    printf "  ${GREEN}alias %s${RESET}=\"%s\"\n", alias_name, $0
  }' | sed "s/\${GREEN}/$(echo -e ${GREEN})/g; s/\${RESET}/$(echo -e ${RESET})/g"
  
  if ! grep -v '^#' "$CACHE" | sort | uniq -c | sort -rn | awk '$1>=3 && length($0)>30' | head -n 1 | grep -q .; then
    _info "No repetitive long commands found (yet!)"
  fi
}

# ----------------------------
# Command timeline
# ----------------------------
_command_timeline() {
  _header "Activity Timeline"
  _refresh_cache
  
  if ! grep -q '^#' "$CACHE" 2>/dev/null; then
    _warn "Timeline requires timestamp history"
    echo "  Enable with: ${BOLD}export HISTTIMEFORMAT='%F %T '${RESET}"
    echo "  Add to ~/.bashrc to make permanent"
    return
  fi
  
  echo -e "${BOLD}Commands per Hour${RESET}"
  awk '/^#/{
    ts=substr($0,2)
    hour=strftime("%H", ts)
    counts[hour]++
  }
  END {
    max=0
    for (h in counts) if (counts[h] > max) max = counts[h]
    for (h=0; h<24; h++) {
      hr=sprintf("%02d", h)
      count=counts[hr]+0
      if (count > 0) {
        pct = max > 0 ? int((count/max)*20) : 0
        bar=""
        for(i=0; i<pct; i++) bar=bar"█"
        printf "  %s:00 │%-20s│ %d\n", hr, bar, count
      }
    }
  }' "$CACHE"
}

# ----------------------------
# Directory activity
# ----------------------------
_directory_activity() {
  _header "Most Visited Directories"
  _refresh_cache
  
  if [ ! -s "$CACHE" ]; then
    _warn "No command history found"
    return
  fi
  
  grep -E "^cd " "$CACHE" 2>/dev/null | \
  awk '{
    dir = $2
    if (dir != "" && dir != "-" && dir != "~" && dir != ".") print dir
  }' | \
  sed "s|^~|$HOME|" | \
  sort | uniq -c | sort -rn | head -n 15 | \
  while read -r count dir; do
    printf "  ${YELLOW}%5s${RESET} × %s\n" "$count" "$dir"
  done
  
  if ! grep -qE "^cd " "$CACHE" 2>/dev/null; then
    _info "No directory navigation found in history"
  fi
}

# ----------------------------
# System Info
# ----------------------------
_system_info() {
  _header "System Overview"
  
  echo -e "${BOLD}Hostname:${RESET} $(hostname)"
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${BOLD}OS:${RESET} $PRETTY_NAME"
  fi
  
  echo -e "${BOLD}Kernel:${RESET} $(uname -r)"
  
  if command -v uptime >/dev/null 2>&1; then
    echo -e "${BOLD}Uptime:${RESET} $(uptime -p 2>/dev/null || uptime | awk '{print $3, $4}')"
  fi
  
  if [ -f /proc/cpuinfo ]; then
    cpu=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//')
    echo -e "${BOLD}CPU:${RESET} $cpu ($(nproc) cores)"
  fi
  
  if command -v free >/dev/null 2>&1; then
    echo -e "${BOLD}Memory:${RESET} $(free -h | awk 'NR==2{printf "%s / %s", $3, $2}')"
  fi
  
  if command -v df >/dev/null 2>&1; then
    echo -e "${BOLD}Disk:${RESET} $(df -h / | awk 'NR==2{printf "%s / %s (%s)", $3, $2, $5}')"
  fi
}

# ----------------------------
# Network checker
# ----------------------------
_network_checker() {
  _header "Network Status"
  
  if command -v ping >/dev/null 2>&1; then
    if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1; then
      _ok "Internet: Connected"
    else
      _warn "Internet: No connection"
    fi
  fi
  
  echo -e "${BOLD}IP Addresses:${RESET}"
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show scope global 2>/dev/null | grep inet | awk '{print "  " $2}' || echo "  None found"
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig | grep "inet " | grep -v "127.0.0.1" | awk '{print "  " $2}' || echo "  None found"
  fi
  
  echo -e "${BOLD}Active Connections:${RESET}"
  if command -v ss >/dev/null 2>&1; then
    echo "  $(ss -t 2>/dev/null | grep -c ESTAB || echo 0) established TCP connections"
  fi
}

# ----------------------------
# Disk summary
# ----------------------------
_disk_summary() {
  _header "Disk Usage"
  
  echo -e "${BOLD}Current Directory Top 10:${RESET}"
  du -sh ./* 2>/dev/null | sort -hr | head -n 10 | awk '{printf "  %-10s %s\n", $1, $2}' || _warn "Cannot analyze current directory"
  
  echo
  echo -e "${BOLD}System Overview:${RESET}"
  df -h 2>/dev/null | awk 'NR==1 || $6=="/" {printf "  %-15s %10s %10s %10s %5s\n", $6, $2, $3, $4, $5}' || true
}

# ----------------------------
# Process snapshot
# ----------------------------
_process_snapshot() {
  _header "Process Overview"
  
  echo -e "${BOLD}Top 5 by CPU:${RESET}"
  ps aux --sort=-%cpu 2>/dev/null | head -n 6 | tail -n 5 | awk '{printf "  %5.1f%% %-10s %s\n", $3, $11, $2}' || _warn "Cannot get process info"
  
  echo
  echo -e "${BOLD}Top 5 by Memory:${RESET}"
  ps aux --sort=-%mem 2>/dev/null | head -n 6 | tail -n 5 | awk '{printf "  %5.1f%% %-10s %s\n", $4, $11, $2}' || true
  
  echo
  echo -e "${BOLD}Total Processes:${RESET} $(ps aux 2>/dev/null | wc -l)"
}

# ----------------------------
# Backup manager
# ----------------------------
_backup_manager() {
  src="${1:-}"
  if [ -z "$src" ]; then
    _warn "Usage: backup <path>"
    return 1
  fi
  
  # Expand tilde
  eval "src=$src"
  
  if [ ! -e "$src" ]; then
    _err "Path not found: $src"
    return 1
  fi
  
  stamp=$(date +%Y%m%d_%H%M%S)
  base=$(basename "$src")
  out="$BACKUP_DIR/${base}_${stamp}.tar.gz"
  
  _info "Creating backup of: $src"
  if tar -czf "$out" -C "$(dirname "$src")" "$base" 2>/dev/null; then
    _ok "Backup saved: $out"
    ls -lh "$out" | awk '{printf "  Size: %s\n", $5}'
  else
    _err "Backup failed"
    return 1
  fi
}

# ----------------------------
# Safe execute
# ----------------------------
_safe_execute() {
  cmd="$1"
  if [ -z "$cmd" ]; then
    _warn "Usage: execute <command>"
    return 1
  fi
  
  echo -e "${BOLD}Command:${RESET} $cmd"
  echo
  read -rp "$(echo -e ${YELLOW}Execute this command? [y/N]${RESET} )" yn
  
  case "$yn" in
    [Yy]*)
      echo
      _info "Executing..."
      echo
      tmp_out=$(mktemp)
      bash -c "$cmd" 2>&1 | tee "$tmp_out"
      rc=${PIPESTATUS[0]}
      
      if [ "$rc" -ne 0 ]; then
        echo
        _err "Command failed (exit code: $rc)"
        {
          printf "\n=== %s ===\n" "$(date '+%Y-%m-%d %H:%M:%S')"
          printf "CMD: %s\n" "$cmd"
          printf "EXIT: %d\n" "$rc"
          printf "OUTPUT:\n"
          cat "$tmp_out"
          printf "\n"
        } >> "$ERROR_LOG"
      else
        echo
        _ok "Command completed successfully"
      fi
      rm -f "$tmp_out"
      ;;
    *)
      _warn "Cancelled"
      ;;
  esac
}

# ----------------------------
# Error log viewer
# ----------------------------
_error_detector() {
  _header "Recent Errors"
  
  if [ ! -f "$ERROR_LOG" ] || [ ! -s "$ERROR_LOG" ]; then
    _info "No errors logged yet"
    echo "  (Use 'execute' command to log command failures)"
    return
  fi
  
  tail -n 50 "$ERROR_LOG"
}

# ----------------------------
# Statistics
# ----------------------------
_show_stats() {
  _header "Command Statistics"
  _refresh_cache
  
  if [ ! -s "$CACHE" ]; then
    _warn "No command history found"
    return
  fi
  
  total=$(grep -v '^#' "$CACHE" | wc -l)
  unique=$(grep -v '^#' "$CACHE" | awk '{print $1}' | sort -u | wc -l)
  
  echo -e "${BOLD}Total Commands:${RESET} $total"
  echo -e "${BOLD}Unique Commands:${RESET} $unique"
  
  if grep -q '^#' "$CACHE" 2>/dev/null; then
    first=$(grep '^#' "$CACHE" | head -1 | awk '{print substr($0,2)}')
    last=$(grep '^#' "$CACHE" | tail -1 | awk '{print substr($0,2)}')
    if [ -n "$first" ] && [ -n "$last" ]; then
      echo -e "${BOLD}History Span:${RESET} $(date -d "@$first" '+%Y-%m-%d' 2>/dev/null || echo "Unknown") to $(date -d "@$last" '+%Y-%m-%d' 2>/dev/null || echo "Unknown")"
    fi
  fi
  
  echo
  echo -e "${BOLD}Top 5 Commands:${RESET}"
  awk '{print $1}' "$CACHE" | grep -v '^#' | sort | uniq -c | sort -rn | head -n 5 | \
  while read -r count cmd; do
    pct=$(awk "BEGIN {printf \"%.1f\", ($count/$total)*100}")
    printf "  ${YELLOW}%5s${RESET} × %-15s ${CYAN}(%s%%)${RESET}\n" "$count" "$cmd" "$pct"
  done
}

# ----------------------------
# Help
# ----------------------------
_show_help() {
  echo
  echo -e "${BOLD}${BLUE}Available Commands:${RESET}"
  echo
  echo -e "${BOLD}Analysis${RESET}"
  echo "  top-commands      Your most used commands"
  echo "  suggest-aliases   Smart alias suggestions"
  echo "  timeline          Activity by hour"
  echo "  dir-activity      Most visited directories"
  echo "  stats             Command usage statistics"
  echo
  echo -e "${BOLD}System${RESET}"
  echo "  system-info       System overview"
  echo "  network-check     Network status"
  echo "  disk-summary      Disk usage analysis"
  echo "  process-snapshot  CPU & memory usage"
  echo
  echo -e "${BOLD}Tools${RESET}"
  echo "  backup <path>     Create backup archive"
  echo "  execute <cmd>     Safely run command"
  echo "  error-log         View logged errors"
  echo
  echo -e "${BOLD}Other${RESET}"
  echo "  help              Show this help"
  echo "  clear             Clear screen"
  echo "  exit              Exit STC"
  echo
}

# ----------------------------
# Main loop
# ----------------------------
_main_loop() {
  clear
  echo
  echo -e "${BOLD}${MAGENTA}"
  echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
  echo "┃                                                                      ┃"
  echo "┃        SMART TERMINAL COMPANION          ┃"
  echo "┃    Your Intelligent Shell Assistant      ┃"
  echo "┃                                                                      ┃"
  echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
  echo -e "${RESET}"
  echo
  _ok "Welcome, ${BOLD}$username${RESET}!"
  _info "Type ${BOLD}'help'${RESET} to see all commands"
  echo

  while true; do
    printf "${BOLD}${GREEN}$username${RESET}${BLUE}@stc${RESET} ${BOLD}›${RESET} "
    if ! IFS= read -r line; then echo; break; fi

    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue

    cmd=$(printf "%s" "$line" | awk '{print $1}')
    args=$(printf "%s" "$line" | awk '{$1=""; sub(/^ /,""); print}')

    case "$cmd" in
      help|h) _show_help ;;
      top-commands|top) _get_top_commands ;;
      suggest-aliases|aliases) _suggest_aliases ;;
      timeline|time) _command_timeline ;;
      dir-activity|dirs) _directory_activity ;;
      stats|statistics) _show_stats ;;
      system-info|system|info) _system_info ;;
      network-check|network|net) _network_checker ;;
      disk-summary|disk) _disk_summary ;;
      process-snapshot|processes|ps) _process_snapshot ;;
      backup)
        if [ -z "$args" ]; then
          _warn "Usage: backup <path>"
        else
          _backup_manager "$args"
        fi
        ;;
      execute|exec|run)
        if [ -z "$args" ]; then
          _warn "Usage: execute <command>"
        else
          _safe_execute "$args"
        fi
        ;;
      error-log|errors) _error_detector ;;
      clear|cls) clear; continue ;;
      exit|quit|q)
        echo
        _ok "Goodbye, $username! 👋"
        echo
        break
        ;;
      *)
        _err "Unknown command: '$cmd'"
        _info "Type ${BOLD}'help'${RESET} for available commands"
        ;;
    esac

    echo
  done
}

# ----------------------------
# Start
# ----------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  _load_username
  _main_loop
fi