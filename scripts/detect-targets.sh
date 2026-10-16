#!/usr/bin/env bash
# detect-targets.sh - Distro & OS agnostic detection of system domains, tools, and packages (Windows & Linux)
set -euo pipefail

LIB="$(dirname "${BASH_SOURCE[0]}")/lib.sh"
if [[ ! -f "$LIB" ]]; then
  echo "Error: $LIB not found; copy the whole skill folder, not a single script." >&2
  exit 1
fi
# shellcheck source=lib.sh
source "$LIB"

output_json=false
if [[ "${1:-}" == "--json" ]]; then
  output_json=true
fi

local_app_data="${LOCALAPPDATA:-$HOME/AppData/Local}"
roaming_app_data="${APPDATA:-$HOME/AppData/Roaming}"

if is_windows; then
  # 1. Available Package Managers on Windows
  available_pms=()
  for pm in winget scoop choco cargo mise pip pipx npm bun uv; do
    if command -v "$pm" >/dev/null 2>&1; then
      available_pms+=("$pm")
    fi
  done

  # 2. System Core Domains on Windows
  system_domains=("storage" "memory" "cpu" "boot" "network")

  # 3. Security Domains on Windows
  security_domains=("firewall" "defender" "ssh" "execution-policy" "uac")

  # 4. Web Browsers & Terminal / Desktop on Windows
  browser_desktop_candidates=(
    "windows-terminal" "wt" "brave" "chrome" "edge" "firefox" "librewolf"
  )

  # 5. Package Managers & Runtimes on Windows
  package_runtime_candidates=(
    "winget" "scoop" "choco" "wsl" "docker" "cargo" "mise" "bun" "node" "python"
  )

  # 6. Developer Tools & CLI Utilities on Windows
  dev_cli_candidates=(
    "pwsh" "powershell" "windows-terminal" "wsl" "powertoys" "pi" "bash" "topgrade" "git"
    "neovim" "nvim" "starship" "bat" "fzf" "ripgrep" "rg" "fd" "eza" "lsd" "lazygit"
    "ffmpeg" "mpv" "yt-dlp" "syncthing" "rustdesk" "controld" "ctrld" "zoxide" "sqlite3" "herdr" "gh"
  )
else
  # Linux Package Managers
  available_pms=()
  for pm in pacman yay paru apt dnf zypper apk flatpak snap nix brew cargo pipx mise asdf; do
    if command -v "$pm" >/dev/null 2>&1; then
      available_pms+=("$pm")
    fi
  done

  # Linux System Domains
  system_domains=("kernel" "storage" "memory" "cpu" "boot" "network")

  # Linux Security Domains
  security_domains=("firewall" "ssh" "sysctl-security" "sandboxing" "package-audit")

  # Linux Browsers & Desktop
  browser_desktop_candidates=(
    "brave" "brave-bin" "librewolf" "firefox" "chromium" "falkon" "google-chrome-stable"
    "plasmashell" "kwin_wayland" "kwin_x11" "dolphin" "kate" "konsole"
  )

  # Linux Package Managers & Runtimes
  package_runtime_candidates=(
    "pacman" "yay" "paru" "makepkg" "flatpak" "cargo" "podman" "docker" "mise"
  )

  # Linux Developer Tools & CLI Utilities
  dev_cli_candidates=(
    "pi" "bash" "topgrade" "git" "neovim" "nvim" "starship" "bat" "fzf" "ripgrep" "rg" "fd"
    "eza" "lsd" "yazi" "ranger" "broot" "delta" "lazygit" "lazydocker"
    "ffmpeg" "mpv" "yt-dlp" "btop" "htop" "syncthing" "sqlite3" "zstd" "pigz"
    "rustdesk" "controld" "ctrld" "herdr" "gh"
  )
fi

# Canonical mapping helper
canonical_name() {
  local t="$1"
  case "$t" in
    wt) echo "windows-terminal" ;;
    nvim) echo "neovim" ;;
    rg) echo "ripgrep" ;;
    ctrld) echo "controld" ;;
    brave-bin) echo "brave" ;;
    google-chrome-stable) echo "chrome" ;;
    plasmashell|kwin_wayland|kwin_x11) echo "kde-plasma" ;;
    mise-en-place|rtx) echo "mise" ;;
    github-cli|gh) echo "gh" ;;
    *) echo "$t" ;;
  esac
}

# Helper to test presence of target
is_target_present() {
  local t="$1"
  if command -v "$t" >/dev/null 2>&1; then
    case "$t" in
      python|python3) python_ok "$t" || return 1 ;;
    esac
    return 0
  fi
  if is_windows; then
    case "$t" in
      windows-terminal|wt)
        if command -v wt >/dev/null 2>&1; then
          return 0
        fi
        if [[ -d "$local_app_data/Packages" ]]; then
          # subshell keeps nocaseglob/nullglob from leaking into the rest of the script
          ( shopt -s nocaseglob nullglob; set -- "$local_app_data/Packages/"*WindowsTerminal*; [[ $# -gt 0 ]] ) && return 0
        fi
        ;;
      brave)
        [[ -d "$local_app_data/BraveSoftware" ]] && return 0
        ;;
      chrome)
        [[ -d "$local_app_data/Google/Chrome" ]] && return 0
        ;;
      edge)
        [[ -d "$local_app_data/Microsoft/Edge" ]] && return 0
        ;;
      firefox)
        [[ -d "$roaming_app_data/Mozilla/Firefox" ]] && return 0
        ;;
      powertoys)
        [[ -d "$local_app_data/Microsoft/PowerToys" || -d "/c/Program Files/PowerToys" ]] && return 0
        ;;
      herdr)
        [[ -d "$roaming_app_data/herdr" || -d "$HOME/.herdr" ]] && return 0
        ;;
      wsl)
        command -v wsl.exe >/dev/null 2>&1 && return 0
        ;;
      mise|rtx)
        [[ -x "$local_app_data/bin/mise.exe" || -x "$HOME/.local/bin/mise.exe" || -d "$local_app_data/mise" ]] && return 0
        ;;
    esac
  fi
  return 1
}

# Detect installed browsers & desktop
detected_browsers_desktop=()
for item in "${browser_desktop_candidates[@]}"; do
  if is_target_present "$item"; then
    canon=$(canonical_name "$item")
    if [[ " ${detected_browsers_desktop[*]:-} " != *" ${canon} "* ]]; then
      detected_browsers_desktop+=("$canon")
    fi
  fi
done

# Detect installed package managers & runtimes
detected_pms_runtimes=()
for item in "${package_runtime_candidates[@]}"; do
  if is_target_present "$item"; then
    canon=$(canonical_name "$item")
    if [[ " ${detected_pms_runtimes[*]:-} " != *" ${canon} "* ]]; then
      detected_pms_runtimes+=("$canon")
    fi
  fi
done

# Detect installed dev & cli tools
detected_dev_cli=()
for item in "${dev_cli_candidates[@]}"; do
  if is_target_present "$item"; then
    canon=$(canonical_name "$item")
    if [[ " ${detected_dev_cli[*]:-} " != *" ${canon} "* ]]; then
      detected_dev_cli+=("$canon")
    fi
  fi
done

# Top balanced picks
if is_windows; then
  balanced_top=("storage" "defender")
  [[ " ${available_pms[*]:-} " =~ " winget " ]] && balanced_top+=("winget")
  [[ " ${detected_browsers_desktop[*]:-} " =~ " windows-terminal " ]] && balanced_top+=("windows-terminal")
  [[ " ${detected_dev_cli[*]:-} " =~ " pwsh " ]] && balanced_top+=("pwsh")
  [[ " ${detected_pms_runtimes[*]:-} " =~ " wsl " ]] && balanced_top+=("wsl")
  [[ " ${detected_dev_cli[*]:-} " =~ " git " ]] && balanced_top+=("git")
  [[ " ${detected_dev_cli[*]:-} " =~ " topgrade " ]] && balanced_top+=("topgrade")
  [[ " ${detected_pms_runtimes[*]:-} " =~ " mise " ]] && balanced_top+=("mise")
  [[ " ${detected_dev_cli[*]:-} " =~ " mpv " ]] && balanced_top+=("mpv")
else
  balanced_top=("kernel" "security" "topgrade")
  [[ " ${detected_pms_runtimes[*]:-} " =~ " mise " ]] && balanced_top+=("mise")
  [[ " ${detected_pms_runtimes[*]:-} " =~ " pacman " ]] && balanced_top+=("pacman")
  [[ " ${detected_dev_cli[*]:-} " =~ " git " ]] && balanced_top+=("git")
  [[ " ${detected_dev_cli[*]:-} " =~ " ripgrep " ]] && balanced_top+=("ripgrep")
  [[ " ${detected_dev_cli[*]:-} " =~ " starship " ]] && balanced_top+=("starship")
  if [[ " ${detected_browsers_desktop[*]:-} " =~ " brave " ]]; then
    balanced_top+=("brave")
  elif [[ " ${detected_browsers_desktop[*]:-} " =~ " librewolf " ]]; then
    balanced_top+=("librewolf")
  fi
fi

# Build complete queue for Full System Optimization (Option 7)
full_targets=()
for t in "${system_domains[@]}" "${security_domains[@]}" "${detected_pms_runtimes[@]}" "${detected_browsers_desktop[@]}" "${detected_dev_cli[@]}"; do
  if [[ " ${full_targets[*]:-} " != *" ${t} "* ]]; then
    full_targets+=("$t")
  fi
done

if [[ "$output_json" == true ]]; then
  cat <<EOF
{
  "active_package_managers": $(to_json_arr "${available_pms[@]}"),
  "system_domains": $(to_json_arr "${system_domains[@]}"),
  "security_domains": $(to_json_arr "${security_domains[@]}"),
  "package_managers_runtimes": $(to_json_arr "${detected_pms_runtimes[@]}"),
  "browsers_and_desktop": $(to_json_arr "${detected_browsers_desktop[@]}"),
  "developer_and_cli_tools": $(to_json_arr "${detected_dev_cli[@]}"),
  "balanced_top": $(to_json_arr "${balanced_top[@]}"),
  "full_targets": $(to_json_arr "${full_targets[@]}")
}
EOF
else
  echo "=== System & Tool Optimizer Target Discovery ($(if is_windows; then echo "Windows"; else echo "Linux"; fi)) ==="
  echo "Active Package Managers: ${available_pms[*]:-None}"
  echo ""
  if is_windows; then
    echo "1. System Core & OS Performance (Storage/NTFS TRIM, Memory Compression, CPU Power Scheme, Boot/Startup, Network):"
    echo "   - ${system_domains[*]}"
    echo ""
    echo "2. System Security Hardening & Posture (Defender Firewall, Antivirus/ASR, SSH, Execution Policy, UAC):"
    echo "   - ${security_domains[*]}"
  else
    echo "1. System Core & OS Performance (Kernel, Storage/SSD, Memory/zram, CPU Governor, Boot):"
    echo "   - ${system_domains[*]}"
    echo ""
    echo "2. System Security Hardening & Posture (Firewall, SSH, Sysctl Security, Sandboxing, Audit):"
    echo "   - ${security_domains[*]}"
  fi
  echo ""
  echo "3. Package Managers & Runtimes (${#detected_pms_runtimes[@]} detected):"
  echo "   - ${detected_pms_runtimes[*]:-None}"
  echo ""
  echo "4. Web Browsers & Terminal / Desktop (${#detected_browsers_desktop[@]} detected):"
  echo "   - ${detected_browsers_desktop[*]:-None}"
  echo ""
  echo "5. Developer & CLI Tools (${#detected_dev_cli[@]} detected):"
  echo "   - ${detected_dev_cli[*]:-None}"
  echo ""
  echo "6. Curated Top Balanced Recommendations (High-impact System + Security + Tools):"
  echo "   - ${balanced_top[*]}"
  echo ""
  echo "7. Full System Optimization (${#full_targets[@]} targets queued across all categories):"
  echo "   - System Core: ${system_domains[*]}"
  echo "   - Security Posture: ${security_domains[*]}"
  echo "   - Package Managers: ${detected_pms_runtimes[*]:-None}"
  echo "   - Terminal & Browsers: ${detected_browsers_desktop[*]:-None}"
  echo "   - Developer & Media Tools: ${detected_dev_cli[*]:-None}"
  echo ""
  echo "8. Custom Selection (Specify target domains or tool names)"
  echo "9. None / Cancel"
  echo "================================================="
fi
