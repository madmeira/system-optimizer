# Contributing to system-optimizer

Contributions that improve hardware probing, cross-platform target coverage, security hardening, or documentation are welcome.

## Local Development & Verification

Run the full validation suite from the repository root before opening a pull request:

```bash
# Syntax & static analysis
for s in scripts/*.sh tests/*.sh; do bash -n "$s"; done
shellcheck -S warning scripts/*.sh tests/*.sh

# JSON schema validation across all probes
for p in hardware-probe system-probe detect-targets security-audit tool-drift-check; do
  ./scripts/"$p".sh --json | python3 -m json.tool > /dev/null
done

# Smoke & consistency test suite
bash tests/backup-smoke.sh
bash tests/probe-fallback.sh
bash tests/json-escape.sh
bash tests/inspect-smoke.sh
bash tests/drift-check-smoke.sh
bash tests/repo-consistency.sh
bash tests/inspect-windows.sh   # Run on Windows (Git Bash) when modifying Windows checks
```

## Coding Standards

- **Bash compatibility**: Target Bash `>= 4.0` (including Git Bash on Windows) and avoid non-portable assumptions.
- **Line endings & permissions**: Keep `LF` line endings (enforced by `.gitattributes`). New runnable scripts in `scripts/` and `tests/` must start with `#!/usr/bin/env bash` and be committed with mode `100755` (`chmod +x`).
- **ShellCheck**: All scripts and tests must pass `shellcheck -S warning` with zero warnings.
- **No hardcoded host values or secrets**: Never hardcode personal usernames, hostnames, paths, GPU/RAM/CPU assumptions, or theme palettes.
- **Safety Contract**: Probes and inspectors must remain strictly read-only. Never invoke `sudo` or unattended elevation inside scripts.

## Checklist for Adding a New Target

When adding or updating an optimization target, keep all layers in sync:

1. `scripts/detect-targets.sh`: Add OS/tool detection and canonical alias mapping.
2. `scripts/target-inspect.sh`: Add Performance, Configuration, and Security inspection logic.
3. `scripts/tool-drift-check.sh`: Register CLI version/schema introspection (or explicit GUI/non-CLI skip) and deprecated config checks.
4. `scripts/host-diff.sh`: Add config paths if the target maintains portable user config files.
5. `SKILL.md`, `README.md`, and `references/optimization-guide.md`: Update target tables, target count, and Triad optimization guidance.
6. `tests/inspect-smoke.sh`, `tests/drift-check-smoke.sh`, and `tests/inspect-windows.sh` (if applicable): Add regression coverage and verify `bash tests/repo-consistency.sh` passes.

## Pull Request Workflow

- Open PRs against `main` using **Conventional Commits** for the PR title (for example, `feat(target): ...`, `fix(inspect): ...`, `docs(readme): ...`, `ci(github): ...`).
- PRs are squash-merged into `main` once both `ubuntu-latest` and `windows-latest` CI checks pass.
- Do not submit unrelated changes or bypass `backup-config.sh` / Safety Contract guarantees.
