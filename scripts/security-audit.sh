#!/usr/bin/env bash
# security-audit.sh - Inspects system, package manager, and service security posture (Windows & Linux)
set -euo pipefail

LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if [[ ! -f "$LIB" ]]; then
  echo "Error: $LIB not found; copy the whole skill folder, not a single script." >&2
  exit 1
fi
# shellcheck source=lib.sh
source "$LIB"

output_json=false
if [[ "${1:-}" == "--json" ]]; then
  output_json=true
fi

if is_windows; then
  # Windows Security Audit
  ps_sec=$(run_ps '
    $fw = @(Get-NetFirewallProfile)
    $fwAllActive = if ($fw.Count -gt 0) { ($fw | Where-Object { $_.Enabled -eq $true }).Count -eq $fw.Count } else { $null }
    $fwSummary = ($fw | ForEach-Object { "$($_.Name):$(if ($_.Enabled) {"Active"} else {"Disabled"})" }) -join ", "

    $mp = try { Get-MpComputerStatus } catch { $null }
    $pref = try { Get-MpPreference } catch { $null }

    $uacKey = try { Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue } catch { $null }
    $ep = Get-ExecutionPolicy
    $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue

    [PSCustomObject]@{
      FirewallAllActive = $fwAllActive
      FirewallSummary = $fwSummary
      RealTimeProtection = if ($mp) { [bool]$mp.RealTimeProtectionEnabled } else { $null }
      AntivirusEnabled = if ($mp) { [bool]$mp.AntivirusEnabled } else { $null }
      PUAProtection = if ($pref) { [int]$pref.PUAProtection } else { $null }
      UACEnabled = if ($uacKey) { $uacKey.EnableLUA -eq 1 } else { $null }
      ConsentBehavior = if ($uacKey) { $uacKey.ConsentPromptBehaviorAdmin } else { $null }
      ExecutionPolicy = "$ep"
      SSHDService = if ($sshd) { "$($sshd.Status)" } else { "NotInstalled" }
    } | ConvertTo-Json -Compress
  ' 2>/dev/null || true)

  fw_summary=$(echo "$ps_sec" | grep -oE '"FirewallSummary":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
  fw_all_active=$(echo "$ps_sec" | grep -oE '"FirewallAllActive":(true|false)' | cut -d: -f2 || echo "unknown")
  realtime_prot=$(echo "$ps_sec" | grep -oE '"RealTimeProtection":(true|false)' | cut -d: -f2 || echo "unknown")
  av_enabled=$(echo "$ps_sec" | grep -oE '"AntivirusEnabled":(true|false)' | cut -d: -f2 || echo "unknown")
  pua_prot=$(echo "$ps_sec" | grep -oE '"PUAProtection":[0-9]+' | cut -d: -f2 || echo "unknown")
  uac_enabled=$(echo "$ps_sec" | grep -oE '"UACEnabled":(true|false)' | cut -d: -f2 || echo "unknown")
  exec_policy=$(echo "$ps_sec" | grep -oE '"ExecutionPolicy":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "unknown")
  sshd_status=$(echo "$ps_sec" | grep -oE '"SSHDService":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "unknown")

  # Network Exposure (listening TCP ports)
  listening_tcp=()
  if command -v netstat >/dev/null 2>&1; then
    while IFS= read -r port; do
      [[ -n "$port" ]] && listening_tcp+=("$port")
    done < <(netstat -ano -p tcp 2>/dev/null | grep -i "LISTENING" | awk '{print $2}' | sort -u || true)
  fi

  # Winget Security Check
  winget_sec_ok="unknown"
  winget_details=""
  if command -v winget >/dev/null 2>&1; then
    winget_info=$(winget --info 2>/dev/null || true)
    [[ -n "$winget_info" ]] && winget_sec_ok=true
    if echo "$winget_info" | grep -i "InstallerHashOverride" | grep -qi "Enabled"; then
      winget_sec_ok=false
      winget_details+="InstallerHashOverride is Enabled (Insecure); "
    fi
    if echo "$winget_info" | grep -i "LocalArchiveMalwareScanOverride" | grep -qi "Enabled"; then
      winget_sec_ok=false
      winget_details+="LocalArchiveMalwareScanOverride is Enabled (Insecure); "
    fi
  fi

  # Sensitive file permissions: POSIX mode bits from Git Bash do not reflect NTFS ACLs, so they are
  # not judged here (the Linux branch applies the 600/400 rule).
  ssh_dir_perms="absent"
  [[ -d "$HOME/.ssh" ]] && ssh_dir_perms="n/a (NTFS)"
  insecure_ssh_keys=()

  # Score calculation
  score_flags=0
  total_flags=6

  [[ "$fw_all_active" == "true" ]] && ((score_flags++)) || true
  [[ "$realtime_prot" == "true" ]] && ((score_flags++)) || true
  [[ "$av_enabled" == "true" ]] && ((score_flags++)) || true
  [[ "$uac_enabled" == "true" ]] && ((score_flags++)) || true
  [[ "$exec_policy" != "Unrestricted" && "$exec_policy" != "Bypass" && "$exec_policy" != "unknown" ]] && ((score_flags++)) || true
  [[ "$winget_sec_ok" == "true" ]] && ((score_flags++)) || true

  if [[ "$output_json" == true ]]; then
    cat <<EOF
{
  "firewall": {
    "all_profiles_active": $(json_bool "$fw_all_active"),
    "summary": "$(json_str "$fw_summary")"
  },
  "defender": {
    "realtime_protection": $(json_bool "$realtime_prot"),
    "antivirus_enabled": $(json_bool "$av_enabled"),
    "pua_protection": $(json_num "$pua_prot")
  },
  "system_security": {
    "uac_enabled": $(json_bool "$uac_enabled"),
    "execution_policy": "$(json_str "$exec_policy")",
    "sshd_service": "$(json_str "$sshd_status")"
  },
  "winget_security": {
    "hash_override_disabled": $(json_bool "$winget_sec_ok"),
    "details": "$(if [[ "$winget_sec_ok" == "unknown" ]]; then echo "winget missing or unreadable, not checked"; else echo "${winget_details:-All secure}"; fi)"
  },
  "network": {
    "listening_tcp": $(to_json_arr "${listening_tcp[@]}")
  },
  "permissions": {
    "ssh_dir": "$(json_str "$ssh_dir_perms")",
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
  * Potentially Unwanted App (PUA) Protection: $(case "$pua_prot" in 1) echo "Enabled (Secure)" ;; 2) echo "Audit mode (detects but does not block; Recommend: Set-MpPreference -PUAProtection 1)" ;; 0) echo "Disabled (Recommend: Set-MpPreference -PUAProtection 1)" ;; *) echo "unknown" ;; esac)
- System Integrity & Policies:
  * User Account Control (UAC): $(case "$uac_enabled" in true) echo "Enabled" ;; false) echo "[CRITICAL: Disabled]" ;; *) echo "unknown" ;; esac)
  * PowerShell ExecutionPolicy: $exec_policy $(case "$exec_policy" in RemoteSigned|Restricted) echo "(OK)" ;; unknown) echo "" ;; *) echo "(Review)" ;; esac)
  * OpenSSH Server Service: $sshd_status
- Package Manager Security (winget):
  * Integrity Checks: $(case "$winget_sec_ok" in true) echo "Enforced (Hash verification and Malware scans active)" ;; false) echo "[WARNING: $winget_details]" ;; *) echo "unknown (winget missing or unreadable, not checked)" ;; esac)
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
    act=$(first_line_or inactive systemctl is-active "$fw")
    enb=$(first_line_or disabled systemctl is-enabled "$fw")
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
  if [[ $(first_line_or inactive systemctl is-active sshd) == "active" ]]; then
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

keyring_timer_active=$(first_line_or inactive systemctl is-active archlinux-keyring-wkd-sync.timer)

pending_sec_updates="unknown"
if command -v arch-audit >/dev/null 2>&1; then
  pending_sec_updates=$(arch-audit -u 2>/dev/null | wc -l || true)
elif command -v checkupdates >/dev/null 2>&1; then
  pending_updates=$(checkupdates 2>/dev/null | wc -l || true)
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
    "name": "$(json_str "$fw_name")",
    "active": "$(json_str "$fw_active")",
    "enabled": "$(json_str "$fw_enabled")"
  },
  "network": {
    "listening_tcp": $(to_json_arr "${listening_tcp[@]}"),
    "listening_udp_count": ${#listening_udp[@]}
  },
  "ssh": {
    "installed": $sshd_installed,
    "active": $sshd_active,
    "permit_root_login": "$(json_str "$ssh_root_login")",
    "password_authentication": "$(json_str "$ssh_pass_auth")"
  },
  "kernel_sysctl_security": {
    "kptr_restrict": "$(json_str "$kptr_restrict")",
    "dmesg_restrict": "$(json_str "$dmesg_restrict")",
    "unprivileged_bpf_disabled": "$(json_str "$unpriv_bpf")",
    "yama_ptrace_scope": "$(json_str "$yama_ptrace")",
    "fs_protected_hardlinks": "$(json_str "$prot_hardlinks")",
    "fs_protected_symlinks": "$(json_str "$prot_symlinks")",
    "fs_protected_fifos": "$(json_str "$prot_fifos")",
    "fs_protected_regular": "$(json_str "$prot_regular")",
    "rp_filter": "$(json_str "$rp_filter")",
    "accept_redirects": "$(json_str "$accept_redirects")"
  },
  "permissions": {
    "umask": "$(json_str "$current_umask")",
    "ssh_dir": "$(json_str "$ssh_dir_perms")",
    "gnupg_dir": "$(json_str "$gnupg_dir_perms")",
    "insecure_ssh_keys": $(to_json_arr "${insecure_ssh_keys[@]}")
  },
  "package_security": {
    "pacman_siglevel": "$(json_str "$pacman_siglevel")",
    "keyring_timer_active": "$(json_str "$keyring_timer_active")",
    "pending_security_updates": "$(json_str "$pending_sec_updates")"
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
