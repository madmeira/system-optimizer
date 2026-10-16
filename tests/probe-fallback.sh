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
# LOCALAPPDATA/APPDATA point to empty temp folders: a real runner has Chrome, Edge and more in the real ones
mkdir -p "$WORK/appdata/Local" "$WORK/appdata/Roaming"
run_probe() {
  env -u NUMBER_OF_PROCESSORS -u PROCESSOR_ARCHITECTURE -u SYSTEMDRIVE WINDIR='C:\Windows' \
    LOCALAPPDATA="$WORK/appdata/Local" APPDATA="$WORK/appdata/Roaming" \
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
# All three PowerShell entry points are stubbed: GitHub's runners ship a real pwsh, so a missing stub
# would run the real PowerShell. The stub prints $PS_STUB_OUT, or fails when it is empty.
ps_stub() { [[ -z "${PS_STUB_LOG:-}" ]] || printf 'CALL %s\n' "$*" >> "$PS_STUB_LOG"; if [[ -n "${PS_STUB_OUT:-}" ]]; then printf '%s' "$PS_STUB_OUT"; else return 1; fi; }
pwsh() { ps_stub "$@"; }; powershell() { ps_stub "$@"; }; powershell.exe() { ps_stub "$@"; }
export -f ps_stub pwsh powershell powershell.exe

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
labels=('Real-Time Protection' 'Antivirus Engine' 'Protection:' 'User Account Control' 'ExecutionPolicy' 'OpenSSH Server' 'Profile Status')
forbidden='Enabled \(Secure\)|\(OK\)'
# winget is not PowerShell: when the host has a readable winget the integrity line is a real answer
if command -v winget > /dev/null 2>&1; then
  echo "note: winget is present here, so its Integrity Checks line is not required to say unknown"
else
  labels+=('Integrity Checks'); forbidden+='|Enforced'
fi
for label in "${labels[@]}"; do
  line="$(grep -m1 -F -- "$label" "$WORK/sec.txt" || true)"
  [[ -n "$line" ]] || fail "text output has no '$label' line"
  grep -q 'unknown' <<< "$line" || fail "text line '$line' does not say unknown"
done
if grep -qE "$forbidden" "$WORK/sec.txt"; then fail "text output claims protection that was not checked"; fi
ok "security-audit text says unknown"

run_probe system-probe.sh --json > "$WORK/sys.json"
"$PY" -m json.tool "$WORK/sys.json" > /dev/null || fail "system-probe JSON is invalid when PowerShell fails"
[[ "$(jget "$WORK/sys.json" error)" != MISSING ]] || fail "system-probe does not say that PowerShell was unavailable"
run_probe system-probe.sh > "$WORK/sys.txt"
if grep -qE 'Windows 11|Balanced|C: \(NTFS\)|Enabled|\(None\)' "$WORK/sys.txt"; then fail "system-probe text still shows invented defaults"; fi
for label in 'Power Scheme' 'SSD TRIM Status' 'NTFS 8.3 Name Creation' 'Memory Compression' 'Fast Startup'; do
  line="$(grep -F -- "$label" "$WORK/sys.txt" || true)"
  grep -q 'unknown' <<< "$line" || fail "system-probe '$label' is not unknown"
done
ok "system-probe reports unknown and valid JSON when PowerShell fails"

# ---- case 2: PowerShell answers but Defender/UAC data is missing (null), PUA in audit mode
export PS_STUB_OUT='{"FirewallAllActive":null,"FirewallSummary":"Domain:Active","RealTimeProtection":null,"AntivirusEnabled":null,"PUAProtection":2,"UACEnabled":null,"ExecutionPolicy":"Restricted","SSHDService":"NotInstalled"}'
run_probe security-audit.sh --json > "$WORK/sec2.json"
"$PY" -m json.tool "$WORK/sec2.json" > /dev/null || fail "security-audit JSON is invalid with partial data"
expect "$WORK/sec2.json" defender.realtime_protection '"unknown"' "partial data"
expect "$WORK/sec2.json" system_security.uac_enabled '"unknown"' "partial data"
expect "$WORK/sec2.json" defender.pua_protection 2 "partial data"
ok "null Defender/UAC values stay unknown, not true"

run_probe security-audit.sh > "$WORK/sec2.txt"
grep -q 'Audit mode' "$WORK/sec2.txt" || fail "PUA value 2 is not labelled Audit mode"
pua_line="$(grep -E 'PUA\) Protection' "$WORK/sec2.txt" || true)"
if grep -q 'Disabled' <<< "$pua_line"; then fail "PUA audit mode is labelled Disabled"; fi
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
export PS_STUB_OUT='{"CPUModel":"Test CPU","Cores":4,"Threads":8,"Arch":"x86_64","RAMTotalGB":16,"SwapTotalGB":2,"GPU":"Test GPU","StorageType":"SSD","OSName":"Windows 11","Kernel":"10.0","PowerScheme":"Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)","MemoryCompression":true}'
run_probe hardware-probe.sh --json > "$WORK/hw5.json"
expect "$WORK/hw5.json" cpu.governor '"Balanced"' "canned hardware data"
expect "$WORK/hw5.json" cpu.cores 8 "canned hardware data"
expect "$WORK/hw5.json" recommended_concurrency 8 "canned hardware data"
expect "$WORK/hw5.json" ram.tier '"high"' "canned hardware data"
run_probe hardware-probe.sh > "$WORK/hw5.txt"
if grep -q '^$' "$WORK/hw5.txt"; then fail "hardware-probe text output has an empty line"; fi
grep -q 'Power/Governor: Balanced' "$WORK/hw5.txt" || fail "text output does not show the plan name"
ok "power plan shows only its name; concurrency equals logical cores; no blank line in text output"

# ---- case 6: system-probe shows only the power plan name (JSON and text)
export PS_STUB_OUT='{"OS":"Windows 11 Pro (10.0, Build 22631)","Uptime":"0d 1h 2m","PowerScheme":"Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)","Volumes":"C: (NTFS, 10 GB free / 20 GB total)","TRIM":"Enabled (TRIM active)","ShortNames8dot3":"Disabled","MemoryCompression":true,"TcpAutoTuning":"normal","FastStartup":true,"StartupAppsCount":0,"StartupApps":"","StoppedAutoServicesCount":0,"StoppedAutoServices":""}'
run_probe system-probe.sh --json > "$WORK/sys6.json"
expect "$WORK/sys6.json" PowerScheme '"Balanced"' "system-probe power plan"
run_probe system-probe.sh > "$WORK/sys6.txt"
grep -q 'Power Scheme: Balanced' "$WORK/sys6.txt" || fail "system-probe text does not show the plan name only: $(grep 'Power Scheme' "$WORK/sys6.txt")"
ok "system-probe shows only the power plan name"

# ---- case 7: PowerShell CRLF output and the target-inspect cpu power plan line
export PS_STUB_OUT=$'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)\r\n'
run_probe target-inspect.sh cpu > "$WORK/cpu7.txt"
grep -qx 'Active Power Scheme: Balanced' "$WORK/cpu7.txt" || fail "target-inspect cpu power plan line: $(grep 'Power Scheme' "$WORK/cpu7.txt")"
if grep -q $'\r' "$WORK/cpu7.txt"; then fail "target-inspect cpu output still has a carriage return"; fi
ok "target-inspect cpu shows only the plan name and no carriage returns"

# ---- case 8: target-inspect on the Windows branch (network, chrome, edge, ssh, wsl) and python detection
no_cr() { if grep -q $'\r' "$1"; then fail "$2: output has a carriage return"; fi; }
export PS_STUB_OUT=$'something\r\n'

run_probe target-inspect.sh network > "$WORK/net8.txt"
grep -q 'Category: System Core / Network' "$WORK/net8.txt" || fail "network has no inspection of its own"
if grep -q 'Winget package search\|NOT FOUND IN PATH' "$WORK/net8.txt"; then fail "network still falls into the package search"; fi
no_cr "$WORK/net8.txt" "network"
ok "network is inspected as a domain, without a package search"

export PS_STUB_OUT=$'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe\r\n'
run_probe target-inspect.sh chrome > "$WORK/chrome8.txt"
grep -q '^Status: INSTALLED' "$WORK/chrome8.txt" || fail "chrome found by the registry is not reported as installed"
grep -qF 'Executable: C:\Program Files\Google\Chrome\Application\chrome.exe' "$WORK/chrome8.txt" || fail "chrome executable is not shown"
if grep -q 'NOT FOUND IN PATH\|Winget package search' "$WORK/chrome8.txt"; then fail "chrome still falls into the package search"; fi
no_cr "$WORK/chrome8.txt" "chrome"
run_probe target-inspect.sh edge > "$WORK/edge8.txt"
grep -q '^Status: INSTALLED' "$WORK/edge8.txt" || fail "edge found by the registry is not reported as installed"
if grep -q 'NOT FOUND IN PATH\|Winget package search' "$WORK/edge8.txt"; then fail "edge still falls into the package search"; fi
no_cr "$WORK/edge8.txt" "edge"
unset PS_STUB_OUT
run_probe target-inspect.sh chrome > "$WORK/chrome8b.txt"
grep -q '^Status: NOT INSTALLED' "$WORK/chrome8b.txt" || fail "chrome without a registry entry or data folder is not reported as not installed"
ok "chrome and edge are inspected from the registry, installed or not"

export PS_STUB_OUT=$'Running\r\n'
run_probe target-inspect.sh ssh > "$WORK/ssh8.txt"
if grep -q '/etc/ssh/sshd_config' "$WORK/ssh8.txt"; then fail "ssh on Windows lists the Git Bash /etc/ssh/sshd_config"; fi
if grep -q 'Permissions: [0-7][0-7][0-7]' "$WORK/ssh8.txt"; then fail "ssh on Windows judges POSIX modes"; fi
no_cr "$WORK/ssh8.txt" "ssh"
ok "ssh on Windows lists only the Windows config files"

# wsl.exe prints its help text (UTF-16 with NULs and CRs) when WSL has no distribution
wsl.exe() { printf 'C\0o\0p\0y\0r\0i\0g\0h\0t\0 (c) Microsoft Corporation.\r\r\n\r\r\nUsage: wsl.exe [Argument]\r\r\n'; }
export -f wsl.exe
run_probe target-inspect.sh wsl > "$WORK/wsl8.txt"
grep -qF '(none: no WSL distribution is installed)' "$WORK/wsl8.txt" || fail "wsl does not say that no distribution is installed"
if grep -q 'Usage: wsl.exe' "$WORK/wsl8.txt"; then fail "wsl still prints the help text as distributions"; fi
grep -q '^Version: unknown' "$WORK/wsl8.txt" || fail "wsl version is not unknown: $(grep '^Version' "$WORK/wsl8.txt")"
no_cr "$WORK/wsl8.txt" "wsl"
[[ "$(tr -cd '\0' < "$WORK/wsl8.txt" | wc -c)" -eq 0 ]] || fail "wsl output has a NUL byte"

# translated help text (pt-BR) must be recognized too: judged by the program name, not by English words
wsl.exe() { printf 'Direitos autorais (c) Microsoft Corporation.\r\r\n\r\r\nUso: wsl.exe [Argumento]\r\r\n'; }
export -f wsl.exe
run_probe target-inspect.sh wsl > "$WORK/wsl8pt.txt"
grep -qF '(none: no WSL distribution is installed)' "$WORK/wsl8pt.txt" || fail "translated wsl help text is listed as distributions"
grep -q '^Version: unknown' "$WORK/wsl8pt.txt" || fail "translated wsl help text is taken as a version"
# WSL installed but no distribution: translated message and a failing exit status
wsl.exe() { echo 'O Subsistema do Windows para Linux nao tem distribuicoes instaladas.'; return 1; }
export -f wsl.exe
run_probe target-inspect.sh wsl > "$WORK/wsl8nd.txt"
grep -qF '(none: no WSL distribution is installed)' "$WORK/wsl8nd.txt" || fail "failing wsl -l is listed as a distribution"
# a real list is still shown
wsl.exe() { printf '  NAME      STATE           VERSION\r\n* Ubuntu    Running         2\r\n'; }
export -f wsl.exe
run_probe target-inspect.sh wsl > "$WORK/wsl8ok.txt"
grep -q '\* \* Ubuntu' "$WORK/wsl8ok.txt" || fail "a real distribution list is not shown"
unset -f wsl.exe
ok "wsl without a distribution says so (also translated), and a real list is shown"

# a browser installed for the current user only is found through HKCU as well
export PS_STUB_OUT=$'C:\\Users\\x\\AppData\\Local\\Google\\Chrome\\Application\\chrome.exe\r\n'
export PS_STUB_LOG="$WORK/ps-cmds.txt"
: > "$WORK/ps-cmds.txt"
run_probe target-inspect.sh chrome > /dev/null
grep -q 'HKCU' "$WORK/ps-cmds.txt" || fail "chrome lookup does not try the per-user registry key"
ok "chrome lookup tries the machine-wide and the per-user registry keys"

# one browser target = one PowerShell call for the browser itself (plus the GPU lookup at the top)
launches=$(grep -c '^CALL ' "$WORK/ps-cmds.txt" || true)
[[ "$launches" -le 2 ]] || fail "chrome target started PowerShell $launches times (expected at most 2)"
ok "a browser target starts PowerShell at most twice"
unset PS_STUB_LOG

# wsl: a translated "no distribution" message with the Store link is not a distribution list, even at exit 0
wsl.exe() { printf 'O Subsistema do Windows para Linux nao tem distribuicoes instaladas.\r\nhttps://aka.ms/wslstore\r\n'; }
export -f wsl.exe
run_probe target-inspect.sh wsl > "$WORK/wsl8link.txt"
grep -qF '(none: no WSL distribution is installed)' "$WORK/wsl8link.txt" || fail "message with the Store link is listed as a distribution"
unset -f wsl.exe
ok "wsl message with the Store link is recognized at exit 0"

# winget: "Enforced" needs both policy lines to be read; a missing or unreadable line is unknown, an enabled one is a warning
export PS_STUB_OUT='{"FirewallAllActive":true,"FirewallSummary":"Domain:Active","RealTimeProtection":true,"AntivirusEnabled":true,"PUAProtection":1,"UACEnabled":true,"ExecutionPolicy":"RemoteSigned","SSHDService":"NotInstalled"}'
winget() { printf 'Windows Package Manager v1.2\r\nSomething unrelated\r\n'; }
export -f winget
run_probe security-audit.sh > "$WORK/wg1.txt"
if grep -q 'Integrity Checks: Enforced' "$WORK/wg1.txt"; then fail "winget is Enforced although no policy line was found"; fi
grep -q 'Integrity Checks: unknown' "$WORK/wg1.txt" || fail "missing winget policy lines are not reported as unknown"
winget() { printf 'InstallerHashOverride                     Disabled\r\nLocalArchiveMalwareScanOverride           Disabled\r\n'; }
export -f winget
run_probe security-audit.sh > "$WORK/wg2.txt"
grep -q 'Integrity Checks: Enforced' "$WORK/wg2.txt" || fail "both policies Disabled should be Enforced"
winget() { printf 'InstallerHashOverride                     Enabled\r\nLocalArchiveMalwareScanOverride           Disabled\r\n'; }
export -f winget
run_probe security-audit.sh > "$WORK/wg3.txt"
grep -q 'WARNING.*InstallerHashOverride is Enabled' "$WORK/wg3.txt" || fail "an enabled hash override is not a warning"
winget() { printf 'InstallerHashOverride                     Desabilitado\r\nLocalArchiveMalwareScanOverride           Desabilitado\r\n'; }
export -f winget
run_probe security-audit.sh > "$WORK/wg4.txt"
grep -q 'Integrity Checks: Enforced' "$WORK/wg4.txt" || fail "pt-BR 'Desabilitado' on both policies should be Enforced"
winget() { printf 'InstallerHashOverride                     Habilitado\r\nLocalArchiveMalwareScanOverride           Desabilitado\r\n'; }
export -f winget
run_probe security-audit.sh > "$WORK/wg5.txt"
grep -q 'WARNING.*InstallerHashOverride is Enabled' "$WORK/wg5.txt" || fail "pt-BR 'Habilitado' is not a warning"
winget() { printf 'InstallerHashOverride                     Zzz\r\nLocalArchiveMalwareScanOverride           Zzz\r\n'; }
export -f winget
run_probe security-audit.sh > "$WORK/wg6.txt"
if grep -q 'Integrity Checks: Enforced' "$WORK/wg6.txt"; then fail "an unrecognized word is reported as Enforced"; fi
# the JSON of "winget settings export" is read first: true/false, no words involved
winget() { if [[ "$1" == settings ]]; then printf '{"adminSettings":{"InstallerHashOverride":true,"LocalArchiveMalwareScanOverride":false}}\r\n'; else printf 'InstallerHashOverride                     Zzz\r\nLocalArchiveMalwareScanOverride           Zzz\r\n'; fi; }
export -f winget
run_probe security-audit.sh > "$WORK/wg7.txt"
grep -q 'WARNING.*InstallerHashOverride is Enabled' "$WORK/wg7.txt" || fail "an enabled override in the settings JSON is not a warning"
winget() { if [[ "$1" == settings ]]; then printf '{"adminSettings":{"InstallerHashOverride":false,"LocalArchiveMalwareScanOverride":false}}\r\n'; else printf 'InstallerHashOverride                     Zzz\r\n'; fi; }
export -f winget
run_probe security-audit.sh > "$WORK/wg8.txt"
grep -q 'Integrity Checks: Enforced' "$WORK/wg8.txt" || fail "settings JSON with both false should be Enforced"
unset -f winget
unset PS_STUB_OUT
ok "winget integrity needs both policy lines: missing or unreadable is unknown, enabled is a warning"

# storage on a pt-BR host: fsutil prints OEM code page bytes (not valid UTF-8) and translated words
fsutil.exe() { printf 'NTFS DisableDeleteNotify = 0  (Permite opera\207\344es TRIM)\r\nReFS DisableDeleteNotify = 0\r\n'; }
export -f fsutil.exe
export PS_STUB_OUT=$'Per volume setting (the default)\r\n'
LC_ALL=C.UTF-8 run_probe target-inspect.sh storage > "$WORK/stor8.txt"
grep -q '^SSD TRIM Status: NTFS DisableDeleteNotify = 0' "$WORK/stor8.txt" || fail "TRIM status from OEM-encoded fsutil text: $(grep 'SSD TRIM' "$WORK/stor8.txt")"
if grep -q 'Binary file' "$WORK/stor8.txt"; then fail "fsutil output was taken as a binary file"; fi
grep -q '^NTFS 8.3 Short Name Creation: Per volume setting' "$WORK/stor8.txt" || fail "8.3 state is not read from the registry"
unset -f fsutil.exe
unset PS_STUB_OUT
ok "storage reads TRIM and 8.3 state without depending on translated or OEM-encoded text"

# python: the Microsoft Store shortcut is not a Python
jhas() {  # jhas <json-file> <key> <item>
  "$PY" - "$1" "$2" "$3" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
print("yes" if sys.argv[3] in d.get(sys.argv[2], []) else "no")
EOF
}
python() { echo "Python was not found; run without arguments to install from the Microsoft Store" >&2; return 49; }
export -f python
run_probe detect-targets.sh --json > "$WORK/det8a.json"
[[ "$(jhas "$WORK/det8a.json" package_managers_runtimes python)" == no ]] || fail "the Store shortcut is detected as an installed Python"
python() { echo "Python 3.12.1"; }
export -f python
run_probe detect-targets.sh --json > "$WORK/det8b.json"
[[ "$(jhas "$WORK/det8b.json" package_managers_runtimes python)" == yes ]] || fail "a real Python is not detected"
unset -f python
ok "python is detected only when it really prints a Python version"

# F2: inspecting the Store shortcut says so (needs a real file named python on PATH, so Linux only)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "SKIP - python Store shortcut inspection (needs a file named python on PATH)" ;;
  *)
    mkdir -p "$WORK/fakebin"
    printf '#!/bin/sh\necho "Python was not found; run without arguments to install from the Microsoft Store" >&2\nexit 49\n' > "$WORK/fakebin/python"
    chmod +x "$WORK/fakebin/python"
    PATH="$WORK/fakebin:$PATH" bash "$ROOT/scripts/target-inspect.sh" python > "$WORK/py8.txt"
    grep -q 'Microsoft Store shortcut' "$WORK/py8.txt" || fail "python Store shortcut is not explained: $(head -3 "$WORK/py8.txt")"
    if grep -q '^Status: INSTALLED' "$WORK/py8.txt"; then fail "the Store shortcut is reported as installed"; fi
    ok "inspecting the python Store shortcut says it is only a shortcut"
    ;;
esac

# E: the bash startup latency is a number (or n/a), never "unknown"
bash "$ROOT/scripts/target-inspect.sh" bash > "$WORK/bash8.txt"
grep -Eq 'Interactive Startup Latency: (~[0-9]+\.[0-9] ms|n/a)' "$WORK/bash8.txt" || fail "bash latency line: $(grep Latency "$WORK/bash8.txt")"
ok "bash startup latency is a number or n/a"

# translated Windows text must not be parsed: TCP tuning and 8.3 names come from cmdlets and the registry
if grep -n 'netsh' "$ROOT/scripts/system-probe.sh" "$ROOT/scripts/target-inspect.sh" >&2 || grep -n '8dot3name' "$ROOT/scripts/system-probe.sh" >&2; then
  fail "a probe parses the text of netsh or fsutil 8dot3name, which is translated"
fi
ok "TCP tuning and 8.3 names do not depend on translated command output"

unset PS_STUB_OUT

# ---- case 4: parent disk names (lsblk is stubbed to fail so the name pattern is what gets tested)
# shellcheck source=../scripts/lib.sh
source "$ROOT/scripts/lib.sh"
lsblk() { return 1; }
for pair in "/dev/nvme0n1p2:nvme0n1" "/dev/mmcblk0p1:mmcblk0" "/dev/sda1:sda" "/dev/vda:vda" "/dev/nvme1n1:nvme1n1"; do
  dev="${pair%%:*}"; want="${pair##*:}"; got="$(parent_disk "$dev")"
  [[ "$got" == "$want" ]] || fail "parent_disk $dev gave '$got', expected '$want'"
done
ok "parent_disk understands nvme, mmc, sd and vd names"

# run_ps drops carriage returns; power_plan_name keeps the name inside the parentheses
export PS_STUB_OUT=$'Enabled=True\r\nOther=False\r\n'
got="$(run_ps 'x')"
[[ "$got" == $'Enabled=True\nOther=False' ]] || fail "run_ps kept carriage returns: $(printf '%q' "$got")"
[[ "$(power_plan_name 'Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (High performance)')" == "High performance" ]] || fail "power_plan_name"
[[ "$(power_plan_name 'no parentheses here')" == "no parentheses here" ]] || fail "power_plan_name without parentheses"
ok "run_ps strips carriage returns and power_plan_name returns the plan name"

echo "probe-fallback: $pass passed"
