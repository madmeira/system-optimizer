#!/usr/bin/env bash
# target-inspect.sh - Inspects system domains, tools, and packages across Performance, Config, and Security (Windows & Linux)
set -euo pipefail

LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if [[ ! -f "$LIB" ]]; then
  echo "Error: $LIB not found; copy the whole skill folder, not a single script." >&2
  exit 1
fi
# shellcheck source=lib.sh
source "$LIB"

target="${1:-}"

if [[ -z "$target" ]]; then
  echo "Usage: $0 <target-domain-tool-or-package>" >&2
  exit 1
fi

local_app_data="${LOCALAPPDATA:-$HOME/AppData/Local}"
roaming_app_data="${APPDATA:-$HOME/AppData/Roaming}"

# Print a browser found on Linux (empty $1 = not installed).
browser_report_linux() {
  local exe="$1" ver
  if [[ -z "$exe" ]]; then
    echo "Status: NOT INSTALLED"
    return 0
  fi
  ver=$("$exe" --version 2>/dev/null | head -n 1 || true)
  echo "Status: INSTALLED"
  echo "Executable: $exe"
  echo "Version: ${ver:-unknown}"
}

# Print a browser found on Windows: <app exe name> <user data folder> <policy registry key>.
# One PowerShell call prints three lines: the program path ("App Paths", machine-wide first, then
# per-user), its version and whether the policy key exists.
browser_report_win() {
  local app="$1" data="$2" policy_key="$3" info exe="" ver="" managed="" profiles
  info=$(SO_APP="$app" SO_KEY="$policy_key" run_ps '
    $p = ""
    foreach ($r in "HKLM","HKCU") {
      $v = (Get-ItemProperty "${r}:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$env:SO_APP" -ErrorAction SilentlyContinue)."(default)"
      if ($v) { $p = $v; break }
    }
    $p
    if ($p) { (Get-Item -LiteralPath $p).VersionInfo.ProductVersion } else { "" }
    Test-Path -Path $env:SO_KEY' 2>/dev/null || true)
  { read -r exe; read -r ver; read -r managed; } <<< "$info" || true
  if [[ -n "$exe" ]]; then
    echo "Status: INSTALLED"
    echo "Executable: $exe"
    echo "Version: ${ver:-unknown}"
  elif [[ -d "$data" ]]; then
    echo "Status: user data found, executable not located"
  else
    echo "Status: NOT INSTALLED"
  fi
  if [[ -d "$data" ]]; then
    profiles=$(find "$data" -maxdepth 1 -type d \( -name Default -o -name 'Profile *' \) 2>/dev/null | wc -l || true)
    echo "User Data: ${data//\//\\}"
    echo "Profiles: $profiles"
  fi
  echo "Managed Policies: ${managed:-unknown}"
}

# Dynamic hardware detection
detected_threads=$(nproc 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-4}")
detected_gpu=$(run_ps '(@(Get-CimInstance Win32_VideoController | Where-Object { $_.AdapterRAM -gt 0 -or ($_.Name -notmatch "Virtual|Remote|Basic") }) | Select-Object -First 1 -ExpandProperty Name) 2>$null' 2>/dev/null || echo "")

# Dynamic theme inference helper
infer_theme() {
  local wt_cfg
  for candidate in \
    "$local_app_data/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
    "$local_app_data/Microsoft/Windows Terminal/settings.json"; do
    if [[ -f "$candidate" ]]; then
      wt_cfg="$candidate"
      break
    fi
  done
  if [[ -n "${wt_cfg:-}" && -f "$wt_cfg" ]]; then
    local wt_theme
    wt_theme=$(grep -E '"colorScheme"[[:space:]]*:' "$wt_cfg" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "")
    if [[ -n "$wt_theme" ]]; then
      echo "$wt_theme"
      return 0
    fi
  fi
  local hdr_cfg="$roaming_app_data/herdr/config.toml"
  if [[ -f "$hdr_cfg" ]]; then
    local hdr_theme
    hdr_theme=$(grep -E '^[[:space:]]*name[[:space:]]*=' "$hdr_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "")
    if [[ -n "$hdr_theme" && "$hdr_theme" != "default" ]]; then
      echo "$hdr_theme"
      return 0
    fi
  fi
  local nv_json="$local_app_data/nvim/lazyvim.json"
  if [[ -f "$nv_json" ]]; then
    local nv_theme
    nv_theme=$(grep -E '"colorscheme"[[:space:]]*:' "$nv_json" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "")
    if [[ -n "$nv_theme" ]]; then
      echo "$nv_theme"
      return 0
    fi
  fi
  if [[ -n "${BAT_THEME:-}" ]]; then
    echo "$BAT_THEME"
    return 0
  fi
  echo ""
}

echo "=== Target Inspection: $target ==="

# 1. System Domains Handling
case "$target" in
  kernel|sysctl|sysctl-security)
    if is_windows; then
      echo "Category: System Core / Windows NT Kernel & Subsystems"
      os_ver=$(run_ps '(Get-CimInstance Win32_OperatingSystem).Version' 2>/dev/null || uname -r)
      os_build=$(run_ps '(Get-CimInstance Win32_OperatingSystem).BuildNumber' 2>/dev/null || echo "unknown")
      echo "Windows Kernel Version: NT $os_ver (Build $os_build)"
      echo "Note: Sysctl parameters apply inside Linux environments and WSL distributions."
      if [[ -f "$HOME/.wslconfig" ]]; then
        echo "Global WSL Kernel Configuration: $HOME/.wslconfig [EXISTS]"
      fi
    else
      echo "Category: System Core / Kernel & Sysctl"
      echo "Kernel Version: $(uname -r)"
      echo "Relevant Config Files:"
      for f in /etc/sysctl.conf /etc/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
      echo "Current Key Parameters:"
      echo "  * vm.swappiness: $(sysctl -n vm.swappiness 2>/dev/null || echo unknown)"
      echo "  * vm.vfs_cache_pressure: $(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo unknown)"
      echo "  * kernel.kptr_restrict: $(sysctl -n kernel.kptr_restrict 2>/dev/null || echo unknown)"
      echo "  * kernel.dmesg_restrict: $(sysctl -n kernel.dmesg_restrict 2>/dev/null || echo unknown)"
      echo "  * kernel.unprivileged_bpf_disabled: $(sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null || echo unknown)"
      echo "  * fs.protected_hardlinks: $(sysctl -n fs.protected_hardlinks 2>/dev/null || echo unknown)"
      echo "  * fs.protected_symlinks: $(sysctl -n fs.protected_symlinks 2>/dev/null || echo unknown)"
      echo "  * fs.protected_fifos: $(sysctl -n fs.protected_fifos 2>/dev/null || echo unknown)"
      echo "  * fs.protected_regular: $(sysctl -n fs.protected_regular 2>/dev/null || echo unknown)"
      echo "  * net.ipv4.tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
      echo "  * net.core.default_qdisc: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    fi
    echo "====================================="
    exit 0
    ;;
  storage|disk|filesystem)
    echo "Category: System Core / Storage & Filesystem"
    if is_windows; then
      echo "Mounted Volumes & Free Space:"
      run_ps 'Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { "  * Drive $($_.DriveLetter): [$($_.FileSystem)] $([math]::Round($_.SizeRemaining/1GB, 1)) GB free of $([math]::Round($_.Size/1GB, 1)) GB" }' 2>/dev/null || true
      # fsutil prints translated text in the OEM code page (bytes that are not valid UTF-8), so only the
      # number after "=" is read (LC_ALL=C: "." must match any byte) and the explanation is written here.
      trim_val=$(fsutil.exe behavior query DisableDeleteNotify 2>&1 | LC_ALL=C grep -a -i "NTFS" | LC_ALL=C sed -nE 's/.*=[[:space:]]*([0-9]+).*/\1/p' | head -n 1 || true)
      case "$trim_val" in
        0) trim_status="NTFS DisableDeleteNotify = 0  (TRIM operations are sent to the storage device)" ;;
        1) trim_status="NTFS DisableDeleteNotify = 1  (TRIM is disabled)" ;;
        *) trim_status="unknown" ;;
      esac
      echo "SSD TRIM Status: $trim_status"
      sn_status=$(run_ps 'switch ((Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name NtfsDisable8dot3NameCreation)) { 0 { "Enabled on all volumes" } 1 { "Disabled on all volumes" } 2 { "Per volume setting (the default)" } 3 { "Disabled, except on the system volume" } default { "unknown" } }' 2>/dev/null || true)
      sn_status="${sn_status:-unknown}"
      echo "NTFS 8.3 Short Name Creation: $sn_status"
      echo "Triad Checkpoints (Performance, Configuration, Security):"
      echo "  * Performance: NVMe/SSD TRIM enabled (DisableDeleteNotify=0), weekly Optimize-Volume -ReTrim"
      echo "  * Configuration: Disable 8.3 name creation on secondary data drives (fsutil 8dot3name set <drive> 1)"
      echo "  * Security: BitLocker drive encryption status, NTFS access control lists"
    else
      root_dev=$(df --output=source / 2>/dev/null | tail -1 || echo "")
      echo "Root Device: $root_dev"
      echo "Mount Options: $(findmnt -n -o OPTIONS / 2>/dev/null || echo defaults)"
      echo "fstrim.timer Status: $(systemctl is-active fstrim.timer 2>/dev/null || echo inactive) ($(systemctl is-enabled fstrim.timer 2>/dev/null || echo disabled))"
      echo "Fstab Config: /etc/fstab"
    fi
    echo "====================================="
    exit 0
    ;;
  memory|swap|zram)
    echo "Category: System Core / Memory & Paging"
    if is_windows; then
      mem_info=$(run_ps '
        $os = Get-CimInstance Win32_OperatingSystem
        $pf = Get-CimInstance Win32_PageFileUsage | Measure-Object -Property AllocatedBaseSize -Sum
        $mm = try { (Get-MMAgent -ErrorAction SilentlyContinue).MemoryCompression } catch { $null }
        [PSCustomObject]@{
          RAMTotalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
          RAMFreeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
          PagefileGB = if ($pf.Sum) { [math]::Round($pf.Sum / 1KB, 2) } else { 0 }
          MemCompression = if ($null -ne $mm) { [bool]$mm } else { $true }
        } | ConvertTo-Json -Compress
      ' 2>/dev/null || true)
      ram_tot=$(echo "$mem_info" | grep -oE '"RAMTotalGB":[0-9.]+' | cut -d: -f2 || echo "16.0")
      ram_free=$(echo "$mem_info" | grep -oE '"RAMFreeGB":[0-9.]+' | cut -d: -f2 || echo "8.0")
      page_file=$(echo "$mem_info" | grep -oE '"PagefileGB":[0-9.]+' | cut -d: -f2 || echo "16.0")
      mem_comp=$(echo "$mem_info" | grep -oE '"MemCompression":(true|false)' | cut -d: -f2 || echo "true")
      echo "Total Physical RAM: ${ram_tot} GiB (${ram_free} GiB free)"
      echo "Paging File (Allocated): ${page_file} GiB"
      echo "Windows Memory Compression: $mem_comp"
      echo "Triad Checkpoints (Performance, Configuration, Security):"
      echo "  * Performance: Enable-MMAgent -mc (compressed in-RAM paging, eliminates SSD paging stalls)"
      echo "  * Configuration: Fixed or system-managed pagefile on fastest NVMe drive"
      echo "  * Security: Memory Integrity (HVCI) and Virtualization-Based Security (VBS)"
    else
      echo "Total Memory: $(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || echo unknown)"
      echo "Swap: $(free -h 2>/dev/null | awk '/Swap:/ {print $2}' || echo unknown)"
      if command -v zramctl >/dev/null 2>&1; then
        echo "zram Devices:"
        zramctl 2>/dev/null || true
      fi
      echo "Relevant Configs:"
      for f in /etc/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
    fi
    echo "====================================="
    exit 0
    ;;
  cpu|governor|power)
    echo "Category: System Core / CPU & Power Management"
    if is_windows; then
      cpu_name=$(run_ps '(Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()' 2>/dev/null || echo "unknown")
      threads=$(run_ps '(Get-CimInstance Win32_Processor | Select-Object -First 1).NumberOfLogicalProcessors' 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-unknown}")
      power_raw=$(run_ps '(powercfg /getactivescheme 2>$null | Out-String).Trim()' 2>/dev/null || true)
      power_scheme=$(power_plan_name "$power_raw")
      [[ -n "$power_scheme" ]] || power_scheme="unknown"
      echo "CPU: $cpu_name ($threads threads)"
      echo "Active Power Scheme: $power_scheme"
      echo "Triad Checkpoints (Performance, Configuration, Security):"
      echo "  * Performance: High Performance or Ultimate Performance scheme (powercfg /s <guid>)"
      echo "  * Configuration: Set 100% min/max processor state on AC, disable core parking on desktop"
      echo "  * Security: Hardware mitigation status (Spectre/Meltdown), AMD SVM / Intel VT-x enabled"
    else
      echo "CPU Model: $(lscpu 2>/dev/null | grep 'Model name:' | sed 's/Model name:[ \t]*//' || echo unknown)"
      echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
      echo "Microcode: $(grep -m1 'microcode' /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo unknown)"
      echo "Power Daemons:"
      for d in power-profiles-daemon tlp cpupower thermald auto-cpufreq; do
        if systemctl is-active "$d" >/dev/null 2>&1; then
          echo "  - [ACTIVE] $d"
        fi
      done
    fi
    echo "====================================="
    exit 0
    ;;
  boot|systemd|startup)
    echo "Category: System Core / Boot Performance & Startup Applications"
    if is_windows; then
      uptime_str=$(run_ps '
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os.LastBootUpTime) {
          $span = (Get-Date) - $os.LastBootUpTime
          "$($span.Days)d $($span.Hours)h $($span.Minutes)m"
        } else { "unknown" }
      ' 2>/dev/null || echo "unknown")
      fast_boot=$(run_ps '
        $hb = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
        if ($null -ne $hb) { [bool]$hb } else { $true }
      ' 2>/dev/null || echo "true")
      echo "System Uptime: $uptime_str"
      echo "Fast Startup (Hiberboot): $fast_boot"
      echo "Startup Applications:"
      run_ps 'Get-CimInstance Win32_StartupCommand | ForEach-Object { "  * $($_.Name): $($_.Command)" }' 2>/dev/null || true
      echo "Stopped Automatic Services:"
      run_ps 'Get-Service | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -ne "Running" } | ForEach-Object { "  * $($_.Name)" }' 2>/dev/null || true
      echo "Triad Checkpoints (Performance, Configuration, Security):"
      echo "  * Performance: Disable high-impact startup items (game clients, telemetry daemons, redundant updaters)"
      echo "  * Configuration: Set non-essential auto services to Delayed Start (StartType: AutomaticDelayedStart)"
      echo "  * Security: Verify Secure Boot status (Confirm-SecureBootUEFI)"
    else
      echo "Startup Time: $(systemd-analyze 2>/dev/null | head -n 1 || echo unknown)"
      echo "Failed Units: $(systemctl --failed --no-legend 2>/dev/null | wc -l || true) unit(s)"
      echo "Journal Usage: $(journalctl --disk-usage 2>/dev/null || echo unknown)"
    fi
    echo "====================================="
    exit 0
    ;;
  firewall|ufw|nftables|firewalld|defender)
    echo "Category: Security / Firewall & Host Protection"
    if is_windows; then
      echo "Windows Defender Firewall Status:"
      run_ps 'Get-NetFirewallProfile | ForEach-Object { "  * Profile $($_.Name): Enabled=$($_.Enabled), DefaultInboundAction=$($_.DefaultInboundAction), DefaultOutboundAction=$($_.DefaultOutboundAction)" }' 2>/dev/null || true
      echo "Windows Defender Antivirus Status:"
      run_ps '
        $mp = try { Get-MpComputerStatus } catch { $null }
        if ($mp) {
          "  * Real-Time Protection: $($mp.RealTimeProtectionEnabled)"
          "  * Antivirus Engine: $($mp.AntivirusEnabled)"
          "  * Signature Age: $([math]::Round($mp.AntivirusSignatureAge, 1)) day(s)"
        }
      ' 2>/dev/null || true
      echo "Listening TCP Ports:"
      if command -v netstat >/dev/null 2>&1; then
        netstat -ano -p tcp 2>/dev/null | grep -i "LISTENING" | awk '{print "    * " $2}' | sort -u || true
      fi
      echo "Triad Checkpoints (Performance, Configuration, Security):"
      echo "  * Security: All 3 profiles Enabled with BlockInbound default, Enable PUAProtection (Set-MpPreference -PUAProtection 1)"
      echo "  * Performance: Add developer folder exclusions for local git builds (target, node_modules) to avoid Defender CPU lockup"
      echo "  * Configuration: Tamper Protection active, Cloud-delivered protection level: High"
    else
      for fw in ufw nftables firewalld; do
        if command -v "$fw" >/dev/null 2>&1; then
          echo "  - $fw: active=$(systemctl is-active "$fw" 2>/dev/null || echo inactive), enabled=$(systemctl is-enabled "$fw" 2>/dev/null || echo disabled)"
        fi
      done
      echo "Listening TCP Ports:"
      ss -tlnH 2>/dev/null | awk '{print "    * " $4}' | sort -u || echo "    (none)"
    fi
    echo "====================================="
    exit 0
    ;;
  ssh|sshd)
    echo "Category: Security / SSH Configuration & Service"
    if is_windows; then
      sshd_svc=$(run_ps '(Get-Service -Name sshd -ErrorAction SilentlyContinue).Status' 2>/dev/null || echo "NotInstalled")
      echo "OpenSSH Server Service: $sshd_svc"
      echo "Config Locations:"
      for f in "$HOME/.ssh/config" "/c/ProgramData/ssh/sshd_config"; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
      echo "Local Key Directory: $HOME/.ssh"
      [[ -d "$HOME/.ssh" ]] && echo "  - Permissions: n/a (NTFS ACLs, not POSIX modes)"
    else
      echo "sshd Service: $(systemctl is-active sshd 2>/dev/null || echo inactive) ($(systemctl is-enabled sshd 2>/dev/null || echo disabled))"
      echo "SSH Configs:"
      for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf ~/.ssh/config; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
      if command -v sshd >/dev/null 2>&1; then
        sshd_t=$(sshd -T 2>/dev/null || true)
        if [[ -n "$sshd_t" ]]; then
          echo "Effective SSH Settings:"
          echo "  * PermitRootLogin: $(echo "$sshd_t" | grep -i '^permitrootlogin' | awk '{print $2}')"
          echo "  * PasswordAuthentication: $(echo "$sshd_t" | grep -i '^passwordauthentication' | awk '{print $2}')"
        fi
      fi
      echo "Permissions of ~/.ssh directory: $(stat -c '%a' "$HOME/.ssh" 2>/dev/null || echo absent)"
    fi
    echo "====================================="
    exit 0
    ;;
  execution-policy|uac)
    echo "Category: Security / Windows Policies & Access Control"
    if is_windows; then
      run_ps '
        $ep = Get-ExecutionPolicy
        $uac = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue)
        "PowerShell ExecutionPolicy: $ep"
        "User Account Control (EnableLUA): $($uac.EnableLUA)"
        "ConsentPromptBehaviorAdmin: $($uac.ConsentPromptBehaviorAdmin) (5 = Prompt for non-Windows, 2 = Prompt for all on Secure Desktop)"
      ' 2>/dev/null || true
      echo "Triad Checkpoints (Performance, Configuration, Security):"
      echo "  * Security: Enforce RemoteSigned policy to prevent arbitrary script execution from web downloads"
      echo "  * Security: Ensure UAC EnableLUA=1 with Secure Desktop prompting"
    fi
    echo "====================================="
    exit 0
    ;;
  winget)
    echo "Category: Package Manager / Windows Package Manager (winget)"
    winget_bin=$(command -v winget 2>/dev/null || echo "")
    echo "Binary: ${winget_bin:-Not installed}"
    winget_ver="unknown"
    if [[ -n "$winget_bin" ]]; then
      winget_ver=$(winget --version 2>/dev/null || echo "unknown")
    fi
    echo "Version: $winget_ver"

    winget_settings="$local_app_data/Packages/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe/LocalState/settings.json"
    echo "Configuration File:"
    if [[ -f "$winget_settings" ]]; then
      echo "  - [EXISTS] $winget_settings"
      echo "Configured Settings:"
      auto_sync=$(grep -E '"autoUpdateIntervalInMinutes"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default (0)")
      telemetry_dis=$(grep -E '"disable"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default")
      downloader=$(grep -E '"downloader"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default")
      pbar=$(grep -E '"progressBar"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default")
      echo "  * Source Sync Interval: ${auto_sync} minutes"
      echo "  * Telemetry Disabled: ${telemetry_dis}"
      echo "  * Downloader Engine: ${downloader}"
      echo "  * Visual Progress Bar: ${pbar}"
    else
      echo "  - [NOT FOUND] $winget_settings (Run 'winget settings' to generate)"
    fi

    echo "Security / Admin Policies (from winget --info):"
    winget --info 2>/dev/null | grep -E "InstallerHashOverride|LocalArchiveMalwareScanOverride|BypassCertificatePinning" | while read -r line; do
      echo "  * $line"
    done || true
    echo "Administrator settings (winget settings export, language-independent):"
    winget settings export 2>/dev/null | tr -d '\r' | grep -oE '"(BypassCertificatePinningForMicrosoftStore|InstallerHashOverride|LocalArchiveMalwareScanOverride|LocalManifestFiles)"[[:space:]]*:[[:space:]]*(true|false)' | sed -E 's/^"([^"]+)"[[:space:]]*:[[:space:]]*/  * \1: /' || echo "  (not available in this winget version)"

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set 'source.autoUpdateIntervalInMinutes: 120' to eliminate 5-10s source sync stall on every invocation"
    echo "  * Performance: Set 'network.downloader: default' (direct WinINet bypasses Delivery Optimization freezes)"
    echo "  * Configuration: Set 'visual.progressBar: rainbow', configure portable package link directories"
    echo "  * Security: Disable telemetry ('telemetry.disable: true'), ensure InstallerHashOverride and BypassCertificatePinning remain Disabled"
    echo "====================================="
    exit 0
    ;;
  windows-terminal|wt)
    echo "Category: Terminal Emulator / Windows Terminal"
    wt_bin=$(command -v wt 2>/dev/null || echo "")
    echo "Binary: ${wt_bin:-App Execution Alias (wt.exe)}"

    wt_settings=""
    for candidate in \
      "$local_app_data/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
      "$local_app_data/Microsoft/Windows Terminal/settings.json" \
      "$local_app_data/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"; do
      if [[ -f "$candidate" ]]; then
        wt_settings="$candidate"
        break
      fi
    done

    echo "Discovered Configuration File:"
    if [[ -n "$wt_settings" ]]; then
      echo "  - [EXISTS] $wt_settings"
      echo "Active Configuration Inspection:"
      def_prof=$(grep -E '"defaultProfile"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "default")
      anim_dis=$(grep -E '"disableAnimations"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "false")
      copy_fmt=$(grep -E '"copyFormatting"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "all")
      echo "  * Default Profile GUID: $def_prof"
      echo "  * Disable Animations: $anim_dis"
      echo "  * Copy Formatting: $copy_fmt"
      atlas_eng=$(grep -E '"useAtlasEngine"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "default (true)")
      echo "  * Atlas GPU Text Engine: $atlas_eng"
    else
      echo "  - Standard settings.json not found yet."
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Hardware-accelerated Atlas text rendering engine ('useAtlasEngine: true'), set 'disableAnimations: true' for instantaneous tab/pane switching"
    echo "  * Configuration: Set pwsh (PowerShell 7) or Git Bash as default profile, 'copyFormatting: none', Nerd Font face ('Hack Nerd Font')"
    echo "  * Security: Avoid profiles that auto-elevate without prompt; review custom action command injection"
    echo "====================================="
    exit 0
    ;;
  wsl)
    echo "Category: Subsystem & Virtualization / Windows Subsystem for Linux (WSL)"
    wsl_bin=$(command -v wsl 2>/dev/null || command -v wsl.exe 2>/dev/null || echo "")
    echo "Binary: ${wsl_bin:-/c/Windows/System32/wsl.exe}"
    wsl_ver=$(wsl.exe --version 2>/dev/null | tr -d '\0\r' || true)
    # without WSL, wsl.exe prints its help text (translated, but it always names "wsl.exe")
    case "$wsl_ver" in
      ""|*wsl.exe*) wsl_ver="unknown (WSL is not installed)" ;;
      # the label is translated and may carry OEM-encoded bytes ("Versão do WSL: 3.0.1.0"): keep the number
      *) wsl_ver=$(LC_ALL=C grep -a -oE '[0-9]+(\.[0-9]+){1,3}' <<< "$wsl_ver" | head -n 1 || true)
         wsl_ver="${wsl_ver:-unknown}" ;;
    esac
    echo "Version: $wsl_ver"

    echo "Discovered Configuration Files:"
    wsl_cfg_candidates=("$HOME/.wslconfig" "/etc/wsl.conf")
    if [[ -n "${USERPROFILE:-}" ]]; then
      wsl_cfg_candidates+=("${USERPROFILE}/.wslconfig")
      if command -v cygpath >/dev/null 2>&1; then
        wsl_cfg_candidates+=("$(cygpath -u "$USERPROFILE" 2>/dev/null)/.wslconfig")
      fi
    fi
    if command -v wslpath >/dev/null 2>&1 && command -v cmd.exe >/dev/null 2>&1; then
      win_prof=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n' || echo "")
      if [[ -n "$win_prof" ]]; then
        wsl_cfg_candidates+=("$(wslpath -u "$win_prof" 2>/dev/null)/.wslconfig")
      fi
    fi
    for f in "${wsl_cfg_candidates[@]}"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Registered WSL Distributions:"
    # Without WSL, wsl.exe prints its help text; without a distribution it prints a message with the
    # Store link (and normally fails). The texts are translated, so judge by the exit status and by
    # the program name or link they contain, not by words.
    wsl_list=""
    wsl_list=$(wsl.exe -l -v 2>/dev/null | tr -d '\0\r') || wsl_list=""
    if [[ -z "$wsl_list" || "$wsl_list" == *"wsl.exe"* || "$wsl_list" == *"aka.ms/"* ]]; then
      echo "  (none: no WSL distribution is installed)"
    else
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  * $line"
      done <<< "$wsl_list"
    fi

    wsl_conf_file=""
    for candidate in "${wsl_cfg_candidates[@]}"; do
      if [[ -f "$candidate" && "$candidate" == *".wslconfig" ]]; then
        wsl_conf_file="$candidate"
        break
      fi
    done
    if [[ -n "$wsl_conf_file" ]]; then
      echo "Current $wsl_conf_file Parameters:"
      grep -E 'memory|processors|swap|autoMemoryReclaim|sparseVhd|dnsTunneling|networkingMode|firewall' "$wsl_conf_file" 2>/dev/null | while read -r line; do
        echo "  - $line"
      done || true
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set 'memory = 8GB' (bound to 50% host RAM), 'autoMemoryReclaim = dropcache' (reclaims cached memory to Windows),"
    echo "                 'sparseVhd = true' (auto-compacts ext4 disk image on file deletion), processors bound to CPU cores"
    echo "  * Configuration: Set 'networkingMode = mirrored' for low latency and Windows localhost parity, 'dnsTunneling = true'"
    echo "  * Security: Set 'firewall = true' with mirrored networking to apply Windows Defender Firewall rules inside WSL"
    echo "====================================="
    exit 0
    ;;
  pwsh|powershell)
    echo "Category: Shell Environment / PowerShell"
    ps_bin=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || echo "")
    echo "Binary: ${ps_bin:-unknown}"
    ps_ver=$(run_ps '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || echo "unknown")
    echo "Version: $ps_ver"

    echo "PowerShell Profile Paths:"
    run_ps '
      $paths = @(
        $PROFILE.CurrentUserCurrentHost,
        $PROFILE.CurrentUserAllHosts,
        $PROFILE.AllUsersCurrentHost,
        $PROFILE.AllUsersAllHosts
      )
      foreach ($p in $paths) {
        if ($p) {
          $ex = if (Test-Path $p) { "[EXISTS]" } else { "[NOT FOUND]" }
          "  - $ex $p"
        }
      }
    ' 2>/dev/null || true

    echo "Environment & PSReadLine Status:"
    run_ps '
      $ep = Get-ExecutionPolicy
      "  * ExecutionPolicy: $ep"
      $psr = try { Get-PSReadLineOption } catch { $null }
      if ($psr) {
        "  * PSReadLine PredictionSource: $($psr.PredictionSource)"
        "  * PSReadLine EditMode: $($psr.EditMode)"
        "  * PSReadLine HistorySavePath: $($psr.HistorySavePath)"
      }
    ' 2>/dev/null || true

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Deferred module loading, starship/zoxide static init caching, PATH deduplication"
    echo "  * Configuration: Set PSReadLine PredictionSource HistoryAndPlugin, PredictionViewStyle ListView, custom aliases"
    echo "  * Security: Set ExecutionPolicy RemoteSigned, scrub plaintext secrets from PSReadLine history"
    echo "====================================="
    exit 0
    ;;
  powertoys)
    echo "Category: Desktop Utilities / Microsoft PowerToys"
    pt_settings="$local_app_data/Microsoft/PowerToys/settings.json"
    echo "Configuration File: $pt_settings $(if [[ -f "$pt_settings" ]]; then echo "[EXISTS]"; else echo "[NOT FOUND]"; fi)"
    if [[ -f "$pt_settings" ]]; then
      echo "Enabled Modules:"
      run_ps '
        $pt = Get-Content "'"$pt_settings"'" -Raw | ConvertFrom-Json
        $pt.enabled | Get-Member -MemberType NoteProperty | ForEach-Object {
          $val = $pt.enabled.$($_.Name)
          "  * $($_.Name): $val"
        }
      ' 2>/dev/null || true
    fi
    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Disable unused background modules (Awake, Mouse utilities, Video Conference Mute) to save memory & thread handles"
    echo "  * Configuration: PowerToys Run hotkey & plugins, FancyZones multi-monitor window tiling"
    echo "  * Security: Restrict administrator mode elevation prompt for plugins"
    echo "====================================="
    exit 0
    ;;
  bash|shell|.bashrc)
    echo "Category: Shell Environment / Bash Configuration"
    echo "Bash Version: $BASH_VERSION"
    echo "Relevant Config Files:"
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bash_aliases" "$HOME/.bash_logout" "$HOME/.minttyrc"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done
    if [[ -d "$HOME/.bash_completion.d" ]]; then
      echo "  - [EXISTS DIR] $HOME/.bash_completion.d"
    fi

    echo "Performance Metrics:"
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      for _ in 1 2 3; do bash -i -c exit > /dev/null 2>&1 || true; done
      lat_start="${EPOCHREALTIME/,/.}"   # some locales print a comma
      for _ in 1 2 3 4 5; do bash -i -c exit > /dev/null 2>&1 || true; done
      lat_end="${EPOCHREALTIME/,/.}"
      startup_ms=$(awk -v s="$lat_start" -v e="$lat_end" 'BEGIN { printf "%.1f", (e - s) / 5 * 1000 }')
      echo "  * Interactive Startup Latency: ~${startup_ms} ms"
    else
      echo "  * Interactive Startup Latency: n/a (needs bash 5: EPOCHREALTIME)"
    fi

    echo "Security & Hygiene Checks:"
    if [[ "$PATH" =~ (^|:)\.($|:) || "$PATH" =~ :: ]]; then
      echo "  * [WARNING] PATH contains relative '.' or empty entry! High security risk for binary hijacking."
    else
      echo "  * PATH Sanitation: OK (No relative or empty directories)"
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Pre-compiled static init caches for starship/fzf/zoxide, mise shims, completion caching"
    echo "  * Configuration: History deduplication, directory spell/autocd, modular ~/.config/bash/ split, aliases"
    echo "  * Security: Explicit umask, safe PATH ordering, restricted permissions on sourced credentials"
    echo "====================================="
    exit 0
    ;;
  pi|pi-agent|agent)
    echo "Category: Agent Harness / Pi Coding Agent"
    pi_bin=$(command -v pi 2>/dev/null || echo "")
    echo "Binary: ${pi_bin:-unknown (running via wrapper/npx)}"
    pi_ver="unknown"
    if [[ -n "$pi_bin" ]]; then
      pi_ver=$("$pi_bin" --version 2>/dev/null || echo "unknown")
    fi
    echo "Version: $pi_ver"

    echo "Configuration & State Files:"
    for f in "$HOME/.pi/agent/settings.json" "$HOME/.pi/agent/auth.json" "$HOME/.pi/agent/mcp.json" "$HOME/.pi/agent/model-router.json" "$HOME/.pi/agent/models.json" "$HOME/.pi/web-search.json"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Performance & Storage Metrics:"
    sessions_dir="$HOME/.pi/agent/sessions"
    if [[ -d "$sessions_dir" ]]; then
      sess_count=$(find "$sessions_dir" -type f -name "*.jsonl" 2>/dev/null | wc -l || true)
      sess_size=$(du -sh "$sessions_dir" 2>/dev/null | awk '{print $1}' || echo "0")
      echo "  * Saved Sessions: $sess_count session files ($sess_size disk usage)"
    fi
    cache_dir="$HOME/.pi/web-search-cache"
    if [[ -d "$cache_dir" ]]; then
      cache_size=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}' || echo "0")
      echo "  * Web Search Cache: $cache_size"
    fi

    echo "Mise Toolchain Synergy in Agent Harness:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      echo "  * Mise Binary Detected: $mise_bin"
      mise_shims="$HOME/.local/share/mise/shims"
      if is_windows; then
        mise_shims="$local_app_data/mise/shims"
      fi
      if [[ -d "$mise_shims" ]]; then
        echo "  * Mise Shims Directory: [EXISTS] ($mise_shims)"
        if [[ ":$PATH:" == *":$mise_shims:"* ]]; then
          echo "  * Shims on Agent PATH: [ACTIVE] (Subshell commands inherit project-pinned runtimes)"
        else
          echo "  * Shims on Agent PATH: [NOT ON PATH] (Ensure mise shims are exported in subshell environments)"
        fi
      fi
    else
      echo "  * Mise not detected on this system."
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Session file archival (>30d), cache pruning, compaction reserve tuning (16384)"
    echo "  * Configuration: Inherit mise shims on PATH for subshell execution (Node, Python, Rust, Go, UV); model router latency tuning"
    echo "  * Security: auth.json 0600 mode, path deny rules (SSH/secrets), npm package supply-chain audit"
    echo "====================================="
    exit 0
    ;;
  controld|ctrld)
    echo "Category: Network & DNS / Control D Encrypted Resolver Daemon"
    ctrld_bin=$(command -v ctrld 2>/dev/null || command -v controld 2>/dev/null || echo "")
    echo "Binary: ${ctrld_bin:-Not installed}"
    if [[ -n "$ctrld_bin" ]]; then
      ctrld_ver=$("$ctrld_bin" version 2>/dev/null || "$ctrld_bin" --version 2>/dev/null || echo "unknown")
      echo "Version: $ctrld_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in \
      "/etc/controld/ctrld.toml" \
      "/etc/ctrld/ctrld.toml" \
      "$roaming_app_data/controld/ctrld.toml" \
      "/c/ProgramData/ControlD/ctrld.toml" \
      "$HOME/.config/controld/ctrld.toml"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: In-memory cache enabled, DoQ (DNS-over-QUIC) primary with DoH failover, LAN discovery off"
    echo "  * Configuration: Local loopback listener 127.0.0.1:53, adapter DNS integration, log level notice"
    echo "  * Security: Encrypted upstream transport, secure config permissions (0600)"
    echo "====================================="
    exit 0
    ;;
  rustdesk)
    echo "Category: Remote Desktop / RustDesk Remote Access"
    rd_bin=$(command -v rustdesk 2>/dev/null || echo "")
    echo "Binary: ${rd_bin:-Not installed (Windows App or Service)}"

    echo "Discovered Configuration Files:"
    for f in \
      "$HOME/.config/rustdesk/RustDesk.toml" \
      "$HOME/.config/rustdesk/RustDesk2.toml" \
      "$roaming_app_data/RustDesk/config/RustDesk.toml" \
      "$roaming_app_data/RustDesk/config/RustDesk2.toml" \
      "$roaming_app_data/RustDesk/config/peers.toml" \
      "/etc/rustdesk/rustdesk.toml"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Hardware video acceleration (NVENC on NVIDIA RTX, D3D11/DirectX on Windows, VA-API on Linux)"
    echo "  * Configuration: Custom ID/relay server, on-demand vs background service mode, tray minimization"
    echo "  * Security: Strong randomized temporary passwords, whitelist allowed peer IDs, restrict remote console execution"
    echo "====================================="
    exit 0
    ;;
  mpv)
    echo "Category: Media Player / mpv Video Player"
    mpv_bin=$(command -v mpv 2>/dev/null || echo "")
    echo "Binary: ${mpv_bin:-Not installed}"
    if [[ -n "$mpv_bin" ]]; then
      mpv_ver=$("$mpv_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $mpv_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in \
      "$roaming_app_data/mpv/mpv.conf" \
      "$HOME/.config/mpv/mpv.conf" \
      "$local_app_data/mpv/mpv.conf"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    mpv_cfg=""
    for f in "$roaming_app_data/mpv/mpv.conf" "$HOME/.config/mpv/mpv.conf" "$local_app_data/mpv/mpv.conf"; do
      if [[ -f "$f" ]]; then
        mpv_cfg="$f"
        break
      fi
    done

    if [[ -n "$mpv_cfg" ]]; then
      echo "Key Parameters in $mpv_cfg:"
      grep -E '^(vo|gpu-api|hwdec|profile|target-colorspace-hint|interpolation|scale|ytdl-format|tone-mapping)=' "$mpv_cfg" 2>/dev/null | while read -r line; do
        echo "  * $line"
      done || true
    fi

    echo "MPV + yt-dlp + GPU HWDEC Companion Synergy:"
    ytdl_bin=$(command -v yt-dlp 2>/dev/null || echo "")
    if [[ -n "$ytdl_bin" ]]; then
      ytdl_ver=$("$ytdl_bin" --version 2>/dev/null || echo "unknown")
      echo "  * Media Streamer (yt-dlp): [AVAILABLE] ($ytdl_bin $ytdl_ver)"
    else
      echo "  * Media Streamer (yt-dlp): [NOT FOUND] (Install yt-dlp to stream web video directly to mpv)"
    fi

    hwdec_choice="hwdec=auto-safe"
    if [[ "$detected_gpu" =~ (NVIDIA|GeForce|RTX|GTX) ]]; then
      hwdec_choice="hwdec=nvdec-copy (NVIDIA RTX / discrete GPU)"
    elif [[ "$detected_gpu" =~ (AMD|Radeon) ]]; then
      hwdec_choice="hwdec=vaapi (Linux) / d3d11va (Windows AMD Radeon)"
    elif [[ "$detected_gpu" =~ (Intel) ]]; then
      hwdec_choice="hwdec=vaapi (Linux) / d3d11va (Windows Intel Graphics)"
    fi
    echo "  * Hardware Decoder: $hwdec_choice"
    echo "  * Browser Bypass: Direct mpv streaming bypasses heavy Chromium/browser CPU and RAM consumption"

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Stream web video directly to mpv via yt-dlp; use 'vo=gpu-next', 'gpu-api=d3d11' (Windows) or 'vulkan' (Linux), $hwdec_choice"
    echo "  * Configuration: HDR passthrough ('target-colorspace-hint=yes'), BT.2446a tone-mapping, EWA Lanczos scaling, ytdl-format bound to 1080p/best"
    echo "  * Security: Safe ytdl options, restrict untrusted lua scripts"
    echo "====================================="
    exit 0
    ;;
  topgrade)
    echo "Category: Maintenance & Update Orchestrator / Topgrade"
    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    echo "Binary: ${tg_bin:-Not installed}"
    if [[ -n "$tg_bin" ]]; then
      tg_ver=$("$tg_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $tg_ver"
    fi

    echo "Discovered Configuration Files:"
    tg_cfg=""
    for f in "$roaming_app_data/topgrade.toml" "$HOME/.config/topgrade.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$tg_cfg" ]] && tg_cfg="$f"
      fi
    done
    if [[ -d "$HOME/.config/topgrade.d" ]]; then
      echo "  - [EXISTS DIR] $HOME/.config/topgrade.d"
    fi

    if [[ -n "$tg_cfg" ]]; then
      echo "Active Topgrade Configuration:"
      cleanup_val=$(grep -E '^[[:space:]]*cleanup[[:space:]]*=' "$tg_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
      retry_val=$(grep -E '^[[:space:]]*ask_retry[[:space:]]*=' "$tg_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "true")
      dis_val=$(grep -E '^[[:space:]]*disable[[:space:]]*=' "$tg_cfg" 2>/dev/null | cut -d= -f2- || echo "[]")
      pre_sudo_val=$(grep -E '^[[:space:]]*pre_sudo[[:space:]]*=' "$tg_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
      echo "  * Post-Run Cleanup: $cleanup_val"
      echo "  * Ask Retry: $retry_val"
      echo "  * Disabled Steps: $dis_val"
      echo "  * Pre-Sudo Credential Cache: $pre_sudo_val"

      echo "Mise Companion Integration in Topgrade:"
      mise_bin=$(command -v mise 2>/dev/null || echo "")
      if [[ -n "$mise_bin" ]]; then
        tg_has_mise=$(grep -E '^[[:space:]]*\[mise\]' "$tg_cfg" 2>/dev/null || true)
        tg_bump=$(grep -A 5 '^[[:space:]]*\[mise\]' "$tg_cfg" 2>/dev/null | grep -E '^[[:space:]]*bump[[:space:]]*=' | cut -d= -f2- | tr -d ' "' || echo "false")
        tg_jobs=$(grep -A 5 '^[[:space:]]*\[mise\]' "$tg_cfg" 2>/dev/null | grep -E '^[[:space:]]*jobs[[:space:]]*=' | cut -d= -f2- | tr -d ' "' || echo "mise default")
        tg_reshim=$(grep -i "reshim" "$tg_cfg" 2>/dev/null || true)
        echo "  * Mise Binary Detected: $mise_bin"
        echo "  * [mise] Section in topgrade.toml: $(if [[ -n "$tg_has_mise" ]]; then echo "Configured (bump=$tg_bump, jobs=$tg_jobs)"; else echo "Missing / Using defaults (bump=false)"; fi)"
        echo "  * Post-Upgrade 'mise reshim' Hook: $(if [[ -n "$tg_reshim" ]]; then echo "Present in post_commands"; else echo "Missing (Add to post_commands to synchronize shims)"; fi)"
        echo "  * Redundant Runtime Self-Updater Conflicts: $(if echo "$dis_val" | grep -qi "uv"; then echo "uv disabled in topgrade (Prevented collision with mise)"; else echo "uv not disabled (May run duplicate self-update if managed by mise)"; fi)"
        echo "  * Rust Compilation De-duplication: $(if echo "$dis_val" | grep -qi "cargo"; then echo "cargo disabled in topgrade (Prevents slow from-source rebuilds, managed via mise binstall)"; else echo "cargo active in topgrade (Will compile from source; consider disabling if using mise cargo.binstall)"; fi)"
      else
        echo "  * Mise is not currently installed on this system."
      fi
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Enable cleanup = true (runs mise prune and cleans package caches); bound [mise] jobs to $(nproc 2>/dev/null || echo 4); disable uninstalled/redundant steps"
    echo "  * Configuration: Set [mise] bump = true for automatic tool version updates; add 'mise reshim' to post_commands; coordinate update order across winget/wsl/pacman/mise"
    echo "  * Security: Restrict untrusted custom commands, verify origin repository of third-party package managers; run mise unprivileged without sudo (allow_root = false)"
    echo "====================================="
    exit 0
    ;;
  mise|rtx)
    echo "Category: Polyglot Tool & Runtime Manager / mise"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    echo "Binary: ${mise_bin:-Not installed}"
    if [[ -n "$mise_bin" ]]; then
      mise_ver=$("$mise_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $mise_ver"
      if is_windows; then
        echo "Platform: Windows (Native / shims)"
      else
        if command -v pacman >/dev/null 2>&1 && pacman -Qo "$mise_bin" >/dev/null 2>&1; then
          pkg_owner=$(pacman -Qo "$mise_bin" 2>/dev/null || true)
          echo "Installation Method: Package Manager ($pkg_owner)"
        else
          echo "Installation Method: Standalone Binary ($mise_bin)"
        fi
      fi
    fi

    echo "Discovered Configuration Files:"
    mise_cfg=""
    for f in "$HOME/.config/mise/config.toml" "$HOME/.config/mise/settings.toml" "$local_app_data/mise/config.toml" "$roaming_app_data/mise/config.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$mise_cfg" && "$f" == *config.toml ]] && mise_cfg="$f"
      fi
    done

    if [[ -n "$mise_cfg" ]]; then
      echo "Active Mise Configuration ($mise_cfg):"
      m_jobs=$(grep -E '^[[:space:]]*jobs[[:space:]]*=' "$mise_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "default (4)")
      m_env_cache=$(grep -E '^[[:space:]]*env_cache[[:space:]]*=' "$mise_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
      m_pin=$(grep -E '^[[:space:]]*pin[[:space:]]*=' "$mise_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
      m_prune_age=$(grep -E '^[[:space:]]*cache_prune_age[[:space:]]*=' "$mise_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "30d")
      m_binstall=$(grep -E '^[[:space:]]*binstall[[:space:]]*=' "$mise_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
      echo "  * Parallel Jobs: $m_jobs (Hardware thread budget: $(nproc 2>/dev/null || echo 4))"
      echo "  * Environment Caching (env_cache): $m_env_cache"
      echo "  * Version Pinning (pin): $m_pin"
      echo "  * Cache Prune Age: $m_prune_age"
      echo "  * Cargo Binstall (precompiled binaries): $m_binstall"
    fi

    if [[ -n "$mise_bin" ]]; then
      echo "Mise Runtime & Tool Summary:"
      tool_count=$("$mise_bin" ls --current 2>/dev/null | wc -l || true)
      echo "  * Active/Managed Tools: $tool_count installed"
    fi

    echo "Topgrade Integration Status:"
    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    if [[ -n "$tg_bin" ]]; then
      tg_cfg=""
      for tf in "$roaming_app_data/topgrade.toml" "$HOME/.config/topgrade.toml"; do
        [[ -f "$tf" ]] && tg_cfg="$tf" && break
      done
      if [[ -n "$tg_cfg" ]]; then
        tg_has_mise_table=$(grep -E '^[[:space:]]*\[mise\]' "$tg_cfg" 2>/dev/null || true)
        tg_mise_bump=$(grep -A 5 '^[[:space:]]*\[mise\]' "$tg_cfg" 2>/dev/null | grep -E '^[[:space:]]*bump[[:space:]]*=' | cut -d= -f2- | tr -d ' "' || echo "false")
        tg_mise_jobs=$(grep -A 5 '^[[:space:]]*\[mise\]' "$tg_cfg" 2>/dev/null | grep -E '^[[:space:]]*jobs[[:space:]]*=' | cut -d= -f2- | tr -d ' "' || echo "mise default")
        tg_cleanup=$(grep -E '^[[:space:]]*cleanup[[:space:]]*=' "$tg_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
        tg_has_reshim=$(grep -i "reshim" "$tg_cfg" 2>/dev/null || true)
        echo "  - Topgrade Config: $tg_cfg"
        echo "  - Native [mise] Step in Topgrade: $(if [[ -n "$tg_has_mise_table" ]]; then echo "Configured (bump=$tg_mise_bump, jobs=$tg_mise_jobs)"; else echo "Default/Unconfigured"; fi)"
        echo "  - Automated Cache/Version Pruning: $(if [[ "$tg_cleanup" == "true" ]]; then echo "Enabled (Topgrade runs mise prune during cleanup)"; else echo "Disabled (Set cleanup = true)"; fi)"
        echo "  - Post-Update Shim Sync (mise reshim): $(if [[ -n "$tg_has_reshim" ]]; then echo "Configured in post_commands"; else echo "Not detected in post_commands (Recommended)"; fi)"
      else
        echo "  - Topgrade installed but topgrade.toml not yet found."
      fi
    else
      echo "  - Topgrade not installed (Recommended companion for workstation maintenance orchestration)."
    fi

    echo "Neovim Companion Status:"
    nv_bin=$(command -v nvim 2>/dev/null || command -v neovim 2>/dev/null || echo "")
    if [[ -n "$nv_bin" ]]; then
      nv_cfg=""
      for nf in "$local_app_data/nvim/init.lua" "$HOME/.config/nvim/init.lua"; do
        [[ -f "$nf" ]] && nv_cfg="$nf" && break
      done
      echo "  - Neovim Binary Detected: $nv_bin"
      echo "  - Config: ${nv_cfg:-Not found}"
      echo "  - LSP Provisioning: Mise shims serve as single-source polyglot LSP, formatter, linter & DAP runtime"
      if [[ -n "$nv_cfg" ]]; then
        nv_dir=$(dirname "$nv_cfg")
        mason_file=$(find "$nv_dir" -name "*mason*.lua" 2>/dev/null | head -n 1 || echo "")
        if [[ -n "$mason_file" ]] && grep -qE 'opts_extend[[:space:]]*=[[:space:]]*\{\}' "$mason_file" 2>/dev/null && grep -qE 'mason[[:space:]]*=[[:space:]]*false' "$mason_file" 2>/dev/null; then
          echo "  - Mason De-duplication: [LOCKED] (opts_extend = {} & mason = false prevent duplicate Mason installs)"
        fi
        if grep -rq "mise_env_sync" "$nv_dir/lua" 2>/dev/null; then
          echo "  - Dynamic Project Env Sync: [ACTIVE] (DirChanged -> mise env --json)"
        fi
      fi
    else
      echo "  - Neovim not installed on this system."
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Match jobs = $(nproc 2>/dev/null || echo 4); enable env_cache = true with env_cache_ttl = '1h' to eliminate subshell PATH latency; enable cargo.binstall = true"
    echo "  * Configuration: Set pin = true; configure cache_prune_age = '7d'; integrate with topgrade ([mise] bump = true, cleanup = true for mise prune, and mise reshim in post_commands)"
    echo "  * Security: Enforce supply-chain attestations (aqua.slsa, aqua.cosign, github_attestations, node.verify); restrict config permissions (0600); isolate runtime installs"
    echo "====================================="
    exit 0
    ;;
  cargo|rust|rustc)
    echo "Category: Toolchain & Package Manager / Cargo & Rust"
    cg_bin=$(command -v cargo 2>/dev/null || echo "")
    echo "Binary: ${cg_bin:-Not installed}"
    if [[ -n "$cg_bin" ]]; then
      cg_ver=$("$cg_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      rc_ver=$(rustc --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $cg_ver (rustc: $rc_ver)"
    fi

    echo "Discovered Configuration Files:"
    cg_cfg=""
    for f in "$HOME/.cargo/config.toml" "${USERPROFILE:-/nonexistent}/.cargo/config.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$cg_cfg" ]] && cg_cfg="$f"
      fi
    done

    if [[ -n "$cg_cfg" ]]; then
      echo "Active Cargo Configuration ($cg_cfg):"
      c_jobs=$(grep -E '^[[:space:]]*jobs[[:space:]]*=' "$cg_cfg" 2>/dev/null | awk -F= '{print $2}' | xargs || echo "default (num_cpus)")
      c_proto=$(grep -E '^[[:space:]]*protocol[[:space:]]*=' "$cg_cfg" 2>/dev/null | awk -F= '{print $2}' | xargs || echo "default (sparse)")
      c_gitcli=$(grep -E '^[[:space:]]*git-fetch-with-cli[[:space:]]*=' "$cg_cfg" 2>/dev/null | awk -F= '{print $2}' | xargs || echo "false")
      echo "  * Parallel Build Jobs: $c_jobs (Hardware thread budget: $(nproc 2>/dev/null || echo 4))"
      echo "  * Crates.io Protocol: $c_proto"
      echo "  * Git Fetch with CLI: $c_gitcli"
    fi

    echo "Mise & Topgrade Companion Integration:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      mise_cfg=""
      for mf in "$HOME/.config/mise/config.toml" "$local_app_data/mise/config.toml"; do
        [[ -f "$mf" ]] && mise_cfg="$mf" && break
      done
      m_binstall=$(grep -E '^[[:space:]]*cargo\.binstall[[:space:]]*=' "$mise_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "false")
      echo "  * Mise Cargo Binstall: $(if [[ "$m_binstall" == "true" ]]; then echo "[ENABLED] (Pre-compiled Rust binaries prioritized)"; else echo "[DISABLED] (Consider enabling cargo.binstall = true)"; fi)"
    else
      echo "  * Mise is not installed."
    fi

    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    if [[ -n "$tg_bin" ]]; then
      tg_cfg=""
      for tf in "$roaming_app_data/topgrade.toml" "$HOME/.config/topgrade.toml"; do
        [[ -f "$tf" ]] && tg_cfg="$tf" && break
      done
      if [[ -n "$tg_cfg" ]]; then
        dis_val=$(grep -E '^[[:space:]]*disable[[:space:]]*=' "$tg_cfg" 2>/dev/null || echo "[]")
        echo "  * Topgrade Cargo Step: $(if echo "$dis_val" | grep -qi "cargo"; then echo "[DISABLED] (Eliminated slow from-source rebuilds, delegated to mise binstall)"; else echo "[ACTIVE] (Will compile CLI tools from source; consider adding 'cargo' to disable = [...])"; fi)"
      fi
    else
      echo "  * Topgrade is not installed."
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Match build.jobs = $(nproc 2>/dev/null || echo 4); ensure registries.crates-io.protocol = 'sparse'; enable net.git-fetch-with-cli = true; prefer mise with cargo.binstall = true for global CLI tools"
    echo "  * Configuration: Disable 'cargo' step in topgrade.toml (disable = ['cargo']) when managing Rust CLIs via mise to eliminate hours of from-source rebuilds; tune codegen-units"
    echo "  * Security: Run cargo audit for supply-chain vulnerability audits; enforce Cargo.lock checksums; restrict ~/.cargo/config.toml permissions to 0600"
    echo "====================================="
    exit 0
    ;;
  ripgrep|rg)
    echo "Category: Search Utility / ripgrep (rg)"
    rg_bin=$(command -v rg 2>/dev/null || command -v ripgrep 2>/dev/null || echo "")
    echo "Binary: ${rg_bin:-Not installed}"
    if [[ -n "$rg_bin" ]]; then
      rg_ver=$("$rg_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $rg_ver"
    fi

    echo "Environment & Configuration Files:"
    echo "  * RIPGREP_CONFIG_PATH: ${RIPGREP_CONFIG_PATH:-[UNSET]}"
    for f in "$HOME/.ripgreprc" "$HOME/.config/ripgrep/config" "$roaming_app_data/ripgrep/config"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done
    echo "Ripgrep + FZF + Bat Synergy Integration:"
    if [[ "${FZF_DEFAULT_COMMAND:-}" =~ (rg|ripgrep) ]]; then
      echo "  * FZF Backend: [WIRED] (rg is active search generator in FZF_DEFAULT_COMMAND)"
    else
      echo "  * FZF Backend: [RECOMMENDED] (Wire rg as backend: export FZF_DEFAULT_COMMAND=\"rg --files --hidden --glob '!.git/*'\")"
    fi
    bat_bin=$(command -v bat 2>/dev/null || echo "")
    if [[ -n "$bat_bin" ]]; then
      echo "  * Bat Previewer: [AVAILABLE] ($bat_bin provides line-numbered syntax previews)"
    else
      echo "  * Bat Previewer: [NOT FOUND]"
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set RIPGREP_CONFIG_PATH, align threads to detected CPU cores (--threads=$detected_threads), set --max-columns=300 with preview, enable --mmap on SSDs"
    echo "  * Configuration: Enable --smart-case by default, wire rg as FZF_DEFAULT_COMMAND backend with bat syntax previews, global ignore globs (!.git, !node_modules)"
    echo "  * Security: Ignore hidden git internal files (--glob=!.git/*) to prevent credential leakage in search results"
    echo "====================================="
    exit 0
    ;;
  zoxide)
    echo "Category: Navigation / zoxide Directory Jumper"
    zo_bin=$(command -v zoxide 2>/dev/null || echo "")
    echo "Binary: ${zo_bin:-Not installed}"
    if [[ -n "$zo_bin" ]]; then
      zo_ver=$("$zo_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $zo_ver"
    fi

    echo "Database & Configuration Locations:"
    for f in "$local_app_data/zoxide/db.zo" "$HOME/.local/share/zoxide/db.zo" "$HOME/.config/zoxide"; do
      [[ -e "$f" ]] && echo "  - [EXISTS] $f"
    done

    if command -v zoxide >/dev/null 2>&1; then
      db_count=$(zoxide query -l 2>/dev/null | wc -l || true)
      echo "Tracked Directories in Database: $db_count entries"
    fi

    echo "Shell Integration:"
    pwsh_prof="$HOME/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
    if [[ -f "$pwsh_prof" ]] && grep -qi "zoxide init" "$pwsh_prof"; then
      echo "  * PowerShell ($pwsh_prof): [INITIALIZED]"
    else
      echo "  * PowerShell: [NOT CONFIGURED] (Recommend: Invoke-Expression (& { (zoxide init powershell | Out-String) }))"
    fi
    if [[ -f "$HOME/.bashrc" ]] && grep -qi "zoxide init" "$HOME/.bashrc"; then
      echo "  * Bash ($HOME/.bashrc): [INITIALIZED]"
    else
      echo "  * Bash: [NOT CONFIGURED] (Recommend: eval \"\$(zoxide init bash)\")"
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Statically cache or fast-init zoxide hook in shell profiles; periodically prune dead paths (zoxide remove)"
    echo "  * Configuration: Define aliases 'z' (jump) and 'zi' (interactive fzf jump); set _ZO_EXCLUDE_DIRS to skip temp and home root"
    echo "  * Security: Protect db.zo database file permissions (0600) to keep browsing history private"
    echo "====================================="
    exit 0
    ;;
  eza)
    echo "Category: Modern File Lister / eza"
    eza_bin=$(command -v eza 2>/dev/null || echo "")
    echo "Binary: ${eza_bin:-Not installed}"
    if [[ -n "$eza_bin" ]]; then
      eza_ver=$("$eza_bin" --version 2>/dev/null | head -n 2 | tr '\n' ' ' || echo "unknown")
      echo "Version: $eza_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in "$roaming_app_data/eza/theme.yml" "$HOME/.config/eza/theme.yml"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Avoid default --git scanning on large repositories or deep tree walks; bind --git only to detailed alias ('ll')"
    echo "  * Configuration: Set ergonomic aliases in pwsh & bash: ls='eza --icons', ll='eza -l --icons --git --header', lt='eza --tree --level=2'"
    echo "  * Security: Maintain --no-dereference by default to avoid unintended symlink traversal"
    echo "====================================="
    exit 0
    ;;
  lazygit)
    echo "Category: Git Terminal UI / lazygit"
    lg_bin=$(command -v lazygit 2>/dev/null || echo "")
    echo "Binary: ${lg_bin:-Not installed}"
    if [[ -n "$lg_bin" ]]; then
      lg_ver=$("$lg_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $lg_ver"
    fi

    echo "Discovered Configuration Files:"
    lg_cfg=""
    for f in "$roaming_app_data/lazygit/config.yml" "$local_app_data/lazygit/config.yml" "$HOME/.config/lazygit/config.yml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$lg_cfg" ]] && lg_cfg="$f"
      fi
    done

    if [[ -n "$lg_cfg" ]]; then
      echo "Key Configuration Parameters:"
      grep -E '^(  autoFetch|  edit|  animateExplosion|  showIcons|  pager):' "$lg_cfg" 2>/dev/null | while read -r line; do
        echo "  * $line"
      done || true

      echo "Lazygit + Neovim + Bat Companion Synergy:"
      nv_remote=$(grep -E 'nvim.*--server|editPreset.*nvim-remote|--remote-tab' "$lg_cfg" 2>/dev/null || true)
      if [[ -n "$nv_remote" ]]; then
        echo "  * Remote Tab Editing: [CONFIGURED] (Uses nvim --server / remote-tab to prevent nested editor spawns)"
      else
        echo "  * Remote Tab Editing: [MISSING] (Configure edit: 'nvim --server \$NVIM --remote-tab' to avoid nested editor freezes)"
      fi

      bat_pager=$(grep -E 'bat.*--style=changes|bat.*--color=always' "$lg_cfg" 2>/dev/null || true)
      if [[ -n "$bat_pager" ]]; then
        echo "  * Bat Diff Pager: [CONFIGURED] (bat --color=always --style=changes)"
      else
        echo "  * Bat Diff Pager: [DEFAULT/MISSING] (Configure git.paging.pager: 'bat --color=always --style=changes' for fast syntax diffs without extra dependencies)"
      fi
    fi

    inferred_thm=$(infer_theme)
    theme_desc="synchronize theme (ask user for preferred theme)"
    [[ -n "$inferred_thm" ]] && theme_desc="synchronize theme (inferred from system/terminal: $inferred_thm)"
    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set 'git.autoFetch: false' to prevent periodic background git spawns; configure pager: 'bat --color=always --style=changes' for lightweight syntax diffs"
    echo "  * Configuration: Configure lazygit to use nvim --server / remote tab editing to prevent nested editor spawns, $theme_desc"
    echo "  * Security: Respect git safe.directory settings; prevent untrusted custom commands"
    echo "====================================="
    exit 0
    ;;
  neovim|nvim)
    echo "Category: Modal Text Editor / Neovim"
    nv_bin=$(command -v nvim 2>/dev/null || command -v neovim 2>/dev/null || echo "")
    echo "Binary: ${nv_bin:-Not installed}"
    if [[ -n "$nv_bin" ]]; then
      nv_ver=$("$nv_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $nv_ver"
    fi

    echo "Discovered Configuration Files:"
    nv_init=""
    for f in "$local_app_data/nvim/init.lua" "$HOME/.config/nvim/init.lua" "$local_app_data/nvim/lazy-lock.json" "$HOME/.config/nvim/lazy-lock.json" "$local_app_data/nvim/lazyvim.json" "$HOME/.config/nvim/lazyvim.json"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$nv_init" && "$f" == *init.lua ]] && nv_init="$f"
      fi
    done

    if [[ -n "$nv_init" ]]; then
      nv_dir=$(dirname "$nv_init")
      echo "Neovim Performance & Hygiene Checks in $nv_dir:"
      if grep -q "vim.loader.enable" "$nv_init" 2>/dev/null; then
        echo "  * Bytecode Loader (vim.loader.enable): [ENABLED] (Fast startup cached)"
      else
        echo "  * Bytecode Loader: [NOT FOUND] (Add 'if vim.loader then vim.loader.enable() end' at top of init.lua)"
      fi

      if grep -rq "loaded_node_provider[[:space:]]*=[[:space:]]*0" "$nv_dir" 2>/dev/null; then
        echo "  * Legacy Remote Providers (node/python3/perl/ruby): [DISABLED] (Startup overhead eliminated)"
      else
        echo "  * Legacy Remote Providers: [ENABLED] (Set vim.g.loaded_{node,python3,perl,ruby}_provider = 0)"
      fi

      if grep -rq "nvim-treesitter\.configs" "$nv_dir/lua" 2>/dev/null; then
        echo "  * Treesitter Config Compatibility: [WARNING] ('nvim-treesitter.configs' found — removed in nvim-treesitter main branch / LazyVim v15+)"
      else
        echo "  * Treesitter Config Compatibility: [CLEAN] (Compatible with nvim-treesitter main branch)"
      fi

      if [[ -f "$nv_dir/.neoconf.json" ]] && grep -q '"neodev"' "$nv_dir/.neoconf.json" 2>/dev/null; then
        echo "  * Neoconf Schema (.neoconf.json): [DEPRECATED KEY] ('neodev' found; replace with 'lazydev')"
      fi

      bak_count=$(find "$nv_dir" -name "*.bak*" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
      if [[ "$bak_count" -gt 0 ]]; then
        echo "  * Leftover Backup Files in Config: [WARNING] ($bak_count *.bak* files found inside $nv_dir)"
      fi

      lsp_log="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lsp.log"
      [[ ! -f "$lsp_log" && -n "$local_app_data" ]] && lsp_log="$local_app_data/nvim-data/lsp.log"
      if [[ -f "$lsp_log" ]]; then
        lsp_log_kb=$(( $(wc -c < "$lsp_log" 2>/dev/null || echo 0) / 1024 ))
        echo "  * LSP Log Size ($lsp_log): ${lsp_log_kb} KB $(if [[ "$lsp_log_kb" -gt 1024 ]]; then echo "[LARGE — consider truncating]"; else echo "[HEALTHY]"; fi)"
      fi

      echo "Mise Companion & Toolchain Integration in Neovim:"
      mise_bin=$(command -v mise 2>/dev/null || echo "")
      if [[ -n "$mise_bin" ]]; then
        echo "  * Mise Binary Detected: $mise_bin"
        has_shims_in_path=false
        if echo "$PATH" | grep -qE "(\.local/share/mise/shims|mise/shims)" || grep -rq "mise/shims" "$nv_dir" 2>/dev/null; then
          has_shims_in_path=true
        fi
        echo "  * Mise Shims in PATH: $(if [[ "$has_shims_in_path" == "true" ]]; then echo "[ACTIVE] (LSPs and formatters discoverable via PATH)"; else echo "[CAUTION] (Prepend ~/.local/share/mise/shims to vim.env.PATH in options.lua)"; fi)"

        if grep -rq "mise_env_sync" "$nv_dir/lua" 2>/dev/null || grep -rq '"env".*"--json"' "$nv_dir/lua" 2>/dev/null; then
          echo "  * Dynamic Project Env Sync (DirChanged -> mise env --json): [ACTIVE]"
        else
          echo "  * Dynamic Project Env Sync (DirChanged -> mise env --json): [MISSING] (Add DirChanged autocmd in autocmds.lua to sync project [env] vars)"
        fi

        mise_cfg=""
        for mf in "$HOME/.config/mise/config.toml" "$local_app_data/mise/config.toml"; do
          [[ -f "$mf" ]] && mise_cfg="$mf" && break
        done
        if [[ -n "$mise_cfg" ]] && grep -qE '^[[:space:]]*rust[[:space:]]*=' "$mise_cfg" 2>/dev/null; then
          if grep -E '^[[:space:]]*rust[[:space:]]*=' "$mise_cfg" 2>/dev/null | grep -q "rust-analyzer"; then
            echo "  * Mise Rust Analyzer Component: [CONFIGURED] (rust components = 'rust-analyzer' prevents rustup shim recursion)"
          else
            echo "  * Mise Rust Analyzer Component: [WARNING] (Set rust = { version = '...', components = 'rust-analyzer' } in mise/config.toml to prevent rustup <-> mise/shims infinite recursion)"
          fi
        fi

        mason_file=$(find "$nv_dir" -name "*mason*.lua" 2>/dev/null | head -n 1 || echo "")
        if [[ -n "$mason_file" ]]; then
          mason_path_opt=$(grep -E '^[[:space:]]*PATH[[:space:]]*=' "$mason_file" 2>/dev/null | cut -d= -f2- | tr -d ' ",' || echo "default (prepend)")
          has_opts_extend_lock=$(grep -E 'opts_extend[[:space:]]*=[[:space:]]*\{\}' "$mason_file" 2>/dev/null || true)
          has_mason_false=$(grep -E 'mason[[:space:]]*=[[:space:]]*false' "$mason_file" 2>/dev/null || true)
          echo "  * Mason.nvim Config: $mason_file"
          echo "  * Mason PATH Precedence: $mason_path_opt $(if [[ "$mason_path_opt" =~ append|skip ]]; then echo "[OPTIMIZED] (Mise project tools take precedence)"; else echo "(Set PATH = 'append' to avoid shadowing project-pinned tools in mise)"; fi)"
          echo "  * Mason LazyVim Extra Lock (opts_extend = {} & mason = false): $(if [[ -n "$has_opts_extend_lock" && -n "$has_mason_false" ]]; then echo "[LOCKED] (LazyVim extras prevented from re-installing Mise tools)"; else echo "[UNLOCKED] (Set opts_extend = {} on mason.nvim and mason = false on Mise LSPs)"; fi)"
        else
          echo "  * Mason.nvim: Not explicitly configured (Mise shims serve as primary tool source)"
        fi

        mason_pkg_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/packages"
        [[ ! -d "$mason_pkg_dir" && -n "$local_app_data" ]] && mason_pkg_dir="$local_app_data/nvim-data/mason/packages"
        if [[ -d "$mason_pkg_dir" ]]; then
          mason_pkgs=$(ls -1 "$mason_pkg_dir" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
          mason_cnt=$(ls -1 "$mason_pkg_dir" 2>/dev/null | wc -l | tr -d ' ')
          echo "  * Installed Mason Packages ($mason_cnt): ${mason_pkgs:-none}"
        fi

        tg_cfg=""
        for tf in "$roaming_app_data/topgrade.toml" "$HOME/.config/topgrade.toml"; do
          [[ -f "$tf" ]] && tg_cfg="$tf" && break
        done
        if [[ -n "$tg_cfg" ]] && grep -qi "mason" "$tg_cfg"; then
          echo "  * Topgrade Mason Step: Detected in topgrade.toml (Coordinated via Topgrade commands)"
        fi
      else
        echo "  * Mise is not installed on this system (Install mise for polyglot runtime & LSP management)."
      fi
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Enable vim.loader.enable() for sub-65ms startup; disable legacy remote providers; discover LSPs via mise shims; rotate lsp.log >1MB"
    echo "  * Configuration: Migrate LSPs/formatters/linters from Mason to mise (aqua:/go:/npm:/github:); lock mason.nvim (PATH='append', opts_extend={}, mason=false) to editor-only adapters; add DirChanged 'mise env --json' sync; ensure LazyVim v15+ compatibility"
    echo "  * Security: Disable modelines (vim.opt.modeline = false, vim.opt.exrc = false); pin plugin commit hashes in lazy-lock.json; enforce 0600 on config files"
    echo "====================================="
    exit 0
    ;;
  git)
    echo "Category: Version Control / Git"
    git_bin=$(command -v git 2>/dev/null || echo "")
    echo "Binary: ${git_bin:-Not installed}"
    if [[ -n "$git_bin" ]]; then
      git_ver=$(git --version 2>/dev/null || echo "unknown")
      echo "Version: $git_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in "$HOME/.gitconfig" "$HOME/.config/git/config" "/c/ProgramData/Git/config" "/etc/gitconfig"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Active Performance & Windows Git Settings:"
    echo "  * core.fscache: $(git config --get core.fscache 2>/dev/null || echo 'unset')"
    echo "  * core.preloadIndex: $(git config --get core.preloadIndex 2>/dev/null || echo 'unset')"
    echo "  * core.untrackedCache: $(git config --get core.untrackedCache 2>/dev/null || echo 'unset')"
    echo "  * core.autocrlf: $(git config --get core.autocrlf 2>/dev/null || echo 'unset')"
    echo "  * credential.helper: $(git config --get credential.helper 2>/dev/null || echo 'unset')"
    echo "  * diff.algorithm: $(git config --get diff.algorithm 2>/dev/null || echo 'unset')"

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set core.fscache = true (huge NTFS status/diff speedup), core.preloadIndex = true, pack memory limits"
    echo "  * Configuration: Set core.autocrlf = input, diff.algorithm = histogram, push.autoSetupRemote = true, delta/bat pager"
    echo "  * Security: Configure safe.directory, use Git Credential Manager (credential.helper = manager) for secure OAuth tokens"
    echo "====================================="
    exit 0
    ;;
  bat)
    echo "Category: Syntax Pager / bat"
    bat_bin=$(command -v bat 2>/dev/null || echo "")
    echo "Binary: ${bat_bin:-Not installed}"
    if [[ -n "$bat_bin" ]]; then
      bat_ver=$("$bat_bin" --version 2>/dev/null || echo "unknown")
      echo "Version: $bat_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in "$roaming_app_data/bat/config" "$HOME/.config/bat/config"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    inferred_thm=$(infer_theme)
    theme_desc="configure theme matching terminal (or prompt user)"
    [[ -n "$inferred_thm" ]] && theme_desc="configure theme matching terminal (inferred: $inferred_thm)"
    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Use --paging=never when piping to pagers/tools, cache custom themes with bat cache --build"
    echo "  * Configuration: $theme_desc, set --style=\"numbers,changes,header\""
    echo "  * Security: Safe terminal escape rendering, avoid executing shell scripts from syntax highlighters"
    echo "====================================="
    exit 0
    ;;
  fzf)
    echo "Category: Fuzzy Finder / fzf"
    fzf_bin=$(command -v fzf 2>/dev/null || echo "")
    echo "Binary: ${fzf_bin:-Not installed}"
    if [[ -n "$fzf_bin" ]]; then
      fzf_ver=$("$fzf_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $fzf_ver"
    fi

    echo "Environment Variables & Synergy Checkpoints:"
    echo "  * FZF_DEFAULT_COMMAND: ${FZF_DEFAULT_COMMAND:-[UNSET]}"
    echo "  * FZF_DEFAULT_OPTS: ${FZF_DEFAULT_OPTS:-[UNSET]}"

    echo "Ripgrep + FZF + Bat Synergy Integration:"
    if [[ "${FZF_DEFAULT_COMMAND:-}" =~ (rg|ripgrep) ]]; then
      echo "  * Search Generator (ripgrep): [CONFIGURED] (rg wired as FZF_DEFAULT_COMMAND backend)"
    elif [[ "${FZF_DEFAULT_COMMAND:-}" =~ fd ]]; then
      echo "  * Search Generator (fd): [CONFIGURED] (fd directory walker)"
    else
      echo "  * Search Generator: [DEFAULT/MISSING] (Wire rg: export FZF_DEFAULT_COMMAND=\"rg --files --hidden --glob '!.git/*'\")"
    fi

    if [[ "${FZF_DEFAULT_OPTS:-}" =~ bat ]]; then
      echo "  * Syntax Previewer (bat): [CONFIGURED] (bat rendering line-numbered previews)"
    else
      echo "  * Syntax Previewer (bat): [RECOMMENDED] (Configure --preview 'bat --style=numbers --color=always --line-range :500 {}')"
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Wire rg (or fd) as backend search generator (FZF_DEFAULT_COMMAND); bound preview range (--line-range :500)"
    echo "  * Configuration: Set layout=reverse, border, preview window using bat with line-numbered syntax previews"
    echo "  * Security: Exclude credentials, .env files, and .git internals from default search index"
    echo "====================================="
    exit 0
    ;;
  starship)
    echo "Category: Shell Prompt / Starship Cross-Shell Prompt"
    ss_bin=$(command -v starship 2>/dev/null || echo "")
    echo "Binary: ${ss_bin:-Not installed}"
    if [[ -n "$ss_bin" ]]; then
      ss_ver=$("$ss_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $ss_ver"
    fi

    echo "Discovered Configuration Files:"
    ss_cfg=""
    for f in "$HOME/.config/starship.toml" "$roaming_app_data/starship.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$ss_cfg" ]] && ss_cfg="$f"
      fi
    done

    if [[ -n "$ss_cfg" ]]; then
      echo "Active Starship Configuration ($ss_cfg):"
      c_to=$(grep -E '^[[:space:]]*command_timeout' "$ss_cfg" 2>/dev/null | awk -F= '{print $2}' | xargs || echo "default (500ms)")
      echo "  * Configured Timeout: $c_to"

      echo "Mise Companion & Zero-Latency Prompt Integration:"
      has_mise_mod=$(grep -E '^[[:space:]]*\[mise\]' "$ss_cfg" 2>/dev/null || true)
      mise_mod_dis=$(grep -A 4 '^[[:space:]]*\[mise\]' "$ss_cfg" 2>/dev/null | grep -E '^[[:space:]]*disabled[[:space:]]*=' | cut -d= -f2- | tr -d ' "' || echo "default (false)")
      echo "  * Native [mise] Prompt Module: $(if [[ -n "$has_mise_mod" && "$mise_mod_dis" != "true" ]]; then echo "[ENABLED] (Unified polyglot tool status)"; else echo "[DISABLED / UNCONFIGURED] (Add [mise] module to starship.toml)"; fi)"

      lang_mods_status=()
      for l_mod in nodejs python rust golang ruby; do
        if grep -A 4 "^[[:space:]]*\[$l_mod\]" "$ss_cfg" 2>/dev/null | grep -q "disabled = true"; then
          lang_mods_status+=("$l_mod:disabled")
        elif grep -q "^[[:space:]]*\[$l_mod\]" "$ss_cfg" 2>/dev/null; then
          lang_mods_status+=("$l_mod:ACTIVE")
        fi
      done
      if [[ ${#lang_mods_status[@]} -gt 0 ]]; then
        echo "  * Language Modules Status: ${lang_mods_status[*]}"
      else
        echo "  * Language Modules Status: Using starship defaults (Per-language modules active by default)"
      fi

      bash_has_mise=$(grep -E '(eval "\$\(mise activate bash\)"|mise activate bash)' "$HOME/.bashrc" 2>/dev/null || true)
      bash_has_ss=$(grep -E '(eval "\$\(starship init bash\)"|starship init bash)' "$HOME/.bashrc" 2>/dev/null || true)
      echo "  * Shell Integration (.bashrc): $(if [[ -n "$bash_has_ss" ]]; then echo "starship init [YES]"; else echo "starship init [NO]"; fi), $(if [[ -n "$bash_has_mise" ]]; then echo "mise activate [YES]"; else echo "mise activate [NO]"; fi)"
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set command_timeout = 500ms; enable native [mise] module and disable redundant language modules ([nodejs], [python], [rust]) to eliminate 50-200ms subshell prompt lag; ensure mise env_cache = true"
    echo "  * Configuration: Clean minimal prompt layout, directory truncation length 3, consistent Nerd Font symbols"
    echo "  * Security: Avoid untrusted custom command execution in prompt modules ([custom.*]); restrict starship.toml permissions to 0600"
    echo "====================================="
    exit 0
    ;;
  yt-dlp)
    echo "Category: Media Downloader / yt-dlp"
    ytdl_bin=$(command -v yt-dlp 2>/dev/null || echo "")
    echo "Binary: ${ytdl_bin:-Not installed}"
    if [[ -n "$ytdl_bin" ]]; then
      ytdl_ver=$("$ytdl_bin" --version 2>/dev/null || echo "unknown")
      echo "Version: $ytdl_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in "$roaming_app_data/yt-dlp/config" "$HOME/.config/yt-dlp/config"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Set --concurrent-fragments=4, integrate ffmpeg multithreading, enable aria2c download engine when available"
    echo "  * Configuration: Default format bestvideo+bestaudio/best, clean output template, embed metadata/subtitles"
    echo "  * Security: Restrict untrusted cookies, sanitize output filenames to prevent directory traversal"
    echo "====================================="
    exit 0
    ;;
  herdr)
    echo "Category: Terminal Workspace & AI Agent Multiplexer / Herdr"
    hdr_bin=$(command -v herdr 2>/dev/null || echo "")
    echo "Binary: ${hdr_bin:-Not installed}"
    if [[ -n "$hdr_bin" ]]; then
      hdr_ver=$("$hdr_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $hdr_ver"
    fi

    echo "Server & Client Runtime Status:"
    if command -v herdr >/dev/null 2>&1; then
      herdr status 2>/dev/null | while read -r line; do
        echo "  $line"
      done || echo "  (Herdr status unavailable)"
    fi

    echo "Discovered Configuration Files:"
    hdr_cfg=""
    for f in "$roaming_app_data/herdr/config.toml" "$HOME/.config/herdr/config.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$hdr_cfg" ]] && hdr_cfg="$f"
      fi
    done

    if [[ -n "$hdr_cfg" ]]; then
      echo "Active Configuration Parameters:"
      def_shell=$(grep -E '^[[:space:]]*default_shell[[:space:]]*=' "$hdr_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "system default")
      theme_name=$(grep -E '^[[:space:]]*name[[:space:]]*=' "$hdr_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "default")
      toast_deliv=$(grep -E '^[[:space:]]*delivery[[:space:]]*=' "$hdr_cfg" 2>/dev/null | cut -d= -f2- | tr -d ' "' || echo "inline")
      echo "  * Default Shell: $def_shell"
      echo "  * Theme: $theme_name"
      echo "  * Notification Delivery: $toast_deliv"
    fi

    echo "Runtime State & Session Artifacts:"
    for sf in "$roaming_app_data/herdr/session.json" "$roaming_app_data/herdr/herdr.sock" "$roaming_app_data/herdr/herdr-server.log" "$HOME/.herdr/packages"; do
      if [[ -e "$sf" ]]; then
        sz=$(du -sh "$sf" 2>/dev/null | awk '{print $1}' || echo "present")
        echo "  - [EXISTS] $(basename "$sf"): $sz ($sf)"
      fi
    done

    inferred_thm=$(infer_theme)
    theme_desc="synchronize theme (or prompt user)"
    [[ -n "$inferred_thm" ]] && theme_desc="synchronize theme (inferred: $inferred_thm)"
    echo "Mise Companion Workspace Toolchains:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      echo "  * Mise Binary Detected: $mise_bin"
      mise_shims="$HOME/.local/share/mise/shims"
      if is_windows; then
        mise_shims="$local_app_data/mise/shims"
      fi
      if [[ -d "$mise_shims" ]]; then
        echo "  * Mise Shims for Agent Workspaces: [ACTIVE] ($mise_shims)"
      fi
    else
      echo "  * Mise not detected on this system."
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Monitor and rotate herdr-server.log; ensure default_shell starts cleanly; prune orphaned sessions"
    echo "  * Configuration: Set default_shell to pwsh (or bash); $theme_desc; configure system toast delivery; inherit mise shims in multiplexed agent panes"
    echo "  * Security: Restrict herdr.sock (0600) and workspace directories (0700); secure agent execution boundaries and API socket"
    echo "====================================="
    exit 0
    ;;
  gh|github-cli)
    echo "Category: Developer Tool / GitHub CLI (gh)"
    gh_bin=$(command -v gh 2>/dev/null || echo "")
    echo "Binary: ${gh_bin:-Not installed}"
    if [[ -n "$gh_bin" ]]; then
      gh_ver=$("$gh_bin" --version 2>/dev/null | head -n 1 || echo "unknown")
      echo "Version: $gh_ver"
    fi

    echo "Authentication & Account Status:"
    if command -v gh >/dev/null 2>&1; then
      gh auth status 2>&1 | while read -r line; do
        echo "  $line"
      done || echo "  (Authentication status check returned non-zero)"
    fi

    echo "Discovered Configuration Files:"
    gh_cfg=""
    gh_hosts=""
    for f in "$roaming_app_data/GitHub CLI/config.yml" "$HOME/.config/gh/config.yml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f"
        [[ -z "$gh_cfg" ]] && gh_cfg="$f"
      fi
    done
    for f in "$roaming_app_data/GitHub CLI/hosts.yml" "$HOME/.config/gh/hosts.yml"; do
      if [[ -f "$f" ]]; then
        perms=$(stat -c "%a" "$f" 2>/dev/null || stat -f "%Lp" "$f" 2>/dev/null || echo "unknown")
        echo "  - [EXISTS] $f (Permissions: $perms)"
        [[ -z "$gh_hosts" ]] && gh_hosts="$f"
      fi
    done

    echo "Active Configuration Parameters:"
    if command -v gh >/dev/null 2>&1; then
      for key in git_protocol editor pager prompt browser; do
        val=$(gh config get "$key" 2>/dev/null || echo "not set")
        echo "  * $key: $val"
      done
    elif [[ -n "$gh_cfg" ]]; then
      echo "  * Config File Found: $gh_cfg"
    fi

    echo "Installed GitHub CLI Extensions:"
    if command -v gh >/dev/null 2>&1; then
      ext_count=$(gh extension list 2>/dev/null | wc -l || true)
      if [[ "$ext_count" -gt 0 ]]; then
        echo "  * Total Extensions: $ext_count"
        gh extension list 2>/dev/null | while read -r eline; do
          echo "    - $eline"
        done
      else
        echo "  * No extensions installed."
      fi
    fi

    echo "Workstation & Cross-Tool Synergies:"
    if command -v git >/dev/null 2>&1; then
      gh_cred_helper=$(git config --get-regexp '^credential\..*helper' 2>/dev/null | grep -i "gh auth git-credential" || true)
      if [[ -n "$gh_cred_helper" ]]; then
        echo "  * Git Credential Helper: [CONFIGURED] (Transparent GitHub authentication for Git & LazyGit)"
      else
        echo "  * Git Credential Helper: [NOT CONFIGURED] (Run 'gh auth setup-git' to eliminate token/password prompts in git & lazygit)"
      fi
    fi
    gh_pager=$(gh config get pager 2>/dev/null || echo "")
    if [[ "$gh_pager" =~ bat ]]; then
      echo "  * Syntax Pager: [CONFIGURED] ($gh_pager)"
    else
      echo "  * Syntax Pager: Default less (Recommend 'gh config set pager \"bat --color=always --style=plain\"')"
    fi
    topgrade_cfg=""
    for tf in "$HOME/.config/topgrade.toml" "$roaming_app_data/topgrade.toml"; do
      [[ -f "$tf" ]] && topgrade_cfg="$tf" && break
    done
    if [[ -n "$topgrade_cfg" ]]; then
      echo "  * Topgrade Maintenance: Configured ($topgrade_cfg)"
    fi

    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Configure pager = 'bat --color=always --style=plain' for zero-latency syntax diff reviews; leverage gh --json queries in scripts"
    echo "  * Configuration: Set git_protocol = 'ssh'; run 'gh auth setup-git' for seamless git & lazygit credentials; configure PR workflow aliases (co, pv)"
    echo "  * Security: Restrict ~/.config/gh/hosts.yml permissions to 0600; enforce least-privilege token scopes; audit third-party extensions before installing"
    echo "====================================="
    exit 0
    ;;
  network|net)
    echo "Category: System Core / Network"
    if is_windows; then
      echo "Active Adapters:"
      run_ps 'Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object { "  * $($_.Name): $($_.InterfaceDescription), $($_.LinkSpeed)" }' 2>/dev/null || echo "  (unknown)"
      echo "DNS Servers (IPv4):"
      run_ps 'Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | ForEach-Object { "  * $($_.InterfaceAlias): $($_.ServerAddresses -join ",")" }' 2>/dev/null || echo "  (unknown)"
      echo "TCP Receive Window Auto-Tuning: $(run_ps '"$((Get-NetTCPSetting -SettingName Internet).AutoTuningLevelLocal)".ToLower()' 2>/dev/null || echo unknown)"
      echo "Listening TCP Sockets: $(netstat -ano -p tcp 2>/dev/null | grep -ci LISTENING || true)"
    else
      echo "Default Route: $(ip route show default 2>/dev/null | head -n 1 || true)"
      echo "DNS Resolvers: $(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ' || true)"
      echo "TCP Congestion Control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
      echo "Default Queue Discipline: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
      echo "Listening TCP Sockets: $(ss -tlnH 2>/dev/null | wc -l || true)"
    fi
    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: TCP auto-tuning left at normal; BBR or CUBIC congestion control; no leftover VPN adapters"
    echo "  * Configuration: Encrypted DNS (DoH/DoT) with a local cache; static addressing only where needed"
    echo "  * Security: Close listening sockets that nothing uses; firewall limited to the local network"
    echo "====================================="
    exit 0
    ;;
  chrome|google-chrome|google-chrome-stable)
    echo "Category: Web Browser / Google Chrome"
    if is_windows; then
      browser_report_win chrome.exe "$local_app_data/Google/Chrome/User Data" 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    else
      browser_report_linux "$(command -v google-chrome-stable || command -v google-chrome || command -v chromium || true)"
    fi
    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Hardware acceleration on; trim startup extensions"
    echo "  * Configuration: One profile per context; sync only what is needed"
    echo "  * Security: Safe Browsing on, auto-update on, audit extensions"
    echo "====================================="
    exit 0
    ;;
  edge|msedge|microsoft-edge)
    echo "Category: Web Browser / Microsoft Edge"
    if is_windows; then
      browser_report_win msedge.exe "$local_app_data/Microsoft/Edge/User Data" 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    else
      browser_report_linux "$(command -v microsoft-edge-stable || command -v microsoft-edge || true)"
    fi
    echo "Triad Checkpoints (Performance, Configuration, Security):"
    echo "  * Performance: Startup boost and background mode only if wanted; hardware acceleration on"
    echo "  * Configuration: One profile per context; sync only what is needed"
    echo "  * Security: SmartScreen on, auto-update on, audit extensions"
    echo "====================================="
    exit 0
    ;;
esac

# 2. Package / Tool Handling
binary_lookup="$target"
case "$target" in
  neovim) binary_lookup="nvim" ;;
  ripgrep) binary_lookup="rg" ;;
  windows-terminal) binary_lookup="wt" ;;
  kde|kde-plasma) binary_lookup="plasmashell" ;;
  baloo) binary_lookup="balooctl6" ;;
  pacman-contrib) binary_lookup="paccache" ;;
  brave|brave-bin) binary_lookup="brave" ;;
  google-chrome) binary_lookup="google-chrome-stable" ;;
esac

bin_path=$(command -v "$binary_lookup" 2>/dev/null || command -v "$target" 2>/dev/null || echo "")

if [[ -z "$bin_path" ]]; then
  echo "Status: NOT FOUND IN PATH"
  echo "Checking common installation locations..."
  if is_windows; then
    case "$target" in
      windows-terminal|wt)
        echo "Windows Terminal is packaged under: $local_app_data/Packages/Microsoft.WindowsTerminal_*"
        ;;
      brave)
        [[ -d "$local_app_data/BraveSoftware" ]] && echo "Found Brave User Data: $local_app_data/BraveSoftware"
        ;;
      chrome)
        [[ -d "$local_app_data/Google/Chrome" ]] && echo "Found Google Chrome: $local_app_data/Google/Chrome"
        ;;
      edge)
        [[ -d "$local_app_data/Microsoft/Edge" ]] && echo "Found Microsoft Edge: $local_app_data/Microsoft/Edge"
        ;;
      powertoys)
        [[ -d "$local_app_data/Microsoft/PowerToys" ]] && echo "Found PowerToys Data: $local_app_data/Microsoft/PowerToys"
        ;;
    esac
    if command -v winget >/dev/null 2>&1; then
      echo "Winget package search for '$target':"
      winget search "$target" 2>/dev/null | head -n 5 || true
    fi
  else
    if command -v pacman >/dev/null 2>&1; then
      pacman -Ss "^$target$" 2>/dev/null | head -n 4 || true
    elif command -v apt >/dev/null 2>&1; then
      apt-cache search "^$target$" 2>/dev/null | head -n 4 || true
    fi
  fi
  echo "====================================="
  exit 0
fi

case "$target" in
  python|python3)
    if ! python_ok "$bin_path"; then
      echo "Status: NOT INSTALLED (the python command is only the Microsoft Store shortcut)"
      echo "Binary Path: $bin_path"
      echo "====================================="
      exit 0
    fi
    ;;
esac

echo "Status: INSTALLED"
echo "Binary Path: $bin_path"

version="unknown"
for flag in "--version" "-V" "-v" "version"; do
  if ver_out=$("$bin_path" $flag 2>/dev/null | tr -d '\0' | head -n 1); then
    if [[ -n "$ver_out" ]]; then
      version="$ver_out"
      break
    fi
  fi
done
echo "Version: $version"

# Candidate Config Locations (Cross-Platform)
config_candidates=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/$target.toml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/$target.yaml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/$target.json"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config.toml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config.yaml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config.json"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target.toml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/init.lua"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/init.vim"
  "$HOME/.$target"
  "$HOME/.${target}rc"
  "$HOME/.${target}.toml"
  "$HOME/.${target}config"
  "$roaming_app_data/$target.toml"
  "$roaming_app_data/$target/config.toml"
  "$local_app_data/$target/init.lua"
  "$local_app_data/$target/$target.json"
)

# Tool-specific known paths
case "$target" in
  topgrade)
    config_candidates+=("$roaming_app_data/topgrade.toml" "$HOME/.config/topgrade.toml")
    ;;
  mpv|yt-dlp)
    config_candidates+=("$roaming_app_data/mpv/mpv.conf" "$HOME/.config/mpv/mpv.conf" "$roaming_app_data/yt-dlp/config" "$HOME/.config/yt-dlp/config")
    ;;
  neovim|nvim)
    config_candidates+=("$local_app_data/nvim/init.lua" "$local_app_data/nvim" "$HOME/.config/nvim/init.lua")
    ;;
  starship)
    config_candidates+=("$HOME/.config/starship.toml" "$roaming_app_data/starship.toml")
    ;;
  git)
    config_candidates+=("$HOME/.gitconfig" "$HOME/.config/git/config" "/etc/gitconfig" "/c/ProgramData/Git/config")
    ;;
  cargo|rust|rustc)
    config_candidates+=("$HOME/.cargo/config.toml")
    ;;
  mise|rtx)
    config_candidates+=("$HOME/.config/mise/config.toml" "$HOME/.config/mise/settings.toml" "$local_app_data/mise/config.toml" "$roaming_app_data/mise/config.toml")
    ;;
  bat)
    config_candidates+=("$roaming_app_data/bat/config" "$HOME/.config/bat/config")
    ;;
  lazygit)
    config_candidates+=("$roaming_app_data/lazygit/config.yml" "$HOME/.config/lazygit/config.yml")
    ;;
  herdr)
    config_candidates+=("$roaming_app_data/herdr/config.toml" "$HOME/.config/herdr/config.toml")
    ;;
  gh|github-cli)
    config_candidates+=("$roaming_app_data/GitHub CLI/config.yml" "$HOME/.config/gh/config.yml" "$HOME/.config/gh/hosts.yml")
    ;;
  brave|brave-bin)
    config_candidates+=("$local_app_data/BraveSoftware/Brave-Browser" "$HOME/.config/brave-flags.conf")
    ;;
  pacman|yay|paru|makepkg)
    config_candidates+=("/etc/pacman.conf" "/etc/makepkg.conf" "$HOME/.config/yay/config.json")
    ;;
esac

echo "Discovered Config Locations:"
found_configs=0
declare -A seen_paths
for cfg in "${config_candidates[@]}"; do
  [[ -n "${seen_paths[$cfg]:-}" ]] && continue
  seen_paths["$cfg"]=1
  if [[ -e "$cfg" ]]; then
    echo "  - [EXISTS] $cfg"
    found_configs=$((found_configs + 1))
  fi
done

if [[ $found_configs -eq 0 ]]; then
  echo "  - None of standard candidate paths exist yet."
fi

# Tool Security & Hardening Check
echo "Triad Checkpoints (Performance, Configuration, Security):"
case "$target" in
  topgrade)
    echo "  * Performance: Parallel tool steps where supported, align [mise] jobs with CPU threads (nproc), enable cleanup = true (runs mise prune)"
    echo "  * Configuration: Coordinated step list (winget, wsl, pacman, mise), [mise] bump = true, 'mise reshim' in post_commands"
    echo "  * Security: Restrict untrusted shell hooks, run mise steps without sudo (allow_root = false), verify package manager signatures"
    ;;
  mise|rtx)
    echo "  * Performance: Match jobs with CPU threads (nproc); env_cache = true with 1h TTL; cargo.binstall = true"
    echo "  * Configuration: Set pin = true; configure cache_prune_age = '7d'; integrate with topgrade ([mise] bump = true, cleanup = true, mise reshim)"
    echo "  * Security: Aqua SLSA/cosign verification; GitHub attestations; node.verify; restrict config permissions (0600)"
    ;;
  cargo|rust|rustc)
    echo "  * Performance: Match build.jobs = \$(nproc 2>/dev/null || echo 4); ensure protocol = 'sparse'; enable net.git-fetch-with-cli = true; prefer mise cargo.binstall"
    echo "  * Configuration: Disable 'cargo' in topgrade.toml (disable = ['cargo']) when managing CLIs via mise to eliminate from-source rebuilds"
    echo "  * Security: Cargo audit supply-chain scanning, enforce Cargo.lock checksums, restrict ~/.cargo/config.toml permissions (0600)"
    ;;
  yt-dlp)
    echo "  * Performance: Stream web video directly to mpv via yt-dlp, bypassing heavy browser CPU/RAM consumption"
    echo "  * Configuration: Bound ytdl-format to 1080p/best; integrate ffmpeg; concurrent fragment downloads (--concurrent-fragments=4)"
    echo "  * Security: Sanitize output filenames; avoid executing untrusted remote postprocessors"
    ;;
  git)
    echo "  * Security: safe.directory configuration, Windows credential manager integration"
    echo "  * Performance: core.fscache = true, core.preloadIndex = true, core.untrackedCache = true, pack memory bounds"
    echo "  * Configuration: diff pager (bat/delta), diff algorithm (histogram), push.autoSetupRemote"
    ;;
  neovim|nvim)
    echo "  * Performance: Byte-compiled lua loader (vim.loader.enable()), deferred plugin loading"
    echo "  * Configuration: Ergonomic keymaps, LSP integration via mise, clipboard provider"
    echo "  * Security: Modelines disabled (nomodeline), secure workspace trust plugins"
    ;;
  starship)
    echo "  * Performance: Command timeout = 500ms, enable native [mise] module, disable slow per-language modules ([nodejs], [python], [rust])"
    echo "  * Configuration: Clean minimal preset, Git branch status symbols, shell prompt caching in bash/pwsh"
    echo "  * Security: Avoid executing external network queries in custom prompt modules, enforce 0600 on starship.toml"
    ;;
  gh|github-cli)
    echo "  * Performance: Use fast bat pager for PR diff reviews; lean API queries via --json; batch extension updates in topgrade"
    echo "  * Configuration: Set git_protocol = 'ssh'; run 'gh auth setup-git'; configure aliases for PR workflows (co, pv)"
    echo "  * Security: Enforce 0600 on hosts.yml; least-privilege token scopes; audit installed extensions"
    ;;
  *)
    echo "  * Security: Least privilege, minimal network exposure, file permissions"
    echo "  * Performance: Concurrency aligned with CPU threads (nproc) and host RAM tier"
    echo "  * Configuration: Ergonomic defaults, integration with system environment"
    ;;
esac

echo "====================================="
