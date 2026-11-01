# system-optimizer

[![CI](https://github.com/madmeira/system-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/madmeira/system-optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A hardware-aware, cross-platform system, runtime, and developer toolchain optimizer across **Performance**, **Configuration**, and **Security** — packaged as an agent skill for [Pi](https://github.com/mario-dn/pi), Claude Code, Codex, and other `.agents/skills`-compatible coding agents, with standalone Bash probe scripts.

| Agent | Invocation | Status |
|---|---|---|
| Pi | `/skill:system-optimizer [targets]` | Original target |
| Claude Code | `/system-optimizer [targets]` (skill folder `~/.claude/skills/system-optimizer/`) | Verified: `full` audit run on a Windows 11 VM (read-only) |
| Codex | Mention `system-optimizer` by name, or copy `SKILL.md` into `AGENTS.md` | Untested |

All probe, audit, and backup scripts in `scripts/` are plain Bash and can also be run directly from a terminal (`--json` supported on probes); script paths in the docs are relative to the skill folder.

## Table of Contents

- [Installation](#installation)
- [Quick Start & Usage](#quick-start--usage)
- [Safety Contract](#safety-contract)
- [Overview & How It Works](#overview--how-it-works)
- [Supported Targets](#supported-targets)
- [Cross-Platform & Hardware Scaling](#cross-platform--hardware-scaling)
- [Toolchain & Ecosystem Synergies](#toolchain--ecosystem-synergies)
- [Standalone CLI Scripts](#standalone-cli-scripts)
- [Persistent Memory Architecture](#persistent-memory-architecture)
- [Repository Structure](#repository-structure)
- [Testing & CI](#testing--ci)
- [License](#license)

## Installation

Install with the [`skills`](https://github.com/vercel-labs/skills) CLI:

```bash
npx skills@latest add madmeira/system-optimizer
```

The CLI finds `SKILL.md` at the root of the repository, then asks which agents to install for, whether the install is global (every project) or only for the current project, and whether to symlink (recommended) or copy. Agents that read `.agents/skills` (Pi, Codex, Cursor, Gemini CLI, and others) share one copy in `~/.agents/skills/system-optimizer`; Claude Code is linked to it from `~/.claude/skills/system-optimizer`. The installer warns when it overwrites an existing skill of the same name. Pass `-a <agent>` and `-g` to answer the first two prompts on the command line.

Manage installed skills later with:

```bash
npx skills list      # list installed skills
npx skills update    # fetch the latest version of installed skills
npx skills remove    # uninstall
```

`update` is a manual step: nothing refreshes the skill in the background.

To install by hand instead, clone or copy the whole skill folder (see [Repository Structure](#repository-structure)); every script in `scripts/` sources `scripts/lib.sh` next to it.

## Quick Start & Usage

Invoke the skill with no arguments for an interactive hardware/OS probe and a 9-option discovery menu, or pass one or more specific targets:

```bash
# 1. Interactive discovery menu (probes hardware, OS, and installed tools first)
/skill:system-optimizer

# 2. Audit and tune specific tools or synergy pipelines
/skill:system-optimizer neovim mise starship
/skill:system-optimizer git lazygit gh bat

# 3. Audit OS storage & security posture
/skill:system-optimizer storage security

# 4. Comprehensive 5-tier full workstation audit
/skill:system-optimizer full
```

*(In Claude Code, use `/system-optimizer [targets]` instead of `/skill:system-optimizer [targets]`.)*

When called **without arguments**, the skill probes your host and presents nine numbered options:
1. **System Core & OS Performance** (TRIM, memory compression/zram, CPU governor/power plan, boot & startup)
2. **System Security Hardening & Posture** (Firewall, Defender/PUA, sysctl, ExecutionPolicy, SSH, systemd sandboxing)
3. **Package Managers & Runtimes** (`winget`, `pacman`, `yay`, `makepkg`, `flatpak`, `wsl`, `podman`, `cargo`, `mise`)
4. **Web Browsers & Terminal / Desktop** (`windows-terminal`, `kde-plasma`, `brave`, `chrome`, `edge`, `librewolf`, `firefox`)
5. **Developer & CLI Tools** (`neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `zoxide`, `eza`, `lazygit`, `git`, `gh`, `mpv`, `yt-dlp`, `pi`, `herdr`, etc.)
6. **Curated Top Balanced Recommendations** (high-impact cross-cutting picks for your host)
7. **Full System Optimization (`full`)** (orchestrated across 5 sequential tiers)
8. **Custom Selection**
9. **None / Cancel**

## Safety Contract

Every invocation — including `full` — strictly enforces a five-rule safety contract:

1. **Audit first, read-only**: Hardware probes, security audits, and target inspections never modify system state.
2. **Propose, then wait**: Findings are presented as numbered proposals; only user-approved items are applied.
3. **Automatic backups with SHA-256 ledger**: Before editing any existing configuration file, `scripts/backup-config.sh` creates a timestamped backup and records its SHA-256 hash and restore command in `~/.config/system-optimizer/backups/backup_log.md`.
4. **No unattended privilege escalation**: The agent never runs `sudo`, edits root-owned files directly, or prompts for passwords; instead, it outputs the exact privileged command for you to review and run.
5. **Explicit confirmation for outward-facing actions**: Network installs, git pushes, PR creation, or external messages always require prior confirmation.

## Overview & How It Works

`system-optimizer` inspects, configures, hardens, and coordinates your workstation environment across three pillars — the **Optimization Triad**:

1. **Performance**: Thread concurrency (`nproc` / logical processors), RAM-tier caching bounds, GPU hardware acceleration (DirectX / D3D11 / NVDEC / Vulkan / VA-API), SSD TRIM & mount optimization, CPU power plans / scaling governors, memory compression (Windows MMAgent / Linux zram), and WSL2 / container resource limits.
2. **Configuration**: Modern upstream defaults, shell & editor ergonomics, cross-tool companion integrations, pruning of deprecated or conflicting flags, static shell startup caching, and automated update orchestration (`topgrade`, `winget`, `pacman`).
3. **Security**: Attack surface reduction (Microsoft Defender PUA & Exploit Guard / Linux `/etc/sysctl.d/` hardening), firewall verification (`ufw` / `nftables` / Defender Firewall), script execution policies (`pwsh` `RemoteSigned`), cryptographic supply-chain verification (`mise` SLSA/cosign, `pacman` `SigLevel`, `winget` hash checks), and least-privilege file/socket permissions (`0600` credentials & agent sockets).

The skill is **100% generic** and contains **no hardcoded hardware values**. Every run executes a **6-Phase Execution Pipeline**:

1. **Probe Hardware & Baseline** (`hardware-probe.sh`, `system-probe.sh`, `detect-targets.sh`)
2. **Audit Security Posture & Target State** (`security-audit.sh`, `target-inspect.sh`)
3. **Research Upstream Standards** (verify current syntax, deprecations, and CVEs)
4. **Propose & Apply Triad Optimizations** (backed up via `backup-config.sh`)
5. **Verification & Health Checks** (config syntax validation, dry-runs, service health)
6. **Memory Persistence & Final Report** (update `MEMORY.md` and `MASTER_MEMORY.md`)

## Supported Targets

`scripts/target-inspect.sh` and the optimization guide cover **44 targets** across system domains, OS platforms, and developer tools:

| Category | Targets |
|---|---|
| **System Domains** | `system`, `security`, `storage`, `network`, `full` |
| **Windows 11 / 10** | `winget`, `windows-terminal`, `wsl`, `pwsh`, `powertoys`, `defender` |
| **Linux** | `pacman`, `yay`, `makepkg`, `kde-plasma` (plus `systemd`, `sysctl`, `flatpak`, `ufw`/`nftables` via domain probes) |
| **Runtimes & Containers** | `mise`, `topgrade`, `cargo`, `python`, `podman`, `lazydocker` |
| **Editor, Shell & CLI** | `neovim`, `bash`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `zoxide`, `eza`, `sqlite3` |
| **Git & GitHub** | `git`, `gh`, `lazygit` |
| **AI Coding Agents** | `pi`, `herdr` |
| **Media, Sync & Network** | `mpv`, `yt-dlp`, `syncthing`, `rustdesk`, `controld`, `chrome`, `edge` |
| **System Monitors** | `btop`, `htop` |

## Cross-Platform & Hardware Scaling

### Operating Systems
- **Linux**: Systemd, sysctl kernel attack surface hardening, `pacman`/`yay`/`makepkg`, `apt`, `dnf`, `flatpak`, Rootless Podman, KDE Plasma, Wayland/X11.
- **Windows 11 / 10**: PowerShell 7 (`pwsh`) & Windows PowerShell, WinGet, WSL2, Windows Terminal, PowerToys, Microsoft Defender Antivirus & PUA protection, NTFS TRIM & 8.3 short-name policy.

### Hardware-Driven Decision Scaling

| Dimension | Scaling Behavior |
|---|---|
| **CPU Concurrency** | Dynamically probes `nproc` / `NumberOfLogicalProcessors` to bind compilation threads (`cargo`, `makepkg`), runtime jobs (`mise`, `topgrade`), and search worker threads (`ripgrep`, `fd`). |
| **RAM Tiers** | **Low (<= 4 GB)**: Constrains buffer caches (Git `pack.windowMemory = 256m`, WSL2 `1.5GB`), enables aggressive browser tab discarding, and leverages Linux zram / Windows Memory Compression.<br>**Medium (4–16 GB)**: Balanced caches and WSL2 allocation.<br>**High (> 16 GB)**: High-throughput in-memory caching and memory-mapped I/O (`--mmap`). |
| **Storage Media** | Probes NVMe/SATA SSD vs Rotational HDD. Activates periodic TRIM (`fstrim.timer` / `DisableDeleteNotify = 0`), WSL2 sparse VHDs (`sparseVhd = true`), and memory-mapped scans on SSDs while avoiding seek thrashing on HDDs. |
| **GPU Architecture** | Tailors hardware video decoding and rendering across NVIDIA (NVDEC/NVENC), AMD Radeon (AMF/VA-API), Intel (QSV/VA-API), and integrated low-power GPUs. |
| **Theme Policy** | **Zero Hardcoding**: Dynamically infers color palettes from your existing terminal, editor, or desktop configuration before aligning companion tool themes. |

## Toolchain & Ecosystem Synergies

- **`topgrade` + `mise`**: Separates OS package upgrades from user polyglot runtimes, disables redundant language updaters, and auto-reshims binaries after upgrades.
- **`mise` + `starship`**: Zero-latency prompt version display via the native `[mise]` module while detecting and removing redundant per-language prompt tokens (`$nodejs`, `$python`, `$rust`, etc.).
- **`neovim` + `mise`**: Single-source polyglot LSPs, formatters, linters, and debuggers via `mise` (`aqua:`/`go:`/`npm:`/`github:` backends, plus `rust` `rust-analyzer` component), Mason locked strictly to editor-only adapters (`PATH = "append"`, `opts_extend = {}`, `mason = false`), LazyVim v15+ compatibility checks, and async `DirChanged` `mise env --json` synchronization.
- **`topgrade` + `cargo` + `mise`**: Prebuilt Rust binary installs via `cargo.binstall = true`, disabling duplicate from-source `cargo-update` builds in Topgrade.
- **`lazygit` + `neovim` + `bat`**: Remote tab editing via `nvim --server` to prevent nested editor instances, paired with `bat --style=changes` syntax diff paging.
- **`ripgrep` + `fzf` + `bat`**: Fast, gitignore-aware fuzzy file and content search with line-numbered, syntax-highlighted previews.
- **`gh` + `git` + `lazygit` + `topgrade`**: Unified GitHub CLI credential delegation (`gh auth setup-git`), syntax-highlighted PR diffs, and automated CLI extension updates.
- **`herdr` + `pi` + `mise`**: Non-interactive agent subshell `mise` shim inheritance, UNIX socket hardening (`0600`), and stale session (>30d) hygiene.
- **`mpv` + `yt-dlp` + GPU**: Hardware-decoded streaming video (`hwdec=auto-safe`, `vo=gpu-next`) with strict TLS certificate verification.

## Standalone CLI Scripts

Every script in `scripts/` can be run directly without an AI agent for diagnostics, JSON reporting, or config backups:

```bash
# Hardware, OS, tool detection, and security posture probes (human-readable or --json)
./scripts/hardware-probe.sh --json
./scripts/system-probe.sh --json
./scripts/detect-targets.sh --json
./scripts/security-audit.sh --json

# Inspect one or more targets (or pass 'all')
./scripts/target-inspect.sh neovim mise starship
./scripts/target-inspect.sh all

# Back up a config file before editing, list backups, or restore from backup
./scripts/backup-config.sh ~/.gitconfig git "Enable delta/bat pager and fsmonitor"
./scripts/backup-config.sh --list
./scripts/backup-config.sh --restore ~/.config/system-optimizer/backups/git_.gitconfig.20260331_120000.bak ~/.gitconfig
```

## Persistent Memory Architecture

After applying approved optimizations, the skill maintains state under `~/.config/system-optimizer/` so future runs remain idempotent and aware of past decisions:

- **`~/.config/system-optimizer/<target>/MEMORY.md`**: Per-target record storing hardware snapshot, upstream standards, applied Triad settings, backup SHA-256 ledger, verification output, and run changelog.
- **`~/.config/system-optimizer/MASTER_MEMORY.md`**: Cross-system ledger tracking the host hardware/security baseline, registered targets matrix, active cross-tool synergies, global resource budget, and cumulative history.
- **`~/.config/system-optimizer/backups/`**: Timestamped `.bak` snapshots and `backup_log.md` audit trail.

## Repository Structure

```text
system-optimizer/
├── SKILL.md                          # Primary agent skill specification & 6-phase workflow
├── README.md                         # Project overview, usage & architecture documentation
├── LICENSE                           # MIT License
├── .gitignore                        # Git exclusion rules
├── .github/workflows/ci.yml          # Ubuntu + Windows CI (ShellCheck, JSON schema & smoke tests)
├── references/
│   └── optimization-guide.md         # Deep-dive target templates, Triad checklists & synergy recipes
├── scripts/
│   ├── lib.sh                        # Shared helpers (sourced by all scripts; keep alongside them)
│   ├── hardware-probe.sh             # Dynamic hardware probe (CPU, RAM tier, GPU, Disk, OS)
│   ├── system-probe.sh               # System configuration & OS health probe
│   ├── detect-targets.sh             # Installed CLI tool, runtime & package manager detector
│   ├── security-audit.sh             # OS security posture & supply-chain audit
│   ├── backup-config.sh              # Pre-modification backup, SHA-256 ledger & restore manager
│   └── target-inspect.sh             # Per-target configuration & cross-tool synergy inspector (44 targets)
└── tests/
    ├── backup-smoke.sh               # Backup, list, restore, and path-traversal safety tests
    ├── probe-fallback.sh             # Verifies probes report "unknown" when PowerShell is unavailable
    ├── inspect-smoke.sh              # Runs all 44 targets in a clean environment + synergy assertions
    ├── inspect-windows.sh            # Smoke test for Windows-specific targets on Windows runners
    ├── json-escape.sh                # Validates JSON escaping for quotes, backslashes & control chars
    └── windows-baseline.sh           # Manual helper to run all probes on a Windows host (Git Bash)
```

## Testing & CI

Run the test suite locally from the repository root:

```bash
bash tests/backup-smoke.sh
bash tests/probe-fallback.sh
bash tests/json-escape.sh
bash tests/inspect-smoke.sh
```

GitHub Actions (`.github/workflows/ci.yml`) runs on both `ubuntu-latest` and `windows-latest`, validating Bash syntax (`bash -n`), `shellcheck`, valid `--json` output across all probes with Python's `json.tool`, and all smoke tests.

## License

Released under the [MIT License](LICENSE).
