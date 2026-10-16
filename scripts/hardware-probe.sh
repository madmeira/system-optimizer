#!/usr/bin/env bash
# hardware-probe.sh - Probes system hardware for system and tool optimization (Windows & Linux)
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
  # Probing Windows via PowerShell CIM/WMI
  ps_data=$(run_ps '
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors
    $os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, TotalVisibleMemorySize, FreePhysicalMemory
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 -or ($_.Name -notmatch "Virtual|Remote|Basic") })
    $gpuName = if ($gpus.Count -gt 0) { $gpus[0].Name } else { "None detected" }
    $gpuRam = if ($gpus.Count -gt 0 -and $gpus[0].AdapterRAM) { "$([math]::Round($gpus[0].AdapterRAM / 1GB, 2)) GB" } else { "" }
    $gpuStr = if ($gpuRam) { "$gpuName ($gpuRam)" } else { $gpuName }

    $disks = try { @(Get-PhysicalDisk | Select-Object -ExpandProperty MediaType -Unique) } catch { @() }
    $diskType = if ($disks.Count -gt 0) { ($disks -join "/") } else { "unknown" }

    $pf = Get-CimInstance Win32_PageFileUsage | Measure-Object -Property AllocatedBaseSize -Sum
    $swapGb = if ($pf.Sum) { [math]::Round($pf.Sum / 1KB, 2) } else { 0 }
    $ramGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)

    $power = try { (powercfg /getactivescheme 2>$null | Out-String).Trim() } catch { $null }
    $mm = try { (Get-MMAgent -ErrorAction SilentlyContinue).MemoryCompression } catch { $null }

    [PSCustomObject]@{
      CPUModel = if ($cpu) { $cpu.Name.Trim() } else { $null }
      Cores = if ($cpu) { [int]$cpu.NumberOfCores } else { $null }
      Threads = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { $null }
      Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
      RAMTotalGB = $ramGb
      SwapTotalGB = $swapGb
      GPU = $gpuStr
      StorageType = $diskType
      OSName = $os.Caption.Trim()
      Kernel = "$($os.Version) (Build $($os.BuildNumber))"
      PowerScheme = $power
      MemoryCompression = if ($null -ne $mm) { [bool]$mm } else { $null }
    } | ConvertTo-Json -Compress
  ' 2>/dev/null || true)

  if [[ -n "$ps_data" ]]; then
    cpu_model=$(echo "$ps_data" | grep -oE '"CPUModel":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
    cpu_cores=$(echo "$ps_data" | grep -oE '"Threads":[0-9]+' | cut -d: -f2 || echo "unknown")
    cpu_arch=$(echo "$ps_data" | grep -oE '"Arch":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "unknown")
    power_raw=$(echo "$ps_data" | grep -oE '"PowerScheme":"[^"]+"' | cut -d: -f2- | tr -d '"' || true)
    # powercfg prints "<label>: <GUID>  (<plan name>)"; keep only the plan name
    if [[ "$power_raw" =~ \(([^\)]*)\)[[:space:]]*$ ]]; then
      cpu_governor="${BASH_REMATCH[1]}"
    else
      cpu_governor="unknown"
    fi
    microcode_rev="N/A (Managed by Windows/UEFI)"
    ram_total_gb=$(echo "$ps_data" | grep -oE '"RAMTotalGB":[0-9.]+' | cut -d: -f2 || echo "unknown")
    swap_total_gb=$(echo "$ps_data" | grep -oE '"SwapTotalGB":[0-9.]+' | cut -d: -f2 || echo "unknown")
    zram_active=false
    zram_size="0"
    zram_algorithm="none"
    mem_compression=$(echo "$ps_data" | grep -oE '"MemoryCompression":(true|false)' | cut -d: -f2 || echo "unknown")
    gpu_info=$(echo "$ps_data" | grep -oE '"GPU":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
    rotational=$(echo "$ps_data" | grep -oE '"StorageType":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "unknown")
    root_device="C:"
    os_name=$(echo "$ps_data" | grep -oE '"OSName":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
    kernel=$(echo "$ps_data" | grep -oE '"Kernel":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
  else
    # PowerShell failed: report only what the environment really tells us, everything else is unknown
    cpu_model="unknown"
    cpu_cores="${NUMBER_OF_PROCESSORS:-unknown}"
    cpu_arch="${PROCESSOR_ARCHITECTURE:-unknown}"
    cpu_governor="unknown"
    microcode_rev="unknown"
    ram_total_gb="unknown"
    swap_total_gb="unknown"
    zram_active=false
    zram_size="0"
    zram_algorithm="none"
    mem_compression="unknown"
    gpu_info="unknown"
    rotational="unknown"
    root_device="${SYSTEMDRIVE:-unknown}"
    os_name="unknown"
    kernel="unknown"
  fi
else
  # Linux hardware probing
  cpu_model=$(lscpu 2>/dev/null | grep -E "^Model name:" | sed 's/Model name:[ \t]*//' || echo "Unknown CPU")
  cpu_cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "1")
  cpu_arch=$(uname -m)
  cpu_governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "unknown")

  microcode_rev="Unknown"
  if [[ -f /proc/cpuinfo ]]; then
    microcode_rev=$(grep -m1 "microcode" /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo "Unknown")
  fi

  ram_total_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
  ram_total_gb=$(awk "BEGIN {printf \"%.2f\", $ram_total_kb / 1024 / 1024}")
  swap_total_kb=$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
  swap_total_gb=$(awk "BEGIN {printf \"%.2f\", $swap_total_kb / 1024 / 1024}")

  zram_active=false
  zram_size="0"
  zram_algorithm="none"
  mem_compression="false"
  if command -v zramctl >/dev/null 2>&1; then
    zram_out=$(zramctl --noheadings --output NAME,ALGORITHM,DISKSIZE 2>/dev/null | head -n 1 || true)
    if [[ -n "$zram_out" ]]; then
      zram_active=true
      zram_algorithm=$(echo "$zram_out" | awk '{print $2}')
      zram_size=$(echo "$zram_out" | awk '{print $3}')
      mem_compression="true"
    fi
  fi

  gpu_info="None detected"
  if command -v lspci >/dev/null 2>&1; then
    gpu_info=$(lspci 2>/dev/null | grep -Ei "vga|3d|display" | sed 's/.*: //' | paste -sd';' | sed 's/;/; /g' || true)
    [[ -z "$gpu_info" ]] && gpu_info="None detected"
  elif command -v fastfetch >/dev/null 2>&1; then
    gpu_info=$(fastfetch --pipe 2>/dev/null | grep "GPU:" | sed 's/GPU:[ \t]*//' || true)
    [[ -z "$gpu_info" ]] && gpu_info="None detected"
  fi

  root_device=$(df --output=source / 2>/dev/null | tail -1 || echo "")
  rotational="unknown"
  if [[ -n "$root_device" ]]; then
    if command -v lsblk >/dev/null 2>&1; then
      rota_val=$(lsblk -no rota "$root_device" 2>/dev/null | head -n 1 || echo "")
      if [[ "$rota_val" == "0" ]]; then
        rotational="SSD/NVMe"
      elif [[ "$rota_val" == "1" ]]; then
        rotational="HDD"
      fi
    fi
  fi

  if [[ "$rotational" == "unknown" && -n "$root_device" ]]; then
    clean_dev=$(parent_disk "$root_device")
    if [[ -f "/sys/block/${clean_dev}/queue/rotational" ]]; then
      if [[ $(cat "/sys/block/${clean_dev}/queue/rotational") == "0" ]]; then
        rotational="SSD/NVMe"
      else
        rotational="HDD"
      fi
    fi
  fi

  os_name="Unknown Linux"
  if [[ -f /etc/os-release ]]; then
    os_name=$(grep -E "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "Linux")
  fi
  kernel=$(uname -r)
fi

# Memory tier & concurrency budget (concurrency is the logical core count, as the docs say)
safe_concurrency=$cpu_cores
if [[ ! "$ram_total_gb" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  memory_tier="unknown"
elif (( $(awk "BEGIN {print ($ram_total_gb < 4.0)}") )); then
  memory_tier="low"
elif (( $(awk "BEGIN {print ($ram_total_gb < 16.0)}") )); then
  memory_tier="medium"
else
  memory_tier="high"
fi

if [[ "$output_json" == true ]]; then
  cat <<EOF
{
  "cpu": {
    "model": "$(json_str "$cpu_model")",
    "cores": $(json_num "$cpu_cores"),
    "arch": "$(json_str "$cpu_arch")",
    "governor": "$(json_str "$cpu_governor")",
    "microcode": "$(json_str "$microcode_rev")"
  },
  "ram": {
    "total_gb": $(json_num "$ram_total_gb"),
    "swap_gb": $(json_num "$swap_total_gb"),
    "tier": "$(json_str "$memory_tier")",
    "zram_active": $(json_bool "$zram_active"),
    "zram_size": "$(json_str "$zram_size")",
    "zram_algorithm": "$(json_str "$zram_algorithm")",
    "memory_compression": $(json_bool "$mem_compression")
  },
  "gpu": "$(json_str "$gpu_info")",
  "storage": {
    "root_device": "$(json_str "$root_device")",
    "root_disk_type": "$(json_str "$rotational")"
  },
  "os": {
    "name": "$(json_str "$os_name")",
    "kernel": "$(json_str "$kernel")"
  },
  "recommended_concurrency": $(json_num "$safe_concurrency")
}
EOF
else
  cat <<EOF
=== System Hardware Profile ===
- OS: $os_name ($kernel, $cpu_arch)
- CPU: $cpu_model ($cpu_cores threads, Power/Governor: $cpu_governor, Microcode: $microcode_rev)
- Memory: ${ram_total_gb} GiB Total (Pagefile/Swap: ${swap_total_gb} GiB, Tier: $memory_tier, Compression: $mem_compression)
EOF
  if [[ "$zram_active" == true ]]; then
    echo "- zram Swap: Active: $zram_active (Size: $zram_size, Algorithm: $zram_algorithm)"
  fi
  cat <<EOF
- GPU: $gpu_info
- Storage Type: $rotational (Root: $root_device)
- Recommended Concurrency / Thread limit: $safe_concurrency
===============================
EOF
fi
