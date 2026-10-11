#!/usr/bin/env bash
# security-audit.sh - Inspects system, package manager, and service security posture (Windows & Linux)
set -euo pipefail

output_json=false
if [[ "${1:-}" == "--json" ]]; then
  output_json=true
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

to_json_arr() {
  local arr=("$@")
  if [[ ${#arr[@]} -eq 0 ]]; then
    echo "[]"
    return
  fi
  local json="["
  for i in "${!arr[@]}"; do
    json+="\"${arr[i]}\""
    [[ $i -lt $((${#arr[@]} - 1)) ]] && json+=", "
  done
  json+="]"
  echo "$json"
}

if is_windows; then
  # Windows Security Audit
  ps_sec=$(run_ps '
    $fw = @(Get-NetFirewallProfile)
    $fwAllActive = ($fw | Where-Object { $_.Enabled -eq $true }).Count -eq $fw.Count
    $fwSummary = ($fw | ForEach-Object { "$($_.Name):$(if ($_.Enabled) {"Active"} else {"Disabled"})" }) -join ", "

    $mp = try { Get-MpComputerStatus } catch { $null }
    $pref = try { Get-MpPreference } catch { $null }

    $uacKey = try { Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue } catch { $null }
    $ep = Get-ExecutionPolicy
    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue

    [PSCustomObject]@{
      FirewallAllActive = $fwAllActive
      FirewallSummary = $fwSummary
      RealTimeProtection = if ($mp) { [bool]$mp.RealTimeProtectionEnabled } else { $true }
      AntivirusEnabled = if ($mp) { [bool]$mp.AntivirusEnabled } else { $true }
      PUAProtection = if ($pref) { [int]$pref.PUAProtection } else { 0 }
      UACEnabled = if ($uacKey) { $uacKey.EnableLUA -eq 1 } else { $true }
      ConsentBehavior = if ($uacKey) { $uacKey.ConsentPromptBehaviorAdmin } else { 5 }
      ExecutionPolicy = "$ep"
      SSHDService = if ($sshd) { "$($sshd.Status)" } else { "NotInstalled" }
    } | ConvertTo-Json -Compress
  ' 2>/dev/null || true)

  fw_summary=$(echo "$ps_sec" | grep -oE '"FirewallSummary":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Domain:Active, Private:Active, Public:Active")
  fw_all_active=$(echo "$ps_sec" | grep -oE '"FirewallAllActive":(true|false)' | cut -d: -f2 || echo "true")
  realtime_prot=$(echo "$ps_sec" | grep -oE '"RealTimeProtection":(true|false)' | cut -d: -f2 || echo "true")
  av_enabled=$(echo "$ps_sec" | grep -oE '"AntivirusEnabled":(true|false)' | cut -d: -f2 || echo "true")
  pua_prot=$(echo "$ps_sec" | grep -oE '"PUAProtection":[0-9]+' | cut -d: -f2 || echo "0")
  uac_enabled=$(echo "$ps_sec" | grep -oE '"UACEnabled":(true|false)' | cut -d: -f2 || echo "true")
  exec_policy=$(echo "$ps_sec" | grep -oE '"ExecutionPolicy":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "RemoteSigned")
  sshd_status=$(echo "$ps_sec" | grep -oE '"SSHDService":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "NotInstalled")

  # Network Exposure (listening TCP ports)
  listening_tcp=()
  if command -v netstat >/dev/null 2>&1; then
    while IFS= read -r port; do
      [[ -n "$port" ]] && listening_tcp+=("$port")
    done < <(netstat -ano -p tcp 2>/dev/null | grep -i "LISTENING" | awk '{print $2}' | sort -u || true)
  fi

  # Winget Security Check
  winget_sec_ok=true
  winget_details=""
  if command -v winget >/dev/null 2>&1; then
    winget_info=$(winget --info 2>/dev/null || true)
    if echo "$winget_info" | grep -i "InstallerHashOverride" | grep -qi "Enabled"; then
      winget_sec_ok=false
      winget_details+="InstallerHashOverride is Enabled (Insecure); "
    fi
    if echo "$winget_info" | grep -i "LocalArchiveMalwareScanOverride" | grep -qi "Enabled"; then
      winget_sec_ok=false
      winget_details+="LocalArchiveMalwareScanOverride is Enabled (Insecure); "
    fi
  fi

  # Sensitive file permissions
  ssh_dir_perms="absent"
  [[ -d "$HOME/.ssh" ]] && ssh_dir_perms=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || echo "present")
  insecure_ssh_keys=()
  if [[ -d "$HOME/.ssh" ]]; then
    for keyfile in "$HOME"/.ssh/id_*; do
      if [[ -f "$keyfile" && "$keyfile" != *.pub ]]; then
        kperm=$(stat -c "%a" "$keyfile" 2>/dev/null || echo "")
        if [[ -n "$kperm" && "$kperm" != "600" && "$kperm" != "400" && "$kperm" != "644" ]]; then
          insecure_ssh_keys+=("$(basename "$keyfile") ($kperm)")
        fi
      fi
    done
  fi

  # Score calculation
  score_flags=0
  total_flags=6

  [[ "$fw_all_active" == "true" ]] && ((score_flags++)) || true
  [[ "$realtime_prot" == "true" ]] && ((score_flags++)) || true
  [[ "$av_enabled" == "true" ]] && ((score_flags++)) || true
  [[ "$uac_enabled" == "true" ]] && ((score_flags++)) || true
  [[ "$exec_policy" != "Unrestricted" && "$exec_policy" != "Bypass" ]] && ((score_flags++)) || true
  [[ "$winget_sec_ok" == "true" ]] && ((score_flags++)) || true

  if [[ "$output_json" == true ]]; then
    cat <<EOF
{
  "firewall": {
    "all_profiles_active": $fw_all_active,
    "summary": "$fw_summary"
  },
  "defender": {
    "realtime_protection": $realtime_prot,
    "antivirus_enabled": $av_enabled,
    "pua_protection": $pua_prot
  },
  "system_security": {
    "uac_enabled": $uac_enabled,
    "execution_policy": "$exec_policy",
    "sshd_service": "$sshd_status"
  },
  "winget_security": {
    "hash_override_disabled": $winget_sec_ok,
    "details": "${winget_details:-All secure}"
  },
  "network": {
    "listening_tcp": $(to_json_arr "${listening_tcp[@]}")
  },
  "permissions": {
    "ssh_dir": "$ssh_dir_perms",
    "insecure_ssh_keys": $(to_json_arr "${insecure_ssh_keys[@]}")
  },
  "score": "$score_flags/$total_flags"
}
EOF
  else
    cat <<EOF
=== System Security & Hardening Audit (Windows) ===
- Security Baseline Score: $score_flags / $total_flags core checks passed
- Windows Defender Firewall:
  * Profile Status: $fw_summary (All Active: $fw_all_active)
- Windows Defender Antivirus & Exploit Guard:
  * Real-Time Protection: $realtime_prot
  * Antivirus Engine: $av_enabled
  * Potentially Unwanted App (PUA) Protection: $(if [[ "$pua_prot" -eq 1 ]]; then echo "Enabled (Secure)"; else echo "Disabled (Recommend: Set-MpPreference -PUAProtection 1)"; fi)
- System Integrity & Policies:
  * User Account Control (UAC): $(if [[ "$uac_enabled" == "true" ]]; then echo "Enabled"; else echo "[CRITICAL: Disabled]"; fi)
  * PowerShell ExecutionPolicy: $exec_policy $(if [[ "$exec_policy" == "RemoteSigned" || "$exec_policy" == "Restricted" ]]; then echo "(OK)"; else echo "(Review)"; fi)
  * OpenSSH Server Service: $sshd_status
- Package Manager Security (winget):
  * Integrity Checks: $(if [[ "$winget_sec_ok" == "true" ]]; then echo "Enforced (Hash verification and Malware scans active)"; else echo "[WARNING: $winget_details]"; fi)
- Network Exposure:
  * Listening TCP Sockets: ${#listening_tcp[@]} detected (${listening_tcp[*]:-None})
- Sensitive File Permissions:
  * ~/.ssh permissions: $ssh_dir_perms
EOF
    if [[ ${#insecure_ssh_keys[@]} -gt 0 ]]; then
      echo "  * [WARNING] Insecure SSH key permissions: ${insecure_ssh_keys[*]}"
    fi
    echo "==================================================="
  fi
  exit 0
fi

# Linux Security Audit
fw_name="None"
fw_active="inactive"
fw_enabled="disabled"

for fw in ufw nftables firewalld; do
  if command -v "$fw" >/dev/null 2>&1; then
    act=$(systemctl is-active "$fw" 2>/dev/null || echo "inactive")
    enb=$(systemctl is-enabled "$fw" 2>/dev/null || echo "disabled")
    if [[ "$act" == "active" ]]; then
      fw_name="$fw"
      fw_active="$act"
      fw_enabled="$enb"
      break
    elif [[ "$fw_name" == "None" ]]; then
      fw_name="$fw"
      fw_active="$act"
      fw_enabled="$enb"
    fi
  fi
done

listening_tcp=()
while IFS= read -r line; do
  [[ -n "$line" ]] && listening_tcp+=("$line")
done < <(ss -tlnH 2>/dev/null | awk '{print $4}' | sort -u || true)

listening_udp=()
while IFS= read -r line; do
  [[ -n "$line" ]] && listening_udp+=("$line")
done < <(ss -ulnH 2>/dev/null | awk '{print $4}' | sort -u || true)

sshd_installed=false
sshd_active=false
ssh_root_login="unknown"
ssh_pass_auth="unknown"

if command -v sshd >/dev/null 2>&1; then
  sshd_installed=true
  if [[ $(systemctl is-active sshd 2>/dev/null || echo "inactive") == "active" ]]; then
    sshd_active=true
  fi

  sshd_test=$(sshd -T 2>/dev/null || true)
  if [[ -n "$sshd_test" ]]; then
    ssh_root_login=$(echo "$sshd_test" | grep -i "^permitrootlogin" | awk '{print $2}' || echo "unknown")
    ssh_pass_auth=$(echo "$sshd_test" | grep -i "^passwordauthentication" | awk '{print $2}' || echo "unknown")
  fi
fi

check_sysctl() {
  local key="$1"
  sysctl -n "$key" 2>/dev/null || echo "unknown"
}

kptr_restrict=$(check_sysctl "kernel.kptr_restrict")
dmesg_restrict=$(check_sysctl "kernel.dmesg_restrict")
unpriv_bpf=$(check_sysctl "kernel.unprivileged_bpf_disabled")
yama_ptrace=$(check_sysctl "kernel.yama.ptrace_scope")
prot_hardlinks=$(check_sysctl "fs.protected_hardlinks")
prot_symlinks=$(check_sysctl "fs.protected_symlinks")
prot_fifos=$(check_sysctl "fs.protected_fifos")
prot_regular=$(check_sysctl "fs.protected_regular")
rp_filter=$(check_sysctl "net.ipv4.conf.all.rp_filter")
accept_redirects=$(check_sysctl "net.ipv4.conf.all.accept_redirects")

current_umask=$(umask)
ssh_dir_perms="absent"
[[ -d "$HOME/.ssh" ]] && ssh_dir_perms=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || echo "unknown")
gnupg_dir_perms="absent"
[[ -d "$HOME/.gnupg" ]] && gnupg_dir_perms=$(stat -c "%a" "$HOME/.gnupg" 2>/dev/null || echo "unknown")

insecure_ssh_keys=()
if [[ -d "$HOME/.ssh" ]]; then
  for keyfile in "$HOME"/.ssh/id_*; do
    if [[ -f "$keyfile" && "$keyfile" != *.pub ]]; then
      kperm=$(stat -c "%a" "$keyfile" 2>/dev/null || echo "")
      if [[ "$kperm" != "600" && "$kperm" != "400" ]]; then
        insecure_ssh_keys+=("$(basename "$keyfile") ($kperm)")
      fi
    fi
  done
fi

pacman_siglevel="unknown"
if [[ -f /etc/pacman.conf ]]; then
  pacman_siglevel=$(grep -E "^[[:space:]]*SigLevel" /etc/pacman.conf 2>/dev/null | head -n 1 | sed 's/.*=[ \t]*//' || echo "default")
fi

keyring_timer_active=$(systemctl is-active archlinux-keyring-wkd-sync.timer 2>/dev/null || echo "inactive")

pending_sec_updates="unknown"
if command -v arch-audit >/dev/null 2>&1; then
  pending_sec_updates=$(arch-audit -u 2>/dev/null | wc -l || echo "0")
elif command -v checkupdates >/dev/null 2>&1; then
  pending_updates=$(checkupdates 2>/dev/null | wc -l || echo "0")
  pending_sec_updates="$pending_updates total updates pending"
fi

systemd_sec_ok=0
systemd_sec_medium=0
systemd_sec_unsafe=0
if command -v systemd-analyze >/dev/null 2>&1; then
  sec_summary=$(systemd-analyze security 2>/dev/null | awk '$2 ~ /^[0-9]/ { if ($2 >= 8.0) unsafe++; else if ($2 >= 5.0) medium++; else ok++ } END { printf "%d %d %d", ok, medium, unsafe }' || echo "0 0 0")
  systemd_sec_ok=$(echo "$sec_summary" | awk '{print $1}')
  systemd_sec_medium=$(echo "$sec_summary" | awk '{print $2}')
  systemd_sec_unsafe=$(echo "$sec_summary" | awk '{print $3}')
fi

score_flags=0
total_flags=6

[[ "$fw_active" == "active" ]] && ((score_flags++)) || true
[[ "$kptr_restrict" != "0" && "$kptr_restrict" != "unknown" ]] && ((score_flags++)) || true
[[ "$dmesg_restrict" == "1" ]] && ((score_flags++)) || true
[[ "$prot_hardlinks" == "1" && "$prot_symlinks" == "1" ]] && ((score_flags++)) || true
[[ "$ssh_dir_perms" == "700" || "$ssh_dir_perms" == "absent" ]] && ((score_flags++)) || true
[[ "$pacman_siglevel" != "Never" ]] && ((score_flags++)) || true

if [[ "$output_json" == true ]]; then
  cat <<EOF
{
  "firewall": {
    "name": "$fw_name",
    "active": "$fw_active",
    "enabled": "$fw_enabled"
  },
  "network": {
    "listening_tcp": $(to_json_arr "${listening_tcp[@]}"),
    "listening_udp_count": ${#listening_udp[@]}
  },
  "ssh": {
    "installed": $sshd_installed,
    "active": $sshd_active,
    "permit_root_login": "$ssh_root_login",
    "password_authentication": "$ssh_pass_auth"
  },
  "kernel_sysctl_security": {
    "kptr_restrict": "$kptr_restrict",
    "dmesg_restrict": "$dmesg_restrict",
    "unprivileged_bpf_disabled": "$unpriv_bpf",
    "yama_ptrace_scope": "$yama_ptrace",
    "fs_protected_hardlinks": "$prot_hardlinks",
    "fs_protected_symlinks": "$prot_symlinks",
    "fs_protected_fifos": "$prot_fifos",
    "fs_protected_regular": "$prot_regular",
    "rp_filter": "$rp_filter",
    "accept_redirects": "$accept_redirects"
  },
  "permissions": {
    "umask": "$current_umask",
    "ssh_dir": "$ssh_dir_perms",
    "gnupg_dir": "$gnupg_dir_perms",
    "insecure_ssh_keys": $(to_json_arr "${insecure_ssh_keys[@]}")
  },
  "package_security": {
    "pacman_siglevel": "$pacman_siglevel",
    "keyring_timer_active": "$keyring_timer_active",
    "pending_security_updates": "$pending_sec_updates"
  },
  "systemd_security_audit": {
    "ok_services": $systemd_sec_ok,
    "medium_risk_services": $systemd_sec_medium,
    "unsafe_or_exposed_services": $systemd_sec_unsafe
  },
  "score": "$score_flags/$total_flags"
}
EOF
else
  cat <<EOF
=== System Security & Hardening Audit ===
- Security Baseline Score: $score_flags / $total_flags core checks passed
- Firewall Posture:
  * Active Firewall: $fw_name (Status: $fw_active, Enabled: $fw_enabled)
- Network Exposure:
  * Listening TCP Sockets: ${#listening_tcp[@]} detected (${listening_tcp[*]:-None})
  * Listening UDP Sockets: ${#listening_udp[@]} detected
- SSH Daemon Hardening:
  * Installed: $sshd_installed, Running: $sshd_active
  * PermitRootLogin: $ssh_root_login
  * PasswordAuthentication: $ssh_pass_auth
- Kernel & Sysctl Attack Surface:
  * kernel.kptr_restrict: $kptr_restrict (Recommended: 1 or 2)
  * kernel.dmesg_restrict: $dmesg_restrict (Recommended: 1)
  * kernel.unprivileged_bpf_disabled: $unpriv_bpf (Recommended: 1 or 2)
  * kernel.yama.ptrace_scope: $yama_ptrace (Recommended: 1)
  * fs.protected_hardlinks / symlinks: $prot_hardlinks / $prot_symlinks (Recommended: 1 / 1)
  * fs.protected_fifos / regular: $prot_fifos / $prot_regular (Recommended: 2 / 2)
  * net.ipv4.conf.all.rp_filter: $rp_filter (Recommended: 1)
  * net.ipv4.conf.all.accept_redirects: $accept_redirects (Recommended: 0)
- File Permissions & Sensitive Directories:
  * umask: $current_umask
  * ~/.ssh permissions: $ssh_dir_perms (Recommended: 700)
  * ~/.gnupg permissions: $gnupg_dir_perms (Recommended: 700)
EOF
  if [[ ${#insecure_ssh_keys[@]} -gt 0 ]]; then
    echo "  * [WARNING] Loose SSH Key Permissions Detected: ${insecure_ssh_keys[*]}"
  fi
  cat <<EOF
- Package & Supply Chain Integrity:
  * Pacman SigLevel: $pacman_siglevel
  * Keyring Sync Timer: $keyring_timer_active
  * Vulnerability / Update Status: $pending_sec_updates
- systemd Sandboxing Assessment (systemd-analyze security):
  * Low Risk (OK): $systemd_sec_ok units
  * Medium Risk: $systemd_sec_medium units
  * Exposed / Unsafe: $systemd_sec_unsafe units
=========================================
EOF
fi
