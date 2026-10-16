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
    ;;
esac

echo "json-escape: $pass passed"
