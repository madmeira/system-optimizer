#!/usr/bin/env bash
# inspect-smoke.sh - every target of scripts/target-inspect.sh must run to the end (exit 0) without
# writing to stderr, in a clean environment (no FZF_*, RIPGREP_*, ... variables, empty HOME).
# A crash such as "unbound variable" or an arithmetic error would otherwise go unnoticed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "SKIP - inspect-smoke (the Windows branch of target-inspect.sh is checked on a real Windows host)"
    exit 0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"

targets="bash bat btop cargo controld defender eza full fzf gh git herdr htop kde-plasma lazydocker lazygit
mise mpv neovim pacman pi podman powertoys pwsh ripgrep rustdesk security starship storage system topgrade
windows-terminal winget wsl yay yt-dlp zoxide"

failed=0; count=0
for t in $targets; do
  count=$((count + 1))
  if env -i PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" "$t" > "$WORK/out" 2> "$WORK/err"; then rc=0; else rc=$?; fi
  if [[ "$rc" -ne 0 || -s "$WORK/err" ]]; then
    failed=$((failed + 1))
    echo "FAIL - target '$t': exit $rc, stderr: $(head -n 2 "$WORK/err" | cut -c1-200)" >&2
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "inspect-smoke: $failed of $count targets failed" >&2
  exit 1
fi
echo "ok   - all $count targets run to the end without errors"
echo "inspect-smoke: $count targets passed"
