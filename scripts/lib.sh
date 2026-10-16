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
