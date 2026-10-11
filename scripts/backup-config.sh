#!/usr/bin/env bash
# backup-config.sh - Automated backup, listing, and restoration for system-optimizer (Windows & Linux)
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

usage() {
  cat <<EOF
Usage:
  $0 <config-path> <target-name> [description]   Create a timestamped backup before editing
  $0 --list [target-name]                         List available backups
  $0 --restore <backup-path> [dest-path]          Restore a configuration from backup
  $0 --diff <backup-path> [current-path]          Show diff between backup and current file

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
  [[ -n "$target" ]] && search_dir="$BACKUP_ROOT/$target"

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
    meta_file="${backup_file}.meta"
    if [[ -f "$meta_file" ]]; then
      raw_orig=$(grep -E "^Original-Path:" "$meta_file" | cut -d: -f2- | xargs)
      current_file=$(normalize_path "$raw_orig")
    fi
  fi

  if [[ -z "$current_file" || ! -f "$current_file" ]]; then
    echo "Error: Current file not specified or doesn't exist: '$current_file'" >&2
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

  if [[ -z "$backup_file" || ! -f "$backup_file" ]]; then
    echo "Error: Backup file not found: '$backup_file'" >&2
    exit 1
  fi

  if [[ -z "$dest_file" ]]; then
    meta_file="${backup_file}.meta"
    if [[ -f "$meta_file" ]]; then
      raw_orig=$(grep -E "^Original-Path:" "$meta_file" | cut -d: -f2- | xargs)
      dest_file=$(normalize_path "$raw_orig")
    fi
  fi

  if [[ -z "$dest_file" ]]; then
    echo "Error: Destination path could not be determined. Please specify: $0 --restore <backup-path> <destination-path>" >&2
    exit 1
  fi

  # Ensure destination directory exists
  dest_dir=$(dirname "$dest_file")
  if [[ ! -d "$dest_dir" ]]; then
    mkdir -p "$dest_dir" 2>/dev/null || (command -v sudo >/dev/null 2>&1 && sudo mkdir -p "$dest_dir")
  fi

  # Pre-restore safety backup of the currently active file if it exists
  if [[ -f "$dest_file" ]]; then
    pre_restore_bak="${dest_file}.pre-restore-$(date +%Y%m%d-%H%M%S).bak"
    cp -p "$dest_file" "$pre_restore_bak" 2>/dev/null || (command -v sudo >/dev/null 2>&1 && sudo cp -p "$dest_file" "$pre_restore_bak") || true
    echo "Saved safety copy of existing file to: $pre_restore_bak"
  fi

  if cp -p "$backup_file" "$dest_file" 2>/dev/null; then
    echo "Successfully restored $backup_file -> $dest_file"
  elif command -v sudo >/dev/null 2>&1; then
    echo "Standard copy failed; attempting with sudo..."
    sudo cp -p "$backup_file" "$dest_file"
    echo "Successfully restored with sudo: $backup_file -> $dest_file"
  else
    echo "Error: Standard restore copy failed and sudo is unavailable. Run with administrative privileges." >&2
    exit 1
  fi
  exit 0
fi

# Backup mode: $1 is config-path, $2 is target-name, $3 is description
config_path=$(normalize_path "$1")
target_name="${2:-general}"
desc="${3:-Auto-backup before optimization}"

if [[ ! -e "$config_path" ]]; then
  echo "Warning: Target config '$config_path' does not exist yet. No backup needed."
  exit 0
fi

if [[ -d "$config_path" ]]; then
  echo "Target '$config_path' is a directory. Use file paths for config backups." >&2
  exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
base_filename=$(basename "$config_path")
target_backup_dir="$BACKUP_ROOT/$target_name"
mkdir -p "$target_backup_dir"

central_backup="$target_backup_dir/${base_filename}.${timestamp}.bak"
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
