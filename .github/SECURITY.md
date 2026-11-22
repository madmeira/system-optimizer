# Security Policy

## Supported Versions

Security fixes are applied to the `main` branch and included in subsequent releases.

| Version | Supported |
|---|---|
| `main` (latest) | Yes |
| Older commits / tags | No |

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report vulnerabilities confidentially using GitHub Private Vulnerability Reporting:

- [Open a Private Security Advisory](https://github.com/madmeira/system-optimizer/security/advisories/new)

Include as much detail as possible:

- Affected script(s), target(s), or documentation
- Operating system, shell, and agent/CLI environment
- Steps to reproduce or proof-of-concept input
- Potential impact (for example, arbitrary command execution, privilege escalation, path traversal, or secret exposure)

## Security Boundaries & Design Guarantees

`system-optimizer` is governed by a six-rule **Safety Contract** documented in `SKILL.md` and `README.md`:

1. **Read-only probes and audits**: `hardware-probe.sh`, `system-probe.sh`, `detect-targets.sh`, `security-audit.sh`, `target-inspect.sh`, and `tool-drift-check.sh` never modify system or tool configuration files.
2. **No unattended privilege escalation**: Scripts and agent instructions never invoke `sudo`, run elevated PowerShell, or prompt for credentials. Privileged changes are emitted as reviewable commands or optional user-owned scripts under `~/.config/system-optimizer/elevated/`.
3. **Hardened configuration backups**: `scripts/backup-config.sh` stores snapshots in mode-`0700` target directories with mode-`0600` `.bak` and `.bak.meta` SHA-256 records, validates target names against path traversal, and rejects unsafe symlinks/paths.
4. **Non-interactive SSH execution**: `scripts/remote-run.sh` and `scripts/host-diff.sh` use SSH `BatchMode` with key-based authentication only and clean up temporary staging directories.
5. **Best-effort redaction caveat (`host-diff.sh`)**: `scripts/host-diff.sh` attempts to mask secrets, tokens, keys, and URL credentials in shell and tool config comparisons, but redaction is best-effort. Users must review output before sharing it externally.
