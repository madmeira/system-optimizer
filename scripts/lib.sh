# shellcheck shell=bash
# lib.sh - helpers shared by the scripts in this folder. Source it; do not run it.
set -euo pipefail

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "lib.sh is a library: source it from another script in scripts/." >&2
  exit 1
fi

is_windows() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*|Windows_NT*) return 0 ;;
  esac
  [[ -n "${WINDIR:-}" || ( -n "${OS:-}" && "$OS" == "Windows_NT" ) ]]
}

# Run a PowerShell command and print its output without carriage returns (PowerShell ends lines with
# CRLF, and a stray \r garbles text output). With pipefail a PowerShell failure is still reported.
run_ps() {
  local ps
  if command -v pwsh >/dev/null 2>&1; then
    ps=pwsh
  elif command -v powershell.exe >/dev/null 2>&1; then
    ps=powershell.exe
  elif command -v powershell >/dev/null 2>&1; then
    ps=powershell
  else
    return 1
  fi
  "$ps" -NoProfile -NonInteractive -Command "$1" | tr -d '\r'
}

# powercfg prints "<label>: <GUID>  (<plan name>)". Print the plan name; without parentheses, print the input.
power_plan_name() {
  local raw="$1"
  if [[ "$raw" =~ \(([^\)]*)\)[[:space:]]*$ ]]; then printf '%s' "${BASH_REMATCH[1]}"; else printf '%s' "$raw"; fi
}

# JSON helpers: never emit an invented value.
json_num()  { if [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; then printf '%s' "$1"; else printf 'null'; fi; }
json_bool() { case "$1" in true|false) printf '%s' "$1" ;; *) printf '"unknown"' ;; esac; }
# Escape a text value for use inside a JSON string: newlines and tabs become spaces, other control
# characters are dropped, then backslash first and quote second.
json_str()  { printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '\000-\010\013\014\016-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# Print a JSON array of strings from the arguments (each one escaped with json_str).
to_json_arr() {
  local arr=("$@") json="[" i
  if [[ ${#arr[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  for i in "${!arr[@]}"; do
    json+="\"$(json_str "${arr[i]}")\""
    [[ $i -lt $((${#arr[@]} - 1)) ]] && json+=", "
  done
  json+="]"
  echo "$json"
}

# Print the parent disk of a block device (nvme0n1p2 -> nvme0n1, mmcblk0p1 -> mmcblk0, sda1 -> sda).
# Uses lsblk when it knows the device, otherwise a name pattern. A whole disk is returned unchanged.
parent_disk() {
  local dev="${1#/dev/}" parent=""
  if command -v lsblk >/dev/null 2>&1; then
    parent="$(lsblk -no pkname "/dev/$dev" 2>/dev/null | head -n 1 || true)"
  fi
  if [[ -z "$parent" ]]; then
    parent="$(printf '%s' "$dev" | sed -E 's#^(nvme[0-9]+n[0-9]+|mmcblk[0-9]+)p[0-9]+$#\1#; s#^([sv]d[a-z]+)[0-9]+$#\1#')"
  fi
  printf '%s' "$parent"
}

# Run a command and print the first line of its output, or the default when it prints nothing.
# Never fails. Use it instead of $(cmd || echo default): systemctl is-active prints "inactive" AND
# exits 3, so the fallback echo would add a second line.
first_line_or() {
  local default="$1" out
  shift
  out="$("$@" 2>/dev/null || true)"
  out="${out%%$'\n'*}"
  printf '%s' "${out:-$default}"
}
