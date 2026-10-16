#!/usr/bin/env bash
# windows-baseline.sh - run the 4 probes on Windows (Git Bash) and check their --json output.
# Usage (from the Proxmox host, QEMU guest agent running in the VM):
#   ssh root@<host> 'qm guest exec <vmid> --pass-stdin 1 --timeout 600 -- "C:\Program Files\Git\bin\bash.exe" -l -s' < tests/windows-baseline.sh
# REPO (git URL or local path) defaults to the upstream repository and REF (branch or tag) to its default
# branch, so without them this tests the upstream code, not your branch. To test a branch, set both, e.g.
#   REPO=https://github.com/<you>/system-optimizer REF=my-branch bash -s < tests/windows-baseline.sh
# Deliberately no `set -e`/pipefail: keep going so every probe is reported even if one fails.
set -u
REPO="${REPO:-https://github.com/madmeira/system-optimizer}"
WORK="/c/Windows/Temp/so-baseline"

rm -rf "$WORK"
git clone -q ${REF:+--branch "$REF"} "$REPO" "$WORK" || { echo "clone failed"; exit 1; }
cd "$WORK" || exit 1
echo "commit: $(git log -1 --format='%h %s')"
echo "bash: ${BASH_VERSION}"
for t in pwsh powershell.exe python3; do
  command -v "$t" >/dev/null 2>&1 && echo "has $t" || echo "no  $t"
done

for p in hardware-probe system-probe detect-targets security-audit; do
  out="/c/Windows/Temp/$p.json"
  bash "scripts/$p.sh" --json > "$out" 2>"$out.err"; rc=$?
  winpath="C:\\Windows\\Temp\\$p.json"
  verdict=$(powershell.exe -NoProfile -Command "try { Get-Content -Raw '$winpath' | ConvertFrom-Json | Out-Null; 'valid' } catch { 'INVALID: ' + \$_.Exception.Message }" 2>&1 | tr -d '\r')
  echo "== $p exit=$rc json=$verdict stderr_bytes=$(wc -c < "$out.err")"
done

echo "--- hardware-probe.json"; cat /c/Windows/Temp/hardware-probe.json
echo "--- security-audit.json"; cat /c/Windows/Temp/security-audit.json
