#!/usr/bin/env bash
# json-escape.sh - values with quotes or backslashes must still produce valid JSON.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PY="$(command -v python3 || command -v python || true)"
[[ -n "$PY" ]] || { echo "FAIL - python3/python not found" >&2; exit 1; }

pass=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
fail() { echo "FAIL - $1" >&2; exit 1; }

# shellcheck source=../scripts/lib.sh
source "$ROOT/scripts/lib.sh"

tricky='a"b\c "quoted" C:\Users\x'
expected="$("$PY" -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$tricky")"

# 1) json_str: the escaped text, wrapped in quotes, must decode to the original
got="$(printf '"%s"' "$(json_str "$tricky")" | "$PY" -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))')"
[[ "$got" == "$expected" ]] || fail "json_str round trip failed: $got"
ok "json_str round-trips quotes and backslashes"

# 2) to_json_arr: several tricky items and an empty list
printf '%s' "$(to_json_arr "$tricky" "plain")" | "$PY" -m json.tool > /dev/null || fail "to_json_arr produced invalid JSON"
[[ "$(to_json_arr)" == "[]" ]] || fail "to_json_arr of nothing is not []"
ok "to_json_arr output is valid JSON"

# 2b) newlines, tabs and control characters would be invalid inside a JSON string
multi=$'line1\nline2\ttab\001x'
got="$(printf '"%s"' "$(json_str "$multi")" | "$PY" -c 'import json,sys; print(json.load(sys.stdin))')"
[[ "$got" == "line1 line2 tabx" ]] || fail "json_str did not flatten control characters: '$got'"
ok "json_str flattens newlines, tabs and control characters"

# 2c) first_line_or: one line even when the command prints "inactive" and fails (systemctl is-active)
fake_systemctl() { echo inactive; return 3; }
[[ "$(first_line_or inactive fake_systemctl)" == "inactive" ]] || fail "first_line_or returned more than one line"
[[ "$(first_line_or fallback false)" == "fallback" ]] || fail "first_line_or did not use the default"
ok "first_line_or never returns a second line"

# 3) json_num / json_bool never emit invented values
[[ "$(json_num 12)" == "12" && "$(json_num abc)" == "null" && "$(json_num '')" == "null" ]] || fail "json_num"
[[ "$(json_bool true)" == "true" && "$(json_bool maybe)" == '"unknown"' ]] || fail "json_bool"
ok "json_num / json_bool use null and \"unknown\" for unusable values"

# 4) end to end: a probe whose input contains quotes and backslashes (Linux branch only)
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) echo "SKIP - end-to-end case (the Linux branch of hardware-probe does not run on Windows)" ;;
  *)
    lspci() { printf '%s\n' '00:02.0 VGA compatible controller: Intel "UHD" \ test'; }
    export -f lspci
    env -u WINDIR -u OS bash "$ROOT/scripts/hardware-probe.sh" --json > "$WORK/hw.json"
    "$PY" -m json.tool "$WORK/hw.json" > /dev/null || fail "hardware-probe JSON is invalid for a GPU name with quotes"
    "$PY" -c 'import json,sys; assert json.load(open(sys.argv[1]))["gpu"] == "Intel \"UHD\" \\ test"' "$WORK/hw.json" || fail "GPU name did not round-trip"
    ok "hardware-probe keeps JSON valid for a GPU name with quotes and backslashes"
    # systemctl prints "inactive" and exits 3 for a missing unit: that used to put a newline in the JSON
    systemctl() { echo inactive; return 3; }
    export -f systemctl
    for p in security-audit system-probe; do
      env -u WINDIR -u OS bash "$ROOT/scripts/$p.sh" --json > "$WORK/$p.json"
      "$PY" -m json.tool "$WORK/$p.json" > /dev/null || fail "$p JSON is invalid when systemctl prints inactive and fails"
    done
    ok "security-audit and system-probe keep JSON valid when systemctl exits non-zero"
    ;;
esac

echo "json-escape: $pass passed"
