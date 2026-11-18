# shellcheck shell=bash
# test-env.sh - source it from a test BEFORE the test points HOME at a temporary directory.
#
# On a workstation that follows this skill's own advice, PATH holds runtime-manager shims (mise). With
# HOME pointed at an empty directory, a shim no longer sees the real trust list, so mise stops at an
# interactive "config files are not trusted. Trust them?" prompt on /dev/tty: an interactive run hangs,
# a run under `timeout` or in the background is stopped by SIGTTIN, and a run without a terminal fails.
#
# The settings below only affect the test processes and write nothing to the real mise state:
#   - MISE_TRUSTED_CONFIG_PATHS=/  trust config files for this run instead of prompting
#   - MISE_*AUTO_INSTALL=false     never download a tool into the empty test HOME
# A shim whose tool is not installed in the test HOME then fails fast instead of hanging, which the
# scripts under test already handle (python_ok falls back to another interpreter, versions read unknown).
#
# Use "${SO_TEST_ENV[@]}" in every `env -i` command line; `export`-style tests get the variables directly.

# shellcheck disable=SC2034
SO_TEST_ENV=(
  "MISE_TRUSTED_CONFIG_PATHS=/"
  "MISE_AUTO_INSTALL=false"
  "MISE_EXEC_AUTO_INSTALL=false"
  "MISE_NOT_FOUND_AUTO_INSTALL=false"
)
export MISE_TRUSTED_CONFIG_PATHS=/ MISE_AUTO_INSTALL=false MISE_EXEC_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false

# Print the absolute path of a working Python interpreter, resolved through any shim while the real HOME
# is still in place (call it before overriding HOME). Prints nothing when there is none.
so_real_python() {
  local cand exe
  for cand in python3 python; do
    command -v "$cand" >/dev/null 2>&1 || continue
    exe=$("$cand" -c 'import sys; print(sys.executable)' 2>/dev/null </dev/null | tr -d '\r' || true)
    if [[ -n "$exe" && -x "$exe" ]]; then
      printf '%s' "$exe"
      return 0
    fi
    # Windows python.exe may print a path -x cannot test from Git Bash; trust the command itself
    if "$cand" --version 2>&1 </dev/null | grep -q '^Python [0-9]'; then
      command -v "$cand"
      return 0
    fi
  done
  return 0
}
