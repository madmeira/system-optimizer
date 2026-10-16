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

## Safety Contract (applies to every mode, including `full`)

1. **Audit first, read-only.** Probes and inspections change nothing.
2. **Propose, then wait.** Present findings as numbered proposals; change only the items the user approves.
3. **Back up before editing.** Run `scripts/backup-config.sh <file> <target> "<why>"` before touching any existing file.
4. **Never run privileged commands yourself.** For `sudo`, root-owned files or passwords, give the user the exact command to run.
5. **Ask before anything outward-facing** (pushes, PRs, messages, installs from the network).

---

## Invocation by Agent

| Agent | How to invoke | Status |
|---|---|---|
| Pi | `/skill:system-optimizer [targets]` | Original target |
| Claude Code | `/system-optimizer [targets]`, or ask for it by name; skill folder `~/.claude/skills/system-optimizer/` | Files installed; full end-to-end run not yet verified |
| Codex | Mention `system-optimizer` by name, or copy this file into `AGENTS.md` | Untested |

Script paths below (`scripts/...`, `references/...`) are relative to the skill folder. The examples use the bare form `system-optimizer [targets]`; add your agent's prefix from the table.

## Invocation Modes

`system-optimizer` with no arguments audits the machine and offers numbered options. Targets can be combined (for example `system-optimizer mise topgrade`); more examples are in `references/optimization-guide.md` §9.

| Kind | Targets |
|---|---|
| Domains | `system`, `security`, `storage`, `full` |
| Windows | `winget`, `windows-terminal`, `wsl`, `pwsh`, `powertoys`, `defender` |
| Linux | `pacman`, `yay`, `kde-plasma` |
| Runtimes & orchestration | `mise`, `topgrade`, `cargo`, `podman`, `lazydocker` |
| Editor, shell & git | `neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `zoxide`, `eza`, `bash`, `git`, `gh`, `lazygit` |
| Media & remote | `mpv`, `yt-dlp`, `rustdesk`, `controld` |
| Agents | `pi`, `herdr` |
| Monitors | `htop`, `btop` |

*(`tool-optimizer` is maintained as a transparent alias to this skill).*

---

## Zero-Argument / Auto-Detection Workflow

When invoked **without arguments**:

1. **Probe System & Tools**: Run `scripts/hardware-probe.sh`, `scripts/system-probe.sh`, and `scripts/detect-targets.sh`.
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
3. **Audit Selected Set**: Run the 6-phase pipeline for each chosen target as an audit, then present numbered proposals and apply only what the user approves (see Safety Contract).

---

## Full Optimization Workflow (Option 7 & `system-optimizer full`)

When **Full Optimization** is selected, the skill systematically orchestrates the Triad across five sequential tiers, ensuring complete system-wide balance, security hardening, and cross-tool synergy. Each tier is an audit followed by numbered proposals; nothing is applied without the user's approval (Safety Contract):

| Tier | Scope | Targets |
|---|---|---|
| 1. System core & OS baseline | TRIM, memory compression, power plan, startup audit | `storage`, `system` |
| 2. Security hardening | Firewall, Defender/PUA, execution policy, package integrity | `security`, `defender` |
| 3. Subsystems & package orchestration | Package managers, WSL, runtimes, update coordination | `winget`, `wsl`, `mise`, `cargo`, `topgrade` |
| 4. Terminal & shell | Terminal engine, shell profiles, history | `windows-terminal`, `pwsh`, `bash` |
| 5. Developer & media toolchain | Editor, search, git, media, agents, remote tools | `neovim`, `lazygit`, `ripgrep`, `zoxide`, `eza`, `bat`, `fzf`, `starship`, `git`, `gh`, `mpv`, `yt-dlp`, `pi`, `herdr`, `rustdesk`, `controld`, `powertoys` |

**Cross-tool synergies** (settings per pipeline in `references/optimization-guide.md` §10):

| Tools | Effect |
|---|---|
| `herdr` + `pi` + `mise` + shell | Agent subshells inherit mise shims and pinned runtimes; sockets `0600` |
| `lazygit` + `neovim` + `bat` | Remote tab editing, `bat` diff paging |
| `ripgrep` + `fzf` + `bat` | `rg`-backed fuzzy search with syntax previews |
| `mpv` + `yt-dlp` + GPU | Hardware-decoded web video outside the browser |
| `winget` + `wsl` + `windows-terminal` | Aligned downloads, WSL2 limits and GPU text rendering |
| `gh` + `git` + `lazygit` + `topgrade` | One credential helper, `bat` pager, automatic extension upgrades |
| `neovim` + `mise` | One source of language servers and formatters |
| `windows-terminal` + `pwsh` + `starship` + `zoxide` + `fzf` | Fast prompt, path jump and history search |
| `topgrade` + `mise` | OS packages and user runtimes updated separately, shims refreshed |
| `mise` + `starship` + shell | Native `[mise]` prompt module, no per-language subshells |
| `topgrade` + `cargo` + `mise` | Prebuilt Rust binaries, no duplicate from-source rebuilds |
| `podman` + `lazydocker` | Rootless containers with a TUI |
| `htop` + `btop` | Shared thread and memory inspection |

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

Run `scripts/hardware-probe.sh` and `scripts/system-probe.sh`.

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
1. Run `scripts/target-inspect.sh <target>` and `scripts/security-audit.sh`.
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

### Phase 4: Propose and Apply Triad Optimization (Performance, Config, Security)

Propose improvements across all three pillars, and apply only the items the user approved (Safety Contract):

#### 1. Performance
- **Concurrency & Parallelism**: Align package downloads, topgrade step concurrency (`[mise] jobs = $(nproc)`), mise jobs (`jobs = $(nproc)`), compilation flags (`cargo jobs`), and ripgrep/fd worker threads to detected CPU logical threads.
- **Storage & I/O**: Ensure NVMe/SSD TRIM is enabled (`DisableDeleteNotify=0`), disable 8.3 short filename generation on data volumes, configure WSL `sparseVhd=true` to automatically shrink virtual disks on file deletion.
- **Memory & Caching**: Enable Windows Memory Compression (`Enable-MMAgent -mc`) or Linux zram; bound WSL2 VM memory in `~/.wslconfig` based on host RAM tier (e.g. 50-60% of host RAM) with `autoMemoryReclaim=dropcache`.
- **Hardware Acceleration**: Enable Atlas GPU text rendering in Windows Terminal; configure `mpv` video output and hardware decoding dynamically tailored to detected GPU (`vo=gpu-next` + `gpu-api=d3d11`/`vulkan` with `hwdec=nvdec-copy` on NVIDIA, `hwdec=d3d11va` on AMD/Intel Windows, `hwdec=vaapi` on Linux, conservative `vo=gpu` on low-power iGPUs) and native HDR presentation when supported.
- **Tool Launch & Hook Latency**: Eliminate repetitive network queries and startup syncs (e.g. `winget` `autoUpdateIntervalInMinutes: 120`; `mise` `env_cache = true` with `1h` TTL and `fetch_remote_versions_cache = "1h"`; static starship prompt caching in `pwsh` and `bash`).
- **Binary Pre-compilation**: Enable `cargo.binstall = true` in `mise` to fetch pre-compiled binaries instead of compiling from source; use native Windows PE shims (`windows_shim_mode = "exe"`).

#### 2. Configuration & Mandatory Pre-Modification Backups
- **Mandatory Safety Backups**:
  - BEFORE modifying or overwriting ANY existing configuration file, the skill **MUST** execute `scripts/backup-config.sh <config_file> <target> [description]`.
  - Backups are preserved in two locations:
    1. Central backup store (private, mode 700): `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak` with a `.meta` companion record (SHA256, original path, timestamp).
    2. Local in-place backup: `<config_file>.bak.<timestamp>` when the directory is user-writable.
  - The backup path, timestamp, and SHA256 checksum must be recorded in the per-target `MEMORY.md` under `## Backups & Rollback Ledger`.
  - Rollback is supported on demand via `scripts/backup-config.sh --restore <backup-path>`.
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
system-optimizer
```
Probes the host, detects Windows 11 with installed tools (`winget`, `windows-terminal`, `wsl`, `pwsh`, `mpv`, `topgrade`, `neovim`), and presents tailored choices.

### Example 2: Windows System Core & Security Hardening
```bash
system-optimizer storage defender
```
Checks NVMe SSD TRIM status, volume free space, Windows Defender Firewall profile states, Antivirus & PUA protection, and open network sockets.

More examples (Examples 3-11) are in `references/optimization-guide.md` §11.
