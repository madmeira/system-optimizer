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

# Best-effort redaction, so review the output before sharing it: values after KEY/TOKEN/SECRET/PASSWORD names,
# user:password@ inside URLs, and common token shapes (sk-, ghp_, AIza, xox*).
redact() {
  sed -E -e 's/((KEY|TOKEN|SECRET|PASS(WORD)?)[A-Za-z_]*[=:] *).*/\1<redacted>/I' \
         -e 's#://[^/@[:space:]]+@#://<redacted>@#g' \
         -e 's/(sk-|gh[pousr]_|AIza|xox[abp]-)[A-Za-z0-9_-]{8,}/<redacted>/g'
}
# Shell files are noisy; compare only the lines that change behaviour. An export shows its value only
# for names that hold paths and tool settings; every other value is hidden, whatever the variable is called.
rc_filter() {
  grep -E '^[[:space:]]*(alias|export|setopt|unsetopt|eval|source|\.|path\+?=|PATH=)' | sed -E 's/^[[:space:]]+//' \
    | sed -E '/^export[[:space:]]+(PATH|EDITOR|VISUAL|PAGER|DIFFPROG|SSH_AUTH_SOCK|XDG_[A-Z_]+|FZF_[A-Z_]+|BAT_[A-Z_]+|RIPGREP_[A-Z_]+|MISE_[A-Z_]+|STARSHIP_[A-Z_]+)=/!s/^(export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*)=.*/\1=<value hidden>/' || true
}

# ssh exits 255 when the connection fails and 1 when "test -f" says the file is missing: keep them apart.
remote_text() { ssh -o BatchMode=yes "$host" "test -f ~/$1 && cat ~/$1"; }

compare() {
  local f="$1" filter="$2" l r rc=0
  if [[ -f "$HOME/$f" ]]; then l=$(redact < "$HOME/$f" | $filter); else l="@@missing@@"; fi
  r=$(remote_text "$f" 2>/dev/null) || rc=$?
  case "$rc" in
    0) r=$(printf '%s\n' "$r" | redact | $filter) ;;
    1) r="@@missing@@" ;;
    *) echo "Error: ssh to $host failed (exit $rc) while reading $f" >&2; exit 1 ;;
  esac
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
