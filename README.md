# system-optimizer

[![CI](https://github.com/madmeira/system-optimizer/actions/workflows/ci.yml/badge.svg)](https://github.com/madmeira/system-optimizer/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A hardware-aware, cross-platform system, runtime, and developer toolchain optimizer across **Performance**, **Configuration**, and **Security** — packaged as an agent skill for [Pi](https://github.com/badlogic/pi-mono), Antigravity (`agy`), Claude Code, Codex, and other `.agents/skills`-compatible coding agents, with standalone Bash probe scripts.

| Agent | Invocation | Status |
|---|---|---|
| Pi | `/skill:system-optimizer [targets]` | Original target |
| Antigravity (`agy` / IDE / 2.0) | `/system-optimizer [targets]`, or ask for it by name (global `~/.gemini/config/skills/system-optimizer/` or workspace `.agents/skills/system-optimizer/`) | Verified: `agy` CLI, Linux & Windows 11 hosts |
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

#### Antigravity (`agy` / Antigravity IDE / Antigravity 2.0)

Antigravity discovers workspace skills under `<repo>/.agents/skills/system-optimizer/` and global skills via a one-level directory scan under `~/.gemini/config/skills/system-optimizer/` (a standalone `~/.gemini/config/skills.json` manifest is not expanded in place of the global directory scan):

- **Linux / macOS**: Symlink or copy the skill directory into `~/.gemini/config/skills/system-optimizer`:
  ```bash
  mkdir -p ~/.gemini/config/skills
  ln -s ~/.agents/skills/system-optimizer ~/.gemini/config/skills/system-optimizer
  ```
- **Windows**: Copy the skill directory (`SKILL.md`, `README.md`, `LICENSE`, `references/`, `scripts/`) into `%USERPROFILE%\.gemini\config\skills\system-optimizer\` as a real directory (avoid NTFS junctions/symlinks on Windows, which Go's `os.ReadDir` `DirEntry.IsDir()` check can skip).

When auditing host-wide targets outside the active workspace under Antigravity, enable `allowNonWorkspaceAccess` for trusted sessions and run probe/backup scripts with `BypassSandbox: true` (on Windows, invoke Git Bash via `"C:\Program Files\Git\bin\bash.exe"` with `BypassSandbox: true`, as the sandbox blocks MSYS2 `\BaseNamedObjects` initialization and `WindowsApps\bash.exe` resolves to WSL) so scripts observe the real host rather than sandbox overlays.

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
3. **Package Managers & Runtimes** (`winget`, `pacman`, `yay`, `makepkg`, `paccache`, `flatpak`, `wsl`, `podman`, `cargo`, `python`, `uv`, `mise`)
4. **Web Browsers & Terminal / Desktop** (`windows-terminal`, `kde-plasma`, `brave`, `chrome`, `edge`, `librewolf`, `firefox`)
5. **Developer & CLI Tools** (`neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `zoxide`, `eza`, `lazygit`, `git`, `gh`, `mpv`, `yt-dlp`, `pi`, `antigravity`, `herdr`, etc.)
6. **Curated Top Balanced Recommendations** (high-impact cross-cutting picks for your host)
7. **Full System Optimization (`full`)** (orchestrated across 5 sequential tiers)
8. **Custom Selection**
9. **None / Cancel**

## Safety Contract

Every invocation — including `full` — strictly enforces a six-rule safety contract:

1. **Audit first, read-only**: Hardware probes, security audits, and target inspections never modify system state.
2. **Propose, then wait**: Findings are presented as numbered proposals; only user-approved items are applied.
3. **Automatic backups with SHA-256 metadata**: Before editing any existing configuration file, `scripts/backup-config.sh` creates a mode-`0600` timestamped snapshot under `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak` alongside a `.bak.meta` SHA-256 companion record (inspectable via `--list` and restorable via `--restore`).
4. **No unattended privilege escalation**: The agent never runs `sudo`, launches elevated PowerShell, edits root-owned files directly, or prompts for passwords; instead, it outputs the exact privileged commands for review and suggests generating a user-owned elevated apply script at the end of the run.
5. **Explicit confirmation for outward-facing actions**: Network installs, git pushes, PR creation, or external messages always require prior confirmation.
6. **Per-host coverage honesty**: Never claim "no problem found" for a host, file, or setting that was not read; explicitly state what was inspected vs. not covered per host.

## Overview & How It Works

`system-optimizer` inspects, configures, hardens, and coordinates your workstation environment across three pillars — the **Optimization Triad**:

1. **Performance**: Thread concurrency (`nproc` / logical processors), RAM-tier caching bounds, GPU hardware acceleration (DirectX / D3D11 / NVDEC / Vulkan / VA-API), SSD TRIM & mount optimization, CPU power plans / scaling governors, memory compression (Windows MMAgent / Linux zram), and WSL2 / container resource limits.
2. **Configuration**: Modern upstream defaults verified against live installed binary schemas (`tool-drift-check.sh`), shell & editor ergonomics, cross-tool companion integrations, pruning of deprecated or conflicting flags, static shell startup caching, and automated update orchestration (`topgrade`, `winget`, `pacman`, `paccache`).
3. **Security**: Attack surface reduction (Microsoft Defender PUA & Exploit Guard / Linux `/etc/sysctl.d/` hardening), firewall verification (`ufw` / `nftables` / Defender Firewall), script execution policies (`pwsh` `RemoteSigned`), cryptographic supply-chain verification (`mise` SLSA/cosign/npm provenance/`minimum_release_age`, `pacman` `DownloadUser = alpm` & `SigLevel`, `winget` hash checks, `uv` `exclude-newer` & `uv audit`), and least-privilege permissions (`0600` credentials & agent sockets including `pi` `auth.json`/`mcp-auth.json`, `antigravity` `oauth_creds.json`/`mcp_config.json`, and `herdr.sock`).

The skill is **100% generic** and contains **no hardcoded hardware values**. Every run executes a **6-Phase Execution Pipeline** with a dynamic schema gate:

1. **Probe Hardware & Baseline** (`hardware-probe.sh`, `system-probe.sh`, `detect-targets.sh`)
2. **Audit Security Posture & Target State** (`security-audit.sh`, `target-inspect.sh`)
2.5. **Dynamic Schema & Version Drift Gate** (`tool-drift-check.sh` — live CLI/schema introspection flagging `[VERIFIED]`, `[VERSION AHEAD]`, `[SCHEMA DRIFT]`, `[DEPRECATED CONFIG]`)
3. **Research Upstream Standards & Live Schemas** (verify current syntax, deprecations, and CVEs)
4. **Propose & Apply Triad Optimizations** (backed up via `backup-config.sh`)
5. **Post-Apply Native Validation Gate & Health Checks** (`herdr config check`, `mise doctor`, `nvim --headless +q`, `bat --diagnostic`, `git config --list`, `sshd -t`; auto-rollback on validator failure)
6. **Memory Persistence, Final Report & Elevated Script Offer** (update `MEMORY.md` and `MASTER_MEMORY.md`, and offer a consolidated elevated apply script when privileged suggestions remain)

## Supported Targets

`scripts/target-inspect.sh` and the optimization guide cover **71 targets** across system domains, OS platforms, browsers, and developer tools:

| Category | Targets |
|---|---|
| **System Domains** | `system`, `security`, `storage`, `network`, `kernel`, `memory`, `cpu`, `boot`, `firewall`, `ssh`, `sandboxing`, `package-audit`, `full` |
| **Windows 11 / 10** | `winget`, `windows-terminal`, `wsl`, `pwsh`, `powertoys`, `defender`, `execution-policy`, `uac` |
| **Linux** | `pacman`, `yay`, `makepkg`, `paccache`, `flatpak`, `kde-plasma`, `dolphin`, `kate`, `konsole` (plus `systemd`, `sysctl`, `ufw`/`nftables` aliases) |
| **Web Browsers** | `brave`, `chrome`, `chromium`, `edge`, `firefox`, `librewolf`, `falkon` |
| **Runtimes & Containers** | `mise`, `topgrade`, `cargo`, `python`, `uv`, `podman`, `docker`, `lazydocker` |
| **Editor, Shell & CLI** | `neovim`, `bash`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `zoxide`, `eza`, `zstd`, `sqlite3` |
| **Git & GitHub** | `git`, `gh`, `lazygit` |
| **AI Coding Agents** | `pi`, `antigravity` (`agy`), `herdr` |
| **Media, Sync & Remote** | `mpv`, `ffmpeg`, `yt-dlp`, `syncthing`, `rustdesk`, `controld` |
| **System Monitors** | `btop`, `htop` |

## Cross-Platform & Hardware Scaling

### Operating Systems
- **Linux**: Systemd, sysctl kernel attack surface hardening, `pacman`/`yay`/`makepkg`, `apt`, `dnf`, `flatpak`, Rootless Podman, KDE Plasma, Wayland/X11.
- **Windows 11 / 10**: PowerShell 7 (`pwsh`) & Windows PowerShell, WinGet, WSL2, Windows Terminal, PowerToys, Microsoft Defender Antivirus & PUA protection, NTFS TRIM & 8.3 short-name policy.

### Hardware-Driven Decision Scaling

| Dimension | Scaling Behavior |
|---|---|
| **CPU Concurrency** | Dynamically probes `nproc` / `NumberOfLogicalProcessors` to bind compilation threads (`makepkg`), runtime jobs (`mise`, `topgrade`), while leaving `cargo`, `ripgrep`, and `fd` on their smarter built-in core auto-detection. |
| **RAM Tiers** | **Low (<= 4 GB)**: Constrains buffer caches (Git `pack.windowMemory = 256m`, WSL2 `1.5GB`), enables aggressive browser tab discarding, and leverages Linux zram / Windows Memory Compression.<br>**Medium (4–16 GB)**: Balanced caches and WSL2 allocation (`[experimental] autoMemoryReclaim=dropcache`).<br>**High (> 16 GB)**: Generous tool buffers (`sqlite3` `cache_size = -16000`) and higher WSL2 headroom. |
| **Storage Media** | Probes NVMe/SATA SSD vs Rotational HDD. Activates periodic TRIM (`fstrim.timer` / `DisableDeleteNotify = 0`) and avoids WSL2 `sparseVhd = true` (Microsoft documents `ext4.vhdx` corruption risk). |
| **GPU Architecture** | Tailors hardware video decoding (`vo=gpu-next`, `profile=high-quality`, zero-copy `hwdec=auto-safe`) across NVIDIA (NVDEC/Vulkan/D3D11), AMD Radeon (VA-API/D3D11VA), Intel (VA-API/D3D11VA), and legacy iGPUs (`vo=gpu` + `opengl`). |
| **Theme Policy** | **Zero Hardcoding**: Dynamically infers color palettes from your existing terminal, editor, or desktop configuration before aligning companion tool themes. |

## Toolchain & Ecosystem Synergies

- **`topgrade` + `mise`**: Separates OS package upgrades from user polyglot runtimes, disables redundant language updaters, and auto-reshims binaries after upgrades.
- **`mise` + `starship`**: Fast prompt integration via `mise` `env_cache = true` (`1h` TTL), `--print-full-init` cached hooks, and optional `[mise]` (`disabled = false`, `$symbol`/`$health`).
- **`neovim` + `mise`**: Single-source polyglot LSPs, formatters, linters, and debuggers via `mise` (`aqua:`/`go:`/`npm:`/`github:` backends, plus `rust` `rust-analyzer` component), Mason locked strictly to editor-only adapters (`PATH = "append"`, `opts_extend = {}`, `opts.servers.<srv>.mason = false`, `automatic_enable = false`), LazyVim v15/v16+ & native `vim.lsp.config`/`vim.lsp.enable` checks, and async `DirChanged` `mise env --json` synchronization.
- **`topgrade` + `cargo` + `mise`**: Prebuilt Rust binary installs via `cargo.binstall = true`, disabling duplicate standalone updaters (`disable = ["uv", "cargo", "pi"]`) in Topgrade.
- **`lazygit` + `neovim` + `bat`**: Remote tab editing via `os.editPreset: "nvim-remote"`, paired with `git.diffRenderers` running `bat --color=always --style=changes,numbers`.
- **`ripgrep` / `fd` + `fzf` + `bat`**: `.gitignore`-aware `fd --strip-cwd-prefix` / `rg --files` search with `fzf` (`--info=inline-right`) and `bat --theme=auto` previews.
- **`gh` + `git` + `lazygit` + `topgrade`**: HTTPS `gh auth setup-git` / SSH workflow, `bat` pager, and Topgrade's native `github_cli_extensions` step.
- **`herdr` + `pi` + `antigravity` + `mise`**: Non-interactive agent subshell `mise` shim inheritance, `herdr integration status` + `resume_agents_on_restore`, `herdr update --handoff`, and `0600` socket/auth hardening (`herdr.sock`, `auth.json`, `mcp-auth.json`, `oauth_creds.json`).
- **`mpv` + `yt-dlp` + GPU**: Hardware-decoded streaming video (`vo=gpu-next`, `profile=high-quality`, zero-copy `hwdec=auto-safe`, `yt-dlp-ejs` + `-N 4`) with strict TLS certificate verification.

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

# Live CLI/schema drift check against verified baseline & active user configs
./scripts/tool-drift-check.sh neovim mise starship herdr
./scripts/tool-drift-check.sh --json

# Back up a config file before editing, list backups, or restore from backup
./scripts/backup-config.sh ~/.gitconfig git "Enable delta/bat pager and fsmonitor"
./scripts/backup-config.sh --list
./scripts/backup-config.sh --restore ~/.config/system-optimizer/backups/git/.gitconfig.20260331-120000.bak ~/.gitconfig

# Audit another machine over SSH: run any read-only script there, then diff shell/tool configs
./scripts/remote-run.sh myserver target-inspect.sh eza git
./scripts/host-diff.sh myserver
```

`remote-run.sh` copies `scripts/` to a temporary folder on the host, runs the script from there and deletes the folder (the scripts find `lib.sh` next to themselves, so they cannot be piped to `bash -s`). `host-diff.sh` compares shell startup files and tool configs between this machine and the host, with best-effort redaction: export values are hidden except for paths and tool settings, and keys, tokens and URL credentials are masked. Review the output before sharing it. Both use SSH keys only (`BatchMode`) and never run `sudo`.

## Persistent Memory Architecture

After applying approved optimizations, the skill maintains state under `~/.config/system-optimizer/` so future runs remain idempotent and aware of past decisions:

- **`~/.config/system-optimizer/<target>/MEMORY.md`**: Per-target record storing hardware snapshot, upstream standards, applied Triad settings, backup SHA-256 ledger, verification output, and run changelog.
- **`~/.config/system-optimizer/MASTER_MEMORY.md`**: Cross-system ledger tracking the host hardware/security baseline, registered targets matrix, active cross-tool synergies, global resource budget, and cumulative history.
- **`~/.config/system-optimizer/backups/<target>/`**: Mode-`0700` per-target backup directories containing mode-`0600` `<filename>.<timestamp>.bak` snapshots and `.bak.meta` SHA-256 companion records (`backup-config.sh --list`).
- **`~/.config/system-optimizer/elevated/`**: Optional user-owned elevated apply scripts (`apply-elevated-<timestamp>.sh` mode `0700` on Linux, or `.ps1` on Windows) offered at the end of runs with privileged suggestions — featuring `--dry-run`/`-DryRun` previews, out-of-tree system backups (`/var/backups/system-optimizer/` or `%ProgramData%\system-optimizer\backups\`), pre-reload syntax checks, and rollback manifests.

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
│   ├── remote-run.sh                 # Run one of these scripts on another host over SSH
│   ├── host-diff.sh                  # Compare shell startup files & tool configs between two hosts (secrets redacted)
│   ├── target-inspect.sh             # Per-target configuration & cross-tool synergy inspector (71 targets)
│   └── tool-drift-check.sh           # Offline live CLI/schema introspection & config deprecation gate
└── tests/
    ├── test-env.sh                   # Shared test-isolation environment helpers (mise trust/shim resolution)
    ├── backup-smoke.sh               # Backup, list, restore, and path-traversal safety tests
    ├── probe-fallback.sh             # Verifies probes report "unknown" when PowerShell is unavailable
    ├── inspect-smoke.sh              # Runs all 71 targets in a clean environment + synergy assertions
    ├── drift-check-smoke.sh          # Verifies tool-drift-check.sh CLI, mock drift states & live JSON
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
bash tests/drift-check-smoke.sh
bash tests/inspect-windows.sh   # Runs on Windows (Git Bash)
```

GitHub Actions (`.github/workflows/ci.yml`) runs on both `ubuntu-latest` and `windows-latest`, validating Bash syntax (`bash -n`), `shellcheck`, valid `--json` output across all probes with Python's `json.tool`, and all smoke tests.

## License

Released under the [MIT License](LICENSE).
