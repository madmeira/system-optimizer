# system-optimizer

A hardware-aware, cross-platform system, runtime, and developer toolchain optimizer, packaged as an agent skill for [Pi](https://github.com/mario-dn/pi), Claude Code and Codex.

| Agent | Invocation | Status |
|---|---|---|
| Pi | `/skill:system-optimizer [targets]` | Original target |
| Claude Code | `/system-optimizer [targets]` (skill folder `~/.claude/skills/system-optimizer/`) | Verified: `full` audit run on a Windows 11 VM (read-only) |
| Codex | mention `system-optimizer` by name, or copy `SKILL.md` into `AGENTS.md` | Untested |

All scripts are plain bash and run on their own; script paths in the docs are relative to the skill folder.

## Overview

`system-optimizer` inspects, configures, hardens, and coordinates your workstation environment across three fundamental pillars: **Performance**, **Configuration**, and **Security**.

The skill is **100% generic** and contains **no hardcoded hardware values**. When executed, it dynamically probes the host hardware and operating system to tailor configuration parameters to the exact machine it runs on—seamlessly scaling between vintage, resource-constrained laptops and modern, high-core-count workstations.

## Cross-Platform & Hardware Support

### Operating Systems
- **Linux**: Systemd, sysctl kernel attack surface hardening, pacman/yay, apt, dnf, flatpak, KDE Plasma, Wayland/X11.
- **Windows 11 / 10**: PowerShell 7 / Windows PowerShell, WinGet, WSL2, Windows Terminal, PowerToys, Microsoft Defender PUA protection, NTFS TRIM & 8.3 name policy.

### Hardware-Driven Decision Scaling

| Dimension | Scaling Behavior |
|---|---|
| **CPU Concurrency** | Dynamically probes `nproc` / `NumberOfLogicalProcessors` to bind compilation threads (`cargo`, `makepkg`), runtime jobs (`mise`, `topgrade`), and search worker threads (`ripgrep`, `fd`). |
| **RAM Tiers** | **Low (<= 4 GB)**: Constrains buffer caches (Git `pack.windowMemory = 256m`, WSL2 `1.5GB`), enables aggressive tab discarding, and leverages zram / Windows Memory Compression.<br>**Medium (4–16 GB)**: Standard caches, balanced WSL2 allocation.<br>**High (> 16 GB)**: Aggressive in-memory caching and memory-mapped I/O (`--mmap`). |
| **Storage Media** | Probes NVMe/SATA SSD vs Rotational HDD. Activates TRIM (`fstrim.timer` / `DisableDeleteNotify = 0`), WSL2 sparse VHDs (`sparseVhd = true`), and memory-mapped scans on SSDs while disabling non-contiguous seek thrashing on HDDs. |
| **GPU Architecture** | Tailors video acceleration and color management across NVIDIA (NVDEC/NVENC), AMD Radeon (AMF/VA-API), Intel (QSV/VA-API), and integrated low-power graphics. |
| **Theme Policy** | **Zero Hardcoding**: Dynamically infers color palettes from terminal, editor, or tool configuration before applying consistent themes. |

## Toolchain & Ecosystem Synergies

- **`topgrade` + `mise`**: Workstation maintenance orchestration, separating OS package managers from user polyglot runtimes, disabling redundant updaters, and auto-reshimming.
- **`mise` + `starship`**: Zero-latency prompt version indication via native `[mise]` module, eliminating per-language subshell query delays.
- **`neovim` + `mise`**: Single-source polyglot LSPs, formatters, linters, and debuggers via `mise` (`aqua:`/`go:`/`npm:`/`github:` backends), Mason locked strictly to editor-only adapters (`PATH = "append"`, `opts_extend = {}`, `mason = false`), and async `DirChanged` `mise env --json` project environment synchronization.
- **`topgrade` + `cargo` + `mise`**: Rust binary pre-compilation via `cargo.binstall = true`, disabling redundant from-source `cargo-update` builds in Topgrade.
- **`lazygit` + `neovim` + `bat`**: Remote tab editing via `nvim --server` to prevent nested editor spawns, with `bat --style=changes` syntax diff paging.
- **`ripgrep` + `fzf` + `bat`**: High-performance fuzzy finding with line-numbered, syntax-highlighted previews.
- **`gh` + `git` + `lazygit` + `topgrade`**: GitHub CLI credential helper delegation (`gh auth setup-git`), syntax PR diff reviews, and automated extension maintenance.
- **`herdr` + `pi` + `mise`**: Autonomous AI coding agent toolchain inheritance in non-interactive subshells, socket hardening (`0600`), and session log hygiene.

## Repository Structure

```
system-optimizer/
├── SKILL.md                          # Primary agent skill specification & invocation rules
├── README.md                         # Architecture overview & documentation
├── .gitignore                        # Git exclusion rules
├── .github/workflows/ci.yml          # ShellCheck, probe JSON validation and the test scripts
├── references/
│   └── optimization-guide.md         # Reference guides, config templates & triad checklists
├── scripts/
│   ├── lib.sh                        # Shared helpers (sourced by the others; keep it next to them)
│   ├── hardware-probe.sh             # Dynamic hardware probe (CPU, RAM, GPU, Disk, OS)
│   ├── system-probe.sh               # System configuration & OS health probe
│   ├── detect-targets.sh             # Installed tool & package manager detection
│   ├── security-audit.sh             # Security posture & supply-chain audit
│   ├── backup-config.sh              # Pre-modification backup & rollback manager
│   └── target-inspect.sh             # Per-target configuration & synergy inspector
└── tests/
    ├── backup-smoke.sh               # Backup, list, restore and safety checks (temp dir only)
    ├── probe-fallback.sh             # Probes say "unknown" when PowerShell fails
    ├── inspect-smoke.sh              # Smoke test: all 44 targets of target-inspect.sh in a clean env
    ├── inspect-windows.sh            # Smoke test: Windows targets on a Windows host
    ├── json-escape.sh                # JSON stays valid for quotes, backslashes, newlines
    └── windows-baseline.sh           # Manual helper: run the probes on a Windows host (Git Bash)
```

Copy the whole skill folder: every probe script needs `scripts/lib.sh` next to it.
