#!/usr/bin/env bash
# inspect-windows.sh - on a real Windows host (Git Bash), the Windows branch of target-inspect.sh must
# run to the end (exit 0) and print no carriage return. inspect-smoke.sh covers Linux; this covers Windows.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) echo "SKIP - inspect-windows (needs a Windows host)"; exit 0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

targets="storage memory cpu boot network firewall defender ssh execution-policy uac wsl powershell bash git winget windows-terminal chrome edge python"

failed=0; count=0
for t in $targets; do
  count=$((count + 1))
  if bash "$ROOT/scripts/target-inspect.sh" "$t" > "$WORK/out" 2> "$WORK/err"; then rc=0; else rc=$?; fi
  if [[ "$rc" -ne 0 ]]; then
    failed=$((failed + 1)); echo "FAIL - target '$t': exit $rc, stderr: $(head -n 2 "$WORK/err" | cut -c1-200)" >&2
  elif grep -q $'\r' "$WORK/out"; then
    failed=$((failed + 1)); echo "FAIL - target '$t': the output has a carriage return" >&2
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "inspect-windows: $failed of $count targets failed" >&2
  exit 1
fi
echo "inspect-windows: $count targets passed"
