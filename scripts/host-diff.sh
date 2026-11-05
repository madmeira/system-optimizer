#!/usr/bin/env bash
# host-diff.sh - compare shell startup files and tool configs between this host and another one.
# A setting that is right on one machine and wrong on the other (for example an eza alias) shows up
# here, not in a per-host probe. Secrets are redacted before anything is printed, and only the files
# listed below are read (never ~/.ssh, ~/.gnupg or .env files).
# Usage: host-diff.sh <ssh-host>
set -euo pipefail

host="${1:-}"
[[ -n "$host" ]] || { echo "Usage: $0 <ssh-host>" >&2; exit 1; }

rc_files=(.zshrc .zshenv .bashrc .bash_profile .profile)
cfg_files=(.gitconfig .config/git/config .config/starship.toml .config/ripgrep/ripgreprc \
           .config/btop/btop.conf .config/topgrade.toml .config/mise/config.toml .config/bat/config)

# Hide values of anything that looks like a secret, from the first KEY/TOKEN/SECRET/PASSWORD to the line end.
redact() { sed -E 's/((KEY|TOKEN|SECRET|PASS(WORD)?)[A-Za-z_]*[=:] *).*/\1<redacted>/I'; }
# Shell files are noisy; compare only the lines that change behaviour.
rc_filter() { grep -E '^[[:space:]]*(alias|export|setopt|unsetopt|eval|source|\.|path\+?=|PATH=)' | sed -E 's/^[[:space:]]+//' || true; }

local_text()  { [[ -f "$HOME/$1" ]] && cat "$HOME/$1"; }
remote_text() { ssh -o BatchMode=yes "$host" "test -f ~/$1 && cat ~/$1"; }

compare() {
  local f="$1" filter="$2" l r
  l=$(local_text "$f" 2>/dev/null | redact | $filter) || l="@@missing@@"
  r=$(remote_text "$f" 2>/dev/null | redact | $filter) || r="@@missing@@"
  if [[ "$l" == "@@missing@@" && "$r" == "@@missing@@" ]]; then return 0; fi
  if [[ "$l" == "$r" ]]; then echo "[SAME]      $f"; return 0; fi
  if [[ "$l" == "@@missing@@" ]]; then echo "[ONLY-REMOTE] $f"; return 0; fi
  if [[ "$r" == "@@missing@@" ]]; then echo "[ONLY-LOCAL]  $f"; return 0; fi
  echo "[DIFFERENT] $f   (< this host, > $host)"
  diff <(printf '%s\n' "$l") <(printf '%s\n' "$r") | head -n 30 | sed 's/^/    /' || true
}

ssh -o BatchMode=yes "$host" true || { echo "Error: cannot reach $host over SSH" >&2; exit 1; }
for f in "${rc_files[@]}"; do compare "$f" rc_filter; done
for f in "${cfg_files[@]}"; do compare "$f" cat; done
