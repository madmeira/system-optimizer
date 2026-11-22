#!/usr/bin/env bash
# repo-consistency.sh - verifies SKILL.md frontmatter, script permissions/shebangs,
# and target inventory synchronization across SKILL.md, README.md, and tests/inspect-smoke.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test-env.sh
source "$ROOT/tests/test-env.sh"
PY="$(so_real_python)"
[[ -n "$PY" ]] || { echo "FAIL - python3/python not found" >&2; exit 1; }

failed=0

# 1. Verify shebangs and executable permissions on scripts/*.sh and tests/*.sh
in_git=0
if [[ -e "$ROOT/.git" ]] && command -v git >/dev/null 2>&1; then
  in_git=1
fi

for f in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do
  rel="${f#"$ROOT"/}"
  if [[ "$rel" == "scripts/lib.sh" || "$rel" == "tests/test-env.sh" ]]; then
    continue
  fi

  first_line="$(head -n 1 "$f" || true)"
  if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
    echo "FAIL - $rel missing '#!/usr/bin/env bash' on line 1 (got: $first_line)" >&2
    failed=$((failed + 1))
  fi

  if [[ "$in_git" -eq 1 ]]; then
    mode="$(git -C "$ROOT" ls-files --stage -- "$rel" | awk '{print $1}')"
    if [[ -n "$mode" && "$mode" != "100755" ]]; then
      echo "FAIL - $rel has git mode '$mode' (expected 100755)" >&2
      failed=$((failed + 1))
    elif [[ -z "$mode" && ! -x "$f" ]]; then
      echo "FAIL - untracked $rel is not executable (chmod +x)" >&2
      failed=$((failed + 1))
    fi
  elif [[ ! -x "$f" ]]; then
    echo "FAIL - $rel is not executable" >&2
    failed=$((failed + 1))
  fi
done

# 2. Verify SKILL.md frontmatter & target inventory sync using UTF-8 relative reads
if ! (cd "$ROOT" && "$PY" - <<'PY'
import pathlib
import re
import sys

errors = []

skill_text = pathlib.Path("SKILL.md").read_text(encoding="utf-8")
readme_text = pathlib.Path("README.md").read_text(encoding="utf-8")
smoke_text = pathlib.Path("tests/inspect-smoke.sh").read_text(encoding="utf-8")

# Check SKILL.md YAML frontmatter
m_fm = re.match(r"^---\n(.*?)\n---\n", skill_text, re.S)
if not m_fm:
    errors.append("SKILL.md is missing valid '---' YAML frontmatter delimiters")
else:
    fm = m_fm.group(1)
    for key in ("name", "description", "license", "compatibility"):
        m_key = re.search(rf"^{key}:\s*(.+)$", fm, re.M)
        if not m_key or not m_key.group(1).strip():
            errors.append(f"SKILL.md frontmatter missing non-empty '{key}' field")
        elif key == "name" and m_key.group(1).strip() != "system-optimizer":
            errors.append(f"SKILL.md frontmatter name must be 'system-optimizer' (got '{m_key.group(1).strip()}')")

# Parse smoke targets from tests/inspect-smoke.sh
m_smoke = re.search(r'targets="([^"]+)"', smoke_text, re.S)
if not m_smoke:
    errors.append("tests/inspect-smoke.sh missing targets=\"...\" block")
    smoke_list = []
else:
    smoke_list = m_smoke.group(1).split()
    if len(smoke_list) != len(set(smoke_list)):
        seen = set()
        dups = [t for t in smoke_list if t in seen or seen.add(t)]
        errors.append(f"tests/inspect-smoke.sh contains duplicate targets: {sorted(set(dups))}")

smoke_set = set(smoke_list)

# Parse SKILL.md ## Invocation Modes table
m_skill_tbl = re.search(r"## Invocation Modes.*?^---", skill_text, re.S | re.M)
if not m_skill_tbl:
    errors.append("SKILL.md missing '## Invocation Modes' section")
else:
    skill_targets = []
    for line in m_skill_tbl.group(0).splitlines():
        if line.startswith("| ") and not line.startswith("| Kind"):
            cols = line.split("|")
            if len(cols) >= 3:
                skill_targets.extend(re.findall(r"`([^`]+)`", cols[2]))
    if not skill_targets:
        errors.append("No targets parsed from SKILL.md '## Invocation Modes' table")
    else:
        missing = sorted(set(skill_targets) - smoke_set)
        if missing:
            errors.append(f"SKILL.md lists targets absent from tests/inspect-smoke.sh: {missing}")

# Parse README.md ## Supported Targets section & count
m_readme_sec = re.search(r"## Supported Targets.*?^## ", readme_text, re.S | re.M)
if not m_readme_sec:
    errors.append("README.md missing '## Supported Targets' section")
else:
    readme_block = m_readme_sec.group(0)
    m_cnt = re.search(r"\*\*(\d+) targets\*\*", readme_block)
    if not m_cnt:
        errors.append("README.md '## Supported Targets' missing '**<N> targets**' count")
    elif smoke_set and int(m_cnt.group(1)) != len(smoke_set):
        errors.append(
            f"README.md states {m_cnt.group(1)} targets, but tests/inspect-smoke.sh covers {len(smoke_set)}"
        )

    readme_targets = []
    for line in readme_block.splitlines():
        if line.startswith("| **"):
            cols = line.split("|")
            if len(cols) >= 3:
                cell = re.sub(r"\([^)]*\)", "", cols[2])
                readme_targets.extend(re.findall(r"`([^`]+)`", cell))
    if not readme_targets:
        errors.append("No targets parsed from README.md '## Supported Targets' table")
    else:
        missing = sorted(set(readme_targets) - smoke_set)
        if missing:
            errors.append(f"README.md lists targets absent from tests/inspect-smoke.sh: {missing}")

if errors:
    for err in errors:
        print(f"FAIL - {err}", file=sys.stderr)
    sys.exit(1)

print(f"PASS - repo-consistency: SKILL.md frontmatter, script modes, and {len(smoke_set)} targets verified")
PY
); then
  failed=$((failed + 1))
fi

if [[ "$failed" -ne 0 ]]; then
  echo "repo-consistency: $failed check(s) failed" >&2
  exit 1
fi
