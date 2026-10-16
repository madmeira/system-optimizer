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

run_ps() {
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -Command "$1"
  elif command -v powershell.exe >/dev/null 2>&1; then
    powershell.exe -NoProfile -NonInteractive -Command "$1"
  elif command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -NonInteractive -Command "$1"
  else
    return 1
  fi
}

# JSON helpers: never emit an invented value.
json_num()  { if [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]; then printf '%s' "$1"; else printf 'null'; fi; }
json_bool() { case "$1" in true|false) printf '%s' "$1" ;; *) printf '"unknown"' ;; esac; }
# Escape a single-line text value for use inside a JSON string: backslash first, then quote.
json_str()  { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

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
