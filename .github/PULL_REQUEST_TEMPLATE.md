## Summary
- 

## Verification
- [ ] `for s in scripts/*.sh tests/*.sh; do bash -n "$s"; done`
- [ ] `shellcheck -S warning scripts/*.sh tests/*.sh`
- [ ] `--json | python3 -m json.tool` passes across `hardware-probe`, `system-probe`, `detect-targets`, `security-audit`, and `tool-drift-check`
- [ ] `bash tests/backup-smoke.sh`
- [ ] `bash tests/probe-fallback.sh`
- [ ] `bash tests/json-escape.sh`
- [ ] `bash tests/inspect-smoke.sh`
- [ ] `bash tests/drift-check-smoke.sh`
- [ ] `bash tests/repo-consistency.sh`

## Docs & Target Sync
- [ ] Updated `SKILL.md`, `README.md`, and `references/optimization-guide.md` if targets, CLI flags, or behavior changed (or N/A)
