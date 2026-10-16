#!/usr/bin/env bash
# system-probe.sh - Probes Windows & Linux system configuration and performance parameters
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
  # Windows System Probing
  ps_data=$(run_ps '
    $os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, LastBootUpTime
    $power = try { ((powercfg /getactivescheme 2>$null) -replace "^.*:\s*", "") } catch { "unknown" }
    $trimNtfs = try {
      $out = cmd.exe /c "fsutil behavior query DisableDeleteNotify 2>&1"
      if ($out -match "NTFS DisableDeleteNotify = 0") { "Enabled (TRIM active)" } else { "Disabled" }
    } catch { "unknown" }
    $shortNames = try {
      $sn = cmd.exe /c "fsutil 8dot3name query 2>&1"
      if ($sn -match "state is 0|state is 2") { "Enabled" } else { "Disabled" }
    } catch { "unknown" }

    $vols = @(Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object {
      "$($_.DriveLetter): ($($_.FileSystem), $([math]::Round($_.SizeRemaining/1GB, 1)) GB free / $([math]::Round($_.Size/1GB, 1)) GB total)"
    })

    $mm = try { (Get-MMAgent -ErrorAction SilentlyContinue).MemoryCompression } catch { $null }
    $tcp = try { ((netsh interface tcp show global 2>$null) | Select-String "Receive Window Auto-Tuning Level") -replace "^.*:\s*", "" } catch { "normal" }
    $hiber = try { (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled } catch { $null }
    $startups = try { @(Get-CimInstance Win32_StartupCommand | Select-Object -ExpandProperty Name) } catch { @() }
    $stoppedSvcs = try { @(Get-Service | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -ne "Running" } | Select-Object -ExpandProperty Name) } catch { @() }

    $uptimeStr = if ($os.LastBootUpTime) {
      $span = (Get-Date) - $os.LastBootUpTime
      "$($span.Days)d $($span.Hours)h $($span.Minutes)m"
    } else { "unknown" }

    [PSCustomObject]@{
      OS = "$($os.Caption) ($($os.Version), Build $($os.BuildNumber))"
      Uptime = $uptimeStr
      PowerScheme = $power
      Volumes = ($vols -join "; ")
      TRIM = $trimNtfs
      ShortNames8dot3 = $shortNames
      MemoryCompression = if ($null -ne $mm) { [bool]$mm } else { $true }
      TcpAutoTuning = "$tcp".Trim()
      FastStartup = if ($null -ne $hiber) { [bool]$hiber } else { $true }
      StartupAppsCount = $startups.Count
      StartupApps = ($startups -join ", ")
      StoppedAutoServicesCount = $stoppedSvcs.Count
      StoppedAutoServices = ($stoppedSvcs -join ", ")
    } | ConvertTo-Json -Compress
  ' 2>/dev/null || true)

  if [[ "$output_json" == true ]]; then
    echo "$ps_data"
  else
    os_info=$(echo "$ps_data" | grep -oE '"OS":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Windows 11")
    uptime_info=$(echo "$ps_data" | grep -oE '"Uptime":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
    power_info=$(echo "$ps_data" | grep -oE '"PowerScheme":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Balanced")
    vols_info=$(echo "$ps_data" | grep -oE '"Volumes":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "C: (NTFS)")
    trim_info=$(echo "$ps_data" | grep -oE '"TRIM":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Enabled")
    sn_info=$(echo "$ps_data" | grep -oE '"ShortNames8dot3":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Disabled")
    mc_info=$(echo "$ps_data" | grep -oE '"MemoryCompression":(true|false)' | cut -d: -f2 || echo "true")
    tcp_info=$(echo "$ps_data" | grep -oE '"TcpAutoTuning":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "normal")
    fast_info=$(echo "$ps_data" | grep -oE '"FastStartup":(true|false)' | cut -d: -f2 || echo "true")
    startup_count=$(echo "$ps_data" | grep -oE '"StartupAppsCount":[0-9]+' | cut -d: -f2 || echo "0")
    startup_list=$(echo "$ps_data" | grep -oE '"StartupApps":"[^"]*"' | cut -d: -f2- | tr -d '"' || echo "None")
    stopped_count=$(echo "$ps_data" | grep -oE '"StoppedAutoServicesCount":[0-9]+' | cut -d: -f2 || echo "0")
    stopped_list=$(echo "$ps_data" | grep -oE '"StoppedAutoServices":"[^"]*"' | cut -d: -f2- | tr -d '"' || echo "None")

    cat <<EOF
=== System Configuration & Performance Probe (Windows) ===
- OS & Kernel: $os_info (Uptime: $uptime_info)
- Power Scheme: $power_info
- Storage & NTFS Volumes:
  * Mounted Volumes: $vols_info
  * SSD TRIM Status: $trim_info
  * NTFS 8.3 Name Creation: $sn_info
- Memory Management:
  * Windows Memory Compression: $mc_info
- Network Stack:
  * TCP Receive Window Auto-Tuning: $tcp_info
- Boot Performance & Startup:
  * Fast Startup (Hiberboot): $fast_info
  * Startup Applications: $startup_count app(s) registered ($startup_list)
- Services Health:
  * Stopped Automatic Services: $stopped_count service(s) ($stopped_list)
===========================================================
EOF
  fi
  exit 0
fi

# Linux System Probing
os_name="Unknown"
[[ -f /etc/os-release ]] && os_name=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
kernel_ver=$(uname -r)

governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "not available")
energy_perf="not available"
if [[ -f /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]]; then
  energy_perf=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null || echo "not available")
fi

virt_type="None (Bare Metal)"
if command -v systemd-detect-virt >/dev/null 2>&1; then
  detected_virt=$(systemd-detect-virt 2>/dev/null || true)
  if [[ -n "$detected_virt" && "$detected_virt" != "none" ]]; then
    virt_type="$detected_virt"
  fi
fi

root_source=$(df --output=source / 2>/dev/null | tail -1 || echo "")
root_fstype=$(df --output=fstype / 2>/dev/null | tail -1 || echo "")
mount_options=$(findmnt -n -o OPTIONS / 2>/dev/null || echo "defaults")
fstrim_active=$(systemctl is-active fstrim.timer 2>/dev/null || echo "inactive")
fstrim_enabled=$(systemctl is-enabled fstrim.timer 2>/dev/null || echo "disabled")

swappiness=$(sysctl -n vm.swappiness 2>/dev/null || echo "unknown")
vfs_cache_pressure=$(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo "unknown")
dirty_ratio=$(sysctl -n vm.dirty_ratio 2>/dev/null || echo "unknown")
dirty_background_ratio=$(sysctl -n vm.dirty_background_ratio 2>/dev/null || echo "unknown")
zram_configured=false
if [[ -f /etc/systemd/zram-generator.conf || -f /usr/lib/systemd/zram-generator.conf ]]; then
  zram_configured=true
fi

tcp_congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo "unknown")
qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo "unknown")

boot_time="unknown"
if command -v systemd-analyze >/dev/null 2>&1; then
  boot_time=$(systemd-analyze 2>/dev/null | head -n 1 || echo "unknown")
fi

slow_units=()
if command -v systemd-analyze >/dev/null 2>&1; then
  while IFS= read -r line; do
    [[ -n "$line" ]] && slow_units+=("$line")
  done < <(systemd-analyze blame 2>/dev/null | head -n 5 || true)
fi

failed_units=()
while IFS= read -r line; do
  [[ -n "$line" ]] && failed_units+=("$line")
done < <(systemctl --failed --no-legend 2>/dev/null | awk '{print $1}' || true)

journal_size=$(journalctl --disk-usage 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)?[KMGT]?" | head -n 1 || echo "unknown")

if [[ "$output_json" == true ]]; then
  cat <<EOF
{
  "os": "$os_name",
  "kernel": "$kernel_ver",
  "virtualization": "$virt_type",
  "cpu_governor": "$governor",
  "energy_performance_preference": "$energy_perf",
  "storage": {
    "root_device": "$root_source",
    "fstype": "$root_fstype",
    "mount_options": "$mount_options",
    "fstrim_timer": {
      "active": "$fstrim_active",
      "enabled": "$fstrim_enabled"
    }
  },
  "memory_sysctl": {
    "swappiness": "$swappiness",
    "vfs_cache_pressure": "$vfs_cache_pressure",
    "dirty_ratio": "$dirty_ratio",
    "dirty_background_ratio": "$dirty_background_ratio",
    "zram_generator_configured": $zram_configured
  },
  "network_sysctl": {
    "tcp_congestion_control": "$tcp_congestion",
    "default_qdisc": "$qdisc"
  },
  "boot_performance": {
    "startup_time": "$boot_time",
    "journal_disk_usage": "$journal_size"
  },
  "failed_units_count": ${#failed_units[@]}
}
EOF
else
  cat <<EOF
=== System Configuration & Performance Probe ===
- OS: $os_name ($kernel_ver, Virt: $virt_type)
- CPU Scaling Governor: $governor (EPP: $energy_perf)
- Root Mount: $root_source ($root_fstype, Options: $mount_options)
- SSD Maintenance: fstrim.timer is $fstrim_active ($fstrim_enabled)
- Memory / VM Sysctl:
  * vm.swappiness: $swappiness
  * vm.vfs_cache_pressure: $vfs_cache_pressure
  * vm.dirty_ratio: $dirty_ratio (background: $dirty_background_ratio)
  * zram-generator config: $zram_configured
- Network Stack:
  * TCP Congestion: $tcp_congestion
  * Default Qdisc: $qdisc
- Boot Performance:
  * $boot_time
  * Journal Disk Usage: ${journal_size:-unknown}
  * Failed Services: ${#failed_units[@]} unit(s)
EOF
  if [[ ${#slow_units[@]} -gt 0 ]]; then
    echo "  * Top Slow Units at Boot:"
    for unit in "${slow_units[@]}"; do
      echo "    - $unit"
    done
  fi
  if [[ ${#failed_units[@]} -gt 0 ]]; then
    echo "  * Failed Units Detected:"
    for f in "${failed_units[@]}"; do
      echo "    - $f"
    done
  fi
  echo "================================================"
fi
