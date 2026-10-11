#!/usr/bin/env bash
# hardware-probe.sh - Probes system hardware for system and tool optimization (Windows & Linux)
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

if is_windows; then
  # Probing Windows via PowerShell CIM/WMI
  ps_data=$(run_ps '
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name, NumberOfCores, NumberOfLogicalProcessors
    $os = Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, TotalVisibleMemorySize, FreePhysicalMemory
    $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 -or ($_.Name -notmatch "Virtual|Remote|Basic") })
    $gpuName = if ($gpus.Count -gt 0) { $gpus[0].Name } else { "None detected" }
    $gpuRam = if ($gpus.Count -gt 0 -and $gpus[0].AdapterRAM) { "$([math]::Round($gpus[0].AdapterRAM / 1GB, 2)) GB" } else { "" }
    $gpuStr = if ($gpuRam) { "$gpuName ($gpuRam)" } else { $gpuName }

    $disks = try { @(Get-PhysicalDisk | Select-Object -ExpandProperty MediaType -Unique) } catch { @("Unknown") }
    $diskType = if ($disks.Count -gt 0) { ($disks -join "/") } else { "SSD" }

    $pf = Get-CimInstance Win32_PageFileUsage | Measure-Object -Property AllocatedBaseSize -Sum
    $swapGb = if ($pf.Sum) { [math]::Round($pf.Sum / 1KB, 2) } else { 0 }
    $ramGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)

    $power = try { ((powercfg /getactivescheme 2>$null) -replace "^.*:\s*", "") } catch { "unknown" }
    $mm = try { (Get-MMAgent -ErrorAction SilentlyContinue).MemoryCompression } catch { $null }

    [PSCustomObject]@{
      CPUModel = if ($cpu) { $cpu.Name.Trim() } else { "Unknown CPU" }
      Cores = if ($cpu) { [int]$cpu.NumberOfCores } else { 1 }
      Threads = if ($cpu) { [int]$cpu.NumberOfLogicalProcessors } else { 1 }
      Arch = if ([Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86" }
      RAMTotalGB = $ramGb
      SwapTotalGB = $swapGb
      GPU = $gpuStr
      StorageType = $diskType
      OSName = $os.Caption.Trim()
      Kernel = "$($os.Version) (Build $($os.BuildNumber))"
      PowerScheme = $power
      MemoryCompression = if ($null -ne $mm) { [bool]$mm } else { $true }
    } | ConvertTo-Json -Compress
  ' 2>/dev/null || true)

  if [[ -n "$ps_data" ]]; then
    cpu_model=$(echo "$ps_data" | grep -oE '"CPUModel":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Unknown CPU")
    cpu_cores=$(echo "$ps_data" | grep -oE '"Threads":[0-9]+' | cut -d: -f2 || echo "1")
    cpu_arch=$(echo "$ps_data" | grep -oE '"Arch":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "x86_64")
    cpu_governor=$(echo "$ps_data" | grep -oE '"PowerScheme":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "unknown")
    microcode_rev="N/A (Managed by Windows/UEFI)"
    ram_total_gb=$(echo "$ps_data" | grep -oE '"RAMTotalGB":[0-9.]+' | cut -d: -f2 || echo "16.0")
    swap_total_gb=$(echo "$ps_data" | grep -oE '"SwapTotalGB":[0-9.]+' | cut -d: -f2 || echo "0.0")
    zram_active=false
    zram_size="0"
    zram_algorithm="none"
    mem_compression=$(echo "$ps_data" | grep -oE '"MemoryCompression":(true|false)' | cut -d: -f2 || echo "true")
    gpu_info=$(echo "$ps_data" | grep -oE '"GPU":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Unknown GPU")
    rotational=$(echo "$ps_data" | grep -oE '"StorageType":"[^"]+"' | cut -d: -f2 | tr -d '"' || echo "SSD")
    root_device="C:"
    os_name=$(echo "$ps_data" | grep -oE '"OSName":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "Microsoft Windows")
    kernel=$(echo "$ps_data" | grep -oE '"Kernel":"[^"]+"' | cut -d: -f2- | tr -d '"' || echo "10.0")
  else
    # Fallback to environment if PowerShell failed
    cpu_model="Generic Multi-Core Processor"
    cpu_cores="${NUMBER_OF_PROCESSORS:-4}"
    cpu_arch="${PROCESSOR_ARCHITECTURE:-x86_64}"
    cpu_governor="Balanced"
    microcode_rev="N/A"
    ram_total_gb="8.00"
    swap_total_gb="8.00"
    zram_active=false
    zram_size="0"
    zram_algorithm="none"
    mem_compression="true"
    gpu_info="Generic Display Adapter"
    rotational="SSD"
    root_device="C:"
    os_name="Microsoft Windows"
    kernel="10.0"
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
    gpu_info=$(lspci | grep -Ei "vga|3d|display" | sed 's/.*: //' | tr '\n' '; ' | sed 's/; $//')
  elif command -v fastfetch >/dev/null 2>&1; then
    gpu_info=$(fastfetch --pipe 2>/dev/null | grep "GPU:" | sed 's/GPU:[ \t]*//' || echo "Unknown GPU")
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
    clean_dev=$(basename "$root_device" | sed 's/[0-9]*$//')
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
    os_name=$(grep -E "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"')
  fi
  kernel=$(uname -r)
fi

# Memory tier & concurrency budget
if (( $(awk "BEGIN {print ($ram_total_gb < 4.0)}") )); then
  safe_concurrency=$cpu_cores
  memory_tier="low"
elif (( $(awk "BEGIN {print ($ram_total_gb < 16.0)}") )); then
  safe_concurrency=$(( cpu_cores * 2 ))
  memory_tier="medium"
else
  safe_concurrency=$(( cpu_cores * 4 ))
  memory_tier="high"
fi

if [[ "$output_json" == true ]]; then
  cat <<EOF
{
  "cpu": {
    "model": "$cpu_model",
    "cores": $cpu_cores,
    "arch": "$cpu_arch",
    "governor": "$cpu_governor",
    "microcode": "$microcode_rev"
  },
  "ram": {
    "total_gb": $ram_total_gb,
    "swap_gb": $swap_total_gb,
    "tier": "$memory_tier",
    "zram_active": $zram_active,
    "zram_size": "$zram_size",
    "zram_algorithm": "$zram_algorithm",
    "memory_compression": $mem_compression
  },
  "gpu": "$gpu_info",
  "storage": {
    "root_device": "$root_device",
    "root_disk_type": "$rotational"
  },
  "os": {
    "name": "$os_name",
    "kernel": "$kernel"
  },
  "recommended_concurrency": $safe_concurrency
}
EOF
else
  cat <<EOF
=== System Hardware Profile ===
- OS: $os_name ($kernel, $cpu_arch)
- CPU: $cpu_model ($cpu_cores threads, Power/Governor: $cpu_governor, Microcode: $microcode_rev)
- Memory: ${ram_total_gb} GiB Total (Pagefile/Swap: ${swap_total_gb} GiB, Tier: $memory_tier, Compression: $mem_compression)
$(if [[ "$zram_active" == true ]]; then echo "- zram Swap: Active: $zram_active (Size: $zram_size, Algorithm: $zram_algorithm)"; fi)
- GPU: $gpu_info
- Storage Type: $rotational (Root: $root_device)
- Recommended Concurrency / Thread limit: $safe_concurrency
===============================
EOF
fi
