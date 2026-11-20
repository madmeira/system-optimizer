---
name: system-optimizer
description: Audits, tunes, hardens, and speeds up Windows and Linux systems, shells, terminals, browsers, package managers, runtimes, and CLI tools across Performance, Configuration, and Security. Use when the user wants to inspect or optimize OS settings (storage/TRIM, memory/zram, CPU/power, network, boot), security posture (Defender/PUA, firewall, sysctl, SSH, ExecutionPolicy), Windows/Linux environments (winget, windows-terminal, wsl, pwsh, powertoys, pacman, yay, makepkg, paccache, flatpak, podman, docker, lazydocker, systemd, kde-plasma, dolphin, kate, konsole), browsers (brave, chrome, edge, firefox, librewolf, falkon), or developer tools (git, gh, lazygit, topgrade, mise, cargo, python, uv, neovim, ripgrep, fd, zoxide, eza, starship, bat, fzf, mpv, stremio, ffmpeg, zstd, yt-dlp, btop, htop, syncthing, sqlite3, rustdesk, controld, pi, antigravity, bash, herdr). Run without arguments to probe hardware and present numbered tuning options.
license: MIT
compatibility: Requires bash >= 4.0; PowerShell 5.1+ or pwsh on Windows
---

# System & Tool Optimizer

A comprehensive optimization skill for Windows and Linux systems, package managers, browsers, terminals, subsystems, and developer toolchains. It evaluates and tunes every target against the **Optimization Triad**:

1. **Performance**: Thread concurrency (`nproc` / logical processors), RAM-tier caching boundaries, GPU/hardware acceleration (DirectX / D3D11 / NVDEC / Vulkan / VA-API), storage/TRIM optimization, power plans / CPU scaling governors, memory compression (Windows MMAgent / Linux zram), and subsystem resource limits (WSL VM memory and vCPU).
2. **Configuration**: Sensible modern defaults verified against live installed binary schemas, workflow ergonomics, companion integrations, pruning obsolete items, static prompt/completion caching, and automated maintenance orchestration (`topgrade`, `winget`, `paccache`).
3. **Security**: Attack surface reduction (Windows Defender PUA & Exploit Guard / Linux sysctl hardening), firewall verification (Windows Defender Firewall / `ufw` / `nftables`), execution policies (`pwsh` RemoteSigned), SSH hardening, package signature verification (`winget` hash checks / `pacman` SigLevel), and least-privilege permissions.

---

## Safety Contract (applies to every mode, including `full`)

1. **Audit first, read-only.** Probes and inspections change nothing.
2. **Propose, then wait.** Present findings as numbered proposals; change only the items the user approves.
3. **Back up before editing.** Run `scripts/backup-config.sh <file> <target> "<why>"` before touching any existing file.
4. **Never run privileged commands yourself.** For `sudo`, Administrator PowerShell, root-owned files, or passwords, never execute them directly — present the exact commands in proposals and, at the end of the run, suggest creating a reviewable elevated apply script containing all pending privileged changes.
5. **Ask before anything outward-facing** (pushes, PRs, messages, installs from the network).
6. **Say what was checked, per host.** Never write "no problem found" for a host, file or setting you did not read. Name each host and what was inspected on it; list what was not covered.

---

## Invocation by Agent

| Agent | How to invoke | Status |
|---|---|---|
| Pi | `/skill:system-optimizer [targets]` | Original target |
| Antigravity (`agy` / IDE / 2.0) | `/system-optimizer [targets]`, or ask for it by name (global skill folder `~/.gemini/config/skills/system-optimizer/` or workspace `.agents/skills/system-optimizer/`) | Verified: `agy` CLI, Linux & Windows 11 hosts |
| Claude Code | `/system-optimizer [targets]`, or ask for it by name; skill folder `~/.claude/skills/system-optimizer/` | Verified: `full` audit run on a Windows 11 VM (read-only) |
| Codex | Mention `system-optimizer` by name, or copy this file into `AGENTS.md` | Untested |

Script paths below (`scripts/...`, `references/...`) are relative to the skill folder. The examples use the bare form `system-optimizer [targets]`; add your agent's prefix from the table.

**Antigravity terminal sandbox note**: Under Antigravity's default sandbox (`BypassSandbox: false`), `run_command` isolates host configuration paths outside the active workspace (such as `~/.gemini/config/` and `/etc`), and on Windows blocks MSYS2/Git Bash `\BaseNamedObjects` initialization (`0xC0000022`). Ensure `allowNonWorkspaceAccess` is enabled for host-wide audits outside the workspace, and run host probe/backup commands with `BypassSandbox: true` (on Windows, invoke `"C:\Program Files\Git\bin\bash.exe"` explicitly rather than the `WindowsApps\bash.exe` WSL stub, or use `read_file`/`write_file` directly for user-approved edits) so probes read the real host environment rather than sandbox overlays.

## Invocation Modes

`system-optimizer` with no arguments audits the machine and offers numbered options. Targets can be combined (for example `system-optimizer mise topgrade`); more examples are in `references/optimization-guide.md` §9.

| Kind | Targets |
|---|---|
| Domains | `system`, `security`, `storage`, `network`, `kernel`, `memory`, `cpu`, `boot`, `firewall`, `ssh`, `sandboxing`, `package-audit`, `full` |
| Windows | `winget`, `windows-terminal`, `wsl`, `pwsh`, `powertoys`, `defender`, `execution-policy`, `uac` |
| Linux | `pacman`, `yay`, `makepkg`, `paccache`, `flatpak`, `kde-plasma`, `dolphin`, `kate`, `konsole` |
| Browsers | `brave`, `chrome`, `chromium`, `edge`, `firefox`, `librewolf`, `falkon` |
| Runtimes & orchestration | `mise`, `topgrade`, `cargo`, `python`, `uv`, `podman`, `docker`, `lazydocker` |
| Editor, shell & git | `neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `zoxide`, `eza`, `zstd`, `sqlite3`, `bash`, `git`, `gh`, `lazygit` |
| Media, sync & remote | `mpv`, `stremio`, `ffmpeg`, `yt-dlp`, `syncthing`, `rustdesk`, `controld` |
| Agents | `pi`, `antigravity`, `herdr` |
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
     - *Windows*: `winget` (sync interval, telemetry, direct WinINet downloader), `wsl` (WSL2 VM memory bounds, mirrored network), `cargo`, `mise`, `uv`, `bun`, `node`, `docker`.
     - *Linux*: `pacman`, `yay`, `makepkg`, `paccache`, `flatpak`, `cargo`, `uv`, `podman`, `mise`.
   - **Option 4: Web Browsers & Terminal / Desktop**:
     - *Windows*: `windows-terminal` (GPU Atlas engine, default profile, disable animations), `brave`, `chrome`, `edge`, `firefox`.
     - *Linux*: `kde-plasma`, `brave`, `librewolf`, `firefox`.
   - **Option 5: Developer & CLI Tools**:
     - Cross-platform: `pwsh`, `bash`, `topgrade`, `git`, `neovim`, `starship`, `bat`, `fzf`, `ripgrep`, `fd`, `lazygit`, `ffmpeg`, `mpv`, `yt-dlp`, `rustdesk`, `controld`, `pi`, `antigravity`, `herdr`.
   - **Option 6: Curated Top Balanced Recommendations** (High-impact cross-cutting set combining System, Security, and Tools).
   - **Option 7: Full System Optimization (Comprehensive)** (Full evaluation and optimization across ALL detected system domains, security posture, and developer toolchain: `storage`, `system`, `security`, `defender`, `firewall`, `winget`, `pacman`, `yay`, `makepkg`, `paccache`, `wsl`, `podman`, `lazydocker`, `windows-terminal`, `kde-plasma`, `pwsh`, `bash`, `topgrade`, `mise`, `cargo`, `python`, `uv`, `ripgrep`, `fd`, `zoxide`, `eza`, `pi`, `antigravity`, `lazygit`, `neovim`, `bat`, `fzf`, `starship`, `git`, `gh`, `mpv`, `yt-dlp`, `btop`, `htop`, `syncthing`, `sqlite3`, `rustdesk`, `controld`, `powertoys`, `herdr`).
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
| 3. Subsystems & package orchestration | Package managers, WSL, containers, runtimes, update coordination | `winget`, `pacman`, `yay`, `makepkg`, `paccache`, `flatpak`, `wsl`, `podman`, `docker`, `lazydocker`, `mise`, `cargo`, `python`, `uv`, `topgrade` |
| 4. Terminal, desktop, browsers & shell | Terminal engine, desktop compositor, browsers, shell profiles, history | `windows-terminal`, `kde-plasma`, `pwsh`, `bash`, `brave`, `chrome`, `edge`, `firefox`, `librewolf` |
| 5. Developer, media & monitor toolchain | Editor, search, git, media, agents, monitors, sync & remote tools | `neovim`, `lazygit`, `ripgrep`, `fd`, `zoxide`, `eza`, `bat`, `fzf`, `starship`, `git`, `gh`, `mpv`, `yt-dlp`, `pi`, `antigravity`, `herdr`, `btop`, `htop`, `syncthing`, `sqlite3`, `rustdesk`, `controld`, `powertoys` |

**Cross-tool synergies** (settings per pipeline in `references/optimization-guide.md` §10):

| Tools | Effect |
|---|---|
| `herdr` + `pi` + `antigravity` + `mise` + shell | Agent subshells inherit mise shims, `herdr integration status`, session resume (`resume_agents_on_restore`), `0600` sockets/auth |
| `lazygit` + `neovim` + `bat` | Remote tab editing (`os.editPreset: "nvim-remote"`), `bat` diff paging via `git.diffRenderers` |
| `ripgrep` + `fzf` + `bat` | `rg`/`fd --strip-cwd-prefix`-backed fuzzy search with syntax previews (`--info=inline-right`) |
| `mpv` + `yt-dlp` + GPU | Hardware-decoded web video (`vo=gpu-next`, `hwdec=auto-safe`, `yt-dlp-ejs`) outside the browser |
| `winget` + `wsl` + `windows-terminal` | Aligned downloads, WSL2 limits and AtlasEngine GPU text rendering |
| `gh` + `git` + `lazygit` + `topgrade` | HTTPS `gh auth setup-git` / SSH workflow, `bat` pager, native Topgrade `github_cli_extensions` step |
| `neovim` + `mise` | Single-source LSPs/formatters/linters via mise, LazyVim v15/v16+ Mason lock (`opts.servers.<srv>.mason = false`, `opts_extend = {}`), native `vim.lsp.config`/`enable`, async `DirChanged` `mise env --json` |
| `windows-terminal` + `pwsh` + `starship` + `zoxide` + `fzf` | Fast `--print-full-init` cached prompt, path jump and history search |
| `topgrade` + `mise` | OS packages and user runtimes updated separately (`disable = ["uv", "cargo", "pi"]`), `mise reshim`, auto-prune |
| `mise` + `starship` + shell | Optional `[mise]` (`$symbol`/`$health`, `disabled = false`) or per-language modules + `env_cache = true` |
| `topgrade` + `cargo` + `mise` | Prebuilt Rust binaries (`cargo.binstall = true`), no duplicate from-source rebuilds |
| `podman` + `lazydocker` | Rootless containers (`pasta` networking, Quadlet units) with `podman.socket` TUI |
| `htop` + `btop` | Shared thread (`delay=20` / `update_ms = 2000`) and GPU/memory inspection |

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
│ 2.5. Dynamic Schema & Version Drift Gate (tool-drift-check.sh)         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 3. Research Upstream Docs, Live Schemas & Security Standards           │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 4. Triad Optimization: Performance + Configuration + Security          │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 5. Post-Apply Native Validation Gate, Dry-Runs & Health Checks         │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 6. Update Memory, Present Summary Report & Offer Elevated Apply Script │
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

### Phase 2.5: Dynamic Schema & Version Drift Gate

Run `./scripts/tool-drift-check.sh <targets>` (or `./scripts/tool-drift-check.sh --json` during full discovery / zero-argument runs). It compares installed binary versions against the skill's verified baseline manifest, executes fast (<2s, offline) live CLI/schema introspection (`mise settings ls`, `herdr --default-config` & `herdr config check`, `starship print-config --default`, `pi` `settings.schema.json`, `agy --help`, `mpv --vo=help`, and `--help` across `rg`/`fd`/`eza`/`fzf`/`bat`/`yt-dlp`/`syncthing`/`uv`/`gh`), and scans active user configs for deprecated or renamed keys, tagging results as `[VERIFIED]`, `[VERSION AHEAD]`, `[SCHEMA DRIFT]`, or `[DEPRECATED CONFIG]`:

- **Live schema verification gate**: Whenever any target reports `[VERSION AHEAD]` or `[SCHEMA DRIFT]`, or before proposing unfamiliar flags or config keys, you **MUST** verify the exact flag/key against the installed binary's live CLI schema (`<tool> --help`, `mise settings ls`, `starship print-config --default`, `herdr --default-config`, `lazygit --config`, `mpv --list-options`, `settings.schema.json`) and/or release notes. **NEVER** emit unverified static flags from memory.
- **Deprecated key surfacing**: Surface every `[DEPRECATED CONFIG]` finding directly in the Phase 4 Triad proposal table so the user can approve cleanup or migration.

---

### Phase 3: Research Upstream & Security Standards

1. Check upstream repositories, release notes, and live tool schemas (especially for any target flagged `[VERSION AHEAD]` or `[SCHEMA DRIFT]` in Phase 2.5):
   - WinGet settings schemas (`https://aka.ms/winget-settings.schema.json`), Windows Terminal documentation, WSL configuration directives, PowerShell best practices.
   - New features, renamed keys, default changes, and deprecations.
   - Security advisories (CVEs, Microsoft Defender Exploit Guard guidelines, CIS Windows/Linux hardening guidelines).
---

### Phase 4: Propose and Apply Triad Optimization (Performance, Config, Security)

Propose improvements across all three pillars, and apply only the items the user approved (Safety Contract):

#### 1. Performance
- **Concurrency & Parallelism**: Align package downloads, topgrade `[mise] jobs = $(nproc)`, mise `jobs = $(nproc)`, and `makepkg` `MAKEFLAGS="-j$(nproc)"` to detected CPU logical threads. Omit redundant `cargo` `build.jobs`, `ripgrep` `--threads`, and `fd -j` (all auto-detect CPU cores and apply smarter defaults/heuristics).
- **Storage & I/O**: Ensure NVMe/SSD TRIM is enabled (`DisableDeleteNotify=0` / `fstrim.timer`), disable 8.3 short filename generation on secondary Windows data volumes, and avoid WSL `sparseVhd=true` (Microsoft warns of `ext4.vhdx` corruption risk; use manual `wsl --manage <distro> --resize` / `Optimize-VHD` maintenance instead).
- **Memory & Caching**: Enable Windows Memory Compression (`Enable-MMAgent -mc`) or Linux zram; bound WSL2 VM memory in `~/.wslconfig` based on host RAM tier (e.g. 50-60% of host RAM) with `autoMemoryReclaim=dropcache` under `[experimental]`.
- **Hardware Acceleration**: Windows Terminal 1.18+ enables AtlasEngine by default (`disableAnimations: true` still helps); configure `mpv` dynamically tailored to detected GPU (`vo=gpu-next` default in 0.41+, `profile=high-quality`, zero-copy `hwdec=auto-safe`, `tone-mapping=auto`, `target-colorspace-hint=auto` or `yes` when HDR mode is active; legacy `vo=gpu` + `gpu-api=opengl` only on old iGPUs).
- **Tool Launch & Hook Latency**: Eliminate repetitive network queries and startup syncs (e.g. `winget` `autoUpdateIntervalInMinutes: 120`; `mise` `env_cache = true` with `1h` TTL, `fetch_remote_versions_cache = "1h"`, `download_cache = true` + `download_cache_max_size = "2GiB"`; `starship init <shell> --print-full-init` / `zoxide init` static caching).
- **Binary Pre-compilation**: Enable `cargo.binstall = true` (default in `mise` 2026.11+) to fetch pre-compiled Rust binaries instead of compiling from source; use native Windows PE shims (`windows_shim_mode = "exe"`).

#### 2. Configuration & Mandatory Pre-Modification Backups
- **Mandatory Safety Backups**:
  - BEFORE modifying or overwriting ANY existing configuration file, the skill **MUST** execute `scripts/backup-config.sh <config_file> [config_file2 ...] <target> [description]` (supports single-file or multi-file batch backups for a target).
  - Backups are preserved in two locations:
    1. Central backup store (private, mode 700): `~/.config/system-optimizer/backups/<target>/<filename>.<timestamp>.bak` with a `.meta` companion record (SHA256, original path, timestamp).
    2. Local in-place backup: `<config_file>.bak.<timestamp>` when the directory is user-writable (skipped automatically in scanned/drop-in config directories such as `/nvim/`, `*.d/`, `/systemd/`, or with `--no-in-place`).
  - The backup path, timestamp, and SHA256 checksum must be recorded in the per-target `MEMORY.md` under `## Backups & Rollback Ledger`.
  - Rollback is supported on demand via `scripts/backup-config.sh --restore <backup-path>`.
- **Modern Defaults & Synergies** *(read `references/optimization-guide.md` §3–§5 and §10 on demand for per-target config templates)*:
  - Align update orchestration (`topgrade` + `mise` + `winget`/`pacman`/`paccache`) so OS packages and user runtimes never duplicate rebuilds (`disable = ["uv", "cargo", "pi"]` when managed by `mise`, native `github_cli_extensions` instead of manual `gh extension upgrade --all`, `[windows]` for `accept_all_updates` / `winget_use_sudo`, post-command `mise reshim`).
  - Eliminate nested processes, deprecated keys, and subshell lag (`lazygit` `os.editPreset: "nvim-remote"` + `git.diffRenderers` + `gui.nerdFontsVersion: "3"`; `starship` `[mise]` `$symbol`/`$health` or per-language modules; `fzf` `--walker` / `fd --strip-cwd-prefix` + `--info=inline-right` + `bat --theme=auto` previews; `neovim` `vim.loader.enable()` + LazyVim v15/v16+ `opts.servers.<srv>.mason = false` / `automatic_enable` + native `vim.lsp.config`/`vim.lsp.enable`; `uv` `compile-bytecode` / `uv cache prune`).
  - Keep AI agent environments synchronized and clean (`pi` `$PI_CODING_AGENT_DIR`, `cacheWarming: "idle"`, `PI_CACHE_RETENTION=long`, `defaultProjectTrust`; `antigravity` `~/.gemini/config/skills/<skill>/` global skill discovery, Streamable HTTP MCP `url`, `brain/` hygiene; `herdr` `herdr integration status`, `[session] resume_agents_on_restore = true`, `herdr update --handoff`, `[terminal] shell_mode`, `default_shell = ""` honoring `$SHELL`, `[advanced] scrollback_limit_bytes`; `mise` shims on `PATH`).

#### 3. Security
- **Privileged Changes (Safety Contract #4)**: Elevated Windows commands (`Enable-MMAgent -mc`, `Set-MpPreference -PUAProtection 1`, `Optimize-Volume -ReTrim`, `fsutil 8dot3name set`) and root-owned Linux configs (`/etc/sysctl.d/*`, `/etc/pacman.conf`, `/etc/makepkg.conf.d/*`, `/etc/ssh/sshd_config.d/*`, `/etc/controld/ctrld.toml`, systemd services/timers) MUST NEVER be executed directly by the agent — present the exact commands for review and collect all pending privileged suggestions so Phase 6 can offer a consolidated elevated apply script at the end.
- **System & Shell Hardening**: Verify all Firewall profiles active with BlockInbound default, Defender Real-Time & PUA protection, Linux sysctl kernel hardening (`kptr_restrict`, `dmesg_restrict`, `unprivileged_bpf_disabled`, `protected_fifos`/`regular`), PowerShell `RemoteSigned`, sanitized `PATH` (no `.` or empty entries), and scrubbed shell history.
- **Supply Chain & Least Privilege** *(details in `references/optimization-guide.md` §2 & §5)*: Enforce cryptographic verification (`mise` SLSA/cosign/attestations/`npm.provenance = true`/`minimum_release_age`, `topgrade` `[misc] allow_root = false` + `sudo_loop` unattended-terminal caveat, `winget` hash/cert checks enabled, `pacman` `DownloadUser = alpm` + sandbox checks + `SigLevel = Required DatabaseOptional`, `uv` `exclude-newer` & `uv audit`, `pip` `PIP_REQUIRE_VIRTUALENV=true`, `PYTHONSAFEPATH=1`, `cargo` lockfile checksums, `neovim` `modeline = false`), avoid destructive defaults (`sqlite3` `.sqliterc` without `PRAGMA journal_mode=WAL`, `yt-dlp` without global `--downloader aria2c` or global `--impersonate`), and enforce `0600` permissions on credentials/sockets (`~/.ssh`, `gh/hosts.yml` or keyring, `pi` `auth.json` & `mcp-auth.json`, `antigravity` `~/.gemini/oauth_creds.json` & `mcp_config.json`, `herdr.sock` & `config.toml`, `PYTHON_HISTORY`).
---

### Phase 5: Post-Apply Native Validation Gate & Health Checks

1. Run each modified tool's native validator immediately after writing user-approved changes:
   - `herdr config check` (must pass before `herdr server reload-config`)
   - `agy plugin validate` (for Antigravity plugins) and JSON syntax validation (`python3 -m json.tool` on `~/.gemini/config/*.json` & `~/.gemini/antigravity-cli/settings.json`)
   - `mise doctor` / `mise settings`
   - `nvim --headless +q`
   - `bat --diagnostic`
   - `git config --list >/dev/null`
   - `winget settings` / `wsl --status` / `pwsh -NoProfile -Command ...`
   - `sshd -t` / `sysctl --system` (inside elevated apply scripts before service reload)
2. **Rollback on validator failure**: If any native check reports an unknown/deprecated key or parse error, fix it against the live binary schema or immediately restore the pre-edit snapshot with `scripts/backup-config.sh --restore <backup-file>`.
3. Verify service and subsystem health (stopped automatic services on Windows, `systemctl --failed` and user units like `podman.socket` / `syncthing.service` on Linux).
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
- **Elevated Suggestions & Script Offer**: List all unapplied privileged optimizations under **Pending Elevated Suggestions**, and **always suggest creating a consolidated elevated apply script** at the end whenever one or more privileged items exist.

#### 4. Suggest Creation of an Elevated Apply Script (When Privileged Items Exist)
Whenever a run produces one or more optimizations requiring elevation (`sudo`, root-owned `/etc/*` files, or systemd units on Linux; Run-as-Administrator PowerShell, `HKLM:` registry keys, Defender, `fsutil`, or `Optimize-Volume` on Windows):
- **Propose at the end of the report**: Explicitly offer to bundle all pending elevated suggestions from the run into a single reviewable script under `~/.config/system-optimizer/elevated/apply-elevated-<YYYYMMDD-HHMMSS>.sh` (`umask 077`, `chmod 0700` on Linux) or `apply-elevated-<YYYYMMDD-HHMMSS>.ps1` (on Windows) so the user does not have to copy-paste privileged commands one by one. Omit this offer only when zero elevated suggestions exist. On multi-host runs, generate separate per-host scripts.
- **Create only on user approval, never execute**: Write the script to the user-owned `~/.config/system-optimizer/elevated/` directory once approved (or immediately if the user asked for the script), then print the exact review, dry-run, and execution commands (`less <script> && bash <script> --dry-run && sudo bash <script>` on Linux; `Get-Content <script>`, `& <script> -DryRun`, then `& <script>` in an Administrator PowerShell prompt on Windows). **Never invoke `sudo`, `su`, `pkexec`, `runas`, or `Start-Process -Verb RunAs` yourself** (Safety Contract #4).
- **Mandatory script safeguards** *(follow the templates in `references/optimization-guide.md` §2)*:
  1. **Strict mode, privilege guard & dry-run**: `set -euo pipefail`, `--dry-run` flag, and `[[ $EUID -eq 0 ]]` check on Linux; `[CmdletBinding(SupportsShouldProcess)] param([switch]$DryRun)`, `$ErrorActionPreference = 'Stop'`, `Set-StrictMode -Version Latest`, and Administrator role check on Windows.
  2. **System backups outside `$HOME` and outside scanned `.d` directories**: Snapshot touched system configs or `HKLM:` keys into `/var/backups/system-optimizer/<timestamp>/` (`chmod 0700`, with `MANIFEST.sha256`) on Linux or `$env:ProgramData\system-optimizer\backups\<timestamp>\` on Windows. Never write root-owned files into `$HOME/.config/system-optimizer/` and never leave `.bak` files inside scanned drop-in directories (`/etc/sysctl.d/`, `/etc/ssh/sshd_config.d/`, `/etc/sudoers.d/`, `/etc/systemd/`).
  3. **Idempotency, validation & rollback summary**: Check current state before mutating, validate syntax before reloading services (`sshd -t` before `systemctl reload sshd`/`ssh`, `sysctl --system` check), log `[step/total]` progress, and print the exact backup path and rollback instructions on exit.
  4. **Memory persistence**: Record pending elevated items and any generated script path in `MASTER_MEMORY.md` (and per-target `MEMORY.md`) as `Pending user execution` until verified on a later run.

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
