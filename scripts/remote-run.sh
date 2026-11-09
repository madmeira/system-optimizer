#!/usr/bin/env bash
# remote-run.sh - run one script of this skill on another host over SSH.
# The scripts locate lib.sh through BASH_SOURCE, so they cannot be piped to "bash -s". This copies
# scripts/ to a temp dir on the host, runs the script from there and deletes the dir. Read-only
# scripts only; it never uses sudo.
# Usage: remote-run.sh <ssh-host> <script.sh> [args...]   e.g. remote-run.sh darktower target-inspect.sh eza
set -euo pipefail

host="${1:-}"; script="${2:-}"
if [[ -z "$host" || ! "$script" =~ ^[A-Za-z0-9._-]+\.sh$ ]]; then
  echo "Usage: $0 <ssh-host> <script.sh> [args...]" >&2
  exit 1
fi
shift 2
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$dir/$script" ]] || { echo "Error: $dir/$script not found" >&2; exit 1; }

printf -v qargs '%q ' "$@"
tar -C "$dir/.." -cf - scripts | ssh -o BatchMode=yes "$host" \
  "d=\$(mktemp -d) && trap 'rm -rf \"\$d\"' EXIT && tar -C \"\$d\" -xf - && bash \"\$d/scripts/$script\" $qargs"
