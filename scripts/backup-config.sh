#!/usr/bin/env bash
# backup-config.sh - Automated backup, listing, and restoration for system-optimizer (Windows & Linux)
#
# Restore integrity: the SHA256 saved in the .meta file is compared with the backup before any
# write. This detects corruption or edits to the backup file; it does not protect against someone
# who can also edit the .meta file.
set -euo pipefail

BACKUP_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/system-optimizer/backups"

normalize_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -u "$p" 2>/dev/null || echo "$p"
  else
    echo "$p" | sed 's#\\#/#g'
  fi
}

# Trim leading/trailing whitespace; quotes and backslashes are kept as they are.
trim() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

# Timestamp with nanoseconds; platforms without %N print a literal "N", which is dropped.
make_timestamp() {
  local ts
  ts=$(date +%Y%m%d-%H%M%S-%N 2>/dev/null || date +%Y%m%d-%H%M%S)
  [[ "$ts" == *-N ]] && ts="${ts%-N}"
  printf '%s' "$ts"
}

# Print "<base><ext>", or "<base>-1<ext>", "<base>-2<ext>"... for the first name that does not exist.
unique_path() {
  local base="$1" ext="$2" candidate n=0
  candidate="${base}${ext}"
  while [[ -e "$candidate" || -e "$candidate.meta" ]]; do
    n=$((n + 1))
    candidate="${base}-${n}${ext}"
  done
  printf '%s' "$candidate"
}

# Accept only an absolute path without ".." segments. Prints the path, or an error and returns 1.
validate_dest_path() {
  local p="$1"
  if [[ -z "$p" ]]; then
    echo "Error: empty destination path" >&2
    return 1
  fi
  case "$p" in
    /*|[A-Za-z]:/*) ;;
    *) echo "Error: destination path is not absolute: '$p'" >&2; return 1 ;;
  esac
  case "/$p/" in
    */../*) echo "Error: destination path contains '..': '$p'" >&2; return 1 ;;
  esac
  printf '%s\n' "$p"
}

# Read Original-Path from a .meta file, validate it and print it. Errors go to stderr, returns 1.
read_original_path() {
  local meta="$1" raw
  if [[ ! -f "$meta" ]]; then
    echo "Error: metadata file not found: '$meta'" >&2
    return 1
  fi
  raw=$(grep -E '^Original-Path:' "$meta" | head -n 1 | cut -d: -f2- || true)
  raw=$(trim "$raw")
  if [[ -z "$raw" ]]; then
    echo "Error: no Original-Path in $meta" >&2
    return 1
  fi
  validate_dest_path "$(normalize_path "$raw")"
}

# Compare the SHA256 recorded in the .meta with the backup file. Refuse when it cannot be verified.
verify_checksum() {
  local bak="$1" meta="$2" expected actual
  if [[ ! -f "$meta" ]]; then
    echo "Error: metadata file missing ($meta); cannot verify backup integrity. Refusing to restore." >&2
    echo "       Only backups in the central store have a .meta. An in-place copy (<file>.bak.<timestamp>) is a plain file: restore it with cp." >&2
    return 1
  fi
  expected=$(grep -E '^SHA256:' "$meta" | head -n 1 | cut -d: -f2- || true)
  expected=$(trim "$expected")
  if [[ -z "$expected" || "$expected" == "unknown" ]]; then
    echo "Error: no usable SHA256 in $meta; cannot verify backup integrity. Refusing to restore." >&2
    return 1
  fi
  if ! command -v sha256sum >/dev/null 2>&1; then
    echo "Error: sha256sum is not available; cannot verify backup integrity. Refusing to restore." >&2
    return 1
  fi
  actual=$(sha256sum "$bak" | awk '{print $1}')
  if [[ "$actual" != "$expected" ]]; then
    echo "Error: checksum mismatch for '$bak' (expected $expected, got $actual). Refusing to restore." >&2
    return 1
  fi
}

# Ask before using sudo. Refuses when the session is not interactive or sudo is missing.
confirm_sudo() {
  local action="$1" path="$2" reply
  if [[ ! -t 0 ]]; then
    echo "Error: '$action' on '$path' needs elevated privileges, but this session is not interactive. Run it yourself with the right permissions." >&2
    return 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "Error: '$action' on '$path' needs elevated privileges and sudo is unavailable." >&2
    return 1
  fi
  read -r -p "Use sudo to ${action}: '${path}'? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Declined: $action '$path'" >&2
    return 1
  fi
}

# A target name becomes a folder name inside the backup store: one plain segment, no separators.
validate_target_name() {
  case "$1" in
    ""|.|..|*/*|*\\*) echo "Error: invalid target name '$1' (use a plain name, no slashes)" >&2; return 1 ;;
  esac
}

usage() {
  cat <<EOF
Usage:
  $0 <config-path> <target-name> [description]   Create a timestamped backup before editing
  $0 --list [target-name]                         List available backups
  $0 --restore <backup-path> [dest-path]          Restore a configuration from backup
  $0 --diff <backup-path> [current-path]          Show diff between backup and current file

Restore verifies the saved SHA256, always writes a safety copy of an existing destination first,
and asks before using sudo (it refuses when the session is not interactive).
Only central-store backups can be restored here; in-place copies (<file>.bak.<timestamp>) are plain files, restore them with cp.

Examples:
  $0 ~/.gitconfig git "Pre-optimization diff pager tuning"
  $0 /etc/sysctl.d/99-zram.conf kernel "Prior to swappiness adjustment"
  $0 ~/.wslconfig wsl "Pre-WSL autoMemoryReclaim configuration"
  $0 --list git
  $0 --restore ~/.config/system-optimizer/backups/git/config.20260905-103000.bak ~/.gitconfig
EOF
}

cmd="${1:-}"

if [[ -z "$cmd" || "$cmd" == "-h" || "$cmd" == "--help" ]]; then
  usage
  exit 0
fi

# List mode
if [[ "$cmd" == "--list" ]]; then
  target="${2:-}"
  search_dir="$BACKUP_ROOT"
  if [[ -n "$target" ]]; then
    validate_target_name "$target" || exit 1
    search_dir="$BACKUP_ROOT/$target"
  fi

  if [[ ! -d "$search_dir" ]]; then
    echo "No backups found in $search_dir"
    exit 0
  fi

  echo "=== System Optimizer Configuration Backups ==="
  found=0
  while IFS= read -r f; do
    if [[ -f "$f" && "$f" == *.bak ]]; then
      found=1
      size=$(stat -c "%s" "$f" 2>/dev/null || wc -c < "$f" || echo "0")
      mtime=$(stat -c "%y" "$f" 2>/dev/null | cut -d. -f1 || echo "unknown")
      echo "  - $f ($size bytes, $mtime)"
    fi
  done < <(find "$search_dir" -type f -name "*.bak" | sort -r)

  if [[ $found -eq 0 ]]; then
    echo "  (No backup files found)"
  fi
  echo "=============================================="
  exit 0
fi

# Diff mode
if [[ "$cmd" == "--diff" ]]; then
  backup_file=$(normalize_path "${2:-}")
  current_file="${3:-}"
  [[ -n "$current_file" ]] && current_file=$(normalize_path "$current_file")

  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    echo "Error: Backup file not found: '$backup_file'" >&2
    exit 1
  fi

  if [[ -z "$current_file" ]]; then
    current_file=$(read_original_path "${backup_file}.meta") || exit 1
  fi

  if [[ ! -f "$current_file" ]]; then
    echo "Error: Current file doesn't exist: '$current_file'" >&2
    exit 1
  fi

  echo "=== Diff: Backup ($backup_file) <-> Current ($current_file) ==="
  diff -u "$backup_file" "$current_file" || true
  echo "================================================================"
  exit 0
fi

# Restore mode
if [[ "$cmd" == "--restore" ]]; then
  backup_file=$(normalize_path "${2:-}")
  dest_file="${3:-}"
  [[ -n "$dest_file" ]] && dest_file=$(normalize_path "$dest_file")
  meta_file="${backup_file}.meta"

  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    echo "Error: Backup file not found: '$backup_file'" >&2
    exit 1
  fi

  verify_checksum "$backup_file" "$meta_file" || exit 1

  if [[ -z "$dest_file" ]]; then
    dest_file=$(read_original_path "$meta_file") || exit 1
  fi

  # Ensure destination directory exists
  dest_dir=$(dirname "$dest_file")
  if [[ ! -d "$dest_dir" ]]; then
    if ! mkdir -p "$dest_dir" 2>/dev/null; then
      confirm_sudo "create directory" "$dest_dir" || exit 1
      sudo mkdir -p "$dest_dir"
    fi
  fi

  # Mandatory safety copy of the currently active file: restore never overwrites without one.
  if [[ -f "$dest_file" ]]; then
    pre_restore_bak=$(unique_path "${dest_file}.pre-restore-$(make_timestamp)" ".bak")
    if ! cp -p "$dest_file" "$pre_restore_bak" 2>/dev/null; then
      if confirm_sudo "write a safety copy of the existing file" "$pre_restore_bak"; then
        sudo cp -p "$dest_file" "$pre_restore_bak" || {
          echo "Error: could not save a safety copy; restore aborted, destination untouched." >&2
          exit 1
        }
      else
        echo "Error: could not save a safety copy; restore aborted, destination untouched." >&2
        exit 1
      fi
    fi
    echo "Saved safety copy of existing file to: $pre_restore_bak"
  fi

  if cp -p "$backup_file" "$dest_file" 2>/dev/null; then
    echo "Successfully restored $backup_file -> $dest_file"
  else
    confirm_sudo "restore over" "$dest_file" || {
      echo "Error: restore not performed." >&2
      exit 1
    }
    sudo cp -p "$backup_file" "$dest_file"
    echo "Successfully restored with sudo: $backup_file -> $dest_file"
  fi
  exit 0
fi

# Backup mode: $1 is config-path, $2 is target-name, $3 is description
if [[ "$cmd" == -* ]]; then
  echo "Error: unknown option '$cmd'" >&2
  usage >&2
  exit 2
fi
config_path=$(normalize_path "$1")
target_name="${2:-general}"
validate_target_name "$target_name" || exit 1
desc="${3:-Auto-backup before optimization}"

if [[ ! -e "$config_path" ]]; then
  echo "Warning: Target config '$config_path' does not exist yet. No backup needed."
  exit 0
fi

if [[ -d "$config_path" ]]; then
  echo "Target '$config_path' is a directory. Use file paths for config backups." >&2
  exit 1
fi

# Backups may hold tokens or private settings: new directories are 700 and the .meta file is 600.
umask 077
base_filename=$(basename "$config_path")
target_backup_dir="$BACKUP_ROOT/$target_name"
mkdir -p "$target_backup_dir"

central_backup=$(unique_path "$target_backup_dir/${base_filename}.$(make_timestamp)" ".bak")
# the prefix is quoted so a file name with [ ] * ? is matched literally, not as a pattern
backup_prefix="$target_backup_dir/${base_filename}."
timestamp="${central_backup#"$backup_prefix"}"
timestamp="${timestamp%.bak}"
central_meta="$central_backup.meta"

# Calculate SHA256 before copy
sha256_hash=$(sha256sum "$config_path" 2>/dev/null | awk '{print $1}' || echo "unknown")
file_size=$(stat -c "%s" "$config_path" 2>/dev/null || wc -c < "$config_path" || echo "0")
file_perms=$(stat -c "%a" "$config_path" 2>/dev/null || echo "644")

# Copy with preserved attributes
cp -p "$config_path" "$central_backup"

# Write metadata companion file
cat <<EOF > "$central_meta"
Original-Path: $config_path
Target: $target_name
Timestamp: $timestamp
SHA256: $sha256_hash
Size: $file_size
Permissions: $file_perms
Description: $desc
EOF

# In-place backup if directory is writable
in_place_backup="${config_path}.bak.${timestamp}"
in_place_created=false
config_dir=$(dirname "$config_path")
if [[ -w "$config_dir" ]]; then
  if cp -p "$config_path" "$in_place_backup" 2>/dev/null; then
    in_place_created=true
  fi
fi

# Output summary
cat <<EOF
[BACKUP CREATED]
Target:       $target_name
Source File:  $config_path
Central Bak:  $central_backup
SHA256:       $sha256_hash
Timestamp:    $timestamp
In-place Bak: $(if [[ "$in_place_created" == true ]]; then echo "$in_place_backup"; else echo "Skipped (directory not user-writable)"; fi)
Description:  $desc
EOF
