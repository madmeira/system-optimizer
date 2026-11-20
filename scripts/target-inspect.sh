#!/usr/bin/env bash
# target-inspect.sh - Inspects system domains, tools, and packages across Performance, Config, and Security (Windows & Linux)
set -euo pipefail

LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if [[ ! -f "$LIB" ]]; then
  echo "Error: $LIB not found; copy the whole skill folder, not a single script." >&2
  exit 1
fi
# shellcheck source=lib.sh
source "$LIB"

target="${1:-}"

if [[ -z "$target" ]]; then
  echo "Usage: $0 <target-domain-tool-or-package> [target2 ...]" >&2
  exit 1
fi

case "$target" in
  -h|--help)
    cat <<'EOF'
Usage: target-inspect.sh <target-domain-tool-or-package> [target2 ...]

Inspects system domains, tools, and packages across Performance, Configuration, and Security.

Domains:
  system, security, full, kernel, sysctl, sysctl-security, storage, disk,
  filesystem, memory, swap, zram, cpu, governor, power, boot, systemd,
  startup, firewall, ufw, nftables, firewalld, defender, ssh, sshd,
  execution-policy, uac, network, net, sandboxing, systemd-security,
  package-audit, pkg-audit, supply-chain

Shells, Terminals & Multiplexers:
  bash, pwsh, powershell, windows-terminal, wt, herdr, wsl

Developer Tools & Runtimes:
  mise, topgrade, pi, antigravity, agy, neovim, nvim, lazygit, git, gh, cargo, rust, rustc,
  python, python3, uv, starship, zoxide, ripgrep, rg, fd, fdfind, eza,
  bat, batcat, fzf, sqlite3

Media, Sync, Containers, Monitors & OS Utilities:
  mpv, stremio, ffmpeg, zstd, yt-dlp, syncthing, podman, docker, lazydocker, flatpak, pacman, yay,
  paru, makepkg, paccache, pacman-contrib, btop, htop, btop4win, rustdesk,
  controld, ctrld, kde, kde-plasma, baloo, winget, powertoys

Browsers & KDE Applications:
  chrome, chromium, edge, brave, firefox, librewolf, falkon, dolphin, kate, konsole
EOF
    exit 0
    ;;
esac
local_app_data="$(win_path_unix "${LOCALAPPDATA:-$HOME/AppData/Local}")"
roaming_app_data="$(win_path_unix "${APPDATA:-$HOME/AppData/Roaming}")"

# Dynamic hardware detection (threads fast at startup; GPU lazy — only queried by targets like mpv)
detected_threads="${_SO_DETECTED_THREADS:-$(nproc 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-4}")}"
get_detected_gpu() {
  if [[ -n "${_SO_DETECTED_GPU+x}" ]]; then
    printf '%s\n' "$_SO_DETECTED_GPU"
    return 0
  fi
  local gpu=""
  if is_windows; then
    gpu=$(run_ps '
      $gpus = @(Get-CimInstance Win32_VideoController | Where-Object { $_.Name -and ($_.AdapterRAM -gt 0 -or $_.Name -notmatch "Virtual|Remote|Basic") })
      $dgpu = @($gpus | Where-Object { $_.Name -match "NVIDIA|GeForce|RTX|GTX|Quadro|Radeon RX|Arc " })
      if ($dgpu.Count -gt 0) { $dgpu[0].Name.Trim() }
      elseif ($gpus.Count -gt 0) { ($gpus | ForEach-Object { $_.Name.Trim() }) -join "; " }
      else { "" }
    ' 2>/dev/null || echo "")
  elif command -v lspci >/dev/null 2>&1; then
    gpu=$(lspci 2>/dev/null | grep -Ei "vga|3d|display" | sed 's/.*: //' | tr '\n' ';' | sed 's/;$/\n/; s/;/; /g' || echo "")
  fi
  export _SO_DETECTED_GPU="$gpu"
  printf '%s\n' "$gpu"
}

if [[ $# -gt 1 ]]; then
  export _SO_DETECTED_THREADS="$detected_threads"
  batch_rc=0
  for batch_target in "$@"; do
    # One failing target must not hide the rest, and must not pass silently.
    bash "$0" "$batch_target" || { echo "ERROR: target '$batch_target' failed (exit $?)" >&2; batch_rc=1; }
  done
  exit "$batch_rc"
fi

# Print the uncommented lines of the user's shell startup files that match an extended regex, as
# "file:line:text", so a finding quotes what is really configured. Returns 1 when nothing matches.
# Reads only the local home: on another host, run this script there (scripts/remote-run.sh).
RC_FILES=("$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zprofile"
          "$HOME/.config/fish/config.fish" "$HOME/.config/powershell/Microsoft.PowerShell_profile.ps1"
          "$HOME/Documents/PowerShell/Microsoft.PowerShell_profile.ps1")
# The startup files rc_lines can read on this host, for "not found" messages: a file they source is not followed.
rc_read() {
  local f out=""
  for f in "${RC_FILES[@]}"; do [[ -f "$f" ]] && out+="$f "; done
  echo "${out:-no startup file found }"
}
rc_lines() {
  local pat="$1" f hit=1
  for f in "${RC_FILES[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -nE -- "$pat" "$f" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*#' | sed "s|^|    $f:|"; then
      hit=0
    fi
  done
  return "$hit"
}

# Print the value a startup file assigns to variable $1 (export VAR=..., VAR=..., fish set -gx VAR ...,
# PowerShell $env:VAR = ...); the last assignment wins. Returns 1 when none is found. Used because a
# non-interactive shell (remote-run.sh over SSH, cron, a CI step) usually never reads ~/.bashrc.
rc_env_val() {
  local var="$1" line val tilde='~'
  line=$(rc_lines "^[[:space:]]*(export[[:space:]]+)?${var}=|^[[:space:]]*set[[:space:]]+-gx[[:space:]]+${var}[[:space:]]|^[[:space:]]*\\\$env:${var}[[:space:]]*=" | awk 'END { if (NR) print }' || true)
  [[ -n "$line" ]] || return 1
  line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[^:]+:[0-9]+://')
  if [[ "$line" =~ set[[:space:]]+-gx[[:space:]]+${var}[[:space:]]+(.*)$ ]]; then
    val="${BASH_REMATCH[1]}"
  else
    val="${line#*=}"
  fi
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  if [[ "$val" =~ ^\"(.*)\"$ || "$val" =~ ^\'(.*)\'$ ]]; then
    val="${BASH_REMATCH[1]}"
  fi
  # expand the home references used in paths (nothing else is evaluated)
  val="${val//\$\{HOME\}/$HOME}"
  val="${val//\$HOME/$HOME}"
  [[ "$val" == "$tilde/"* ]] && val="$HOME/${val#"$tilde/"}"
  printf '%s' "$val"
}

# Value of variable $1: the current environment first, then the startup files (see rc_env_val).
env_val() {
  local var="$1"
  if [[ -n "${!var:-}" ]]; then
    printf '%s' "${!var}"
  else
    rc_env_val "$var" || true
  fi
}

# Display form of variable $1: its value, the startup-file value marked as such, or $2 (default [UNSET]).
env_show() {
  local var="$1" unset_label="${2:-[UNSET]}" v
  if [[ -n "${!var:-}" ]]; then
    printf '%s' "${!var}"
  elif v=$(rc_env_val "$var") && [[ -n "$v" ]]; then
    printf '%s (from startup file; not in this shell'\''s environment)' "$v"
  else
    printf '%s' "$unset_label"
  fi
}

# Print "  * <sysctl>: <value> [OK]" or "[WARNING] (Recommended: <hint>)". $2 is a regex of acceptable values.
sysctl_check() {
  local v
  v=$(sysctl -n "$1" 2>/dev/null || echo unknown)
  if [[ "$v" == unknown ]]; then
    echo "  * $1: unknown [NOT READABLE]"
  elif [[ "$v" =~ ^($2)$ ]]; then
    echo "  * $1: $v [OK]"
  else
    echo "  * $1: $v [WARNING] (Recommended: $3)"
  fi
}

# Print "  * <git key>: [OK]" when the key has the wanted value (any value when $2 is empty), else [NOT CONFIGURED].
git_check() {
  local v
  if [[ "$2" == true ]]; then
    v=$(git config --type=bool --get "$1" 2>/dev/null || true)   # yes, on, 1 and True all mean true
  else
    v=$(git config --get "$1" 2>/dev/null || true)
  fi
  if { [[ -z "$2" && -n "$v" ]]; } || { [[ -n "$2" && "$v" == "$2" ]]; }; then
    echo "  * $1: ${v:-set} [OK]"
  elif [[ "$2" == true && -z "$v" && -n "$(git config --get "$1" 2>/dev/null || true)" ]]; then
    # set, but not a valid boolean: git itself rejects it
    echo "  * $1: invalid value '$(git config --get "$1")' [NOT CONFIGURED] (Recommend: $3)"
  else
    echo "  * $1: ${v:-unset} [NOT CONFIGURED] (Recommend: $3)"
  fi
}

# Format file permissions on Linux (POSIX modes are ignored on Windows/Git Bash). Unix sockets are
# checked too. Tools that rewrite a state file atomically (temp file + rename with 0666 & ~umask, e.g.
# zoxide db.zo, herdr session.json) reset a chmod 0600 on every write; a 0700 parent directory already
# blocks other users, so such a file is reported [OK] instead of a recommendation that cannot stick.
cfg_perm_tag() {
  local f="$1" p d
  if is_windows || [[ ! -f "$f" && ! -S "$f" ]]; then
    return 0
  fi
  p=$(stat -c "%a" "$f" 2>/dev/null || echo "")
  if [[ -n "$p" ]]; then
    if [[ "$p" == "600" || "$p" == "400" || "$p" == "700" || "$f" == /etc/* ]]; then
      printf ' (mode: %s)' "$p"
    else
      # any private ancestor up to (not including) $HOME blocks other users, e.g. ~/.config/falkon (700)
      # protects ~/.config/falkon/profiles/default/settings.ini
      d=$(dirname "$f")
      local priv_dir="" priv_mode="" depth=0
      while [[ -n "$d" && "$d" != "/" && "$d" != "." && "$d" != "$HOME" && depth -lt 8 ]]; do
        priv_mode=$(stat -c "%a" "$d" 2>/dev/null || echo "")
        if [[ "$priv_mode" == "700" || "$priv_mode" == "500" ]]; then
          priv_dir="$d"
          break
        fi
        d=$(dirname "$d")
        depth=$((depth + 1))
      done
      if [[ -n "$priv_dir" ]]; then
        if [[ "$priv_dir" == "$(dirname "$f")" ]]; then
          printf ' (mode: %s, dir: %s [OK])' "$p" "$priv_mode"
        else
          printf ' (mode: %s, %s: %s [OK])' "$p" "$priv_dir" "$priv_mode"
        fi
      else
        printf ' (mode: %s -> recommend 0600, or 0700 on %s)' "$p" "$(dirname "$f")"
      fi
    fi
  fi
}

# Strip ANSI CSI escape sequences and CR/NUL from CLI output
strip_ansi() {
  local esc
  esc=$(printf '\033')
  tr -d '\0\r' | sed -E "s/${esc}\\[[0-9;]*[[:alpha:]]//g"
}

# Run a command and print its first non-blank ANSI-stripped stdout line, or $1 default (SIGPIPE-safe under pipefail).
first_clean_line_or() {
  local default="$1" raw line
  shift
  raw=$("$@" 2>/dev/null || true)
  line=$(printf '%s\n' "$raw" | strip_ansi | awk 'NF && !found { out=$0; found=1 } END { if (found) printf "%s", out }')
  printf '%s' "${line:-$default}"
}

# Return 0 if any .lua file under $1 sets automatic_installation inside a mason-lspconfig spec/setup block.
has_mason_lspconfig_deprecated() {
  local dir="$1" f
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if awk '
      /^[[:space:]]*--/ { next }
      {
        line = $0
        sub(/[[:space:]]*--.*$/, "", line)
        if (line ~ /mason-lspconfig/) { in_mlsp = 1 }
        else if (line ~ /["'\''][[:alnum:]_.-]+\/[[:alnum:]_.-]+["'\'']/ || line ~ /mason-(tool-installer|nvim-dap|null-ls)/) { in_mlsp = 0 }
        if (in_mlsp && line ~ /automatic_installation[[:space:]]*=/) { found = 1; exit }
      }
      END { exit !found }
    ' "$f" 2>/dev/null; then
      return 0
    fi
  done < <(grep -RIl --include='*.lua' --exclude-dir=.git 'automatic_installation' "$dir" 2>/dev/null || true)
  return 1
}

# Print the value of key $3 in [section] $2 of an INI/KConfig file $1 (KDE rc files, Falkon settings.ini).
# Section and key match exactly, spaces included ("KFileDialog Settings", "Days Meta Infos"); the last
# assignment wins, as in KConfig. Prints nothing when absent.
ini_val() {
  local file="$1" section="$2" key="$3"
  [[ -r "$file" ]] || return 0
  awk -v sec="[$section]" -v k="$key" '
    { sub(/\r$/, "") }
    /^[[:space:]]*\[/ { cur = $0; sub(/^[[:space:]]+/, "", cur); sub(/[[:space:]]+$/, "", cur); next }
    cur == sec {
      line = $0
      p = index(line, "=")
      if (p == 0) next
      name = substr(line, 1, p - 1); sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
      sub(/\[\$[a-z]+\]$/, "", name)
      if (name == k) { val = substr(line, p + 1); sub(/^[[:space:]]+/, "", val); found = 1 }
    }
    END { if (found) printf "%s", val }
  ' "$file" 2>/dev/null || true
}

# Extract a key's value within a specific TOML [section] (empty section = top-level before any [section])
toml_section_val() {
  local file="$1" section="$2" key="$3"
  [[ -r "$file" ]] || return 0
  awk -v sec="$section" -v k="$key" '
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*\[/) {
        hdr = line
        sub(/^[[:space:]]*\[+/, "", hdr)
        sub(/\].*$/, "", hdr)
        gsub(/[[:space:]]+/, "", hdr)
        in_sec = (sec != "" && hdr == sec)
        seen_sec = 1
        next
      }
      if ((sec == "" && !seen_sec) || in_sec) {
        if (line ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
          val = line
          sub(/^[^=]*=[[:space:]]*/, "", val)
          if (val ~ /^"/) {
            sub(/^"/, "", val); sub(/".*$/, "", val)
          } else if (val ~ /^'\''/) {
            sub(/^'\''/, "", val); sub(/'\''.*$/, "", val)
          } else {
            sub(/[[:space:]]*#.*$/, "", val)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
          }
          print val
          exit
        }
      }
    }
  ' "$file" 2>/dev/null || true
}

# Extract a single- or multi-line TOML array value for <key> (e.g. disable = [...])
toml_extract_array() {
  local file="$1" key="$2"
  [[ -r "$file" ]] || return 0
  awk -v k="$key" '
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/[[:space:]]*#.*$/, "", line)
      if (!collecting && line ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
        val = line
        sub(/^[^=]*=[[:space:]]*/, "", val)
        collecting = 1
        acc = val
        if (acc ~ /\]/) { print acc; collecting = 0; exit }
        next
      }
      if (collecting) {
        acc = acc " " line
        if (line ~ /\]/) { print acc; collecting = 0; exit }
      }
    }
    END { if (collecting && acc != "") print acc }
  ' "$file" 2>/dev/null || true
}

# Print a browser found on Linux (empty $1 = not installed).
browser_report_linux() {
  local exe="$1" ver
  if [[ -z "$exe" ]]; then
    echo "Status: NOT INSTALLED"
    return 0
  fi
  ver=$("$exe" --version 2>/dev/null | head -n 1 || true)
  echo "Status: INSTALLED"
  echo "Executable: $exe"
  echo "Version: ${ver:-unknown}"
}

# List managed-policy files of a Linux browser: policies are what turn Safe Browsing and update settings from a default into a rule.
browser_policy_linux() {
  local d n=0 f
  for d in "$@"; do
    for f in "$d"/*.json; do
      [[ -f "$f" ]] || continue
      echo "Policy file: [MANAGED] $f"
      n=$((n + 1))
    done
  done
  [[ "$n" -gt 0 ]] || echo "Policy files: [UNMANAGED] none (browser defaults apply)"
}

# Print a browser found on Windows: <app exe name> <user data folder> <policy registry key>.
# One PowerShell call prints three lines: the program path ("App Paths", machine-wide first, then
# per-user), its version and whether the policy key exists.
browser_report_win() {
  local app="$1" data="$2" policy_key="$3" info exe="" ver="" managed="" profiles
  info=$(SO_APP="$app" SO_KEY="$policy_key" run_ps '
    $p = ""
    foreach ($r in "HKLM","HKCU") {
      $v = (Get-ItemProperty "${r}:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$env:SO_APP" -ErrorAction SilentlyContinue)."(default)"
      if ($v) { $p = $v; break }
    }
    $p
    if ($p) { (Get-Item -LiteralPath $p).VersionInfo.ProductVersion } else { "" }
    Test-Path -Path $env:SO_KEY' 2>/dev/null || true)
  { read -r exe; read -r ver; read -r managed; } <<< "$info" || true
  if [[ -n "$exe" ]]; then
    echo "Status: INSTALLED"
    echo "Executable: $exe"
    echo "Version: ${ver:-unknown}"
  elif [[ -d "$data" ]]; then
    echo "Status: user data found, executable not located"
  else
    echo "Status: NOT INSTALLED"
  fi
  if [[ -d "$data" ]]; then
    profiles=$(find "$data" -maxdepth 1 -type d \( -name Default -o -name 'Profile *' \) 2>/dev/null | wc -l || true)
    echo "User Data: $data"
    echo "Profiles: $profiles"
  fi
  echo "Managed Policies: ${managed:-unknown}"
}

# Dynamic theme inference helper
infer_theme() {
  local wt_cfg
  for candidate in \
    "$local_app_data/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
    "$local_app_data/Microsoft/Windows Terminal/settings.json"; do
    if [[ -f "$candidate" ]]; then
      wt_cfg="$candidate"
      break
    fi
  done
  if [[ -n "${wt_cfg:-}" && -f "$wt_cfg" ]]; then
    local wt_theme
    wt_theme=$(grep -E '"colorScheme"[[:space:]]*:' "$wt_cfg" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "")
    if [[ -n "$wt_theme" ]]; then
      echo "$wt_theme"
      return 0
    fi
  fi
  local hdr_cfg
  for hdr_cfg in "${HERDR_CONFIG_PATH:-}" "$roaming_app_data/herdr/config.toml" "$HOME/.config/herdr/config.toml"; do
    if [[ -n "$hdr_cfg" && -f "$hdr_cfg" ]]; then
      local hdr_theme
      hdr_theme=$(toml_section_val "$hdr_cfg" "theme" "name")
      if [[ -n "$hdr_theme" && "$hdr_theme" != "default" ]]; then
        echo "$hdr_theme"
        return 0
      fi
    fi
  done
  local agy_settings="$HOME/.gemini/antigravity-cli/settings.json"
  if [[ -f "$agy_settings" ]]; then
    local agy_theme
    agy_theme=$(grep -E '"colorScheme"[[:space:]]*:' "$agy_settings" 2>/dev/null | head -n 1 | cut -d: -f2- | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*,?[[:space:]]*$//' || echo "")
    if [[ -n "$agy_theme" && "${agy_theme,,}" != "default" ]]; then
      echo "$agy_theme"
      return 0
    fi
  fi
  local nv_json
  for nv_json in "$local_app_data/nvim/lazyvim.json" "$HOME/.config/nvim/lazyvim.json"; do
    if [[ -f "$nv_json" ]]; then
      local nv_theme
      nv_theme=$(grep -E '"colorscheme"[[:space:]]*:' "$nv_json" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "")
      if [[ -n "$nv_theme" ]]; then
        echo "$nv_theme"
        return 0
      fi
    fi
  done
  if [[ -f "$HOME/.config/btop/btop.conf" ]]; then
    local btop_theme
    btop_theme=$(grep -E '^[[:space:]]*color_theme[[:space:]]*=' "$HOME/.config/btop/btop.conf" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d ' "' || echo "")
    if [[ -n "$btop_theme" && "$btop_theme" != "Default" ]]; then
      # color_theme may be a full path (/usr/share/btop/themes/tokyo-night.theme): print the theme name
      btop_theme=$(basename "$btop_theme" .theme)
      echo "$btop_theme"
      return 0
    fi
  fi
  if [[ -n "${BAT_THEME:-}" ]]; then
    echo "$BAT_THEME"
    return 0
  fi
  echo ""
}

echo "=== Target Inspection: $target ==="

# 1. System Domains Handling
case "$target" in
  kernel|sysctl|sysctl-security)
    if is_windows; then
      echo "Category: System Core / Windows NT Kernel & Subsystems"
      os_ver=$(run_ps '(Get-CimInstance Win32_OperatingSystem).Version' 2>/dev/null || uname -r)
      os_build=$(run_ps '(Get-CimInstance Win32_OperatingSystem).BuildNumber' 2>/dev/null || echo "unknown")
      echo "Windows Kernel Version: NT $os_ver (Build $os_build)"
      echo "Note: Sysctl parameters apply inside Linux environments and WSL distributions."
      if [[ -f "$HOME/.wslconfig" ]]; then
        echo "Global WSL Kernel Configuration: $HOME/.wslconfig [EXISTS]"
      fi
    else
      echo "Category: System Core / Kernel & Sysctl"
      echo "Kernel Version: $(uname -r)"
      echo "Relevant Config Files:"
      for f in /etc/sysctl.conf /etc/sysctl.d/*.conf /usr/lib/sysctl.d/*.conf; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
      echo "Current Key Parameters:"
      echo "  * vm.swappiness: $(sysctl -n vm.swappiness 2>/dev/null || echo unknown)"
      echo "  * vm.vfs_cache_pressure: $(sysctl -n vm.vfs_cache_pressure 2>/dev/null || echo unknown)"
      sysctl_check kernel.kptr_restrict '1|2' '1 or 2'
      sysctl_check kernel.dmesg_restrict '1' '1'
      sysctl_check kernel.unprivileged_bpf_disabled '1|2' '1 or 2'
      sysctl_check fs.protected_hardlinks '1|2' '1'
      sysctl_check fs.protected_symlinks '1|2' '1'
      sysctl_check fs.protected_fifos '2' '2'
      sysctl_check fs.protected_regular '2' '2'
      echo "  * net.ipv4.tcp_congestion_control: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
      echo "  * net.core.default_qdisc: $(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)"
    fi
    echo "====================================="
    exit 0
    ;;
  storage|disk|filesystem)
    echo "Category: System Core / Storage & Filesystem"
    if is_windows; then
      echo "Mounted Volumes & Free Space:"
      run_ps 'Get-Volume | Where-Object { $_.DriveLetter } | ForEach-Object { "  * Drive $($_.DriveLetter): [$($_.FileSystem)] $([math]::Round($_.SizeRemaining/1GB, 1)) GB free of $([math]::Round($_.Size/1GB, 1)) GB" }' 2>/dev/null || true
      # fsutil prints translated text in the OEM code page (bytes that are not valid UTF-8), so only the
      # number after "=" is read (LC_ALL=C: "." must match any byte) and the explanation is written here.
      trim_val=$(fsutil.exe behavior query DisableDeleteNotify 2>&1 | LC_ALL=C grep -a -i "NTFS" | LC_ALL=C sed -nE 's/.*=[[:space:]]*([0-9]+).*/\1/p' | head -n 1 || true)
      case "$trim_val" in
        0) trim_status="NTFS DisableDeleteNotify = 0  (TRIM operations are sent to the storage device) [OK]" ;;
        1) trim_status="NTFS DisableDeleteNotify = 1  (TRIM is disabled) [WARNING] (Recommended: fsutil behavior set DisableDeleteNotify 0)" ;;
        *) trim_status="unknown" ;;
      esac
      echo "SSD TRIM Status: $trim_status"
      sn_status=$(run_ps 'switch ((Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name NtfsDisable8dot3NameCreation)) { 0 { "Enabled on all volumes" } 1 { "Disabled on all volumes" } 2 { "Per volume setting (the default)" } 3 { "Disabled, except on the system volume" } default { "unknown" } }' 2>/dev/null || true)
      sn_status="${sn_status:-unknown}"
      echo "NTFS 8.3 Short Name Creation: $sn_status"
      echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
      echo "  * Performance: NVMe/SSD TRIM enabled (DisableDeleteNotify=0), weekly Optimize-Volume -ReTrim"
      echo "  * Configuration: Disable 8.3 name creation on secondary data drives (fsutil 8dot3name set <drive> 1)"
      echo "  * Security: BitLocker drive encryption status, NTFS access control lists"
    else
      root_dev=$(LC_ALL=C df --output=source / 2>/dev/null | tail -1 || echo "")
      echo "Root Device: $root_dev"
      root_opts=$(findmnt -n -o OPTIONS / 2>/dev/null || echo defaults)
      echo "Mount Options: $root_opts"
      fstrim_act=$(first_line_or inactive systemctl is-active fstrim.timer)
      fstrim_en=$(first_line_or disabled systemctl is-enabled fstrim.timer)
      if [[ "$fstrim_act" == active || "$root_opts" =~ (^|,)discard(=|,|$) ]]; then
        echo "fstrim.timer Status: $fstrim_act ($fstrim_en) [OK]"
      else
        echo "fstrim.timer Status: $fstrim_act ($fstrim_en) [WARNING] (Recommended: systemctl enable --now fstrim.timer on SSD/NVMe, or mount with discard=async)"
      fi
      if [[ "$root_opts" =~ (^|,)(noatime|relatime|lazytime)(,|$) ]]; then
        echo "Root atime Policy: ${BASH_REMATCH[2]} [OK]"
      elif [[ "$root_opts" =~ (^|,)strictatime(,|$) ]]; then
        echo "Root atime Policy: strictatime [WARNING] (Recommended: relatime or noatime)"
      fi
      root_use=$(LC_ALL=C df --output=pcent / 2>/dev/null | tail -1 | tr -dc '0-9' || true)
      if [[ -n "$root_use" ]]; then
        if (( root_use >= 90 )); then
          echo "Root Filesystem Usage: ${root_use}% [WARNING] (above 90%; free space or clean caches)"
        else
          echo "Root Filesystem Usage: ${root_use}% [OK]"
        fi
      fi
      echo "Fstab Config: /etc/fstab"
    fi
    echo "====================================="
    exit 0
    ;;
  memory|swap|zram)
    echo "Category: System Core / Memory & Paging"
    if is_windows; then
      mem_info=$(run_ps '
        $os = Get-CimInstance Win32_OperatingSystem
        $pf = Get-CimInstance Win32_PageFileUsage | Measure-Object -Property AllocatedBaseSize -Sum
        $mm = try { (Get-MMAgent -ErrorAction SilentlyContinue).MemoryCompression } catch { $null }
        $inv = [Globalization.CultureInfo]::InvariantCulture
        if ($os) { ([math]::Round($os.TotalVisibleMemorySize / 1MB, 2)).ToString($inv) } else { "unknown" }
        if ($os) { ([math]::Round($os.FreePhysicalMemory / 1MB, 2)).ToString($inv) } else { "unknown" }
        if ($null -ne $pf -and $null -ne $pf.Sum) { ([math]::Round($pf.Sum / 1KB, 2)).ToString($inv) } else { if ($os) { "0" } else { "unknown" } }
        if ($null -ne $mm) { ([string][bool]$mm).ToLower() } else { "unknown" }
      ' 2>/dev/null || true)
      { read -r ram_tot; read -r ram_free; read -r page_file; read -r mem_comp; } <<< "$mem_info" || true
      ram_tot="${ram_tot:-unknown}"
      ram_free="${ram_free:-unknown}"
      page_file="${page_file:-unknown}"
      mem_comp="${mem_comp:-unknown}"
      if [[ "$ram_tot" == "unknown" ]]; then
        echo "Total Physical RAM: unknown"
      else
        echo "Total Physical RAM: ${ram_tot} GiB (${ram_free} GiB free)"
      fi
      if [[ "$page_file" == "unknown" ]]; then
        echo "Paging File (Allocated): unknown"
      else
        echo "Paging File (Allocated): ${page_file} GiB"
      fi
      case "$mem_comp" in
        true) echo "Windows Memory Compression: true [OK]" ;;
        false) echo "Windows Memory Compression: false [WARNING] (Recommended: Enable-MMAgent -MemoryCompression)" ;;
        *) echo "Windows Memory Compression: $mem_comp" ;;
      esac
      echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
      echo "  * Performance: Enable-MMAgent -mc (compressed in-RAM paging, eliminates SSD paging stalls)"
      echo "  * Configuration: Fixed or system-managed pagefile on fastest NVMe drive"
      echo "  * Security: Memory Integrity (HVCI) and Virtualization-Based Security (VBS)"
    else
      echo "Total Memory: $(LC_ALL=C free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo unknown)"
      echo "Swap: $(LC_ALL=C free -h 2>/dev/null | awk '/^Swap:/ {print $2}' || echo unknown)"
      zram_active=false
      if [[ -r /proc/swaps ]] && grep -q '^/dev/zram' /proc/swaps 2>/dev/null; then
        zram_active=true
      fi
      swap_total_kb=$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)
      if [[ "$zram_active" == true ]]; then
        echo "Compressed Swap (zram): active [OK]"
      elif [[ "${swap_total_kb:-0}" == 0 ]]; then
        echo "Compressed Swap (zram): none [WARNING] (no swap at all; Recommended: zram-generator with zram-size = ram / 2)"
      else
        echo "Compressed Swap (zram): none [NOTE] (disk swap only; zram-generator avoids SSD paging stalls)"
      fi
      swp=$(sysctl -n vm.swappiness 2>/dev/null || echo unknown)
      if [[ "$swp" =~ ^[0-9]+$ ]]; then
        if [[ "$zram_active" == true && "$swp" -lt 100 ]]; then
          echo "  * vm.swappiness: $swp [NOTE] (with zram, 100-180 is the upstream-recommended range)"
        else
          echo "  * vm.swappiness: $swp [OK]"
        fi
      fi
      if command -v zramctl >/dev/null 2>&1; then
        echo "zram Devices:"
        zramctl 2>/dev/null || true
      fi
      echo "Relevant Configs:"
      for f in /etc/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
    fi
    echo "====================================="
    exit 0
    ;;
  cpu|governor|power)
    echo "Category: System Core / CPU & Power Management"
    if is_windows; then
      cpu_name=$(run_ps '(Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()' 2>/dev/null || echo "unknown")
      threads=$(run_ps '(Get-CimInstance Win32_Processor | Select-Object -First 1).NumberOfLogicalProcessors' 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-unknown}")
      power_raw=$(run_ps '(powercfg /getactivescheme 2>$null | Out-String).Trim()' 2>/dev/null || true)
      power_scheme=$(power_plan_name "$power_raw")
      [[ -n "$power_scheme" ]] || power_scheme="unknown"
      echo "CPU: $cpu_name ($threads threads)"
      echo "Active Power Scheme: $power_scheme"
      if [[ "$power_scheme" =~ (Power[[:space:]]saver|Energy) ]]; then
        echo "  * Power Scheme: [WARNING] power-saving plan active on a workstation (Recommended: Balanced or High Performance on AC)"
      elif [[ "$power_scheme" != unknown ]]; then
        echo "  * Power Scheme: [OK]"
      fi
      echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
      echo "  * Performance: High Performance or Ultimate Performance scheme (powercfg /s <guid>)"
      echo "  * Configuration: Set 100% min/max processor state on AC, disable core parking on desktop"
      echo "  * Security: Hardware mitigation status (Spectre/Meltdown), AMD SVM / Intel VT-x enabled"
    else
      echo "CPU Model: $(LC_ALL=C lscpu 2>/dev/null | grep 'Model name:' | sed 's/Model name:[ \t]*//' || echo unknown)"
      echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo unknown)"
      echo "Microcode: $(grep -m1 'microcode' /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo unknown)"
      echo "Power Daemons:"
      active_pd=()
      for d in power-profiles-daemon tlp cpupower thermald auto-cpufreq tuned; do
        if systemctl is-active "$d" >/dev/null 2>&1; then
          echo "  - [ACTIVE] $d"
          [[ "$d" != thermald ]] && active_pd+=("$d")
        fi
      done
      if [[ ${#active_pd[@]} -gt 1 ]]; then
        echo "  * Power Daemon Conflict: [WARNING] ${active_pd[*]} all manage CPU frequency; keep only one"
      else
        echo "  * Power Daemon Conflict: [OK] ${active_pd[*]:-none} managing CPU frequency"
      fi
      if grep -qm1 'microcode' /proc/cpuinfo 2>/dev/null; then
        echo "  * Microcode: [OK] loaded"
      fi
    fi
    echo "====================================="
    exit 0
    ;;
  boot|systemd|startup)
    echo "Category: System Core / Boot Performance & Startup Applications"
    if is_windows; then
      uptime_str=$(run_ps '
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os.LastBootUpTime) {
          $span = (Get-Date) - $os.LastBootUpTime
          "$($span.Days)d $($span.Hours)h $($span.Minutes)m"
        } else { "unknown" }
      ' 2>/dev/null || echo "unknown")
      fast_boot=$(run_ps '
        $hb = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
        if ($null -ne $hb) { ([string][bool]$hb).ToLower() } else { "unknown" }
      ' 2>/dev/null || echo "unknown")
      fast_boot="${fast_boot:-unknown}"
      echo "System Uptime: $uptime_str"
      echo "Fast Startup (Hiberboot): $fast_boot"
      echo "Startup Applications:"
      run_ps 'Get-CimInstance Win32_StartupCommand | ForEach-Object { "  * $($_.Name): $($_.Command)" }' 2>/dev/null || true
      echo "Stopped Automatic Services:"
      run_ps 'Get-Service | Where-Object { $_.StartType -eq "Automatic" -and $_.Status -ne "Running" } | ForEach-Object { "  * $($_.Name)" }' 2>/dev/null || true
      echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
      echo "  * Performance: Disable high-impact startup items (game clients, telemetry daemons, redundant updaters)"
      echo "  * Configuration: Set non-essential auto services to Delayed Start (StartType: AutomaticDelayedStart)"
      echo "  * Security: Verify Secure Boot status (Confirm-SecureBootUEFI)"
    else
      echo "Startup Time: $(LC_ALL=C systemd-analyze 2>/dev/null | head -n 1 || echo unknown)"
      failed_units=$(systemctl --failed --no-legend 2>/dev/null | sed 's/^[^A-Za-z0-9_@.-]*//' | awk '{print $1}' || true)
      if [[ -n "$failed_units" ]]; then
        echo "Failed Units: [WARNING] $(printf '%s\n' "$failed_units" | wc -l) unit(s): $(tr '\n' ' ' <<< "$failed_units")"
      else
        echo "Failed Units: [OK] none"
      fi
      echo "Journal Usage: $(LC_ALL=C journalctl --disk-usage 2>/dev/null || echo unknown)"
    fi
    echo "====================================="
    exit 0
    ;;
  firewall|ufw|nftables|firewalld|defender)
    echo "Category: Security / Firewall & Host Protection"
    if is_windows; then
      echo "Windows Defender Firewall Status:"
      run_ps 'Get-NetFirewallProfile | ForEach-Object { $tag = if ($_.Enabled -and "$($_.DefaultInboundAction)" -ne "Allow") { "[OK]" } else { "[WARNING]" }; "  * Profile $($_.Name): Enabled=$($_.Enabled), DefaultInboundAction=$($_.DefaultInboundAction), DefaultOutboundAction=$($_.DefaultOutboundAction) $tag" }' 2>/dev/null || true
      echo "Windows Defender Antivirus Status:"
      run_ps '
        $mp = try { Get-MpComputerStatus } catch { $null }
        if ($mp) {
          "  * Real-Time Protection: $($mp.RealTimeProtectionEnabled) $(if ($mp.RealTimeProtectionEnabled) { "[OK]" } else { "[WARNING]" })"
          "  * Antivirus Engine: $($mp.AntivirusEnabled) $(if ($mp.AntivirusEnabled) { "[OK]" } else { "[WARNING]" })"
          "  * Signature Age: $([math]::Round($mp.AntivirusSignatureAge, 1)) day(s) $(if ($mp.AntivirusSignatureAge -le 7) { "[OK]" } else { "[WARNING] (older than 7 days)" })"
        }
      ' 2>/dev/null || true
      echo "Listening TCP Ports:"
      if command -v netstat >/dev/null 2>&1; then
        netstat -ano -p tcp 2>/dev/null | grep -i "LISTENING" | awk '{print "    * " $2}' | sort -u || true
      fi
      echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
      echo "  * Security: All 3 profiles Enabled with BlockInbound default, Enable PUAProtection (Set-MpPreference -PUAProtection 1)"
      echo "  * Performance: Add developer folder exclusions for local git builds (target, node_modules) to avoid Defender CPU lockup"
      echo "  * Configuration: Tamper Protection active, Cloud-delivered protection level: High"
    else
      fw_active=""
      for fw in ufw nftables firewalld; do
        if command -v "$fw" >/dev/null 2>&1; then
          fw_a=$(first_line_or inactive systemctl is-active "$fw")
          fw_e=$(first_line_or disabled systemctl is-enabled "$fw")
          echo "  - $fw: active=$fw_a, enabled=$fw_e"
          [[ "$fw_a" == active ]] && fw_active+="$fw "
        fi
      done
      if [[ -n "$fw_active" ]]; then
        echo "  * Host Firewall: [OK] active (${fw_active% })"
      else
        echo "  * Host Firewall: [WARNING] no active ufw/nftables/firewalld service (Recommended: enable one with a default-deny inbound policy)"
      fi
      echo "Listening TCP Ports:"
      ss -tlnH 2>/dev/null | awk '{print "    * " $4}' | sort -u || echo "    (none)"
    fi
    echo "====================================="
    exit 0
    ;;
  ssh|sshd)
    echo "Category: Security / SSH Configuration & Service"
    if is_windows; then
      sshd_svc=$(run_ps '(Get-Service -Name sshd -ErrorAction SilentlyContinue).Status' 2>/dev/null || echo "NotInstalled")
      echo "OpenSSH Server Service: $sshd_svc"
      echo "Config Locations:"
      for f in "$HOME/.ssh/config" "/c/ProgramData/ssh/sshd_config"; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
      echo "Local Key Directory: $HOME/.ssh"
      [[ -d "$HOME/.ssh" ]] && echo "  - Permissions: n/a (NTFS ACLs, not POSIX modes)"
    else
      ssh_unit="sshd"
      if [[ $(first_line_or inactive systemctl is-active sshd) != "active" && $(first_line_or inactive systemctl is-active ssh) == "active" ]]; then
        ssh_unit="ssh"
      fi
      echo "sshd Service ($ssh_unit): $(first_line_or inactive systemctl is-active "$ssh_unit") ($(first_line_or disabled systemctl is-enabled "$ssh_unit"))"
      echo "SSH Configs:"
      for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf ~/.ssh/config; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f"
      done
      sshd_t=""
      if command -v sshd >/dev/null 2>&1; then
        sshd_t=$(sshd -T 2>/dev/null || true)
      fi
      ssh_files=()
      prl=""; pwa=""; ssh_src=""
      if [[ -n "$sshd_t" ]]; then
        echo "Effective SSH Settings:"
        prl=$(echo "$sshd_t" | grep -i '^permitrootlogin' | awk '{print tolower($2)}' || true)
        pwa=$(echo "$sshd_t" | grep -i '^passwordauthentication' | awk '{print tolower($2)}' || true)
        ssh_src="sshd -T"
      else
        for sf in /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config; do
          [[ -r "$sf" ]] && ssh_files+=("$sf")
        done
        if [[ ${#ssh_files[@]} -gt 0 ]]; then
          prl=$(grep -hEi '^[[:space:]]*PermitRootLogin[[:space:]]+' "${ssh_files[@]}" 2>/dev/null | head -n 1 | awk '{print tolower($2)}' || true)
          pwa=$(grep -hEi '^[[:space:]]*PasswordAuthentication[[:space:]]+' "${ssh_files[@]}" 2>/dev/null | head -n 1 | awk '{print tolower($2)}' || true)
          echo "Configured SSH Settings (config fallback):"
          ssh_src="config"
        fi
      fi
      if [[ -n "$ssh_src" ]]; then
        # OpenSSH defaults: PermitRootLogin prohibit-password, PasswordAuthentication yes
        prl_show="${prl:-prohibit-password (default, not explicitly set)}"
        pwa_show="${pwa:-yes (default, not explicitly set)}"
        case "${prl:-prohibit-password}" in
          no|prohibit-password|without-password|forced-commands-only) echo "  * PermitRootLogin: $prl_show [OK]" ;;
          *) echo "  * PermitRootLogin: $prl_show [WARNING] (Recommended: no or prohibit-password)" ;;
        esac
        if [[ "${pwa:-yes}" == no ]]; then
          echo "  * PasswordAuthentication: $pwa_show [OK]"
        else
          echo "  * PasswordAuthentication: $pwa_show [WARNING] (Recommended: no, key-based auth only, when sshd is exposed)"
        fi
      fi
      ssh_dir_mode=$(stat -c '%a' "$HOME/.ssh" 2>/dev/null || echo absent)
      case "$ssh_dir_mode" in
        absent) echo "Permissions of ~/.ssh directory: absent" ;;
        700|500) echo "Permissions of ~/.ssh directory: $ssh_dir_mode [OK]" ;;
        *) echo "Permissions of ~/.ssh directory: $ssh_dir_mode [WARNING] (Recommended: chmod 700 ~/.ssh)" ;;
      esac
    fi
    echo "====================================="
    exit 0
    ;;
  execution-policy|uac)
    echo "Category: Security / Windows Policies & Access Control"
    if is_windows; then
      run_ps '
        $ep = Get-ExecutionPolicy
        $uac = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue)
        $epTag = if ("$ep" -in @("Unrestricted", "Bypass")) { "[WARNING] (Recommended: RemoteSigned)" } else { "[OK]" }
        $luaTag = if ($uac.EnableLUA -eq 1) { "[OK]" } else { "[WARNING] (UAC disabled; set EnableLUA=1)" }
        $cpTag = if ($uac.ConsentPromptBehaviorAdmin -eq 0) { "[WARNING] (elevates without prompting)" } else { "[OK]" }
        "PowerShell ExecutionPolicy: $ep $epTag"
        "User Account Control (EnableLUA): $($uac.EnableLUA) $luaTag"
        "ConsentPromptBehaviorAdmin: $($uac.ConsentPromptBehaviorAdmin) (5 = Prompt for non-Windows, 2 = Prompt for all on Secure Desktop) $cpTag"
      ' 2>/dev/null || true
      echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
      echo "  * Security: Enforce RemoteSigned policy to prevent arbitrary script execution from web downloads"
      echo "  * Security: Ensure UAC EnableLUA=1 with Secure Desktop prompting"
    fi
    echo "====================================="
    exit 0
    ;;
  winget)
    echo "Category: Package Manager / Windows Package Manager (winget)"
    winget_bin=$(command -v winget 2>/dev/null || echo "")
    echo "Binary: ${winget_bin:-Not installed}"
    winget_ver="unknown"
    if [[ -n "$winget_bin" ]]; then
      winget_ver=$(winget --version 2>/dev/null || echo "unknown")
    fi
    echo "Version: $winget_ver"

    winget_settings="$local_app_data/Packages/Microsoft.DesktopAppInstaller_8wekyb3d8bbwe/LocalState/settings.json"
    echo "Configuration File:"
    if [[ -f "$winget_settings" ]]; then
      echo "  - [EXISTS] $winget_settings"
      echo "Configured Settings:"
      auto_sync=$(grep -E '"autoUpdateIntervalInMinutes"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default (0)")
      telemetry_dis=$(grep -E '"disable"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default")
      downloader=$(grep -E '"downloader"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default")
      pbar=$(grep -E '"progressBar"[[:space:]]*:' "$winget_settings" 2>/dev/null | awk -F: '{print $2}' | tr -d ' ,}' || echo "default")
      echo "  * Source Sync Interval: ${auto_sync} minutes"
      echo "  * Telemetry Disabled: ${telemetry_dis}"
      echo "  * Downloader Engine: ${downloader}"
      echo "  * Visual Progress Bar: ${pbar}"
    else
      echo "  - [NOT FOUND] $winget_settings (Run 'winget settings' to generate)"
    fi

    echo "Security / Admin Policies (from winget --info):"
    winget --info 2>/dev/null | grep -E "InstallerHashOverride|LocalArchiveMalwareScanOverride|BypassCertificatePinning" | while read -r line; do
      echo "  * $line"
    done || true
    echo "Administrator settings (winget settings export, language-independent):"
    winget settings export 2>/dev/null | tr -d '\r' | grep -oE '"(BypassCertificatePinningForMicrosoftStore|InstallerHashOverride|LocalArchiveMalwareScanOverride|LocalManifestFiles)"[[:space:]]*:[[:space:]]*(true|false)' | sed -E 's/^"([^"]+)"[[:space:]]*:[[:space:]]*/  * \1: /' || echo "  (not available in this winget version)"

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Set 'source.autoUpdateIntervalInMinutes: 120' to eliminate 5-10s source sync stall on every invocation"
    echo "  * Performance: Set 'network.downloader: default' (direct WinINet bypasses Delivery Optimization freezes)"
    echo "  * Configuration: Set 'visual.progressBar: rainbow', configure portable package link directories"
    echo "  * Security: Disable telemetry ('telemetry.disable: true'), ensure InstallerHashOverride and BypassCertificatePinning remain Disabled"
    echo "====================================="
    exit 0
    ;;
  windows-terminal|wt)
    echo "Category: Terminal Emulator / Windows Terminal"
    wt_bin=$(command -v wt 2>/dev/null || echo "")
    echo "Binary: ${wt_bin:-App Execution Alias (wt.exe)}"

    wt_settings=""
    for candidate in \
      "$local_app_data/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
      "$local_app_data/Microsoft/Windows Terminal/settings.json" \
      "$local_app_data/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"; do
      if [[ -f "$candidate" ]]; then
        wt_settings="$candidate"
        break
      fi
    done

    echo "Discovered Configuration File:"
    if [[ -n "$wt_settings" ]]; then
      echo "  - [EXISTS] $wt_settings"
      echo "Active Configuration Inspection:"
      def_prof=$(grep -E '"defaultProfile"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "default")
      anim_dis=$(grep -E '"disableAnimations"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "false")
      copy_fmt=$(grep -E '"copyFormatting"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || echo "all")
      echo "  * Default Profile GUID: $def_prof"
      echo "  * Disable Animations: $anim_dis"
      echo "  * Copy Formatting: $copy_fmt"
      atlas_eng=$(grep -E '"useAtlasEngine"[[:space:]]*:' "$wt_settings" 2>/dev/null | head -1 | awk -F: '{print $2}' | tr -d ' ,"' || true)
      if [[ "$atlas_eng" == "false" ]]; then
        echo "  * Atlas GPU Text Engine: false [WARNING] (Legacy setting explicitly disables GPU text rendering; remove or set true)"
      else
        echo "  * Atlas GPU Text Engine: ${atlas_eng:-default (enabled in WT 1.18+)}"
      fi
    else
      echo "  - Standard settings.json not found yet."
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Atlas GPU text rendering is enabled by default in Windows Terminal 1.18+ (ensure useAtlasEngine is not false); set 'disableAnimations: true' for instantaneous tab/pane switching"
    echo "  * Configuration: Set pwsh (PowerShell 7) or Git Bash as default profile, 'copyFormatting: none', Nerd Font face ('Hack Nerd Font')"
    echo "  * Security: Avoid profiles that auto-elevate without prompt; review custom action command injection"
    echo "====================================="
    exit 0
    ;;
  wsl)
    echo "Category: Subsystem & Virtualization / Windows Subsystem for Linux (WSL)"
    wsl_bin=$(command -v wsl 2>/dev/null || command -v wsl.exe 2>/dev/null || echo "")
    echo "Binary: ${wsl_bin:-/c/Windows/System32/wsl.exe}"
    wsl_ver=$(wsl.exe --version 2>/dev/null | tr -d '\0\r' || true)
    # without WSL, wsl.exe prints its help text (translated, but it always names "wsl.exe")
    case "$wsl_ver" in
      ""|*wsl.exe*) wsl_ver="unknown (WSL is not installed)" ;;
      # the label is translated and may carry OEM-encoded bytes ("Versão do WSL: 3.0.1.0"): keep the number
      *) wsl_ver=$(LC_ALL=C grep -a -oE '[0-9]+(\.[0-9]+){1,3}' <<< "$wsl_ver" | head -n 1 || true)
         wsl_ver="${wsl_ver:-unknown}" ;;
    esac
    echo "Version: $wsl_ver"

    echo "Discovered Configuration Files:"
    wsl_cfg_candidates=("$HOME/.wslconfig" "/etc/wsl.conf")
    if [[ -n "${USERPROFILE:-}" ]]; then
      wsl_cfg_candidates+=("${USERPROFILE}/.wslconfig")
      if command -v cygpath >/dev/null 2>&1; then
        wsl_cfg_candidates+=("$(cygpath -u "$USERPROFILE" 2>/dev/null)/.wslconfig")
      fi
    fi
    if command -v wslpath >/dev/null 2>&1 && command -v cmd.exe >/dev/null 2>&1; then
      win_prof=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n' || echo "")
      if [[ -n "$win_prof" ]]; then
        wsl_cfg_candidates+=("$(wslpath -u "$win_prof" 2>/dev/null)/.wslconfig")
      fi
    fi
    for f in "${wsl_cfg_candidates[@]}"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done

    echo "Registered WSL Distributions:"
    # Without WSL, wsl.exe prints its help text; without a distribution it prints a message with the
    # Store link (and normally fails). The texts are translated, so judge by the exit status and by
    # the program name or link they contain, not by words.
    wsl_list=""
    wsl_list=$(wsl.exe -l -v 2>/dev/null | tr -d '\0\r') || wsl_list=""
    if [[ -z "$wsl_list" || "$wsl_list" == *"wsl.exe"* || "$wsl_list" == *"aka.ms/"* ]]; then
      echo "  (none: no WSL distribution is installed)"
    else
      while IFS= read -r line; do
        [[ -n "$line" ]] && echo "  * $line"
      done <<< "$wsl_list"
    fi

    wsl_conf_file=""
    for candidate in "${wsl_cfg_candidates[@]}"; do
      if [[ -f "$candidate" && "$candidate" == *".wslconfig" ]]; then
        wsl_conf_file="$candidate"
        break
      fi
    done
    if [[ -n "$wsl_conf_file" ]]; then
      echo "Current $wsl_conf_file Parameters:"
      grep -E 'memory|processors|swap|autoMemoryReclaim|sparseVhd|dnsTunneling|networkingMode|firewall' "$wsl_conf_file" 2>/dev/null | while read -r line; do
        echo "  - $line"
      done || true
      wsl_amr_exp=$(toml_section_val "$wsl_conf_file" "experimental" "autoMemoryReclaim")
      wsl_amr_top=$(toml_section_val "$wsl_conf_file" "" "autoMemoryReclaim")
      wsl_amr_wsl2=$(toml_section_val "$wsl_conf_file" "wsl2" "autoMemoryReclaim")
      if [[ -n "$wsl_amr_top" || -n "$wsl_amr_wsl2" ]]; then
        echo "  * [WARNING] autoMemoryReclaim should be placed under [experimental] in $wsl_conf_file"
      elif [[ -n "$wsl_amr_exp" ]]; then
        echo "  * [experimental] autoMemoryReclaim: $wsl_amr_exp"
      fi
      wsl_sparse=$(toml_section_val "$wsl_conf_file" "experimental" "sparseVhd")
      [[ -z "$wsl_sparse" ]] && wsl_sparse=$(toml_section_val "$wsl_conf_file" "wsl2" "sparseVhd")
      [[ -z "$wsl_sparse" ]] && wsl_sparse=$(toml_section_val "$wsl_conf_file" "" "sparseVhd")
      if [[ "${wsl_sparse,,}" == "true" ]]; then
        echo "  * [WARNING] sparseVhd=true is enabled in $wsl_conf_file (disabled upstream by Microsoft due to ext4 corruption risks)"
      fi
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Set 'memory = 8GB' (bound to 50% host RAM), '[experimental] autoMemoryReclaim = dropcache' (reclaims cached memory to Windows), processors bound to CPU cores"
    echo "  * Configuration: Set 'networkingMode = mirrored' for low latency and Windows localhost parity, 'dnsTunneling = true'"
    echo "  * Security: Set 'firewall = true' with mirrored networking to apply Windows Defender Firewall rules inside WSL"
    echo "====================================="
    exit 0
    ;;
  pwsh|powershell)
    echo "Category: Shell Environment / PowerShell"
    ps_bin=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || echo "")
    echo "Binary: ${ps_bin:-unknown}"
    ps_ver=$(run_ps '$PSVersionTable.PSVersion.ToString()' 2>/dev/null || echo "unknown")
    echo "Version: $ps_ver"

    echo "PowerShell Profile Paths:"
    run_ps '
      $paths = @(
        $PROFILE.CurrentUserCurrentHost,
        $PROFILE.CurrentUserAllHosts,
        $PROFILE.AllUsersCurrentHost,
        $PROFILE.AllUsersAllHosts
      )
      foreach ($p in $paths) {
        if ($p) {
          $ex = if (Test-Path $p) { "[EXISTS]" } else { "[NOT FOUND]" }
          "  - $ex $p"
        }
      }
    ' 2>/dev/null || true

    echo "Environment & PSReadLine Status:"
    run_ps '
      $ep = Get-ExecutionPolicy
      "  * ExecutionPolicy: $ep"
      $psr = try { Get-PSReadLineOption } catch { $null }
      if ($psr) {
        "  * PSReadLine PredictionSource: $($psr.PredictionSource)"
        "  * PSReadLine EditMode: $($psr.EditMode)"
        "  * PSReadLine HistorySavePath: $($psr.HistorySavePath)"
      }
    ' 2>/dev/null || true

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Deferred module loading, starship/zoxide static init caching, PATH deduplication"
    echo "  * Configuration: Set PSReadLine PredictionSource HistoryAndPlugin, PredictionViewStyle ListView, custom aliases"
    echo "  * Security: Set ExecutionPolicy RemoteSigned, scrub plaintext secrets from PSReadLine history"
    echo "====================================="
    exit 0
    ;;
  powertoys)
    echo "Category: Desktop Utilities / Microsoft PowerToys"
    pt_settings="$local_app_data/Microsoft/PowerToys/settings.json"
    echo "Configuration File: $pt_settings $(if [[ -f "$pt_settings" ]]; then echo "[EXISTS]"; else echo "[NOT FOUND]"; fi)"
    if [[ -f "$pt_settings" ]]; then
      echo "Enabled Modules:"
      run_ps '
        $pt = Get-Content "'"$pt_settings"'" -Raw | ConvertFrom-Json
        $pt.enabled | Get-Member -MemberType NoteProperty | ForEach-Object {
          $val = $pt.enabled.$($_.Name)
          "  * $($_.Name): $val"
        }
      ' 2>/dev/null || true
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Disable unused background modules (Awake, Mouse utilities, Video Conference Mute) to save memory & thread handles"
    echo "  * Configuration: PowerToys Run hotkey & plugins, FancyZones multi-monitor window tiling"
    echo "  * Security: Restrict administrator mode elevation prompt for plugins"
    echo "====================================="
    exit 0
    ;;
  bash|shell|.bashrc)
    echo "Category: Shell Environment / Bash Configuration"
    echo "Bash Version: $BASH_VERSION"
    echo "Relevant Config Files:"
    for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.bash_aliases" "$HOME/.bash_logout" "$HOME/.minttyrc"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f"
    done
    if [[ -d "$HOME/.bash_completion.d" ]]; then
      echo "  - [EXISTS DIR] $HOME/.bash_completion.d"
    fi

    echo "Performance Metrics:"
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
      for _ in 1 2 3; do bash -i -c exit > /dev/null 2>&1 || true; done
      lat_start="${EPOCHREALTIME/,/.}"   # some locales print a comma
      for _ in 1 2 3 4 5; do bash -i -c exit > /dev/null 2>&1 || true; done
      lat_end="${EPOCHREALTIME/,/.}"
      startup_ms=$(awk -v s="$lat_start" -v e="$lat_end" 'BEGIN { printf "%.1f", (e - s) / 5 * 1000 }')
      echo "  * Interactive Startup Latency: ~${startup_ms} ms"
    else
      echo "  * Interactive Startup Latency: n/a (needs bash 5: EPOCHREALTIME)"
    fi

    echo "Security & Hygiene Checks:"
    if [[ "$PATH" =~ (^|:)\.($|:) || "$PATH" =~ (^:|::|:$) ]]; then
      echo "  * [WARNING] PATH contains relative '.' or empty entry! High security risk for binary hijacking."
    else
      echo "  * PATH Sanitation: OK (No relative or empty directories)"
    fi
    if [[ -f "$HOME/.bashrc" ]]; then
      echo "Active .bashrc Ergonomics & Integrations:"
      echo "  * HISTCONTROL: $(grep -E '^[[:space:]]*(export[[:space:]]+)?HISTCONTROL=' "$HOME/.bashrc" 2>/dev/null | tail -n 1 || echo 'unset')"
      echo "  * Shell Hooks: $(grep -oE '(mise activate|starship init|zoxide init|fzf --bash)' "$HOME/.bashrc" 2>/dev/null | sort -u | tr '\n' ' ' || echo 'none detected')"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Pre-compiled static init caches for starship/fzf/zoxide, mise shims, completion caching"
    echo "  * Configuration: History deduplication, directory spell/autocd, modular ~/.config/bash/ split, aliases"
    echo "  * Security: Explicit umask, safe PATH ordering, restricted permissions on sourced credentials"
    echo "====================================="
    exit 0
    ;;
  pi|pi-agent|agent)
    echo "Category: Agent Harness / Pi Coding Agent"
    pi_bin=$(command -v pi 2>/dev/null || echo "")
    echo "Binary: ${pi_bin:-unknown (running via wrapper/npx)}"
    pi_ver="unknown"
    if [[ -n "$pi_bin" ]]; then
      pi_ver=$(first_clean_line_or "unknown" "$pi_bin" --version)
    fi
    echo "Version: $pi_ver"

    pi_agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
    echo "Configuration & State Files ($pi_agent_dir):"
    for f in \
      "$pi_agent_dir/settings.json" \
      "$pi_agent_dir/auth.json" \
      "$pi_agent_dir/mcp-auth.json" \
      "$pi_agent_dir/models.json" \
      "$pi_agent_dir/mcp.json" \
      "$pi_agent_dir/trust.json" \
      "$pi_agent_dir/keybindings.json"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      fi
    done
    for f in "$pi_agent_dir/model-router.json" "$HOME/.pi/web-search.json"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f") (optional third-party extension)"
      fi
    done

    if ! is_windows; then
      for cred_f in "$pi_agent_dir/auth.json" "$pi_agent_dir/mcp-auth.json"; do
        if [[ -f "$cred_f" ]]; then
          cred_mode=$(stat -c "%a" "$cred_f" 2>/dev/null || echo "")
          if [[ -n "$cred_mode" && "$cred_mode" != "600" && "$cred_mode" != "400" ]]; then
            echo "  * [SECURITY WARNING] $cred_f has mode $cred_mode (must be 0600 — stores sensitive credentials/OAuth tokens)"
          fi
        fi
      done
    fi

    pi_settings="$pi_agent_dir/settings.json"
    if [[ -f "$pi_settings" ]]; then
      echo "Active Pi Settings ($pi_settings):"
      if command -v python3 >/dev/null 2>&1; then
        pi_parsed=$(python3 - "$pi_settings" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        d = json.load(fh)
    cw = d.get("cacheWarming", "default (idle)")
    dpt = d.get("defaultProjectTrust", "default (ask)")
    dt = d.get("defaultTools", "default (all built-in)")
    comp = d.get("compaction", {})
    rt = comp.get("reserveTokens", "default (16384)") if isinstance(comp, dict) else "unknown"
    krt = comp.get("keepRecentTokens", "default (20000)") if isinstance(comp, dict) else "unknown"
    legacy = [k for k in ("permissions", "experimental") if k in d]
    print(f"cw={cw}")
    print(f"dpt={dpt}")
    print(f"dt={dt}")
    print(f"rt={rt}")
    print(f"krt={krt}")
    print(f"legacy={','.join(legacy)}")
except Exception:
    pass
PY
        )
        if [[ -n "$pi_parsed" ]]; then
          pi_cw=$(printf '%s\n' "$pi_parsed" | sed -n 's/^cw=//p' | head -n 1)
          pi_dpt=$(printf '%s\n' "$pi_parsed" | sed -n 's/^dpt=//p' | head -n 1)
          pi_dt=$(printf '%s\n' "$pi_parsed" | sed -n 's/^dt=//p' | head -n 1)
          pi_rt=$(printf '%s\n' "$pi_parsed" | sed -n 's/^rt=//p' | head -n 1)
          pi_krt=$(printf '%s\n' "$pi_parsed" | sed -n 's/^krt=//p' | head -n 1)
          pi_legacy=$(printf '%s\n' "$pi_parsed" | sed -n 's/^legacy=//p' | head -n 1)
          echo "  * cacheWarming: ${pi_cw:-default (idle)}"
          echo "  * compaction: reserveTokens=${pi_rt:-default (16384)}, keepRecentTokens=${pi_krt:-default (20000)}"
          echo "  * defaultProjectTrust: ${pi_dpt:-default (ask)}"
          echo "  * defaultTools: ${pi_dt:-default (all built-in)}"
          if [[ "$pi_dpt" == "always" ]]; then
            echo "  * [SECURITY WARNING] defaultProjectTrust is 'always' globally (prefer 'ask' or 'never' with trust.json)"
          fi
          if [[ -n "$pi_legacy" ]]; then
            echo "  * [NOTE] Legacy/non-core settings keys present ($pi_legacy); Pi 1.5.2 uses top-level cacheWarming, defaultProjectTrust, and defaultTools"
          fi
        fi
      else
        pi_cw=$(grep -E '"cacheWarming"[[:space:]]*:' "$pi_settings" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || true)
        pi_dpt=$(grep -E '"defaultProjectTrust"[[:space:]]*:' "$pi_settings" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || true)
        echo "  * cacheWarming: ${pi_cw:-default (idle)}"
        echo "  * defaultProjectTrust: ${pi_dpt:-default (ask)}"
        if [[ "$pi_dpt" == "always" ]]; then
          echo "  * [SECURITY WARNING] defaultProjectTrust is 'always' globally (prefer 'ask' or 'never' with trust.json)"
        fi
        if grep -qE '"(permissions|experimental)"[[:space:]]*:' "$pi_settings" 2>/dev/null; then
          echo "  * [NOTE] Legacy/non-core settings keys present (permissions/experimental); Pi 1.5.2 uses top-level cacheWarming, defaultProjectTrust, and defaultTools"
        fi
      fi
    fi

    echo "Performance & Storage Metrics:"
    sessions_dir="$pi_agent_dir/sessions"
    if [[ -d "$sessions_dir" ]]; then
      sess_count=$(find "$sessions_dir" -type f -name "*.jsonl" 2>/dev/null | wc -l | tr -d ' ' || true)
      stale_sess_count=$(find "$sessions_dir" -type f -name "*.jsonl" -mtime +30 2>/dev/null | wc -l | tr -d ' ' || true)
      sess_size=$(du -sh "$sessions_dir" 2>/dev/null | awk '{print $1}' || echo "0")
      echo "  * Saved Sessions: $sess_count session files ($sess_size disk usage, $stale_sess_count stale >30d)"
    fi
    cache_dir="$HOME/.pi/web-search-cache"
    if [[ -d "$cache_dir" ]]; then
      cache_size=$(du -sh "$cache_dir" 2>/dev/null | awk '{print $1}' || echo "0")
      echo "  * Web Search Cache (optional extension): $cache_size"
    fi

    echo "Mise Toolchain Synergy in Agent Harness:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      echo "  * Mise Binary Detected: $mise_bin"
      mise_shims="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
      if is_windows; then
        mise_shims="$(win_path_unix "${MISE_DATA_DIR:-$local_app_data/mise}")/shims"
      fi
      if [[ -d "$mise_shims" ]]; then
        echo "  * Mise Shims Directory: [EXISTS] ($mise_shims)"
        if [[ ":$PATH:" == *":$mise_shims:"* ]]; then
          echo "  * Shims on Agent PATH: [ACTIVE] (Subshell commands inherit project-pinned runtimes)"
        else
          echo "  * Shims on Agent PATH: [NOT ON PATH] (Export mise shims on PATH or set shellPath/shellCommandPrefix in settings.json)"
        fi
      fi
    else
      echo "  * Mise not detected on this system."
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Archive stale sessions (>30d); keep cacheWarming = 'idle' with PI_CACHE_RETENTION=long; tune compaction.keepRecentTokens/modelOverrides (reserveTokens defaults to 16384); prefer codemode/deferred MCP exposure"
    echo "  * Configuration: Inherit mise shims on PATH (or shellPath in settings.json) for subshell runtimes; manage keybindings.json, mcp.json, and models.json"
    echo "  * Security: Enforce 0600 on auth.json and mcp-auth.json; use defaultProjectTrust: 'ask' (trust.json) and defaultTools / --exclude-tools (OS/container sandboxing or tool_call extension for path gating); audit npm packages (--ignore-scripts)"
    echo "====================================="
    exit 0
    ;;
  antigravity|agy|antigravity-cli|antigravity-ide)
    echo "Category: Agent Harness / Google Antigravity (agy)"
    agy_bin=$(command -v agy 2>/dev/null || command -v antigravity 2>/dev/null || echo "")
    if [[ -z "$agy_bin" && -x "$HOME/.local/bin/agy" ]]; then
      agy_bin="$HOME/.local/bin/agy"
    fi
    echo "Binary: ${agy_bin:-Not found on PATH}"
    agy_ver="unknown"
    if [[ -n "$agy_bin" ]]; then
      agy_ver=$(first_clean_line_or "unknown" "$agy_bin" --version)
    fi
    echo "Version: $agy_ver"

    gemini_dir="$HOME/.gemini"
    agy_cli_dir="$gemini_dir/antigravity-cli"
    agy_cfg_dir="$gemini_dir/config"
    echo "Configuration & State Files ($gemini_dir):"
    for f in \
      "$agy_cli_dir/settings.json" \
      "$agy_cfg_dir/config.json" \
      "$agy_cfg_dir/mcp_config.json" \
      "$agy_cfg_dir/hooks.json" \
      "$agy_cfg_dir/skills.json" \
      "$agy_cfg_dir/plugins.json" \
      "$gemini_dir/oauth_creds.json" \
      "$gemini_dir/trustedFolders.json"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      fi
    done

    if ! is_windows; then
      for cred_f in "$gemini_dir/oauth_creds.json" "$agy_cfg_dir/mcp_config.json"; do
        if [[ -f "$cred_f" ]]; then
          cred_mode=$(stat -c "%a" "$cred_f" 2>/dev/null || echo "")
          if [[ -n "$cred_mode" && "$cred_mode" != "600" && "$cred_mode" != "400" ]]; then
            echo "  * [SECURITY WARNING] $cred_f has mode $cred_mode (must be 0600 — stores sensitive credentials/OAuth tokens)"
          fi
        fi
      done
    fi

    agy_settings="$agy_cli_dir/settings.json"
    if [[ -f "$agy_settings" ]]; then
      echo "Active Antigravity CLI Settings ($agy_settings):"
      agy_model=""
      agy_scheme=""
      agy_nonws=""
      agy_trusted=""
      agy_broad_trust=""
      if command -v python3 >/dev/null 2>&1; then
        agy_parsed=$(python3 - "$agy_settings" <<'PY' 2>/dev/null || true
import json, os, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
        d = json.load(fh)
    model = d.get("model", "default")
    scheme = d.get("colorScheme", "default")
    nonws = d.get("allowNonWorkspaceAccess", False)
    if isinstance(nonws, bool):
        nonws_s = "true" if nonws else "false"
    else:
        nonws_s = str(nonws)
    tw = d.get("trustedWorkspaces", [])
    if isinstance(tw, list):
        tw_s = ", ".join(str(x) for x in tw) if tw else "(none)"
        home = os.path.expanduser("~")
        broad = any(str(x).rstrip("/") in ("", home.rstrip("/")) or str(x) in ("$HOME", "~") for x in tw)
    else:
        tw_s = str(tw)
        broad = False
    print(f"model={model}")
    print(f"scheme={scheme}")
    print(f"nonws={nonws_s}")
    print(f"tw={tw_s}")
    print(f"broad={'true' if broad else 'false'}")
except Exception:
    pass
PY
        )
        if [[ -n "$agy_parsed" ]]; then
          agy_model=$(printf '%s\n' "$agy_parsed" | sed -n 's/^model=//p' | head -n 1)
          agy_scheme=$(printf '%s\n' "$agy_parsed" | sed -n 's/^scheme=//p' | head -n 1)
          agy_nonws=$(printf '%s\n' "$agy_parsed" | sed -n 's/^nonws=//p' | head -n 1)
          agy_trusted=$(printf '%s\n' "$agy_parsed" | sed -n 's/^tw=//p' | head -n 1)
          agy_broad_trust=$(printf '%s\n' "$agy_parsed" | sed -n 's/^broad=//p' | head -n 1)
        fi
      fi
      if [[ -z "$agy_model" && -z "$agy_scheme" && -z "$agy_nonws" ]]; then
        agy_model=$(grep -E '"model"[[:space:]]*:' "$agy_settings" 2>/dev/null | head -n 1 | cut -d: -f2- | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*,?[[:space:]]*$//' || true)
        agy_scheme=$(grep -E '"colorScheme"[[:space:]]*:' "$agy_settings" 2>/dev/null | head -n 1 | cut -d: -f2- | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*,?[[:space:]]*$//' || true)
        agy_nonws=$(grep -E '"allowNonWorkspaceAccess"[[:space:]]*:' "$agy_settings" 2>/dev/null | head -n 1 | cut -d: -f2- | tr -d ' ,"' || true)
        tw_block=$(awk '/"trustedWorkspaces"[[:space:]]*:/{in_tw=1} in_tw{print; if (/\]/) exit}' "$agy_settings" 2>/dev/null || true)
        agy_trusted_arr=()
        while IFS= read -r tw_item; do
          [[ -z "$tw_item" || "$tw_item" == "trustedWorkspaces" ]] && continue
          agy_trusted_arr+=("$tw_item")
          [[ "$tw_item" == "/" || "$tw_item" == "${HOME%/}" || "$tw_item" == '$HOME' || "$tw_item" == "~" ]] && agy_broad_trust="true"
        done < <(printf '%s\n' "$tw_block" | grep -oE '"[^"]+"' | tr -d '"' || true)
        if [[ ${#agy_trusted_arr[@]} -gt 0 ]]; then
          agy_trusted=$(printf '%s, ' "${agy_trusted_arr[@]}")
          agy_trusted="${agy_trusted%, }"
        fi
      fi
      echo "  * model: ${agy_model:-default}"
      echo "  * colorScheme: ${agy_scheme:-default}"
      echo "  * allowNonWorkspaceAccess: ${agy_nonws:-false}"
      echo "  * trustedWorkspaces: ${agy_trusted:-(none)}"
      if [[ "${agy_nonws,,}" == "true" ]]; then
        echo "  * [NOTE] allowNonWorkspaceAccess is enabled globally (useful for host-wide skills like system-optimizer; disable or use --sandbox on untrusted repos)"
      fi
      if [[ "$agy_broad_trust" == "true" ]]; then
        echo "  * [SECURITY WARNING] trustedWorkspaces includes '/' or '\$HOME' (prefer scoping to dedicated workspace folders such as ~/repos)"
      fi
    fi

    echo "Customizations & MCP Configuration ($agy_cfg_dir):"
    if [[ -f "$agy_cfg_dir/skills/system-optimizer/SKILL.md" ]]; then
      echo "  * Global Skill Discovery (system-optimizer): [REGISTERED] ($agy_cfg_dir/skills/system-optimizer/SKILL.md)"
    elif [[ -f "$agy_cfg_dir/skills.json" ]] && grep -qE 'system-optimizer|\.pi/agent/skills|\.agents/skills' "$agy_cfg_dir/skills.json" 2>/dev/null; then
      echo "  * Global Skill Discovery (system-optimizer): [MISCONFIGURED] ($agy_cfg_dir/skills.json exists without $agy_cfg_dir/skills/system-optimizer/SKILL.md — Antigravity's global ~/.gemini/config/skills/ directory scan does not expand skills.json; copy or symlink the skill folder into ~/.gemini/config/skills/system-optimizer/)"
    else
      echo "  * Global Skill Discovery (system-optimizer): [NOT REGISTERED] (Copy into ~/.gemini/config/skills/system-optimizer/ on Windows, or symlink on Linux/macOS)"
    fi

    agy_mcp="$agy_cfg_dir/mcp_config.json"
    if [[ -f "$agy_mcp" ]]; then
      if grep -qE '"serverUrl"[[:space:]]*:|"type"[[:space:]]*:[[:space:]]*"sse"' "$agy_mcp" 2>/dev/null; then
        echo "  * [DEPRECATED] Legacy MCP 'serverUrl' or 'type: sse' found in $agy_mcp (use Streamable HTTP 'url' or stdio 'mcp-remote')"
      else
        echo "  * MCP Config ($agy_mcp): [OK] (no legacy serverUrl/sse entries)"
      fi
    fi

    echo "Performance & Storage Metrics:"
    agy_brain_dir="$agy_cli_dir/brain"
    if [[ -d "$agy_brain_dir" ]]; then
      brain_count=$(find "$agy_brain_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || true)
      stale_brain_count=$(find "$agy_brain_dir" -mindepth 1 -maxdepth 1 -type d -mtime +30 2>/dev/null | wc -l | tr -d ' ' || true)
      brain_size=$(du -sh "$agy_brain_dir" 2>/dev/null | awk '{print $1}' || echo "0")
      echo "  * Saved Brain/Artifacts Sessions: ${brain_count:-0} session dirs ($brain_size disk usage, ${stale_brain_count:-0} stale >30d)"
    fi

    echo "Mise, Herdr & Topgrade Companion Synergies:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      echo "  * Mise Binary Detected: $mise_bin"
      mise_shims="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
      if is_windows; then
        mise_shims="$(win_path_unix "${MISE_DATA_DIR:-$local_app_data/mise}")/shims"
      fi
      if [[ -d "$mise_shims" ]]; then
        echo "  * Mise Shims Directory: [EXISTS] ($mise_shims)"
        if [[ ":$PATH:" == *":$mise_shims:"* ]]; then
          echo "  * Shims on Agent PATH: [ACTIVE] (Subshell commands inherit project-pinned runtimes)"
        else
          echo "  * Shims on Agent PATH: [NOT ON PATH] (Export mise shims on PATH so Antigravity subshells use project-pinned runtimes)"
        fi
      fi
    else
      echo "  * Mise not detected on this system."
    fi

    herdr_bin=$(command -v herdr 2>/dev/null || echo "")
    agy_herdr_hook="$agy_cfg_dir/hooks/herdr-agent-state.sh"
    if [[ -n "$herdr_bin" || -f "$agy_herdr_hook" ]]; then
      if [[ -f "$agy_herdr_hook" ]]; then
        echo "  * Herdr Agent Hook ($agy_herdr_hook): [ACTIVE]"
      else
        echo "  * Herdr Agent Hook: [NOT INSTALLED] (Run 'herdr integration install antigravity-cli')"
      fi
    fi

    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    if [[ -n "$tg_bin" ]]; then
      echo "  * Topgrade Maintenance: [AVAILABLE] (supports native 'antigravity_cli' / 'antigravity' steps)"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Prune stale brain/session artifacts (>30d); keep always-on rules under the 24 KB / 20k-token budget; keep mise shims on PATH"
    echo "  * Configuration: Install global skills under ~/.gemini/config/skills/<skill>/ (copy on Windows, symlink on Linux/macOS); migrate legacy MCP 'serverUrl'/'sse' to Streamable HTTP 'url' or 'mcp-remote'; run 'herdr integration install antigravity-cli' when using Herdr"
    echo "  * Security: Enforce 0600 on oauth_creds.json and mcp_config.json; scope trustedWorkspaces to dedicated workspace dirs (not / or \$HOME); use --sandbox on untrusted repositories and keep allowNonWorkspaceAccess scoped to trusted workflows"
    echo "====================================="
    exit 0
    ;;
  controld|ctrld)
    echo "Category: Network & DNS / Control D Encrypted Resolver Daemon"
    ctrld_bin=$(command -v ctrld 2>/dev/null || command -v controld 2>/dev/null || echo "")
    echo "Binary: ${ctrld_bin:-Not installed}"
    if [[ -n "$ctrld_bin" ]]; then
      ctrld_ver=$(first_clean_line_or "" "$ctrld_bin" version)
      [[ -z "$ctrld_ver" ]] && ctrld_ver=$(first_clean_line_or "unknown" "$ctrld_bin" --version)
      echo "Version: $ctrld_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in \
      "/etc/controld/ctrld.toml" \
      "$roaming_app_data/controld/ctrld.toml" \
      "/c/ProgramData/ControlD/ctrld.toml" \
      "$HOME/.config/controld/ctrld.toml"; do
      [[ -f "$f" ]] || continue
      if [[ ! -r "$f" ]]; then
        echo "  - [NOT READABLE] $f$(cfg_perm_tag "$f") (root-owned; inspect with elevated privileges)"
        continue
      fi
      echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      if grep -qE '^[[:space:]]*ip[[:space:]]*=[[:space:]]*"0\.0\.0\.0"' "$f" 2>/dev/null; then
        echo "  * [WARNING] listener in $f binds 0.0.0.0 (use 127.0.0.1 unless this host serves the LAN)"
      fi
      cd_type=$(toml_section_val "$f" "upstream.0" "type")
      [[ -z "$cd_type" ]] && cd_type=$(toml_section_val "$f" "upstream.1" "type")
      cd_cache=$(toml_section_val "$f" "service" "cache_enable")
      cd_csize=$(toml_section_val "$f" "service" "cache_size")
      cd_imode=$(toml_section_val "$f" "service" "intercept_mode")
      [[ -n "$cd_type" ]] && echo "  * Upstream Protocol: $cd_type"
      [[ -n "$cd_cache" ]] && echo "  * Cache Enabled: $cd_cache (cache_size=${cd_csize:-default})"
      [[ -n "$cd_imode" ]] && echo "  * Intercept Mode: $cd_imode"
    done
    if [[ -n "$ctrld_bin" ]] && ! is_windows; then
      echo "  * Service ctrld: $(first_line_or inactive systemctl is-active ctrld)"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Enable in-memory cache (cache_enable = true, cache_size = 4096); use type = 'doh3' (DNS-over-HTTP/3) primary with 'doh' failover; disable LAN discovery"
    echo "  * Configuration: Local loopback listener 127.0.0.1:53 (restricted = true), adapter DNS integration, log_level = 'notice'"
    echo "  * Security: Encrypted upstream transport (doh3/doh), secure config permissions (0600)"
    echo "====================================="
    exit 0
    ;;
  rustdesk)
    echo "Category: Remote Desktop / RustDesk Remote Access"
    rd_bin=$(command -v rustdesk 2>/dev/null || echo "")
    echo "Binary: ${rd_bin:-Not installed (Windows App or Service)}"
    rd_ver="unknown"
    if [[ -n "$rd_bin" ]]; then
      rd_ver=$(first_clean_line_or "" "$rd_bin" --version)
    fi
    if [[ -z "$rd_ver" || "$rd_ver" == "unknown" ]] && ! is_windows && command -v pacman >/dev/null 2>&1; then
      rd_ver=$(pacman -Q rustdesk-bin rustdesk 2>/dev/null | head -n 1 || true)
    fi
    echo "Version: ${rd_ver:-unknown}"

    echo "Discovered Configuration Files:"
    for f in \
      "$HOME/.config/rustdesk/RustDesk.toml" \
      "$HOME/.config/rustdesk/RustDesk2.toml" \
      "$roaming_app_data/RustDesk/config/RustDesk.toml" \
      "$roaming_app_data/RustDesk/config/RustDesk2.toml" \
      "$roaming_app_data/RustDesk/config/peers.toml" \
      "/c/Windows/ServiceProfiles/LocalService/AppData/Roaming/RustDesk/config/RustDesk2.toml" \
      "/etc/rustdesk/rustdesk.toml"; do
      [[ -f "$f" ]] || continue
      if [[ ! -r "$f" ]]; then
        echo "  - [NOT READABLE] $f$(cfg_perm_tag "$f")"
        continue
      fi
      echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      if grep -qE "verification-method[[:space:]]*=[[:space:]]*['\"]use-permanent-password" "$f" 2>/dev/null; then
        echo "  * [NOTE] $f accepts the permanent password only (a preference: temporary or both passwords, plus approve-mode click, exposes less)"
      fi
      if grep -qiE "direct-server[[:space:]]*=[[:space:]]*['\"]?Y['\"]?" "$f" 2>/dev/null; then
        echo "  * [WARNING] $f enables direct-server = 'Y' (direct IP access exposed; disable unless restricted to trusted LAN)"
      fi
      rd_approve=$(grep -E "approve-mode[[:space:]]*=" "$f" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d " '\"" || true)
      rd_lan=$(grep -E "enable-lan-discovery[[:space:]]*=" "$f" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d " '\"" || true)
      rd_headless=$(grep -E "allow-linux-headless[[:space:]]*=" "$f" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d " '\"" || true)
      [[ -n "$rd_approve" ]] && echo "  * approve-mode: $rd_approve"
      [[ -n "$rd_lan" ]] && echo "  * enable-lan-discovery: $rd_lan"
      [[ -n "$rd_headless" ]] && echo "  * allow-linux-headless: $rd_headless"
    done
    if [[ -n "$rd_bin" ]] && ! is_windows; then
      echo "  * Service rustdesk: $(first_line_or inactive systemctl is-active rustdesk)"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Hardware video acceleration (NVENC on NVIDIA RTX, D3D11/DirectX on Windows, VA-API on Linux)"
    echo "  * Configuration: Custom ID/relay server, on-demand vs background service mode, disable direct-server unless needed"
    echo "  * Security: Strong randomized temporary passwords, approve-mode = 'password-and-click' or 'click', whitelist allowed peer IDs, restrict remote console execution"
    echo "====================================="
    exit 0
    ;;
  mpv)
    echo "Category: Media Player / mpv Video Player"
    mpv_bin=$(command -v mpv 2>/dev/null || echo "")
    echo "Binary: ${mpv_bin:-Not installed}"
    if [[ -n "$mpv_bin" ]]; then
      mpv_ver=$(first_clean_line_or "unknown" "$mpv_bin" --version)
      echo "Version: $mpv_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in \
      "$roaming_app_data/mpv/mpv.conf" \
      "$HOME/.config/mpv/mpv.conf" \
      "$local_app_data/mpv/mpv.conf"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
    done

    mpv_cfg=""
    for f in "$roaming_app_data/mpv/mpv.conf" "$HOME/.config/mpv/mpv.conf" "$local_app_data/mpv/mpv.conf"; do
      if [[ -f "$f" ]]; then
        mpv_cfg="$f"
        break
      fi
    done

    if [[ -n "$mpv_cfg" ]]; then
      echo "Key Parameters in $mpv_cfg:"
      grep -E '^[[:space:]]*(vo|gpu-api|gpu-context|hwdec|profile|hdr-compute-peak|target-colorspace-hint(-mode)?|interpolation|scale|ytdl-format|tone-mapping)[[:space:]]*=' "$mpv_cfg" 2>/dev/null | while read -r line; do
        echo "  * $line"
      done || true
      if grep -qiE '^[[:space:]]*profile[[:space:]]*=[[:space:]]*gpu-hq([[:space:]]|$|#)' "$mpv_cfg" 2>/dev/null; then
        echo "  * [DEPRECATED] profile=gpu-hq is a legacy alias in $mpv_cfg (use profile=high-quality)"
      fi
      if grep -qE '^[[:space:]]*tone-mapping-desaturate(-exponent)?[[:space:]]*=' "$mpv_cfg" 2>/dev/null; then
        echo "  * [DEPRECATED] tone-mapping-desaturate in $mpv_cfg was removed in mpv 0.42 (delete it; gpu-next tone mapping covers it)"
      fi
      if grep -qiE '^[[:space:]]*hwdec[[:space:]]*=[[:space:]]*[a-z0-9]+-copy([[:space:],]|$)' "$mpv_cfg" 2>/dev/null; then
        echo "  * [NOTE] Copyback hwdec (*-copy) forces GPU->RAM->GPU PCIe transfers; prefer zero-copy hwdec=auto-safe unless using CPU video filters"
      fi
      if grep -qiE '^[[:space:]]*[^#]*no-check-certificate' "$mpv_cfg" 2>/dev/null; then
        echo "  * [SECURITY WARNING] 'no-check-certificates' found in $mpv_cfg (disables TLS verification)"
      fi
    fi

    echo "MPV + yt-dlp + GPU HWDEC Companion Synergy:"
    ytdl_bin=$(command -v yt-dlp 2>/dev/null || echo "")
    if [[ -n "$ytdl_bin" ]]; then
      ytdl_ver=$(first_clean_line_or "unknown" "$ytdl_bin" --version)
      echo "  * Media Streamer (yt-dlp): [AVAILABLE] ($ytdl_bin $ytdl_ver)"
    else
      echo "  * Media Streamer (yt-dlp): [NOT FOUND] (Install yt-dlp to stream web video directly to mpv)"
    fi

    detected_gpu="$(get_detected_gpu)"
    hwdec_choice="hwdec=auto-safe (zero-copy default)"
    vo_choice="vo=gpu-next, gpu-api=vulkan (Linux) or d3d11/vulkan (Windows)"
    if [[ "$detected_gpu" =~ (NVIDIA|GeForce|RTX|GTX) ]]; then
      hwdec_choice="hwdec=auto-safe (or nvdec,vulkan,auto zero-copy on NVIDIA)"
    elif [[ "$detected_gpu" =~ (AMD|Radeon) ]]; then
      hwdec_choice="hwdec=auto-safe (or vaapi,vulkan,auto on Linux / d3d11va,vulkan,auto on Windows AMD)"
    elif [[ "$detected_gpu" =~ (Haswell|Ivy[[:space:]]Bridge|Sandy[[:space:]]Bridge|HD[[:space:]]Graphics[[:space:]]4[0-9]{3}) ]]; then
      hwdec_choice="hwdec=auto-safe (Legacy Intel iGPU VA-API)"
      vo_choice="vo=gpu, gpu-api=opengl (Conservative pipeline for legacy Intel iGPU)"
    elif [[ "$detected_gpu" =~ (Intel) ]]; then
      hwdec_choice="hwdec=auto-safe (or vaapi,vulkan,auto on Linux / d3d11va,vulkan,auto on Windows Intel)"
    fi
    echo "  * Hardware Decoder: $hwdec_choice"
    echo "  * Recommended Video Output: $vo_choice"
    echo "  * Browser Bypass: Direct mpv streaming bypasses heavy Chromium/browser CPU and RAM consumption"

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Stream web video directly to mpv via yt-dlp; use $vo_choice, $hwdec_choice, profile=high-quality"
    echo "  * Configuration: Use tone-mapping=auto and target-colorspace-hint=auto (or =yes on HDR displays); bind ytdl-format to 1080p/best"
    echo "  * Security: Enforce TLS certificate verification (never pass no-check-certificates), restrict untrusted lua scripts"
    echo "====================================="
    exit 0
    ;;
  stremio|stremio-linux-shell|stremio-shell|stremio-shell-ng|com.stremio.Stremio)
    echo "Category: Streaming Media Center / Stremio"
    st_fp_info=""
    st_fp_ver=""
    st_fp_inst=""
    st_bin=""
    st_exe=""
    st_has_data=false

    if is_windows; then
      for cand in \
        "$local_app_data/Programs/LNV/Stremio-5/stremio-shell-ng.exe" \
        "$local_app_data/Programs/LNV/Stremio/stremio.exe"; do
        if [[ -f "$cand" ]]; then
          st_exe="$cand"
          break
        fi
      done
      if [[ -z "$st_exe" ]]; then
        st_exe=$(command -v stremio-shell-ng 2>/dev/null || command -v stremio 2>/dev/null || echo "")
      fi
      if [[ -n "$st_exe" ]]; then
        echo "Status: INSTALLED"
        echo "Executable: $st_exe"
        if [[ -f "$st_exe" ]]; then
          st_ver=$(SO_EXE="$st_exe" run_ps '(Get-Item -LiteralPath $env:SO_EXE).VersionInfo.ProductVersion' 2>/dev/null || true)
          echo "Version: ${st_ver:-unknown}"
        else
          echo "Version: unknown"
        fi
      elif [[ -d "$local_app_data/Programs/LNV/Stremio-5" || -d "$local_app_data/Programs/LNV/Stremio" ]]; then
        echo "Status: INSTALLED (directory found; main executable not matched)"
      elif [[ -f "$roaming_app_data/stremio/stremio-server/server-settings.json" || -d "$roaming_app_data/stremio" ]]; then
        st_has_data=true
        echo "Status: user data found, executable not located"
      else
        echo "Status: NOT INSTALLED"
      fi
    else
      st_bin=$(command -v stremio 2>/dev/null || command -v stremio-linux-shell 2>/dev/null || echo "")
      if command -v flatpak >/dev/null 2>&1; then
        st_fp_info=$(flatpak info com.stremio.Stremio 2>/dev/null || true)
        if [[ -n "$st_fp_info" ]]; then
          st_fp_ver=$(printf '%s\n' "$st_fp_info" | awk -F: '/^[[:space:]]*Version:/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }')
          st_fp_inst=$(printf '%s\n' "$st_fp_info" | awk -F: '/^[[:space:]]*Installation:/ { sub(/^[[:space:]]+/, "", $2); print $2; exit }')
        fi
      fi
      [[ -d "$HOME/.var/app/com.stremio.Stremio" || -d "$HOME/.stremio-server" ]] && st_has_data=true

      if [[ -n "$st_bin" || -n "$st_fp_info" ]]; then
        echo "Status: INSTALLED"
        [[ -n "$st_bin" ]] && echo "Native Binary: $st_bin ($(first_clean_line_or "unknown" "$st_bin" --version))"
        if [[ -n "$st_fp_info" ]]; then
          echo "Flatpak Package: com.stremio.Stremio (Version: ${st_fp_ver:-unknown}, Installation: ${st_fp_inst:-unknown})"
        fi
      elif [[ "$st_has_data" == true ]]; then
        echo "Status: user data found, binary not located"
      else
        echo "Status: NOT INSTALLED"
      fi
    fi

    echo "Discovered Streaming Server Configuration Files:"
    st_srv_cfg=""
    st_srv_candidates=()
    if is_windows; then
      st_srv_candidates=(
        "$roaming_app_data/stremio/stremio-server/server-settings.json"
        "$local_app_data/Smart Code ltd/Stremio/server-settings.json"
      )
    else
      st_srv_candidates=(
        "$HOME/.var/app/com.stremio.Stremio/.stremio-server/server-settings.json"
        "$HOME/.var/app/com.stremio.Stremio/data/.stremio-server/server-settings.json"
        "$HOME/.stremio-server/server-settings.json"
        "${XDG_DATA_HOME:-$HOME/.local/share}/Smart Code ltd/Stremio/server-settings.json"
      )
    fi
    for f in "${st_srv_candidates[@]}"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$st_srv_cfg" ]] && st_srv_cfg="$f"
      fi
    done

    echo "Streaming Server Findings:"
    if [[ -z "$st_srv_cfg" ]]; then
      echo "  * Server Settings: [NOT CONFIGURED] (created on first launch; quit Stremio completely before editing)"
    elif [[ ! -r "$st_srv_cfg" ]]; then
      echo "  * Server Settings: [NOT READABLE] $st_srv_cfg"
    else
      st_json=$(cat "$st_srv_cfg" 2>/dev/null || true)
      st_srv_ver=$(ps_json_str "$st_json" "serverVersion" "")
      [[ -n "$st_srv_ver" && "$st_srv_ver" != "unknown" ]] && echo "  * Server Version: $st_srv_ver"

      st_cache_root=$(ps_json_str "$st_json" "cacheRoot" "")
      [[ -n "$st_cache_root" && "$st_cache_root" != "unknown" ]] && echo "  * Cache Root: $st_cache_root"
      st_cache_dir="$(dirname "$st_srv_cfg")/stremio-cache"
      if [[ ! -d "$st_cache_dir" && -n "$st_cache_root" && -d "$st_cache_root/stremio-cache" ]]; then
        st_cache_dir="$st_cache_root/stremio-cache"
      fi
      if [[ -d "$st_cache_dir" ]] && command -v du >/dev/null 2>&1; then
        st_cache_du=$(du -sh "$st_cache_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")
        echo "  * Active Cache Usage ($st_cache_dir): $st_cache_du"
      fi

      if grep -qE '"cacheSize"[[:space:]]*:[[:space:]]*null' <<< "$st_json"; then
        echo "  * cacheSize: [WARNING] unlimited (null) — can fill smaller SSDs; set a bounded cap (e.g. 2 GiB on <=256 GB disks, 5-10 GiB on larger SSDs)"
      else
        st_cache_size=$(ps_json_num "$st_json" "cacheSize" "unset")
        if [[ "$st_cache_size" == "0" ]]; then
          echo "  * cacheSize: [NOTE] disabled (0 bytes — fine for debrid/HTTP streams, can buffer on P2P torrents)"
        elif [[ "$st_cache_size" =~ ^[0-9]+$ ]]; then
          st_cache_gib=$(LC_ALL=C awk -v b="$st_cache_size" 'BEGIN { printf "%.2f", b / 1073741824 }')
          echo "  * cacheSize: [OK] ${st_cache_gib} GiB ($st_cache_size bytes)"
        else
          echo "  * cacheSize: $st_cache_size"
        fi
      fi

      st_bt_conn=$(ps_json_num "$st_json" "btMaxConnections" "unset")
      if [[ "$st_bt_conn" =~ ^-?[0-9]+$ ]]; then
        if (( st_bt_conn <= 0 || st_bt_conn > 300 )); then
          echo "  * btMaxConnections: [WARNING] $st_bt_conn (excessive connections can exhaust consumer router NAT tables; 55-200 is typical)"
        else
          echo "  * btMaxConnections: [OK] $st_bt_conn (default 55; 100-200 helps P2P ramp-up on fast links)"
        fi
      fi

      st_bt_soft=$(ps_json_num "$st_json" "btDownloadSpeedSoftLimit" "unset")
      st_bt_hard=$(ps_json_num "$st_json" "btDownloadSpeedHardLimit" "unset")
      if [[ "$st_bt_hard" =~ ^[0-9]+$ ]]; then
        st_soft_mb=$(LC_ALL=C awk -v b="${st_bt_soft:-0}" 'BEGIN { if (b ~ /^[0-9]+$/) printf "%.2f", b / 1048576; else printf "?" }')
        st_hard_mb=$(LC_ALL=C awk -v b="$st_bt_hard" 'BEGIN { printf "%.2f", b / 1048576 }')
        if (( st_bt_hard > 0 && st_bt_hard <= 4194304 )); then
          echo "  * P2P Speed Limits: [NOTE] Default P2P speed cap (${st_soft_mb}/${st_hard_mb} MiB/s) can bottleneck 4K HDR P2P streams (raise Torrent Profile to Fast/Ultra Fast if using P2P)"
        else
          echo "  * P2P Speed Limits: [OK] soft=${st_soft_mb} MiB/s, hard=${st_hard_mb} MiB/s (0 = uncapped)"
        fi
      fi

      st_hw_transcode=$(ps_json_bool "$st_json" "transcodeHardwareAccel" "unknown")
      case "$st_hw_transcode" in
        true) echo "  * transcodeHardwareAccel: [OK] enabled (GPU hardware transcoding when transcoding is needed)" ;;
        false) echo "  * transcodeHardwareAccel: [NOTE] disabled (CPU software fallback if transcoding is triggered; enable when GPU supports VA-API/NVENC/D3D11VA)" ;;
      esac

      st_remote_https=$(ps_json_str "$st_json" "remoteHttps" "none")
      if [[ -n "$st_remote_https" && "$st_remote_https" != "none" ]]; then
        echo "  * remoteHttps: [WARNING] remote HTTPS endpoint configured ($st_remote_https); ensure TLS, firewall rules, and VPN/LAN restrictions protect port 12470"
      else
        echo "  * remoteHttps: [OK] disabled (local streaming server only)"
      fi

      st_local_addon=$(ps_json_bool "$st_json" "localAddonEnabled" "unknown")
      case "$st_local_addon" in
        true) echo "  * localAddonEnabled: [NOTE] enabled (local media files indexed via local addon)" ;;
        false) echo "  * localAddonEnabled: [OK] disabled" ;;
      esac

      st_proxy_streams=$(ps_json_bool "$st_json" "proxyStreamsEnabled" "unknown")
      [[ "$st_proxy_streams" != "unknown" ]] && echo "  * proxyStreamsEnabled: $st_proxy_streams"
    fi

    echo "Embedded libmpv & Hardware Decoding Synergy:"
    if is_windows; then
      st_win_mpv="$local_app_data/Programs/LNV/Stremio-5/portable_config/mpv.conf"
      if [[ -f "$st_win_mpv" ]]; then
        echo "  - [EXISTS] $st_win_mpv (Stremio 5 portable libmpv config)"
        grep -E '^[[:space:]]*(vo|hwdec|gpu-api|profile)[[:space:]]*=' "$st_win_mpv" 2>/dev/null | sed 's/^/    /' || true
      else
        echo "  * Stremio 5 portable_config/mpv.conf: not present (uses built-in defaults; add portable_config/mpv.conf only if overriding libmpv properties)"
      fi
      [[ -f "$roaming_app_data/mpv/mpv.conf" ]] && echo "  - [EXISTS] $roaming_app_data/mpv/mpv.conf (standalone mpv config)"
    else
      st_mpv_loc=""
      st_kf="$HOME/.var/app/com.stremio.Stremio/config/glib-2.0/settings/keyfile"
      if [[ -f "$st_kf" ]]; then
        st_mpv_loc=$(ini_val "$st_kf" "com/stremio/stremio" "mpv-config-location" || true)
        st_mpv_loc="${st_mpv_loc#\'}"; st_mpv_loc="${st_mpv_loc%\'}"
        st_mpv_loc="${st_mpv_loc#\"}"; st_mpv_loc="${st_mpv_loc%\"}"
      elif command -v gsettings >/dev/null 2>&1; then
        st_gs=$(gsettings get com.stremio.Stremio mpv-config-location 2>/dev/null || true)
        st_gs="${st_gs#\'}"; st_gs="${st_gs%\'}"
        [[ -n "$st_gs" ]] && st_mpv_loc="$st_gs"
      fi
      if [[ -n "$st_mpv_loc" ]]; then
        if [[ -f "$st_mpv_loc" ]]; then
          echo "  * mpv-config-location: [CONFIGURED] $st_mpv_loc (verify vo=libmpv is kept intact)"
        else
          echo "  * mpv-config-location: [WARNING] points to missing file '$st_mpv_loc'"
        fi
      else
        echo "  * mpv-config-location: [NOTE] built-in libmpv defaults (vo=libmpv, hwdec=auto-safe); custom mpv.conf can be linked via mpv-config-location (keep vo=libmpv intact)"
      fi
      for f in "$HOME/.config/mpv/mpv.conf" "$HOME/.var/app/com.stremio.Stremio/config/mpv/mpv.conf"; do
        [[ -f "$f" ]] && echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      done

      st_render=""
      for rn in /dev/dri/renderD*; do
        [[ -e "$rn" ]] && { st_render="$rn"; break; }
      done
      if [[ -n "$st_render" ]]; then
        echo "  * DRM Render Node: [OK] $st_render (available for VA-API/Vulkan hardware decode)"
      else
        echo "  * DRM Render Node: [NOTE] none found under /dev/dri/renderD* (hardware decode unavailable in this environment)"
      fi

      if [[ -n "$st_fp_info" || -d "$HOME/.var/app/com.stremio.Stremio" ]]; then
        st_fp_ov="$HOME/.local/share/flatpak/overrides/com.stremio.Stremio"
        if [[ -f "$st_fp_ov" ]]; then
          echo "  - [EXISTS] $st_fp_ov$(cfg_perm_tag "$st_fp_ov")"
          if grep -qE '^[[:space:]]*filesystems?=([^#]*;)?(host|host-os|host-etc|home|/)($|;|:rw)' "$st_fp_ov" 2>/dev/null; then
            echo "  * Flatpak Override: [WARNING] grants broad filesystem access (host/home) to com.stremio.Stremio"
          fi
        fi
        st_va_name=$(env_val LIBVA_DRIVER_NAME)
        if [[ -n "$st_va_name" ]]; then
          if [[ -f "$st_fp_ov" ]] && grep -qE "^[[:space:]]*LIBVA_DRIVER_NAME=${st_va_name}([[:space:]]|$)" "$st_fp_ov" 2>/dev/null; then
            echo "  * Flatpak LIBVA_DRIVER_NAME: [OK] $st_va_name forwarded in override"
          else
            echo "  * Flatpak LIBVA_DRIVER_NAME: [NOTE] Host sets LIBVA_DRIVER_NAME=$st_va_name, which Flatpak does not inherit automatically (forward with: flatpak override --user --env=LIBVA_DRIVER_NAME=$st_va_name com.stremio.Stremio if VA-API decode fails)"
          fi
        fi
      fi
    fi

    echo "Streaming Server Port Security (11470 / 12470):"
    st_listeners=""
    if is_windows; then
      if command -v netstat >/dev/null 2>&1; then
        st_listeners=$(netstat -ano -p tcp 2>/dev/null | awk 'toupper($0) ~ /LISTENING/ && $2 ~ /:(11470|12470)$/ {print $2}' | sort -u || true)
      fi
    elif command -v ss >/dev/null 2>&1; then
      st_listeners=$(ss -tlnH 2>/dev/null | awk '$4 ~ /:(11470|12470)$/ {print $4}' | sort -u || true)
    fi
    if [[ -n "$st_listeners" ]]; then
      st_wild=""
      st_loop=""
      while IFS= read -r st_ep; do
        [[ -n "$st_ep" ]] || continue
        if [[ "$st_ep" =~ ^(0\.0\.0\.0|\*|\[::\]): ]]; then
          st_wild+="$st_ep "
        else
          st_loop+="$st_ep "
        fi
      done <<< "$st_listeners"
      if [[ -n "$st_wild" ]]; then
        echo "  * Port Exposure: [SECURITY WARNING] Streaming server listening on all interfaces (${st_wild% }); restrict to 127.0.0.1 or firewall ports 11470/12470"
      else
        echo "  * Port Exposure: [OK] listening on loopback only (${st_loop% })"
      fi
    else
      echo "  * Port Exposure: [OK] streaming server not currently listening (starts on demand with Stremio)"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Keep hardware-accelerated decoding enabled (hwdec=auto-safe in embedded libmpv; forward LIBVA_DRIVER_NAME in Flatpak override on legacy Intel iGPUs), size cacheSize to disk/RAM tier (2 GiB small-SSD/low-RAM, 5-10 GiB larger SSDs), raise Torrent Profile (btDownloadSpeed*Limit, btMaxConnections 55-200) if 4K P2P streams buffer, and enable transcodeHardwareAccel where GPU supports it"
    echo "  * Configuration: Quit Stremio and its server process before editing server-settings.json (otherwise overwritten on exit); when linking a custom mpv.conf (mpv-config-location on Linux / portable_config/mpv.conf on Windows Stremio 5), keep vo=libmpv intact"
    echo "  * Security: Keep streaming server loopback-only (127.0.0.1:11470, remoteHttps: \"\" unless behind authenticated HTTPS/VPN), keep .stremio-server mode 0700 (or server-settings.json 0600), audit third-party community addons, and avoid broad Flatpak filesystems=host overrides"
    echo "====================================="
    exit 0
    ;;
  topgrade)
    echo "Category: Maintenance & Update Orchestrator / Topgrade"
    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    echo "Binary: ${tg_bin:-Not installed}"
    if [[ -n "$tg_bin" ]]; then
      tg_ver=$(first_clean_line_or "unknown" "$tg_bin" --version)
      echo "Version: $tg_ver"
    fi

    echo "Discovered Configuration Files:"
    tg_cfg=""
    tg_files=()
    for f in "$roaming_app_data/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$tg_cfg" ]] && tg_cfg="$f"
        tg_files+=("$f")
      fi
    done
    tg_d_dir="${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.d"
    if [[ -d "$tg_d_dir" ]]; then
      echo "  - [EXISTS DIR] $tg_d_dir"
      for df in "$tg_d_dir"/*.toml; do
        if [[ -f "$df" ]]; then
          echo "  - [EXISTS] $df$(cfg_perm_tag "$df")"
          tg_files+=("$df")
        fi
      done
    fi

    if [[ ${#tg_files[@]} -gt 0 ]]; then
      echo "Active Topgrade Configuration:"
      cleanup_val=""
      retry_val=""
      pre_sudo_val=""
      sudo_loop_val=""
      dis_val=""
      tg_has_mise=""
      tg_bump=""
      tg_jobs=""
      tg_reshim=""
      tg_win_accept=""
      tg_win_sudo=""
      tg_dup_gh_ext=""
      for tf in "${tg_files[@]}"; do
        [[ -z "$cleanup_val" ]] && cleanup_val=$(toml_section_val "$tf" "misc" "cleanup")
        [[ -z "$cleanup_val" ]] && cleanup_val=$(toml_section_val "$tf" "" "cleanup")
        [[ -z "$retry_val" ]] && retry_val=$(toml_section_val "$tf" "misc" "ask_retry")
        [[ -z "$retry_val" ]] && retry_val=$(toml_section_val "$tf" "" "ask_retry")
        [[ -z "$pre_sudo_val" ]] && pre_sudo_val=$(toml_section_val "$tf" "misc" "pre_sudo")
        [[ -z "$pre_sudo_val" ]] && pre_sudo_val=$(toml_section_val "$tf" "" "pre_sudo")
        [[ -z "$sudo_loop_val" ]] && sudo_loop_val=$(toml_section_val "$tf" "misc" "sudo_loop")
        [[ -z "$sudo_loop_val" ]] && sudo_loop_val=$(toml_section_val "$tf" "" "sudo_loop")
        arr=$(toml_extract_array "$tf" "disable")
        [[ -n "$arr" ]] && dis_val="$dis_val $arr"
        grep -qE '^[[:space:]]*\[mise\]' "$tf" 2>/dev/null && tg_has_mise="yes"
        [[ -z "$tg_bump" ]] && tg_bump=$(toml_section_val "$tf" "mise" "bump")
        [[ -z "$tg_jobs" ]] && tg_jobs=$(toml_section_val "$tf" "mise" "jobs")
        grep -qi "reshim" "$tf" 2>/dev/null && tg_reshim="yes"
        [[ -z "$tg_win_accept" ]] && tg_win_accept=$(toml_section_val "$tf" "windows" "accept_all_updates")
        [[ -z "$tg_win_sudo" ]] && tg_win_sudo=$(toml_section_val "$tf" "windows" "winget_use_sudo")
        grep -qi "gh extension upgrade" "$tf" 2>/dev/null && tg_dup_gh_ext="yes"
      done
      dis_val="${dis_val:-[]}"
      echo "  * Post-Run Cleanup: ${cleanup_val:-false}"
      echo "  * Ask Retry: ${retry_val:-true}"
      echo "  * Disabled Steps: $dis_val"
      echo "  * Pre-Sudo Credential Cache: ${pre_sudo_val:-false}"
      if [[ "$sudo_loop_val" == "true" ]]; then
        echo "  * [NOTE] sudo_loop = true keeps sudo cached (avoid leaving unattended terminals open)"
      fi
      if is_windows || [[ -n "$tg_win_accept" || -n "$tg_win_sudo" ]]; then
        echo "  * [windows] accept_all_updates: ${tg_win_accept:-unset}, winget_use_sudo: ${tg_win_sudo:-unset}"
      fi
      if [[ -n "$tg_dup_gh_ext" ]]; then
        echo "  * [NOTE] Manual 'gh extension upgrade' found in config; Topgrade 17+ handles this natively via github_cli_extensions"
      fi

      echo "Mise Companion Integration in Topgrade:"
      mise_bin=$(command -v mise 2>/dev/null || echo "")
      if [[ -n "$mise_bin" ]]; then
        echo "  * Mise Binary Detected: $mise_bin"
        echo "  * [mise] Section in topgrade config: $(if [[ -n "$tg_has_mise" ]]; then echo "Configured (bump=${tg_bump:-false}, jobs=${tg_jobs:-mise default})"; else echo "Missing / Using defaults (bump=false)"; fi)"
        echo "  * Post-Upgrade 'mise reshim' Hook: $(if [[ -n "$tg_reshim" ]]; then echo "Present in post_commands"; else echo "Missing (Add to post_commands to synchronize shims)"; fi)"
        echo "  * Redundant Runtime Self-Updater Conflicts: $(if echo "$dis_val" | grep -qi "uv"; then echo "uv disabled in topgrade (Prevented collision with mise)"; else echo "uv not disabled (May run duplicate self-update if managed by mise)"; fi)"
        echo "  * Rust Compilation De-duplication: $(if echo "$dis_val" | grep -qi "cargo"; then echo "cargo disabled in topgrade (Prevents slow from-source rebuilds, managed via mise binstall)"; else echo "cargo active in topgrade (Will compile from source; consider disabling if using mise cargo.binstall)"; fi)"
        pi_bin_tg=$(command -v pi 2>/dev/null || echo "")
        if [[ "$pi_bin_tg" == *"mise"* ]] || "$mise_bin" ls pi 2>/dev/null | grep -q .; then
          echo "  * Pi Agent Step De-duplication: $(if echo "$dis_val" | grep -qiE '(^|[^a-z])pi([^a-z]|$)'; then echo "pi disabled in topgrade (Prevented dual-updater collision with mise)"; else echo "pi managed by mise but not in disable (Add 'pi' alongside 'uv'/'cargo' in disable)"; fi)"
        fi
      else
        echo "  * Mise is not currently installed on this system."
      fi
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Enable cleanup = true (runs mise prune and cleans package caches); bound [mise] jobs to $detected_threads; disable uninstalled or mise-managed steps ('uv', 'cargo', 'pi')"
    echo "  * Configuration: Set [mise] bump = true and 'mise reshim' in [post_commands]; on Windows set [windows] accept_all_updates = true and winget_use_sudo = false; rely on native github_cli_extensions step"
    echo "  * Security: Set [misc] allow_root = false; restrict untrusted custom [commands]; avoid unattended sudo_loop = true; enforce 0600 on topgrade.toml"
    echo "====================================="
    exit 0
    ;;
  mise|rtx)
    echo "Category: Polyglot Tool & Runtime Manager / mise"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    echo "Binary: ${mise_bin:-Not installed}"
    if [[ -n "$mise_bin" ]]; then
      mise_ver=$(first_clean_line_or "unknown" "$mise_bin" --version)
      echo "Version: $mise_ver"
      if is_windows; then
        echo "Platform: Windows (Native / shims)"
      else
        if command -v pacman >/dev/null 2>&1 && pacman -Qo "$mise_bin" >/dev/null 2>&1; then
          pkg_owner=$(pacman -Qo "$mise_bin" 2>/dev/null || true)
          echo "Installation Method: Package Manager ($pkg_owner)"
        else
          echo "Installation Method: Standalone Binary ($mise_bin)"
        fi
      fi
    fi

    echo "Discovered Configuration Files:"
    mise_cfg_dir="${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"
    mise_cfg=""
    mise_toml_files=()
    for f in "$mise_cfg_dir/config.toml" "$roaming_app_data/mise/config.toml" "$local_app_data/mise/config.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$mise_cfg" ]] && mise_cfg="$f"
        mise_toml_files+=("$f")
      fi
    done
    if [[ -d "$mise_cfg_dir/conf.d" ]]; then
      for cf in "$mise_cfg_dir/conf.d"/*.toml; do
        if [[ -f "$cf" ]]; then
          echo "  - [EXISTS] $cf$(cfg_perm_tag "$cf")"
          mise_toml_files+=("$cf")
        fi
      done
    fi
    if [[ -f "$mise_cfg_dir/settings.toml" ]]; then
      echo "  - [LEGACY] $mise_cfg_dir/settings.toml$(cfg_perm_tag "$mise_cfg_dir/settings.toml") -> migrate to config.toml [settings]"
      mise_toml_files+=("$mise_cfg_dir/settings.toml")
    fi

    mise_setting_val() {
      local key="$1" default="$2" val="" sec="" subk="$1" mf=""
      if [[ -n "$mise_bin" ]]; then
        val=$(first_clean_line_or "" "$mise_bin" settings get "$key")
      fi
      if [[ -z "$val" ]]; then
        if [[ "$key" == *.* ]]; then
          sec="settings.${key%.*}"
          subk="${key#*.}"
        else
          sec="settings"
        fi
        for mf in "${mise_toml_files[@]}"; do
          val=$(toml_section_val "$mf" "$sec" "$subk")
          [[ -z "$val" && "$key" == *.* ]] && val=$(toml_section_val "$mf" "settings" "$key")
          [[ -z "$val" ]] && val=$(toml_section_val "$mf" "" "$key")
          [[ -n "$val" ]] && break
        done
      fi
      printf '%s' "${val:-$default}"
    }

    if [[ -n "$mise_bin" || ${#mise_toml_files[@]} -gt 0 ]]; then
      echo "Active Mise Settings ($(if [[ -n "$mise_bin" ]]; then echo "live mise settings + TOML"; else echo "${mise_cfg:-TOML}"; fi)):"
      m_jobs=$(mise_setting_val "jobs" "default (4)")
      m_env_cache=$(mise_setting_val "env_cache" "false")
      m_env_cache_ttl=$(mise_setting_val "env_cache_ttl" "1h")
      m_pin=$(mise_setting_val "pin" "false")
      m_prune_age=$(mise_setting_val "cache_prune_age" "30d")
      m_binstall=$(mise_setting_val "cargo.binstall" "true")
      m_dl_cache=$(mise_setting_val "download_cache" "true")
      m_dl_max=$(mise_setting_val "download_cache_max_size" "2GiB")
      m_auto_prune=$(mise_setting_val "upgrade.auto_prune" "true")
      m_min_age=$(mise_setting_val "minimum_release_age" "unset")
      m_npm_prov=$(mise_setting_val "npm.provenance" "true")
      echo "  * Parallel Jobs: $m_jobs (Hardware thread budget: $detected_threads)"
      echo "  * Environment Caching (env_cache): $m_env_cache (ttl=$m_env_cache_ttl)"
      echo "  * Download Cache: $m_dl_cache (max_size=$m_dl_max)"
      echo "  * Version Pinning (pin): $m_pin"
      echo "  * Cache Prune Age: $m_prune_age (upgrade.auto_prune=$m_auto_prune)"
      echo "  * Cargo Binstall (cargo.binstall): $m_binstall"
      echo "  * Supply-Chain Guards: minimum_release_age=$m_min_age, npm.provenance=$m_npm_prov"

      for mf in "${mise_toml_files[@]}"; do
        if grep -qE '^[[:space:]]*always_keep_download[[:space:]]*=' "$mf" 2>/dev/null; then
          echo "  * [DEPRECATED] always_keep_download found in $mf (replaced by download_cache = true / download_cache_max_size; removed in mise 2027.11.0)"
        fi
        if grep -qE '^[[:space:]]*allow_root[[:space:]]*=' "$mf" 2>/dev/null; then
          echo "  * [WARNING] Invalid setting 'allow_root' in $mf (unknown in mise — allow_root belongs in topgrade.toml [misc])"
        fi
      done
    fi

    if [[ -n "$mise_bin" ]]; then
      echo "Mise Runtime & Tool Summary:"
      tool_count=$("$mise_bin" ls --current 2>/dev/null | wc -l | tr -d ' ' || true)
      echo "  * Active/Managed Tools: $tool_count installed"
    fi

    echo "Topgrade Integration Status:"
    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    if [[ -n "$tg_bin" ]]; then
      tg_cfg=""
      tg_all=()
      for tf in "$roaming_app_data/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.toml"; do
        if [[ -f "$tf" ]]; then
          [[ -z "$tg_cfg" ]] && tg_cfg="$tf"
          tg_all+=("$tf")
        fi
      done
      for df in "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.d"/*.toml; do
        [[ -f "$df" ]] && tg_all+=("$df")
      done
      if [[ ${#tg_all[@]} -gt 0 ]]; then
        tg_has_mise_table=""
        tg_mise_bump=""
        tg_mise_jobs=""
        tg_cleanup=""
        tg_has_reshim=""
        for tf in "${tg_all[@]}"; do
          grep -qE '^[[:space:]]*\[mise\]' "$tf" 2>/dev/null && tg_has_mise_table="yes"
          [[ -z "$tg_mise_bump" ]] && tg_mise_bump=$(toml_section_val "$tf" "mise" "bump")
          [[ -z "$tg_mise_jobs" ]] && tg_mise_jobs=$(toml_section_val "$tf" "mise" "jobs")
          [[ -z "$tg_cleanup" ]] && tg_cleanup=$(toml_section_val "$tf" "misc" "cleanup")
          [[ -z "$tg_cleanup" ]] && tg_cleanup=$(toml_section_val "$tf" "" "cleanup")
          grep -qi "reshim" "$tf" 2>/dev/null && tg_has_reshim="yes"
        done
        echo "  - Topgrade Config: ${tg_cfg:-${tg_all[0]}}"
        echo "  - Native [mise] Step in Topgrade: $(if [[ -n "$tg_has_mise_table" ]]; then echo "Configured (bump=${tg_mise_bump:-false}, jobs=${tg_mise_jobs:-mise default})"; else echo "Default/Unconfigured"; fi)"
        echo "  - Automated Cache/Version Pruning: $(if [[ "$tg_cleanup" == "true" ]]; then echo "Enabled (Topgrade runs mise prune during cleanup)"; else echo "Disabled (Set cleanup = true)"; fi)"
        echo "  - Post-Update Shim Sync (mise reshim): $(if [[ -n "$tg_has_reshim" ]]; then echo "Configured in post_commands"; else echo "Not detected in post_commands (Recommended)"; fi)"
      else
        echo "  - Topgrade installed but topgrade.toml not yet found."
      fi
    else
      echo "  - Topgrade not installed (Recommended companion for workstation maintenance orchestration)."
    fi

    echo "Neovim Companion Status:"
    nv_bin=$(command -v nvim 2>/dev/null || command -v neovim 2>/dev/null || echo "")
    if [[ -n "$nv_bin" ]]; then
      nv_cfg=""
      for nf in "$local_app_data/nvim/init.lua" "$HOME/.config/nvim/init.lua"; do
        [[ -f "$nf" ]] && nv_cfg="$nf" && break
      done
      echo "  - Neovim Binary Detected: $nv_bin"
      echo "  - Config: ${nv_cfg:-Not found}"
      echo "  - LSP Provisioning: Mise shims serve as single-source polyglot LSP, formatter, linter & DAP runtime"
      if [[ -n "$nv_cfg" ]]; then
        nv_dir=$(dirname "$nv_cfg")
        if [[ -d "$nv_dir/lua" ]] && grep -rqE 'opts_extend[[:space:]]*=[[:space:]]*\{\}' "$nv_dir/lua" 2>/dev/null && grep -rqE 'mason[[:space:]]*=[[:space:]]*false' "$nv_dir/lua" 2>/dev/null; then
          echo "  - Mason De-duplication: [LOCKED] (opts_extend = {} & mason = false prevent duplicate Mason installs)"
        fi
        if [[ -d "$nv_dir/lua" ]] && grep -rq "mise_env_sync" "$nv_dir/lua" 2>/dev/null; then
          echo "  - Dynamic Project Env Sync: [ACTIVE] (DirChanged -> mise env --json)"
        fi
      fi
    else
      echo "  - Neovim not installed on this system."
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Match jobs = $detected_threads; enable env_cache = true (env_cache_ttl = '1h'); use download_cache = true with download_cache_max_size = '2GiB' (not always_keep_download); enable cargo.binstall = true"
    echo "  * Configuration: Set pin = true, cache_prune_age = '7d', upgrade.auto_prune = true; place overrides in conf.d/*.toml; integrate with topgrade ([mise] bump = true, cleanup = true, mise reshim in post_commands)"
    echo "  * Security: Enforce minimum_release_age, npm.provenance = true, aqua.slsa, aqua.cosign, github_attestations, node.verify; restrict config permissions (0600); isolate runtime installs"
    echo "====================================="
    exit 0
    ;;
  cargo|rust|rustc)
    echo "Category: Toolchain & Package Manager / Cargo & Rust"
    cg_bin=$(command -v cargo 2>/dev/null || echo "")
    echo "Binary: ${cg_bin:-Not installed}"
    if [[ -n "$cg_bin" ]]; then
      cg_ver=$(first_clean_line_or "unknown" "$cg_bin" --version)
      rc_ver=$(first_clean_line_or "unknown" rustc --version)
      echo "Version: $cg_ver (rustc: $rc_ver)"
    fi

    echo "Discovered Configuration Files:"
    cg_home="${CARGO_HOME:-$HOME/.cargo}"
    cg_cfg=""
    for f in "$cg_home/config.toml" "${USERPROFILE:-/nonexistent}/.cargo/config.toml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$cg_cfg" ]] && cg_cfg="$f"
      fi
    done
    for leg_f in "$cg_home/config" "${USERPROFILE:-/nonexistent}/.cargo/config"; do
      if [[ -f "$leg_f" ]]; then
        echo "  - [DEPRECATED] $leg_f$(cfg_perm_tag "$leg_f") -> rename extensionless 'config' to 'config.toml'"
        [[ -z "$cg_cfg" ]] && cg_cfg="$leg_f"
      fi
    done

    if [[ -n "$cg_cfg" ]]; then
      echo "Active Cargo Configuration ($cg_cfg):"
      c_jobs=$(toml_section_val "$cg_cfg" "build" "jobs")
      c_gitcli=$(toml_section_val "$cg_cfg" "net" "git-fetch-with-cli")
      echo "  * Parallel Build Jobs: ${c_jobs:-default (logical CPUs)}"
      echo "  * Git Fetch with CLI: ${c_gitcli:-false}"
    fi

    if [[ -d "$cg_home/registry/cache" || -d "$cg_home/git/db" ]]; then
      echo "Cargo Cache Footprint ($cg_home):"
      [[ -d "$cg_home/registry/cache" ]] && echo "  * Registry Cache: $(du -sh "$cg_home/registry/cache" 2>/dev/null | awk '{print $1}' || echo unknown)"
      [[ -d "$cg_home/git/db" ]] && echo "  * Git DB Cache: $(du -sh "$cg_home/git/db" 2>/dev/null | awk '{print $1}' || echo unknown)"
    fi

    echo "Mise & Topgrade Companion Integration:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      m_binstall=$(first_clean_line_or "" "$mise_bin" settings get cargo.binstall)
      if [[ -z "$m_binstall" ]]; then
        for mf in "${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/config.toml" "${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/conf.d"/*.toml "$roaming_app_data/mise/config.toml" "$local_app_data/mise/config.toml"; do
          [[ -f "$mf" ]] || continue
          m_binstall=$(toml_section_val "$mf" "settings.cargo" "binstall")
          [[ -z "$m_binstall" ]] && m_binstall=$(toml_section_val "$mf" "settings" "cargo.binstall")
          [[ -n "$m_binstall" ]] && break
        done
      fi
      m_binstall="${m_binstall:-true}"
      echo "  * Mise Cargo Binstall: $(if [[ "$m_binstall" == "true" ]]; then echo "[ENABLED] (Pre-compiled Rust binaries prioritized)"; else echo "[DISABLED] (Consider enabling cargo.binstall = true)"; fi)"
    else
      echo "  * Mise is not installed."
    fi

    tg_bin=$(command -v topgrade 2>/dev/null || echo "")
    if [[ -n "$tg_bin" ]]; then
      tg_dis=""
      for tf in "$roaming_app_data/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.d"/*.toml; do
        [[ -f "$tf" ]] || continue
        tg_dis="$tg_dis $(toml_extract_array "$tf" "disable")"
      done
      if [[ -n "${tg_dis// /}" ]]; then
        echo "  * Topgrade Cargo Step: $(if echo "$tg_dis" | grep -qi "cargo"; then echo "[DISABLED] (Eliminated slow from-source rebuilds, delegated to mise binstall)"; else echo "[ACTIVE] (Will compile CLI tools from source; consider adding 'cargo' to disable = [...])"; fi)"
      fi
    else
      echo "  * Topgrade is not installed."
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Rely on Cargo's default sparse protocol & num_cpus jobs (rustc 1.100+ uses rust-lld by default on Linux x86_64; mold optional); set net.git-fetch-with-cli = true; prune caches with cargo-cache/cargo-sweep; prefer mise cargo.binstall = true"
    echo "  * Configuration: Disable 'cargo' step in topgrade.toml (disable = ['cargo']) when managing Rust CLIs via mise; keep target-cpu=native per-project rather than global"
    echo "  * Security: Run cargo audit for supply-chain vulnerability audits; enforce Cargo.lock checksums; restrict ~/.cargo/config.toml and credentials.toml to 0600"
    echo "====================================="
    exit 0
    ;;
  ripgrep|rg)
    echo "Category: Search Utility / ripgrep (rg)"
    rg_bin=$(command -v rg 2>/dev/null || command -v ripgrep 2>/dev/null || echo "")
    echo "Binary: ${rg_bin:-Not installed}"
    if [[ -n "$rg_bin" ]]; then
      rg_ver=$(first_clean_line_or "unknown" "$rg_bin" --version)
      echo "Version: $rg_ver"
    fi

    echo "Environment & Configuration Files:"
    echo "  * RIPGREP_CONFIG_PATH: $(env_show RIPGREP_CONFIG_PATH)"
    rg_cfg_env=$(env_val RIPGREP_CONFIG_PATH)
    fzf_cmd_env=$(env_val FZF_DEFAULT_COMMAND)
    rg_cfgs=()
    for f in "$rg_cfg_env" "$HOME/.ripgreprc" "${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config" "$roaming_app_data/ripgrep/config"; do
      [[ -n "$f" && -f "$f" ]] || continue
      seen=0
      for existing in "${rg_cfgs[@]}"; do
        [[ "$existing" == "$f" ]] && seen=1 && break
      done
      [[ "$seen" -eq 1 ]] && continue
      rg_cfgs+=("$f")
      echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      if grep -qE '^[[:space:]]*--mmap([[:space:]]|$)' "$f" 2>/dev/null; then
        echo "  * [WARNING] --mmap forced in $f (ripgrep auto-enables mmap heuristically; forcing --mmap hurts parallel traversal and risks SIGBUS on truncated files)"
      fi
    done

    echo "Ripgrep + FZF + Bat Synergy Integration:"
    if [[ "$fzf_cmd_env" =~ (^|[^A-Za-z0-9_])(rg|ripgrep)([^A-Za-z0-9_]|$) ]]; then
      echo "  * FZF Backend: [WIRED] (rg is active search generator in FZF_DEFAULT_COMMAND)"
    elif [[ "$fzf_cmd_env" =~ (^|[^A-Za-z0-9_])(fd|fdfind)([^A-Za-z0-9_]|$) ]]; then
      echo "  * FZF Backend: [CONFIGURED] (fd is active in FZF_DEFAULT_COMMAND; rg serves content search)"
    else
      echo "  * FZF Backend: [RECOMMENDED] (Wire rg or fd as backend: export FZF_DEFAULT_COMMAND=\"rg --files --hidden --glob '!.git/*'\")"
    fi
    bat_bin=$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || echo "")
    if [[ -n "$bat_bin" ]]; then
      echo "  * Bat Previewer: [AVAILABLE] ($bat_bin provides line-numbered syntax previews)"
    else
      echo "  * Bat Previewer: [NOT FOUND]"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Set RIPGREP_CONFIG_PATH, set --max-columns=300 and --max-columns-preview (avoid forcing --mmap or hardcoded --threads)"
    echo "  * Configuration: Enable --smart-case by default, wire rg/fd as FZF_DEFAULT_COMMAND backend with bat syntax previews, global ignore globs (!.git, !node_modules)"
    echo "  * Security: Ignore hidden git internal files (--glob=!.git/*) to prevent credential leakage in search results"
    echo "====================================="
    exit 0
    ;;
  zoxide)
    echo "Category: Navigation / zoxide Directory Jumper"
    zo_bin=$(command -v zoxide 2>/dev/null || echo "")
    echo "Binary: ${zo_bin:-Not installed}"
    if [[ -n "$zo_bin" ]]; then
      zo_ver=$(first_clean_line_or "unknown" "$zo_bin" --version)
      echo "Version: $zo_ver"
    fi

    echo "Database & Configuration Locations:"
    for f in "$local_app_data/zoxide/db.zo" "${XDG_DATA_HOME:-$HOME/.local/share}/zoxide/db.zo" "${XDG_CONFIG_HOME:-$HOME/.config}/zoxide"; do
      if [[ -d "$f" ]]; then
        echo "  - [EXISTS DIR] $f"
      elif [[ -e "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      fi
    done

    if command -v zoxide >/dev/null 2>&1; then
      db_count=$(zoxide query -l 2>/dev/null | wc -l | tr -d ' ' || true)
      echo "Tracked Directories in Database: $db_count entries"
    fi

    echo "Shell Integration:"
    if is_windows || command -v pwsh >/dev/null 2>&1; then
      pwsh_prof="$HOME/.config/powershell/Microsoft.PowerShell_profile.ps1"
      is_windows && pwsh_prof="$HOME/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
      if [[ -f "$pwsh_prof" ]] && grep -qi "zoxide init" "$pwsh_prof"; then
        echo "  * PowerShell ($pwsh_prof): [INITIALIZED]"
      else
        echo "  * PowerShell: [NOT CONFIGURED] (Recommend: Invoke-Expression (& { (zoxide init powershell | Out-String) }))"
      fi
    fi
    if rc_lines 'zoxide init' >/dev/null; then
      echo "  * Shell Startup Hooks:"
      rc_lines 'zoxide init'
    else
      echo "  * Shell Startup Hooks: [NOT CONFIGURED] in the files read: $(rc_read)(Recommend: eval \"\$(zoxide init bash)\")"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Statically cache or fast-init zoxide hook in shell profiles; periodically prune dead paths (zoxide remove)"
    if is_windows; then
      echo "  * Configuration: Define aliases 'z' (jump) and 'zi' (interactive fzf jump); set semicolon-delimited _ZO_EXCLUDE_DIRS on Windows (note \$HOME is excluded by default)"
    else
      echo "  * Configuration: Define aliases 'z' (jump) and 'zi' (interactive fzf jump); set colon-delimited _ZO_EXCLUDE_DIRS on Unix (note \$HOME is excluded by default)"
    fi
    echo "  * Security: Keep the zoxide data directory at 0700 (zoxide rewrites db.zo with 0666 & ~umask on every jump, so a chmod 0600 on the file alone does not stick)"
    echo "====================================="
    exit 0
    ;;
  eza)
    echo "Category: Modern File Lister / eza"
    eza_bin=$(command -v eza 2>/dev/null || echo "")
    echo "Binary: ${eza_bin:-Not installed}"
    if [[ -n "$eza_bin" ]]; then
      eza_raw=$("$eza_bin" --version 2>/dev/null || true)
      eza_ver=$(printf '%s\n' "$eza_raw" | strip_ansi | awk 'NR==2 && NF { out=$0 } END { if (out != "") printf "%s", out }')
      [[ -z "$eza_ver" ]] && eza_ver=$(first_clean_line_or "unknown" "$eza_bin" --version)
      echo "Version: $eza_ver"
    fi

    echo "Discovered Configuration Files:"
    eza_cfg_dir="${EZA_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/eza}"
    for f in "$roaming_app_data/eza/theme.yml" "$eza_cfg_dir/theme.yml"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
    done

    echo "Aliases in shell startup files:"
    if rc_lines '(^|[^A-Za-z0-9_])eza([^A-Za-z0-9_]|$)'; then
      # An icons flag without a value takes the next word as its value on recent eza, so "ls /path" fails.
      if rc_lines "(^|[^A-Za-z0-9_])eza[^#]*--icon[s]([^=]|\$)" >/dev/null; then
        echo "  * Icons flag: [MISCONFIGURED] icons flag without a value (Use =auto: it also keeps icons out of pipes)"
      else
        echo "  * Icons flag: [OK]"
      fi
      if rc_lines "(^|[^A-Za-z0-9_])eza[^#]*--no-dereference" >/dev/null; then
        echo "  * [WARNING] '--no-dereference' found in eza alias (not a valid eza flag; eza already skips symlink traversal by default)"
      fi
    else
      echo "  * eza alias: [NOT CONFIGURED] in the files read: $(rc_read)(files they source are not followed) (Recommend: alias ls='eza --icons=auto')"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Avoid default --git scanning on large repositories or deep tree walks; bind --git only to detailed alias ('ll')"
    echo "  * Configuration: Set ergonomic aliases in pwsh & bash: ls='eza --icons=auto', ll='eza -l --icons=auto --git --header', lt='eza --tree --level=2'; configure EZA_CONFIG_DIR/theme.yml"
    echo "  * Security: eza does not dereference symlinks by default (avoid -X/--dereference on untrusted trees); avoid --icons=always in scripts"
    echo "====================================="
    exit 0
    ;;
  lazygit)
    echo "Category: Git Terminal UI / lazygit"
    lg_bin=$(command -v lazygit 2>/dev/null || echo "")
    echo "Binary: ${lg_bin:-Not installed}"
    if [[ -n "$lg_bin" ]]; then
      lg_ver=$(first_clean_line_or "unknown" "$lg_bin" --version)
      echo "Version: $lg_ver"
    fi

    echo "Discovered Configuration Files:"
    lg_cfg=""
    for f in "$roaming_app_data/lazygit/config.yml" "$local_app_data/lazygit/config.yml" "${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$lg_cfg" ]] && lg_cfg="$f"
      fi
    done

    if [[ -n "$lg_cfg" ]]; then
      echo "Key Configuration Parameters:"
      grep -E '^[[:space:]]*(autoFetch|editPreset|edit|animateExplosion|nerdFontsVersion|showIcons|diffRenderers|paging|pagers):' "$lg_cfg" 2>/dev/null | while read -r line; do
        echo "  * $line"
      done || true
      if grep -qE '^[[:space:]]*(paging|pagers):' "$lg_cfg" 2>/dev/null; then
        echo "  * [DEPRECATED] git.paging/git.pagers found in $lg_cfg (migrate to git.diffRenderers)"
      fi
      if grep -qE '^[[:space:]]*showIcons:' "$lg_cfg" 2>/dev/null; then
        echo "  * [DEPRECATED] gui.showIcons found in $lg_cfg (use gui.nerdFontsVersion: \"3\")"
      fi
      if grep -qE '^[[:space:]]*edit:.*\$FILE' "$lg_cfg" 2>/dev/null; then
        echo "  * [WARNING] \$FILE placeholder found in os.edit (use {{filename}} placeholder or os.editPreset: \"nvim-remote\")"
      fi

      echo "Lazygit + Neovim + Bat Companion Synergy:"
      nv_remote=$(grep -E 'nvim.*--server|editPreset:[[:space:]]*["'\'']?nvim-remote|--remote-tab|\{\{filename\}\}' "$lg_cfg" 2>/dev/null || true)
      if [[ -n "$nv_remote" ]]; then
        echo "  * Remote Tab Editing: [CONFIGURED] (Uses editPreset: nvim-remote / {{filename}} to prevent nested editor spawns)"
      else
        echo "  * Remote Tab Editing: [MISSING] (Configure os.editPreset: 'nvim-remote' or os.edit with {{filename}} to avoid nested editor spawns)"
      fi

      bat_pager=$(grep -E 'diffRenderers|bat.*--style=changes|bat.*--color=always' "$lg_cfg" 2>/dev/null || true)
      if [[ -n "$bat_pager" ]]; then
        echo "  * Diff Renderer (git.diffRenderers / bat): [CONFIGURED]"
      else
        echo "  * Diff Renderer: [DEFAULT/MISSING] (Configure git.diffRenderers with bat --color=always --style=changes,numbers)"
      fi
    fi

    inferred_thm=$(infer_theme)
    theme_desc="synchronize theme (ask user for preferred theme)"
    [[ -n "$inferred_thm" ]] && theme_desc="synchronize theme (inferred from system/terminal: $inferred_thm)"
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Set 'git.autoFetch: false' and 'gui.animateExplosion: false'; configure git.diffRenderers with bat (--color=always --style=changes,numbers)"
    echo "  * Configuration: Set 'os.editPreset: \"nvim-remote\"' (or {{filename}} placeholder — never \$FILE) and 'gui.nerdFontsVersion: \"3\"', $theme_desc"
    echo "  * Security: Respect git safe.directory settings; prevent untrusted customCommands; enforce 0600 on config.yml"
    echo "====================================="
    exit 0
    ;;
  neovim|nvim)
    echo "Category: Modal Text Editor / Neovim"
    nv_bin=$(command -v nvim 2>/dev/null || command -v neovim 2>/dev/null || echo "")
    echo "Binary: ${nv_bin:-Not installed}"
    if [[ -n "$nv_bin" ]]; then
      nv_ver=$(first_clean_line_or "unknown" "$nv_bin" --version)
      echo "Version: $nv_ver"
    fi

    echo "Discovered Configuration Files:"
    nv_init=""
    for f in "$local_app_data/nvim/init.lua" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.lua" "$local_app_data/nvim/lazy-lock.json" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazy-lock.json" "$local_app_data/nvim/lazyvim.json" "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/lazyvim.json"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$nv_init" && "$f" == *init.lua ]] && nv_init="$f"
      fi
    done

    if [[ -n "$nv_init" ]]; then
      nv_dir=$(dirname "$nv_init")
      echo "Neovim Performance & Hygiene Checks in $nv_dir:"
      if grep -q "vim.loader.enable" "$nv_init" 2>/dev/null; then
        echo "  * Bytecode Loader (vim.loader.enable): [ENABLED] (Fast startup cached)"
      else
        echo "  * Bytecode Loader: [NOT FOUND] (Add 'if vim.loader then vim.loader.enable() end' at top of init.lua)"
      fi

      if grep -rq "loaded_node_provider[[:space:]]*=[[:space:]]*0" "$nv_dir" 2>/dev/null; then
        echo "  * Legacy Remote Providers (node/python3/perl/ruby): [DISABLED] (Startup overhead eliminated)"
      else
        echo "  * Legacy Remote Providers: [ENABLED] (Set vim.g.loaded_{node,python3,perl,ruby}_provider = 0)"
      fi

      if grep -RIq --include='*.lua' --exclude-dir=.git "nvim-treesitter\.configs" "$nv_dir" 2>/dev/null; then
        echo "  * Treesitter Config Compatibility: [WARNING] ('nvim-treesitter.configs' found — removed in nvim-treesitter main branch / LazyVim v15/v16+)"
      else
        echo "  * Treesitter Config Compatibility: [CLEAN] (Compatible with nvim-treesitter main branch)"
      fi

      if has_mason_lspconfig_deprecated "$nv_dir"; then
        echo "  * Mason-lspconfig Option: [DEPRECATED] 'automatic_installation' found in mason-lspconfig spec under $nv_dir (Mason v2 / LazyVim v15/v16+ uses 'automatic_enable')"
      fi

      if grep -RIqE --include='*.lua' --exclude-dir=.git 'require[[:space:]]*\([[:space:]]*["'\'']lspconfig["'\''][[:space:]]*\)[[:space:]]*\.[A-Za-z0-9_]+[[:space:]]*[:.]setup' "$nv_dir" 2>/dev/null; then
        echo "  * Legacy lspconfig.setup: [DEPRECATED] require('lspconfig').<server>.setup found in $nv_dir (Neovim 0.11/0.12 uses native vim.lsp.config + vim.lsp.enable)"
      fi

      if [[ -f "$nv_dir/.neoconf.json" ]] && grep -q '"neodev"' "$nv_dir/.neoconf.json" 2>/dev/null; then
        echo "  * Neoconf Schema (.neoconf.json): [DEPRECATED KEY] ('neodev' found; replace with 'lazydev')"
      fi

      if grep -rqE 'modeline[[:space:]]*=[[:space:]]*false' "$nv_dir" 2>/dev/null; then
        echo "  * Modeline Hardening (modeline = false): [ENABLED] (exrc also defaults to false with SHA-256 :trust in Neovim 0.12)"
      else
        echo "  * Modeline Hardening: [DEFAULT TRUE] (Set vim.opt.modeline = false; exrc already defaults to false with :trust)"
      fi

      bak_count=$(find "$nv_dir" -name "*.bak*" 2>/dev/null | wc -l | tr -d ' ' || echo 0)
      if [[ "$bak_count" -gt 0 ]]; then
        echo "  * Leftover Backup Files in Config: [WARNING] ($bak_count *.bak* files found inside $nv_dir)"
      fi

      lsp_log="${XDG_STATE_HOME:-$HOME/.local/state}/nvim/lsp.log"
      [[ ! -f "$lsp_log" && -n "$local_app_data" ]] && lsp_log="$local_app_data/nvim-data/lsp.log"
      if [[ -f "$lsp_log" ]]; then
        lsp_log_kb=$(( $(wc -c < "$lsp_log" 2>/dev/null || echo 0) / 1024 ))
        echo "  * LSP Log Size ($lsp_log): ${lsp_log_kb} KB $(if [[ "$lsp_log_kb" -gt 1024 ]]; then echo "[LARGE — consider truncating]"; else echo "[HEALTHY]"; fi)"
      fi

      echo "Mise Companion & Toolchain Integration in Neovim:"
      mise_bin=$(command -v mise 2>/dev/null || echo "")
      if [[ -n "$mise_bin" ]]; then
        echo "  * Mise Binary Detected: $mise_bin"
        has_shims_in_path=false
        if echo "$PATH" | grep -qE "(\.local/share/mise/shims|mise/shims)" || grep -rq "mise/shims" "$nv_dir" 2>/dev/null; then
          has_shims_in_path=true
        fi
        echo "  * Mise Shims in PATH: $(if [[ "$has_shims_in_path" == "true" ]]; then echo "[ACTIVE] (LSPs and formatters discoverable via PATH)"; else echo "[CAUTION] (Prepend ~/.local/share/mise/shims to vim.env.PATH in options.lua)"; fi)"

        if [[ -d "$nv_dir/lua" ]] && (grep -rq "mise_env_sync" "$nv_dir/lua" 2>/dev/null || grep -rq '"env".*"--json"' "$nv_dir/lua" 2>/dev/null); then
          echo "  * Dynamic Project Env Sync (DirChanged -> mise env --json): [ACTIVE]"
        else
          echo "  * Dynamic Project Env Sync (DirChanged -> mise env --json): [MISSING] (Add DirChanged autocmd in autocmds.lua to sync project [env] vars)"
        fi

        mise_cfg=""
        for mf in "${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/config.toml" "$roaming_app_data/mise/config.toml" "$local_app_data/mise/config.toml"; do
          [[ -f "$mf" ]] && mise_cfg="$mf" && break
        done
        if [[ -n "$mise_cfg" ]] && grep -qE '^[[:space:]]*rust[[:space:]]*=' "$mise_cfg" 2>/dev/null; then
          if grep -E '^[[:space:]]*rust[[:space:]]*=' "$mise_cfg" 2>/dev/null | grep -q "rust-analyzer"; then
            echo "  * Mise Rust Analyzer Component: [CONFIGURED] (rust components = 'rust-analyzer' prevents rustup shim recursion)"
          else
            echo "  * Mise Rust Analyzer Component: [WARNING] (Set rust = { version = '...', components = 'rust-analyzer' } in mise/config.toml to prevent rustup <-> mise/shims infinite recursion)"
          fi
        fi

        if [[ -d "$nv_dir/lua" ]]; then
          mason_matches=$(grep -rlE 'mason(\.nvim|-lspconfig)|opts_extend[[:space:]]*=[[:space:]]*\{\}|mason[[:space:]]*=[[:space:]]*false|PATH[[:space:]]*=[[:space:]]*["'\''](append|skip)["'\'']' "$nv_dir/lua" 2>/dev/null || true)
          mason_path_opt=$(grep -rhE '^[[:space:]]*PATH[[:space:]]*=' "$nv_dir/lua" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d ' ",'\''' || true)
          has_opts_extend_lock=$(grep -rlE 'opts_extend[[:space:]]*=[[:space:]]*\{\}' "$nv_dir/lua" 2>/dev/null || true)
          has_mason_false=$(grep -rlE 'mason[[:space:]]*=[[:space:]]*false' "$nv_dir/lua" 2>/dev/null || true)
          if [[ -n "$mason_matches" ]]; then
            echo "  * Mason Lua Files Searched: $nv_dir/lua/**/*.lua"
            echo "  * Mason PATH Precedence: ${mason_path_opt:-default (prepend)} $(if [[ "$mason_path_opt" =~ append|skip ]]; then echo "[OPTIMIZED] (Mise project tools take precedence)"; else echo "(Set PATH = 'append' to avoid shadowing project-pinned tools in mise)"; fi)"
            echo "  * Mason LazyVim Extra Lock (opts_extend = {} & mason = false): $(if [[ -n "$has_opts_extend_lock" && -n "$has_mason_false" ]]; then echo "[LOCKED] (LazyVim extras prevented from re-installing Mise tools)"; else echo "[UNLOCKED] (Set opts_extend = {} on mason.nvim and mason = false on Mise LSPs)"; fi)"
          else
            echo "  * Mason.nvim: Not explicitly configured in $nv_dir/lua (Mise shims serve as primary tool source)"
          fi
        fi

        mason_pkg_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/mason/packages"
        [[ ! -d "$mason_pkg_dir" && -n "$local_app_data" ]] && mason_pkg_dir="$local_app_data/nvim-data/mason/packages"
        if [[ -d "$mason_pkg_dir" ]]; then
          mason_pkgs=$(ls -1 "$mason_pkg_dir" 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')
          mason_cnt=$(ls -1 "$mason_pkg_dir" 2>/dev/null | wc -l | tr -d ' ')
          echo "  * Installed Mason Packages ($mason_cnt): ${mason_pkgs:-none}"
        fi

        tg_cfg=""
        for tf in "$roaming_app_data/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.toml"; do
          [[ -f "$tf" ]] && tg_cfg="$tf" && break
        done
        if [[ -n "$tg_cfg" ]] && grep -qi "mason" "$tg_cfg"; then
          echo "  * Topgrade Mason Step: Detected in topgrade.toml (Coordinated via Topgrade commands)"
        fi
      else
        echo "  * Mise is not installed on this system (Install mise for polyglot runtime & LSP management)."
      fi
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Enable vim.loader.enable() for sub-65ms startup; disable legacy remote providers; discover LSPs via mise shims; rotate lsp.log >1MB"
    echo "  * Configuration: Migrate LSPs/formatters/linters from Mason to mise; lock mason.nvim (PATH='append', opts_extend={}, mason=false) or use Mason v2 automatic_enable; prefer native vim.lsp.config/vim.lsp.enable; add DirChanged 'mise env --json' sync; ensure LazyVim v15/v16+ compatibility"
    echo "  * Security: Set vim.opt.modeline = false (exrc already defaults to false with SHA-256 :trust in Neovim 0.12); pin plugin commit hashes in lazy-lock.json; enforce 0600 on private config files"
    echo "====================================="
    exit 0
    ;;
  git)
    echo "Category: Version Control / Git"
    git_bin=$(command -v git 2>/dev/null || echo "")
    echo "Binary: ${git_bin:-Not installed}"
    if [[ -n "$git_bin" ]]; then
      git_ver=$(first_clean_line_or "unknown" git --version)
      echo "Version: $git_ver"
    fi

    echo "Discovered Configuration Files:"
    for f in "$HOME/.gitconfig" "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" "/c/ProgramData/Git/config" "/etc/gitconfig"; do
      [[ -f "$f" ]] && echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
    done

    echo "Active Performance & Git Settings:"
    if is_windows; then
      echo "  * core.fscache: $(git config --get core.fscache 2>/dev/null || echo 'unset')"
    fi
    echo "  * core.preloadIndex: $(git config --get core.preloadIndex 2>/dev/null || echo 'default (true)')"
    echo "  * core.untrackedCache: $(git config --get core.untrackedCache 2>/dev/null || echo 'unset')"
    echo "  * core.fsmonitor: $(git config --get core.fsmonitor 2>/dev/null || echo 'unset')"
    echo "  * feature.manyFiles: $(git config --get feature.manyFiles 2>/dev/null || echo 'unset')"
    echo "  * core.autocrlf: $(git config --get core.autocrlf 2>/dev/null || echo 'unset')"
    echo "  * credential.helper: $(git config --get credential.helper 2>/dev/null || echo 'unset')"
    echo "  * diff.algorithm: $(git config --get diff.algorithm 2>/dev/null || echo 'unset')"
    echo "  * merge.conflictStyle: $(git config --get merge.conflictStyle 2>/dev/null || echo 'unset')"
    echo "  * branch.sort: $(git config --get branch.sort 2>/dev/null || echo 'unset')"
    echo "  * rerere.enabled: $(git config --get rerere.enabled 2>/dev/null || echo 'unset')"
    echo "  * rebase.updateRefs: $(git config --get rebase.updateRefs 2>/dev/null || echo 'unset')"
    if [[ -n "$git_bin" ]]; then
      echo "Git Findings:"
      git_check credential.helper "" "gh auth setup-git, or a credential manager"
      git_check diff.algorithm histogram "git config --global diff.algorithm histogram"
      git_check push.autoSetupRemote true "git config --global push.autoSetupRemote true"
      if git config --get-all safe.directory 2>/dev/null | grep -qx '\*'; then
        echo "  * safe.directory: [WARNING] '*' turns off the repository ownership check"
      fi
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    if is_windows; then
      echo "  * Performance: Set core.fscache = true (NTFS speedup), feature.manyFiles = true (enables index.skipHash & untrackedCache), and per-large-repo native core.fsmonitor = true"
      echo "  * Configuration: Set core.autocrlf = input, diff.algorithm = histogram, merge.conflictStyle = zdiff3, branch.sort = -committerdate, rerere.enabled = true, rebase.updateRefs = true, push.autoSetupRemote = true"
      echo "  * Security: Configure safe.directory, use Git Credential Manager (credential.helper = manager) or gh auth setup-git for OAuth tokens"
    else
      echo "  * Performance: Set feature.manyFiles = true (index.skipHash + untrackedCache), and per-large-repo native core.fsmonitor = true (watch inotify limits; avoid on network/FUSE mounts)"
      echo "  * Configuration: Set core.autocrlf = input, diff.algorithm = histogram, merge.conflictStyle = zdiff3, branch.sort = -committerdate, rerere.enabled = true, rebase.updateRefs = true, push.autoSetupRemote = true"
      echo "  * Security: Configure safe.directory, use SSH keys or gh auth setup-git / libsecret credential helper"
    fi
    echo "====================================="
    exit 0
    ;;
  bat|batcat)
    echo "Category: Syntax Pager / bat"
    bat_bin=$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || echo "")
    echo "Binary: ${bat_bin:-Not installed}"
    if [[ -n "$bat_bin" ]]; then
      bat_ver=$(first_clean_line_or "unknown" "$bat_bin" --version)
      echo "Version: $bat_ver"
    fi

    echo "Discovered Configuration Files:"
    bat_cfg_file=""
    if [[ -n "$bat_bin" ]]; then
      bat_cfg_file=$("$bat_bin" --config-file 2>/dev/null | tr -d '\r' || true)
    fi
    bat_found=0
    bat_seen=""
    for f in "${BAT_CONFIG_PATH:-}" "$bat_cfg_file" "$roaming_app_data/bat/config" "${XDG_CONFIG_HOME:-$HOME/.config}/bat/config"; do
      [[ -n "$f" && -f "$f" ]] || continue
      case "$bat_seen" in *"|$f|"*) continue ;; esac
      bat_seen="$bat_seen|$f|"
      echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      bat_found=1
    done

    echo "Bat Findings:"
    if [[ "$bat_found" -eq 1 ]]; then
      echo "  * Config file: [OK]"
    else
      echo "  * Config file: [NOT CONFIGURED] (Recommend: --theme=auto and --style in ${bat_cfg_file:-~/.config/bat/config})"
    fi
    echo "  * Shell startup files (BAT_* variables, cat/bat aliases):"
    rc_lines 'BAT_|alias cat=|alias bat=' || echo "    [NOT CONFIGURED] in the files read: $(rc_read)(files they source are not followed)"

    bat_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/bat"
    if [[ -n "$bat_bin" ]]; then
      bat_cfg_dir_cli=$("$bat_bin" --config-dir 2>/dev/null | tr -d '\r' || true)
      [[ -n "$bat_cfg_dir_cli" ]] && bat_cfg_dir="$bat_cfg_dir_cli"
    fi
    bat_has_custom=0
    if [[ -d "$bat_cfg_dir/themes" ]] && [[ -n "$(ls -A "$bat_cfg_dir/themes" 2>/dev/null || true)" ]]; then
      bat_has_custom=1
    fi
    if [[ -d "$bat_cfg_dir/syntaxes" ]] && [[ -n "$(ls -A "$bat_cfg_dir/syntaxes" 2>/dev/null || true)" ]]; then
      bat_has_custom=1
    fi

    inferred_thm=$(infer_theme)
    theme_desc="configure adaptive --theme=auto with --theme-dark/--theme-light"
    [[ -n "$inferred_thm" ]] && theme_desc="configure adaptive --theme=auto with --theme-dark/--theme-light (inferred: $inferred_thm)"
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    if [[ "$bat_has_custom" -eq 1 ]]; then
      echo "  * Performance: Use --paging=never when piping to tools; rebuild custom theme/syntax cache with 'bat cache --build'"
    else
      echo "  * Performance: Use --paging=never when piping to tools (bat cache --build is only needed when custom themes/ or syntaxes/ exist)"
    fi
    echo "  * Configuration: $theme_desc, set --style=\"numbers,changes,header\""
    echo "  * Security: Safe terminal escape rendering, avoid executing shell scripts from syntax highlighters"
    echo "====================================="
    exit 0
    ;;
  fzf)
    echo "Category: Fuzzy Finder / fzf"
    fzf_bin=$(command -v fzf 2>/dev/null || echo "")
    echo "Binary: ${fzf_bin:-Not installed}"
    if [[ -n "$fzf_bin" ]]; then
      fzf_ver=$(first_clean_line_or "unknown" "$fzf_bin" --version)
      echo "Version: $fzf_ver"
    fi

    echo "Discovered Configuration Files:"
    fzf_cmd_env=$(env_val FZF_DEFAULT_COMMAND)
    fzf_opts_env=$(env_val FZF_DEFAULT_OPTS)
    fzf_ctrl_t_env=$(env_val FZF_CTRL_T_OPTS)
    fzf_opts_file_env=$(env_val FZF_DEFAULT_OPTS_FILE)
    fzf_rc="${fzf_opts_file_env:-${XDG_CONFIG_HOME:-$HOME/.config}/fzf/fzfrc}"
    for f in "$fzf_rc" "$HOME/.fzfrc"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        if grep -qE '(^|[[:space:]])--inline-info([[:space:]]|$)' "$f" 2>/dev/null; then
          echo "  * [DEPRECATED] --inline-info found in $f (replace with --info=inline-right or --info=inline)"
        fi
      fi
    done

    echo "Environment Variables & Synergy Checkpoints:"
    echo "  * FZF_DEFAULT_COMMAND: $(env_show FZF_DEFAULT_COMMAND)"
    echo "  * FZF_DEFAULT_OPTS: $(env_show FZF_DEFAULT_OPTS)"
    echo "  * FZF_CTRL_T_OPTS: $(env_show FZF_CTRL_T_OPTS)"
    echo "  * FZF_DEFAULT_OPTS_FILE: $(env_show FZF_DEFAULT_OPTS_FILE)"
    if [[ "$fzf_opts_env" == *"--inline-info"* ]]; then
      echo "  * [DEPRECATED] --inline-info in FZF_DEFAULT_OPTS (replace with --info=inline-right)"
    fi

    echo "Shell Integration:"
    # Legacy scripts live in fzf's own tree (/usr/share/fzf/key-bindings.bash, ~/.fzf/shell/completion.zsh)
    # or are named *.fzf.*: another tool's *completion.bash (e.g. socket-completion.bash) is not fzf.
    fzf_legacy_re='fzf[^#[:space:]]*/(key-bindings|completion)\.(bash|zsh)|(key-bindings|completion)\.fzf\.(bash|zsh)|\.fzf\.(bash|zsh)'
    if rc_lines "fzf --(bash|zsh|fish)|$fzf_legacy_re" >/dev/null; then
      rc_lines "fzf --(bash|zsh|fish)|$fzf_legacy_re"
      if rc_lines "$fzf_legacy_re" >/dev/null; then
        echo "  * [NOTE] Legacy key-bindings/completion sourcing detected; fzf 0.48+ supports unified 'eval \"\$(fzf --bash)\"' / 'source <(fzf --zsh)'"
      fi
    else
      echo "  * Shell Hooks: [NOT CONFIGURED] in the files read: $(rc_read)(Recommend: eval \"\$(fzf --bash)\" / source <(fzf --zsh))"
    fi

    echo "Ripgrep + FZF + Bat Synergy Integration:"
    if [[ "$fzf_cmd_env" =~ (^|[^A-Za-z0-9_])(rg|ripgrep)([^A-Za-z0-9_]|$) ]]; then
      echo "  * Search Generator (ripgrep): [CONFIGURED] (rg wired as FZF_DEFAULT_COMMAND backend)"
    elif [[ "$fzf_cmd_env" =~ (^|[^A-Za-z0-9_])(fd|fdfind)([^A-Za-z0-9_]|$) ]]; then
      echo "  * Search Generator (fd): [CONFIGURED] (fd directory walker)"
    else
      echo "  * Search Generator: [DEFAULT] (Built-in --walker is multithreaded in fzf 0.75+; wire 'fd --type f --strip-cwd-prefix --hidden --exclude .git' or 'rg --files' for .gitignore awareness)"
    fi

    fzf_bat_src=""
    if [[ "$fzf_opts_env" =~ (^|[^A-Za-z0-9_])(bat|batcat)[[:space:]] ]]; then
      fzf_bat_src="FZF_DEFAULT_OPTS"
    elif [[ "$fzf_ctrl_t_env" =~ (^|[^A-Za-z0-9_])(bat|batcat)[[:space:]] ]]; then
      fzf_bat_src="FZF_CTRL_T_OPTS (scoped to file search; keeps CTRL-R and piped input preview-free)"
    elif [[ -f "$fzf_rc" ]] && grep -qE -- '--preview.*(^|[^A-Za-z0-9_])(bat|batcat)[[:space:]]' "$fzf_rc" 2>/dev/null; then
      fzf_bat_src="$fzf_rc"
    fi
    if [[ -n "$fzf_bat_src" ]]; then
      echo "  * Syntax Previewer (bat): [CONFIGURED] (bat previews via $fzf_bat_src)"
    else
      echo "  * Syntax Previewer (bat): [RECOMMENDED] (Configure --preview 'bat --style=numbers --color=always --line-range :500 {}')"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Built-in --walker is already multithreaded (0.75+); use 'fd --type f --strip-cwd-prefix --hidden --exclude .git' or rg for .gitignore filtering; bound preview (--line-range :500)"
    echo "  * Configuration: Enable shell integration (fzf --bash/--zsh/--fish); store defaults in FZF_DEFAULT_OPTS_FILE (~/.config/fzf/fzfrc) with --info=inline-right (never deprecated --inline-info), layout=reverse, bat preview"
    echo "  * Security: Exclude credentials, .env files, and .git internals from default search index"
    echo "====================================="
    exit 0
    ;;
  starship)
    echo "Category: Shell Prompt / Starship Cross-Shell Prompt"
    ss_bin=$(command -v starship 2>/dev/null || echo "")
    echo "Binary: ${ss_bin:-Not installed}"
    if [[ -n "$ss_bin" ]]; then
      ss_ver=$(first_clean_line_or "unknown" "$ss_bin" --version)
      echo "Version: $ss_ver"
    fi

    echo "Discovered Configuration Files:"
    ss_cfg=""
    for f in "${STARSHIP_CONFIG:-}" "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml" "$roaming_app_data/starship.toml"; do
      if [[ -n "$f" && -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$ss_cfg" ]] && ss_cfg="$f"
      fi
    done

    if [[ -n "$ss_cfg" ]]; then
      echo "Active Starship Configuration ($ss_cfg):"
      c_to=$(toml_section_val "$ss_cfg" "" "command_timeout")
      echo "  * Configured Timeout: ${c_to:-default (500ms)}"

      echo "Mise Companion & Zero-Latency Prompt Integration:"
      has_mise_mod=$(grep -E '^[[:space:]]*\[mise\]' "$ss_cfg" 2>/dev/null || true)
      mise_mod_dis=$(toml_section_val "$ss_cfg" "mise" "disabled")
      if [[ -n "$has_mise_mod" && "$mise_mod_dis" == "false" ]]; then
        echo "  * Native [mise] Prompt Module: [ENABLED] (disabled = false)"
      elif [[ -n "$has_mise_mod" && -z "$mise_mod_dis" ]]; then
        echo "  * Native [mise] Prompt Module: [DISABLED] (default (true — disabled unless set false))"
      else
        echo "  * Native [mise] Prompt Module: [DISABLED / UNCONFIGURED] (Add [mise] with disabled = false in starship.toml)"
      fi

      mise_mod_fmt=$(toml_section_val "$ss_cfg" "mise" "format")
      if [[ "$mise_mod_fmt" == *'$version'* ]]; then
        echo "  * [WARNING] [mise] format references '\$version' which does not exist in starship [mise] module (valid variables: \$symbol, \$health)"
      fi

      lang_mods_status=()
      for l_mod in nodejs python rust golang ruby dotnet bun package; do
        lm_dis=$(toml_section_val "$ss_cfg" "$l_mod" "disabled")
        if [[ "$lm_dis" == "true" ]]; then
          lang_mods_status+=("$l_mod:disabled")
        elif grep -q "^[[:space:]]*\[$l_mod\]" "$ss_cfg" 2>/dev/null; then
          lang_mods_status+=("$l_mod:ACTIVE")
        fi
      done
      if [[ ${#lang_mods_status[@]} -gt 0 ]]; then
        echo "  * Language Modules Status: ${lang_mods_status[*]}"
      else
        echo "  * Language Modules Status: Using starship defaults (Per-language modules active by default)"
      fi
      if [[ -n "$has_mise_mod" && "$mise_mod_dis" == "false" ]]; then
        fmt_langs=$(grep -E '^[[:space:]]*format[[:space:]]*=' "$ss_cfg" 2>/dev/null | grep -oE '\$(nodejs|python|rust|golang|ruby|dotnet|bun|package)' | tr '\n' ' ' || true)
        if [[ -n "$fmt_langs" ]]; then
          echo "  * [WARNING] Redundant Language Tokens in 'format': ${fmt_langs}(Remove from format when [mise] is enabled)"
        fi
      fi
    fi

    echo "Shell Integration:"
    if rc_lines 'starship init' >/dev/null; then
      echo "  * Starship Init Hooks:"
      rc_lines 'starship init'
    else
      echo "  * Starship Init Hooks: [NOT CONFIGURED] in the files read: $(rc_read)"
    fi
    if rc_lines 'mise activate' >/dev/null; then
      echo "  * Mise Activate Hooks:"
      rc_lines 'mise activate'
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Set command_timeout = 500 (integer ms); enable [mise] (disabled = false) and disable redundant language modules ([nodejs], [python], [rust]); if caching static init, use 'starship init <shell> --print-full-init'"
    echo "  * Configuration: Clean minimal prompt layout, directory truncation length 3, consistent Nerd Font symbols (note [mise] format supports \$symbol/\$health, not \$version)"
    echo "  * Security: Avoid untrusted custom command execution in prompt modules ([custom.*]); restrict starship.toml permissions to 0600"
    echo "====================================="
    exit 0
    ;;
  yt-dlp)
    echo "Category: Media Downloader / yt-dlp"
    ytdl_bin=$(command -v yt-dlp 2>/dev/null || echo "")
    echo "Binary: ${ytdl_bin:-Not installed}"
    if [[ -n "$ytdl_bin" ]]; then
      ytdl_ver=$(first_clean_line_or "unknown" "$ytdl_bin" --version)
      echo "Version: $ytdl_ver"
    fi

    echo "Discovered Configuration Files:"
    ytdl_cfg=0
    for f in "$roaming_app_data/yt-dlp/config" "${XDG_CONFIG_HOME:-$HOME/.config}/yt-dlp/config" "$HOME/.config/yt-dlp.conf"; do
      [[ -f "$f" ]] || continue
      echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
      ytdl_cfg=1
      if grep -qE '^[[:space:]]*--no-check-certificates?' "$f" 2>/dev/null; then
        echo "  * [SECURITY WARNING] --no-check-certificate in $f turns off TLS verification"
      fi
      if grep -qE '^[[:space:]]*--cookies' "$f" 2>/dev/null; then
        echo "  * [WARNING] $f references a cookies file (keep that file at 0600)"
      fi
      if grep -qE '^[[:space:]]*--(external-)?downloader[[:space:]=]+.*aria2c' "$f" 2>/dev/null; then
        echo "  * [WARNING] Global aria2c downloader in $f causes YouTube HTTP 403/SABR throttling (prefer native -N 4 / --concurrent-fragments 4)"
      fi
      if grep -qE '^[[:space:]]*--impersonate([[:space:]=]|$)' "$f" 2>/dev/null; then
        echo "  * [WARNING] Global --impersonate in $f degrades download speed/stability (use --impersonate per-command only)"
      fi
    done
    [[ "$ytdl_cfg" -eq 1 ]] || echo "  * Config file: [NOT CONFIGURED] (Recommend: ~/.config/yt-dlp/config)"

    echo "YouTube EJS & JS Runtime Dependencies:"
    js_rt_found=()
    for jrt in deno node bun qjs; do
      command -v "$jrt" >/dev/null 2>&1 && js_rt_found+=("$jrt")
    done
    echo "  * JS Runtimes on PATH: ${js_rt_found[*]:-none detected}"
    ejs_status="not detected"
    if command -v pacman >/dev/null 2>&1 && pacman -Q yt-dlp-ejs >/dev/null 2>&1; then
      ejs_status="installed ($(pacman -Q yt-dlp-ejs 2>/dev/null))"
    elif python3 -c 'import yt_dlp_ejs' >/dev/null 2>&1 || /usr/bin/python3 -c 'import yt_dlp_ejs' >/dev/null 2>&1; then
      ejs_status="installed (Python yt_dlp_ejs)"
    fi
    echo "  * yt-dlp-ejs Solver: $ejs_status"
    if ! command -v deno >/dev/null 2>&1; then
      if command -v node >/dev/null 2>&1; then
        echo "  * [NOTE] deno not found; pass '--js-runtimes node' in config if using Node.js for EJS challenges"
      elif command -v bun >/dev/null 2>&1; then
        echo "  * [NOTE] deno not found; pass '--js-runtimes bun' in config if using Bun for EJS challenges"
      fi
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Use native -N 4 (--concurrent-fragments=4) with ffmpeg (never global aria2c or global --impersonate)"
    echo "  * Configuration: Default format bestvideo+bestaudio/best, clean output template, ensure yt-dlp-ejs + deno (or --js-runtimes node/bun) for YouTube"
    echo "  * Security: Restrict untrusted cookies (0600), sanitize output filenames, never pass --no-check-certificates"
    echo "====================================="
    exit 0
    ;;
  herdr)
    echo "Category: Terminal Workspace & AI Agent Multiplexer / Herdr"
    hdr_bin=$(command -v herdr 2>/dev/null || echo "")
    echo "Binary: ${hdr_bin:-Not installed}"
    if [[ -n "$hdr_bin" ]]; then
      hdr_ver=$(first_clean_line_or "unknown" "$hdr_bin" --version)
      echo "Version: $hdr_ver"
    fi

    echo "Server & Client Runtime Status:"
    if [[ -n "$hdr_bin" ]]; then
      "$hdr_bin" status 2>/dev/null | while IFS= read -r line; do
        echo "  $line"
      done || echo "  (Herdr status unavailable)"
      echo "Agent Integration Hooks (herdr integration status):"
      hdr_int=$("$hdr_bin" integration status 2>/dev/null | strip_ansi || true)
      if [[ -n "$hdr_int" ]]; then
        while IFS= read -r iline; do
          [[ -n "$iline" ]] && echo "  $iline"
        done <<< "$hdr_int"
        for ag in pi claude codex antigravity-cli; do
          ag_cmd="$ag"
          [[ "$ag" == "antigravity-cli" ]] && ag_cmd="agy"
          if command -v "$ag_cmd" >/dev/null 2>&1; then
            ag_line=$(printf '%s\n' "$hdr_int" | grep -iE "(^|[[:space:]])${ag}([[:space:]:]|$)" | head -n 1 || true)
            if [[ -n "$ag_line" ]] && echo "$ag_line" | grep -qiE 'not installed|missing|outdated|stale'; then
              echo "  * [NOTE] $ag_cmd is installed on PATH but its Herdr hook reports: $ag_line"
            fi
          fi
        done
      else
        echo "  (herdr integration status unavailable)"
      fi
    fi

    echo "Discovered Configuration Files:"
    hdr_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
    hdr_cfg=""
    for f in "${HERDR_CONFIG_PATH:-}" "$roaming_app_data/herdr/config.toml" "$hdr_cfg_dir/config.toml"; do
      if [[ -n "$f" && -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$hdr_cfg" ]] && hdr_cfg="$f"
      fi
    done
    for bdir in "$hdr_cfg_dir" "$roaming_app_data/herdr"; do
      [[ -d "$bdir" ]] || continue
      for bf in "$bdir"/config.toml.bak.*; do
        [[ -f "$bf" ]] || continue
        echo "  * [WARNING] Stray backup config $bf$(cfg_perm_tag "$bf") (clean up or restrict permissions to 0600)"
      done
    done

    if [[ -n "$hdr_cfg" ]]; then
      echo "Active Configuration Parameters ($hdr_cfg):"
      def_shell=$(toml_section_val "$hdr_cfg" "terminal" "default_shell")
      shell_mode=$(toml_section_val "$hdr_cfg" "terminal" "shell_mode")
      theme_name=$(toml_section_val "$hdr_cfg" "theme" "name")
      theme_auto=$(toml_section_val "$hdr_cfg" "theme" "auto_switch")
      theme_dark=$(toml_section_val "$hdr_cfg" "theme" "dark_name")
      theme_light=$(toml_section_val "$hdr_cfg" "theme" "light_name")
      toast_deliv=$(toml_section_val "$hdr_cfg" "ui.toast" "delivery")
      resume_agents=$(toml_section_val "$hdr_cfg" "session" "resume_agents_on_restore")
      scrollback_bytes=$(toml_section_val "$hdr_cfg" "advanced" "scrollback_limit_bytes")
      if is_windows; then
        echo "  * Default Shell: ${def_shell:-system default}"
      else
        echo "  * Default Shell: ${def_shell:-empty (honors \$SHELL)}"
      fi
      echo "  * Shell Mode: ${shell_mode:-default}"
      echo "  * Theme: ${theme_name:-default} (auto_switch=${theme_auto:-false}${theme_dark:+, dark=$theme_dark}${theme_light:+, light=$theme_light})"
      echo "  * Notification Delivery ([ui.toast]): ${toast_deliv:-off}"
      echo "  * Session Resume Agents: ${resume_agents:-default}"
      echo "  * Scrollback Limit Bytes: ${scrollback_bytes:-default}"
    fi

    echo "Runtime State, Sockets & Session Artifacts:"
    hdr_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/herdr"
    for sf in \
      "$hdr_cfg_dir/session.json" \
      "$hdr_cfg_dir/session-snapshots" \
      "$hdr_cfg_dir/herdr.sock" \
      "$hdr_cfg_dir/herdr-client.sock" \
      "$hdr_cfg_dir/herdr.log" \
      "$hdr_cfg_dir/herdr-server.log" \
      "$hdr_cfg_dir/herdr-client.log" \
      "$hdr_state_dir" \
      "$HOME/.herdr/worktrees" \
      "$roaming_app_data/herdr/session.json" \
      "$roaming_app_data/herdr/herdr.sock" \
      "$roaming_app_data/herdr/herdr-server.log"; do
      if [[ -e "$sf" || -S "$sf" ]]; then
        sz=$(du -sh "$sf" 2>/dev/null | awk '{print $1}' || echo "present")
        echo "  - [EXISTS] $(basename "$sf"): $sz ($sf)$(cfg_perm_tag "$sf")"
        if [[ -S "$sf" ]] && ! is_windows; then
          smode=$(stat -c "%a" "$sf" 2>/dev/null || echo "")
          if [[ -n "$smode" && "$smode" != "600" ]]; then
            echo "  * [SECURITY WARNING] Socket $sf has mode $smode (recommend 0600)"
          fi
        fi
      fi
    done

    inferred_thm=$(infer_theme)
    theme_desc="synchronize theme (or prompt user)"
    [[ -n "$inferred_thm" ]] && theme_desc="synchronize theme (inferred: $inferred_thm)"
    echo "Mise Companion Workspace Toolchains:"
    mise_bin=$(command -v mise 2>/dev/null || echo "")
    if [[ -n "$mise_bin" ]]; then
      echo "  * Mise Binary Detected: $mise_bin"
      mise_shims="${MISE_DATA_DIR:-$HOME/.local/share/mise}/shims"
      if is_windows; then
        mise_shims="$(win_path_unix "${MISE_DATA_DIR:-$local_app_data/mise}")/shims"
      fi
      if [[ -d "$mise_shims" ]]; then
        echo "  * Mise Shims for Agent Workspaces: [ACTIVE] ($mise_shims)"
      fi
    else
      echo "  * Mise not detected on this system."
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Monitor/rotate herdr*.log; bound [advanced] scrollback_limit_bytes; prune orphaned sessions/worktrees; use 'herdr update --handoff' for zero-downtime restarts"
    if is_windows; then
      echo "  * Configuration: Set default_shell to pwsh; configure [terminal] shell_mode, [session] resume_agents_on_restore, $theme_desc (auto_switch/dark_name/light_name), [ui.toast] delivery; validate via 'herdr config check' + 'herdr server reload-config'"
    else
      echo "  * Configuration: Leave default_shell = \"\" on Unix (honors \$SHELL); configure [terminal] shell_mode, [session] resume_agents_on_restore, $theme_desc (auto_switch/dark_name/light_name), [ui.toast] delivery; validate via 'herdr config check' + 'herdr server reload-config'"
    fi
    echo "  * Security: Restrict herdr.sock, herdr-client.sock, and config.toml to 0600 (clean up stray config.toml.bak.*); keep workspace directories at 0700"
    echo "====================================="
    exit 0
    ;;
  gh|github-cli)
    echo "Category: Developer Tool / GitHub CLI (gh)"
    gh_bin=$(command -v gh 2>/dev/null || echo "")
    echo "Binary: ${gh_bin:-Not installed}"
    if [[ -n "$gh_bin" ]]; then
      gh_ver=$(first_clean_line_or "unknown" "$gh_bin" --version)
      echo "Version: $gh_ver"
    fi

    echo "Authentication & Account Status:"
    if command -v gh >/dev/null 2>&1; then
      gh auth status 2>&1 | while read -r line; do
        echo "  $line"
      done || echo "  (Authentication status check returned non-zero)"
    fi

    echo "Discovered Configuration Files:"
    gh_cfg=""
    gh_hosts=""
    for f in "$roaming_app_data/GitHub CLI/config.yml" "${XDG_CONFIG_HOME:-$HOME/.config}/gh/config.yml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$gh_cfg" ]] && gh_cfg="$f"
      fi
    done
    for f in "$roaming_app_data/GitHub CLI/hosts.yml" "${XDG_CONFIG_HOME:-$HOME/.config}/gh/hosts.yml"; do
      if [[ -f "$f" ]]; then
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        [[ -z "$gh_hosts" ]] && gh_hosts="$f"
        if grep -qE '^[[:space:]]*oauth_token:' "$f" 2>/dev/null; then
          echo "  * [SECURITY WARNING] $f stores plaintext oauth_token: (prefer OS keyring or expiring tokens)"
        fi
      fi
    done

    echo "Active Configuration Parameters:"
    if command -v gh >/dev/null 2>&1; then
      for key in git_protocol editor pager prompt browser telemetry expiring_credentials color_labels; do
        val=$(gh config get "$key" 2>/dev/null || echo "not set")
        echo "  * $key: $val"
        if [[ "$key" == "telemetry" && "$val" == "enabled" ]]; then
          echo "  * [NOTE] gh telemetry is enabled (disable with: gh config set telemetry disabled)"
        fi
      done
    elif [[ -n "$gh_cfg" ]]; then
      echo "  * Config File Found: $gh_cfg"
    fi

    echo "Installed GitHub CLI Extensions:"
    if command -v gh >/dev/null 2>&1; then
      ext_count=$(gh extension list 2>/dev/null | wc -l | tr -d ' ' || true)
      if [[ "$ext_count" -gt 0 ]]; then
        echo "  * Total Extensions: $ext_count"
        gh extension list 2>/dev/null | while read -r eline; do
          echo "    - $eline"
        done
      else
        echo "  * No extensions installed."
      fi
    fi

    echo "Workstation & Cross-Tool Synergies:"
    if command -v git >/dev/null 2>&1; then
      git_creds=$(git config --get-regexp '^credential\..*helper' 2>/dev/null || true)
      gh_proto=$(gh config get git_protocol 2>/dev/null || echo "")
      if echo "$git_creds" | grep -qi "gh auth git-credential"; then
        echo "  * Git Credential Helper: [CONFIGURED] (Transparent GitHub authentication via gh auth git-credential)"
      elif echo "$git_creds" | grep -qiE "manager|osxkeychain|libsecret"; then
        echo "  * Git Credential Helper: [CONFIGURED] (System Git Credential Manager active; 'gh auth setup-git' optional)"
      elif [[ "$gh_proto" == "ssh" ]]; then
        echo "  * Git Credential Helper: [OK] (git_protocol: ssh uses SSH keys; 'gh auth setup-git' only needed for HTTPS remotes)"
      else
        echo "  * Git Credential Helper: [NOT CONFIGURED] (Run 'gh auth setup-git' to eliminate token/password prompts for HTTPS remotes)"
      fi
    fi
    gh_pager=$(gh config get pager 2>/dev/null || echo "")
    if [[ "$gh_pager" =~ bat ]]; then
      echo "  * Syntax Pager: [CONFIGURED] ($gh_pager)"
    else
      echo "  * Syntax Pager: Default less (Recommend 'gh config set pager \"bat --color=always --style=plain\"')"
    fi
    topgrade_cfg=""
    for tf in "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.toml" "$roaming_app_data/topgrade.toml"; do
      [[ -f "$tf" ]] && topgrade_cfg="$tf" && break
    done
    if [[ -n "$topgrade_cfg" ]]; then
      echo "  * Topgrade Maintenance: Configured ($topgrade_cfg)"
    fi

    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Configure 'pager: bat --color=always --style=plain' in config.yml for zero-latency diff reviews; leverage gh --json queries in scripts"
    echo "  * Configuration: Set 'git_protocol: ssh' (run 'gh auth setup-git' if using HTTPS remotes); set 'color_labels: enabled' and 'telemetry: disabled'; configure PR workflow aliases"
    echo "  * Security: Avoid plaintext oauth_token in hosts.yml (prefer OS keyring + expiring_credentials: enabled); restrict hosts.yml to 0600 on Linux/WSL (NTFS ACLs on Windows); audit third-party extensions"
    echo "====================================="
    exit 0
    ;;
  network|net)
    echo "Category: System Core / Network"
    if is_windows; then
      echo "Active Adapters:"
      run_ps 'Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | ForEach-Object { "  * $($_.Name): $($_.InterfaceDescription), $($_.LinkSpeed)" }' 2>/dev/null || echo "  (unknown)"
      echo "DNS Servers (IPv4):"
      run_ps 'Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | ForEach-Object { "  * $($_.InterfaceAlias): $($_.ServerAddresses -join ",")" }' 2>/dev/null || echo "  (unknown)"
      at_lvl=$(run_ps '"$((Get-NetTCPSetting -SettingName Internet).AutoTuningLevelLocal)".ToLower()' 2>/dev/null || echo unknown)
      case "$at_lvl" in
        normal|experimental) echo "TCP Receive Window Auto-Tuning: $at_lvl [OK]" ;;
        disabled|highlyrestricted|restricted) echo "TCP Receive Window Auto-Tuning: $at_lvl [WARNING] (Recommended: Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal Normal)" ;;
        *) echo "TCP Receive Window Auto-Tuning: ${at_lvl:-unknown}" ;;
      esac
      echo "Listening TCP Sockets: $(netstat -ano -p tcp 2>/dev/null | grep -ci LISTENING || true)"
    else
      echo "Default Route: $(ip route show default 2>/dev/null | head -n 1 || true)"
      echo "DNS Resolvers: $(grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ' || true)"
      tcp_cc=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)
      case "$tcp_cc" in
        bbr|bbr2|bbr3|cubic) echo "TCP Congestion Control: $tcp_cc [OK]" ;;
        unknown) echo "TCP Congestion Control: unknown [NOT READABLE]" ;;
        *) echo "TCP Congestion Control: $tcp_cc [WARNING] (Recommended: bbr or cubic)" ;;
      esac
      qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo unknown)
      case "$qdisc" in
        fq|fq_codel|cake|fq_pie) echo "Default Queue Discipline: $qdisc [OK]" ;;
        unknown) echo "Default Queue Discipline: unknown [NOT READABLE]" ;;
        *) echo "Default Queue Discipline: $qdisc [WARNING] (Recommended: fq_codel, or fq with bbr)" ;;
      esac
      echo "Listening TCP Sockets: $(ss -tlnH 2>/dev/null | wc -l || true)"
      wild_listen=$(ss -tlnH 2>/dev/null | awk '{print $4}' | grep -E '^(0\.0\.0\.0|\*|\[::\]):' | sort -u | tr '\n' ' ' || true)
      if [[ -n "$wild_listen" ]]; then
        echo "  * Listening on all interfaces: [NOTE] ${wild_listen% } (confirm each is intended and firewalled)"
      else
        echo "  * Listening on all interfaces: [OK] none (loopback/specific addresses only)"
      fi
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: TCP auto-tuning left at normal; BBR or CUBIC congestion control; no leftover VPN adapters"
    echo "  * Configuration: Encrypted DNS (DoH/DoT) with a local cache; static addressing only where needed"
    echo "  * Security: Close listening sockets that nothing uses; firewall limited to the local network"
    echo "====================================="
    exit 0
    ;;
  falkon)
    echo "Category: Web Browser / Falkon (QtWebEngine)"
    fk_bin=$(command -v falkon 2>/dev/null || echo "")
    echo "Binary: ${fk_bin:-Not installed}"
    [[ -n "$fk_bin" ]] && echo "Version: $(first_clean_line_or unknown "$fk_bin" --version)"
    fk_root=""
    for d in "${XDG_CONFIG_HOME:-$HOME/.config}/falkon" "$local_app_data/falkon"; do
      [[ -d "$d/profiles" ]] && { fk_root="$d"; break; }
    done
    if [[ -z "$fk_root" ]]; then
      echo "Profiles: none yet (Falkon creates ~/.config/falkon/profiles on first start)"
    else
      fk_prof=$(ini_val "$fk_root/profiles/profiles.ini" Profiles startProfile | tr -d '"')
      fk_prof="${fk_prof:-default}"
      fk_set="$fk_root/profiles/$fk_prof/settings.ini"
      echo "Profiles Directory: $fk_root/profiles (start profile: $fk_prof)$(is_windows || printf ' (dir mode: %s)' "$(stat -c '%a' "$fk_root" 2>/dev/null || echo unknown)")"
      if [[ -f "$fk_set" ]]; then
        echo "  - [EXISTS] $fk_set$(cfg_perm_tag "$fk_set")"
        echo "Falkon Findings:"
        fk_adb=$(ini_val "$fk_set" AdBlock enabled)
        if [[ "${fk_adb:-true}" == true ]]; then
          fk_adb_src="settings.ini"; [[ -z "$fk_adb" ]] && fk_adb_src="default"
          echo "  * AdBlock: [OK] enabled ($fk_adb_src; fewer scripts and requests on low-RAM hosts)"
        else
          echo "  * AdBlock: [WARNING] disabled (enable [AdBlock] enabled=true: blocks trackers and heavy ad scripts)"
        fi
        fk_tpc=$(ini_val "$fk_set" Cookie-Settings filterThirdPartyCookies)
        if [[ "$fk_tpc" == true ]]; then
          echo "  * Third-party Cookies: [OK] filtered"
        else
          echo "  * Third-party Cookies: [NOTE] not filtered (Preferences > Privacy > Cookies: filter third-party cookies)"
        fi
        fk_dnt=$(ini_val "$fk_set" Web-Browser-Settings DoNotTrack)
        echo "  * DoNotTrack: ${fk_dnt:-default (false)}"
        fk_dns=$(ini_val "$fk_set" Web-Browser-Settings DNSPrefetch)
        echo "  * DNS Prefetch: ${fk_dns:-default (true)}"
        for f in "$fk_root/profiles/$fk_prof/session.dat" "$fk_root/profiles/$fk_prof/browsedata.db"; do
          [[ -f "$f" ]] && echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        done
      else
        echo "  * settings.ini: [NOT CONFIGURED] ($fk_set does not exist yet)"
      fi
    fi
    echo "  * QTWEBENGINE_CHROMIUM_FLAGS: $(env_show QTWEBENGINE_CHROMIUM_FLAGS)"
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Keep AdBlock on; GPU rasterization via QTWEBENGINE_CHROMIUM_FLAGS='--enable-gpu-rasterization' (verify in falkon:config / chrome://gpu)"
    echo "  * Configuration: One profile per context; trim speed-dial thumbnails and session restore on low RAM"
    echo "  * Security: Filter third-party cookies, keep QtWebEngine updated with the distro (security fixes ship with Qt), 0700 profile directory"
    echo "====================================="
    exit 0
    ;;
  dolphin|kate|konsole)
    kde_cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
    kde_data="${XDG_DATA_HOME:-$HOME/.local/share}"
    kde_bin=$(command -v "$target" 2>/dev/null || echo "")
    case "$target" in
      dolphin) echo "Category: File Manager / KDE Dolphin" ;;
      kate) echo "Category: Text Editor / KDE Kate" ;;
      konsole) echo "Category: Terminal Emulator / KDE Konsole" ;;
    esac
    echo "Binary: ${kde_bin:-Not installed}"
    [[ -n "$kde_bin" ]] && echo "Version: $(first_clean_line_or unknown "$kde_bin" --version)"
    kde_rc="$kde_cfg/${target}rc"
    echo "Configuration File:"
    if [[ -f "$kde_rc" ]]; then
      echo "  - [EXISTS] $kde_rc$(cfg_perm_tag "$kde_rc")"
    else
      echo "  - $kde_rc does not exist yet (written when a setting is changed from defaults)"
    fi
    echo "${target^} Findings:"
    case "$target" in
      dolphin)
        bl_idx=$(ini_val "$kde_cfg/baloofilerc" "Basic Settings" Indexing-Enabled)
        if [[ "$bl_idx" == false ]]; then
          echo "  * Baloo Indexing: [OK] disabled (no background crawl; Dolphin search falls back to a live scan)"
        else
          echo "  * Baloo Indexing: [NOTE] ${bl_idx:-enabled (default)} (disk and RAM cost on low-end hosts: balooctl6 disable, or restrict folders)"
        fi
        rm_size=$(ini_val "$kde_cfg/kdeglobals" PreviewSettings MaximumRemoteSize)
        if [[ -z "$rm_size" || "$rm_size" == 0 ]]; then
          echo "  * Remote Previews: [OK] off (${rm_size:-default}; no thumbnail downloads over sftp/smb)"
        else
          echo "  * Remote Previews: [NOTE] up to $rm_size bytes per remote file (slow on network folders; set 0 in kdeglobals [PreviewSettings])"
        fi
        dl_tabs=$(ini_val "$kde_rc" General RememberOpenedTabs)
        echo "  * Restore Tabs on Start: ${dl_tabs:-default (true)}"
        sm_list=()
        for sm_dir in "$kde_data/kio/servicemenus" "$kde_data/kservices5/ServiceMenus"; do
          [[ -d "$sm_dir" ]] || continue
          for sm in "$sm_dir"/*.desktop; do
            [[ -f "$sm" ]] && sm_list+=("$sm")
          done
        done
        if [[ ${#sm_list[@]} -gt 0 ]]; then
          echo "  * User Service Menus: [NOTE] ${#sm_list[@]} installed (each runs its Exec= command from the context menu; audit third-party ones):"
          for sm in "${sm_list[@]}"; do
            echo "    - $sm$(cfg_perm_tag "$sm")"
          done
        else
          echo "  * User Service Menus: [OK] none installed"
        fi
        ;;
      kate)
        km_save=$(ini_val "$kde_rc" General "Save Meta Infos")
        km_days=$(ini_val "$kde_rc" General "Days Meta Infos")
        if [[ "$km_save" == false ]]; then
          echo "  * Document Meta History: [OK] not saved"
        elif [[ "${km_days:-30}" =~ ^[0-9]+$ && "${km_days:-30}" -le 90 ]]; then
          echo "  * Document Meta History: [OK] kept ${km_days:-30 (default)} day(s)"
        else
          echo "  * Document Meta History: [NOTE] kept $km_days day(s) (lists every opened file; 30 is the default)"
        fi
        km_swap=$(ini_val "$kde_rc" "KTextEditor Document" "Swap File Mode")
        case "${km_swap:-1}" in
          0) echo "  * Swap Files: [NOTE] disabled (no crash recovery for unsaved edits)" ;;
          2) echo "  * Swap Files: [OK] custom directory ($(ini_val "$kde_rc" "KTextEditor Document" "Swap Directory"))" ;;
          *) echo "  * Swap Files: [OK] enabled (mode ${km_swap:-1, default}; .swp next to each file; mode 2 keeps them out of project trees)" ;;
        esac
        km_lsp="$kde_cfg/kate/lspclient/settings.json"
        if [[ -f "$km_lsp" ]]; then
          echo "  - [EXISTS] $km_lsp$(cfg_perm_tag "$km_lsp") (LSP server overrides)"
        else
          echo "  * LSP Overrides: none (built-in defaults; servers come from PATH, e.g. mise shims)"
        fi
        km_sess="$kde_data/kate/sessions"
        [[ -d "$km_sess" ]] && echo "  * Sessions: $(find "$km_sess" -maxdepth 1 -name '*.katesession' 2>/dev/null | wc -l | tr -d ' ') saved in $km_sess"
        ;;
      konsole)
        ks_prof_name=$(ini_val "$kde_rc" "Desktop Entry" DefaultProfile)
        ks_prof=""
        [[ -n "$ks_prof_name" && -f "$kde_data/konsole/$ks_prof_name" ]] && ks_prof="$kde_data/konsole/$ks_prof_name"
        if [[ -z "$ks_prof" ]]; then
          echo "  * Default Profile: built-in (fixed 1000-line scrollback) [OK]"
        else
          echo "  - [EXISTS] $ks_prof$(cfg_perm_tag "$ks_prof") (default profile)"
          ks_hm=$(ini_val "$ks_prof" Scrolling HistoryMode)
          ks_hs=$(ini_val "$ks_prof" Scrolling HistorySize)
          case "${ks_hm:-1}" in
            2) echo "  * Scrollback: [WARNING] unlimited (grows without bound in temp files; set a fixed HistorySize such as 10000)" ;;
            0) echo "  * Scrollback: [NOTE] disabled" ;;
            *) echo "  * Scrollback: [OK] fixed ${ks_hs:-1000} lines" ;;
          esac
        fi
        ;;
    esac
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    case "$target" in
      dolphin)
        echo "  * Performance: Disable or scope Baloo on low RAM; no remote previews; static icon sizes"
        echo "  * Configuration: Keep dolphinrc minimal (KConfig stores only non-defaults); per-folder view props via .directory"
        echo "  * Security: Audit user service menus (they run commands); keep ~/.config files 0600" ;;
      kate)
        echo "  * Performance: Bound meta history (Days Meta Infos), disable unused plugins, keep large-file limits on"
        echo "  * Configuration: LSP servers from PATH (mise shims) with lspclient/settings.json overrides; swap mode 2 keeps .swp out of git trees"
        echo "  * Security: Do not trust .kateproject build commands from unknown repositories" ;;
      konsole)
        echo "  * Performance: Fixed scrollback (5000-10000 lines), GPU-light fonts, no blur behind on iGPU"
        echo "  * Configuration: One default profile; shell integration via starship/zoxide in ~/.bashrc"
        echo "  * Security: Disable 'allow running commands from links' for untrusted output; review SSH manager entries" ;;
    esac
    echo "====================================="
    exit 0
    ;;
  ffmpeg|ffprobe)
    echo "Category: Media Toolkit / FFmpeg"
    ff_bin=$(command -v ffmpeg 2>/dev/null || echo "")
    echo "Binary: ${ff_bin:-Not installed}"
    if [[ -n "$ff_bin" ]]; then
      echo "Version: $(first_clean_line_or unknown "$ff_bin" -hide_banner -version)"
      ff_hw=$("$ff_bin" -hide_banner -hwaccels 2>/dev/null </dev/null | tail -n +2 | tr -s '[:space:]' ' ' || true)
      ff_hw="${ff_hw# }"; ff_hw="${ff_hw% }"
      echo "Hardware Acceleration Methods: ${ff_hw:-none}"
    fi
    echo "FFmpeg Findings:"
    if is_windows; then
      if [[ " ${ff_hw:-} " =~ \ (d3d11va|d3d12va|dxva2|cuda|qsv)\  ]]; then
        echo "  * Hardware Decode: [OK] ${BASH_REMATCH[1]} available (use -hwaccel auto or d3d11va)"
      elif [[ -n "$ff_bin" ]]; then
        echo "  * Hardware Decode: [NOTE] no Windows hwaccel in this build (use a full gyan.dev/BtbN build)"
      fi
    else
      render_node=""
      for rn in /dev/dri/renderD*; do [[ -e "$rn" ]] && { render_node="$rn"; break; }; done
      echo "  * DRM Render Node: ${render_node:-none found}"
      va_name=$(env_val LIBVA_DRIVER_NAME)
      echo "  * LIBVA_DRIVER_NAME: $(env_show LIBVA_DRIVER_NAME "[UNSET] (libva auto-selects)")"
      if [[ -n "$va_name" ]]; then
        va_found=""
        va_dirs="${LIBVA_DRIVERS_PATH:-}:/usr/lib/dri:/usr/lib64/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/aarch64-linux-gnu/dri"
        IFS=: read -r -a va_dir_arr <<< "$va_dirs"
        for vd in "${va_dir_arr[@]}"; do
          [[ -n "$vd" && -f "$vd/${va_name}_drv_video.so" ]] && { va_found="$vd/${va_name}_drv_video.so"; break; }
        done
        if [[ -n "$va_found" ]]; then
          echo "  * VA-API Driver: [OK] $va_found"
        else
          echo "  * VA-API Driver: [WARNING] ${va_name}_drv_video.so not found (wrong LIBVA_DRIVER_NAME breaks hardware decode in ffmpeg, mpv and browsers)"
        fi
      fi
      if [[ -n "${ff_hw:-}" && " $ff_hw " == *" vaapi "* ]]; then
        if [[ -n "$render_node" ]]; then
          echo "  * Hardware Decode: [OK] vaapi compiled in and $render_node present"
        else
          echo "  * Hardware Decode: [NOTE] vaapi compiled in but no render node (container, VM or missing GPU driver)"
        fi
      elif [[ -n "$ff_bin" ]]; then
        echo "  * Hardware Decode: [NOTE] this ffmpeg build lists no vaapi hwaccel"
      fi
      if [[ -n "$render_node" ]] && command -v vainfo >/dev/null 2>&1; then
        va_info=$(timeout 5 vainfo --display drm --device "$render_node" 2>&1 </dev/null | grep -m1 -i 'driver version' | sed 's/.*:[[:space:]]*//' || true)
        echo "  * vainfo Driver: ${va_info:-unknown}"
      fi
    fi
    ff_presets="$HOME/.ffmpeg"
    [[ -d "$ff_presets" ]] && echo "  * User Presets: $ff_presets ($(find "$ff_presets" -maxdepth 1 -name '*.ffpreset' 2>/dev/null | wc -l | tr -d ' ') .ffpreset file(s))"
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: -hwaccel vaapi (Linux) / d3d11va (Windows) for decode; -threads 0 lets ffmpeg size the pool; prefer -c copy when no re-encode is needed"
    echo "  * Configuration: Set LIBVA_DRIVER_NAME only when auto-detection picks the wrong driver (i965 for Haswell and older Intel, iHD for Broadwell+)"
    echo "  * Security: Process untrusted media with -protocol_whitelist file,pipe so playlists cannot fetch URLs; keep ffmpeg updated (demuxer CVEs)"
    echo "====================================="
    exit 0
    ;;
  zstd)
    echo "Category: Compression / Zstandard (zstd)"
    zs_bin=$(command -v zstd 2>/dev/null || echo "")
    echo "Binary: ${zs_bin:-Not installed}"
    [[ -n "$zs_bin" ]] && echo "Version: $(first_clean_line_or unknown "$zs_bin" --version)"
    echo "Environment (read by the zstd CLI):"
    echo "  * ZSTD_NBTHREADS: $(env_show ZSTD_NBTHREADS)"
    echo "  * ZSTD_CLEVEL: $(env_show ZSTD_CLEVEL)"
    echo "Zstd Findings:"
    zs_thr=$(env_val ZSTD_NBTHREADS)
    if [[ -z "$zs_thr" ]]; then
      echo "  * Threads: [NOTE] unset (the CLI picks a small default; set ZSTD_NBTHREADS=$detected_threads or pass -T0 for large archives)"
    elif [[ "$zs_thr" =~ ^[0-9]+$ ]]; then
      if [[ "$zs_thr" -eq 0 || "$zs_thr" -le "$detected_threads" ]]; then
        echo "  * Threads: [OK] $zs_thr (host has $detected_threads thread(s); 0 = all cores)"
      else
        echo "  * Threads: [WARNING] $zs_thr exceeds the $detected_threads hardware thread(s) (oversubscription; use $detected_threads or 0)"
      fi
    else
      echo "  * Threads: [WARNING] '$zs_thr' is not a number (zstd ignores it)"
    fi
    zs_lvl=$(env_val ZSTD_CLEVEL)
    if [[ -z "$zs_lvl" ]]; then
      echo "  * Default Level: [OK] unset (zstd default 3)"
    elif [[ "$zs_lvl" =~ ^-?[0-9]+$ ]] && (( zs_lvl <= 19 )); then
      if (( zs_lvl > 12 )); then
        echo "  * Default Level: [NOTE] $zs_lvl (slow for everyday use; tools that inherit ZSTD_CLEVEL become much slower)"
      else
        echo "  * Default Level: [OK] $zs_lvl"
      fi
    else
      echo "  * Default Level: [WARNING] '$zs_lvl' is invalid or above 19 (levels 20-22 need --ultra; zstd ignores the variable)"
    fi
    if [[ -r /etc/makepkg.conf ]]; then
      mk_zst=$(cat /etc/makepkg.conf /etc/makepkg.conf.d/*.conf "${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf" 2>/dev/null | grep -E '^[[:space:]]*COMPRESSZST=' | tail -n 1 || true)
      if [[ "$mk_zst" == *"-T0"* || "$mk_zst" == *"--threads=0"* ]]; then
        echo "  * makepkg COMPRESSZST: [OK] multithreaded ($mk_zst)"
      elif [[ -n "$mk_zst" ]]; then
        echo "  * makepkg COMPRESSZST: [NOTE] $mk_zst (add -T0 so package compression uses every core)"
      fi
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: ZSTD_NBTHREADS sized to the CPU (or -T0); --long=27 for large similar files; level 3 default, 19 only for archives"
    echo "  * Configuration: Keep env defaults conservative: every tool that shells out to zstd (makepkg, tar --zstd, mkinitcpio) inherits them"
    echo "  * Security: Verify downloaded .zst archives with checksums/signatures before extracting; zstd --test checks integrity"
    echo "====================================="
    exit 0
    ;;
  chrome|google-chrome|google-chrome-stable|chromium)
    echo "Category: Web Browser / Google Chrome"
    if is_windows; then
      browser_report_win chrome.exe "$local_app_data/Google/Chrome/User Data" 'HKLM:\SOFTWARE\Policies\Google\Chrome'
    else
      browser_report_linux "$(command -v google-chrome-stable || command -v google-chrome || command -v chromium || true)"
      browser_policy_linux /etc/opt/chrome/policies/managed /etc/chromium/policies/managed
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Hardware acceleration on; trim startup extensions"
    echo "  * Configuration: One profile per context; sync only what is needed"
    echo "  * Security: Safe Browsing on, auto-update on, audit extensions"
    echo "====================================="
    exit 0
    ;;
  edge|msedge|microsoft-edge)
    echo "Category: Web Browser / Microsoft Edge"
    if is_windows; then
      browser_report_win msedge.exe "$local_app_data/Microsoft/Edge/User Data" 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    else
      browser_report_linux "$(command -v microsoft-edge-stable || command -v microsoft-edge || true)"
      browser_policy_linux /etc/opt/edge/policies/managed
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Startup boost and background mode only if wanted; hardware acceleration on"
    echo "  * Configuration: One profile per context; sync only what is needed"
    echo "  * Security: SmartScreen on, auto-update on, audit extensions"
    echo "====================================="
    exit 0
    ;;
  brave|brave-browser|brave-bin)
    echo "Category: Web Browser / Brave Browser"
    if is_windows; then
      browser_report_win brave.exe "$local_app_data/BraveSoftware/Brave-Browser/User Data" 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave'
    else
      browser_report_linux "$(command -v brave-browser || command -v brave || true)"
      browser_policy_linux /etc/brave/policies/managed
      brave_flags="${XDG_CONFIG_HOME:-$HOME/.config}/brave-flags.conf"
      if [[ -f "$brave_flags" ]]; then
        echo "Launch Flags: [EXISTS] $brave_flags$(cfg_perm_tag "$brave_flags")"
        # The Arch launcher reads this file with mapfile and drops only whole-line comments: a trailing
        # "# note" after a flag is passed to Brave as literal arguments.
        bf_inline=$(grep -nE '^[[:space:]]*[^#[:space:]].*[[:space:]]#' "$brave_flags" 2>/dev/null || true)
        if [[ -n "$bf_inline" ]]; then
          echo "  * Inline Comments: [WARNING] trailing '#' comments are passed to Brave as arguments; move them to their own line:"
          printf '%s\n' "$bf_inline" | sed "s|^|    $brave_flags:|"
        else
          echo "  * Inline Comments: [OK] none (only whole-line comments)"
        fi
        bf_dupes=$(grep -vE '^[[:space:]]*(#|$)' "$brave_flags" 2>/dev/null | sed -E 's/=.*//; s/[[:space:]]+$//' | sort | uniq -d | tr '\n' ' ' || true)
        [[ -n "$bf_dupes" ]] && echo "  * Duplicate Flags: [WARNING] ${bf_dupes% } (later values override earlier ones; merge them)"
      fi
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Hardware acceleration on; enable Memory Saver; trim unused startup extensions"
    echo "  * Configuration: Separate profiles per context; sync only needed data types"
    echo "  * Security: Brave Shields tracker/fingerprinting protection active, Safe Browsing on, auto-update on, audit extensions"
    echo "====================================="
    exit 0
    ;;
  firefox|mozilla-firefox|librewolf)
    if [[ "$target" == "librewolf" ]]; then
      echo "Category: Web Browser / LibreWolf"
      ff_app="librewolf.exe"
      ff_win_profiles="$roaming_app_data/librewolf/Profiles"
      ff_policy_key='HKLM:\SOFTWARE\Policies\LibreWolf'
    else
      echo "Category: Web Browser / Mozilla Firefox"
      ff_app="firefox.exe"
      ff_win_profiles="$roaming_app_data/Mozilla/Firefox/Profiles"
      ff_policy_key='HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
    fi
    if is_windows; then
      ff_info=$(SO_APP="$ff_app" SO_KEY="$ff_policy_key" run_ps '
        $p = ""
        foreach ($r in "HKLM","HKCU") {
          $v = (Get-ItemProperty "${r}:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$env:SO_APP" -ErrorAction SilentlyContinue)."(default)"
          if ($v) { $p = $v; break }
        }
        if (-not $p) {
          $cands = if ($env:SO_APP -eq "librewolf.exe") {
            @("$env:ProgramFiles\LibreWolf\librewolf.exe", "${env:ProgramFiles(x86)}\LibreWolf\librewolf.exe", "$env:LOCALAPPDATA\Programs\librewolf\librewolf.exe", "$env:LOCALAPPDATA\LibreWolf\librewolf.exe")
          } else {
            @("$env:ProgramFiles\Mozilla Firefox\firefox.exe", "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe", "$env:LOCALAPPDATA\Mozilla Firefox\firefox.exe")
          }
          foreach ($cand in $cands) {
            if ($cand -and (Test-Path -LiteralPath $cand)) { $p = $cand; break }
          }
        }
        $p
        if ($p) { (Get-Item -LiteralPath $p).VersionInfo.ProductVersion } else { "" }
        $polFile = if ($p) { Join-Path (Split-Path -Parent $p) "distribution\policies.json" } else { "" }
        ((Test-Path -Path $env:SO_KEY) -or ([bool]$polFile -and (Test-Path -LiteralPath $polFile)))
      ' 2>/dev/null || true)
      { read -r ff_exe; read -r ff_ver; read -r ff_managed; } <<< "$ff_info" || true
      if [[ -n "${ff_exe:-}" ]]; then
        echo "Status: INSTALLED"
        echo "Executable: $ff_exe"
        echo "Version: ${ff_ver:-unknown}"
      elif [[ -d "$ff_win_profiles" ]]; then
        echo "Status: user data found, executable not located"
      else
        echo "Status: NOT INSTALLED"
      fi
      if [[ -d "$ff_win_profiles" ]]; then
        ff_prof_count=$(find "$ff_win_profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ' || true)
        echo "Profiles Directory: $ff_win_profiles"
        echo "Profiles: ${ff_prof_count:-0}"
      fi
      echo "Managed Policies: ${ff_managed:-unknown}"
    else
      if [[ "$target" == "librewolf" ]]; then
        browser_report_linux "$(command -v librewolf || true)"
        browser_policy_linux /etc/librewolf/policies /usr/lib/librewolf/distribution
        ff_linux_dir="$HOME/.librewolf"
      else
        browser_report_linux "$(command -v firefox || true)"
        browser_policy_linux /etc/firefox/policies /usr/lib/firefox/distribution
        ff_linux_dir="$HOME/.mozilla/firefox"
      fi
      if [[ -d "$ff_linux_dir" ]]; then
        ff_prof_count=$(find "$ff_linux_dir" -mindepth 1 -maxdepth 1 -type d -name '*.*' 2>/dev/null | wc -l | tr -d ' ' || true)
        echo "Profiles Directory: $ff_linux_dir ($ff_prof_count profile dir(s))"
      fi
    fi
    # Preference files: LibreWolf's librewolf.overrides.cfg (~/.librewolf, %USERPROFILE%\.librewolf) and
    # each profile's user.js. Quote the performance/privacy keys they set.
    ff_pref_files=()
    if [[ "$target" == "librewolf" ]]; then
      for f in "$HOME/.librewolf/librewolf.overrides.cfg" "${XDG_CONFIG_HOME:-$HOME/.config}/librewolf/librewolf.overrides.cfg"; do
        [[ -f "$f" ]] && ff_pref_files+=("$f")
      done
    fi
    for ff_pdir in "${ff_linux_dir:-}" "${ff_win_profiles:-}"; do
      [[ -n "$ff_pdir" && -d "$ff_pdir" ]] || continue
      while IFS= read -r f; do
        [[ -n "$f" ]] && ff_pref_files+=("$f")
      done < <(find "$ff_pdir" -mindepth 2 -maxdepth 2 -name user.js -type f 2>/dev/null || true)
    done
    echo "Preference Files:"
    if [[ ${#ff_pref_files[@]} -eq 0 ]]; then
      if [[ "$target" == "librewolf" ]]; then
        echo "  * Overrides: [NOT CONFIGURED] (Recommend: ~/.librewolf/librewolf.overrides.cfg for settings that survive updates)"
      else
        echo "  * user.js: [NOT CONFIGURED] (Recommend: a profile user.js for reproducible preferences)"
      fi
    else
      ff_pref_re='media\.hardware-video-decoding|media\.ffmpeg\.vaapi|gfx\.webrender|layers\.acceleration|browser\.tabs\.unloadOnLowMemory|dom\.security\.https_only_mode|privacy\.resistFingerprinting|network\.trr\.mode|browser\.cache\.disk'
      for f in "${ff_pref_files[@]}"; do
        echo "  - [EXISTS] $f$(cfg_perm_tag "$f")"
        grep -nE "^[[:space:]]*(user_)?(pref|defaultPref|lockPref)\([[:space:]]*[\"'](${ff_pref_re})" "$f" 2>/dev/null | sed "s|^|    $f:|" || true
      done
      ff_all=$(cat "${ff_pref_files[@]}" 2>/dev/null | grep -vE '^[[:space:]]*//' || true)
      if is_windows; then
        :
      elif printf '%s' "$ff_all" | grep -qE "media\.hardware-video-decoding\.force-enabled[\"'][[:space:]]*,[[:space:]]*true|media\.ffmpeg\.vaapi\.enabled[\"'][[:space:]]*,[[:space:]]*true"; then
        echo "  * Hardware Video Decoding: [OK] forced on in a preference file"
      else
        echo "  * Hardware Video Decoding: [NOTE] not forced (Recommend: media.hardware-video-decoding.force-enabled = true on VA-API capable GPUs)"
      fi
      if printf '%s' "$ff_all" | grep -qE "privacy\.resistFingerprinting[\"'][[:space:]]*,[[:space:]]*true"; then
        echo "  * resistFingerprinting: [NOTE] enabled (breaks site time zones/dark mode; LibreWolf default, intended for privacy)"
      fi
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Performance: Hardware WebRender compositing & media.hardware-video-decoding.force-enabled (Firefox 137+ on Linux) / D3D11 video decode (Windows); auto-unload inactive tabs on low/medium RAM"
    echo "  * Configuration: Manage reproducible preferences via profile user.js; keep separate profiles per workflow"
    echo "  * Security: Enable HTTPS-Only Mode, Enhanced Tracking Protection (Strict), DNS-over-HTTPS, and audit extensions"
    echo "====================================="
    exit 0
    ;;
  system|os)
    echo "Category: System Meta-Target / Host Hardware & OS Baseline"
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    bash "$script_dir/hardware-probe.sh"
    echo ""
    bash "$script_dir/system-probe.sh"
    echo "====================================="
    exit 0
    ;;
  security|hardening|audit)
    echo "Category: Security Meta-Target / Defensive Posture Audit"
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    bash "$script_dir/security-audit.sh"
    echo "====================================="
    exit 0
    ;;
  full|all)
    echo "Category: System Meta-Target / Full Workstation Inspection Sweep"
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    bash "$script_dir/hardware-probe.sh"
    echo ""
    bash "$script_dir/system-probe.sh"
    echo ""
    bash "$script_dir/security-audit.sh"
    echo ""
    bash "$script_dir/detect-targets.sh"
    echo "====================================="
    exit 0
    ;;
  sandboxing|systemd-security)
    echo "Category: Security / Service & Application Sandboxing"
    if is_windows; then
      hvci_state=$(run_ps '
        $hvci = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name Enabled -ErrorAction SilentlyContinue).Enabled
        if ($null -ne $hvci) { [int]$hvci } else { "unknown" }
      ' 2>/dev/null || echo "unknown")
      case "$hvci_state" in
        1) echo "  * Memory Integrity (HVCI): Enabled [OK]" ;;
        0) echo "  * Memory Integrity (HVCI): Disabled [WARNING] (Enable Core Isolation Memory Integrity)" ;;
        *) echo "  * Memory Integrity (HVCI): unknown [NOT READABLE]" ;;
      esac
    else
      if [[ -r /sys/module/apparmor/parameters/enabled ]] && [[ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" == "Y" ]]; then
        echo "  * Mandatory Access Control: AppArmor enabled [OK]"
      elif command -v getenforce >/dev/null 2>&1 && [[ "$(getenforce 2>/dev/null || true)" == "Enforcing" ]]; then
        echo "  * Mandatory Access Control: SELinux Enforcing [OK]"
      else
        echo "  * Mandatory Access Control: none active [NOTE] (AppArmor or SELinux not detected as enforcing)"
      fi
      if [[ -e /proc/sys/kernel/unprivileged_userns_clone ]]; then
        sysctl_check kernel.unprivileged_userns_clone '1' '1 (required for rootless Podman/Flatpak/bwrap)'
      fi
      echo "  * Bubblewrap (bwrap): $(command -v bwrap 2>/dev/null || echo 'not installed')"
      if command -v systemd-analyze >/dev/null 2>&1; then
        sa_raw=$(LC_ALL=C systemd-analyze security 2>/dev/null || true)
        sb_counts=$(printf '%s\n' "$sa_raw" | LC_ALL=C awk '$2 ~ /^[0-9]/ { if ($2 >= 8.0) u++; else if ($2 >= 5.0) m++; else o++ } END { printf "%d %d %d\n", o+0, m+0, u+0 }')
        read -r sb_ok sb_med sb_unsafe <<< "$sb_counts"
        if [[ "${sb_unsafe:-0}" -gt 0 ]]; then
          echo "  * systemd Service Exposure: [WARNING] $sb_unsafe unsafe/exposed (>=8.0), $sb_med medium, $sb_ok OK"
        else
          echo "  * systemd Service Exposure: [OK] 0 unsafe units ($sb_med medium, $sb_ok OK)"
        fi
      else
        echo "  * systemd Service Exposure: unavailable [NOT READABLE]"
      fi
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Security: Harden exposed custom systemd units (ProtectSystem=strict, PrivateTmp=true, NoNewPrivileges=true); keep MAC/HVCI active"
    echo "  * Configuration: Prefer rootless containers (Podman) and portal-restricted Flatpak overrides over host-wide privileges"
    echo "  * Performance: Avoid heavy VM isolation for trusted CLI workloads where namespace sandboxing suffices"
    echo "====================================="
    exit 0
    ;;
  package-audit|pkg-audit|supply-chain)
    echo "Category: Security / Package Integrity & Vulnerability Audit"
    if is_windows; then
      if command -v winget >/dev/null 2>&1; then
        wg_exp=$(winget settings export 2>/dev/null | tr -d '\r' || true)
        if printf '%s\n' "$wg_exp" | grep -qE '"(InstallerHashOverride|LocalArchiveMalwareScanOverride)"[[:space:]]*:[[:space:]]*true'; then
          echo "  * WinGet Integrity Overrides: [WARNING] hash or malware scan override is enabled"
        elif [[ -n "$wg_exp" ]]; then
          echo "  * WinGet Integrity Overrides: [OK] hash and malware scan checks enforced"
        else
          echo "  * WinGet Integrity Overrides: [NOT READABLE]"
        fi
      else
        echo "  * WinGet Integrity Overrides: winget not installed [NOT READABLE]"
      fi
    else
      if [[ -r /etc/pacman.conf ]]; then
        # Every SigLevel line counts (the global [options] one and any per-repository override), plus the
        # Include'd repository files under /etc/pacman.d.
        pac_conf_files=(/etc/pacman.conf)
        while IFS= read -r inc; do
          [[ -r "$inc" ]] && pac_conf_files+=("$inc")
        done < <(grep -hE '^[[:space:]]*Include[[:space:]]*=' /etc/pacman.conf 2>/dev/null | sed 's/.*=[[:space:]]*//' | sort -u || true)
        sig_all=$(grep -HnE '^[[:space:]]*SigLevel[[:space:]]*=' "${pac_conf_files[@]}" 2>/dev/null || true)
        sig_lvl=$(grep -E '^[[:space:]]*SigLevel[[:space:]]*=' /etc/pacman.conf 2>/dev/null | head -n 1 | sed 's/.*=[[:space:]]*//' || true)
        sig_weak=$(printf '%s\n' "$sig_all" | grep -E '=[^#]*\b(Never|TrustAll)\b' || true)
        if [[ -n "$sig_weak" ]]; then
          echo "  * Pacman SigLevel: [WARNING] Never/TrustAll weakens GPG package verification:"
          printf '%s\n' "$sig_weak" | sed 's/^/    /'
        else
          echo "  * Pacman SigLevel (/etc/pacman.conf): ${sig_lvl:-default (Required DatabaseOptional)} [OK] ($(printf '%s\n' "$sig_all" | grep -c . || true) SigLevel line(s) checked)"
        fi
        dl_user=$(grep -E '^[[:space:]]*DownloadUser[[:space:]]*=' /etc/pacman.conf 2>/dev/null | head -n 1 | sed 's/.*=[[:space:]]*//' || true)
        if [[ -n "$dl_user" ]]; then
          echo "  * Pacman DownloadUser: $dl_user [OK] (downloads run unprivileged)"
        else
          echo "  * Pacman DownloadUser: unset [WARNING] (Recommended: DownloadUser = alpm, pacman 7.0+)"
        fi
        if grep -qE '^[[:space:]]*DisableSandbox' /etc/pacman.conf 2>/dev/null; then
          echo "  * Pacman Download Sandbox: [WARNING] DisableSandbox* is set (Landlock/seccomp download sandbox off)"
        else
          echo "  * Pacman Download Sandbox: [OK] not disabled"
        fi
      elif [[ -d /etc/apt ]]; then
        if grep -RqiE 'AllowUnauthenticated[[:space:]]+"true"' /etc/apt/apt.conf /etc/apt/apt.conf.d 2>/dev/null; then
          echo "  * APT Signature Policy: AllowUnauthenticated=true [WARNING]"
        else
          echo "  * APT Signature Policy: GPG repository verification active [OK]"
        fi
      elif [[ -r /etc/dnf/dnf.conf ]]; then
        if grep -Eqi '^[[:space:]]*gpgcheck[[:space:]]*=[[:space:]]*(1|true|yes)' /etc/dnf/dnf.conf 2>/dev/null; then
          echo "  * DNF Signature Policy: gpgcheck enabled [OK]"
        else
          echo "  * DNF Signature Policy: gpgcheck not enabled [WARNING]"
        fi
      else
        echo "  * OS Package Signature Policy: [NOT READABLE] (no readable pacman/apt/dnf config)"
      fi
      scanners=()
      for sc in arch-audit cargo-audit pip-audit trivy osv-scanner; do
        command -v "$sc" >/dev/null 2>&1 && scanners+=("$sc")
      done
      echo "  * Installed Vulnerability Scanners: ${scanners[*]:-none detected}"
    fi
    echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
    echo "  * Security: Enforce GPG/hash verification across OS and language package managers (pacman SigLevel, winget hash check, mise SLSA/cosign)"
    echo "  * Configuration: Install arch-audit / unattended-upgrades / cargo-audit to catch CVEs early"
    echo "  * Performance: Schedule vulnerability database syncs alongside regular topgrade maintenance"
    echo "====================================="
    exit 0
    ;;
esac

case "$target" in
  pacman|yay|paru|makepkg|paccache|pacman-contrib) echo "Category: Package Manager / Arch Linux Package & Build Stack" ;;
  flatpak) echo "Category: Package Manager / Flatpak Sandboxed Applications" ;;
  kde|kde-plasma|baloo) echo "Category: Desktop Environment / KDE Plasma & KWin" ;;
  podman|docker|lazydocker) echo "Category: Containers / Container Runtime & Lazydocker" ;;
  fd|fdfind) echo "Category: Search Utility / fd File Finder" ;;
  btop|htop|btop4win) echo "Category: System Monitor / Resource & Process Viewer" ;;
  syncthing) echo "Category: File Synchronization / Syncthing" ;;
  python|python3) echo "Category: Language Runtime / Python" ;;
  uv) echo "Category: Python Package & Project Manager / uv" ;;
  sqlite3) echo "Category: Database CLI / SQLite3" ;;
  *) echo "Category: Package / Tool ($target)" ;;
esac

binary_lookup="$target"
case "$target" in
  kde|kde-plasma) binary_lookup="plasmashell" ;;
  baloo) binary_lookup="balooctl6" ;;
  pacman-contrib) binary_lookup="paccache" ;;
  yay) binary_lookup="paru" ;;   # detect-targets.sh folds paru into yay: a paru-only host must still resolve
  fd) binary_lookup="fdfind" ;;
  btop) binary_lookup="btop4win" ;;
  bat) binary_lookup="batcat" ;;
  python) binary_lookup="python3" ;;
esac

bin_path=$(command -v -- "$target" 2>/dev/null || command -v -- "$binary_lookup" 2>/dev/null || echo "")

if [[ -z "$bin_path" ]]; then
  echo "Status: NOT FOUND IN PATH"
  echo "Checking common installation locations..."
  if is_windows; then
    if command -v winget >/dev/null 2>&1; then
      echo "Winget package search for '$target':"
      winget search --count 5 --accept-source-agreements "$target" 2>/dev/null | tr -d '\r' | head -n 8 || true
    fi
  else
    if command -v pacman >/dev/null 2>&1; then
      pacman -Ss "^$target$" 2>/dev/null | head -n 4 || true
    elif command -v apt >/dev/null 2>&1; then
      apt-cache search "^$target$" 2>/dev/null | head -n 4 || true
    fi
  fi
  echo "====================================="
  exit 0
fi

case "$target" in
  python|python3)
    if ! python_ok "$bin_path"; then
      py_out=$("$bin_path" --version 2>&1 </dev/null || true)
      if is_windows || [[ "$bin_path" == *WindowsApps* || "$py_out" == *"Microsoft Store"* ]]; then
        echo "Status: NOT INSTALLED (the python command is only the Microsoft Store shortcut)"
        echo "Binary Path: $bin_path"
        echo "====================================="
        exit 0
      fi
      # A broken stub or shim on Unix may shadow a working interpreter: try fallback names before giving up.
      py_alt=""
      for py_cand in python3 python /usr/bin/python3 /usr/local/bin/python3; do
        py_cand_path=$(command -v -- "$py_cand" 2>/dev/null || true)
        if [[ -n "$py_cand_path" && "$py_cand_path" != "$bin_path" ]] && python_ok "$py_cand_path"; then
          py_alt="$py_cand_path"
          break
        fi
      done
      if [[ -n "$py_alt" ]]; then
        echo "  * [WARNING] $bin_path does not run as Python (broken stub or shim); using $py_alt"
        bin_path="$py_alt"
      else
        echo "Status: BROKEN ($bin_path --version did not report a Python version)"
        echo "  * [WARNING] Output: $(printf '%s' "$py_out" | strip_ansi | head -n 2 | tr '\n' ' ')"
        echo "Binary Path: $bin_path"
        echo "====================================="
        exit 0
      fi
    fi
    ;;
esac

echo "Status: INSTALLED"
echo "Binary Path: $bin_path"

version="unknown"
if [[ "$target" == "sqlite3" ]]; then
  version=$(first_clean_line_or "unknown" "$bin_path" -batch -init /dev/null --version)
else
  ver_flags=("--version" "-V" "-v" "version")
  # ffmpeg/ffprobe only accept the single-dash -version (and -v takes an argument)
  [[ "$target" == ffmpeg || "$target" == ffprobe ]] && ver_flags=("-version")
  for flag in "${ver_flags[@]}"; do
    if raw_ver=$("$bin_path" "$flag" 2>/dev/null </dev/null); then
      ver_out=$(printf '%s\n' "$raw_ver" | strip_ansi | awk 'NF && !found { out=$0; found=1 } END { if (found) printf "%s", out }')
      if [[ -n "$ver_out" ]]; then
        version="$ver_out"
        break
      fi
    fi
  done
fi
echo "Version: $version"

st_cli_cfg=""
st_cli_db=""
if [[ "$target" == "syncthing" ]]; then
  st_paths_out=$("$bin_path" paths 2>/dev/null | strip_ansi || true)
  if [[ -n "$st_paths_out" ]]; then
    st_cli_cfg=$(printf '%s\n' "$st_paths_out" | awk '/Configuration file:/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
    st_cli_db=$(printf '%s\n' "$st_paths_out" | awk '/Database location:/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
  fi
fi

# Candidate Config Locations (Cross-Platform)
config_candidates=(
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/$target.toml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/$target.yaml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/$target.json"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config.toml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config.yaml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config.json"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/config"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target.toml"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/init.lua"
  "${XDG_CONFIG_HOME:-$HOME/.config}/$target/init.vim"
  "$HOME/.$target"
  "$HOME/.${target}rc"
  "$HOME/.${target}.toml"
  "$HOME/.${target}config"
  "$roaming_app_data/$target.toml"
  "$roaming_app_data/$target/config.toml"
  "$local_app_data/$target/init.lua"
  "$local_app_data/$target/$target.json"
)

# Tool-specific known paths
case "$target" in
  pacman|yay|paru|makepkg|paccache|pacman-contrib)
    config_candidates+=("/etc/pacman.conf" "/etc/makepkg.conf" "/etc/makepkg.conf.d" "${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf" "$HOME/.makepkg.conf" "/etc/conf.d/pacman-contrib" "${XDG_CONFIG_HOME:-$HOME/.config}/yay/config.json")
    ;;
  kde|kde-plasma)
    config_candidates+=("$HOME/.config/kdeglobals" "$HOME/.config/kwinrc" "$HOME/.config/baloofilerc")
    ;;
  flatpak)
    config_candidates+=("$HOME/.local/share/flatpak/overrides/global" "/var/lib/flatpak/overrides/global")
    ;;
  podman)
    config_candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/containers/containers.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/containers/containers.conf.d" "${XDG_CONFIG_HOME:-$HOME/.config}/containers/registries.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/containers/storage.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd" "/etc/containers/containers.conf" "/etc/containers/systemd")
    ;;
  lazydocker)
    config_candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/lazydocker/config.yml" "$roaming_app_data/lazydocker/config.yml")
    ;;
  docker)
    config_candidates+=("$HOME/.docker/config.json" "${XDG_CONFIG_HOME:-$HOME/.config}/docker/daemon.json" "/etc/docker/daemon.json")
    ;;
  fd|fdfind)
    config_candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/fd/ignore" "$roaming_app_data/fd/ignore")
    ;;
  btop|htop|btop4win)
    config_candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/btop/btop.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/htop/htoprc" "$local_app_data/btop/btop.conf")
    ;;
  syncthing)
    [[ -n "$st_cli_cfg" ]] && config_candidates+=("$st_cli_cfg")
    config_candidates+=("${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml" "${XDG_CONFIG_HOME:-$HOME/.config}/syncthing/config.xml" "$local_app_data/Syncthing/config.xml")
    ;;
  uv)
    [[ -n "${UV_CONFIG_FILE:-}" ]] && config_candidates+=("$UV_CONFIG_FILE")
    config_candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" "$roaming_app_data/uv/uv.toml" "/etc/uv/uv.toml")
    ;;
  python|python3)
    config_candidates+=("${PIP_CONFIG_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/pip/pip.conf}" "$roaming_app_data/pip/pip.ini" "${PYTHON_HISTORY:-${XDG_STATE_HOME:-$HOME/.local/state}/python_history}" "$HOME/.python_history")
    ;;
  sqlite3)
    config_candidates+=("$HOME/.sqliterc")
    ;;
esac

echo "Discovered Config Locations:"
found_configs=0
declare -A seen_paths
for cfg in "${config_candidates[@]}"; do
  [[ -z "$cfg" ]] && continue
  [[ -n "${seen_paths[$cfg]:-}" ]] && continue
  seen_paths["$cfg"]=1
  if [[ -d "$cfg" ]]; then
    echo "  - [EXISTS DIR] $cfg"
    found_configs=$((found_configs + 1))
  elif [[ -e "$cfg" ]]; then
    echo "  - [EXISTS] $cfg$(cfg_perm_tag "$cfg")"
    found_configs=$((found_configs + 1))
  fi
done

if [[ $found_configs -eq 0 ]]; then
  echo "  - None of standard candidate paths exist yet."
fi

# Target-specific state inspection for Linux & cross-platform tools
case "$target" in
  python|python3)
    echo "Active Python Environment:"
    py_ext=$("$bin_path" -c 'import os, sysconfig; print(os.path.exists(os.path.join(sysconfig.get_path("stdlib"), "EXTERNALLY-MANAGED")))' 2>/dev/null | tr -d '\r' || echo unknown)
    case "$py_ext" in
      True)  echo "  * System pip protected (EXTERNALLY-MANAGED): [OK]" ;;
      False) echo "  * System pip protected (EXTERNALLY-MANAGED): [NOTE] this Python has no marker, so pip can change it (fine for pyenv or a virtualenv; otherwise use venv, uv or pipx)" ;;
      *)     echo "  * System pip protected (EXTERNALLY-MANAGED): unknown" ;;
    esac
    if [[ "$py_ext" == "False" ]]; then
      pip_cfg_found=""
      for pf in "${PIP_CONFIG_FILE:-}" "${XDG_CONFIG_HOME:-$HOME/.config}/pip/pip.conf" "$roaming_app_data/pip/pip.ini"; do
        [[ -n "$pf" && -f "$pf" ]] && pip_cfg_found="$pf" && break
      done
      pip_req_venv=$(env_val PIP_REQUIRE_VIRTUALENV)
      if [[ -z "$pip_req_venv" && -n "$pip_cfg_found" ]]; then
        pip_req_venv=$(grep -iE '^[[:space:]]*require-virtualenv[[:space:]]*=' "$pip_cfg_found" 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d ' "' || true)
      fi
      if [[ "${pip_req_venv,,}" == "true" || "$pip_req_venv" == "1" ]]; then
        echo "  * pip require-virtualenv: [OK] ($pip_req_venv)"
      else
        echo "  * pip require-virtualenv: [NOTE] unset (without EXTERNALLY-MANAGED, set PIP_REQUIRE_VIRTUALENV=true or require-virtualenv = true in pip.conf)"
      fi
    fi
    echo "  * Virtualenv active: ${VIRTUAL_ENV:-no}"
    echo "  * uv: $(command -v uv 2>/dev/null || echo 'not installed')"
    echo "  * PYTHONSAFEPATH: $(env_show PYTHONSAFEPATH unset)"
    py_hist="${PYTHON_HISTORY:-${XDG_STATE_HOME:-$HOME/.local/state}/python_history}"
    [[ ! -f "$py_hist" && -f "$HOME/.python_history" ]] && py_hist="$HOME/.python_history"
    if [[ -f "$py_hist" ]]; then
      echo "  * Python History ($py_hist):$(cfg_perm_tag "$py_hist")"
    fi
    py_rt_info=$("$bin_path" -c 'import sys; gil = sys._is_gil_enabled() if hasattr(sys, "_is_gil_enabled") else "n/a"; jit = hasattr(sys, "_jit"); lazy = sys.version_info >= (3, 15); print(f"gil={gil} jit_api={jit} py315_lazy={lazy}")' 2>/dev/null | tr -d '\r' || true)
    [[ -n "$py_rt_info" ]] && echo "  * Runtime Capabilities: $py_rt_info (PYTHON_LAZY_IMPORTS=${PYTHON_LAZY_IMPORTS:-unset})"
    ;;
  uv)
    echo "Active uv Environment & Cache:"
    uv_cache_dir=$("$bin_path" cache dir 2>/dev/null | tr -d '\r' || true)
    if [[ -n "$uv_cache_dir" && -d "$uv_cache_dir" ]]; then
      uv_cache_sz=$(du -sh "$uv_cache_dir" 2>/dev/null | awk '{print $1}' || echo "unknown")
      echo "  * Cache Directory: $uv_cache_dir ($uv_cache_sz)"
    elif [[ -n "$uv_cache_dir" ]]; then
      echo "  * Cache Directory: $uv_cache_dir (not created yet)"
    fi
    uv_tools_out=$("$bin_path" tool list 2>/dev/null || true)
    if [[ -n "$uv_tools_out" ]]; then
      uv_tool_cnt=$(printf '%s\n' "$uv_tools_out" | grep -cE '^[^[:space:]-]' || true)
      echo "  * Installed uv Tools: $uv_tool_cnt"
    else
      echo "  * Installed uv Tools: 0"
    fi
    uv_cfg=""
    for uf in "${UV_CONFIG_FILE:-}" "${XDG_CONFIG_HOME:-$HOME/.config}/uv/uv.toml" "$roaming_app_data/uv/uv.toml" "/etc/uv/uv.toml"; do
      [[ -n "$uf" && -f "$uf" ]] && uv_cfg="$uf" && break
    done
    if [[ -n "$uv_cfg" ]]; then
      echo "Active uv Configuration ($uv_cfg):"
      uv_bc=$(toml_section_val "$uv_cfg" "" "compile-bytecode")
      uv_lm=$(toml_section_val "$uv_cfg" "" "link-mode")
      uv_en=$(toml_section_val "$uv_cfg" "" "exclude-newer")
      echo "  * compile-bytecode: ${uv_bc:-${UV_COMPILE_BYTECODE:-default (false)}}"
      echo "  * link-mode: ${uv_lm:-${UV_LINK_MODE:-default (clone/hardlink)}}"
      echo "  * exclude-newer: ${uv_en:-unset}"
    else
      echo "  * UV_COMPILE_BYTECODE=${UV_COMPILE_BYTECODE:-unset}, UV_LINK_MODE=${UV_LINK_MODE:-unset}"
    fi
    if command -v mise >/dev/null 2>&1 && command -v topgrade >/dev/null 2>&1; then
      tg_uv_dis=""
      for tf in "$roaming_app_data/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/topgrade.d"/*.toml; do
        [[ -f "$tf" ]] && tg_uv_dis="$tg_uv_dis $(toml_extract_array "$tf" "disable")"
      done
      if [[ -n "${tg_uv_dis// /}" ]] && ! echo "$tg_uv_dis" | grep -qi "uv"; then
        echo "  * [NOTE] Both mise and topgrade detected; add 'uv' to topgrade disable = [...] if uv is managed by mise"
      fi
    fi
    ;;
  sqlite3)
    if [[ -f "$HOME/.sqliterc" ]]; then
      echo "Active ~/.sqliterc:$(cfg_perm_tag "$HOME/.sqliterc")"
      grep -vE '^[[:space:]]*(--|$)' "$HOME/.sqliterc" 2>/dev/null | sed 's/^/    /' | head -n 10 || true
      if grep -qiE 'journal_mode[[:space:]]*=[[:space:]]*WAL' "$HOME/.sqliterc" 2>/dev/null; then
        echo "  * [WARNING] PRAGMA journal_mode=WAL in ~/.sqliterc mutates every opened DB header and fails on read-only DBs/scripts"
      fi
    else
      echo "  * ~/.sqliterc: [NOT CONFIGURED] (Recommend: .output /dev/null, PRAGMA foreign_keys = ON;, PRAGMA busy_timeout = 5000;, .output stdout, .headers on, .mode box)"
    fi
    ;;
  pacman|yay|paru|makepkg|paccache|pacman-contrib)
    echo "Active Arch Linux Package & Build Settings:"
    if [[ -r /etc/pacman.conf ]]; then
      echo "  * ParallelDownloads (/etc/pacman.conf): $(grep -E '^[[:space:]]*ParallelDownloads' /etc/pacman.conf 2>/dev/null | awk -F= '{print $2}' | tr -d ' ' || echo 'commented/disabled')"
      pac_dl_user=$(grep -E '^[[:space:]]*DownloadUser[[:space:]]*=' /etc/pacman.conf 2>/dev/null | head -n 1 | awk -F= '{print $2}' | tr -d ' ' || true)
      if [[ -n "$pac_dl_user" ]]; then
        echo "  * DownloadUser (/etc/pacman.conf): $pac_dl_user [OK]"
      else
        echo "  * DownloadUser (/etc/pacman.conf): [WARNING] unset (Pacman 7+ privilege-drop sandbox disabled; recommend DownloadUser = alpm)"
      fi
      if grep -qE '^[[:space:]]*DisableSandbox(Filesystem|Syscalls)?([[:space:]]|$)' /etc/pacman.conf 2>/dev/null; then
        echo "  * [SECURITY WARNING] DisableSandbox* option active in /etc/pacman.conf (weakens Pacman 7+ download sandbox)"
      fi
      pac_sigs=$(grep -E '^[[:space:]]*SigLevel[[:space:]]*=' /etc/pacman.conf 2>/dev/null || true)
      echo "  * SigLevel (/etc/pacman.conf): $(printf '%s\n' "$pac_sigs" | head -n 1 | awk -F= '{print $2}' | sed 's/^[[:space:]]*//' || echo 'default')"
      if printf '%s\n' "$pac_sigs" | grep -qiE '\b(Never|TrustAll)\b'; then
        echo "  * [SECURITY WARNING] Weak SigLevel (Never/TrustAll) found in /etc/pacman.conf"
      fi
    fi
    for mf in /etc/makepkg.conf /etc/makepkg.conf.d/*.conf "${XDG_CONFIG_HOME:-$HOME/.config}/pacman/makepkg.conf" "$HOME/.makepkg.conf"; do
      [[ -r "$mf" ]] || continue
      mk_flags=$(grep -E '^[[:space:]]*MAKEFLAGS=' "$mf" 2>/dev/null | tail -n 1 || true)
      mk_opts=$(grep -E '^[[:space:]]*OPTIONS=' "$mf" 2>/dev/null | tail -n 1 || true)
      mk_rust=$(grep -E '^[[:space:]]*RUSTFLAGS=' "$mf" 2>/dev/null | tail -n 1 || true)
      [[ -n "$mk_flags" ]] && echo "  * MAKEFLAGS ($mf): $mk_flags"
      [[ -n "$mk_opts" ]] && echo "  * OPTIONS ($mf): $mk_opts"
      [[ -n "$mk_rust" ]] && echo "  * RUSTFLAGS ($mf): $mk_rust"
    done
    yay_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/yay/config.json"
    if [[ -r "$yay_cfg" ]]; then
      yay_sudo=$(grep -E '"sudoloop"[[:space:]]*:' "$yay_cfg" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,' || true)
      yay_clean=$(grep -E '"cleanAfter"[[:space:]]*:' "$yay_cfg" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,' || true)
      yay_rm=$(grep -E '"removemake"[[:space:]]*:' "$yay_cfg" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,"' || true)
      yay_diff=$(grep -E '"diffmenu"[[:space:]]*:' "$yay_cfg" 2>/dev/null | head -n 1 | awk -F: '{print $2}' | tr -d ' ,' || true)
      echo "  * yay Config ($yay_cfg): sudoloop=${yay_sudo:-false}, cleanAfter=${yay_clean:-false}, removemake=${yay_rm:-ask}, diffmenu=${yay_diff:-true}"
      if [[ "$yay_sudo" == "true" ]]; then
        echo "  * [WARNING] yay sudoloop=true keeps sudo credentials alive during untrusted AUR builds"
      fi
    fi
    if [[ -r /etc/conf.d/pacman-contrib ]]; then
      echo "  * paccache Config (/etc/conf.d/pacman-contrib): $(grep -E '^[[:space:]]*PACCACHE_ARGS=' /etc/conf.d/pacman-contrib 2>/dev/null || echo 'default')"
    fi
    echo "  * paccache.timer: $(first_line_or inactive systemctl is-active paccache.timer) ($(first_line_or disabled systemctl is-enabled paccache.timer))"
    ;;
  kde|kde-plasma)
    echo "Active KDE Plasma & KWin Parameters:"
    if [[ -f "$HOME/.config/kdeglobals" ]]; then
      echo "  * AnimationDurationFactor: $(grep -E '^AnimationDurationFactor=' "$HOME/.config/kdeglobals" 2>/dev/null | cut -d= -f2 || echo 'default (1.0)')"
    fi
    if [[ -f "$HOME/.config/baloofilerc" ]]; then
      echo "  * Baloo Indexing-Enabled: $(grep -E '^Indexing-Enabled=' "$HOME/.config/baloofilerc" 2>/dev/null | cut -d= -f2 || echo 'default (true)')"
    fi
    ;;
  flatpak)
    echo "Active Flatpak Remotes & Sandbox Overrides:"
    flatpak remotes --columns=name,options 2>/dev/null | sed 's/^/  * Remote: /' || true
    fp_ov="$HOME/.local/share/flatpak/overrides/global"
    if [[ -f "$fp_ov" ]] && grep -qE '^[[:space:]]*filesystems?=([^#]*;)?host($|;)' "$fp_ov" 2>/dev/null; then
      echo "  * Global Override ($fp_ov): [WARNING] grants filesystems=host across all Flatpak apps"
    elif [[ -f "$fp_ov" ]]; then
      echo "  * Global Override ($fp_ov): [OK] no global filesystem=host escape"
    fi
    for ov_dir in "$HOME/.local/share/flatpak/overrides" "/var/lib/flatpak/overrides"; do
      [[ -d "$ov_dir" ]] || continue
      for ovf in "$ov_dir"/*; do
        [[ -r "$ovf" && -f "$ovf" ]] || continue
        [[ "$ovf" == "$fp_ov" ]] && continue
        # backup copies (global.bak.<ts>, *.pre-restore-*) are not overrides flatpak applies
        case "$ovf" in *.bak*|*.pre-restore-*|*~) continue ;; esac
        if grep -qE '^[[:space:]]*filesystems?=([^#]*;)?(host|host-os|host-etc|home|/)($|;|:rw)' "$ovf" 2>/dev/null; then
          echo "  * Override ($ovf): [WARNING] grants broad filesystem access (host/host-os/host-etc/home//)"
        fi
      done
    done
    ;;
  podman)
    echo "Active Rootless Podman & Quadlet Status:"
    for cf in "${XDG_CONFIG_HOME:-$HOME/.config}/containers/containers.conf" "${XDG_CONFIG_HOME:-$HOME/.config}/containers/containers.conf.d"/*.conf "/etc/containers/containers.conf"; do
      [[ -r "$cf" && -f "$cf" ]] || continue
      echo "  * Inspecting $cf:"
      grep -E '^[[:space:]]*(pids_limit|log_size_max|runtime|network_backend)[[:space:]]*=' "$cf" 2>/dev/null | sed 's/^/    /' || true
      if grep -qE '^[[:space:]]*[^#]*slirp4netns' "$cf" 2>/dev/null; then
        echo "  * [WARNING] Removed 'slirp4netns' referenced in $cf (Podman 6 uses pasta/netavark)"
      fi
      if grep -qE '^[[:space:]]*log_max_size[[:space:]]*=' "$cf" 2>/dev/null; then
        echo "  * [WARNING] Typo 'log_max_size' in $cf (valid containers.conf key is 'log_size_max')"
      fi
    done
    if command -v pasta >/dev/null 2>&1 || command -v passt >/dev/null 2>&1; then
      echo "  * Rootless Network (pasta/passt): [AVAILABLE]"
    else
      echo "  * Rootless Network (pasta/passt): [NOT FOUND] (Podman 6 requires pasta for rootless networking)"
    fi
    quad_cnt=0
    for qd in "${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd" "/etc/containers/systemd"; do
      [[ -d "$qd" ]] || continue
      for qf in "$qd"/*.container "$qd"/*.pod "$qd"/*.volume "$qd"/*.network "$qd"/*.kube "$qd"/*.image "$qd"/*.build "$qd"/*.artifact; do
        [[ -e "$qf" ]] && quad_cnt=$((quad_cnt + 1))
      done
    done
    echo "  * Quadlet Units Discovered: $quad_cnt"
    ;;
  lazydocker)
    echo "Active Lazydocker & Socket Status:"
    for ldf in "${XDG_CONFIG_HOME:-$HOME/.config}/lazydocker/config.yml" "$roaming_app_data/lazydocker/config.yml"; do
      [[ -r "$ldf" && -f "$ldf" ]] || continue
      echo "  * Inspecting $ldf:"
      grep -E '^[[:space:]]*(dockerCompose|containerStatusHealthStyle|reporting)[[:space:]]*:' "$ldf" 2>/dev/null | sed 's/^/    /' || true
      if grep -qE '^[[:space:]]*optionsColor:' "$ldf" 2>/dev/null; then
        echo "  * [DEPRECATED] optionsColor in $ldf (use gui.theme.optionsTextColor)"
      fi
    done
    if ! is_windows; then
      echo "  * User podman.socket: $(first_line_or inactive systemctl --user is-active podman.socket)"
      echo "  * DOCKER_HOST: $(env_show DOCKER_HOST)"
    fi
    ;;
  docker)
    if [[ -f /etc/containers/nodocker ]] || "$bin_path" --version 2>/dev/null | grep -qi "podman"; then
      echo "  * Wrapper: [NOTE] docker CLI is backed by podman-docker compatibility wrapper"
    fi
    if [[ -f "$HOME/.docker/config.json" ]]; then
      if grep -q '"auths"' "$HOME/.docker/config.json" 2>/dev/null && ! grep -qE '"credsStore"[[:space:]]*:[[:space:]]*"[^"]+"' "$HOME/.docker/config.json" 2>/dev/null; then
        if grep -A 5 '"auths"' "$HOME/.docker/config.json" 2>/dev/null | grep -q '"auth"'; then
          echo "  * Docker Credentials ($HOME/.docker/config.json): [WARNING] base64 auth token stored without credsStore"
        else
          echo "  * Docker Credentials ($HOME/.docker/config.json): [OK]"
        fi
      else
        echo "  * Docker Credentials ($HOME/.docker/config.json): [OK]"
      fi
    fi
    for djson in "${XDG_CONFIG_HOME:-$HOME/.config}/docker/daemon.json" "/etc/docker/daemon.json"; do
      if [[ -r "$djson" ]]; then
        echo "  * Daemon Config ($djson): readable"
        grep -E '"(log-driver|max-size|live-restore|userns-remap)"' "$djson" 2>/dev/null | sed 's/^[[:space:]]*/    /' || true
      fi
    done
    ;;
  syncthing)
    st_cfg="${st_cli_cfg:-}"
    for sc in "${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml" "${XDG_CONFIG_HOME:-$HOME/.config}/syncthing/config.xml" "$local_app_data/Syncthing/config.xml"; do
      [[ -z "$st_cfg" && -f "$sc" ]] && st_cfg="$sc" && break
    done
    if [[ -n "$st_cfg" && -r "$st_cfg" ]]; then
      echo "Active Syncthing GUI & Relay Settings ($st_cfg):"
      st_gui_blk=$(awk '/<gui[ >]/,/<\/gui>/' "$st_cfg" 2>/dev/null || true)
      st_gui_addr=$(printf '%s\n' "$st_gui_blk" | grep -oE '<address>[^<]+</address>' | head -n 1 | sed -E 's/<\/?address>//g' || true)
      st_gui_tls=$(printf '%s\n' "$st_gui_blk" | grep -oE 'tls="(true|false)"' | head -n 1 | cut -d'"' -f2 || true)
      st_gui_user=$(printf '%s\n' "$st_gui_blk" | grep -oE '<user>[^<]*</user>' | head -n 1 | sed -E 's/<\/?user>//g' || true)
      st_relays=$(grep -oE '<relaysEnabled>[^<]+</relaysEnabled>' "$st_cfg" 2>/dev/null | head -n 1 | sed -E 's/<\/?relaysEnabled>//g' || true)
      echo "  * GUI Listen Address: ${st_gui_addr:-unknown} (tls=${st_gui_tls:-false}, user=${st_gui_user:-[NONE]})"
      echo "  * Relays Enabled: ${st_relays:-default (true)}"
      if [[ -n "$st_gui_addr" && "$st_gui_addr" != 127.0.0.1:* && "$st_gui_addr" != "[::1]:"* ]] && [[ "$st_gui_tls" != "true" || -z "$st_gui_user" ]]; then
        echo "  * [SECURITY WARNING] Syncthing GUI listens beyond loopback ($st_gui_addr) without both TLS and authentication user"
      fi
    fi
    st_db="${st_cli_db:-$(dirname "${st_cfg:-${XDG_STATE_HOME:-$HOME/.local/state}/syncthing/config.xml}")}"
    if [[ -d "$st_db/index-v2" ]]; then
      echo "  * Database Engine: SQLite v2 ($st_db/index-v2)"
    fi
    if [[ -d "$st_db/index-v0.14.0.db" ]]; then
      echo "  * [NOTE] Leftover v1 LevelDB index ($st_db/index-v0.14.0.db) found — safe to remove after verifying v2 SQLite index-v2/ migration"
    fi
    if ! is_windows; then
      echo "  * User Service (syncthing.service): $(first_line_or inactive systemctl --user is-active syncthing.service)"
    fi
    ;;
  btop|htop|btop4win)
    echo "Active System Monitor Parameters:"
    for bf in "${XDG_CONFIG_HOME:-$HOME/.config}/btop/btop.conf" "$local_app_data/btop/btop.conf"; do
      if [[ -r "$bf" ]]; then
        echo "  * btop ($bf):"
        grep -E '^[[:space:]]*(update_ms|proc_tree|shown_boxes|color_theme)[[:space:]]*=' "$bf" 2>/dev/null | sed 's/^/    /' || true
      fi
    done
    hf="${XDG_CONFIG_HOME:-$HOME/.config}/htop/htoprc"
    if [[ -r "$hf" ]]; then
      echo "  * htop ($hf) (note: close htop before editing htoprc as htop overwrites it on exit):"
      grep -E '^(delay|show_cpu_frequency|show_cpu_temperature|hide_userland_threads|tree_view)=' "$hf" 2>/dev/null | sed 's/^/    /' || true
    fi
    ;;
esac

# Tool Security & Hardening Check
echo "Recommendations (advice only; the findings are the tagged lines and quoted file lines above):"
case "$target" in
  pacman|yay|paru|makepkg|paccache|pacman-contrib)
    echo "  * Performance: Set ParallelDownloads = 5 in /etc/pacman.conf; set MAKEFLAGS=\"-j${detected_threads}\" and '!debug' in /etc/makepkg.conf (plus /etc/makepkg.conf.d/rust.conf); COMPRESSZST already uses zstd -T0"
    echo "  * Configuration: Enable Color, ILoveCandy, VerbosePkgLists; configure /etc/conf.d/pacman-contrib + paccache.timer; set yay cleanAfter = true"
    echo "  * Security: Keep DownloadUser = alpm and avoid DisableSandbox*; enforce SigLevel = Required DatabaseOptional (never Never/TrustAll); avoid yay sudoloop = true; audit PKGBUILDs"
    ;;
  kde|kde-plasma)
    echo "  * Performance: Reduce or disable AnimationDurationFactor on low-power iGPUs; disable Baloo file indexing when using ripgrep/fd"
    echo "  * Configuration: Wayland session with adaptive TearFree compositing; consistent dark color scheme"
    echo "  * Security: KScreenLocker lock-on-resume enabled; restrict KWallet and ~/.config permissions"
    ;;
  flatpak)
    echo "  * Performance: Prune unused runtimes (flatpak uninstall --unused); share host GPU/VA-API extensions"
    echo "  * Configuration: Prefer --user Flathub installations for rootless updates integrated with topgrade"
    echo "  * Security: Avoid global or per-app filesystem=host/home overrides across ~/.local/share/flatpak/overrides and /var/lib/flatpak/overrides; grant narrow XDG portal paths"
    ;;
  podman)
    echo "  * Performance: Use crun lightweight OCI runtime + pasta rootless networking (never removed slirp4netns), bound log_size_max (10MB), native overlayfs storage driver"
    echo "  * Configuration: Manage rootless services as systemd Quadlets (~/.config/containers/systemd/) instead of deprecated 'podman generate systemd'; prune dangling images periodically"
    echo "  * Security: Rootless container execution, enforce pids_limit (2048), restrict containers.conf permissions to 0600"
    ;;
  lazydocker)
    echo "  * Performance: Pair with rootless podman.socket (DOCKER_HOST=unix://\$XDG_RUNTIME_DIR/podman/podman.sock) to inspect containers without a heavy daemon"
    echo "  * Configuration: Set commandTemplates.dockerCompose: 'podman compose' when using Podman; use gui.theme.optionsTextColor (not deprecated optionsColor)"
    echo "  * Security: Restrict ~/.config/lazydocker/config.yml permissions to 0600; audit custom commands"
    ;;
  docker)
    echo "  * Performance: Bound container json-file logs (max-size 10m, max-file 3); prune unused build cache and images (docker system prune)"
    echo "  * Configuration: Pair with lazydocker TUI; use rootless ~/.config/docker/daemon.json on Linux or bound WSL2 backend RAM on Windows"
    echo "  * Security: Prefer rootless mode or userns-remap; store registry tokens in OS keychain via credsStore; avoid mounting docker.sock into untrusted containers"
    ;;
  fd|fdfind)
    echo "  * Performance: fd automatically scales worker threads to logical CPUs; exclude heavy build/cache trees (.git, node_modules, target, .venv)"
    echo "  * Configuration: Maintain shared ignore patterns in ~/.config/fd/ignore paired with ripgrep and fzf"
    echo "  * Security: Enforce 0600 on ~/.config/fd/ignore"
    ;;
  btop|htop|btop4win)
    inferred_thm=$(infer_theme)
    thm_rec="unify theme (or ask user)"
    [[ -n "$inferred_thm" ]] && thm_rec="unify theme (inferred: $inferred_thm)"
    echo "  * Performance: Set update_ms = 2000 (btop) / delay = 20 (htop = 2.0s) to minimize monitor CPU overhead"
    echo "  * Configuration: Show CPU frequency/temperature, per-core graphs, and zram/swap usage; $thm_rec; close htop before editing htoprc"
    echo "  * Security: Run unprivileged without CAP_SYS_PTRACE/sudo unless inspecting root processes; enforce 0600 on config"
    ;;
  syncthing)
    echo "  * Performance: Bound maxFolderConcurrency and hashing threads to host CPU/RAM tier; verify v2 SQLite index-v2/ migration and disable NAT/global discovery when LAN-only"
    echo "  * Configuration: Enable local discovery and fsWatcherEnabled=true; run via 'syncthing serve' / systemctl --user enable --now syncthing.service"
    echo "  * Security: Bind GUI strictly to 127.0.0.1:8384 with TLS + bcrypt authentication; enforce 0600 on config.xml"
    ;;
  sqlite3)
    echo "  * Performance: Keep WAL/synchronous pragmas per-DB rather than global ~/.sqliterc; use .output /dev/null + PRAGMA temp_store = MEMORY; + PRAGMA busy_timeout = 5000; + .output stdout"
    echo "  * Configuration: Set PRAGMA foreign_keys = ON;, .headers on, and .mode box in ~/.sqliterc for readable interactive queries"
    echo "  * Security: Enforce 0600 on ~/.sqliterc; avoid loading untrusted SQLite extensions"
    ;;
  uv)
    echo "  * Performance: Enable compile-bytecode = true (UV_COMPILE_BYTECODE=1) and link-mode = 'hardlink' (or 'copy' across filesystems); periodically prune cache (uv cache prune)"
    echo "  * Configuration: Manage settings in ~/.config/uv/uv.toml; install CLI tools via 'uv tool install'; disable 'uv' in topgrade.toml when managed by mise"
    echo "  * Security: Configure exclude-newer cooldown in uv.toml for supply-chain protection; run 'uv audit' and commit uv.lock"
    ;;
  python|python3)
    echo "  * Performance: Prefer uv for fast dependency resolution and bytecode compilation; evaluate Python 3.15+ '-X lazy_imports' (PYTHON_LAZY_IMPORTS=1) and free-threaded/JIT builds where supported"
    echo "  * Configuration: Isolate project dependencies per virtualenv/uv environment; set PIP_REQUIRE_VIRTUALENV=true (or pip.conf require-virtualenv = true) when EXTERNALLY-MANAGED is absent"
    echo "  * Security: Respect EXTERNALLY-MANAGED protection; set PYTHONSAFEPATH=1; keep PYTHON_HISTORY at 0600; pin dependencies with hashes in lockfiles"
    ;;
  *)
    echo "  * Security: Least privilege, minimal network exposure, file permissions"
    echo "  * Performance: Concurrency aligned with CPU threads (nproc) and host RAM tier"
    echo "  * Configuration: Ergonomic defaults, integration with system environment"
    ;;
esac

echo "====================================="
