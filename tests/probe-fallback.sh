#!/usr/bin/env bash
# probe-fallback.sh - when PowerShell fails or returns partial data, the Windows branch of the probes
# must say "unknown" instead of inventing values or reporting protection that was never checked.
# PowerShell is stubbed with exported shell functions (works on Linux and on Git Bash, where a script
# named *.exe may not execute). HOME is a temp dir so nothing real is read.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"; mkdir -p "$HOME"

PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "FAIL - python3/python not found" >&2; exit 1; }

pass=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; exit 1; }

# run_probe <script> [args]: run a probe in a Windows-looking environment with the stubs below
run_probe() {
  env -u NUMBER_OF_PROCESSORS -u PROCESSOR_ARCHITECTURE -u SYSTEMDRIVE WINDIR='C:\Windows' \
    bash "$ROOT/scripts/$1" "${@:2}"
}
# jget <json-file> <dotted.path>: print the value, or MISSING
jget() {
  "$PY" - "$1" "$2" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    if not isinstance(d, dict) or k not in d:
        print("MISSING"); sys.exit(0)
    d = d[k]
print(json.dumps(d))
EOF
}
expect() {  # expect <json-file> <path> <expected-json> <label>
  local got; got="$(jget "$1" "$2")"
  [[ "$got" == "$3" ]] || fail "$4: $2 is $got, expected $3"
}

# ---- case 1: PowerShell fails completely
pwsh() { return 1; }; powershell() { return 1; }; powershell.exe() { return 1; }
export -f pwsh powershell powershell.exe

run_probe hardware-probe.sh --json > "$WORK/hw.json"
"$PY" -m json.tool "$WORK/hw.json" > /dev/null || fail "hardware-probe JSON is invalid on failure"
expect "$WORK/hw.json" cpu.model '"unknown"' "hardware failure"
expect "$WORK/hw.json" cpu.cores null "hardware failure"
expect "$WORK/hw.json" ram.total_gb null "hardware failure"
expect "$WORK/hw.json" ram.tier '"unknown"' "hardware failure"
expect "$WORK/hw.json" gpu '"unknown"' "hardware failure"
expect "$WORK/hw.json" storage.root_disk_type '"unknown"' "hardware failure"
expect "$WORK/hw.json" recommended_concurrency null "hardware failure"
if grep -qE 'Generic|8\.0|16\.0' "$WORK/hw.json"; then fail "hardware-probe still prints invented defaults"; fi
ok "hardware-probe reports unknown when PowerShell fails"

run_probe security-audit.sh --json > "$WORK/sec.json"
"$PY" -m json.tool "$WORK/sec.json" > /dev/null || fail "security-audit JSON is invalid on failure"
for path in firewall.all_profiles_active defender.realtime_protection defender.antivirus_enabled \
            system_security.uac_enabled; do
  expect "$WORK/sec.json" "$path" '"unknown"' "security failure"
done
expect "$WORK/sec.json" defender.pua_protection null "security failure"
expect "$WORK/sec.json" system_security.execution_policy '"unknown"' "security failure"
expect "$WORK/sec.json" system_security.sshd_service '"unknown"' "security failure"
score="$(jget "$WORK/sec.json" score)"
[[ "$score" != '"6/6"' ]] || fail "score is 6/6 although nothing could be checked"
ok "security-audit reports unknown and no false 6/6 when PowerShell fails ($score)"

run_probe security-audit.sh > "$WORK/sec.txt"
for label in 'Real-Time Protection' 'Antivirus Engine' 'Protection:' 'User Account Control' 'ExecutionPolicy' 'OpenSSH Server' 'Integrity Checks' 'Profile Status'; do
  line="$(grep -m1 -F -- "$label" "$WORK/sec.txt" || true)"
  [[ -n "$line" ]] || fail "text output has no '$label' line"
  grep -q 'unknown' <<< "$line" || fail "text line '$line' does not say unknown"
done
if grep -qE 'Enabled \(Secure\)|\(OK\)|Enforced' "$WORK/sec.txt"; then fail "text output claims protection that was not checked"; fi
ok "security-audit text says unknown"

run_probe system-probe.sh --json > "$WORK/sys.json"
"$PY" -m json.tool "$WORK/sys.json" > /dev/null || fail "system-probe JSON is invalid when PowerShell fails"
[[ "$(jget "$WORK/sys.json" error)" != MISSING ]] || fail "system-probe does not say that PowerShell was unavailable"
run_probe system-probe.sh > "$WORK/sys.txt"
if grep -qE 'Windows 11|Balanced|C: \(NTFS\)|Enabled|\(None\)' "$WORK/sys.txt"; then fail "system-probe text still shows invented defaults"; fi
for label in 'Power Scheme' 'SSD TRIM Status' 'NTFS 8.3 Name Creation' 'Memory Compression' 'Fast Startup'; do
  grep -F -- "$label" "$WORK/sys.txt" | grep -q 'unknown' || fail "system-probe '$label' is not unknown"
done
ok "system-probe reports unknown and valid JSON when PowerShell fails"

# ---- case 2: PowerShell answers but Defender/UAC data is missing (null), PUA in audit mode
unset -f pwsh powershell  # run_ps tries pwsh first; only powershell.exe answers in this case
powershell.exe() {
  printf '%s' '{"FirewallAllActive":null,"FirewallSummary":"Domain:Active","RealTimeProtection":null,"AntivirusEnabled":null,"PUAProtection":2,"UACEnabled":null,"ExecutionPolicy":"Restricted","SSHDService":"NotInstalled"}'
}
export -f powershell.exe
run_probe security-audit.sh --json > "$WORK/sec2.json"
"$PY" -m json.tool "$WORK/sec2.json" > /dev/null || fail "security-audit JSON is invalid with partial data"
expect "$WORK/sec2.json" defender.realtime_protection '"unknown"' "partial data"
expect "$WORK/sec2.json" system_security.uac_enabled '"unknown"' "partial data"
expect "$WORK/sec2.json" defender.pua_protection 2 "partial data"
ok "null Defender/UAC values stay unknown, not true"

run_probe security-audit.sh > "$WORK/sec2.txt"
grep -q 'Audit mode' "$WORK/sec2.txt" || fail "PUA value 2 is not labelled Audit mode"
if grep -E 'PUA\) Protection' "$WORK/sec2.txt" | grep -q 'Disabled'; then fail "PUA audit mode is labelled Disabled"; fi
ok "PUA value 2 is labelled Audit mode"

# ---- case 3: several GPUs are joined with "; " and no trailing separator (Linux branch only)
if [[ "$(uname -s)" == MINGW* || "$(uname -s)" == MSYS* || "$(uname -s)" == CYGWIN* ]]; then
  echo "SKIP - GPU list case (the Linux branch of hardware-probe does not run on Windows)"
else
  lspci() { printf '%s\n' '00:02.0 VGA compatible controller: Intel UHD' '00:1f.3 Audio device: Intel Audio' '01:00.0 3D controller: NVIDIA GTX'; }
  export -f lspci
  env -u WINDIR -u OS bash "$ROOT/scripts/hardware-probe.sh" --json > "$WORK/gpu2.json"
  expect "$WORK/gpu2.json" gpu '"Intel UHD; NVIDIA GTX"' "two GPUs"
  lspci() { printf '%s\n' '00:02.0 VGA compatible controller: Intel UHD'; }
  export -f lspci
  env -u WINDIR -u OS bash "$ROOT/scripts/hardware-probe.sh" --json > "$WORK/gpu1.json"
  expect "$WORK/gpu1.json" gpu '"Intel UHD"' "one GPU"
  ok "GPU list is joined with '; ' and has no trailing separator"
fi

# ---- case 5: canned PowerShell hardware data -> clean governor name, concurrency = logical cores, no blank line
powershell.exe() {
  printf '%s' '{"CPUModel":"Test CPU","Cores":4,"Threads":8,"Arch":"x86_64","RAMTotalGB":16,"SwapTotalGB":2,"GPU":"Test GPU","StorageType":"SSD","OSName":"Windows 11","Kernel":"10.0","PowerScheme":"Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)","MemoryCompression":true}'
}
export -f powershell.exe
run_probe hardware-probe.sh --json > "$WORK/hw5.json"
expect "$WORK/hw5.json" cpu.governor '"Balanced"' "canned hardware data"
expect "$WORK/hw5.json" cpu.cores 8 "canned hardware data"
expect "$WORK/hw5.json" recommended_concurrency 8 "canned hardware data"
expect "$WORK/hw5.json" ram.tier '"high"' "canned hardware data"
run_probe hardware-probe.sh > "$WORK/hw5.txt"
if grep -q '^$' "$WORK/hw5.txt"; then fail "hardware-probe text output has an empty line"; fi
grep -q 'Power/Governor: Balanced' "$WORK/hw5.txt" || fail "text output does not show the plan name"
ok "power plan shows only its name; concurrency equals logical cores; no blank line in text output"

# ---- case 4: parent disk names (lsblk is stubbed to fail so the name pattern is what gets tested)
# shellcheck source=../scripts/lib.sh
source "$ROOT/scripts/lib.sh"
lsblk() { return 1; }
for pair in "/dev/nvme0n1p2:nvme0n1" "/dev/mmcblk0p1:mmcblk0" "/dev/sda1:sda" "/dev/vda:vda" "/dev/nvme1n1:nvme1n1"; do
  dev="${pair%%:*}"; want="${pair##*:}"; got="$(parent_disk "$dev")"
  [[ "$got" == "$want" ]] || fail "parent_disk $dev gave '$got', expected '$want'"
done
ok "parent_disk understands nvme, mmc, sd and vd names"

echo "probe-fallback: $pass passed"
