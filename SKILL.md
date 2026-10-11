---
name: system-optimizer
description: Inspects, configures, hardens, and optimizes the system, tools, desktop/terminal environments, and software packages across Performance, Configuration, and Security. Native support for Windows (winget, windows-terminal, wsl, pwsh, powertoys, defender, storage/trim) and Linux (pacman, yay, flatpak, systemd, sysctl, kde-plasma), as well as cross-platform tools (git, topgrade, mise, neovim, ripgrep, starship, bat, fzf, lazygit, mpv, yt-dlp, rustdesk, controld, pi, bash, herdr, gh). Tailored to host hardware (CPU threads, RAM tier, GPU, disk type) and upstream standards. When called without arguments, probes the system and presents numbered tuning options. Maintains persistent memory in ~/.config/system-optimizer/<target>/MEMORY.md and cross-system ~/.config/system-optimizer/MASTER_MEMORY.md.
---

# System & Tool Optimizer

A comprehensive optimization skill for Windows and Linux systems, package managers, browsers, terminals, subsystems, and developer toolchains. It evaluates and tunes every target against the **Optimization Triad**:

1. **Performance**: Thread concurrency (`nproc` / logical processors), RAM-tier caching boundaries, GPU/hardware acceleration (DirectX / D3D11 / NVDEC / Vulkan / VA-API), storage/TRIM optimization, power plans / CPU scaling governors, memory compression (Windows MMAgent / Linux zram), and subsystem resource limits (WSL VM memory, vCPU, and sparse VHDs).
2. **Configuration**: Sensible modern defaults, workflow ergonomics, companion integrations, pruning obsolete items, static prompt/completion caching, and automated maintenance orchestration (`topgrade`, `winget`, `paccache`).
3. **Security**: Attack surface reduction (Windows Defender PUA & Exploit Guard / Linux sysctl hardening), firewall verification (Windows Defender Firewall / `ufw` / `nftables`), execution policies (`pwsh` RemoteSigned), SSH hardening, package signature verification (`winget` hash checks / `pacman` SigLevel), and least-privilege permissions.

---

## Invocation Modes

```bash
# Auto-detection mode (no arguments provided, detects OS and installed tools):
/skill:system-optimizer

# Windows equivalent packages & tools:
/skill:system-optimizer winget windows-terminal wsl pwsh
/skill:system-optimizer storage defender powertoys
/skill:system-optimizer topgrade mpv rustdesk

# Specific system domain(s):
/skill:system-optimizer system           # Core OS (storage/TRIM, memory, cpu power, boot)
/skill:system-optimizer security         # Security posture, firewall, antivirus/defender, SSH
/skill:system-optimizer storage          # NVMe/SSD TRIM, volume health, filesystem performance

# Specific tool(s) or package(s):
/skill:system-optimizer pwsh             # PowerShell 7 profile, PSReadLine & predictions
/skill:system-optimizer windows-terminal # Windows Terminal GPU engine, profiles, styling
/skill:system-optimizer wsl              # WSL 2 .wslconfig, mirrored networking, auto-memory
/skill:system-optimizer winget           # Windows Package Manager sync interval, telemetry, downloader
/skill:system-optimizer topgrade         # Topgrade cross-package update coordinator
/skill:system-optimizer mise             # Mise polyglot toolchain, env caching & supply chain
/skill:system-optimizer mise topgrade    # Unified workstation maintenance & runtime orchestration
/skill:system-optimizer mise neovim      # Polyglot LSP, formatter runtime & Mason de-duplication
/skill:system-optimizer mise starship    # Zero-latency prompt integration, native [mise] module & shell hooks
/skill:system-optimizer mise cargo topgrade # Rust pre-compiled binstall vs compilation de-duplication
/skill:system-optimizer mise pi herdr    # AI coding agent workspace toolchain & non-interactive PATH isolation
/skill:system-optimizer lazygit neovim bat    # Remote tab editing (nvim --server) & bat diff pager
/skill:system-optimizer ripgrep fzf bat       # rg search generator (FZF_DEFAULT_COMMAND) & bat syntax previews
/skill:system-optimizer mpv yt-dlp            # Web video hardware streaming (GPU HWDEC) bypassing browser CPU/RAM
/skill:system-optimizer winget wsl windows-terminal # WinGet concurrency, WSL2 mirrored/dropcache & Terminal Atlas GPU
/skill:system-optimizer podman lazydocker     # Rootless container management & TUI dashboard
/skill:system-optimizer htop btop             # Resource monitoring & hardware thread inspection
/skill:system-optimizer mpv              # mpv GPU-next, D3D11/NVDEC, HDR passthrough
/skill:system-optimizer pi               # Pi coding agent harness, sessions & settings optimization
/skill:system-optimizer controld         # Control D encrypted DNS resolver daemon & cache
/skill:system-optimizer rustdesk         # RustDesk remote desktop, hardware video codecs & access control
/skill:system-optimizer git              # Git performance (fscache, preloadIndex, diff pager)
/skill:system-optimizer herdr            # Herdr AI agent terminal workspace manager, sessions & sockets
/skill:system-optimizer gh                   # GitHub CLI credentials, pager, default protocol & extensions
/skill:system-optimizer gh git lazygit       # GitHub CLI credential helper & PR/review workflow synergy

# Linux system domain(s) & packages (when running on Linux):
/skill:system-optimizer pacman yay kde-plasma

# Comprehensive full system run:
/skill:system-optimizer full
```

*(Note: `/skill:tool-optimizer` is maintained as a transparent alias to this skill).*

---

## Zero-Argument / Auto-Detection Workflow

When invoked **without arguments**:

1. **Probe System & Tools**: Run `<skill_dir>/scripts/hardware-probe.sh`, `<skill_dir>/scripts/system-probe.sh`, and `<skill_dir>/scripts/detect-targets.sh`.
2. **Present Categorized Numbered Choices** (tailored to detected OS):
   - **Option 1: System Core & OS Performance**:
     - *Windows*: Storage / NVMe SSD TRIM (`fsutil DisableDeleteNotify`), Memory Compression (`Get-MMAgent`), CPU Power Scheme (`powercfg`), Boot & Startup Apps.
     - *Linux*: Kernel sysctl, Storage/SSD mount options, Memory/zram, CPU Governor, Boot speed (`systemd-analyze`).
   - **Option 2: System Security Hardening & Posture**:
     - *Windows*: Windows Defender Firewall (Domain/Private/Public), Microsoft Defender Antivirus & PUA Protection, PowerShell ExecutionPolicy (`RemoteSigned`), UAC integrity, OpenSSH.
     - *Linux*: Firewall (`ufw`/`nftables`), SSH daemon, sysctl security flags, systemd sandboxing.
   - **Option 3: Package Managers & Runtimes**:
     - *Windows*: `winget` (sync interval, telemetry, direct WinINet downloader), `wsl` (WSL2 VM memory bounds, mirrored network), `cargo`, `mise`, `bun`, `node`, `docker`.
     - *Linux*: `pacman`, `yay`, `makepkg`, `flatpak`, `cargo`, `podman`, `mise`.
   - **Option 4: Web Browsers & Terminal / Desktop**:
     - *Windows*: `windows-terminal` (GPU Atlas engine, default profile, disable animations), `brave`, `chrome`, `edge`, `firefox`.
     - *Linux*: `kde-plasma`, `brave`, `librewolf`, `firefox`.
   - **Option 5: Developer & CLI Tools**:
     - Cross-platform: `pwsh`, `bash`, `topgrade`, `git`, `neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `lazygit`, `ffmpeg`, `mpv`, `yt-dlp`, `rustdesk`, `controld`, `pi`, `herdr`.
   - **Option 6: Curated Top Balanced Recommendations** (High-impact cross-cutting set combining System, Security, and Tools).
   - **Option 7: Full System Optimization (Comprehensive)** (Full evaluation and optimization across ALL detected system domains, security posture, and developer toolchain: `storage`, `defender`, `firewall`, `winget`, `wsl`, `windows-terminal`, `pwsh`, `bash`, `topgrade`, `mise`, `ripgrep`, `zoxide`, `eza`, `pi`, `lazygit`, `neovim`, `bat`, `fzf`, `starship`, `git`, `mpv`, `yt-dlp`, `powertoys`, `herdr`).
   - **Option 8: Custom Selection** (User enters specific domains or tool names).
   - **Option 9: None / Cancel**.
3. **Execute Selected Set**: Proceed through the 6-phase optimization pipeline for each chosen target.

---

## Full Optimization Workflow (Option 7 & `/skill:system-optimizer full`)

When **Full Optimization** is selected, the skill systematically orchestrates the Triad across five sequential tiers, ensuring complete system-wide balance, security hardening, and cross-tool synergy:

1. **Tier 1: System Core & OS Baseline**:
   - NVMe/SSD TRIM verification (`fsutil DisableDeleteNotify = 0`), volume health checks, and 8.3 short name deactivation on secondary data drives.
   - Memory Compression activation (`Enable-MMAgent -mc` or zram) to prevent SSD paging lockups.
   - Power plan alignment (`powercfg`) ensuring maximum responsiveness on AC.
   - Startup application audit (pruning unneeded background updaters and telemetry daemons).

2. **Tier 2: System Security Hardening**:
   - Windows Defender Firewall profile enforcement (Domain/Private/Public active with default BlockInbound).
   - Antivirus & Exploit Guard hardening: Enable Potentially Unwanted Application (PUA) Protection (`Set-MpPreference -PUAProtection 1`).
   - PowerShell script execution hardening: Enforce `ExecutionPolicy RemoteSigned` for `CurrentUser`.
   - Package manager supply chain security: Enforce `winget` hash verification and malware scan overrides remaining disabled.

3. **Tier 3: Subsystems & Package Orchestration**:
   - **`winget`**: Configure `%LOCALAPPDATA%\Packages\Microsoft.DesktopAppInstaller_*\LocalState\settings.json` with 2-hour source sync (`autoUpdateIntervalInMinutes: 120`), direct WinINet downloader, and telemetry disabled.
   - **`wsl`**: Configure `~/.wslconfig` with memory bounding (50% host RAM / 8GB), `autoMemoryReclaim=dropcache`, `sparseVhd=true`, `dnsTunneling=true`, and `networkingMode=mirrored`.
   - **`mise`**: Configure `~/.config/mise/config.toml` (or `%LOCALAPPDATA%\mise\config.toml`): thread concurrency (`jobs = $(nproc)`), environment caching (`env_cache = true`, `env_cache_ttl = "1h"`), version pinning (`pin = true`), pre-compiled Rust binaries (`cargo.binstall = true`), storage hygiene (`cache_prune_age = "7d"`, `always_keep_download = false`), native Windows PE shims (`windows_shim_mode = "exe"`), and supply-chain verification (`aqua.slsa = true`, `aqua.cosign = true`, `github_attestations = true`, `node.verify = true`).
   - **`cargo`**: Configure `~/.cargo/config.toml` with `build.jobs = $(nproc)`, `net.git-fetch-with-cli = true`, sparse index registry protocol, and prefer pre-compiled binaries via `mise` (`cargo.binstall = true`) to prevent CPU-pegging from-source rebuilds.
   - **`topgrade`**: Configure `%APPDATA%\topgrade.toml` / `~/.config/topgrade.toml` to coordinate updates across `pacman`/`yay`/`winget`, `wsl`, `git`, `cargo`, and `mise` in one command, with `cleanup = true` (which triggers `mise prune`), `[mise] bump = true`, `jobs` aligned to CPU threads, redundant tool self-updaters and from-source recompilations disabled (`disable = ["uv", "cargo"]` when Rust CLIs are managed via `mise` binstall), and post-command `mise reshim` to synchronize binary shims.
4. **Tier 4: Terminal & Shell Environment**:
   - **`windows-terminal`**: Enable GPU-accelerated Atlas text rendering engine, `disableAnimations: true`, `copyFormatting: "none"`, default profile set to PowerShell 7, Hack Nerd Font.
   - **`pwsh` (PowerShell 7)**: Configure `$PROFILE` with PSReadLine predictive IntelliSense (`Set-PSReadLineOption -PredictionSource HistoryAndPlugin -PredictionViewStyle ListView`), deferred module loading, and history deduplication.
   - **`bash`**: Sanitize `$PATH`, set safe umask, configure history deduplication, and pre-cache static prompt hooks.

5. **Tier 5: Developer & Media Toolchain**:
   - **`neovim` (`nvim`)**: Verify byte-compiled Lua loader (`vim.loader.enable()` in `init.lua`), configure mise shims PATH safety guard, integrate single-source polyglot LSP & formatters via `mise` (`pyright`, `ruff`, `biome`, `rust-analyzer`), configure `mason.nvim` with `PATH = "append"` to prevent shadowing project-pinned tools, persistent undo (`undofile`), clipboard provider, telescope integration with `ripgrep`/`fzf`, and disable insecure modelines (`vim.opt.modeline = false`).
   - **`lazygit`**: Configure `%APPDATA%\lazygit\config.yml` with `git.autoFetch: false` (eliminates background git processes triggering Defender scans), Neovim RPC remote-tab editing (`nvim --server "$NVIM" --remote-tab "$FILE"`), and terminal-synchronized theme palette.
   - **`ripgrep` (`rg`)**: Configure `RIPGREP_CONFIG_PATH` with threads dynamically aligned to detected CPU logical cores (`--threads=$(nproc)`), `--smart-case`, `--max-columns=300` preview, `--mmap` for NVMe SSDs, and global ignore globs (`!.git`, `!node_modules`, `!target`).
   - **`zoxide`**: Configure fast directory jumping (`z`, `zi`), set `_ZO_EXCLUDE_DIRS` for system/temp roots, initialize shell hooks in `$PROFILE` and `.bashrc`, and prune stale directories.
   - **`eza`**: Define standard ergonomic aliases in `pwsh` and `bash` (`ls`, `ll`, `la`, `lt`) with icons and header, binding git status strictly to detailed listings to avoid recursive tree slowdowns.
   - **`bat` & `fzf`**: Set `FZF_DEFAULT_COMMAND` to multithreaded `fd --type f --hidden --exclude .git`, configure `bat` syntax pager with inferred terminal theme or user-selected palette.
   - **`starship`**: Configure `command_timeout = 500ms`, enable native `[mise]` module for zero-latency polyglot runtime indication, disable slow per-language subshell version modules (`nodejs`, `python`, `rust`, `golang`), and pre-cache prompt evaluation in `bash` and `pwsh`.
   - **`git`**: Configure `core.fscache = true`, `core.preloadIndex = true`, `core.untrackedCache = true`, `diff.algorithm = histogram`, `push.autoSetupRemote = true`, and Git Credential Manager (`credential.helper = manager`).
   - **`mpv` & `yt-dlp`**: Configure `vo=gpu-next`, `gpu-api=d3d11` (or `vulkan`), hardware decoding tailored to detected GPU (`hwdec=nvdec-copy` on NVIDIA RTX, `d3d11va`/`vaapi` on AMD/Intel), native HDR passthrough (`target-colorspace-hint=yes`), BT.2446a tone-mapping, and multithreaded fragment downloads in yt-dlp.
   - **`pi`**: Enforce `auth.json` 0600 permissions, configure session file archiving (>30d), compaction token reserve tuning (`16384`), tool access boundaries, and ensure `mise` shims (`~/.local/share/mise/shims` or `%LOCALAPPDATA%\mise\shims`) are active in agent execution environments to prevent non-interactive "command not found" errors.
   - **`rustdesk` & `controld`**: Configure hardware video encoding tailored to GPU (NVENC/D3D/AMF/VA-API), custom relay server, and encrypted DNS transport (DoQ/DoH) with in-memory caching.
   - **`herdr`**: Audit and rotate `herdr-server.log` (prune log bloat from long agent runs); verify `default_shell = "pwsh"` or `/bin/bash`; synchronize theme with inferred terminal palette; configure system toast notifications (`delivery = "system"`); ensure multiplexed agent workspaces inherit active `mise` shims and pinned project toolchains; protect socket (`0600`) and workspace directory permissions (`0700`).
   - **`gh` (GitHub CLI)**: Configure `git_protocol: ssh` (or `https`), `pager: "bat --color=always --style=plain"` for fast syntax reviews, configure `gh auth setup-git` for zero-credential prompting, enable `prompt: enabled`, configure standard aliases (`co: "pr checkout"`, `pv: "pr view"`), audit installed extensions (`gh extension list`), restrict `hosts.yml` permissions to `0600`, and integrate with Topgrade and AI agent workflows.
   - **`powertoys`**: Disable unused background utility modules to reclaim RAM and thread handles.

6. **Cross-Tool Synergies**:
   - Establish seamless pipelines between tools:
     - `herdr` + `pi` + `mise` + `pwsh`/`bash`: Autonomous AI coding agent toolchain inheritance — ensures non-interactive agent task subshells (`bash -c`, `pwsh -Command`) inherit active mise shims and project-pinned runtimes (`node`, `python`, `rust`, `go`, `uv`) without PATH drift or manual exports; worktree branch isolation; multiplexed agent panes; and automated socket permission hardening (`0600`/`0700`).
     - `lazygit` + `neovim` + `bat`: Remote tab editing & dependency-free syntax diff paging — configure lazygit to use `nvim --server` / remote tab editing to prevent nested editor spawns, and configure pager: `"bat --color=always --style=changes"` for fast syntax-highlighted diffs without extra pager dependencies.
     - `ripgrep` + `fzf` + `bat`: High-performance search & preview pipeline — wire `rg` as the backend search generator for fzf (`FZF_DEFAULT_COMMAND`), with `bat` rendering line-numbered, syntax-highlighted previews for files and code hits.
     - `mpv` + `yt-dlp` + GPU HWDEC: Web stream hardware passthrough — stream web video directly to mpv via yt-dlp, using native hardware decoding (`nvdec-copy` on NVIDIA RTX, `vaapi` on Intel/AMD, `d3d11va` on Windows) and D3D11/Vulkan color management (`vo=gpu-next`), bypassing heavy browser CPU/RAM consumption.
     - `winget` + `wsl` + `windows-terminal`: Windows 11 unified subsystem & terminal acceleration — align WinGet download concurrency, WSL2 mirrored networking / memory bounding (`autoMemoryReclaim=dropcache`, `sparseVhd=true`), and Windows Terminal Atlas GPU text rendering engine (`useAtlasEngine=true`).
     - `gh` + `git` + `lazygit` + `topgrade`: Seamless credential helper & PR review synergy — `gh auth setup-git` registers GitHub CLI as Git's credential helper across CLI and LazyGit; LazyGit custom commands trigger `gh pr checkout` and `gh pr view`; `gh` pager delegates to `bat` for zero-latency syntax-highlighted code reviews; and Topgrade automates `gh extension upgrade --all` during workstation maintenance.
     - `neovim` + `mise`: Single-source polyglot LSP & formatter runtime — Neovim consumes language servers (`pyright`, `ruff`, `biome`, `rust-analyzer`, `gopls`) and formatters directly from mise shims without Mason duplication; Mason `PATH = "append"` ensures project-pinned tools take precedence; Topgrade automatically updates runtimes and syncs shims via `[post_commands]` `mise reshim`.
     - `windows-terminal` + `pwsh` + `starship` + `zoxide` + `fzf`: Instant prompt rendering, fuzzy path completion, and interactive history navigation.
     - `topgrade` + `mise`: Unified workstation maintenance orchestration — strict separation of OS package managers (`pacman`/`yay`/`winget`) from user polyglot toolchains (`node`, `python`, `rust`, `uv`); hardware CPU thread budget alignment; collision prevention by disabling redundant standalone updaters in Topgrade (`disable = ["uv"]`); automated cache and old version reclamation via Topgrade `cleanup = true` and `mise prune`; and instantaneous binary shim and language server synchronization via Topgrade `[post_commands]` executing `mise reshim`.
     - `mise` + `starship` + `bash`/`pwsh`: Zero-latency prompt integration — native `[mise]` module in `starship.toml` displays active toolchain without spawning slow per-language subshell queries; mise `env_cache = true` (`1h` TTL) guarantees sub-millisecond shell prompt redraws on directory transitions.
     - `topgrade` + `cargo` + `mise`: Rust tooling compilation de-duplication — Rust CLI tools (`ripgrep`, `eza`, `bat`, `starship`, `zoxide`) managed via `mise` with `cargo.binstall = true` fetch pre-compiled binaries in seconds; Topgrade's from-source `cargo-update` step is disabled (`disable = ["cargo"]`), eliminating CPU-pegging compilations and hours of rebuild time during workstation updates.
     - `podman` + `lazydocker`: Rootless OCI container orchestration via crun runtime, user namespace isolation, UNIX socket forwarding, and interactive TUI monitoring without privileged root daemon exposure.
     - `htop` + `btop`: Unified hardware thread and memory inspection, low-overhead sensor polling, update delay tuning, and process hierarchy inspection aligned with CPU/RAM tiers.

---

## 6-Phase Execution Pipeline

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. Probe Hardware & Baseline (hardware-probe.sh, system-probe.sh)      │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 2. Audit Security Posture & State (security-audit.sh, target-inspect)  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 3. Research Upstream Docs, Changelogs & Security Standards             │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 4. Triad Optimization: Performance + Configuration + Security          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 5. Verification, Dry-Runs & Health Checks                              │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 6. Update ~/.config/system-optimizer/ Memory & Present Summary Report  │
└────────────────────────────────────────────────────────────────────────┘
```

---

### Phase 1: Hardware & System Probing

Run `<skill_dir>/scripts/hardware-probe.sh` and `<skill_dir>/scripts/system-probe.sh`.

Extract host boundaries:
- **CPU & Architecture**: Physical cores, logical threads (`nproc` / CIM logical processors), CPU power plan / scaling governor, microcode / firmware state.
- **Memory & Swap / Pagefile Tier**:
  - *Low (<= 4GB)*: Enforce strict application memory ceilings, configure aggressive memory compression (`Enable-MMAgent -mc` or Linux `zram-generator`), bound worker pools strictly to logical cores.
  - *Medium (4GB - 16GB)*: Balanced worker pools (`threads * 2` for I/O tasks), standard caching, WSL memory cap at 4GB-8GB.
  - *High (> 16GB)*: Aggressive in-memory caching, memory-mapped I/O, generous tool buffers, WSL memory cap at 8GB-12GB.
- **GPU & Video Acceleration**: Detect integrated/discrete GPU (e.g. NVIDIA RTX series, AMD Radeon, Intel Arc/Iris), DirectX / Direct3D 11/12, Vulkan, VA-API, Hardware-accelerated GPU scheduling (HAGS).
- **Storage Type & Volumes**: Identify NVMe/SSD vs HDD via `Get-PhysicalDisk` or `lsblk`, verify SSD TRIM status (`fsutil DisableDeleteNotify` or `fstrim.timer`).
- **Startup Metrics**: Check startup application count, boot duration, and stopped/failed system services.

---

### Phase 2: Target Inspection & Security Auditing

For each target domain or tool:
1. Run `<skill_dir>/scripts/target-inspect.sh <target>` and `<skill_dir>/scripts/security-audit.sh`.
2. Determine:
   - For **System domains**: Current storage TRIM state, volume health, power scheme, firewall profile states (Domain/Private/Public), Defender real-time & PUA protection, listening network sockets.
   - For **Tools/Packages**: Binary path, version, config file locations (`%APPDATA%`, `%LOCALAPPDATA%`, `~/.config`, `/etc`), origin package manager, active security/sandboxing posture.

---

### Phase 3: Research Upstream & Security Standards

1. Check upstream repositories, release notes, and documentation for:
   - WinGet settings schemas (`https://aka.ms/winget-settings.schema.json`), Windows Terminal documentation, WSL configuration directives, PowerShell best practices.
   - New features, flags, and recommended defaults.
   - Security advisories (CVEs, Microsoft Defender Exploit Guard guidelines, CIS Windows/Linux hardening guidelines).

---

### Phase 4: Apply Triad Optimization (Performance, Config, Security)

Always apply improvements across all three pillars:

#### 1. Performance
- **Concurrency & Parallelism**: Align package downloads, topgrade step concurrency (`[mise] jobs = $(nproc)`), mise jobs (`jobs = $(nproc)`), compilation flags (`cargo jobs`), and ripgrep/fd worker threads to detected CPU logical threads.
- **Storage & I/O**: Ensure NVMe/SSD TRIM is enabled (`DisableDeleteNotify=0`), disable 8.3 short filename generation on data volumes, configure WSL `sparseVhd=true` to automatically shrink virtual disks on file deletion.
- **Memory & Caching**: Enable Windows Memory Compression (`Enable-MMAgent -mc`) or Linux zram; bound WSL2 VM memory in `~/.wslconfig` based on host RAM tier (e.g. 50-60% of host RAM) with `autoMemoryReclaim=dropcache`.
- **Hardware Acceleration**: Enable Atlas GPU text rendering in Windows Terminal; configure `mpv` video output and hardware decoding dynamically tailored to detected GPU (`vo=gpu-next` + `gpu-api=d3d11`/`vulkan` with `hwdec=nvdec-copy` on NVIDIA, `hwdec=d3d11va` on AMD/Intel Windows, `hwdec=vaapi` on Linux, conservative `vo=gpu` on low-power iGPUs) and native HDR presentation when supported.
- **Tool Launch & Hook Latency**: Eliminate repetitive network queries and startup syncs (e.g. `winget` `autoUpdateIntervalInMinutes: 120`; `mise` `env_cache = true` with `1h` TTL and `fetch_remote_versions_cache = "1h"`; static starship prompt caching in `pwsh` and `bash`).
- **Binary Pre-compilation**: Enable `cargo.binstall = true` in `mise` to fetch pre-compiled binaries instead of compiling from source; use native Windows PE shims (`windows_shim_mode = "exe"`).

#### 2. Configuration & Mandatory Pre-Modification Backups
- **Mandatory Safety Backups**:
  - BEFORE modifying or overwriting ANY existing configuration file, the skill **MUST** execute `<skill_dir>/scripts/backup-config.sh <config_file> <target> [description]`.
  - Backups are preserved in two locations:
    1. Central immutable store: `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak` with a `.meta` companion record (SHA256, original path, timestamp).
    2. Local in-place backup: `<config_file>.bak.<timestamp>` when the directory is user-writable.
  - The backup path, timestamp, and SHA256 checksum must be recorded in the per-target `MEMORY.md` under `## Backups & Rollback Ledger`.
  - Rollback is supported on demand via `<skill_dir>/scripts/backup-config.sh --restore <backup-path>`.
- **Modern Defaults**:
  - `winget`: Set rainbow progress bar, direct WinINet downloader, 2-hour source sync.
  - `windows-terminal`: Default profile to PowerShell 7 (`pwsh`) or WSL, `disableAnimations: true`, `copyFormatting: none`, Hack Nerd Font.
  - `pwsh`: PSReadLine `PredictiveSource HistoryAndPlugin`, `PredictionViewStyle ListView`, completion menus, starship/zoxide integration.
  - `wsl`: `networkingMode=mirrored`, `dnsTunneling=true`, `systemd=true`.
  - `topgrade`: Coordinated updates across `pacman`/`yay`/`winget`, `wsl`, `git`, `cargo`, `mise`; dedicated `[mise]` table (`bump = true`, jobs bound to `$(nproc)`); `cleanup = true` (triggers `mise prune`); post-command `mise reshim`; collision avoidance via `disable = ["uv", "cargo"]` when Rust CLIs are managed via mise binstall.
  - `mise`: Version pinning (`pin = true`), storage hygiene (`cache_prune_age = "7d"`, `always_keep_download = false`), runtime ergonomics (`node.corepack = true`, `python.uv_venv_auto = "source"`), pre-compiled Rust binaries (`cargo.binstall = true`), and companion integration with Topgrade.
  - `cargo`: Concurrency bound to `build.jobs = $(nproc)`, `registries.crates-io.protocol = "sparse"`, `net.git-fetch-with-cli = true`, global CLI utilities delegated to `mise` with `cargo.binstall = true`, and Topgrade from-source rebuild step disabled (`disable = ["cargo"]`).
  - `neovim`: Bytecode loader (`vim.loader.enable()`), mise shims PATH safety guard, Mason `PATH = "append"` de-duplication, persistent undo (`undofile`), and single-source polyglot LSP integration.
  - `pi`: Toolchain shim inheritance via active `mise` shims on subshell PATH, session lifecycle hygiene (>30d pruning), compaction reserve boundaries (`16384`), thinking budget alignment, and strict permission deny rules (`0600` `auth.json`, SSH/secrets deny).
  - `herdr`: Multiplexed AI workspace panes with persistent session resumption (`resume_agents_on_restore = true`), default shell bound to `/bin/bash` or `pwsh`, theme synchronization, system toast delivery, `mise` shims inheritance, and local UNIX socket security (`0600`).
  - `gh`: Set `git_protocol = "ssh"`, `pager = "bat --color=always --style=plain"`, `prompt = "enabled"`, configure `gh auth setup-git` for Git credential delegation, and automate extension upgrades via Topgrade.

#### 3. Security
- **System Hardening**:
  - *Windows*: Enable Microsoft Defender Potentially Unwanted Application (PUA) Protection (`Set-MpPreference -PUAProtection 1`), enforce all 3 Firewall profiles enabled with default BlockInbound, verify UAC `EnableLUA=1`.
  - *Linux*: Kernel attack surface reduction via `/etc/sysctl.d/99-system-hardening.conf` (`kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`, `net.ipv4.conf.all.rp_filter=1`).
- **Execution & Shell Security**: Enforce PowerShell `ExecutionPolicy RemoteSigned` to block downloaded unsigned scripts; scrub sensitive tokens from shell history.
- **Supply Chain & Package Integrity**:
  - `mise`: Enforce cryptographic provenance verification (`aqua.slsa = true`, `aqua.cosign = true`, `github_attestations = true`, `node.verify = true`), enforce `allow_root = false` to block root execution, protect `config.toml` permissions (`0600`).
  - `winget`: Ensure `InstallerHashOverride` and `BypassCertificatePinningForMicrosoftStore` remain `Disabled`, disable backend telemetry.
  - `pacman`: Ensure `SigLevel = Required DatabaseOptional`.
  - `cargo`: Enforce `Cargo.lock` checksum verification, `cargo-audit` and `cargo-vet` integration, `0600` config permissions.
  - `pi` / `herdr`: Enforce `0600` permissions on `auth.json`, `config.toml`, and socket files (`herdr.sock`), restrict workspace directory permissions (`0700`), and enforce path deny rules on private credential stores.
  - `gh`: Restrict `~/.config/gh/hosts.yml` permissions to `0600`, enforce least-privilege OAuth scopes, and audit installed extensions against supply-chain vulnerabilities.
- **SSH & Credential Security**: Restrict permissions on `~/.ssh` and private keys; ensure Windows OpenSSH Server is only active when explicitly required.

---

### Phase 5: Verification & Health Checks

1. Validate configuration syntax before applying or reloading (e.g. `winget settings`, `wsl --status`, `pwsh -NoProfile -Command ...`, `git config --list`).
2. Run tool verification commands and dry-runs to confirm zero regressions.
3. Verify service and subsystem health (stopped automatic services on Windows, `systemctl --failed` on Linux).

---

### Phase 6: Memory Persistence & Final Report

The skill MUST maintain persistent memory under `~/.config/system-optimizer/` as the single source of truth for host and toolchain status.

#### 1. Per-Target Memory (`~/.config/system-optimizer/<target>/MEMORY.md`)
Maintains:
- **Target Metadata**: Target name, category (system/package/terminal/shell/tool), version, config paths, timestamp.
- **Hardware Snapshot**: CPU threads, RAM tier, GPU driver, disk type.
- **Upstream & Security Standards**: Release highlights, CVE mitigations, best practices.
- **Applied Triad Optimizations**:
  - *Performance*: Concurrency, memory bounds, hardware acceleration, launch latency.
  - *Configuration*: Modern defaults, integrations, cleanup.
  - *Security*: Hardening flags, policies, permission restrictions.
- **Backups & Rollback Ledger**: Exact backup file paths, timestamps, SHA256 hashes, and restore commands.
- **Verification & Health Check**: Output of test runs or dry-runs.
- **Subsequent Run History**: Dated changelog of modifications.

#### 2. Master System Memory (`~/.config/system-optimizer/MASTER_MEMORY.md`)
The unified system-wide orchestrator:
- **1. System Hardware & OS Baseline**: Host specs, OS version/build, CPU threads, RAM tier, memory compression, GPU.
- **2. System Security Posture Baseline**: Firewall state, antivirus & PUA protection, execution policies, open ports.
- **3. Registered System Domains & Tools Table**: Complete matrix of all optimized system domains, tools, packages, and their Triad alignment status.
- **4. Cross-System & Cross-Tool Synergies**: Inter-tool coordination (`topgrade` package orchestration, `windows-terminal` + `pwsh` + `starship` + `fzf`/`zoxide`, `wsl` mirrored networking + host firewall, `mpv` + discrete GPU D3D11/NVDEC + HDR).
- **5. Global Resource & Security Budget**: Coordinated thread limits, RAM ceilings, storage hygiene policies, and security baselines.
- **6. Cumulative Optimization History Log**: Append-only dated ledger of all optimization runs.

#### 3. Present Final Report
Conclude every run with:
- **Triad Summary Table**: Detailed breakdown of Performance, Configuration, and Security improvements per target.
- **Verification Status**: Results of dry-runs, syntax checks, and service status.
- **Persistent Memory Confirmation**: Notification of updated records in `~/.config/system-optimizer/`.
- **Actionable Recommendations**: Next steps (e.g. terminal reload, PowerShell session restart, optional companion packages, security updates).

---

## Examples

### Example 1: Zero-Argument Run (Interactive Discovery Menu)
```bash
/skill:system-optimizer
```
Probes the host, detects Windows 11 with installed tools (`winget`, `windows-terminal`, `wsl`, `pwsh`, `mpv`, `topgrade`, `neovim`), and presents tailored choices.

### Example 2: Windows System Core & Security Hardening
```bash
/skill:system-optimizer storage defender
```
Checks NVMe SSD TRIM status, volume free space, Windows Defender Firewall profile states, Antivirus & PUA protection, and open network sockets.

### Example 3: Windows Terminal, Shell, and Subsystem
```bash
/skill:system-optimizer windows-terminal pwsh wsl
```
Optimizes Windows Terminal GPU Atlas rendering and styling, configures PowerShell 7 PSReadLine predictive IntelliSense, and tunes WSL2 VM memory bounding, disk compaction (`sparseVhd`), and mirrored networking.

### Example 4: Package Management & Media Playback
```bash
/skill:system-optimizer winget topgrade mpv
```
Tunes WinGet source sync interval and downloader engine, configures Topgrade cross-ecosystem updates, and optimizes mpv Direct3D11/Vulkan hardware video decoding (NVDEC/D3D11VA/VA-API) and HDR presentation dynamically tailored to host GPU architecture.


### Example 5: Polyglot Toolchains & Maintenance Orchestration (mise + topgrade)
```bash
/skill:system-optimizer mise topgrade
```
Evaluates host CPU thread concurrency and bounds both tools to `$(nproc)`, configures mise environment caching (`env_cache = true`) and supply-chain verification (SLSA/cosign), configures Topgrade with `[mise] bump = true`, enables `cleanup = true` (to auto-prune obsolete runtimes), adds `mise reshim` to `post_commands`, and disables conflicting standalone updaters (`disable = ["uv"]`).


### Example 6: Polyglot LSP Runtime & Editor Synergy (mise + neovim)
```bash
/skill:system-optimizer mise neovim
```
Configures Neovim with `vim.loader.enable()` for sub-100ms startup, ensures `mise` shims are active on `PATH`, configures `mason.nvim` with `PATH = "append"` to prevent shadowing project-pinned tools, and routes all language servers (`pyright`, `ruff`, `biome`, `rust-analyzer`) through `mise` with automated `topgrade` upgrade synchronization.


### Example 7: Zero-Latency Prompt & Shell Integration (mise + starship)
```bash
/skill:system-optimizer mise starship bash
```
Configures `starship.toml` with the native `[mise]` module, disables slow per-language subshell version queries (`[nodejs]`, `[python]`, `[rust]`), bounds prompt timeout to `500ms`, and activates `mise` in `.bashrc` or `$PROFILE` with `env_cache = true` for sub-millisecond directory transitions.


### Example 8: Rust Pre-compiled Binstall & Compilation De-duplication (mise + cargo + topgrade)
```bash
/skill:system-optimizer mise cargo topgrade
```
Enables `cargo.binstall = true` in mise for fast pre-compiled Rust binary management, bounds `~/.cargo/config.toml` concurrency to `$(nproc)`, configures Topgrade with `disable = ["cargo"]` to prevent redundant from-source `cargo-update` builds, and routes binary upgrades through `[mise] bump = true`.


### Example 9: Autonomous Coding Agent Toolchain & Workspace Synergy (mise + pi + herdr)
```bash
/skill:system-optimizer mise pi herdr
```
Ensures autonomous AI coding agent tasks (`pi`) and multiplexed workspaces (`herdr`) inherit active `mise` shims in non-interactive subshell runs (`bash -c`, `pwsh -Command`), eliminating toolchain drift and "command not found" errors on project runtimes (Node, Python, Rust, Go, UV); prunes agent log bloat; tunes compaction token reserves (`16384`); and enforces strict socket and authentication token security (`0600`/`0700`).

### Example 10: Broader Cross-Tool Workstation Synergies
```bash
/skill:system-optimizer lazygit neovim bat ripgrep fzf mpv yt-dlp winget wsl windows-terminal
```
Configures lazygit to use `nvim --server` / remote tab editing to prevent nested editor spawns, and routes diffs through `bat --color=always --style=changes` for lightweight syntax highlighting; wires ripgrep as the `FZF_DEFAULT_COMMAND` search generator with bat rendering line-numbered previews; configures mpv with yt-dlp and GPU hardware video decoding (`nvdec-copy`/`vaapi`/`d3d11va`) to stream web video directly and bypass browser CPU/RAM usage; and coordinates WinGet download concurrency, WSL2 mirrored networking / memory bounding (`autoMemoryReclaim=dropcache`), and Windows Terminal Atlas GPU text rendering.

### Example 11: GitHub CLI & Workstation Developer Workflow Synergy (gh + git + lazygit + bat + topgrade)
```bash
/skill:system-optimizer gh git lazygit bat topgrade
```
Configures `gh auth setup-git` to register GitHub CLI as Git's credential helper (`!gh auth git-credential`), enabling transparent authentication across CLI and LazyGit without password prompts; routes `gh` diff reviews through `bat --color=always --style=plain` for fast 24-bit syntax highlighting; sets `git_protocol = "ssh"`; configures PR workflow aliases; enforces `0600` permissions on `~/.config/gh/hosts.yml`; and orchestrates automated extension updates via Topgrade.
