#!/usr/bin/env bash
# drift-check-smoke.sh - verifies scripts/tool-drift-check.sh across:
#   1. CLI usage (--help exit 0, unknown option exit 2)
#   2. Clean empty PATH (all targets not_installed, valid JSON)
#   3. Mocked binaries exercising [VERIFIED], [VERSION AHEAD], [SCHEMA DRIFT], and [DEPRECATED CONFIG]
#   4. Alias resolution (rg -> ripgrep, nvim -> neovim, ctrld -> controld)
#   5. Live host execution (--json valid JSON + human-readable mode exit 0)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIFT="$ROOT/scripts/tool-drift-check.sh"
PY="$(command -v python3 || command -v python)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home" "$WORK/appdata/Local" "$WORK/appdata/Roaming" "$WORK/emptybin" "$WORK/mockbin"

# Link basic POSIX/core utilities into emptybin so tool-drift-check.sh runs with zero tracked tools installed.
# Use type -P (external executables only, skipping shell builtins like printf on Git Bash) and copy MSYS2 DLLs on Windows.
for b in bash sh env grep sed awk cat tr cut head tail wc dirname basename uname date mktemp sort rm mkdir printf chmod readlink realpath timeout cygpath; do
  p="$(type -P "$b" 2>/dev/null || true)"
  if [[ -n "$p" && -f "$p" ]]; then
    ln -sf "$p" "$WORK/emptybin/$(basename "$p")"
  fi
done
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    for dll in /usr/bin/*.dll /bin/*.dll; do
      [[ -f "$dll" ]] && cp -f "$dll" "$WORK/emptybin/"
    done
    ;;
esac

run_isolated() {
  local path_val="$1"
  shift
  env -i PATH="$path_val" HOME="$WORK/home" USERPROFILE="$WORK/home" \
    LOCALAPPDATA="$WORK/appdata/Local" APPDATA="$WORK/appdata/Roaming" LANG=C \
    SYSTEMROOT="${SYSTEMROOT:-}" WINDIR="${WINDIR:-}" MSYS2_ARG_CONV_EXCL="*" \
    "$WORK/emptybin/bash" "$@"
}

# 1. --help exits 0; unknown option exits 2
bash "$DRIFT" --help > /dev/null
if bash "$DRIFT" --definitely-invalid-flag > /dev/null 2>&1; then
  echo "FAIL - tool-drift-check.sh accepted an invalid flag" >&2
  exit 1
fi
rc=0
bash "$DRIFT" --definitely-invalid-flag > /dev/null 2>&1 || rc=$?
[[ "$rc" -eq 2 ]] || { echo "FAIL - expected exit 2 on invalid flag, got $rc" >&2; exit 1; }
echo "ok   - CLI argument validation (--help=0, invalid=2)"

# 2. Clean environment with no tracked tools installed -> all not_installed, valid JSON
empty_json="$(run_isolated "$WORK/emptybin" "$DRIFT" --json)"
"$PY" - "$empty_json" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
summary = data["summary"]
assert summary["total"] >= 33, f"expected >=33 tracked targets, got {summary}"
assert summary["not_installed"] == summary["total"], f"expected all not_installed in empty PATH, got {summary}"
assert summary["verified"] == 0 and summary["schema_drift"] == 0, f"unexpected counts: {summary}"
PYEOF
echo "ok   - clean PATH reports all targets not_installed with valid JSON"

# 3. Mocked binaries exercising VERIFIED, VERSION AHEAD, SCHEMA DRIFT, and DEPRECATED CONFIG
#   - rg 15.2.0 with --max-columns-preview -> VERIFIED
cat > "$WORK/mockbin/rg" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "ripgrep 15.2.0"
elif [[ "${1:-}" == "--help" ]]; then
  echo "Usage: rg [OPTIONS] PATTERN [PATH ...] --max-columns-preview --smart-case"
fi
EOF

#   - fd 99.1.0 with --strip-cwd-prefix -> VERSION AHEAD
cat > "$WORK/mockbin/fd" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "fd 99.1.0"
elif [[ "${1:-}" == "--help" ]]; then
  echo "Usage: fd [OPTIONS] --strip-cwd-prefix"
fi
EOF

#   - bat 0.26.1 missing --theme-dark in --help -> SCHEMA DRIFT
cat > "$WORK/mockbin/bat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "bat 0.26.1"
elif [[ "${1:-}" == "--help" ]]; then
  echo "Usage: bat [OPTIONS] (flag removed in mock)"
fi
EOF

#   - mise 2026.11.8 with download_cache in settings ls, PLUS deprecated always_keep_download in user config -> DEPRECATED CONFIG
cat > "$WORK/mockbin/mise" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "2026.11.8 linux-x64"
elif [[ "${1:-}" == "settings" ]]; then
  echo "download_cache = true"
fi
EOF

#   - nvim 0.12.6 + mason-tool-installer automatic_installation (valid) vs mason-lspconfig automatic_installation (deprecated)
cat > "$WORK/mockbin/nvim" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "NVIM v0.12.6"
fi
EOF

#   - ctrld 1.5.0 with doh3 in start --help -> VERIFIED via alias
cat > "$WORK/mockbin/ctrld" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "ctrld v1.5.0"
elif [[ "${1:-}" == "start" ]]; then
  echo "ctrld start --config --doh3"
fi
EOF

#   - agy 1.5.9 with --sandbox, plugin, mcp in --help -> VERIFIED via alias
cat > "$WORK/mockbin/agy" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "1.5.9"
elif [[ "${1:-}" == "--help" ]]; then
  echo "Usage: agy --sandbox plugin mcp"
fi
EOF

chmod +x "$WORK/mockbin/rg" "$WORK/mockbin/fd" "$WORK/mockbin/bat" "$WORK/mockbin/mise" "$WORK/mockbin/nvim" "$WORK/mockbin/ctrld" "$WORK/mockbin/agy"
mkdir -p "$WORK/home/.config/mise" "$WORK/home/.config/nvim/lua/plugins"
cat > "$WORK/home/.config/mise/config.toml" <<'EOF'
[settings]
always_keep_download = true
EOF
# Valid mason-tool-installer automatic_installation must NOT trigger a false positive
cat > "$WORK/home/.config/nvim/lua/plugins/mason.lua" <<'EOF'
return {
  { "WhoIsSethDaniel/mason-tool-installer.nvim", opts = { automatic_installation = false } },
  { "mason-org/mason-lspconfig.nvim", opts = { automatic_enable = false } },
}
EOF

mock_json="$(run_isolated "$WORK/mockbin:$WORK/emptybin" "$DRIFT" --json rg fd bat mise)"
"$PY" - "$mock_json" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
by_name = {t["target"]: t for t in data["targets"]}
assert by_name["ripgrep"]["status"] == "verified", f"expected ripgrep verified, got {by_name['ripgrep']}"
assert by_name["fd"]["status"] == "version_ahead", f"expected fd version_ahead, got {by_name['fd']}"
assert by_name["fd"]["version_ahead"] is True
assert by_name["bat"]["status"] == "schema_drift", f"expected bat schema_drift, got {by_name['bat']}"
assert by_name["bat"]["schema_ok"] is False
assert by_name["mise"]["status"] == "deprecated_config", f"expected mise deprecated_config, got {by_name['mise']}"
assert any("always_keep_download" in f for f in by_name["mise"]["findings"]), f"missing finding in {by_name['mise']}"
s = data["summary"]
assert (s["verified"], s["version_ahead"], s["schema_drift"], s["deprecated_config"]) == (1, 1, 1, 1), f"bad summary: {s}"
PYEOF

mock_txt="$(run_isolated "$WORK/mockbin:$WORK/emptybin" "$DRIFT" rg fd bat mise)"
for expected in "[VERIFIED]" "[VERSION AHEAD]" "[SCHEMA DRIFT]" "[DEPRECATED CONFIG]"; do
  if [[ "$mock_txt" != *"$expected"* ]]; then
    echo "FAIL - human output missing tag $expected" >&2
    exit 1
  fi
done
echo "ok   - VERIFIED, VERSION AHEAD, SCHEMA DRIFT, and DEPRECATED CONFIG verified"

# 4. Alias resolution (rg -> ripgrep, nvim -> neovim, ctrld -> controld, agy -> antigravity), mason scoping, and domain-target skip
alias_json="$(run_isolated "$WORK/mockbin:$WORK/emptybin" "$DRIFT" --json rg nvim ctrld agy storage firefox)"
"$PY" - "$alias_json" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
by_name = {t["target"]: t for t in data["targets"]}
assert set(by_name.keys()) == {"ripgrep", "neovim", "controld", "antigravity"}, f"unexpected targets: {by_name.keys()}"
assert by_name["neovim"]["status"] == "verified", f"mason-tool-installer caused false positive: {by_name['neovim']}"
assert by_name["controld"]["status"] == "verified", f"expected controld verified, got {by_name['controld']}"
assert by_name["antigravity"]["status"] == "verified", f"expected antigravity verified, got {by_name['antigravity']}"
PYEOF
mkdir -p "$WORK/home/.gemini/config"
printf '{"mcpServers":{"legacy":{"serverUrl":"https://example.com/sse","type":"sse"}}}\n' > "$WORK/home/.gemini/config/mcp_config.json"
agy_dep_json="$(run_isolated "$WORK/mockbin:$WORK/emptybin" "$DRIFT" --json agy)"
"$PY" - "$agy_dep_json" <<'PYEOF'
import json, sys
data = json.loads(sys.argv[1])
by_name = {t["target"]: t for t in data["targets"]}
assert by_name["antigravity"]["status"] == "deprecated_config", f"expected deprecated_config, got {by_name['antigravity']}"
findings = " ".join(by_name["antigravity"]["findings"])
assert "serverUrl" in findings and "sse" in findings, f"missing expected MCP findings: {findings}"
PYEOF
echo "ok   - aliases (rg, nvim, ctrld, agy), antigravity MCP drift, mason-lspconfig scoping, and OS/GUI domain skip verified"

# 5. Live host run (both --json and human output) must succeed and emit valid JSON
live_json="$(bash "$DRIFT" --json)"
"$PY" -m json.tool <<< "$live_json" > /dev/null
bash "$DRIFT" > /dev/null
echo "ok   - live host tool-drift-check.sh (--json and text) succeeded"
echo "drift-check-smoke: 5 suites passed"
