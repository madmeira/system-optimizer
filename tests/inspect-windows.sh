#!/usr/bin/env bash
# inspect-windows.sh - on a real Windows host (Git Bash), the Windows branch of target-inspect.sh must
# run to the end (exit 0), print its header and no carriage return, and show no shell error. inspect-smoke.sh covers Linux; this covers Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) echo "SKIP - inspect-windows (needs a Windows host)"; exit 0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

targets="system security full storage memory cpu boot network firewall defender ssh execution-policy uac wsl powershell pwsh
bash git winget windows-terminal powertoys chrome edge brave firefox python pi mise cargo topgrade neovim starship herdr gh mpv
yt-dlp ripgrep fd eza zoxide bat fzf lazygit btop lazydocker syncthing sqlite3 rustdesk controld"

domain_and_browser_targets=" system security full storage memory cpu boot network firewall defender ssh execution-policy uac wsl powershell chrome edge brave firefox "

failed=0; count=0
for t in $targets; do
  count=$((count + 1))
  if bash "$ROOT/scripts/target-inspect.sh" "$t" > "$WORK/out" 2> "$WORK/err"; then rc=0; else rc=$?; fi
  if [[ "$rc" -ne 0 ]]; then
    failed=$((failed + 1)); echo "FAIL - target '$t': exit $rc, stderr: $(head -n 2 "$WORK/err" | cut -c1-200)" >&2
  elif grep -q $'\r' "$WORK/out"; then
    failed=$((failed + 1)); echo "FAIL - target '$t': the output has a carriage return" >&2
  elif ! grep -qF "=== Target Inspection: $t ===" "$WORK/out"; then
    failed=$((failed + 1)); echo "FAIL - target '$t': no header, output starts with: $(head -n 1 "$WORK/out" | cut -c1-120)" >&2
  elif [[ "$domain_and_browser_targets" == *" $t "* ]] && grep -Eq 'Status: NOT FOUND IN PATH|Winget package search' "$WORK/out"; then
    failed=$((failed + 1)); echo "FAIL - target '$t': fell through to generic package search" >&2
  elif grep -Eq 'unbound variable|syntax error|command not found|bad substitution' "$WORK/err" "$WORK/out"; then
    failed=$((failed + 1)); echo "FAIL - target '$t': shell error: $(grep -Eh 'unbound variable|syntax error|command not found|bad substitution' "$WORK/err" "$WORK/out" | head -n 1 | cut -c1-160)" >&2
  fi
done

# Verify Windows path normalization for mise shims when LOCALAPPDATA uses backslashes
mkdir -p "$WORK/home/.pi/agent" "$WORK/local/mise/shims" "$WORK/bin"
printf '#!/usr/bin/env bash\necho 1.0.0\n' > "$WORK/bin/pi"
printf '#!/usr/bin/env bash\necho 2026.10.0\n' > "$WORK/bin/mise"
chmod +x "$WORK/bin/pi" "$WORK/bin/mise"
win_local="$(cygpath -w "$WORK/local" 2>/dev/null || printf '%s' "$WORK/local")"
unix_shims="$(cygpath -u "$win_local" 2>/dev/null || printf '%s' "$WORK/local")/mise/shims"
pi_out="$(HOME="$WORK/home" LOCALAPPDATA="$win_local" PATH="$WORK/bin:$unix_shims:$PATH" bash "$ROOT/scripts/target-inspect.sh" pi)"
if [[ "$pi_out" != *"Shims on Agent PATH: [ACTIVE]"* ]]; then
  failed=$((failed + 1)); echo "FAIL - pi target did not normalize backslash LOCALAPPDATA against Git Bash PATH" >&2
fi

# Verify gh on Windows does not attach POSIX mode tags (Permissions: 644) to NTFS hosts.yml
mkdir -p "$WORK/roaming/GitHub CLI" "$WORK/home/.config/gh"
printf 'github.com:\n    user: test\n' > "$WORK/roaming/GitHub CLI/hosts.yml"
printf '#!/usr/bin/env bash\necho "gh version 2.60.0"\n' > "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
gh_out="$(HOME="$WORK/home" APPDATA="$(cygpath -w "$WORK/roaming" 2>/dev/null || printf '%s' "$WORK/roaming")" PATH="$WORK/bin:$PATH" bash "$ROOT/scripts/target-inspect.sh" gh)"
if grep -Eq 'Permissions: [0-7]{3}' <<< "$gh_out"; then
  failed=$((failed + 1)); echo "FAIL - gh on Windows attached POSIX permission tag to NTFS hosts.yml" >&2
fi

if [[ "$failed" -ne 0 ]]; then
  echo "inspect-windows: $failed failure(s) across $count targets" >&2
  exit 1
fi
echo "inspect-windows: $count targets + Windows path/NTFS checks passed"
