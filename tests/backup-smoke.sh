#!/usr/bin/env bash
# backup-smoke.sh - backup -> list -> restore smoke test for scripts/backup-config.sh.
# Runs entirely in a temp dir with its own XDG_CONFIG_HOME; never touches real config.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP="$ROOT/scripts/backup-config.sh"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null || true; rm -rf "$WORK"' EXIT
export XDG_CONFIG_HOME="$WORK/cfg"

pass=0; skipped=0
ok()   { pass=$((pass + 1)); echo "ok   - $1"; }
skip() { skipped=$((skipped + 1)); echo "SKIP - $1"; }
fail() { echo "FAIL - $1" >&2; exit 1; }
is_windows_shell() { case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) return 0 ;; *) return 1 ;; esac; }

STORE="$XDG_CONFIG_HOME/system-optimizer/backups"

# --- basic cycle: backup -> list -> modify -> restore -> identical
mkdir -p "$WORK/w"
cfg="$WORK/w/app.conf"
printf 'original\n' > "$cfg"

out="$(bash "$BACKUP" "$cfg" smoke "smoke test")"
grep -q 'BACKUP CREATED' <<< "$out" || fail "backup did not report BACKUP CREATED"
bak="$(find "$STORE/smoke" -type f -name '*.bak' | head -n 1)"
[[ -f "$bak" && -f "$bak.meta" ]] || fail "central backup or .meta missing"
ok "backup created with .meta"

if is_windows_shell; then
  skip "store permissions (NTFS ignores POSIX modes on Git Bash)"
else
  [[ "$(stat -c %a "$STORE")" == "700" && "$(stat -c %a "$STORE/smoke")" == "700" ]] || fail "backup store is not mode 700"
  [[ "$(stat -c %a "$bak.meta")" == "600" ]] || fail ".meta is not mode 600"
  ok "backup store is private (700) and .meta is 600"
fi

# capture first: "cmd | grep -q" can end in SIGPIPE (status 141) under pipefail, e.g. on Git Bash
list_out="$(bash "$BACKUP" --list smoke)"
grep -qF -- "$bak" <<< "$list_out" || { printf '%s\n' "$list_out" >&2; fail "--list does not show the backup"; }
ok "--list shows the backup"

printf 'changed\n' > "$cfg"
bash "$BACKUP" --restore "$bak" "$cfg" < /dev/null > /dev/null
[[ "$(cat "$cfg")" == "original" ]] || fail "restore did not bring back the original content"
cmp -s "$bak" "$cfg" || fail "restored file is not byte-identical to the backup"
ok "restore is byte-identical"

# --- helpers for the hardening cases
make_backup() {  # make_backup <file> <target>; prints the central backup path
  bash "$BACKUP" "$1" "$2" "case" | sed -n 's/^Central Bak: *//p'
}
fails() { if "$@" > "$WORK/out" 2>&1; then return 1; else return 0; fi; }  # succeeds when the command fails

# --- metadata path validation: ../x is refused, nothing is written
f="$WORK/w/meta.conf"; printf 'keep\n' > "$f"
bak="$(make_backup "$f" meta)"
sed -i.orig 's#^Original-Path:.*#Original-Path: ../x#' "$bak.meta"
fails bash "$BACKUP" --restore "$bak" < /dev/null || fail "restore accepted Original-Path ../x"
grep -q 'not absolute' "$WORK/out" || fail "no clear message for a relative Original-Path"
[[ ! -e "$WORK/w/../x" || ! -s "$WORK/w/../x" ]] || fail "restore wrote through ../x"
ok "relative Original-Path is refused"

# --- a backup edited after creation, or without its .meta, is refused
f="$WORK/w/tamper.conf"; printf 'good\n' > "$f"
bak="$(make_backup "$f" tamper)"
printf 'EVIL\n' >> "$bak"
fails bash "$BACKUP" --restore "$bak" "$f" < /dev/null || fail "restore accepted a modified backup"
[[ "$(cat "$f")" == "good" ]] || fail "destination changed after a refused restore"
ok "modified backup is refused and destination is unchanged"

f="$WORK/w/nometa.conf"; printf 'good\n' > "$f"
bak="$(make_backup "$f" nometa)"
rm -f "$bak.meta"
fails bash "$BACKUP" --restore "$bak" "$f" < /dev/null || fail "restore accepted a backup without .meta"
ok "backup without .meta is refused"

# --- a path with an apostrophe restores through the .meta
f="$WORK/w/it's a file.conf"; printf 'apostrophe\n' > "$f"
bak="$(make_backup "$f" apos)"
printf 'changed\n' > "$f"
bash "$BACKUP" --restore "$bak" < /dev/null > /dev/null
[[ "$(cat "$f")" == "apostrophe" ]] || fail "restore through .meta failed for a path with an apostrophe"
ok "path with an apostrophe restores via .meta"

# --- a .meta without Original-Path says so
sed -i.orig '/^Original-Path:/d' "$bak.meta"
fails bash "$BACKUP" --restore "$bak" < /dev/null || fail "restore accepted a .meta without Original-Path"
grep -q 'no Original-Path' "$WORK/out" || fail "no clear message for a missing Original-Path"
ok "missing Original-Path gives a clear error"

# --- a file name with glob characters keeps a real timestamp and still gets its in-place copy
f="$WORK/w/a[1].conf"; printf 'glob\n' > "$f"
bak="$(make_backup "$f" glob)"
grep -Eq '^Timestamp: [0-9]{8}-[0-9]{6}' "$bak.meta" || fail "Timestamp in .meta is wrong for a name with [ ]: $(grep '^Timestamp:' "$bak.meta")"
[[ -n "$(find "$WORK/w" -maxdepth 1 -name 'a\[1\].conf.bak.*')" ]] || fail "no in-place copy for a name with [ ]"
ok "file name with glob characters: real timestamp and in-place copy"

# --- the in-place copy is a plain file: restore refuses it and says to use cp
g="$WORK/w/inplace.conf"; printf 'v1\n' > "$g"; bash "$BACKUP" "$g" inplace "t" > /dev/null
inplace="$(find "$WORK/w" -maxdepth 1 -name 'inplace.conf.bak.*' | head -n 1)"
printf 'v2\n' > "$g"
fails bash "$BACKUP" --restore "$inplace" "$g" < /dev/null || fail "restore accepted an in-place copy"
grep -q 'restore it with cp' "$WORK/out" || fail "no hint to use cp for in-place copies"
[[ "$(cat "$g")" == "v2" ]] || fail "destination changed after the refused restore"
ok "in-place copy is refused with a hint to use cp"

# --- three backups in a row are three distinct backups
f="$WORK/w/rapid.conf"; printf 'r\n' > "$f"
for _ in 1 2 3; do bash "$BACKUP" "$f" rapid "r" > /dev/null; done
[[ "$(find "$STORE/rapid" -type f -name '*.bak' | wc -l)" -eq 3 ]] || fail "rapid backups overwrote each other"
ok "three rapid backups are distinct"

# --- cases that need a user who cannot write to a directory
if is_windows_shell; then
  skip "unwritable-directory cases (NTFS ignores chmod on Git Bash)"
elif [[ "$(id -u)" -eq 0 ]]; then
  skip "unwritable-directory cases (running as root can write anywhere)"
else
  # destination directory not writable, file does not exist yet: no sudo without a TTY, nothing created
  mkdir -p "$WORK/ro1"; f="$WORK/w/ro1.conf"; printf 'x\n' > "$f"
  bak="$(make_backup "$f" ro1)"
  chmod 555 "$WORK/ro1"
  fails bash "$BACKUP" --restore "$bak" "$WORK/ro1/new.conf" < /dev/null || fail "restore into a read-only dir succeeded"
  [[ ! -e "$WORK/ro1/new.conf" ]] || fail "restore created a file in a read-only dir"
  grep -q 'not interactive' "$WORK/out" || fail "no clear non-interactive sudo message"
  ok "restore into a read-only dir exits non-zero without writing"

  # existing writable file inside a read-only dir: safety copy cannot be written, so restore must stop
  mkdir -p "$WORK/ro2"; printf 'precious\n' > "$WORK/ro2/app.conf"
  f="$WORK/w/ro2.conf"; printf 'old\n' > "$f"
  bak="$(make_backup "$f" ro2)"
  chmod 555 "$WORK/ro2"
  fails bash "$BACKUP" --restore "$bak" "$WORK/ro2/app.conf" < /dev/null || fail "restore overwrote a file without a safety copy"
  [[ "$(cat "$WORK/ro2/app.conf")" == "precious" ]] || fail "destination changed although the safety copy failed"
  if grep -q 'Saved safety copy' "$WORK/out"; then fail "claimed a safety copy that was not written"; fi
  ok "restore stops when the safety copy cannot be written"
fi

echo "backup-smoke: $pass passed, $skipped skipped"
