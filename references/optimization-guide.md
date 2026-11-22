# System, Security & Tool Optimization Guide (Windows & Linux)

This reference guide provides engineering heuristics, hardening standards, upstream research strategies, and persistent memory specifications for the **`system-optimizer`** skill across both Windows and Linux hosts.

---

## 1. System & Hardware Tuning Heuristics

### CPU & Concurrency
- **Logical Threads (`nproc` / Logical Processors)**:
  - *Package Compilation & Runtimes (`makepkg`, `mise`, `topgrade`)*: Set `MAKEFLAGS="-j$(nproc)"`, `mise` `jobs = <nproc>`, and `topgrade` `[mise] jobs = <nproc>`. Omit redundant `cargo` `build.jobs` (Cargo already defaults to logical CPU threads).
  - *Package Downloads (`winget`, `pacman`, `yay`)*: Concurrency aligned with network bandwidth and disk I/O; `winget` direct WinINet downloader (`ParallelDownloads = 5` is already Arch's default in `/etc/pacman.conf`).
  - *Search & Indexing (`ripgrep`, `fd`, `fzf`)*: Rely on built-in auto-detection (`rg` defaults to `--threads=0` with single-file/directory heuristics; `fd` defaults to logical cores; `fzf` `--walker` is multithreaded). Do NOT hardcode `--threads` or `-j`.
  - *Compression (`zstd`)*: Multithreaded compression (`zstd -T0 -3`; note `makepkg` already defaults to `COMPRESSZST=(zstd -c -T0 -)`).
- **Power Plans & Scaling**:
  - *Windows*: High Performance or Ultimate Performance power plan (`powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`), ensuring 100% min/max processor states on AC and preventing core parking from introducing wake latency on desktop workstations.
  - *Linux*: CPU governors: `schedutil` (balanced), `performance` (max throughput); Energy Performance Preference (EPP): `balance_performance` on AC.

### Memory Tier Management
- **Low RAM (<= 4GB)**:
  - Keep application worker pools bounded strictly to logical thread count.
  - Enforce strict per-process memory limits (e.g. Git `pack.windowMemory = 256m`, `pack.packSizeLimit = 512m`).
  - *Windows*: Enable Memory Compression (`Enable-MMAgent -mc` — *elevated PowerShell; provide command for user to run per Safety Contract #4*) to compress idle pages in RAM instead of incurring disk paging latency.
  - *Linux*: Enable `zram-generator` with `zstd` algorithm and `vm.swappiness = 150-180`.
  - Bound WSL2 VM memory strictly to 1.5GB-2GB in `~/.wslconfig`.
- **Medium RAM (4GB - 16GB)**:
  - Balanced concurrency (`threads * 2` for I/O tasks).
  - Standard in-memory buffers and caching.
  - Bound WSL2 VM memory to 6GB-8GB with `autoMemoryReclaim = dropcache` under `[experimental]`.
- **High RAM (> 16GB)**:
  - Generous tool buffers and in-memory caches (`sqlite3` `cache_size = -16000`).
  - Bound WSL2 VM memory to 8GB-12GB, reserving ample headroom for Windows host GPU/gaming/compilation.

### Storage & Filesystem
- **Windows (NTFS / NVMe / SSD)**:
  - *TRIM Verification*: Ensure `fsutil behavior query DisableDeleteNotify` returns `0` (TRIM operations enabled for SSDs).
  - *Periodic Optimization*: Run weekly volume re-trim via elevated PowerShell (`Optimize-Volume -DriveLetter C -ReTrim -Verbose` — *user-run admin command*).
  - *NTFS 8.3 Short Names*: Disable 8.3 name generation on secondary data volumes (`fsutil 8dot3name set D: 1` — *user-run admin command*) to eliminate directory enumeration overhead on large repositories (e.g. `node_modules`).
  - *WSL Disk Compaction*: **Do NOT set `sparseVhd=true`** — Microsoft documents `ext4.vhdx` data-corruption risk with sparse VHDs. Compact offline when needed via `wsl --shutdown` + `wsl --manage <distro> --resize` or `Optimize-VHD`.
- **Linux (Ext4 / Btrfs / NVMe / SSD)**:
  - *Mount Flags*: Ensure `noatime` is enabled to eliminate write overhead on file reads.
  - *Discard*: Enable periodic TRIM timer (`systemctl enable --now fstrim.timer`).
  - *Schedulers*: `none` or `kyber` for NVMe; `bfq` for HDDs.

### GPU & Hardware Video Acceleration
- **Windows (DirectX / Direct3D 11/12 & NVIDIA NVDEC/NVENC)**:
  - Video Players (`mpv`): Use `vo=gpu-next` (default in 0.41+), `gpu-api=d3d11`, `profile=high-quality`, zero-copy `hwdec=auto-safe`, `tone-mapping=auto`, and `target-colorspace-hint=auto` (or `yes` when HDR display mode is active). Avoid `nvdec-copy` unless CPU-side video filters require copyback.
  - Terminal Emulators (`windows-terminal`): Windows Terminal 1.18+ enables the Atlas GPU rendering engine by default; set `"disableAnimations": true` to remove tab/pane transition lag.
  - Hardware-Accelerated GPU Scheduling (HAGS): Ensure HAGS is enabled in Windows Graphics Settings to reduce frame latency.
- **Linux (VA-API & Vulkan)**:
  - Intel: `intel-media-driver` or `i965` driver.
  - AMD: `radeonsi` Mesa driver.
  - Video Players (`mpv`): `vo=gpu-next`, `gpu-api=vulkan`, `profile=high-quality`, zero-copy `hwdec=auto-safe` (`vaapi,vulkan,auto` / `nvdec,vulkan,auto`) on modern GPUs; reserve `vo=gpu` + `gpu-api=opengl` + `hwdec=vaapi` with `hwdec-codecs` matching `vainfo` (e.g. `h264,mpeg2video,vc1`) strictly for legacy Intel Gen7/Haswell iGPUs.

---

## 1.1 Hardware-Driven Decision Engine & Dynamic Theme Policy

The `system-optimizer` skill dynamically derives configuration parameters directly from probed host hardware metrics. No values or themes are hardcoded.

### Hardware Decision Rules

| Hardware Metric | Probed Range / Category | Decision & Configured Parameters |
| :--- | :--- | :--- |
| **CPU Logical Threads (`nproc`)** | Any (e.g. 4, 8, 12, 16, 32) | • `mise` / `topgrade`: `jobs = <nproc>`<br>• `makepkg`: `MAKEFLAGS="-j<nproc>"`<br>• `zstd`: `-T<nproc> -3`<br>• `WSL`: `processors = max(2, floor(nproc / 2))` or matching physical cores<br>• Omit redundant `cargo` `build.jobs`, `rg --threads`, and `fd -j` (auto-detected) |
| **RAM Tier** | **Low (<= 4 GB)** | • Enforce memory limits: Git `pack.windowMemory = 256m`<br>• WSL: `memory = 1.5GB`<br>• Enforce Windows Memory Compression (`Enable-MMAgent -mc`) or Linux zram (`vm.swappiness=160`)<br>• Browser: Aggressive background tab discarding enabled<br>• PowerToys: Disable all non-essential background modules |
| | **Medium (4 GB - 16 GB)** | • Standard caching buffers: Git `pack.windowMemory = 512m`<br>• WSL: `memory = floor(RAM / 2)` (e.g. 8GB on 16GB host) with `[experimental] autoMemoryReclaim = dropcache`<br>• Standard in-memory caching |
| | **High (> 16 GB)** | • Generous tool buffers (`sqlite3` `cache_size = -16000`)<br>• WSL: `memory = floor(RAM * 0.6)` (leaving ample RAM for host apps & games)<br>• Pi Agent: `compaction.reserveTokens` defaults to `16384`; tune `compaction.modelOverrides` / `keepRecentTokens` per provider |
| **GPU Architecture** | **NVIDIA Discrete GPU (RTX / GTX)** | • `mpv`: `vo=gpu-next`, `gpu-api=d3d11` (Windows) or `vulkan` (Linux), `profile=high-quality`, zero-copy `hwdec=auto-safe` (or `nvdec,vulkan,auto`; avoid `nvdec-copy` unless CPU filters are active)<br>• `rustdesk`: NVENC hardware video encode (H.264/AV1)<br>• Terminal: Atlas GPU rasterization (default in Windows Terminal 1.18+)<br>• Windows: Hardware-Accelerated GPU Scheduling (HAGS) enabled |
| | **AMD Radeon** | • `mpv`: `vo=gpu-next`, `hwdec=auto-safe` (`d3d11va,vulkan,auto` on Windows; `vaapi,vulkan,auto` with `radeonsi` on Linux)<br>• `rustdesk`: AMF hardware video encode |
| | **Intel Arc / Iris Xe** | • `mpv`: `vo=gpu-next`, `hwdec=auto-safe` (`d3d11va,vulkan,auto` on Windows; `vaapi,vulkan,auto` with `intel-media-driver` on Linux)<br>• `rustdesk`: QSV hardware video encode |
| | **Legacy / Low-Power iGPU** | • `mpv`: `vo=gpu`, `gpu-api=opengl` (for Gen7/Haswell), `profile=fast`, `hwdec=vaapi` + `hwdec-codecs=h264,mpeg2video,vc1` (per `vainfo`, avoiding CUDA/VDPAU/VP9 probes), `tone-mapping=auto`, `script-opts-append=ytdl_hook-all_formats=no` when pinning `ytdl-format`, disabled heavy debanding<br>• Terminal: Disable translucent acrylic / blur effects to eliminate redraw lag |
| **Storage Media** | **NVMe / SATA SSD** | • Enforce TRIM: `fsutil DisableDeleteNotify = 0` / `fstrim.timer`<br>• Secondary Windows drives: Disable 8.3 short names (`fsutil 8dot3name set <drive> 1`)<br>• WSL: Avoid `sparseVhd=true` (ext4 corruption risk)<br>• Git: Enable `core.untrackedCache = true` (`feature.manyFiles = true`), plus `core.fscache = true` on **Windows only** |
| | **Rotational HDD** | • Bound concurrent directory walking if I/O saturates; avoid aggressive parallel indexing |
| **Display Capabilities** | **HDR Display Mode Active** | • `mpv`: Set `target-colorspace-hint=yes` for native HDR passthrough to Windows DWM / Wayland |
| | **SDR Display** | • `mpv`: Keep `vo=gpu-next` defaults `tone-mapping=auto`, `hdr-compute-peak=auto`, `target-colorspace-hint=auto` (paired with `profile=high-quality`) |
| | **High Refresh Display (>= 120Hz)** | • `mpv`: Enable `video-sync=display-resample` and `interpolation=yes` to eliminate panning judder |

### Dynamic Theme Inference Policy (Zero Hardcoding)

The skill NEVER hardcodes theme palettes (such as Tokyo Night or Catppuccin). Instead:
1. **Inspection Order**:
   - First, inspect the host terminal configuration (e.g. Windows Terminal `defaultProfile` `colorScheme`).
   - Second, inspect Herdr (`theme.name` in `config.toml`).
   - Third, inspect Neovim (`colorscheme` in `init.lua` or `lazyvim.json`).
   - Fourth, inspect environment variables (e.g. `BAT_THEME`).
2. **If a consistent theme is found across tools**: Propagate that inferred theme to unconfigured tools (`lazygit`, `bat`, `herdr`, `windows-terminal`).
3. **If no theme is detected or if tools have conflicting themes**: Ask the user for their preferred theme palette before making any changes.

---

## 2. System Security Hardening Standards

### Windows Security Hardening
- **Windows Defender Antivirus & Exploit Guard**:
  - Verify Real-Time Protection and Antivirus engine are active (`Get-MpComputerStatus`).
  - *PUA Protection*: Enable Potentially Unwanted Application blocking via `Set-MpPreference -PUAProtection 1` *(elevated PowerShell; provide command for user to run per Safety Contract #4 — blocks adware, coinminers, browser hijackers)*.
  - *Developer Exclusions*: To prevent Windows Defender from locking up CPU threads during intensive compilation, add process or folder exclusions for local workspace build artifacts (`node_modules`, `target`, `.git`), while keeping system-wide file scanning active.
- **Windows Defender Firewall**:
  - Verify all three profiles (`Domain`, `Private`, `Public`) are enabled (`Get-NetFirewallProfile`).
  - Default policy: Inbound connections blocked/denied, outbound allowed.
  - Audit open listening ports with `netstat -ano -p tcp` or `Get-NetTCPConnection -State Listen`.
- **PowerShell Execution & Script Security**:
  - Enforce `ExecutionPolicy RemoteSigned` for `CurrentUser` (`Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`) to block unsigned remote scripts from running while allowing local scripts.
  - Ensure sensitive tokens, credentials, and passwords are not stored in PSReadLine history (`$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt`).
- **User Account Control (UAC)**:
  - Enforce `EnableLUA = 1` in `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`.
  - Admin consent behavior set to secure desktop prompting.
- **OpenSSH on Windows**:
  - If Windows OpenSSH Server (`sshd`) is installed, restrict it to on-demand or disable if unused.
  - Protect `$HOME/.ssh` permissions and private keys (`id_ed25519`).

### Linux Security Hardening
- **Kernel Sysctl Hardening (`/etc/sysctl.d/99-system-hardening.conf`)**:
  - `kernel.kptr_restrict = 2`: Hides kernel pointers.
  - `kernel.dmesg_restrict = 1`: Restricts dmesg access.
  - `kernel.unprivileged_bpf_disabled = 1`: Restricts unprivileged eBPF.
  - `kernel.yama.ptrace_scope = 1`: Limits ptrace to parent processes.
  - `fs.protected_hardlinks = 1`, `fs.protected_symlinks = 1`, `fs.protected_fifos = 2`, `fs.protected_regular = 2`.
  - `net.ipv4.conf.all.rp_filter = 1`, `net.ipv4.conf.all.accept_redirects = 0`.
- **Firewall & Services**:
  - Active `ufw` or `nftables` with default-deny inbound.
  - Service sandboxing audit via `systemd-analyze security`.

### Elevated Suggestions Apply Script Templates (Linux & Windows)

When a run produces privileged recommendations (Safety Contract #4), Phase 6 suggests creating a user-owned, reviewable script under `~/.config/system-optimizer/elevated/` (`chmod 0700` on Linux). Never run `sudo` or Administrator PowerShell yourself — write the script on user confirmation and give the user the exact inspect, dry-run, and execute commands.

#### Linux Elevated Script Template (`~/.config/system-optimizer/elevated/apply-elevated-<YYYYMMDD-HHMMSS>.sh`)
```bash
#!/usr/bin/env bash
# Generated by system-optimizer for host: <hostname> (<YYYY-MM-DD HH:MM:SS>)
# Targets: <comma-separated targets>
# Preview: bash "$0" --dry-run
# Apply:   sudo bash "$0"
set -euo pipefail
umask 077

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--dry-run]" >&2
  exit 2
fi

if [[ "$DRY_RUN" -eq 0 && "$EUID" -ne 0 ]]; then
  echo "Error: root privileges required. Preview with 'bash $0 --dry-run' or apply with 'sudo bash $0'." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
# Store backups under /var/backups (never write root-owned files into $HOME, and never drop .bak files in /etc/*.d/).
BACKUP_DIR="/var/backups/system-optimizer/$STAMP"

run_cmd() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [DRY-RUN] %s\n' "$*"
  else
    "$@"
  fi
}

backup_sys_file() {
  local src="$1"
  [[ -f "$src" ]] || return 0
  local rel="${src#/}"
  local dst="$BACKUP_DIR/$rel"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  [DRY-RUN] backup %s -> %s\n' "$src" "$dst"
    return 0
  fi
  install -d -m 0700 "$(dirname "$dst")"
  cp -a -- "$src" "$dst"
  sha256sum -- "$dst" >> "$BACKUP_DIR/MANIFEST.sha256"
}

if [[ "$DRY_RUN" -eq 0 ]]; then
  install -d -m 0700 "$BACKUP_DIR"
fi

echo "[1/2] Applying kernel sysctl hardening (/etc/sysctl.d/99-system-hardening.conf)..."
backup_sys_file /etc/sysctl.d/99-system-hardening.conf
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "  [DRY-RUN] write /etc/sysctl.d/99-system-hardening.conf and run sysctl --system"
else
  install -d -m 0755 /etc/sysctl.d
  cat <<'EOF' > /etc/sysctl.d/99-system-hardening.conf
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF
  chmod 0644 /etc/sysctl.d/99-system-hardening.conf
  sysctl --system >/dev/null
fi

echo "[2/2] Enabling periodic SSD TRIM timer (fstrim.timer)..."
run_cmd systemctl enable --now fstrim.timer

echo "Done. Backups & SHA-256 manifest: $BACKUP_DIR (restore any file with: sudo cp -a \"$BACKUP_DIR/<path>\" \"/<path>\")"
```

#### Windows Elevated Script Template (`~/.config/system-optimizer/elevated/apply-elevated-<YYYYMMDD-HHMMSS>.ps1`)
```powershell
# Generated by system-optimizer for host: <hostname> (<YYYY-MM-DD HH:MM:SS>)
# Targets: <comma-separated targets>
# Preview: pwsh -NoProfile -File .\apply-elevated-<stamp>.ps1 -DryRun
# Apply (from an Administrator PowerShell prompt): pwsh -NoProfile -File .\apply-elevated-<stamp>.ps1
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $DryRun -and -not $isAdmin) {
  Write-Error "Administrator privileges required. Preview with '-DryRun' or run from an elevated PowerShell prompt."
  exit 1
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDir = Join-Path $env:ProgramData "system-optimizer\backups\$Stamp"
if (-not $DryRun) {
  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
}

Write-Host "[1/3] Ensuring Windows Memory Compression is enabled..."
$mm = Get-MMAgent
if (-not $mm.MemoryCompression) {
  if ($DryRun) { Write-Host "  [DRY-RUN] Enable-MMAgent -MemoryCompression" }
  else { Enable-MMAgent -MemoryCompression }
} else {
  Write-Host "  Already enabled."
}

Write-Host "[2/3] Ensuring Microsoft Defender PUA Protection is enabled..."
$mp = Get-MpPreference
if ($mp.PUAProtection -ne 1) {
  if ($DryRun) {
    Write-Host "  [DRY-RUN] Set-MpPreference -PUAProtection Enabled (previous: $($mp.PUAProtection))"
  } else {
    "PUAProtection=$($mp.PUAProtection)" | Set-Content -LiteralPath (Join-Path $BackupDir 'defender-prev.txt') -Encoding UTF8
    Set-MpPreference -PUAProtection Enabled
  }
} else {
  Write-Host "  Already enabled."
}

Write-Host "[3/3] Verifying NTFS TRIM (DisableDeleteNotify = 0)..."
if ($DryRun) { Write-Host "  [DRY-RUN] fsutil behavior set DisableDeleteNotify 0" }
else { fsutil behavior set DisableDeleteNotify 0 | Out-Null }

Write-Host "Done. State backups stored in: $BackupDir"
```

---

### 2.5 Dynamic Tool-Drift & Live Schema Verification Workflow

Because CLI flags, default values, and TOML/YAML/JSON keys evolve rapidly across releases, `system-optimizer` never relies solely on memorized static flags:

1. **Pre-Proposal Drift Check (`./scripts/tool-drift-check.sh`)**:
   - Run `./scripts/tool-drift-check.sh [--json] [target ...]` in Phase 2.5.
   - Compares installed binary versions against the skill's verified baseline manifest and executes fast (<2s, offline) live CLI/schema introspection (`mise settings ls`, `herdr --default-config` & `herdr config check`, `starship print-config --default`, `pi` `settings.schema.json`, `mpv --vo=help`, and `--help` across `rg`/`fd`/`eza`/`fzf`/`bat`/`yt-dlp`/`syncthing`/`uv`/`gh`).
   - Scans active user configs for deprecated or renamed keys and emits `[VERIFIED]`, `[VERSION AHEAD]`, `[SCHEMA DRIFT]`, or `[DEPRECATED CONFIG]`.
   - Whenever `[VERSION AHEAD]` or `[SCHEMA DRIFT]` appears — or before emitting any unfamiliar flag/key — verify the exact syntax directly against the installed binary (`<tool> --help`, `mise settings ls`, `starship print-config --default`, `herdr --default-config`, `lazygit --config`, `mpv --list-options`, `settings.schema.json`). Surface every `[DEPRECATED CONFIG]` finding in the Phase 4 Triad proposal table.
2. **Post-Apply Native Validation Gate (Phase 5)**:
   - Immediately after writing user-approved config changes, run the tool's native validator (`herdr config check` before `herdr server reload-config`, `mise doctor` / `mise settings`, `nvim --headless +q`, `bat --diagnostic`, `git config --list >/dev/null`, `sshd -t` in elevated scripts).
   - If any validator reports an unknown/deprecated key or parse error, fix it against the live schema or roll back immediately with `scripts/backup-config.sh --restore <backup-file>`.

---
---

## 3. Windows Subsystem for Linux (WSL 2) Tuning

WSL 2 on Windows 11 provides a high-performance lightweight virtualized Linux kernel. Tuning both the Windows host config (`~/.wslconfig`) and the in-distro config (`/etc/wsl.conf`) is essential for balance and speed.

### Global Windows Host Config (`~/.wslconfig`)
```ini
# Settings apply across all Linux distros running on WSL 2
[wsl2]
# Bound WSL VM memory to prevent exhausting Windows host memory
memory=8GB

# Bound processors to match host physical cores
processors=6

# Set swap space on host NVMe drive
swap=4GB

# Localhost communication parity
localhostForwarding=true
nestedVirtualization=false
guiApplications=false

# Advanced & Experimental Features (Windows 11 23H2+)
[experimental]
# Automatically reclaim cached memory from Linux back to Windows
autoMemoryReclaim=dropcache

# WARNING: Do NOT enable sparseVhd=true — Microsoft documents ext4.vhdx corruption risk.
# Compact manually offline when needed via: wsl --shutdown && wsl --manage <distro> --resize

# Tunnel DNS queries through Windows networking (default true in modern WSL under [wsl2])
dnsTunneling=true

# Low-latency mirrored networking mode
networkingMode=mirrored

# Apply Windows Defender Firewall rules to WSL network traffic
firewall=true

# Synchronize Windows proxy settings into WSL
autoProxy=true
```

### In-Distro Configuration (`/etc/wsl.conf`)
```ini
[boot]
systemd=true

[automount]
enabled=true
options="metadata,umask=22,fmask=11"
mountFsTab=true

[network]
generateResolvConf=true

[interop]
enabled=true
appendWindowsPath=true
```

---

## 4. Windows Package Managers & Terminals

### Windows Package Manager (`winget`)
- **Configuration File**: `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\settings.json`
- **Tuned Configuration**:
```json
{
  "$schema": "https://aka.ms/winget-settings.schema.json",
  "source": {
    // Limits source catalog sync checks to once every 2 hours (eliminates 5-10s startup lag)
    "autoUpdateIntervalInMinutes": 120
  },
  "telemetry": {
    // Disables background telemetry calls to Microsoft during package operations
    "disable": true
  },
  "network": {
    // Direct WinINet engine bypasses Delivery Optimization throttling
    "downloader": "default"
  },
  "visual": {
    "progressBar": "rainbow"
  }
}
```
- **Security Posture**: Verify that `InstallerHashOverride` and `BypassCertificatePinningForMicrosoftStore` remain `Disabled` in `winget --info`.

### Windows Terminal (`windows-terminal` / `wt`)
- **Configuration File**: `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
- **Performance**:
  - Atlas GPU text rendering engine (enabled by default in Windows Terminal 1.18+).
  - `"disableAnimations": true`: Eliminates transition latency when switching tabs or splitting panes.
  - `"copyFormatting": "none"`: Copies clean raw text without bloated HTML/RTF styling.
  - `"copyOnSelect": false`: Prevents accidental clipboard overwrites.
- **Configuration & Ergonomics**:
  - Set default profile to PowerShell 7 (`pwsh`) or WSL.
  - Clean font rendering with Nerd Fonts (`Hack Nerd Font`, `JetBrainsMono NF`).
  - High-contrast theme aligned with user preference or dynamically inferred from existing terminal profiles.
- **Security**:
  - Ensure shell profiles execute with standard user privileges by default (`"elevate": false`).

### PowerShell 7 (`pwsh`)
- **Profile Path**: `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`
- **Performance Optimization**:
  - Profile loading speed: Benchmark via `pwsh -NoProfile -Command "Measure-Command { . \$PROFILE }"` (target < 150ms).
  - Defer heavy module imports (`Import-Module`) until command invocation.
  - Pre-generate or statically cache `starship init pwsh --print-full-init` and `zoxide init` prompts to eliminate subshell forks.
- **Configuration & Ergonomics (PSReadLine)**:
  - `Set-PSReadLineOption -PredictionSource HistoryAndPlugin`: Enables fast inline predictive IntelliSense based on past command history.
  - `Set-PSReadLineOption -PredictionViewStyle ListView`: Displays multi-line interactive completion suggestions.
  - `Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete`: Clean bash-like tab completion menu.
- **Security Hardening**:
  - Enforce `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`.
  - Sensitive history scrubbing: Ensure passwords and API tokens are not saved to PSReadLine history.

### Microsoft PowerToys (`powertoys`)
- **Configuration Path**: `%LOCALAPPDATA%\Microsoft\PowerToys\settings.json`
- **Performance Optimization**:
  - Disable unused background daemon modules (e.g. Awake, Mouse utilities, Video Conference Mute, Color Picker) to reclaim background RAM and thread handles.
- **Configuration**:
  - PowerToys Run: Configure fast app & file launcher hotkey (`Alt+Space`) with bounded search indexing.
  - FancyZones: Custom window tiling zones optimized for high-resolution displays.

---

## 5. Cross-Platform Developer & Media Tools

### Package Orchestrator (`topgrade`)
- **Configuration**: `%APPDATA%\topgrade.toml` (Windows) or `~/.config/topgrade.toml` (Linux). Supports drop-in snippet overrides in `~/.config/topgrade.d/*.toml`.
- **Triad Tuning**:
  - *Performance*:
    - Parallel execution: Set `[mise] jobs = $(nproc)` and `[git] max_concurrency = 5` to align with CPU/network budget (Topgrade has no global step concurrency setting).
    - Disable missing or uninstalled package hooks (`disable = [...]`) to eliminate probing latency across inactive steps.
    - Enable `cleanup = true`: Orchestrates post-upgrade disk reclamation, automatically cleaning package manager caches and triggering `mise prune` to delete obsolete runtimes and tools.
  - *Configuration*:
    - Coordinate holistic update pipeline across OS package managers (`pacman`, `yay`, `winget`), subsystems (`wsl`), developer tools (`git`, `cargo`, `github_cli_extensions`), and polyglot runtimes (`mise`).
    - Dedicated `[mise]` table: Enable `bump = true` (plus `interactive = false`, `quiet = false`) to allow Topgrade to upgrade installed tools (`mise upgrade`).
    - Post-Upgrade Synchronization: Add `"Mise Reshim" = "mise reshim"` to `[post_commands]` ensuring binary shims, dynamic environment paths, and editor language servers are synchronized immediately after runtime updates.
    - Prevent Duplicate Updater Conflicts: Add redundant tool self-updaters (e.g. `"uv"`, `"cargo"`, `"pi"`, `"bun_packages"`, `"npm"`) to `disable = [...]` if their binaries/runtimes are already managed by `mise`, eliminating dual-update race conditions. Do NOT add manual `gh extension upgrade --all` in `[git]` or `[commands]` — Topgrade 17+ includes a native `github_cli_extensions` step.
    - Windows & Linux specifics: Verify `[windows]` defaults `accept_all_updates = true` and `winget_use_sudo = false` (these live under `[windows]`, NOT `[misc]`). On Linux, `[misc]` `pre_sudo = true`, `[git] fallback_to_fetch_default = true`, `[misc] notify_end = "on_failure"`, and `[cargo]` `git = false`, `quiet = true`, `locked = true` keep runs clean.
  - *Security*:
    - Restrict untrusted shell hooks in `pre_commands` and `post_commands`; execute only verified binaries with explicit arguments.
    - Set `ask_retry = false` to prevent unattended batch execution hangs on network drops or DNS failures.
    - Enforce privilege boundaries: Keep `[misc] allow_root = false` so Topgrade elevates via `sudo` only for OS package managers while running `mise` unprivileged. **Security caveat on `sudo_loop = true` (`--sudoloop`)**: upstream warns that walking away from an active terminal allows someone else to Ctrl+C and inherit the cached `sudo` ticket — enable only on physically trusted single-user workstations.
- **Production Tuned Configuration (`topgrade.toml`)**:
  ```toml
  [misc]
  assume_yes = true
  ask_retry = false
  cleanup = true
  pre_sudo = true
  allow_root = false
  notify_end = "on_failure"
  # Disable steps that are uninstalled or managed exclusively via mise
  disable = ["uv", "cargo", "pi"]

  [windows]
  accept_all_updates = true
  winget_use_sudo = false

  [git]
  max_concurrency = 5
  fallback_to_fetch_default = true

  [mise]
  # Enables automatic version bumps for tools managed by mise
  bump = true
  interactive = false
  # Concurrency bound to CPU threads
  jobs = 4

  [post_commands]
  # Synchronize shims immediately after runtime updates
  "Mise Reshim" = "mise reshim"
  ```

### Polyglot Tool & Runtime Manager (`mise`)
- **Configuration**: `~/.config/mise/config.toml` (Linux/macOS; drop-ins in `~/.config/mise/conf.d/*.toml`) or `%APPDATA%\mise\config.toml` / `~/.config/mise/config.toml` (Windows; `%LOCALAPPDATA%\mise` holds data/shims). Do not use obsolete `settings.toml`.
- **Triad Tuning**:
  - *Performance*:
    - Thread Concurrency: Bound `jobs = $(nproc)` (e.g. 4, 8, 16, 32 depending on detected hardware CPU threads) to saturate network and I/O parallelism during multi-tool installations.
    - Subshell PATH & Environment Latency: Enable `env_cache = true` with `env_cache_ttl = "1h"`. This avoids spawning a full `mise hook-env` evaluation on every shell prompt or subshell invocation, cutting terminal startup and prompt latency by 80-90%.
    - Remote Metadata Query Caching: Set `fetch_remote_versions_cache = "1h"` and `fetch_remote_versions_timeout = "5s"` to eliminate interactive shell freezes during outbound network timeouts or GitHub API rate-limiting.
    - Fast Binary Installations: Keep `cargo.binstall = true` (default in `mise 2026.11+`, plus `cargo.binstall_quickinstall = true`) to fetch pre-compiled Rust binaries from GitHub releases instead of invoking local `cargo build --release` from source.
    - Windows Native Shims: Configure `windows_shim_mode = "exe"` on Windows for high-performance native PE shims instead of slower `.cmd` / `.bat` wrappers.
    - Git Submodule / Backend Speed: Enable `libgit2 = true` and `gix = true` for high-throughput native git operations.
  - *Configuration*:
    - Version Pinning: Set `pin = true` so tool additions record exact semantic versions in `mise.toml` rather than floating ranges.
    - Storage Hygiene & Lifecycle: Set `cache_prune_age = "7d"`, `download_cache = true`, and `download_cache_max_size = "2GiB"` (replacing deprecated `always_keep_download`, which emits a runtime `WARN` and is removed in `2027.11.0`). In `mise 2026.11+`, `upgrade.auto_prune = true` and `upgrade.prune_after = "24h"` also prune old upgraded versions automatically alongside Topgrade's `cleanup = true`.
    - Runtime Ergonomics: Set `node.corepack = true` for yarn/pnpm management, and configure `python.uv_venv_auto = "source"` to automatically source `uv` virtual environments upon directory navigation.
    - Topgrade Integration: Align `jobs` with Topgrade's `[mise] jobs` setting, configure `bump = true` in Topgrade, and run `mise doctor` / `mise settings ls` to validate config keys.
  - *Security & Supply-Chain Integrity*:
    - Supply-Chain Cooldowns: Configure `minimum_release_age` (e.g. `"3d"` or `"7d"`) with `minimum_release_age_excludes` for trusted fast-moving tools to mitigate newly published compromised upstream releases.
    - Provenance & Cryptographic Verification: `aqua.slsa = true`, `aqua.cosign = true`, `aqua.github_attestations = true`, `aqua.minisign = true`, `github_attestations = true`, `slsa = true`, `node.verify = true`, and `npm.provenance = true` are enabled by default in `mise 2026.11+` — verify they remain enabled (and consider `locked_verify_provenance`).
    - Restrict Config Permissions: Enforce `0600` permissions on `~/.config/mise/config.toml` to protect environment variables and private registry tokens. *(Note: `allow_root` is NOT a `mise` setting — it belongs in `topgrade.toml`'s `[misc]` section.)*
- **Production Tuned Configuration (`~/.config/mise/config.toml`)**:
  ```toml
  # Global Mise Production Configuration - Aligned with System Optimizer Triad
  [settings]
  # Performance & Concurrency
  jobs = 4                               # Aligned with host CPU logical threads
  env_cache = true                       # Eliminates shell hook latency
  env_cache_ttl = "1h"                   # Cache TTL for environment evaluations
  fetch_remote_versions_cache = "1h"     # Metadata cache to avoid network stalls
  fetch_remote_versions_timeout = "5s"   # Fail-fast network timeout
  cargo.binstall = true                  # Fetch pre-compiled Rust binaries (default)
  libgit2 = true                         # Native git library for fast cloning
  gix = true                             # Pure-Rust git backend
  windows_shim_mode = "exe"              # Fast native shims on Windows

  # Configuration & Ergonomics
  pin = true                             # Always pin exact version numbers
  cache_prune_age = "7d"                 # Auto-expire download caches
  download_cache = true                  # Keep bounded download cache (replaces always_keep_download)
  download_cache_max_size = "2GiB"       # Upper bound for cached downloads
  not_found_auto_install = true          # Auto-prompt to install missing tools
  node.corepack = true                   # Automatic Corepack management for Node
  python.uv_venv_auto = "source"         # Auto-source uv virtualenvs

  # Supply-Chain Security & Integrity
  minimum_release_age = "3d"             # Cooldown before adopting brand-new releases
  aqua.slsa = true                       # Verify SLSA provenance for aqua packages
  aqua.cosign = true                     # Verify Cosign cryptographic signatures
  aqua.minisign = true                   # Verify Minisign signatures
  github_attestations = true             # Verify GitHub artifact build attestations
  npm.provenance = true                  # Verify npm provenance attestations
  node.verify = true                     # Checksum & signature check for Node.js

  [tools]
  # Managed polyglot runtimes and CLI developer tools
  node = "lts"
  python = "latest"
  uv = "latest"
  rust = { version = "stable", components = "rust-analyzer" }
  go = "latest"

  # Single-source Neovim LSPs, formatters, linters & debuggers
  "aqua:LuaLS/lua-language-server" = "latest"
  "aqua:JohnnyMorganz/StyLua" = "latest"
  "aqua:mvdan/sh" = "latest"
  "aqua:koalaman/shellcheck" = "latest"
  "aqua:astral-sh/ruff" = "latest"
  "aqua:mvdan/gofumpt" = "latest"
  "aqua:golangci/golangci-lint" = "latest"
  "aqua:artempyanykh/marksman" = "latest"
  "aqua:tamasfe/taplo" = "latest"
  "go:golang.org/x/tools/gopls" = "latest"
  "go:golang.org/x/tools/cmd/goimports" = "latest"
  "npm:@vtsls/language-server" = "latest"
  "npm:vscode-langservers-extracted" = "latest"
  "npm:pyright" = "latest"
  "npm:bash-language-server" = "latest"
  "npm:markdownlint-cli2" = "latest"
  "npm:markdown-toc" = "latest"
  "github:Samsung/netcoredbg" = "latest"
  ```

### Mise & Topgrade Unified Workstation Orchestration Architecture
The combination of `topgrade` and `mise` forms the foundational modern workstation orchestration layer across Linux and Windows. To ensure deterministic, high-performance, and secure system maintenance without package manager drift or duplicate execution loops, the integration follows five core pillars:

1. **Strict Separation of Package Management Tiers**:
   - *Operating System Layer (Topgrade)*: Responsible for host-level OS packages, kernel updates, firmware, display drivers, container runtimes, and system-wide services via `pacman`, `yay`, `winget`, `apt`, or `flatpak`.
   - *Polyglot Toolchain & Runtime Layer (Mise)*: Responsible for per-user developer runtimes (`node`, `python`, `go`, `rust`, `java`, `dotnet`), build utilities (`uv`, `bun`, `pnpm`), and language servers (`gopls`, `pyright`, `typescript-language-server`).
   - *Integration Principle*: The OS package manager never manages user developer toolchains, and Mise never manages host system services. Topgrade acts as the overarching orchestrator that sequences both tiers in one unified run.

2. **Hardware Concurrency & Thread Budget Alignment**:
   - Both Topgrade's `[mise] jobs` and Mise's `jobs` setting are explicitly bound to the host physical/logical CPU core count (`$(nproc)`).
   - When Topgrade triggers `mise upgrade`, it runs tool downloads and builds at maximum thread capacity without oversubscribing host scheduler queues or causing UI stutters.

3. **Collision & Drift Prevention via Selective Step Disabling**:
   - Topgrade includes native built-in steps for standalone tools like `uv`, `bun_packages`, `npm`, `cargo`, and `pip`.
   - When these developer tools are managed by `mise`, running Topgrade's standalone steps leads to dual updates, conflicting versions, or permission errors (e.g. `uv self update` failing because the binary lives inside `~/.local/share/mise/installs/uv/`).
   - *Resolution*: Redundant steps are explicitly added to Topgrade's `disable = ["uv", ...]` list, delegating their complete lifecycle to Mise's `[mise] bump = true` step.

4. **Post-Run Lifecycle Synchronization (`cleanup` & `reshim`)**:
   - *Automated Cache Pruning*: Topgrade's `cleanup = true` triggers `mise prune -y` at the end of the update routine, purging older unreferenced tool versions and freeing NVMe/SSD capacity according to `cache_prune_age = "7d"`.
   - *Immediate Shim Synchronization*: Topgrade's `[post_commands]` executes `mise reshim` to immediately refresh binary shims and dynamic PATH pointers. Developers never encounter stale symlinks or "command not found" errors after an update run.

5. **Privilege Boundary Enforcement**:
   - Topgrade handles `sudo` elevation for OS-level updates (`pre_sudo = true`, `[misc] allow_root = false` in `topgrade.toml`), executing user `mise` tool updates strictly unprivileged in user space.

6. **Rust Tooling & Pre-compiled Binstall vs From-Source Rebuilds (`cargo` + `mise` + `topgrade`)**:
   - *The Bottleneck*: Topgrade has a default `[cargo]` step that runs `cargo install-update -a` (using `cargo-update`), which scans and compiles installed Rust CLI binaries from source code. On developer workstations, recompiling utilities like `ripgrep`, `bat`, `eza`, `starship`, `zoxide`, and `bottom` from source saturates CPU threads, exhausts memory, and causes 15–45 minute workstation update pauses.
   - *The Pre-compiled Binstall Solution*: When Rust CLI tools are managed via `mise` with `cargo.binstall = true`, `mise` queries GitHub release assets and downloads cryptographically verified, pre-compiled native binaries directly in seconds.
   - *De-duplication in Topgrade*: Topgrade's from-source `cargo` step is disabled via `disable = ["cargo"]` (or scoped strictly to private internal crates), while `[mise] bump = true` handles instantaneous binary updates.

### Rust Package Manager & Toolchain (`cargo`)
- **Configuration**: `~/.cargo/config.toml` (Linux/macOS) or `%USERPROFILE%\.cargo\config.toml` (Windows). *(Flag deprecated extensionless `~/.cargo/config` and rename to `config.toml`.)*
- **Triad Tuning**:
  - *Performance*:
    - Concurrency: Omit `build.jobs` — Cargo already defaults to logical CPU threads and avoids stale hardcoded core counts.
    - Sparse Registry Protocol: `registries.crates-io.protocol = "sparse"` is already the built-in default since Cargo 1.68 (do not emit redundantly).
    - Linker: `rustc 1.100+` on `x86_64-unknown-linux-gnu` already links with bundled `rust-lld` by default (omit redundant `-fuse-ld=lld`; optionally configure `mold` only if installed and needed).
    - Git Fetch CLI: Set `net.git-fetch-with-cli = true` to leverage host system Git credentials and SSH multiplexing.
    - De-duplication via Mise: Delegate global Rust CLI utility installations to `mise` with `cargo.binstall = true` (`mise use -g cargo:ripgrep`), reserving native `cargo install` strictly for packages without release binaries.
    - Cache Hygiene: Inspect `~/.cargo/registry/cache` and `~/.cargo/git/db` disk usage; clean stale downloads with `cargo-cache` or `cargo-sweep` (`cargo gc` / `-Z gc` remain nightly-only).
  - *Configuration*:
    - Scope release optimization flags (`opt-level = 3`, `lto = "thin"`, `codegen-units = 16`) strictly under `[profile.release]` (avoid global `build.rustflags = ["-C", "target-cpu=native"]`, which breaks cross-compilation and busts shared build caches).
  - *Security*:
    - Supply-Chain Security: Integrate `cargo-audit` and `cargo-vet` into CI/maintenance workflows.
    - Enforce verified checksums for all crate dependencies in `Cargo.lock`.
- **Production Tuned Configuration (`~/.cargo/config.toml`)**:
  ```toml
  # Cargo Production Configuration
  [net]
  git-fetch-with-cli = true         # Leverage system git & SSH multiplexing
  retry = 2

  [profile.release]
  opt-level = 3
  lto = "thin"
  codegen-units = 16
  ```
### Search Utilities (`ripgrep` / `rg` & `fd`)
- **`ripgrep` Configuration**: `$RIPGREP_CONFIG_PATH` pointing to `~/.config/ripgrep/config` or `%APPDATA%\ripgrep\config`.
- **`fd` Configuration**: `fd` (`10.5+`) has **no** config file (never check `~/.config/fd/config`); place global ignore patterns in `~/.config/fd/ignore` (`%APPDATA%\fd\ignore` on Windows).
- **Triad Tuning**:
  - *Performance*: Do **NOT** pass `--mmap` or `--threads=$(nproc)` in `ripgreprc` (and do not pass `-j` to `fd`): `rg` (`15.2+`) already auto-detects CPU cores (`--threads=0`) while staying single-threaded on single files, and automatically enables `--mmap` only when its heuristic determines it is faster (forcing `--mmap` degrades parallel directory traversal via kernel `mmap` contention and risks `SIGBUS` on truncated files). Keep `--max-columns=300` and `--max-columns-preview` to prevent runaway output on minified files.
  - *Configuration*: Enable `--smart-case` and standard ignore globs (`--glob=!.git/*`, `--glob=!node_modules/*`, `--glob=!target/*`, `--glob=!dist/*`, `--glob=!.venv/*`).
  - *Security*: Ignore hidden `.git` internals to prevent credential leakage in search output; sanitize regex queries.
### Directory Navigation (`zoxide`)
- **Database & State**: `%LOCALAPPDATA%\zoxide\db.zo` (Windows) or `~/.local/share/zoxide/db.zo` (Linux).
- **Triad Tuning**:
  - *Performance*: Initialize `zoxide init <shell>` once in shell startup (`~/.bashrc`, `~/.zshrc`, `config.fish`, or `$PROFILE`). Periodically prune dead/stale directory paths with `zoxide remove`.
  - *Configuration*: Standard aliases: `z` (jump) and `zi` (interactive fuzzy search with `fzf`). `_ZO_EXCLUDE_DIRS` is a **`os.PathListSeparator`-delimited environment variable** (`:` on Unix, `;` on Windows; `$HOME` is excluded by default) — e.g. `export _ZO_EXCLUDE_DIRS="/tmp:/var/tmp"` on Linux/macOS or `$env:_ZO_EXCLUDE_DIRS = "$env:TEMP;C:\Windows"` on Windows.
  - *Security*: Restrict the data directory (`chmod 0700 ~/.local/share/zoxide`) to maintain directory privacy. zoxide rewrites `db.zo` atomically (temp file + rename, `0666 & ~umask`) on every jump, so a `chmod 0600` on the file alone is reset; the inspector reports `(mode: 644, dir: 700 [OK])` for this case.

### Modern File Lister (`eza`)
- **Configuration**: `${EZA_CONFIG_DIR:-~/.config/eza}/theme.yml` or `%APPDATA%\eza\theme.yml`.
- **Triad Tuning**:
  - *Performance*: Avoid default `--git` scanning on deep directory trees or network shares; bind `--git` strictly to the detailed long listing alias (`ll`).
  - *Configuration*: Standard ergonomic aliases in `pwsh`, `bash`, and `zsh`:
    - `ls='eza --icons=auto'`
    - `ll='eza -l --icons=auto --git --header --time-style=relative'`
    - `la='eza -la --icons=auto --git --header'`
    - `lt='eza --tree --level=2 --icons=auto'`
    - Keep `=auto`: recent `eza` versions take an optional value for `--icons=WHEN`, so without `=auto`, `ls /sys` reads `/sys` as the icon mode and fails.
  - *Security*: Do **NOT** pass `--no-dereference` (`eza 0.23+` rejects it as an unexpected argument); `eza` already does not dereference symlinks by default unless `-X`/`--dereference`/`--follow-symlinks` is passed.
### Git Terminal UI (`lazygit`)
- **Configuration**: `%APPDATA%\lazygit\config.yml` or `~/.config/lazygit/config.yml` (`lazygit --config` prints the active defaults).
- **Triad Tuning**:
  - *Performance*: Set `git.autoFetch: false` (vital on Windows to prevent background git subprocesses from continuously triggering Microsoft Defender file scans) and `gui.animateExplosion: false` (under `gui:`, not bare top-level `animateExplosion`).
  - *Configuration*:
    - Diff rendering (`lazygit 0.66+` migrated `git.paging` → `git.pagers` → `git.diffRenderers`):
      ```yaml
      gui:
        nerdFontsVersion: "3"
        animateExplosion: false
      git:
        autoFetch: false
        diffRenderers:
          - colorArg: always
            command: bat --color=always --style=changes,numbers
      os:
        editPreset: "nvim-remote"
      ```
    - Prefer `os.editPreset: "nvim-remote"` (or `os.edit` with `{{filename}}` — never `$FILE` or removed `os.editCommand`/`os.editCommandTemplate`); replace deprecated `gui.showIcons` with `gui.nerdFontsVersion: "3"`; synchronize theme palette with active terminal/editor or prompt user.
  - *Security*: Respect git `safe.directory` rules; avoid untrusted custom commands.
### Modal Text Editor (`neovim` / `nvim`)
- **Configuration**: `%LOCALAPPDATA%\nvim\init.lua` (Windows) or `~/.config/nvim/init.lua` (Linux), plus modular `lua/config/*.lua` and `lua/plugins/*.lua` (LazyVim / `lazy.nvim`).
- **Production Performance `init.lua` / `lua/config/options.lua` Template**:
  ```lua
  -- 1. Bytecode loader caching: cuts Neovim startup time to <65ms
  if vim.loader then
    vim.loader.enable()
  end

  -- 2. Mise shims prepended + Mason bin appended on PATH:
  --    Ensures Mise shims take priority even when launched from GUI/desktop,
  --    while editor-only Mason adapters (roslyn, codelldb, js-debug-adapter)
  --    remain immediately discoverable before mason.nvim lazy-loads.
  local is_win = vim.fn.has("win32") == 1
  local sep = is_win and ";" or ":"
  local mise_shims = is_win and vim.fn.expand("$LOCALAPPDATA/mise/shims") or vim.fn.expand("~/.local/share/mise/shims")
  if vim.fn.isdirectory(mise_shims) == 1 and not vim.env.PATH:find(mise_shims, 1, true) then
    vim.env.PATH = mise_shims .. sep .. vim.env.PATH
  end
  local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
  if vim.fn.isdirectory(mason_bin) == 1 and not vim.env.PATH:find(mason_bin, 1, true) then
    vim.env.PATH = vim.env.PATH .. sep .. mason_bin
  end
  vim.env.MASON = vim.fn.stdpath("data") .. "/mason"

  -- 3. Disable unused legacy remote plugin hosts (saves 50-100ms startup)
  vim.g.loaded_node_provider = 0
  vim.g.loaded_python3_provider = 0
  vim.g.loaded_perl_provider = 0
  vim.g.loaded_ruby_provider = 0

  -- 4. Core ergonomics & persistent undo
  vim.opt.undofile = true
  vim.opt.undolevels = 10000
  vim.opt.updatetime = 200
  vim.opt.timeoutlen = 300

  -- 5. Security: block arbitrary execution from downloaded files
  vim.opt.modeline = false
  -- vim.opt.exrc already defaults to false in Neovim 0.12 (using cryptographic :trust prompts if enabled)
  ```
- **Triad Tuning**:
  - *Performance*:
    - Enable byte-compiled Lua caching at the top of `init.lua` (`vim.loader.enable()`).
    - Disable legacy remote providers (`loaded_node_provider`, `loaded_python3_provider`, `loaded_perl_provider`, `loaded_ruby_provider = 0`).
    - Disable unused built-in runtime plugins (`gzip`, `tarPlugin`, `tohtml`, `tutor`, `zipPlugin`, `netrwPlugin`), while **retaining `matchit` and `matchparen`** (negligible <1ms cost in Neovim 0.12+, required for `%` block/tag jumping unless `vim-matchup` is installed).
    - Resolve language servers and formatters directly via `mise` shims on `PATH` without spawning synchronous `mise which` subshells.
    - Rotate or truncate oversized `~/.local/state/nvim/lsp.log` when it exceeds 1 MB.
  - *Configuration*:
    - Integrate with system clipboard (`win32yank`/`powershell` on Windows, `wl-clipboard`/`xclip` on Linux).
    - **Neovim `0.11` / `0.12` Native LSP & `vim.pack`**: For non-LazyVim setups, migrate deprecated `require("lspconfig").<server>.setup()` calls to native `vim.lsp.config("<server>", { ... })` + `vim.lsp.enable("<server>")` (Neovim `0.12` also adds built-in `vim.pack`).
    - Single-source LSP, linter, formatter, and debugger provisioning via `mise` (`aqua:`, `go:`, `npm:`, `github:` backends), locking `mason.nvim` strictly to editor-only VSIX/custom-registry bundles (`codelldb`, `js-debug-adapter`, `roslyn`).
    - Async `DirChanged` + `VimEnter` hook running `mise env --json` to dynamically sync project `.mise.toml` `[env]` variables (`GOPATH`, `JAVA_HOME`, virtualenvs, custom project vars) when switching projects inside a running Neovim instance.
    - **LazyVim `v15` / `v16+` & Modern Plugin Hygiene**:
      - **`nvim-treesitter` (`main` branch rewrite)**: Never call `require("nvim-treesitter.configs").setup(opts)` (removed in the `main` branch rewrite; LazyVim `16.x` uses native `vim.treesitter.start` and requires Neovim `>= 0.12` for unpinned `main`). Use `opts_extend = { "ensure_installed" }` with `opts = { ensure_installed = { ... } }` and ensure `tree-sitter` CLI (`>= 0.26.1`) is installed.
      - **Avoid Redundant Fold/Bigfile Overrides**: Do not override `vim.opt.foldexpr` or create custom `BigFileDisable` `BufReadPre` autocmds when using LazyVim/`snacks.nvim` — LazyVim `16+` uses `v:lua.LazyVim.treesitter.foldexpr()` and `v:lua.vim.lsp.foldexpr()` (replacing deprecated `v:lua.lazyvim.util.ui.foldexpr()`), and `snacks.nvim` provides `bigfile = { enabled = true, size = 1.5 * 1024 * 1024 }`.
      - **`blink.cmp` + `crates.nvim`**: LazyVim `15/16+` defaults to `blink.cmp` and `snacks.nvim`. Set `completion = { cmp = { enabled = false } }` on `saecki/crates.nvim` so `:checkhealth` does not warn about missing `nvim-cmp`.
      - **Modern AI & Lua Dev Extras**: Prefer `lazyvim.plugins.extras.ai.copilot-native` (native Neovim 0.12 LSP inline completions) or `ai.sidekick` (`folke/sidekick.nvim`) over legacy `ai.copilot-chat`, and replace deprecated `"neodev"` keys in `.neoconf.json` with `"lazydev"` (`folke/lazydev.nvim`).
      - **Backup File Hygiene**: Never leave `.bak.*` files inside `~/.config/nvim/lua/` (keep backups strictly in `~/.config/system-optimizer/backups/neovim/`).
  - *Security*: Disable insecure modelines (`vim.opt.modeline = false`; note `exrc` already defaults to `false` in Neovim 0.12 with cryptographic SHA-256 `:trust` verification); enforce plugin lockfile commit pinning in `lazy-lock.json`; validate cleanly via `nvim --headless +q`.

#### Neovim & Mise Polyglot LSP, Formatter & Toolchain Architecture
The integration between Neovim and Mise establishes a unified, reproducible development environment where language servers, linters, and formatters are managed by Mise (with SLSA/Cosign verification) and shared identically across terminal, Git hooks, CI, and Neovim.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                     Polyglot Toolchain & LSPs in Mise                            │
│  aqua:LuaLS/lua-language-server   aqua:JohnnyMorganz/StyLua   aqua:mvdan/sh      │
│  aqua:koalaman/shellcheck         aqua:astral-sh/ruff         aqua:tamasfe/taplo │
│  aqua:artempyanykh/marksman       aqua:mvdan/gofumpt          aqua:golangci-lint │
│  go:golang.org/x/tools/gopls      go:golang.org/x/tools/cmd/goimports            │
│  npm:@vtsls/language-server       npm:vscode-langservers-extracted               │
│  npm:pyright  npm:markdownlint-cli2  npm:markdown-toc  github:Samsung/netcoredbg │
└────────────────────────────────────────┬─────────────────────────────────────────┘
                                         │
                     ┌───────────────────┴───────────────────┐
                     ▼                                       ▼
        ┌─────────────────────────┐             ┌─────────────────────────┐
        │  Terminal / Git Hooks   │             │   Neovim (LSP Client)   │
        │  mise exec / CI parity  │             │ nvim-lspconfig / conform│
        └─────────────────────────┘             └─────────────────────────┘
                     ▲                                       ▲
                     │                                       │
┌────────────────────┴───────────────────────────────────────┴─────────────────────┐
│                           Topgrade Orchestration                                 │
│  1. [mise] bump = true  -->  2. mise reshim  -->  3. Instant Neovim LSP Refresh  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

1. **Migrating Mason Packages to Mise & Locking Down `mason.nvim`**:
   - **Why**: By default, `mason.nvim` and LazyVim `lang.*` extras (`lang.go`, `lang.python`, `lang.typescript`, `lang.rust`, `lang.json`, `lang.markdown`, `util.dot`) install duplicate private copies of language servers, formatters, and linters into `~/.local/share/nvim/mason/packages/`. In `mason-lspconfig.nvim` v2 / LazyVim `16+`, `automatic_installation` was replaced by `automatic_enable` (calling `vim.lsp.enable()`); prevent Mason from installing Mise-managed LSPs via `opts_extend = {}` on `mason.nvim` and `opts.servers.<name>.mason = false` in `nvim-lspconfig` (or `automatic_enable = false` in standalone setups).
   - **Mise Backend Mapping for Neovim Tools**:
     - *Aqua Registry (cryptographically verified binaries)*: `aqua:LuaLS/lua-language-server`, `aqua:JohnnyMorganz/StyLua`, `aqua:mvdan/sh` (`shfmt`), `aqua:koalaman/shellcheck`, `aqua:astral-sh/ruff`, `aqua:mvdan/gofumpt`, `aqua:golangci/golangci-lint`, `aqua:artempyanykh/marksman`, `aqua:tamasfe/taplo`.
     - *Go Backend*: `go:golang.org/x/tools/gopls`, `go:golang.org/x/tools/cmd/goimports` (plus `dlv` via Go/system).
     - *NPM Backend*: `npm:@vtsls/language-server`, `npm:vscode-langservers-extracted` (`vscode-json-language-server`, `vscode-eslint-language-server`), `npm:pyright`, `npm:bash-language-server`, `npm:markdownlint-cli2`, `npm:markdown-toc`.
     - *GitHub Releases Backend*: `github:Samsung/netcoredbg` (C#/.NET debugger).
     - *Toolchain Built-ins*: `rust = { version = "stable", components = "rust-analyzer" }` (IMPORTANT: `rustup`'s default profile only installs `cargo`/`clippy`/`rustfmt` and creates a proxy symlink `~/.cargo/bin/rust-analyzer -> rustup`; without `components = "rust-analyzer"`, invoking `~/.local/share/mise/shims/rust-analyzer` triggers `rust-analyzer is unavailable for the active toolchain -> falling back to mise/shims/rust-analyzer -> error: infinite recursion detected`).
   - **Editor-Only Packages Retained in Mason**: Reserve Mason strictly for VSIX bundles or custom-registry editor adapters that do not belong in global CLI toolchains: `codelldb` (C/C++/Rust LLDB VSIX), `js-debug-adapter` (VSCode JS DAP bundle), and `roslyn` (from `github:Crashdummyy/mason-registry`). Uninstall all migrated packages from `~/.local/share/nvim/mason/packages/`.
   - **Recommended `lua/plugins/mason.lua` Configuration**:
     ```lua
     return {
       {
         "mason-org/mason.nvim",
         opts_extend = {}, -- Prevent LazyVim lang extras from re-adding Mise-managed tools
         opts = {
           PATH = "append", -- Mise shims take priority; Mason acts strictly as fallback
           registries = {
             "github:mason-org/mason-registry",
             "github:Crashdummyy/mason-registry", -- If using roslyn.nvim
           },
           ensure_installed = {
             "codelldb",
             "js-debug-adapter",
             "roslyn",
           },
         },
       },
       {
         "mason-org/mason-lspconfig.nvim",
         -- Mason v2 / LazyVim 16+ uses automatic_enable (not removed automatic_installation)
         opts = { ensure_installed = {}, automatic_enable = false },
       },
       {
         "jay-babu/mason-nvim-dap.nvim",
         optional = true,
         opts = { ensure_installed = {}, automatic_installation = false },
       },
       {
         "neovim/nvim-lspconfig",
         opts = function(_, opts)
           opts.servers = opts.servers or {}
           for _, server in ipairs({
             "bashls", "eslint", "gopls", "jsonls", "lua_ls", "marksman",
             "pyright", "ruff", "rust_analyzer", "taplo", "vtsls",
           }) do
             opts.servers[server] = opts.servers[server] or {}
             opts.servers[server].mason = false
           end
         end,
       },
     }
     ```

2. **Dynamic Per-Project Mise `[env]` Synchronization (`lua/config/autocmds.lua`)**:
   - While Mise shims resolve project-pinned binaries automatically, project-specific `[env]` variables defined in `.mise.toml` (`GOPATH`, `JAVA_HOME`, custom env vars) are not updated when switching directories inside a running Neovim session (e.g., via `Snacks.picker.projects`).
   - Add a non-blocking `DirChanged` + `VimEnter` autocmd using `vim.system`:
     ```lua
     local mise_bin = vim.fn.exepath("mise")
     if mise_bin ~= "" then
       local function sync_mise_env(cwd)
         vim.system({ mise_bin, "env", "--json" }, { cwd = cwd, text = true }, function(obj)
           if obj.code ~= 0 or not obj.stdout or obj.stdout == "" then return end
           vim.schedule(function()
             local ok, env_map = pcall(vim.json.decode, obj.stdout)
             if not ok or type(env_map) ~= "table" then return end
             for k, v in pairs(env_map) do
               if k ~= "PATH" and k ~= "SHLVL" and k ~= "_" and k ~= "PWD" and k ~= "OLDPWD"
                 and not k:match("^__MISE_") and not k:match("^MISE_")
                 and type(v) == "string" then
                 vim.env[k] = v
               end
             end
           end)
         end)
       end
       vim.api.nvim_create_autocmd({ "DirChanged", "VimEnter" }, {
         group = vim.api.nvim_create_augroup("mise_env_sync", { clear = true }),
         callback = function() sync_mise_env(vim.fn.getcwd()) end,
       })
     end
     ```

3. **Unified Maintenance Chain (`topgrade` -> `mise` -> `neovim`)**:
   - When workstation maintenance runs via `topgrade`:
     1. Topgrade executes the `[mise]` update step with `bump = true`, updating language servers, linters, and formatters to latest upstream stable releases.
     2. Topgrade executes `mise reshim` via `[post_commands]`.
     3. Neovim automatically picks up updated language servers upon next launch or `:LspRestart`, while `MasonUpdateAll` only needs to check the 2–3 remaining editor-only adapters.
### Syntax Pager & Fuzzy Finder (`bat` + `fzf`)
- **`bat` (`0.26+`) Tuning (`$(bat --config-file)` / `$BAT_CONFIG_PATH` / `~/.config/bat/config`)**:
  - *Performance*: Set `--paging=never` when used as a sub-pager for lazygit or git diff; run `bat cache --build` **only** when custom `.tmTheme`/`.sublime-syntax` files exist under `$(bat --config-dir)/{themes,syntaxes}`. Validate with `bat --diagnostic`.
  - *Configuration*: Prefer adaptive `--theme=auto` paired with `--theme-dark="<theme>"` and `--theme-light="<theme>"` (`BAT_THEME_DARK` / `BAT_THEME_LIGHT`) aligned to the inferred terminal/editor palette, and set `--style="numbers,changes,header"`.
- **`fzf` (`0.75+`) Tuning (`FZF_DEFAULT_COMMAND`, `FZF_DEFAULT_OPTS`, `FZF_DEFAULT_OPTS_FILE`)**:
  - *Performance*: `fzf`'s built-in `--walker=file,follow,hidden` (`--walker-skip=.git,node_modules`) is already **multithreaded** when `FZF_DEFAULT_COMMAND` is unset. Wire `fd --type f --strip-cwd-prefix --hidden --exclude .git` or `rg --files --hidden --glob '!.git/*'` when `.gitignore`-aware filtering is desired.
  - *Configuration*: Initialize shell keybindings/completion natively with `eval "$(fzf --bash)"`, `source <(fzf --zsh)`, or `fzf --fish | source` (replacing legacy `/usr/share/fzf/key-bindings.*` scripts). Use `--info=inline-right` (replacing deprecated `--inline-info`), `--style=minimal` or `default`, `FZF_DEFAULT_OPTS_FILE` (`~/.config/fzf/fzfrc`), and `bat` previews clamped to `--line-range :300`.
  - *Security*: Exclude sensitive files (`.git/`, `.env*`, `id_rsa*`) from the default search index.

### Shell Prompt (`starship` `1.27+`)
- **Configuration**: `~/.config/starship.toml` or `%APPDATA%\starship.toml`.
- **Important `[mise]` Module Behavior (`starship 1.27+`)**:
  - `[mise]` defaults to `disabled = true` and exposes **only `$symbol` and `$health`** (default `format = "on [$symbol$health]($style) "`) — it has **no `$version` variable** (putting `$version` in `[mise] format` renders empty).
  - Choose one of two patterns: (a) keep per-language modules enabled while relying on `mise` `env_cache = true` for fast shim resolution, or (b) enable `[mise] disabled = false` with `format = "on [$symbol$health]($style) "` to show Mise health status without spawning per-language version queries.
- **Production Performance `starship.toml` Template**:
  ```toml
  # Starship Production Performance Configuration
  # Bounds prompt command evaluation to prevent terminal hitching
  command_timeout = 500
  add_newline = false

  format = """
  $directory\
  $git_branch\
  $git_status\
  $mise\
  $character"""

  [directory]
  truncation_length = 3
  truncate_to_repo = true
  style = "bold cyan"

  [git_branch]
  symbol = " "
  style = "bold purple"

  [git_status]
  style = "bold red"
  conflicted = "="
  ahead = "⇡"
  behind = "⇣"
  diverged = "⇕"
  untracked = "?"
  modified = "!"
  staged = "+"

  # Native Mise module: exposes $symbol and $health (not $version)
  [mise]
  disabled = false
  format = "on [$symbol$health]($style) "
  symbol = " "
  style = "bold yellow"

  # Disable slow per-language modules only if you intentionally omit runtime versions from the prompt
  [nodejs]
  disabled = true
  [python]
  disabled = true
  [rust]
  disabled = true
  [golang]
  disabled = true

  [character]
  success_symbol = "[❯](bold green)"
  error_symbol = "[❯](bold red)"
  ```
- **Shell Integration (`bash`, `zsh`, `fish` & `pwsh`)**:
  - Note: When caching init output to a file for fast shell startup, always pass **`--print-full-init`** (`starship init bash` alone emits only a `source <(...)` subshell stub!).
  - *Bash* (`~/.bashrc`):
    ```bash
    # Activate mise with environment caching
    if command -v mise >/dev/null 2>&1; then
      eval "$(mise activate bash)"
    fi
    # Fast Starship prompt hook (use --print-full-init when caching to a static file)
    if command -v starship >/dev/null 2>&1; then
      eval "$(starship init bash --print-full-init)"
    fi
    ```
  - *PowerShell 7* (`$PROFILE`):
    ```powershell
    # Activate mise
    if (Get-Command mise -ErrorAction SilentlyContinue) {
      Invoke-Expression (&mise activate pwsh | Out-String)
    }
    # Fast Starship prompt hook (use --print-full-init when caching)
    if (Get-Command starship -ErrorAction SilentlyContinue) {
      Invoke-Expression (&starship init pwsh --print-full-init | Out-String)
    }
    ```
- **Triad Tuning**:
  - *Performance*: Set `command_timeout = 500` (integer ms); enable `env_cache = true` (`1h` TTL) in `mise`; use `--print-full-init` if caching init scripts.
  - *Configuration*: Minimalist clean layout; directory truncation length 3; consistent Nerd Font symbols.
  - *Security*: Avoid executing arbitrary remote network queries in custom prompt modules (`[custom.*]`); restrict `starship.toml` permissions to `0600`.
### Media Player (`mpv` `0.42+`)
- **Configuration**: `%APPDATA%\mpv\mpv.conf` (Windows) or `~/.config/mpv/mpv.conf` (Linux). Enforce `0600`.
- **Triad Tuning**:
  - *Performance*:
    - Discrete GPU / modern iGPU: `vo=gpu-next` (default in `mpv 0.41+`), `gpu-api=d3d11` (Windows) or `gpu-api=vulkan` (Linux), `profile=high-quality` (replaces legacy alias `gpu-hq`), and zero-copy **`hwdec=auto-safe`** (or `nvdec,vulkan,auto` / `vaapi,vulkan,auto` / `d3d11va,vulkan,auto` — avoid `nvdec-copy` unless CPU-side video filters require GPU→RAM copyback).
    - Legacy Intel iGPU (Haswell / Ivy Bridge / HD Graphics 4xxx): conservative `vo=gpu`, `gpu-api=opengl`, `profile=fast`, and `hwdec=vaapi` + `hwdec-codecs=h264,mpeg2video,vc1` (matching `vainfo` on Linux instead of `auto-safe` to avoid CUDA/VDPAU/VP9 probe errors before clean software decode fallback).
    - `interpolation=yes`, `video-sync=display-resample`: Smooth motion on high-refresh displays.
  - *Configuration*: Keep `tone-mapping=auto` (`hdr-compute-peak=auto`, libplacebo spline/dynamic ST.2094 under `vo=gpu-next`, resolving to `bt.2390` under `vo=gpu` — never pair `bt.2446a`, `spline`, `st2094-40`, or `st2094-10` with `vo=gpu`) and `target-colorspace-hint=auto` (set `target-colorspace-hint=yes` only when HDR display mode is active so SDR panels do not get washed-out PQ signals); remove `tone-mapping-desaturate` / `tone-mapping-desaturate-exponent` if present (removed in `mpv 0.42`; libplacebo tone mapping handles desaturation); bound `ytdl-format` to `1080p/best` and add `script-opts-append=ytdl_hook-all_formats=no` when pinning codecs via `ytdl-format` on `mpv 0.42+`.
  - *Security*: Enforce TLS certificate verification (never pass `no-check-certificates` in `ytdl-raw-options`); restrict untrusted Lua scripts; enforce `0600` on `mpv.conf`.

### Streaming Media Center (`stremio`)
- **Installation & Paths**:
  - *Linux*: Flatpak `com.stremio.Stremio` (`stremio-linux-shell` GTK4/`libmpv`), storing server state in `~/.var/app/com.stremio.Stremio/.stremio-server/server-settings.json` (or `.../data/.stremio-server/server-settings.json` and native `~/.stremio-server/server-settings.json`), and Flatpak GSettings keyfile at `~/.var/app/com.stremio.Stremio/config/glib-2.0/settings/keyfile`.
  - *Windows*: Stremio 5 (`%LOCALAPPDATA%\Programs\LNV\Stremio-5\stremio-shell-ng.exe` with `portable_config\mpv.conf`), Stremio 4 (`%LOCALAPPDATA%\Programs\LNV\Stremio\stremio.exe`), and server config at `%APPDATA%\stremio\stremio-server\server-settings.json`.
- **Triad Tuning**:
  - *Performance*: Keep hardware-accelerated decoding enabled (`hwdec=auto-safe` in embedded `libmpv`; on Flatpak with legacy Intel iGPUs where host `LIBVA_DRIVER_NAME` is set, forward it via `flatpak override --user --env=LIBVA_DRIVER_NAME=<driver> com.stremio.Stremio` if VA-API decode fails). Size `cacheSize` in `server-settings.json` to disk/RAM tier (`2147483648` = 2 GiB on small SSDs/low RAM; 5–10 GiB on larger SSDs; avoid unbounded `null` on tight drives). Raise Torrent Profile (`btDownloadSpeedSoftLimit`/`btDownloadSpeedHardLimit`, `btMaxConnections` 55–200) when 4K P2P streams buffer; enable `transcodeHardwareAccel` where GPU supports VA-API/NVENC/D3D11VA.
  - *Configuration*: Quit Stremio and its server process completely before editing `server-settings.json` (Stremio overwrites it on exit). When attaching a custom `mpv.conf` via `mpv-config-location` (Linux) or `portable_config\mpv.conf` (Windows Stremio 5), keep `vo=libmpv` intact (do not force `vo=gpu-next`).
  - *Security*: Keep the local streaming server bound to loopback (`127.0.0.1:11470`, `remoteHttps: ""` unless behind an authenticated HTTPS reverse proxy or VPN on port `12470`); restrict `.stremio-server` to `0700` (or `server-settings.json` to `0600`); audit third-party community addons; avoid broad Flatpak `filesystems=host` overrides.

### Media Downloader (`yt-dlp` `2026+`)
- **Configuration**: `%APPDATA%\yt-dlp\config` or `~/.config/yt-dlp/config`.
- **Triad Tuning**:
  - *Performance*: Use yt-dlp's native downloader with `-N 4` (`--concurrent-fragments 4`) and integrate `ffmpeg`. **Warn against global `--downloader aria2c`** in `yt-dlp/config`: `aria2c` bypasses dynamic range chunking, SABR handling, and session state, triggering YouTube HTTP 403s or severe throttling (if used for generic HTTP files, scope with `--downloader "dash,m3u8:native"`).
  - *Configuration*: YouTube extraction now requires **`yt-dlp-ejs`** + an active JS runtime (`--js-runtimes deno|node|bun|quickjs`; only `deno` is enabled by default — configure `--js-runtimes node` or `bun` if `deno` is absent). Keep `--no-remote-components` (default) when `yt-dlp-ejs` is installed via package manager; default format `bestvideo+bestaudio/best`, embed subtitles and chapter markers.
  - *Security*: **Warn against setting `--impersonate` globally** in `yt-dlp/config` (upstream warns it degrades speed/stability; use per-command/extractor only). Restrict untrusted cookie injection; sanitize output filenames.

### Remote Desktop (`rustdesk` `1.5+`)
- **Configuration**: `%APPDATA%\RustDesk\config\RustDesk2.toml` (and `C:\Windows\ServiceProfiles\LocalService\AppData\Roaming\RustDesk\config\RustDesk2.toml` for Windows service mode) or `~/.config/rustdesk/RustDesk2.toml` (Linux).
- **Triad Tuning**:
  - *Performance*: Hardware video acceleration (NVENC/Direct3D on Windows, VA-API/NVENC on Linux) for low-CPU 60 FPS streaming.
  - *Configuration*: Custom private ID and relay server settings; tray minimization.
  - *Security*: Audit `RustDesk2.toml` `[options]` for `verification-method = 'use-permanent-password'`, `direct-server = 'Y'` (disable direct IP access if relay-only is desired), `approve-mode`, `enable-lan-discovery`, and `allow-linux-headless`; whitelist approved peer IDs.

### Git Version Control (`git` `2.56+`)
- **Configuration**: `~/.gitconfig` (or `~/.config/git/config`), `%PROGRAMDATA%\Git\config`. Validate with `git config --list >/dev/null`.
- **Cross-Platform Triad Tuning**:
  - `feature.manyFiles = true`: Enables `index.version = 4`, `index.skipHash = true`, and `core.untrackedCache = true` together for large worktrees.
  - `diff.algorithm = histogram` & `merge.conflictStyle = zdiff3`: Cleaner diffs and 3-way conflict markers showing the common ancestor.
  - `branch.sort = -committerdate` & `tag.sort = version:refname`: Surfaces active branches and semantic tags first.
  - `rerere.enabled = true` & `rerere.autoUpdate = true`: Remembers and auto-stages recurring conflict resolutions.
  - `fetch.prune = true`, `push.autoSetupRemote = true`, `rebase.autoStash = true`, `rebase.autoSquash = true`, `rebase.updateRefs = true`.
  - `core.fsmonitor = true` *(per-large-repo, native filesystems only — avoid on NFS, `/mnt/c`, or submodule-heavy superprojects; Linux uses built-in `inotify` daemon)*.
  - `core.autocrlf = input` on Linux/macOS (`true` on Windows). *(Note: `core.preloadIndex = true` has been Git's default since v2.1.0.)*
- **Windows-Only Tuning**:
  - `core.fscache = true`: Git-for-Windows NTFS stat cache (does **not** exist in upstream/Linux Git — scope strictly to Windows).
  - `credential.helper = manager`: Integrates with Windows Credential Manager.
### GitHub CLI (`gh` `2.104+`)
- **Configuration**: `~/.config/gh/config.yml`, `~/.config/gh/hosts.yml` (Linux/macOS) or `%APPDATA%\GitHub CLI\` (Windows). *(Note: `config.yml` is **YAML** (`key: value`), not TOML `=`.)*
- **Synergies**:
  - **Git & LazyGit Credential Helper (HTTPS)**: Running `gh auth setup-git` configures `credential.helper` for **HTTPS** GitHub remotes (SSH remotes use your SSH agent/keys directly).
  - **LazyGit TUI Integration**: Custom LazyGit keybindings invoke `gh pr view --web`, `gh pr checkout`, and `gh pr create` directly from branch and commit views.
  - **Bat Syntax Pager**: Setting `gh config set pager "bat --color=always --style=plain"` gives zero-latency syntax-highlighted diffs during `gh pr diff` and `gh pr view` reviews.
  - **Topgrade Automated Maintenance**: Topgrade `17+` includes a native `github_cli_extensions` step (and `github_cli_skills`) — do not add redundant `gh extension upgrade --all` commands.
  - **Neovim Remote Review**: Setting `gh config set editor "nvim"` or using `octo.nvim` connects GitHub CLI data with modal editing.
  - **Autonomous AI Coding Agents (`pi` & `herdr`)**: Non-interactive agent runs execute `gh pr`, `gh issue`, and `gh run watch` to inspect CI and create pull requests without browser interaction.
- **Triad Tuning**:
  - *Performance*: Use `bat --color=always --style=plain` as `pager`; leverage `--json` + `jq` in scripts; let Topgrade's native `github_cli_extensions` step batch extension updates.
  - *Configuration* (`~/.config/gh/config.yml`):
    ```yaml
    git_protocol: ssh   # or https (with `gh auth setup-git`)
    prompt: enabled
    pager: bat --color=always --style=plain
    color_labels: enabled
    aliases:
      co: pr checkout
      pv: pr view
      pc: pr create
      il: issue list
    ```
  - *Security*:
    - Prefer OS keyring credential storage (`gh auth login`) over plaintext `oauth_token:` in `hosts.yml`; enforce `0600` on `~/.config/gh/hosts.yml`.
    - Inspect `telemetry: disabled` (default — warn if enabled) and `expiring_credentials: enabled` (auto-refreshing expiring tokens).
    - Audit installed extensions (`gh extension list`, e.g. `gh-dash`, `gh-poi`; note `gh-copilot` is retired) and request least-privilege OAuth scopes.
### Pi Coding Agent Harness (`pi` `1.5.2+`)
- **Configuration**: `${PI_CODING_AGENT_DIR:-~/.pi/agent}/settings.json` (validates against `dist/settings.schema.json`), `auth.json` (`0600`), `mcp-auth.json` (`0600`), `models.json`, `mcp.json`, `trust.json`, `keybindings.json`, and `sessions/`. *(Note: core Pi 1.5+ has no `model-router.json` or `~/.pi/web-search.json` — those are optional third-party extension artifacts.)*
- **Mise Toolchain Synergy**:
  - Autonomous agents frequently execute shell commands (`bash -c "npm test"` or `pwsh -Command "pytest"`). Non-interactive subshells bypass interactive `.bashrc` activation hooks, causing `command not found` or system binary drift.
  - Adding `~/.local/share/mise/shims` (or `%LOCALAPPDATA%\mise\shims`, or configuring Pi's `shellPath` / `shellCommandPrefix`) ensures agents execute project-pinned toolchains defined in `.mise.toml`.
- **Triad Tuning**:
  - *Performance*:
    - Prompt cache warming: Set `"cacheWarming": "idle"` (default in 1.5.2, supersedes legacy `experimental.preservePromptCache`) and `PI_CACHE_RETENTION=long`; configure `transport` (`"auto" | "sse" | "websocket" | "websocket-cached"`).
    - Built-in `codemode` & deferred MCP: Enable `defaultTools: ["+codemode"]` and MCP `exposure: "codemode"` / `"deferred"` to avoid context bloat from direct MCP tool schemas.
    - Note `compaction.reserveTokens = 16384` is already the built-in default (tune `compaction.modelOverrides` or `keepRecentTokens` only if needed); prune `sessions/` >30d and monitor `mcp.log` (rotates at 5 MB).
  - *Configuration*: Configure `PI_CLIPBOARD_OSC52=1` (helpful inside `herdr` remote sessions), `terminal.showTerminalProgress`, `tuiMode: "fullscreen"`, and `selfUpdateCommand` / `PI_SELF_UPDATE_COMMAND` (disable Topgrade's `"pi"` step when `pi` is managed by `mise`).
  - *Security*:
    - Enforce `0600` on **both** `auth.json` and `mcp-auth.json`.
    - Use built-in `defaultProjectTrust` (`"ask"` or `"never"`, stored in `trust.json`, never `"always"` globally) and tool gating (`defaultTools` / `--tools` / `--exclude-tools`) — note `permissions.deny` is **not** a built-in Pi setting (path-level denies require OS/container sandboxing or a `tool_call` extension).
    - Review `enableInstallTelemetry` (`false` or `PI_TELEMETRY=0` if strict privacy is desired) and install npm extensions/updates with `--ignore-scripts`.
### Google Antigravity CLI & Agent Platform (`antigravity` / `agy` `1.5+`)
- **Configuration & State**:
  - CLI settings: `~/.gemini/antigravity-cli/settings.json` (`model`, `colorScheme`, `allowNonWorkspaceAccess`, `trustedWorkspaces`)
  - Global customizations: `~/.gemini/config/` (`config.json`, `skills/`, `skills.json`, `plugins/`, `plugins.json`, `hooks.json`, `mcp_config.json`)
  - Workspace customizations: `<repo>/.agents/` (`skills/`, `plugins/`, `rules/*.md`, `skills.json`, `plugins.json`, `hooks.json`) plus `GEMINI.md` / `AGENTS.md`
  - Credentials & session artifacts: `~/.gemini/oauth_creds.json` (`0600`), `~/.gemini/trustedFolders.json`, `~/.gemini/antigravity-cli/brain/`
- **Triad Tuning**:
  - *Performance*:
    - Respect progressive disclosure budgets: keep always-on `GEMINI.md` / `AGENTS.md` rule files compact (per-file cap 24 KB, global aggregate rules budget 20k tokens) and offload multi-step workflows into `skills/<name>/SKILL.md` with `references/`.
    - Prune stale session artifacts under `~/.gemini/antigravity-cli/brain/` (>30 days) when disk usage grows.
    - Keep `mise` shims on `PATH` so Antigravity `run_command` subshells resolve project-pinned runtimes without re-initializing interactive shells.
  - *Configuration*:
    - Install global skills under `~/.gemini/config/skills/<skill>/SKILL.md` (symlink on Linux/macOS; real directory copy on Windows so Go's `os.ReadDir` does not skip NTFS junctions/reparse points) or workspace skills under `<repo>/.agents/skills/<skill>/SKILL.md` — note that Antigravity's global `~/.gemini/config/skills/` directory scan does not expand a standalone `~/.gemini/config/skills.json` manifest in place of skill subdirectories.
    - Use **Streamable HTTP** (`"url": "https://.../mcp"`) or Stdio (`command`/`args`) in `mcp_config.json` — legacy `"type": "sse"` and `"serverUrl"` are deprecated/unsupported (bridge SSE-only servers with `mcp-remote`).
    - Align theme (`colorScheme` in `~/.gemini/antigravity-cli/settings.json`) with terminal/editor theme; pair with `herdr integration install antigravity-cli` and Topgrade's native `antigravity_cli` (`agy update`) / `antigravity` steps; validate plugins with `agy plugin validate <dir> --strict`.
  - *Security*:
    - Enforce `0600` on `~/.gemini/oauth_creds.json` and `~/.gemini/config/mcp_config.json`.
    - Scope `trustedWorkspaces` in `~/.gemini/antigravity-cli/settings.json` to dedicated project roots (e.g. `~/repos`), never `/` or `$HOME`.
    - Keep Antigravity's terminal sandbox (`agy --sandbox`) enabled on untrusted repositories and gate `allowNonWorkspaceAccess` to trusted host-wide workflows (such as `system-optimizer`).
### Terminal Workspace & Agent Multiplexer (`herdr` `0.9.5+`)
- **Configuration**: `${HERDR_CONFIG_PATH:-~/.config/herdr/config.toml}` (Linux/macOS) or `%APPDATA%\herdr\config.toml` (Windows).
- **Runtime State & Sockets**:
  - *Linux/macOS*: `~/.config/herdr/` (`session.json`, `session-snapshots/`, `herdr.sock`, `herdr-client.sock`, `herdr.log`, `herdr-server.log`, `herdr-client.log`), `~/.local/state/herdr/` (`agent-detection/`, `client-shell/`), `~/.herdr/worktrees` *(there is no `~/.herdr/packages`)*.
  - *Windows*: `%APPDATA%\herdr\` (`session.json`, `session-snapshots/`, `herdr.sock`, `herdr-server.log`) and `~/.herdr/worktrees`.
- **Mise & Pi Workspace Synergy**:
  - Configure `[terminal] shell_mode` (`"auto" | "login" | "non_login"`) so pane shells consistently load `mise` shims/activations, and leave `default_shell = ""` on Linux/macOS to honor `$SHELL` (use `"pwsh"` on Windows).
  - Run `herdr integration status` / `herdr integration install <agent>` (`pi`, `claude`, `codex`, etc.) and set `[session] resume_agents_on_restore = true` (`startup_per_agent_delay_ms = 100`) so Herdr automatically resumes agent conversations across server restarts.
- **Triad Tuning**:
  - *Performance*:
    - Bound per-pane memory on Low/Medium RAM hosts with `[advanced] scrollback_limit_bytes = 10000000` (10 MB per pane).
    - Rotate/truncate oversized `herdr-server.log` and `herdr-client.log`.
    - Check `herdr status` for `update.restart_needed` / `server_binary_stale` and use **`herdr update --handoff`** for zero-downtime live session handoffs (instead of `herdr server stop` before updates).
  - *Configuration*:
    - Validate before reloading: **`herdr config check`** then **`herdr server reload-config`** (run `herdr --default-config` to inspect schema).
    - Theme synchronization: `[theme] auto_switch = true` (`dark_name` / `light_name`) or `name = "<inferred>"`.
    - UI & remote ergonomics: `[ui] show_agent_labels_on_pane_borders = true`, `status_indicators = "symbols"`, `host_cursor = "auto"`, `[ui.toast] delivery = "system"` (valid: `"off"|"herdr"|"terminal"|"system"`), `[terminal] new_cwd = "follow"`, `kitty_graphics = true`, `[remote] manage_ssh_config = true`.
  - *Security*: Enforce `0600` permissions on `config.toml`, `herdr.sock`, and `herdr-client.sock` (`0700` on workspace dirs); never expose Herdr sockets externally without TLS/SSH tunneling; isolate worker panes in Git worktrees.

### Python & UV Package/Runtime Manager (`uv` `0.13+` & `python` `3.13–3.15+`)
- **Configuration**: `~/.config/uv/uv.toml` (`%APPDATA%\uv\uv.toml`, or `$UV_CONFIG_FILE`), `~/.config/pip/pip.conf` (`%APPDATA%\pip\pip.ini`).
- **Triad Tuning**:
  - *Performance*: Enable `compile-bytecode = true` (`UV_COMPILE_BYTECODE=1`) for faster app startups, tune `link-mode` (`UV_LINK_MODE`), prune unused cache artifacts with `uv cache prune`, and upgrade installed CLI tools with `uv tool upgrade --all` (disable Topgrade's `"uv"` step if `uv` itself is managed by `mise`). On Python `3.15+`, evaluate `-X lazy_imports` (`PYTHON_LAZY_IMPORTS`), free-threaded builds (`sys._is_gil_enabled()`), experimental JIT (`sys._jit`), and Linux `-X perf` / `-X perf_jit` (avoid deprecated `-b`).
  - *Configuration*: Centralize CLI tools under `uv tool` / `mise`, and pair with `python.uv_venv_auto = "source"` in `mise`.
  - *Security*:
    - Protect `mise`/`pyenv` Python from accidental global package pollution: set `PIP_REQUIRE_VIRTUALENV=true` and `[global] require-virtualenv = true` in `pip.conf`.
    - Set `PYTHONSAFEPATH=1` (`-P`, prevents CWD `sys.path` hijacking), store `PYTHON_HISTORY` in `~/.local/state/python_history` with `0600` permissions, use `exclude-newer` cooldowns in `uv.toml`, and run `uv audit` for vulnerability checks.

### File Synchronization (`syncthing` `v2.0+` / `v2.1.7`)
- **Configuration & Data (v2.0+ SQLite Architecture)**:
  - Resolve active paths via **`syncthing paths`** (legacy `-home`/`-paths`/`-logfile`/`-no-browser` single-dash flags were removed in v2.0; use subcommands `syncthing serve`, `syncthing paths`, `syncthing cli` and GNU flags `-C`/`--config`, `-D`/`--data`, `-H`/`--home`).
  - Fresh Linux v2 installs store both `config.xml` and SQLite `index-v2/` (`folder.*.db`) under `${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/` unless `${XDG_CONFIG_HOME:-$HOME/.config}/syncthing/config.xml` already exists.
- **Triad Tuning**:
  - *Performance*: Syncthing v2 replaced LevelDB (`index-v0.14.0.db`) and v1 `databaseTuning` with SQLite (`index-v2/`). Check for leftover `index-v0.14.0.db` directories after upgrading to reclaim disk space, and tune `syncthing serve` `--db-maintenance-interval=8h` / `--db-delete-retention-interval=10920h` if needed.
  - *Configuration*: Manage via user service `systemctl --user enable --now syncthing.service`.
  - *Security*: Enforce `tls="true"` on `<gui>`, bind to `127.0.0.1:8384` (never `0.0.0.0` without reverse-proxy auth), require `<user>` + bcrypt `<password>`, and disable global discovery/relays (`<relaysEnabled>false`) on LAN-only setups.

### Arch Package Management (`pacman` `7.1+`, `makepkg`, `yay` `13.1+`, `paccache`)
- **Configuration Layers**:
  - `/etc/pacman.conf` (root-owned — elevated apply script only)
  - `makepkg` precedence: `/etc/makepkg.conf` → `/etc/makepkg.conf.d/*.conf` (`rust.conf`, etc.) → `${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf` (prefer user config or `/etc/makepkg.conf.d/99-system-optimizer.conf` to avoid `.pacnew` conflicts)
  - `~/.config/yay/config.json` (manage via `yay --save`) and `/etc/conf.d/pacman-contrib` (`PACCACHE_ARGS`)
- **Triad Tuning**:
  - *Performance*: `ParallelDownloads = 5` and `COMPRESSZST=(zstd -c -T0 -)` are already Arch upstream defaults. Set `MAKEFLAGS="-j$(nproc)"` and consider `!debug` in `OPTIONS` (avoids multi-GB `-debug` AUR packages and SSD wear). Enable `paccache.timer` with `PACCACHE_ARGS="-k2"` in `/etc/conf.d/pacman-contrib`, and prune uninstalled packages (`paccache -ruk0`) plus `~/.cache/yay`.
  - *Configuration*: Use `yay --save --cleanAfter --removemake --diffmenu --pgpfetch --batchinstall`.
  - *Security*: Audit `/etc/pacman.conf` for Pacman 7's **`DownloadUser = alpm`** privilege-drop + Landlock/seccomp sandboxing; flag any **`DisableSandbox`**, **`DisableSandboxFilesystem`**, or **`DisableSandboxSyscalls`**; ensure `SigLevel = Required DatabaseOptional` globally and no `[repo]` sets `Never`/`TrustAll`; avoid `"sudoloop": true` in `yay` during untrusted AUR builds.

### Rootless Containers & TUI (`podman` `6.2+`, `lazydocker` `0.25+`, `docker`)
- **Configuration**: `~/.config/containers/containers.conf` (and `containers.conf.d/*.conf`), `~/.config/containers/systemd/*.{container,pod,volume,network}`, `~/.config/lazydocker/config.yml`.
- **Triad Tuning**:
  - *Performance*: Place keys in the exact `containers.conf(5)` tables (`[containers]` `pids_limit = 2048`, `log_size_max = 10485760` — note `log_max_size` is ignored — `log_driver = "journald"`; `[engine]` `runtime = "crun"`, `cgroup_manager = "systemd"`, `events_logger = "journald"`, `image_parallel_copies`).
  - *Configuration*:
    - **Podman 6 networking**: `slirp4netns` was removed — use `[network]` `default_rootless_network_cmd = "pasta"` (`passt` package) and `network_backend = "netavark"`.
    - **Quadlet units**: Replace deprecated `podman generate systemd` with Quadlet units under `~/.config/containers/systemd/`.
    - **LazyDocker + Podman**: Enable `systemctl --user enable --now podman.socket`, export `DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"`, set `commandTemplates.dockerCompose: "podman compose"`, and use `gui.theme.optionsTextColor` (not deprecated `optionsColor`).
    - **Docker**: BuildKit (`buildx`) is default since Docker 23+ (no `DOCKER_BUILDKIT=1` needed); detect `podman-docker` (`/etc/containers/nodocker`) before auditing `daemon.json` (`~/.config/docker/daemon.json` for rootless).
  - *Security*: Rootless user namespaces (`crun` + `pasta`), bounded `pids_limit` and `log_size_max`, and no privileged root daemon socket exposure.

### System Monitors & Embedded Database (`btop` `1.4+`, `htop` `3.5+`, `sqlite3` `3.54+`)
- **`btop` (`~/.config/btop/btop.conf`)**: Set `update_ms = 2000`, `proc_tree`, `shown_boxes` (including `gpu0` in `btop 1.4+`), and `color_theme` dynamically inferred from terminal/editor (never hardcoded).
- **`htop` (`~/.config/htop/htoprc`)**: Close `htop` before editing (`htop` overwrites `htoprc` on exit). Set `delay=20` (tenths of a second = 2.0s parity with `btop` `update_ms = 2000`), `show_cpu_frequency=1`, `show_cpu_temperature=1`, `hide_userland_threads=1` on high-core hosts, and `tree_view=1`.
- **`sqlite3` (`~/.sqliterc`)**:
  - **NEVER set `PRAGMA journal_mode=WAL` in `~/.sqliterc`**: it mutates the on-disk header of every opened database, fails on read-only DBs, leaves `-wal`/`-shm` sidecars, and prints `wal` to stdout.
  - Wrap interactive PRAGMAs in `.output /dev/null` ... `.output stdout` so `sqlite3` scripts/version probes are not polluted:
    ```sql
    .output /dev/null
    PRAGMA foreign_keys = ON;
    PRAGMA busy_timeout = 5000;
    PRAGMA temp_store = MEMORY;
    PRAGMA cache_size = -16000;
    .output stdout
    .headers on
    .mode box
    .nullvalue 'NULL'
    ```

### Encrypted DNS Resolver (`controld` / `ctrld` `v1.5+`)
- **Configuration**: `/etc/controld/ctrld.toml` (root-owned, `0600` — inspect and apply only via elevated privileges per Safety Contract #4).
- **Triad Tuning**:
  - *Performance*: Set `[service]` `cache_enable = true`, `cache_size = 4096`, and use **`type = "doh3"`** (`--proto doh3`, DNS-over-HTTP/3 QUIC on `443/udp`) as primary transport with `"doh"` failover (avoids `853/udp` DoQ firewall blocks).
  - *Configuration*: `[listener.0]` `ip = "127.0.0.1"`, `port = 53`, `restricted = true`; `[service]` `log_level = "notice"`, `intercept_mode` (`"off"|"dns"|"hard"`).
  - *Security*: Disable unnecessary LAN discovery (`discover_mdns = false`, `discover_arp = false`, `discover_dhcp = false`, `discover_ptr = false`) and keep `0600 root:root` on `/etc/controld/ctrld.toml`.

### Web Browsers (`firefox` / `librewolf` `137+`)
- **Hardware Video Decoding (Linux VA-API)**: In Firefox/LibreWolf `137+`, `media.ffmpeg.vaapi.enabled` was removed — enable **`media.hardware-video-decoding.force-enabled`** (in `about:config` / `user.js`) instead. Keep `gfx.webrender.all = true`, strict Enhanced Tracking Protection / uBlock Origin, and RAM-tier tab-discarding policies.
---
## 5.2 Tier 2: Broader Cross-Tool Workstation Synergies

| Synergy Pair / Trio | Architectural Benefit & Triad Rationale | Configuration Integration Pattern |
|---|---|---|
| **`lazygit` + `neovim` + `bat`** | Configure lazygit to use `os.editPreset: "nvim-remote"` to prevent nested editor spawns, and `git.diffRenderers` with `bat --color=always --style=changes,numbers` for fast syntax-highlighted diffs. | In `lazygit/config.yml`: set `os.editPreset: "nvim-remote"`, `gui.nerdFontsVersion: "3"`, and `git.diffRenderers: [{ colorArg: always, command: "bat --color=always --style=changes,numbers" }]`. |
| **`ripgrep` / `fd` + `fzf` + `bat`** | Wire `fd --strip-cwd-prefix` or `rg` as the `.gitignore`-aware file generator for `fzf` (`FZF_DEFAULT_COMMAND`), with `bat --theme=auto` rendering line-numbered previews. | Export `FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --exclude .git'` (or `rg --files --hidden --glob "!.git/*"`), and `FZF_DEFAULT_OPTS="--info=inline-right --preview 'bat --style=numbers --color=always --line-range :300 {}'"`. |
| **`mpv` + `yt-dlp` + GPU HWDEC** | Stream web video directly to `mpv` via `yt-dlp` (`yt-dlp-ejs`), using zero-copy hardware decoding (`hwdec=auto-safe`) and `vo=gpu-next`, bypassing heavy browser CPU/RAM consumption. | In `mpv.conf`: `vo=gpu-next`, `profile=high-quality`, `hwdec=auto-safe`, `tone-mapping=auto`, `target-colorspace-hint=auto` (`yes` when HDR mode active), `ytdl-format="bestvideo[height<=?1080]+bestaudio/best"`. |
| **`winget` + `wsl` + `windows-terminal`** | Align WinGet download concurrency, WSL2 mirrored networking / `[experimental] autoMemoryReclaim=dropcache`, and Windows Terminal AtlasEngine (default in 1.18+). | In `settings.json`: `disableAnimations=true`; in `.wslconfig`: `networkingMode=mirrored`, `[experimental] autoMemoryReclaim=dropcache`, `memory=4GB`/`8GB` (no `sparseVhd`); in WinGet: `downloader=default`, `source.autoUpdateIntervalInMinutes=120`. |
| **`gh` + `git` + `lazygit`** | Register GitHub CLI as the Git credential helper for HTTPS remotes (`gh auth setup-git`) or use SSH keys, and integrate PR/issue reviews in the terminal UI. | Run `gh auth setup-git` for HTTPS remotes; configure `lazygit` `git.diffRenderers` with `bat`; configure `gh` `pager: bat --color=always --style=plain`. |
| **`gh` + `topgrade`** | Coordinated maintenance and supply-chain auditing of third-party GitHub CLI extensions during system upgrades. | Rely on Topgrade 17+'s native `github_cli_extensions` step (ensure `"github_cli_extensions"` is not in `disable`). |

### Detailed Implementation Specifications

#### 1. lazygit + neovim + bat
- **Nested Editor Elimination**: Spawning a standard `nvim` inside `lazygit` within an interactive terminal creates nested process trees, cursor fighting, terminal redraw latency, and terminal freeze hazards. Setting `os.editPreset: "nvim-remote"` (or `os.edit` using `{{filename}}`) dispatches file edits directly into the parent/sibling Neovim RPC server (`$NVIM`) as a new tab.
- **Dependency-Free Syntax Paging**: Routing `lazygit` diffs through `git.diffRenderers` (`command: bat --color=always --style=changes,numbers`, `colorArg: always`) delivers immediate 24-bit syntax highlighting, git modification markers, and line numbering.

#### 2. ripgrep / fd + fzf + bat
- **Multithreaded & `.gitignore`-Aware Search**: `fzf`'s built-in `--walker` is already multithreaded when `FZF_DEFAULT_COMMAND` is unset. Wiring `fd --type f --strip-cwd-prefix --hidden --exclude .git` or `rg --files --hidden --glob "!.git/*"` adds automatic `.gitignore` filtering while letting `rg`/`fd` auto-manage their own worker threads and heuristics (without `--threads` or `--mmap`).
- **Syntax Preview Clamping**: `bat` previews are clamped via `--line-range :500` to prevent memory exhaustion when browsing large minified or generated files, while providing rich, theme-coordinated syntax highlighting for source files.

#### 3. mpv + yt-dlp + GPU HWDEC
- **Chromium/Browser Overhead Bypass**: Playing 1080p60 or 4K web video inside a modern browser (Chrome, Edge, Brave) consumes 1.5–3.5 GiB of RAM, incurs heavy JavaScript runtime overhead, and triggers CPU-intensive software VP9/AV1 decoding on constrained systems.
- **Hardware-Accelerated Stream Passthrough**: Piping web video URLs directly into `mpv` (`mpv "https://..."`) delegates extraction to `yt-dlp` (`yt-dlp-ejs` + JS runtime) and video decoding to the host GPU ASIC via `vo=gpu-next`, `profile=high-quality`, and zero-copy `hwdec=auto-safe`. This drops CPU utilization from 40–80% to <5% and reduces memory footprint to under 150 MiB.
- **Color Pipeline**: Default `tone-mapping=auto` (`hdr-compute-peak=auto`) and `target-colorspace-hint=auto` (or `yes` when HDR display mode is active) deliver reference-grade presentation without washing out SDR panels.

#### 4. winget + wsl + windows-terminal
- **Windows Subsystem Alignment**: WSL2 virtual machines default to consuming up to 50% of total host RAM with memory caches lingering inside the Linux kernel. Configuring `autoMemoryReclaim=dropcache` automatically returns Linux file cache pages back to Windows host memory.
- **Network Parity**: `networkingMode=mirrored` enables sub-millisecond localhost networking parity between Windows and WSL2, while `firewall=true` propagates Windows Defender Firewall rules inside Linux containers and services.
- **Terminal Rendering**: Windows Terminal 1.18+ enables the DirectX Atlas text rendering engine by default; setting `"disableAnimations": true` removes tab/pane transition lag.
- **WinGet Concurrency**: Setting WinGet downloaders to `default` (WinINet) bypasses Delivery Optimization freezes and coordinates seamless updates across host tools.

#### 5. gh + git + lazygit + topgrade
- **Zero-Friction Git Credential Delegation**: Running `gh auth setup-git` links the GitHub CLI authentication state with Git's internal credential architecture (`!gh auth git-credential`). This eliminates personal access token copy-pasting and credential helper misconfigurations across both CLI `git` and terminal TUIs like `lazygit`.
- **Fast Syntax-Highlighted PR Reviews**: Setting `gh config set pager "bat --color=always --style=plain"` invokes `bat` directly during `gh pr diff` and `gh pr view`, providing instant 24-bit colorway syntax highlighting without requiring third-party pager setup.
- **Automated Extension Maintenance**: Third-party GitHub CLI extensions (`gh-dash`, `gh-poi`) are updated automatically by Topgrade 17+'s native `github_cli_extensions` step, ensuring patches are applied consistently without manual `[commands]` hooks.

## 6. Mandatory Pre-Modification Backup & Rollback Protocol

Every file edited or overwritten by `system-optimizer` MUST be backed up using `scripts/backup-config.sh` before any changes are written to disk. Script paths are relative to the skill folder (for example `~/.claude/skills/system-optimizer/` or `~/.pi/agent/skills/system-optimizer/`).

### 1. Dual-Location Backup Architecture
1. **Centralized Vault**: `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak`
   - Accompanied by `<filename>.<timestamp>.bak.meta` containing:
     - `Original-Path`: Full absolute path of source configuration.
     - `Timestamp`: Execution timestamp (`YYYYMMDD-HHMMSS-NNNNNNNNN`, with a numeric suffix if two backups collide).
     - `SHA256`: Checksum of the pre-modification state.
     - `Size` & `Permissions`: File size in bytes and permissions.
     - `Description`: Rationale for modification.
2. **In-Place Adjacent Backup**: `<config_path>.bak.<timestamp>`
   - Created in the parent directory when user write permissions allow (e.g. `settings.json.bak.20260905-143000`), and automatically skipped inside scanned/drop-in config directories (`/nvim/`, `*.d/`, `/systemd/`) or when `--no-in-place` is passed so tools do not accidentally load `.bak` files.
   - A plain copy with no `.meta`: `--restore` only accepts central-vault backups (it verifies their SHA256), so restore an in-place copy with `cp`.

### 2. Backup CLI Commands
- Create backup (single file or multi-file batch):
  ```bash
  scripts/backup-config.sh [--no-in-place] <config-path> [config-path2 ...] <target> "Reason"
  ```
- List backups:
  ```bash
  scripts/backup-config.sh --list [target]
  ```
- Diff backup against current:
  ```bash
  scripts/backup-config.sh --diff <backup-file> [current-file]
  ```
- Restore / Rollback:
  ```bash
  scripts/backup-config.sh --restore <backup-file> [dest-file]
  ```

---

## 7. Persistent Memory Specifications

### Per-Target Memory Schema (`~/.config/system-optimizer/<target>/MEMORY.md`)

```markdown
# Memory: <target_name>

## 1. Metadata
- **Target**: <name>
- **Category**: <system|package-manager|terminal|shell|subsystem|tool>
- **Installed Version**: <version_or_active_state>
- **Config Path**: <path>
- **Last Optimized**: <timestamp>

## 2. Hardware Snapshot at Optimization
- **CPU**: <model> (<cores> threads, Power/Governor: <power_scheme>)
- **RAM**: <total_gb> GiB (Tier: <low|medium|high>, Compression: <status>)
- **Storage**: <SSD/NVMe|HDD> (Root: <drive>)
- **GPU**: <gpu_info>

## 3. Upstream Findings & Hardening Standards
- **Upstream Source / Spec**: <url_or_man_page>
- **Latest Version / Standard**: <version_or_standard>
- **Notable Directives**:
  - <directive_1>
  - <directive_2>

## 4. Applied Triad Optimizations (Performance, Config, Security)
- **Performance Improvements**:
  - `<setting>`: <explanation (concurrency, memory bounds, hardware acceleration, launch latency)>
- **Configuration Improvements**:
  - `<setting>`: <explanation (defaults, integrations, obsolete pruning)>
- **Security Hardening**:
  - `<setting>`: <explanation (least privilege, policies, attack surface reduction)>

## 5. Backups & Rollback Ledger
- **Active Pre-Modification Backup**: `<path_to_backup_file>`
- **SHA256 Checksum**: `<hash>`
- **Timestamp**: `<YYYYMMDD-HHMMSS>`
- **In-Place Backup**: `<in_place_bak_path>`
- **Rollback Command**: `scripts/backup-config.sh --restore <backup-file>`

## 6. Verification & Health Checks
- Syntax & validation output: `<command_output>`
- Dry-run / status check: `<status>`

## 7. History & Subsequent Run Notes
- **[<timestamp>]**: Triad optimization completed.
```

---

## 8. Master Memory Schema (`~/.config/system-optimizer/MASTER_MEMORY.md`)

```markdown
# Master System & Tool Optimization Memory

## 1. System Hardware & OS Baseline
- **OS**: Microsoft Windows 11 Pro (Build 26200) / Linux Kernel
- **CPU**: Model, Cores, Threads, Power Scheme / Scaling Governor
- **RAM Tier**: Low / Medium / High, Memory Compression status, Pagefile / Swap
- **GPU**: Driver, Model, VRAM, Direct3D / Vulkan / VA-API profile
- **Storage**: NVMe / SSD, TRIM status, NTFS volumes / mount options

## 2. System Security Baseline
- **Firewall**: Windows Defender Firewall profiles (Domain/Private/Public) / ufw
- **Antivirus & Exploit Protection**: RealTimeProtection, PUAProtection, TamperProtection
- **Policy Integrity**: ExecutionPolicy, UAC level
- **Network Exposure**: Count and list of open listening TCP sockets
- **Package Integrity**: WinGet hash verification active / pacman SigLevel

## 3. Registered Targets Matrix
| Target | Category | Version / State | Triad Status (Perf / Config / Sec) | Last Updated |
| :--- | :--- | :--- | :--- | :--- |
| `storage` | System Core | TRIM Enabled | OPTIMIZED (NTFS ReTrim / 8.3 Names) | 2026-09-07 |
| `defender` | Security | PUA Active | OPTIMIZED (Block Inbound / PUA Guard) | 2026-09-07 |
| `winget` | Package Manager | 1.30.x | OPTIMIZED (120m Sync / WinINet / No Telemetry)| 2026-09-07 |
| `windows-terminal` | Terminal | 1.24.x | OPTIMIZED (Atlas Engine / No Anim / pwsh) | 2026-09-07 |
| `wsl` | Subsystem | 2.6.x | OPTIMIZED (8GB RAM / Mirrored Net / dropcache)| 2026-09-07 |
| `pwsh` | Shell | 7.6.5 | OPTIMIZED (PSReadLine Predict / RemoteSigned)| 2026-09-07 |
| `topgrade` | Maintenance | 17.16.x | OPTIMIZED (Cross-Package Orchestration) | 2026-09-07 |
| `mise` | Runtime Manager | 2026.x | OPTIMIZED (env_cache / jobs / supply-chain / topgrade) | 2026-09-07 |
| `mpv` | Media | 0.41.0 | OPTIMIZED (gpu-next / D3D11 / NVDEC / HDR) | 2026-09-07 |
| `git` | Developer Tool | 2.56.x | OPTIMIZED (manyFiles / zdiff3 / fscache[Win]) | 2026-09-07 |

## 4. Cross-System & Cross-Tool Synergies
- **Unified Workstation Orchestration (`topgrade` + `mise`)**: Coordinates host OS packages (`pacman`, `yay`, `winget`) with user polyglot runtimes (`node`, `python`, `rust`, `uv`); binds parallel jobs to hardware CPU threads (`nproc`); prevents dual-update conflicts by disabling redundant standalone updaters (`disable = ["uv", "cargo", "pi"]`) in topgrade; executes post-update `mise reshim` to keep binary shims synchronized; auto-prunes obsolete tool versions and caches via `cleanup = true` and `mise prune`.
- **Terminal & Shell Workflow (`windows-terminal` + `pwsh` + `starship` + `fzf`/`zoxide`)**: GPU-accelerated Atlas rendering, PSReadLine history prediction, static prompt generation.
- **Virtualization & Subsystem Integration (`wsl` + host firewall)**: Mirrored networking shares Windows localhost and Windows Defender Firewall secures WSL traffic (compact `ext4.vhdx` offline when needed; avoid `sparseVhd=true`).
- **Media & Hardware Acceleration (`mpv` + Discrete GPU)**: D3D11 NVDEC / hardware video decode, HDR passthrough, smooth motion interpolation.

## 5. Global Resource & Security Budget
- **CPU Saturation Guard**: Prevent simultaneous WSL compilation and host transcoding.
- **RAM Threshold**: Bound WSL VM memory to 50% host RAM (8GB); enable Windows Memory Compression.
- **Storage Hygiene**: Package cache retention limits, SSD weekly TRIM maintenance.
- **Security Posture**: Default-deny incoming firewall, PUA protection active, RemoteSigned script execution.

## 6. Cumulative Integration History Log
- [<timestamp>]: Optimization run details.
```


## 9. Invocation Examples (moved from SKILL.md)

```bash
# Auto-detection mode (no arguments provided, detects OS and installed tools):
system-optimizer

# Windows equivalent packages & tools:
system-optimizer winget windows-terminal wsl pwsh
system-optimizer storage defender powertoys
system-optimizer topgrade mpv rustdesk

# Specific system domain(s):
system-optimizer system           # Core OS (storage/TRIM, memory, cpu power, boot)
system-optimizer security         # Security posture, firewall, antivirus/defender, SSH
system-optimizer storage          # NVMe/SSD TRIM, volume health, filesystem performance

# Specific tool(s) or package(s):
system-optimizer pwsh             # PowerShell 7 profile, PSReadLine & predictions
system-optimizer windows-terminal # Windows Terminal GPU engine, profiles, styling
system-optimizer wsl              # WSL 2 .wslconfig, mirrored networking, auto-memory
system-optimizer winget           # Windows Package Manager sync interval, telemetry, downloader
system-optimizer topgrade         # Topgrade cross-package update coordinator
system-optimizer mise             # Mise polyglot toolchain, env caching & supply chain
system-optimizer mise topgrade    # Unified workstation maintenance & runtime orchestration
system-optimizer mise neovim      # Polyglot LSP, formatter runtime & Mason de-duplication
system-optimizer mise starship    # Zero-latency prompt integration, native [mise] module & shell hooks
system-optimizer mise cargo topgrade # Rust pre-compiled binstall vs compilation de-duplication
system-optimizer mise pi herdr    # AI coding agent workspace toolchain & non-interactive PATH isolation
system-optimizer antigravity      # Google Antigravity (agy) settings, global skills, MCP config & credentials
system-optimizer mise antigravity herdr # Antigravity + Mise PATH shims + Herdr integration hook synergy
system-optimizer lazygit neovim bat    # Remote tab editing (nvim --server) & bat diff pager
system-optimizer ripgrep fzf bat       # rg search generator (FZF_DEFAULT_COMMAND) & bat syntax previews
system-optimizer mpv yt-dlp            # Web video hardware streaming (GPU HWDEC) bypassing browser CPU/RAM
system-optimizer winget wsl windows-terminal # WinGet concurrency, WSL2 mirrored/dropcache & Terminal Atlas GPU
system-optimizer podman lazydocker     # Rootless container management & TUI dashboard
system-optimizer htop btop             # Resource monitoring & hardware thread inspection
system-optimizer mpv              # mpv GPU-next, D3D11/NVDEC, HDR passthrough
system-optimizer pi               # Pi coding agent harness, sessions & settings optimization
system-optimizer controld         # Control D encrypted DNS resolver daemon & cache
system-optimizer rustdesk         # RustDesk remote desktop, hardware video codecs & access control
system-optimizer git              # Git workflow & performance (manyFiles, zdiff3, rerere, Windows fscache)
system-optimizer herdr            # Herdr AI agent terminal workspace manager, sessions & sockets
system-optimizer gh                   # GitHub CLI credentials, pager, default protocol & extensions
system-optimizer gh git lazygit       # GitHub CLI credential helper & PR/review workflow synergy

# Linux system domain(s) & packages (when running on Linux):
system-optimizer pacman yay kde-plasma

# Comprehensive full system run:
system-optimizer full
```

## 10. Full Optimization Tier Details and Cross-Tool Synergies (moved from SKILL.md)

1. **Tier 1: System Core & OS Baseline**:
   - NVMe/SSD TRIM verification (`fsutil DisableDeleteNotify = 0`), volume health checks, and 8.3 short name deactivation on secondary data drives.
   - Memory Compression activation (`Enable-MMAgent -mc` in user-run elevated PowerShell, or Linux zram) to prevent SSD paging lockups.
   - Power plan alignment (`powercfg`) ensuring maximum responsiveness on AC.
   - Startup application audit (pruning unneeded background updaters and telemetry daemons).

2. **Tier 2: System Security Hardening**:
   - Windows Defender Firewall profile enforcement (Domain/Private/Public active with default BlockInbound).
   - Antivirus & Exploit Guard hardening: Enable Potentially Unwanted Application (PUA) Protection (`Set-MpPreference -PUAProtection 1` — user-run elevated PowerShell).
   - PowerShell script execution hardening: Enforce `ExecutionPolicy RemoteSigned` for `CurrentUser`.
   - Package manager supply chain security: Enforce `winget` hash verification and malware scan overrides remaining disabled.

3. **Tier 3: Subsystems & Package Orchestration**:
   - **`winget`**: Configure `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_*\LocalState\settings.json` with 2-hour source sync (`autoUpdateIntervalInMinutes: 120`), direct WinINet downloader, and telemetry disabled.
   - **`wsl`**: Configure `~/.wslconfig` with memory bounding (50% host RAM / 8GB), `[experimental] autoMemoryReclaim=dropcache`, `networkingMode=mirrored`, and `[wsl2] dnsTunneling=true` (default). Do NOT enable `sparseVhd=true` (ext4 corruption risk).
   - **`mise`**: Configure `~/.config/mise/config.toml` (plus `conf.d/*.toml`, or `%APPDATA%\mise\config.toml` on Windows): thread concurrency (`jobs = $(nproc)`), environment caching (`env_cache = true`, `env_cache_ttl = "1h"`), version pinning (`pin = true`), pre-compiled Rust binaries (`cargo.binstall = true`), storage hygiene (`cache_prune_age = "7d"`, `download_cache = true`, `download_cache_max_size = "2GiB"`, `upgrade.auto_prune = true`), native Windows PE shims (`windows_shim_mode = "exe"`), and supply-chain verification (`minimum_release_age`, `aqua.slsa = true`, `aqua.cosign = true`, `aqua.minisign = true`, `github_attestations = true`, `npm.provenance = true`, `node.verify = true`).
   - **`cargo`**: Configure `~/.cargo/config.toml` (flag deprecated extensionless `~/.cargo/config`) with `net.git-fetch-with-cli = true` and `[profile.release]` tuning (`opt-level = 3`, `lto = "thin"`, `codegen-units = 16`). Omit redundant `build.jobs`, `protocol = "sparse"`, global `target-cpu=native`, and `-fuse-ld=lld` on Linux `x86_64` (`rust-lld` is default); prune `~/.cargo/registry/cache` via `cargo-cache`/`cargo-sweep`; delegate Rust CLI tools to `mise` (`cargo.binstall = true`).
   - **`uv` & `python`**: Configure `~/.config/uv/uv.toml` (`compile-bytecode = true`, `exclude-newer` cooldowns, `uv cache prune`, `uv audit`) and protect `mise`/`pyenv` Python with `PIP_REQUIRE_VIRTUALENV=true` (`pip.conf`), `PYTHONSAFEPATH=1`, and `PYTHON_HISTORY` (`0600`).
   - **`pacman`, `makepkg`, `yay`, & `paccache`**: Audit `/etc/pacman.conf` for `DownloadUser = alpm`, sandbox checks (`DisableSandbox*`), and `SigLevel = Required DatabaseOptional`; place user `MAKEFLAGS="-j$(nproc)"` and `!debug` in `~/.config/pacman/makepkg.conf` or `/etc/makepkg.conf.d/`; configure `yay --save` (avoid `sudoloop: true`); enable `paccache.timer` (`PACCACHE_ARGS="-k2"`).
   - **`podman` & `lazydocker`**: Configure `containers.conf` (`[network] default_rootless_network_cmd = "pasta"`, `[containers]` `pids_limit`/`log_size_max`, `[engine]` `runtime = "crun"`), Quadlet units in `~/.config/containers/systemd/`, and `podman.socket` + `commandTemplates.dockerCompose: "podman compose"` in `lazydocker/config.yml`.
   - **`topgrade`**: Configure `%APPDATA%\topgrade.toml` / `~/.config/topgrade.toml` (+ `topgrade.d/*.toml`) to coordinate OS packages, `wsl`, `git`, `github_cli_extensions`, and `mise`, with `[misc] allow_root = false`, `cleanup = true`, `notify_end = "on_failure"`, `[windows]` `accept_all_updates`/`winget_use_sudo`, `[git] fallback_to_fetch_default = true`, `[mise] bump = true`, `disable = ["uv", "cargo", "pi"]`, and `[post_commands]` `"Mise Reshim" = "mise reshim"`.
4. **Terminal, Browser & Shell Environment**:
   - **`windows-terminal`**: AtlasEngine is enabled by default in 1.18+; set `disableAnimations: true`, `copyFormatting: "none"`, default profile set to PowerShell 7, Nerd Font.
   - **`pwsh` (PowerShell 7)**: Configure `$PROFILE` with PSReadLine predictive IntelliSense (`Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView`), deferred module loading, `--print-full-init` cached prompt hooks, and history deduplication.
   - **`bash`**: Sanitize `$PATH`, set safe umask, configure history deduplication, and pre-cache `--print-full-init` prompt hooks.
   - **`firefox` / `librewolf`**: Enable `media.hardware-video-decoding.force-enabled` (137+, replacing removed `media.ffmpeg.vaapi.enabled`), `gfx.webrender.all`, and RAM-tier tab discarding.

5. **Developer, Media, Sync & Monitor Toolchain**:
   - **`neovim` (`nvim`)**: Verify `vim.loader.enable()`, prepend mise shims and append Mason bin on `vim.env.PATH`, migrate LSPs/formatters/linters/DAPs to `mise`, lock `mason.nvim` (`PATH = "append"`, `opts_extend = {}`, `automatic_enable = false` on `mason-lspconfig.nvim`, `opts.servers.<srv>.mason = false`), use native `vim.lsp.config()`/`vim.lsp.enable()`, add async `DirChanged`/`VimEnter` `mise env --json` sync, enforce LazyVim v15/v16+ compatibility (`nvim-treesitter` `main` branch, `v:lua.LazyVim.treesitter.foldexpr()`, `lazydev.nvim`, `ai.copilot-native`/`ai.sidekick`, `crates.nvim` `cmp.enabled = false` with `blink.cmp`, retain `matchit`/`matchparen`), disable `modeline` (`exrc` defaults `false` with `:trust`), and validate with `nvim --headless +q`.
   - **`lazygit`**: Configure `git.autoFetch: false`, `gui.nerdFontsVersion: "3"`, `gui.animateExplosion: false`, `os.editPreset: "nvim-remote"` (or `{{filename}}`), `git.diffRenderers` with `bat --color=always --style=changes,numbers`, and terminal-synchronized theme palette.
   - **`ripgrep` (`rg`) & `fd`**: Configure `RIPGREP_CONFIG_PATH` with `--smart-case`, `--max-columns=300`, `--max-columns-preview`, and ignore globs (`!.git/*`, `!node_modules/*`, `!target/*`) — omit `--mmap` and `--threads`; place `fd` ignore patterns in `~/.config/fd/ignore` and omit `-j`.
   - **`zoxide`**: Configure fast directory jumping (`z`, `zi`), `:`/`;`-delimited `_ZO_EXCLUDE_DIRS`, initialize shell hooks, and prune stale directories.
   - **`eza`**: Define ergonomic aliases (`ls`, `ll`, `la`, `lt`) with `--icons=auto`, binding `--git` strictly to detailed listings; do not pass nonexistent `--no-dereference`.
   - **`bat` & `fzf`**: Set `FZF_DEFAULT_COMMAND` to `fd --type f --strip-cwd-prefix --hidden --exclude .git` (or `rg --files`), enable `fzf --bash`/`--zsh`/`--fish`, use `--info=inline-right`, and configure `bat --theme=auto` (`--theme-dark`/`--theme-light`, validate with `bat --diagnostic`).
   - **`starship`**: Configure `command_timeout = 500`, choose `[mise]` (`disabled = false`, `$symbol`/`$health`) or per-language modules with `mise` `env_cache = true`, and pass `--print-full-init` if caching init output.
   - **`git`**: Configure `feature.manyFiles = true`, `diff.algorithm = histogram`, `merge.conflictStyle = zdiff3`, `branch.sort = -committerdate`, `rerere.enabled = true`, `fetch.prune = true`, `push.autoSetupRemote = true`, `rebase.updateRefs = true`, per-large-repo `core.fsmonitor = true`, and Windows-only `core.fscache = true` / `credential.helper = manager`.
   - **`mpv` & `yt-dlp`**: Configure `vo=gpu-next`, `profile=high-quality`, zero-copy `hwdec=auto-safe`, `tone-mapping=auto`, `target-colorspace-hint=auto` (`yes` when HDR active); in `yt-dlp`, use `yt-dlp-ejs` + `--js-runtimes` + native `-N 4` and warn against global `--downloader aria2c` and global `--impersonate`.
   - **`stremio`**: Inspect `server-settings.json` (`cacheSize`, `btMaxConnections`, P2P speed limits, `transcodeHardwareAccel`, `remoteHttps`), embedded `libmpv` (`mpv-config-location` / `portable_config/mpv.conf` keeping `vo=libmpv`), Flatpak `LIBVA_DRIVER_NAME` forwarding, `0700` `.stremio-server` / `0600` permissions, and loopback-only `11470`/`12470` port exposure.
   - **`pi`**: Honor `$PI_CODING_AGENT_DIR`, enforce `0600` on `auth.json` and `mcp-auth.json`, configure `defaultProjectTrust` (`trust.json`), `defaultTools`/`--exclude-tools`, `cacheWarming: "idle"`, `PI_CACHE_RETENTION=long`, `codemode`, session pruning (>30d), and `mise` shims on `PATH`.
   - **`antigravity` (`agy`)**: Inspect `~/.gemini/antigravity-cli/settings.json`, `~/.gemini/config/{skills/,mcp_config.json,hooks.json,plugins/}`, and `~/.gemini/oauth_creds.json` (`0600`); flag legacy MCP `serverUrl` / `type: sse`; verify `~/.gemini/config/skills/system-optimizer/SKILL.md` global skill discovery (and warn if only `skills.json` is present), `herdr integration install antigravity-cli`, `mise` shims on `PATH`, scoped `trustedWorkspaces`, and stale `brain/` pruning (>30d).
   - **`rustdesk` & `controld`**: Inspect `RustDesk2.toml` (`direct-server`, `approve-mode`, `verification-method`) and GPU encode; configure `/etc/controld/ctrld.toml` (`0600`) with `type = "doh3"` primary + `"doh"` failover and `[service]` `cache_enable = true`.
   - **`herdr`**: Inspect `~/.config/herdr/` (`config.toml`, `session.json`, `herdr.sock`, `herdr-server.log`) and `~/.local/state/herdr/`; validate with `herdr config check` before `herdr server reload-config`; use `herdr update --handoff`; run `herdr integration status` with `resume_agents_on_restore = true`; keep `default_shell = ""` (`$SHELL`) on Linux/macOS (`"pwsh"` on Windows), `[terminal] shell_mode`, `[advanced] scrollback_limit_bytes`, `0600` on sockets/config.
   - **`syncthing`**: Use Syncthing v2 `syncthing paths` / `syncthing serve` (`index-v2/` SQLite), GUI `tls="true"` on `127.0.0.1`, and `systemctl --user enable --now syncthing.service`.
   - **`btop`, `htop`, & `sqlite3`**: Align `btop` `update_ms = 2000` (with `gpu0` and inferred theme) and `htop` `delay=20` (close `htop` before editing); write a safe `~/.sqliterc` wrapped in `.output /dev/null` ... `.output stdout` without `PRAGMA journal_mode=WAL`.
   - **`gh` (GitHub CLI)**: Use YAML syntax (`git_protocol: ssh`, `pager: "bat --color=always --style=plain"`, `prompt: enabled`, `telemetry: disabled`, `expiring_credentials: enabled`), HTTPS `gh auth setup-git`, OS keyring or `0600` `hosts.yml`, active extensions (`gh-dash`, `gh-poi`), and native Topgrade `github_cli_extensions`.
   - **`powertoys`**: Disable unused background utility modules to reclaim RAM and thread handles.

6. **Cross-Tool Synergies**:
   - Establish seamless pipelines between tools:
     - `herdr` + `pi` + `antigravity` + `mise` + `pwsh`/`bash`: Autonomous AI coding agent toolchain inheritance, `herdr integration status` + `resume_agents_on_restore = true`, worktree branch isolation, and `0600` socket/auth hardening.
     - `lazygit` + `neovim` + `bat`: Remote tab editing (`os.editPreset: "nvim-remote"`) and syntax diff paging via `git.diffRenderers` (`bat --color=always --style=changes,numbers`).
     - `ripgrep` / `fd` + `fzf` + `bat`: `.gitignore`-aware search (`fd --strip-cwd-prefix` / `rg --files`) with `--info=inline-right` and `bat --theme=auto` previews.
     - `mpv` + `yt-dlp` + GPU HWDEC: Zero-copy `hwdec=auto-safe` + `vo=gpu-next` + `yt-dlp-ejs` web streaming bypassing browser CPU/RAM overhead.
     - `winget` + `wsl` + `windows-terminal`: WinGet concurrency, WSL2 mirrored networking / `[experimental] autoMemoryReclaim=dropcache` (no `sparseVhd`), and Windows Terminal AtlasEngine.
     - `gh` + `git` + `lazygit` + `topgrade`: HTTPS `gh auth setup-git` / SSH workflow, `bat` pager, LazyGit PR views, and Topgrade's native `github_cli_extensions` step.
     - `neovim` + `mise`: Single-source polyglot LSPs/formatters/linters/DAPs via mise shims, locked `mason.nvim` (`opts_extend = {}`, `opts.servers.<srv>.mason = false`), native `vim.lsp.config`/`enable`, async `DirChanged` `mise env --json` sync, and `topgrade` + `mise reshim`.
     - `windows-terminal` + `pwsh` + `starship` + `zoxide` + `fzf`: Instant `--print-full-init` cached prompt, fuzzy path completion, and interactive history navigation.
     - `topgrade` + `mise`: Unified workstation maintenance (`disable = ["uv", "cargo", "pi"]`, `cleanup = true` + `mise prune`, `[post_commands]` `mise reshim`).
     - `mise` + `starship` + `bash`/`pwsh`: Optional `[mise]` (`disabled = false`, `$symbol`/`$health`) or per-language modules + `mise` `env_cache = true`.
     - `topgrade` + `cargo` + `mise`: Prebuilt Rust binaries via `mise` `cargo.binstall = true`, disabling duplicate from-source `cargo` rebuilds in Topgrade.
     - `podman` + `lazydocker`: Rootless containers (`crun`, `pasta`, Quadlet units, `podman.socket`) with interactive TUI monitoring.
     - `htop` + `btop`: Aligned thread/memory/GPU monitoring (`delay=20` / `update_ms = 2000`).

## 11. More Examples (moved from SKILL.md)

### Example 3: Windows Terminal, Shell, and Subsystem
```bash
system-optimizer windows-terminal pwsh wsl
```
Optimizes Windows Terminal settings, configures PowerShell 7 PSReadLine predictive IntelliSense and `--print-full-init` cached prompts, and tunes WSL2 VM memory bounding and mirrored networking (without `sparseVhd=true`).

### Example 4: Package Management & Media Playback
```bash
system-optimizer winget topgrade mpv
```
Tunes WinGet source sync interval and downloader engine, configures Topgrade cross-ecosystem updates, and optimizes `mpv` (`vo=gpu-next`, `profile=high-quality`, zero-copy `hwdec=auto-safe`, `tone-mapping=auto`, `target-colorspace-hint=auto`).

### Example 5: Polyglot Toolchains & Maintenance Orchestration (mise + topgrade)
```bash
system-optimizer mise topgrade
```
Evaluates host CPU thread concurrency and bounds `mise`/`topgrade` `[mise] jobs` to `$(nproc)`, configures `mise` caching (`env_cache = true`, `download_cache = true`, `download_cache_max_size = "2GiB"`) and supply-chain verification (`minimum_release_age`, SLSA/cosign/npm provenance), configures Topgrade with `[mise] bump = true`, `cleanup = true`, `"Mise Reshim" = "mise reshim"`, and `disable = ["uv", "cargo", "pi"]`.

### Example 6: Polyglot LSP Runtime & Editor Synergy (mise + neovim)
```bash
system-optimizer mise neovim
```
Configures Neovim with `vim.loader.enable()`, prepends `mise` shims and appends Mason bin on `vim.env.PATH`, migrates polyglot LSPs/formatters/linters from `mason.nvim` to `mise`, locks `mason.nvim` (`PATH = "append"`, `opts_extend = {}`, `opts.servers.<srv>.mason = false`), adds an async `DirChanged` `mise env --json` hook, validates LazyVim v15/v16+ compatibility (`nvim-treesitter` `main` branch, `v:lua.LazyVim.treesitter.foldexpr()`, `lazydev`, `ai.copilot-native`/`ai.sidekick`), and verifies with `nvim --headless +q`.

### Example 7: Zero-Latency Prompt & Shell Integration (mise + starship)
```bash
system-optimizer mise starship bash
```
Configures `starship.toml` with `command_timeout = 500`, `[mise]` (`$symbol`/`$health`) or per-language modules paired with `mise` `env_cache = true`, and caches `starship init <shell> --print-full-init`.

### Example 8: Rust Pre-compiled Binstall & Compilation De-duplication (mise + cargo + topgrade)
```bash
system-optimizer mise cargo topgrade
```
Verifies `cargo.binstall = true` in `mise`, cleans `~/.cargo/config.toml` (`[profile.release]`, `git-fetch-with-cli = true`, flagging deprecated `~/.cargo/config`), configures Topgrade with `disable = ["cargo"]` to prevent redundant from-source `cargo-update` builds, and routes binary upgrades through `[mise] bump = true`.

### Example 9: Autonomous Coding Agent Toolchain & Workspace Synergy (mise + pi + herdr)
```bash
system-optimizer mise pi herdr
```
Ensures `pi` and `herdr` inherit active `mise` shims, configures `herdr integration status` + `[session] resume_agents_on_restore = true`, tunes `pi` (`cacheWarming: "idle"`, `PI_CACHE_RETENTION=long`, `defaultProjectTrust`), validates with `herdr config check`, and enforces `0600` permissions on `herdr.sock`, `config.toml`, `auth.json`, and `mcp-auth.json`.

### Example 10: Broader Cross-Tool Workstation Synergies
```bash
system-optimizer lazygit neovim bat ripgrep fzf mpv yt-dlp winget wsl windows-terminal
```
Configures `lazygit` `os.editPreset: "nvim-remote"` and `git.diffRenderers` (`bat`), wires `fd --strip-cwd-prefix` / `rg --files` for `fzf` (`--info=inline-right`) with `bat --theme=auto` previews, configures `mpv` (`vo=gpu-next`, `hwdec=auto-safe`) with `yt-dlp` (`yt-dlp-ejs`, `-N 4`), and aligns WinGet, WSL2 (`autoMemoryReclaim=dropcache`), and Windows Terminal.

### Example 11: GitHub CLI & Workstation Developer Workflow Synergy (gh + git + lazygit + bat + topgrade)
```bash
system-optimizer gh git lazygit bat topgrade
```
Configures `gh auth setup-git` for HTTPS remotes (or `git_protocol: ssh`), sets YAML `pager: bat --color=always --style=plain`, enables `telemetry: disabled` and `expiring_credentials: enabled`, enforces `0600` on `hosts.yml`, tunes `git` (`feature.manyFiles`, `zdiff3`, `rerere`, `rebase.updateRefs`), and uses Topgrade's native `github_cli_extensions` step.
