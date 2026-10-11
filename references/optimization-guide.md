# System, Security & Tool Optimization Guide (Windows & Linux)

This reference guide provides engineering heuristics, hardening standards, upstream research strategies, and persistent memory specifications for the **`system-optimizer`** skill across both Windows and Linux hosts.

---

## 1. System & Hardware Tuning Heuristics

### CPU & Concurrency
- **Logical Threads (`nproc` / Logical Processors)**:
  - *Package Compilation (`cargo`, `ninja`, `makepkg`)*: Set `jobs = threads`, `MAKEFLAGS="-j$(nproc)"`.
  - *Package Downloads (`winget`, `pacman`, `yay`)*: Concurrency aligned with network bandwidth and disk I/O; `winget` direct WinINet downloader, `ParallelDownloads = 5` in pacman.
  - *Search & Indexing (`ripgrep`, `fd`, `fzf`)*: Bounded to detected logical thread count (`--threads $(nproc)`).
  - *Compression (`zstd`)*: Multithreaded compression level 3 (`zstd -T$(threads) -3`).
- **Power Plans & Scaling**:
  - *Windows*: High Performance or Ultimate Performance power plan (`powercfg /s 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c`), ensuring 100% min/max processor states on AC and preventing core parking from introducing wake latency on desktop workstations.
  - *Linux*: CPU governors: `schedutil` (balanced), `performance` (max throughput); Energy Performance Preference (EPP): `balance_performance` on AC.

### Memory Tier Management
- **Low RAM (<= 4GB)**:
  - Keep application worker pools bounded strictly to logical thread count.
  - Enforce strict per-process memory limits (e.g. Git `pack.windowMemory = 256m`, `pack.packSizeLimit = 512m`).
  - *Windows*: Enable Memory Compression (`Enable-MMAgent -mc`) to compress idle pages in RAM instead of incurring disk paging latency.
  - *Linux*: Enable `zram-generator` with `zstd` algorithm and `vm.swappiness = 150-180`.
  - Bound WSL2 VM memory strictly to 1.5GB-2GB in `~/.wslconfig`.
- **Medium RAM (4GB - 16GB)**:
  - Balanced concurrency (`threads * 2` for I/O tasks).
  - Standard in-memory buffers and caching.
  - Bound WSL2 VM memory to 6GB-8GB with `autoMemoryReclaim = dropcache`.
- **High RAM (> 16GB)**:
  - Aggressive in-memory caching, memory-mapped I/O.
  - Bound WSL2 VM memory to 8GB-12GB, reserving ample headroom for Windows host GPU/gaming/compilation.

### Storage & Filesystem
- **Windows (NTFS / NVMe / SSD)**:
  - *TRIM Verification*: Ensure `fsutil behavior query DisableDeleteNotify` returns `0` (TRIM operations enabled for SSDs).
  - *Periodic Optimization*: Run weekly volume re-trim via PowerShell (`Optimize-Volume -DriveLetter C -ReTrim -Verbose`).
  - *NTFS 8.3 Short Names*: Disable 8.3 name generation on secondary data volumes (`fsutil 8dot3name set D: 1`) to eliminate directory enumeration overhead on large repositories (e.g. `node_modules`).
  - *WSL Disk Compaction*: Set `sparseVhd = true` in `~/.wslconfig` so Windows automatically reclaims unallocated space from `ext4.vhdx` when files are deleted inside WSL.
- **Linux (Ext4 / Btrfs / NVMe / SSD)**:
  - *Mount Flags*: Ensure `noatime` is enabled to eliminate write overhead on file reads.
  - *Discard*: Enable periodic TRIM timer (`systemctl enable --now fstrim.timer`).
  - *Schedulers*: `none` or `kyber` for NVMe; `bfq` for HDDs.

### GPU & Hardware Video Acceleration
- **Windows (DirectX / Direct3D 11/12 & NVIDIA NVDEC/NVENC)**:
  - Video Players (`mpv`): Set `vo=gpu-next`, `gpu-api=d3d11`, `hwdec=nvdec-copy` on NVIDIA RTX GPUs. Direct3D 11 is rock-solid on Windows 11 and supports native HDR presentation (`target-colorspace-hint=yes`).
  - Terminal Emulators (`windows-terminal`): Enable the GPU-accelerated Atlas rendering engine with `disableAnimations: true`.
  - Hardware-Accelerated GPU Scheduling (HAGS): Ensure HAGS is enabled in Windows Graphics Settings to reduce frame latency.
- **Linux (VA-API & Vulkan)**:
  - Intel: `intel-media-driver` or `i965` driver.
  - AMD: `radeonsi` Mesa driver.
  - Video Players (`mpv`): `hwdec=vaapi`, `vo=gpu`, `gpu-context=wayland`.

---

## 1.1 Hardware-Driven Decision Engine & Dynamic Theme Policy

The `system-optimizer` skill dynamically derives configuration parameters directly from probed host hardware metrics. No values or themes are hardcoded.

### Hardware Decision Rules

| Hardware Metric | Probed Range / Category | Decision & Configured Parameters |
| :--- | :--- | :--- |
| **CPU Logical Threads (`nproc`)** | Any (e.g. 4, 8, 12, 16, 32) | • `ripgrep`: `--threads=<nproc>`<br>• `cargo`: `jobs = <nproc>`<br>• `zstd`: `-T<nproc> -3`<br>• `WSL`: `processors = max(2, floor(nproc / 2))` or matching physical cores to prevent host starvation |
| **RAM Tier** | **Low (<= 4 GB)** | • Enforce memory limits: Git `pack.windowMemory = 256m`<br>• WSL: `memory = 1.5GB`<br>• Enforce Windows Memory Compression (`Enable-MMAgent -mc`) or Linux zram (`vm.swappiness=160`)<br>• Browser: Aggressive background tab discarding enabled<br>• PowerToys: Disable all non-essential background modules |
| | **Medium (4 GB - 16 GB)** | • Standard caching buffers: Git `pack.windowMemory = 512m`<br>• WSL: `memory = floor(RAM / 2)` (e.g. 8GB on 16GB host) with `autoMemoryReclaim = dropcache`<br>• Standard in-memory caching |
| | **High (> 16 GB)** | • Aggressive in-memory caching and memory-mapped I/O<br>• WSL: `memory = floor(RAM * 0.6)` (leaving ample RAM for host apps & games)<br>• Pi Agent: token compaction reserve `16384`–`32768` |
| **GPU Architecture** | **NVIDIA Discrete GPU (RTX / GTX)** | • `mpv`: `hwdec=nvdec-copy`, `vo=gpu-next`, `gpu-api=d3d11` (or `vulkan`) for NVDEC hardware decode<br>• `rustdesk`: NVENC hardware video encode (H.264/AV1)<br>• Terminal: GPU-accelerated Atlas DirectX rasterization engine<br>• Windows: Hardware-Accelerated GPU Scheduling (HAGS) enabled |
| | **AMD Radeon** | • `mpv`: `hwdec=d3d11va` (Windows) / `vaapi` with `radeonsi` (Linux)<br>• `rustdesk`: AMF hardware video encode |
| | **Intel Arc / Iris Xe** | • `mpv`: `hwdec=d3d11va` (Windows) / `vaapi` with `intel-media-driver` (Linux)<br>• `rustdesk`: QSV hardware video encode |
| | **Integrated / Low-Power GPU** | • `mpv`: `vo=gpu` (instead of `gpu-next`), conservative spline36 scaling, disabled heavy debanding<br>• Terminal: Disable translucent acrylic / blur effects to eliminate redraw lag |
| **Storage Media** | **NVMe / SATA SSD** | • Enforce TRIM: `fsutil DisableDeleteNotify = 0` / `fstrim.timer`<br>• Secondary drives: Disable 8.3 short names (`fsutil 8dot3name set <drive> 1`)<br>• WSL: Enable `sparseVhd = true` for auto-compacting virtual disks<br>• `ripgrep`: Enable `--mmap` for fast memory-mapped file scans<br>• Git: Enable `core.fscache = true` and `core.untrackedCache = true` |
| | **Rotational HDD** | • Disable `--mmap` to avoid disk head thrashing on non-contiguous blocks<br>• Bound concurrent directory walking threads |
| **Display Capabilities** | **HDR Display Mode Active** | • `mpv`: Enable `target-colorspace-hint=yes` for native HDR passthrough to Windows DWM |
| | **SDR Display** | • `mpv`: Enable `hdr-compute-peak=yes` with `tone-mapping=bt.2446a` for dynamic tone-mapping |
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
  - *PUA Protection*: Enable Potentially Unwanted Application blocking via `Set-MpPreference -PUAProtection 1` (blocks adware, coinminers, browser hijackers).
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

# Automatically shrink ext4.vhdx when files are deleted inside WSL
sparseVhd=true

# Tunnel DNS queries through Windows networking (fixes VPN DNS issues)
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
  - Atlas GPU text rendering engine enabled.
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
  - Pre-generate or statically cache starship and zoxide prompts to eliminate subshell forks.
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
    - Parallel execution: Configure step concurrency and set `[mise] jobs = $(nproc)` to match hardware CPU thread budget.
    - Disable missing or uninstalled package hooks (`disable = [...]`) to eliminate probing latency across inactive steps.
    - Enable `cleanup = true`: Orchestrates post-upgrade disk reclamation, automatically cleaning package manager caches and triggering `mise prune` to delete obsolete runtimes and tools.
  - *Configuration*:
    - Coordinate holistic update pipeline across OS package managers (`pacman`, `yay`, `winget`), subsystems (`wsl`), developer tools (`git`, `cargo`), and polyglot runtimes (`mise`).
    - Dedicated `[mise]` table: Enable `bump = true` to allow Topgrade to upgrade installed tools to their latest matching versions (`mise upgrade`).
    - Post-Upgrade Synchronization: Add `"Mise Reshim" = "mise reshim"` to `[post_commands]` ensuring binary shims, dynamic environment paths, and editor language servers are synchronized immediately after runtime updates.
    - Prevent Duplicate Updater Conflicts: Add redundant tool self-updaters (e.g. `uv`, `bun_packages`, `npm`) to `disable = [...]` if their binaries/runtimes are already managed by `mise`, eliminating dual-update race conditions and filesystem permission collisions.
    - Windows specific: Set `accept_all_updates = true` and `winget_use_sudo = false`. Set `pre_sudo = true` and `sudo_loop = true` on Linux for non-blocking single authentication.
  - *Security*:
    - Restrict untrusted shell hooks in `pre_commands` and `post_commands`; execute only verified binaries with explicit arguments.
    - Set `ask_retry = false` to prevent unattended batch execution hangs on network drops or DNS failures.
    - Enforce privilege boundaries: Keep Topgrade elevating via `sudo` exclusively for OS package managers; run `mise` steps unprivileged in user space (`allow_root = false`).
- **Production Tuned Configuration (`topgrade.toml`)**:
  ```toml
  [misc]
  assume_yes = true
  ask_retry = false
  cleanup = true
  pre_sudo = true
  sudo_loop = true
  # Disable steps that are either uninstalled or managed exclusively via mise
  disable = ["uv", "go", "gcloud"]

  [mise]
  # Enables automatic version bumps for tools managed by mise
  bump = true
  # Concurrency bound to CPU threads
  jobs = 4

  [post_commands]
  # Synchronize shims and prune orphaned tool versions immediately after updates
  "Mise Reshim" = "mise reshim"
  ```

### Polyglot Tool & Runtime Manager (`mise`)
- **Configuration**: `~/.config/mise/config.toml` (Linux/macOS) or `%LOCALAPPDATA%\mise\config.toml` (Windows). Global settings can also reside in `settings.toml`.
- **Triad Tuning**:
  - *Performance*:
    - Thread Concurrency: Bound `jobs = $(nproc)` (e.g. 4, 8, 16, 32 depending on detected hardware CPU threads) to saturate network and I/O parallelism during multi-tool installations.
    - Subshell PATH & Environment Latency: Enable `env_cache = true` with `env_cache_ttl = "1h"`. This avoids spawning a full `mise hook-env` evaluation on every shell prompt or subshell invocation, cutting terminal startup and prompt latency by 80-90%.
    - Remote Metadata Query Caching: Set `fetch_remote_versions_cache = "1h"` and `fetch_remote_versions_timeout = "5s"` to eliminate interactive shell freezes during outbound network timeouts or GitHub API rate-limiting.
    - Fast Binary Installations: Set `cargo.binstall = true` (and `cargo.binstall_quickinstall = true` where applicable) to fetch pre-compiled Rust binaries from GitHub releases instead of invoking local `cargo build --release` from source, saving gigabytes of RAM and minutes of CPU compilation time.
    - Windows Native Shims: Configure `windows_shim_mode = "exe"` on Windows for high-performance native PE shims instead of slower `.cmd` / `.bat` wrappers.
    - Git Submodule / Backend Speed: Enable `libgit2 = true` and `gix = true` for high-throughput native git operations.
  - *Configuration*:
    - Version Pinning: Set `pin = true` so tool additions record exact semantic versions in `mise.toml` rather than floating ranges, ensuring absolute environment reproducibility and preventing breaking changes.
    - Storage Hygiene & Lifecycle: Set `cache_prune_age = "7d"` and `always_keep_download = false` to prevent downloaded tarballs, zips, and build artifacts from consuming tens of gigabytes of disk space on fast NVMe/SSDs.
    - Runtime Ergonomics: Set `node.corepack = true` for seamless yarn/pnpm management, and configure `python.uv_venv_auto = "source"` to automatically source uv virtual environments upon directory navigation.
    - Topgrade Integration: Align `jobs` with Topgrade's `[mise] jobs` setting, configure `bump = true` in Topgrade, and rely on Topgrade's post-run `cleanup = true` to invoke `mise prune -y`.
  - *Security & Supply-Chain Integrity*:
    - Aqua & Cosign Supply-Chain Verification: Enable `aqua.slsa = true` and `aqua.cosign = true` to cryptographically verify SLSA provenance and Cosign cryptographic signatures for tools installed via the Aqua registry backend.
    - GitHub Attestations & Verification: Enable `github_attestations = true` to verify build attestations for pre-compiled GitHub release assets.
    - Node.js Distribution Verification: Enable `node.verify = true` to validate SHA256 checksums and PGP signatures on Node.js official binaries.
    - Restrict Config Permissions: Enforce `0600` permissions on `~/.config/mise/config.toml` to protect environment variables and private registry tokens.
    - Restrict Root Execution: Set `allow_root = false` to prevent accidental elevation when running maintenance tasks with `sudo`.
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
  cargo.binstall = true                  # Fetch pre-compiled Rust binaries
  libgit2 = true                         # Native git library for fast cloning
  windows_shim_mode = "exe"              # Fast native shims on Windows

  # Configuration & Ergonomics
  pin = true                             # Always pin exact version numbers
  cache_prune_age = "7d"                 # Auto-expire download caches
  always_keep_download = false           # Delete downloaded archives after install
  not_found_auto_install = true          # Auto-prompt to install missing tools
  node.corepack = true                   # Automatic Corepack management for Node
  python.uv_venv_auto = "source"         # Auto-source uv virtualenvs

  # Supply-Chain Security & Integrity
  aqua.slsa = true                       # Verify SLSA provenance for aqua packages
  aqua.cosign = true                     # Verify Cosign cryptographic signatures
  github_attestations = true             # Verify GitHub artifact build attestations
  node.verify = true                     # Checksum & signature check for Node.js
  allow_root = false                     # Disallow running mise under root/sudo

  [tools]
  # Managed polyglot runtimes and CLI developer tools
  node = "lts"
  python = "latest"
  uv = "latest"
  rust = "stable"
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
   - Topgrade handles `sudo` elevation for OS-level updates (`pre_sudo = true`, `sudo_loop = true`), but executes user tool updates without root privileges.
   - Mise enforces `allow_root = false`, preventing unintentional execution of user tool plugins or arbitrary post-install scripts as `root`.

6. **Rust Tooling & Pre-compiled Binstall vs From-Source Rebuilds (`cargo` + `mise` + `topgrade`)**:
   - *The Bottleneck*: Topgrade has a default `[cargo]` step that runs `cargo install-update -a` (using `cargo-update`), which scans and compiles installed Rust CLI binaries from source code. On developer workstations, recompiling utilities like `ripgrep`, `bat`, `eza`, `starship`, `zoxide`, and `bottom` from source saturates CPU threads, exhausts memory, and causes 15–45 minute workstation update pauses.
   - *The Pre-compiled Binstall Solution*: When Rust CLI tools are managed via `mise` with `cargo.binstall = true`, `mise` queries GitHub release assets and downloads cryptographically verified, pre-compiled native binaries directly in seconds.
   - *De-duplication in Topgrade*: Topgrade's from-source `cargo` step is disabled via `disable = ["cargo"]` (or scoped strictly to private internal crates), while `[mise] bump = true` handles instantaneous binary updates.

### Rust Package Manager & Toolchain (`cargo`)
- **Configuration**: `~/.cargo/config.toml` (Linux/macOS) or `%USERPROFILE%\.cargo\config.toml` (Windows).
- **Triad Tuning**:
  - *Performance*:
    - Concurrency: Set `build.jobs = $(nproc)` to saturate CPU logical cores during local crate compilation.
    - Sparse Registry Protocol: Ensure `registries.crates-io.protocol = "sparse"` (default in modern Cargo) to eliminate multi-minute git index clones.
    - Git Fetch CLI: Set `net.git-fetch-with-cli = true` to leverage host system Git credentials and SSH multiplexing.
    - De-duplication via Mise: Delegate global Rust CLI utility installations to `mise` with `cargo.binstall = true` (`mise use -g cargo:ripgrep`), reserving native `cargo install` strictly for packages without release binaries.
  - *Configuration*:
    - Set default build profiles (`opt-level = 3`, `lto = "thin"`, `codegen-units = 16` for development/release balance).
  - *Security*:
    - Supply-Chain Security: Integrate `cargo-audit` and `cargo-vet` into CI/maintenance workflows.
    - Enforce verified checksums for all crate dependencies in `Cargo.lock`.
- **Production Tuned Configuration (`~/.cargo/config.toml`)**:
  ```toml
  # Cargo Production Performance Configuration
  [build]
  jobs = 4                          # Bound to host logical CPU threads
  rustflags = ["-C", "target-cpu=native"]

  [net]
  git-fetch-with-cli = true         # Leverage system git & SSH multiplexing
  retry = 2

  [registries.crates-io]
  protocol = "sparse"               # High-speed HTTP sparse index protocol
  ```
### Search Utility (`ripgrep` / `rg`)
- **Configuration**: `$RIPGREP_CONFIG_PATH` pointing to `~/.config/ripgrep/config` or `%APPDATA%\ripgrep\config`.
- **Triad Tuning**:
  - *Performance*: Bound worker threads dynamically to detected CPU logical threads (`--threads=$(nproc)`); enable `--mmap` for fast memory-mapped searches on SSDs/NVMe; set `--max-columns=300` and `--max-columns-preview` to prevent runaway memory when matching huge minified JavaScript / JSON files.
  - *Configuration*: Enable `--smart-case` by default; configure standard ignore globs (`--glob=!.git/*`, `--glob=!node_modules/*`, `--glob=!target/*`, `--glob=!dist/*`, `--glob=!.venv/*`).
  - *Security*: Ignore hidden git internals to prevent credential leakage in search output; sanitize regex queries.

### Directory Navigation (`zoxide`)
- **Database & State**: `%LOCALAPPDATA%\zoxide\db.zo` (Windows) or `~/.local/share/zoxide/db.zo` (Linux).
- **Triad Tuning**:
  - *Performance*: Pre-cache or fast-initialize zoxide in shell profiles (`pwsh` `$PROFILE` and `bash` `~/.bashrc`) rather than spawning slow dynamic subshells on every terminal startup. Periodically prune dead/stale directory paths with `zoxide remove`.
  - *Configuration*: Standard aliases: `z` (jump) and `zi` (interactive fuzzy search with `fzf`). Set `_ZO_EXCLUDE_DIRS = "$HOME", "/tmp", "C:\Windows"` to avoid polluting the database with root/temp paths.
  - *Security*: Restrict `db.zo` file permissions (`0600`) to maintain directory privacy.

### Modern File Lister (`eza`)
- **Configuration**: `%APPDATA%\eza\theme.yml` or `~/.config/eza/theme.yml`.
- **Triad Tuning**:
  - *Performance*: Avoid default `--git` scanning on deep directory trees or network shares; bind `--git` strictly to the detailed long listing alias (`ll`).
  - *Configuration*: Standard ergonomic aliases in `pwsh` and `bash`:
    - `ls='eza --icons'`
    - `ll='eza -l --icons --git --header --time-style=relative'`
    - `la='eza -la --icons --git --header'`
    - `lt='eza --tree --level=2 --icons'`
  - *Security*: Keep `--no-dereference` active by default so symlinks are never traversed into restricted directories.

### Git Terminal UI (`lazygit`)
- **Configuration**: `%APPDATA%\lazygit\config.yml` or `~/.config/lazygit/config.yml`.
- **Triad Tuning**:
  - *Performance*: Set `git.autoFetch: false` (vital on Windows to prevent background git subprocesses from continuously triggering Microsoft Defender file scans and high CPU usage); set `animateExplosion: false`.
  - *Configuration*: Integrate with Neovim via RPC remote tab editing (`edit: 'nvim --server "$NVIM" --remote-tab "$FILE"'`) to avoid nested editor freezes; synchronize theme palette with active terminal/editor or prompt user.
  - *Security*: Respect git `safe.directory` rules; avoid untrusted custom commands.

### Modal Text Editor (`neovim` / `nvim`)
- **Configuration**: `%LOCALAPPDATA%\nvim\init.lua` (Windows) or `~/.config/nvim/init.lua` (Linux).
- **Production Performance `init.lua` Template**:
  ```lua
  -- 1. Bytecode loader caching: cuts Neovim startup time to <100ms
  if vim.loader then
    vim.loader.enable()
  end

  -- 2. Mise shims PATH safety guard: ensures LSPs/formatters resolve even when launched from GUI/desktop
  local is_win = vim.fn.has("win32") == 1
  local sep = is_win and ";" or ":"
  local mise_shims = is_win and vim.fn.expand("$LOCALAPPDATA/mise/shims") or vim.fn.expand("~/.local/share/mise/shims")
  if vim.fn.isdirectory(mise_shims) == 1 and not string.find(vim.env.PATH, mise_shims, 1, true) then
    vim.env.PATH = mise_shims .. sep .. vim.env.PATH
  end

  -- 3. Core ergonomics & persistent undo
  vim.opt.undofile = true
  vim.opt.undolevels = 10000
  vim.opt.updatetime = 200
  vim.opt.timeoutlen = 300

  -- 4. Security: block arbitrary execution from downloaded files
  vim.opt.modeline = false
  ```
- **Triad Tuning**:
  - *Performance*: Enable byte-compiled Lua caching at the top of `init.lua` (`vim.loader.enable()`); defer non-critical plugins via `lazy.nvim` (`event = "VeryLazy"`); resolve language servers via shims on PATH without spawning slow synchronous subshells (`mise which` / `mise exec`).
  - *Configuration*: Integrate with system clipboard (`win32yank`/`powershell` on Windows, `wl-clipboard`/`xclip` on Linux); telescope integration with `ripgrep` and `fzf`; single-source LSP and formatter management via `mise`.
  - *Security*: Disable insecure modelines (`vim.opt.modeline = false`) to prevent arbitrary command execution from untrusted downloaded source files; enforce plugin lockfile pinning in `lazy-lock.json`; set config permissions to `0600`.

#### Neovim & Mise Polyglot LSP, Formatter & Toolchain Architecture
The integration between Neovim and Mise establishes a unified, reproducible development environment where language servers and formatters are decoupled from ad-hoc editor plugin managers and bound to project-level or global mise configurations.

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│                           Polyglot Toolchain in Mise                             │
│       Node / TS       Python          Rust         Go          Lua        Shell  │
│       pyright         ruff / black    rust-analyzer gopls      lua-ls     shfmt  │
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

1. **Mason.nvim PATH Precedence & De-duplication**:
   - By default, `mason.nvim` prepends its private binary directory (`~/.local/share/nvim/mason/bin`) to Neovim's `PATH`. This causes Neovim to run isolated Mason-managed binaries instead of the project-pinned compiler, LSP, or formatter specified in `.mise.toml`.
   - **Recommended Configuration**: Set `PATH = "append"` in `mason.nvim`:
     ```lua
     -- In lua/plugins/mason.lua
     return {
       "williamboman/mason.nvim",
       opts = {
         PATH = "append", -- Project/mise tools on PATH take precedence; Mason only fills gaps
       },
     }
     ```
   - **De-duplication**: Avoid installing packages in Mason that are already managed in `~/.config/mise/config.toml` or project `.mise.toml` (e.g. `pyright`, `ruff`, `typescript-language-server`, `rust-analyzer`). Reserve Mason strictly for editor-only extensions (such as `roslyn.nvim` or specialized DAP debug adapters).

2. **Native LSP & Formatter Setup via Mise Shims**:
   - `nvim-lspconfig` and `conform.nvim` automatically discover executables on `PATH`. Because `mise` shims are active on `PATH`, no custom wrapper code or subshell execution is needed:
     ```lua
     -- LSP setup automatically finds mise shims in <1ms without latency
     local lspconfig = require("lspconfig")
     lspconfig.pyright.setup({})
     lspconfig.ts_ls.setup({})
     lspconfig.rust_analyzer.setup({})

     -- Formatter setup via conform.nvim
     require("conform").setup({
       formatters_by_ft = {
         python = { "ruff_format", "ruff_fix" },
         javascript = { "biome", "prettier" },
         lua = { "stylua" },
       },
     })
     ```

3. **Unified Maintenance Chain (`topgrade` -> `mise` -> `neovim`)**:
   - When workstation maintenance runs via `topgrade`:
     1. Topgrade executes the `[mise]` update step with `bump = true`, updating language servers, linters, and formatters to latest upstream stable releases.
     2. Topgrade executes `mise reshim` via `[post_commands]`.
     3. Neovim automatically picks up updated language servers upon next launch or `:LspRestart`, eliminating the need to run headless Mason updates or manual `:MasonUpdate`.

### Syntax Pager & Fuzzy Finder (`bat` + `fzf`)
- **`bat` Tuning (`%APPDATA%\bat\config` / `~/.config/bat/config`)**:
  - *Performance*: Set `--paging=never` when used as a sub-pager for lazygit or git diff; pre-cache themes with `bat cache --build`.
  - *Configuration*: Synchronize `--theme` with the inferred terminal/editor theme (or prompt user), set `--style="numbers,changes,header"`.
- **`fzf` Tuning (`FZF_DEFAULT_COMMAND`, `FZF_DEFAULT_OPTS`)**:
  - *Performance*: Set `FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'` for multithreaded directory traversal.
  - *Configuration*: Set layout to reverse, border, preview window using bat with line preview limits (`--preview 'bat --color=always --line-range :300 {}'`).
  - *Security*: Exclude sensitive files (`.git/`, `.env*`, `id_rsa*`) from the default search index.

### Shell Prompt (`starship`)
- **Configuration**: `~/.config/starship.toml` or `%APPDATA%\starship.toml`.
- **Production Performance `starship.toml` Template (with native `mise` integration)**:
  ```toml
  # Starship Production Performance Configuration
  # Bounds prompt command evaluation to prevent terminal hitching
  command_timeout = 500
  add_newline = false

  # Core prompt modules
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

  # Native Mise module: displays active polyglot tools without spawning slow language subshells
  [mise]
  disabled = false
  format = "via [$symbol$version]($style) "
  symbol = " "
  style = "bold yellow"

  # Disable individual per-language version modules to eliminate 50-200ms prompt lag
  [nodejs]
  disabled = true

  [python]
  disabled = true

  [rust]
  disabled = true

  [golang]
  disabled = true

  [ruby]
  disabled = true

  [php]
  disabled = true

  [java]
  disabled = true

  [character]
  success_symbol = "[❯](bold green)"
  error_symbol = "[❯](bold red)"
  ```

- **Shell Integration (`bash` & `pwsh`)**:
  - *Bash* (`~/.bashrc`):
    ```bash
    # Activate mise with environment caching
    if command -v mise >/dev/null 2>&1; then
      eval "$(mise activate bash)"
    fi
    # Fast Starship prompt hook
    if command -v starship >/dev/null 2>&1; then
      eval "$(starship init bash)"
    fi
    ```
  - *PowerShell 7* (`$PROFILE`):
    ```powershell
    # Activate mise
    if (Get-Command mise -ErrorAction SilentlyContinue) {
      Invoke-Expression (&mise activate pwsh | Out-String)
    }
    # Fast Starship prompt hook
    if (Get-Command starship -ErrorAction SilentlyContinue) {
      Invoke-Expression (&starship init pwsh | Out-String)
    }
    ```

- **Triad Tuning**:
  - *Performance*:
    - Set `command_timeout = 500ms`.
    - Disable redundant per-language modules (`[nodejs]`, `[python]`, `[rust]`, `[golang]`). In traditional setups, each active language module spawns a separate binary (`node --version`, `python --version`) through shims on every prompt draw.
    - Enable the native `[mise]` module, which queries the current environment directly in a single pass.
    - Enable `env_cache = true` with `env_cache_ttl = "1h"` in `mise/config.toml` to guarantee sub-millisecond directory transitions.
  - *Configuration*: Minimalist clean layout; directory truncation length 3; consistent Nerd Font symbols.
  - *Security*: Avoid executing arbitrary remote network queries in custom prompt modules (`[custom.*]`); restrict `starship.toml` permissions to `0600`.
### Media Player (`mpv`)
- **Configuration**: `%APPDATA%\mpv\mpv.conf` (Windows) or `~/.config/mpv/mpv.conf` (Linux).
- **Windows Triad Tuning (Discrete GPU / NVIDIA RTX + HDR Display)**:
  - `vo=gpu-next`: Modern libplacebo-based renderer.
  - `gpu-api=d3d11`: Rock-solid Direct3D 11 API on Windows 11 with native HDR presentation.
  - `hwdec=nvdec-copy`: Hardware decoder tailored to detected GPU (NVDEC copy-back on NVIDIA, d3d11va on AMD/Intel).
  - `target-colorspace-hint=yes`: Native HDR passthrough to Windows DWM when HDR is active.
  - `hdr-compute-peak=yes`, `tone-mapping=bt.2446a`: Dynamic peak detection HDR tone-mapping to SDR when HDR display mode is off.
  - `interpolation=yes`, `video-sync=display-resample`: Smooth motion eliminating judder on high-refresh displays (144Hz).
  - `scale=ewa_lanczossharp`, `cscale=spline36`: Sharp high-quality upscaling for compressed web streams.
  - `deband=yes`: Eliminates color banding gradients in web video.

### Media Downloader (`yt-dlp`)
- **Configuration**: `%APPDATA%\yt-dlp\config` or `~/.config/yt-dlp/config`.
- **Triad Tuning**:
  - *Performance*: Configure `--concurrent-fragments=4` and multithreaded download connections; integrate `ffmpeg` for post-processing.
  - *Configuration*: Default to `bestvideo+bestaudio/best`, embed subtitles and chapter markers.
  - *Security*: Restrict untrusted cookie injection, sanitize output filenames.

### Remote Desktop (`rustdesk`)
- **Configuration**: `%APPDATA%\RustDesk\config` (Windows) or `~/.config/rustdesk` (Linux).
- **Triad Tuning**:
  - *Performance*: Hardware video acceleration (Direct3D/NVENC on Windows, VA-API on Linux) for low-CPU 60 FPS streaming.
  - *Configuration*: Custom private ID and relay server settings; tray minimization.
  - *Security*: Enforce strong one-time passwords, restrict direct IP access, whitelist approved peer IDs.

### Git Version Control (`git`)
- **Configuration**: `~/.gitconfig`, `%PROGRAMDATA%\Git\config`.
- **Windows Triad Tuning**:
  - `core.fscache = true`: Caches filesystem stat calls, significantly speeding up status and diff on NTFS.
  - `core.preloadIndex = true`: Parallelizes index preloading across CPU cores.
  - `core.untrackedCache = true`: Uses filesystem timestamps to avoid scanning unchanged directories.
  - `core.autocrlf = input` (or `true` on Windows): Consistent newline handling.
  - `credential.helper = manager`: Integrates with secure Windows Credential Manager.
  - `diff.algorithm = histogram`: Clean readable diffs.

### GitHub CLI (`gh`)
- **Configuration**: `~/.config/gh/config.yml`, `~/.config/gh/hosts.yml` (Linux/macOS) or `%APPDATA%\GitHub CLI\` (Windows).
- **Synergies**:
  - **Git & LazyGit Credential Helper**: Running `gh auth setup-git` configures `credential.helper` so Git and LazyGit operations authenticate transparently via GitHub CLI's keyring/tokens without password prompts.
  - **LazyGit TUI Integration**: Custom LazyGit keybindings invoke `gh pr view --web`, `gh pr checkout`, and `gh pr create` directly from branch and commit views.
  - **Bat Syntax Pager**: Setting `gh config set pager "bat --color=always --style=plain"` gives zero-latency syntax-highlighted diffs during `gh pr diff` and `gh pr view` reviews.
  - **Topgrade Automated Maintenance**: Topgrade coordinates `gh extension upgrade --all` during workstation updates.
  - **Neovim Remote Review**: Setting `gh config set editor "nvim"` or using `octo.nvim` connects GitHub CLI data with modal editing.
  - **Autonomous AI Coding Agents (`pi` & `herdr`)**: Non-interactive agent runs execute `gh pr`, `gh issue`, and `gh run watch` to inspect CI and create pull requests without browser interaction.
- **Triad Tuning**:
  - *Performance*:
    - Use `bat --color=always --style=plain` as the review pager to avoid terminal lockup and provide fast syntax highlighting.
    - Leverage lean JSON queries with `--json` and `jq` in scripts and shell functions instead of parsing unstructured terminal output.
    - Coordinate batch extension upgrades in Topgrade to prevent background update lag.
  - *Configuration*:
    - Set `git_protocol = "ssh"` (or `"https"` with `gh auth setup-git`).
    - Run `gh auth setup-git` to register GitHub CLI as the Git credential helper.
    - Enable interactive prompt ergonomics: `prompt = "enabled"`.
    - Configure productive PR workflow aliases: `co: "pr checkout"`, `pv: "pr view"`, `pc: "pr create"`, `il: "issue list"`.
  - *Security*:
    - Restrict `~/.config/gh/hosts.yml` permissions to `0600` (contains OAuth/PAT tokens).
    - Audit installed extensions (`gh extension list`) to mitigate supply-chain risks.
    - Request only necessary OAuth scopes (`repo`, `read:org`, `gist`) rather than admin scopes.
### Pi Coding Agent Harness (`pi`)
- **Configuration**: `~/.pi/agent/settings.json`, `~/.pi/agent/auth.json`.
- **Mise Toolchain Synergy**:
  - Autonomous agents frequently execute shell commands (`bash -c "npm test"` or `pwsh -Command "pytest"`). Non-interactive subshells bypass interactive `.bashrc` activation hooks, which can lead to `command not found` or executing the wrong system binary.
  - Adding `~/.local/share/mise/shims` (or `%LOCALAPPDATA%\mise\shims`) to the agent subshell execution path ensures agents always execute the project-pinned toolchains (Node.js, Python, Rust, Go, UV, Bun) defined in `.mise.toml`.
- **Triad Tuning**:
  - *Performance*: Session archival (`~/.pi/agent/sessions/`) older than 30 days, web search cache pruning, compaction token reserve tuning (`16384`).
  - *Configuration*: Model router latency tuning, thinking budget assignment, terminal progress indicators, toolchain shim inheritance.
  - *Security*: Restrict `auth.json` permissions (`0600`), explicit tool permission deny rules for sensitive files (`.ssh`, `.secrets`).

### Terminal Workspace & Agent Multiplexer (`herdr`)
- **Configuration**: `%APPDATA%\herdr\config.toml` (Windows) or `~/.config/herdr/config.toml` (Linux).
- **Runtime State & Sockets**: `%APPDATA%\herdr\` (`session.json`, `herdr.sock`, `herdr-server.log`).
- **Mise Workspace Toolchain Synergy**:
  - When Herdr spawns worker terminal panes across Git worktrees, ensuring child shells inherit active `mise` shims guarantees that concurrent agent workers can run builds, tests, and formatting concurrently without environment drift.
- **Triad Tuning**:
  - *Performance*:
    - Monitor and truncate `herdr-server.log` and `herdr-client.log` to prevent disk bloat during long AI agent sessions.
    - Clean up orphaned session artifacts and stale sockets on restart (`herdr server stop` before updates).
    - Ensure `default_shell = "pwsh"` or `"/bin/bash"` launches cleanly with fast static prompt/module loading.
  - *Configuration*:
    - Set `default_shell = "pwsh"` on Windows (or `"bash"`).
    - Theme synchronization: Set `name` to match inferred terminal/editor color palette or prompt user.
    - UI ergonomics: Enable `show_agent_labels_on_pane_borders = true`, set `status_indicators = "symbols"`.
    - Native desktop notifications: Configure `[ui.toast]` `delivery = "system"` for unobtrusive notification center delivery.
  - *Security*:
    - Strictly enforce local user access on `herdr.sock` and `config.toml` (`0600` permissions).
    - Restrict workspace directory permissions (`0700`).
    - Never expose the Herdr socket API to external network interfaces without TLS/SSH tunneling.
    - Isolate AI coding agent execution panes using Git worktrees and explicit directory boundaries.
---
## 5.2 Tier 2: Broader Cross-Tool Workstation Synergies

| Synergy Pair / Trio | Architectural Benefit & Triad Rationale | Configuration Integration Pattern |
|---|---|---|
| **`lazygit` + `neovim` + `bat`** | Configure lazygit to use `nvim --server` / remote tab editing to prevent nested editor spawns, and configure pager: `"bat --color=always --style=changes"` for fast syntax-highlighted diffs without extra pager dependencies. | In `lazygit/config.yml`: set `os.editCommand: nvim`, `os.editCommandTemplate: '{{editor}} --server "$NVIM" --remote-tab "{{filename}}"'` (or `editPreset: 'nvim-remote'`), and `git.paging.pager: "bat --color=always --style=changes"`. |
| **`ripgrep` + `fzf` + `bat`** | Wire `rg` as the backend search generator for fzf (`FZF_DEFAULT_COMMAND`), with `bat` rendering line-numbered, syntax-highlighted previews for files and code hits. | Export `FZF_DEFAULT_COMMAND='rg --files --hidden --glob "!.git/*"'` and `FZF_DEFAULT_OPTS="--preview 'bat --style=numbers --color=always --line-range :500 {}'"`. |
| **`mpv` + `yt-dlp` + GPU HWDEC** | Stream web video directly to mpv via yt-dlp, using native hardware decoding (`nvdec-copy` on NVIDIA RTX, `vaapi` on Intel/AMD, `d3d11va` on Windows) and D3D11/Vulkan color management, bypassing heavy browser CPU/RAM consumption. | In `mpv.conf`: `vo=gpu-next`, `hwdec=nvdec-copy` (or `vaapi`/`d3d11va`), `ytdl-format="bestvideo[height<=?1080]+bestaudio/best"`, `target-colorspace-hint=yes`. |
| **`winget` + `wsl` + `windows-terminal`** | Align WinGet download concurrency, WSL2 mirrored networking / memory bounding (`autoMemoryReclaim=dropcache`), and Windows Terminal Atlas GPU text rendering. | In `settings.json`: `useAtlasEngine=true`; in `.wslconfig`: `networkingMode=mirrored`, `autoMemoryReclaim=dropcache`, `sparseVhd=true`, `memory=4GB`/`8GB`; in WinGet: `downloader=default`, `source.autoUpdateIntervalInMinutes=120`. |
| **`gh` + `git` + `lazygit`** | Register GitHub CLI as the Git credential helper to eliminate token prompts, and integrate PR/issue reviews directly within the terminal UI. | Run `gh auth setup-git` to register `gh auth git-credential` with Git; configure `git.paging.pager: "bat --color=always --style=plain"`; configure LazyGit custom commands for PR checkouts. |
| **`gh` + `topgrade`** | Coordinated maintenance and supply-chain auditing of third-party GitHub CLI extensions during system upgrades. | Include `gh extension upgrade --all` in Topgrade `[git]` or `[commands]` maintenance steps. |

### Detailed Implementation Specifications

#### 1. lazygit + neovim + bat
- **Nested Editor Elimination**: Spawning a standard `nvim` inside `lazygit` within an interactive terminal creates nested process trees, cursor fighting, terminal redraw latency, and terminal freeze hazards. Utilizing Neovim's UNIX socket or named pipe server (`--server "$NVIM" --remote-tab`) dispatches file edits directly into the parent or sibling Neovim instance as a new tab, instantly returning focus when the buffer is closed.
- **Dependency-Free Syntax Paging**: Instead of requiring heavy external diff pagers like `delta` when not already present, routing lazygit diffs through `bat --color=always --style=changes` delivers immediate 24-bit syntax highlighting, git modification markers, and line numbering with sub-millisecond startup times.

#### 2. ripgrep + fzf + bat
- **Multithreaded Search Backend**: Standard fuzzy walkers rely on slow single-threaded directory scans. Wiring `ripgrep` (`rg --files --hidden --glob "!.git/*"`) as `FZF_DEFAULT_COMMAND` leverages ripgrep's SIMD-accelerated directory walking, multithreaded directory traversal (`--threads=$(nproc)`), and automatic `.gitignore` parsing.
- **Syntax Preview Clamping**: `bat` previews are clamped via `--line-range :500` to prevent memory exhaustion when browsing large minified or generated files, while providing rich, theme-coordinated syntax highlighting for source files.

#### 3. mpv + yt-dlp + GPU HWDEC
- **Chromium/Browser Overhead Bypass**: Playing 1080p60 or 4K web video inside a modern browser (Chrome, Edge, Brave) consumes 1.5–3.5 GiB of RAM, incurs heavy JavaScript runtime overhead, and triggers CPU-intensive software VP9/AV1 decoding on constrained systems.
- **Hardware-Accelerated Stream Passthrough**: Piping web video URLs directly into `mpv` (`mpv "https://..."`) delegates extraction to `yt-dlp` and video decoding to the host GPU ASIC (`nvdec-copy` on NVIDIA RTX, `vaapi` on Intel/AMD, `d3d11va` on Windows) via `vo=gpu-next`. This drops CPU utilization from 40–80% to <5% and reduces memory footprint to under 150 MiB.
- **Color Pipeline**: Native DWM/Wayland HDR passthrough (`target-colorspace-hint=yes`) and BT.2446a tone-mapping deliver reference-grade presentation without browser ICC color distortion.

#### 4. winget + wsl + windows-terminal
- **Windows Subsystem Alignment**: WSL2 virtual machines default to consuming up to 50% of total host RAM with memory caches lingering inside the Linux kernel. Configuring `autoMemoryReclaim=dropcache` automatically returns Linux file cache pages back to Windows host memory.
- **Network Parity**: `networkingMode=mirrored` enables sub-millisecond localhost networking parity between Windows and WSL2, while `firewall=true` propagates Windows Defender Firewall rules inside Linux containers and services.
- **Terminal Rendering**: Windows Terminal's DirectX Atlas text rendering engine (`useAtlasEngine=true`) accelerates font glyph rasterization on the GPU, eliminating terminal scrolling latency even under heavy multi-megabyte log outputs.
- **WinGet Concurrency**: Setting WinGet downloaders to `default` (WinINet) bypasses Delivery Optimization freezes and coordinates seamless updates across host tools.

#### 5. gh + git + lazygit + topgrade
- **Zero-Friction Git Credential Delegation**: Running `gh auth setup-git` links the GitHub CLI authentication state with Git's internal credential architecture (`!gh auth git-credential`). This eliminates personal access token copy-pasting and credential helper misconfigurations across both CLI `git` and terminal TUIs like `lazygit`.
- **Fast Syntax-Highlighted PR Reviews**: Setting `gh config set pager "bat --color=always --style=plain"` invokes `bat` directly during `gh pr diff` and `gh pr view`, providing instant 24-bit colorway syntax highlighting without requiring third-party pager setup.
- **Automated Extension Maintenance**: Third-party GitHub CLI extensions (`gh-copilot`, `gh-dash`, `gh-poi`) are maintained via Topgrade's maintenance flow using `gh extension upgrade --all`, ensuring security patches and bug fixes are applied consistently.

## 6. Mandatory Pre-Modification Backup & Rollback Protocol

Every file edited or overwritten by `system-optimizer` MUST be backed up using `<skill_dir>/scripts/backup-config.sh` before any changes are written to disk.

### 1. Dual-Location Backup Architecture
1. **Centralized Vault**: `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak`
   - Accompanied by `<filename>.<timestamp>.bak.meta` containing:
     - `Original-Path`: Full absolute path of source configuration.
     - `Timestamp`: Execution timestamp (`YYYYMMDD-HHMMSS`).
     - `SHA256`: Checksum of the pre-modification state.
     - `Size` & `Permissions`: File size in bytes and permissions.
     - `Description`: Rationale for modification.
2. **In-Place Adjacent Backup**: `<config_path>.bak.<timestamp>`
   - Created in the parent directory when user write permissions allow (e.g. `settings.json.bak.20260905-143000`).

### 2. Backup CLI Commands
- Create backup:
  ```bash
  ~/.pi/agent/skills/system-optimizer/scripts/backup-config.sh <config-path> <target> "Reason"
  ```
- List backups:
  ```bash
  ~/.pi/agent/skills/system-optimizer/scripts/backup-config.sh --list [target]
  ```
- Diff backup against current:
  ```bash
  ~/.pi/agent/skills/system-optimizer/scripts/backup-config.sh --diff <backup-file> [current-file]
  ```
- Restore / Rollback:
  ```bash
  ~/.pi/agent/skills/system-optimizer/scripts/backup-config.sh --restore <backup-file> [dest-file]
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
- **Rollback Command**: `~/.pi/agent/skills/system-optimizer/scripts/backup-config.sh --restore <backup-file>`

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
| `wsl` | Subsystem | 2.7.x | OPTIMIZED (8GB RAM / Mirrored Net / SparseVHD)| 2026-09-07 |
| `pwsh` | Shell | 7.6.5 | OPTIMIZED (PSReadLine Predict / RemoteSigned)| 2026-09-07 |
| `topgrade` | Maintenance | 17.12.x | OPTIMIZED (Cross-Package Orchestration) | 2026-09-07 |
| `mise` | Runtime Manager | 2026.x | OPTIMIZED (env_cache / jobs / supply-chain / topgrade) | 2026-09-07 |
| `mpv` | Media | 0.41.0 | OPTIMIZED (gpu-next / D3D11 / NVDEC / HDR) | 2026-09-07 |
| `git` | Developer Tool | 2.55.0 | OPTIMIZED (fscache / preloadIndex / diff) | 2026-09-07 |

## 4. Cross-System & Cross-Tool Synergies
- **Unified Workstation Orchestration (`topgrade` + `mise`)**: Coordinates host OS packages (`pacman`, `yay`, `winget`) with user polyglot runtimes (`node`, `python`, `rust`, `uv`); binds parallel jobs to hardware CPU threads (`nproc`); prevents dual-update conflicts by disabling redundant standalone steps (`disable = ["uv"]`) in topgrade; executes post-update `mise reshim` to keep binary shims synchronized; auto-prunes obsolete tool versions and caches via `cleanup = true` and `mise prune`.
- **Terminal & Shell Workflow (`windows-terminal` + `pwsh` + `starship` + `fzf`/`zoxide`)**: GPU-accelerated Atlas rendering, PSReadLine history prediction, static prompt generation.
- **Virtualization & Subsystem Integration (`wsl` + host firewall)**: Mirrored networking shares Windows localhost, Windows Defender Firewall secures WSL traffic, sparseVhd auto-compacts virtual disks.
- **Media & Hardware Acceleration (`mpv` + Discrete GPU)**: D3D11 NVDEC / hardware video decode, HDR passthrough, smooth motion interpolation.

## 5. Global Resource & Security Budget
- **CPU Saturation Guard**: Prevent simultaneous WSL compilation and host transcoding.
- **RAM Threshold**: Bound WSL VM memory to 50% host RAM (8GB); enable Windows Memory Compression.
- **Storage Hygiene**: Package cache retention limits, SSD weekly TRIM maintenance.
- **Security Posture**: Default-deny incoming firewall, PUA protection active, RemoteSigned script execution.

## 6. Cumulative Integration History Log
- [<timestamp>]: Optimization run details.
```
