---
name: system-optimizer
description: Audits, tunes, hardens, and speeds up Windows and Linux systems, shells, terminals, browsers, package managers, runtimes, and CLI tools across Performance, Configuration, and Security. Use when the user wants to inspect or optimize OS settings (storage/TRIM, memory/zram, CPU/power, network, boot), security posture (Defender/PUA, firewall, sysctl, SSH, ExecutionPolicy), Windows/Linux environments (winget, windows-terminal, wsl, pwsh, powertoys, pacman, yay, makepkg, flatpak, podman, lazydocker, systemd, kde-plasma), browsers (brave, chrome, edge, firefox, librewolf), or developer tools (git, gh, lazygit, topgrade, mise, cargo, python, neovim, ripgrep, fd, zoxide, eza, starship, bat, fzf, mpv, yt-dlp, btop, htop, syncthing, sqlite3, rustdesk, controld, pi, bash, herdr). Run without arguments to probe hardware and present numbered tuning options.
license: MIT
compatibility: Requires bash >= 4.0; PowerShell 5.1+ or pwsh on Windows
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
6. **Say what was checked, per host.** Never write "no problem found" for a host, file or setting you did not read. Name each host and what was inspected on it; list what was not covered.

---

## Invocation by Agent

| Agent | How to invoke | Status |
|---|---|---|
| Pi | `/skill:system-optimizer [targets]` | Original target |
| Claude Code | `/system-optimizer [targets]`, or ask for it by name; skill folder `~/.claude/skills/system-optimizer/` | Verified: `full` audit run on a Windows 11 VM (read-only) |
| Codex | Mention `system-optimizer` by name, or copy this file into `AGENTS.md` | Untested |

Script paths below (`scripts/...`, `references/...`) are relative to the skill folder. The examples use the bare form `system-optimizer [targets]`; add your agent's prefix from the table.

## Invocation Modes

`system-optimizer` with no arguments audits the machine and offers numbered options. Targets can be combined (for example `system-optimizer mise topgrade`); more examples are in `references/optimization-guide.md` §9.

| Kind | Targets |
|---|---|
| Domains | `system`, `security`, `storage`, `network`, `full` |
| Windows | `winget`, `windows-terminal`, `wsl`, `pwsh`, `powertoys`, `defender` |
| Linux | `pacman`, `yay`, `makepkg`, `kde-plasma` |
| Browsers | `brave`, `chrome`, `edge`, `firefox`, `librewolf` |
| Runtimes & orchestration | `mise`, `topgrade`, `cargo`, `python`, `podman`, `lazydocker` |
| Editor, shell & git | `neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `zoxide`, `eza`, `sqlite3`, `bash`, `git`, `gh`, `lazygit` |
| Media, sync & remote | `mpv`, `yt-dlp`, `syncthing`, `rustdesk`, `controld` |
| Agents | `pi`, `herdr` |
| Monitors | `htop`, `btop` |

*(`tool-optimizer` is maintained as a transparent alias to this skill).*

---

## Zero-Argument / Auto-Detection Workflow

When invoked **without arguments**:

1. **Probe System & Tools**: Run `scripts/hardware-probe.sh`, `scripts/system-probe.sh`, and `scripts/detect-targets.sh`.
2. **Print the full numbered menu as text, then ask** (tailored to detected OS). Write all nine options below in the reply itself, one per line with its detected scope, before asking which to audit. A choice widget (buttons) can only hold two to four options, so use it at most as a shortcut for the top picks. It never replaces the text menu, and the user can answer with any number from 1 to 9. The options:
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
   - **Option 7: Full System Optimization (Comprehensive)** (Full evaluation and optimization across ALL detected system domains, security posture, and developer toolchain: `storage`, `system`, `security`, `defender`, `firewall`, `winget`, `pacman`, `yay`, `makepkg`, `wsl`, `podman`, `lazydocker`, `windows-terminal`, `kde-plasma`, `pwsh`, `bash`, `topgrade`, `mise`, `cargo`, `ripgrep`, `fd`, `zoxide`, `eza`, `pi`, `lazygit`, `neovim`, `bat`, `fzf`, `starship`, `git`, `gh`, `mpv`, `yt-dlp`, `btop`, `htop`, `syncthing`, `sqlite3`, `rustdesk`, `controld`, `powertoys`, `herdr`).
   - **Option 8: Custom Selection** (User enters specific domains or tool names).
   - **Option 9: None / Cancel**.
3. **Audit Selected Set**: Run the 6-phase pipeline for each chosen target as an audit, then present numbered proposals and apply only what the user approves (see Safety Contract).

---

## Full Optimization Workflow (Option 7 & `system-optimizer full`)

When **Full Optimization** is selected, the skill systematically orchestrates the Triad across five sequential tiers, ensuring complete system-wide balance, security hardening, and cross-tool synergy. Each tier is an audit followed by numbered proposals; nothing is applied without the user's approval (Safety Contract):

| Tier | Scope | Targets |
|---|---|---|
| 1. System core & OS baseline | TRIM, memory compression / zram, power plan / CPU governor, network, sysctl, startup audit | `storage`, `network`, `system` |
| 2. Security hardening | Firewall (`ufw`/`nftables`/Defender), Defender/PUA, sysctl hardening, execution policy, package integrity | `security`, `defender` |
| 3. Subsystems & package orchestration | Package managers, WSL, containers, runtimes, update coordination | `winget`, `pacman`, `yay`, `makepkg`, `wsl`, `podman`, `lazydocker`, `mise`, `cargo`, `python`, `topgrade` |
| 4. Terminal, desktop, browsers & shell | Terminal engine, desktop compositor, browsers, shell profiles, history | `windows-terminal`, `kde-plasma`, `pwsh`, `bash`, `brave`, `chrome`, `edge`, `firefox`, `librewolf` |
| 5. Developer, media & monitor toolchain | Editor, search, git, media, agents, monitors, sync & remote tools | `neovim`, `lazygit`, `ripgrep`, `fd`, `zoxide`, `eza`, `bat`, `fzf`, `starship`, `git`, `gh`, `mpv`, `yt-dlp`, `pi`, `herdr`, `btop`, `htop`, `syncthing`, `sqlite3`, `rustdesk`, `controld`, `powertoys` |

**Cross-tool synergies** (settings per pipeline in `references/optimization-guide.md` §10):

| Tools | Effect |
|---|---|
| `herdr` + `pi` + `mise` + shell | Agent subshells inherit mise shims and pinned runtimes; sockets `0600` |
| `lazygit` + `neovim` + `bat` | Remote tab editing, `bat` diff paging |
| `ripgrep` + `fzf` + `bat` | `rg`-backed fuzzy search with syntax previews |
| `mpv` + `yt-dlp` + GPU | Hardware-decoded web video outside the browser |
| `winget` + `wsl` + `windows-terminal` | Aligned downloads, WSL2 limits and GPU text rendering |
| `gh` + `git` + `lazygit` + `topgrade` | One credential helper, `bat` pager, automatic extension upgrades |
| `neovim` + `mise` | Single-source LSPs, formatters & linters via mise (`aqua:`/`go:`/`npm:`/`github:`), Mason locked to editor-only adapters (`opts_extend = {}`, `mason = false`), async `DirChanged` `mise env --json` sync |
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
1. Run `scripts/target-inspect.sh <target> [target2 ...]` (supports batching multiple targets in a single invocation) and `scripts/security-audit.sh`.
2. Determine:
   - For **System domains**: Current storage TRIM state, volume health, power scheme, firewall profile states (Domain/Private/Public), Defender real-time & PUA protection, listening network sockets.
   - For **Tools/Packages**: Binary path, version, config file locations (`%APPDATA%`, `%LOCALAPPDATA%`, `~/.config`, `/etc`), origin package manager, active security/sandboxing posture.

**Reading the output (the audit is only as good as what it reads):**
- **Findings vs advice.** Only tagged lines (`[OK]`, `[MISCONFIGURED]`, `[NOT CONFIGURED]`, `[WARNING]`...) and quoted `file:line:text` lines are findings. The block headed `Recommendations (advice only...)` is static text printed for every host. Never present it as an audit result.
- **Read the whole output.** Do not filter it by keywords such as `warn` or `recommend`: a wrong setting that carries no such word is lost. A target whose output has no tagged line was not audited. Read its config by hand (`grep` the shell startup files, `git config --list`, the tool's own `--show-config`) before saying it is fine.
- **Batches must fail loudly.** `target-inspect.sh a b c` prints `ERROR: target 'x' failed` on stderr and exits 1 if any target fails. Treat that as an unfinished audit, not as a result.

**More than one host** (the user says "here and on `<host>`"):
1. Run Phase 1 and 2 on every host. `scripts/remote-run.sh <host> <script.sh> [args]` runs a skill script over SSH (the scripts cannot be piped to `bash -s`: they find `lib.sh` through `BASH_SOURCE`).
2. Run `scripts/host-diff.sh <host>`. It compares shell startup files and tool configs between the hosts, with secrets redacted. A setting that differs between hosts is a finding on the weaker one, even when each host looks fine alone.
3. Report per host (Safety Contract 6). Anything asked for "on both" and done on only one is called out.

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
  - BEFORE modifying or overwriting ANY existing configuration file, the skill **MUST** execute `scripts/backup-config.sh <config_file> [config_file2 ...] <target> [description]` (supports single-file or multi-file batch backups for a target).
  - Backups are preserved in two locations:
    1. Central backup store (private, mode 700): `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak` with a `.meta` companion record (SHA256, original path, timestamp).
    2. Local in-place backup: `<config_file>.bak.<timestamp>` when the directory is user-writable (skipped automatically in scanned/drop-in config directories such as `/nvim/`, `*.d/`, `/systemd/`, or with `--no-in-place`).
  - The backup path, timestamp, and SHA256 checksum must be recorded in the per-target `MEMORY.md` under `## Backups & Rollback Ledger`.
  - Rollback is supported on demand via `scripts/backup-config.sh --restore <backup-path>`.
- **Modern Defaults & Synergies** *(read `references/optimization-guide.md` §3–§5 and §10 on demand for per-target config templates)*:
  - Align update orchestration (`topgrade` + `mise` + `winget`/`pacman`) so OS packages and user runtimes never duplicate rebuilds (`cargo.binstall = true`, `disable = ["uv", "cargo"]`, post-command `mise reshim`).
  - Eliminate nested processes and subshell lag (`lazygit` → `nvim --server`, `starship` native `[mise]` module with integer `command_timeout = 500`, `fzf` backed by `fd` or `rg` with `bat` previews, `neovim` `vim.loader.enable()` + Mason de-duplication).
  - Ensure non-interactive AI agent subshells (`pi`, `herdr`) inherit `mise` shims on `PATH` and prune stale session logs (>30d).

#### 3. Security
- **Privileged Changes (Safety Contract #4)**: Elevated Windows commands (`Enable-MMAgent -mc`, `Set-MpPreference -PUAProtection 1`, `Optimize-Volume -ReTrim`, `fsutil 8dot3name set`) and root-owned Linux configs (`/etc/sysctl.d/*`, `/etc/pacman.conf`, `/etc/ssh/sshd_config`) MUST NEVER be executed directly by the agent — present the exact command for the user to run.
- **System & Shell Hardening**: Verify all Firewall profiles active with BlockInbound default, Defender Real-Time & PUA protection, Linux sysctl kernel hardening (`kptr_restrict`, `dmesg_restrict`, `unprivileged_bpf_disabled`, `protected_fifos`/`regular`), PowerShell `RemoteSigned`, sanitized `PATH` (no `.` or empty entries), and scrubbed shell history.
- **Supply Chain & Least Privilege** *(details in `references/optimization-guide.md` §2 & §5)*: Enforce cryptographic verification (`mise` SLSA/cosign/attestations + `allow_root = false`, `winget` hash/cert checks enabled, `pacman` `SigLevel = Required DatabaseOptional`, `cargo` lockfile checksums) and `0600` permissions on credentials/sockets (`~/.ssh`, `gh/hosts.yml`, `pi/agent/auth.json`, `herdr.sock`).
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
- **Coverage**: Per host, which targets and files were actually read, and which were not (see Safety Contract 6).
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
