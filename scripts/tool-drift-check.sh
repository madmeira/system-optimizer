#!/usr/bin/env bash
# tool-drift-check.sh - Dynamic offline version, CLI/schema, and deprecated-config drift probe
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

JSON_MODE=false
POSITIONAL=()

usage() {
  cat <<'EOF'
Usage: tool-drift-check.sh [--json] [--help] [target ...]

Dynamic offline probe for upstream CLI/schema drift and deprecated user config settings.
Exits 0 on normal completion (read-only diagnostic probe) and 2 on invalid options.

Examples:
  tool-drift-check.sh
  tool-drift-check.sh --json
  tool-drift-check.sh mise rg neovim
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      JSON_MODE=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL+=("$1")
        shift
      done
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

HAS_TIMEOUT=false
command -v timeout >/dev/null 2>&1 && HAS_TIMEOUT=true

run_bounded() {
  if [[ "$HAS_TIMEOUT" == true ]]; then
    timeout 5 "$@" </dev/null
  else
    "$@" </dev/null
  fi
}

clean_output() {
  sed $'s/\033\\[[0-9;]*[a-zA-Z]//g' | tr -d '\r'
}

extract_first_semver_str() {
  local s="$1"
  if [[ "$s" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

resolve_alias() {
  case "$1" in
    rg) echo "ripgrep" ;;
    nvim) echo "neovim" ;;
    ctrld) echo "controld" ;;
    python3|py) echo "python" ;;
    yt_dlp|ytdlp) echo "yt-dlp" ;;
    sqlite) echo "sqlite3" ;;
    fdfind) echo "fd" ;;
    batcat) echo "bat" ;;
    paru) echo "yay" ;;
    powershell) echo "pwsh" ;;
    pacman-contrib) echo "paccache" ;;
    btop4win) echo "btop" ;;
    agy|antigravity-cli|antigravity-ide) echo "antigravity" ;;
    chromium|google-chrome|google-chrome-stable) echo "chrome" ;;
    msedge|microsoft-edge) echo "edge" ;;
    brave-browser|brave-bin) echo "brave" ;;
    ffprobe) echo "ffmpeg" ;;
    *) echo "$1" ;;
  esac
}

is_non_cli_target() {
  case "$1" in
    system|security|full|kernel|sysctl|sysctl-security|storage|disk|filesystem|memory|swap|zram|cpu|governor|power|boot|systemd|startup|firewall|ufw|nftables|firewalld|defender|ssh|sshd|execution-policy|uac|network|net|sandboxing|systemd-security|package-audit|pkg-audit|supply-chain|bash|windows-terminal|wt|makepkg|kde|kde-plasma|baloo|winget|powertoys|chrome|edge|brave|firefox|librewolf|falkon|dolphin|kate|konsole)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

get_verified_baseline() {
  case "$1" in
    mise) echo "2026.11" ;;
    pi) echo "1.5" ;;
    antigravity) echo "1.5" ;;
    topgrade) echo "17.16" ;;
    neovim) echo "0.12" ;;
    herdr) echo "0.9" ;;
    lazygit) echo "0.66" ;;
    fzf) echo "0.75" ;;
    cargo) echo "1.100" ;;
    python) echo "3.15" ;;
    uv) echo "0.13" ;;
    git) echo "2.56" ;;
    gh) echo "2.104" ;;
    starship) echo "1.27" ;;
    zoxide) echo "0.10" ;;
    ripgrep) echo "15.2" ;;
    fd) echo "10.5" ;;
    eza) echo "0.23" ;;
    bat) echo "0.26" ;;
    mpv) echo "0.42" ;;
    ffmpeg) echo "9.0" ;;
    zstd) echo "1.5" ;;
    yt-dlp) echo "2026.10" ;;
    syncthing) echo "2.1" ;;
    podman) echo "6.2" ;;
    docker) echo "28.0" ;;
    lazydocker) echo "0.25" ;;
    flatpak) echo "1.18" ;;
    pacman) echo "7.1" ;;
    yay) echo "13.1" ;;
    paccache) echo "1.13" ;;
    btop) echo "1.4" ;;
    htop) echo "3.5" ;;
    sqlite3) echo "3.54" ;;
    rustdesk) echo "1.5" ;;
    controld) echo "1.5" ;;
    pwsh) echo "7.6" ;;
    wsl) echo "2.6" ;;
    *) echo "" ;;
  esac
}

# Compare major.minor of installed version against baseline; echoes true if ahead, false otherwise
is_version_ahead() {
  local installed="$1"
  local baseline="$2"
  [[ -z "$installed" || -z "$baseline" ]] && { echo "false"; return; }

  local inst_maj inst_min base_maj base_min
  inst_maj=$(echo "$installed" | cut -d. -f1 | tr -cd '0-9')
  inst_min=$(echo "$installed" | cut -d. -f2 | tr -cd '0-9')
  base_maj=$(echo "$baseline" | cut -d. -f1 | tr -cd '0-9')
  base_min=$(echo "$baseline" | cut -d. -f2 | tr -cd '0-9')

  inst_maj="${inst_maj:-0}"
  inst_min="${inst_min:-0}"
  base_maj="${base_maj:-0}"
  base_min="${base_min:-0}"

  if (( 10#$inst_maj > 10#$base_maj )); then
    echo "true"
  elif (( 10#$inst_maj == 10#$base_maj && 10#$inst_min > 10#$base_min )); then
    echo "true"
  else
    echo "false"
  fi
}

resolve_realpath() {
  local p="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$p" 2>/dev/null || echo "$p"
  elif command -v readlink >/dev/null 2>&1; then
    readlink -f "$p" 2>/dev/null || echo "$p"
  else
    echo "$p"
  fi
}

find_windows_appdata() {
  local kind="$1" # Roaming or Local
  local sub="$2"
  local candidates=()
  if [[ "$kind" == "Roaming" && -n "${APPDATA:-}" ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      candidates+=("$(cygpath -u "$APPDATA" 2>/dev/null)/$sub")
    else
      candidates+=("$APPDATA/$sub")
    fi
  elif [[ "$kind" == "Local" && -n "${LOCALAPPDATA:-}" ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      candidates+=("$(cygpath -u "$LOCALAPPDATA" 2>/dev/null)/$sub")
    else
      candidates+=("$LOCALAPPDATA/$sub")
    fi
  fi
  candidates+=("$HOME/AppData/$kind/$sub")
  local c
  for c in "${candidates[@]}"; do
    [[ -e "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

find_wslconfig() {
  local candidates=("$HOME/.wslconfig")
  if [[ -n "${USERPROFILE:-}" ]]; then
    if command -v cygpath >/dev/null 2>&1; then
      candidates+=("$(cygpath -u "$USERPROFILE" 2>/dev/null)/.wslconfig")
    fi
    candidates+=("$USERPROFILE/.wslconfig")
  fi
  local c
  for c in "${candidates[@]}"; do
    [[ -f "$c" ]] && { echo "$c"; return 0; }
  done
  return 1
}

# SIGPIPE-safe uncommented regex search on a single file (no grep|grep pipeline).
uncommented_match() {
  local file="$1" pat="$2" comment_re="${3:-^[[:space:]]*#}"
  [[ -r "$file" ]] || return 1
  awk -v c="$comment_re" -v p="$pat" '$0 !~ c && $0 ~ p { found=1; exit } END { exit !found }' "$file" 2>/dev/null
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
probe_target() {
  local target="$1"
  local out_dir="$2"
  local xdg_cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
  local xdg_state="${XDG_STATE_HOME:-$HOME/.local/state}"
  local xdg_data="${XDG_DATA_HOME:-$HOME/.local/share}"

  local baseline installed="false" version="" schema_ok="true" version_ahead="false"
  local schema_drift=false deprecated_cfg=false
  local findings=()

  baseline="$(get_verified_baseline "$target")"
  if [[ -z "$baseline" ]]; then
    printf 'not_installed\n' > "$out_dir/status"
    printf 'false\n' > "$out_dir/installed"
    printf '\n' > "$out_dir/version"
    printf '\n' > "$out_dir/baseline"
    printf 'false\n' > "$out_dir/schema_ok"
    printf 'Unrecognized target: %s\n' "$target" > "$out_dir/findings"
    return 0
  fi

  local bin="" raw_ver=""
  case "$target" in
    mise) bin="$(command -v mise 2>/dev/null || true)" ;;
    pi) bin="$(command -v pi 2>/dev/null || true)" ;;
    antigravity)
      bin="$(command -v agy 2>/dev/null || command -v antigravity 2>/dev/null || true)"
      [[ -z "$bin" && -x "$HOME/.local/bin/agy" ]] && bin="$HOME/.local/bin/agy"
      ;;
    topgrade) bin="$(command -v topgrade 2>/dev/null || true)" ;;
    neovim) bin="$(command -v nvim 2>/dev/null || true)" ;;
    herdr) bin="$(command -v herdr 2>/dev/null || true)" ;;
    lazygit) bin="$(command -v lazygit 2>/dev/null || true)" ;;
    fzf) bin="$(command -v fzf 2>/dev/null || true)" ;;
    cargo) bin="$(command -v cargo 2>/dev/null || true)" ;;
    python)
      for py_cand in python3 python; do
        if command -v "$py_cand" >/dev/null 2>&1; then
          raw_ver=$(run_bounded "$py_cand" --version 2>&1 || true)
          raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
          if [[ "$raw_ver" =~ Python[[:space:]]+([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
            bin="$py_cand"
            version="${BASH_REMATCH[1]}"
            break
          fi
        fi
      done
      ;;
    uv) bin="$(command -v uv 2>/dev/null || true)" ;;
    git) bin="$(command -v git 2>/dev/null || true)" ;;
    gh) bin="$(command -v gh 2>/dev/null || true)" ;;
    starship) bin="$(command -v starship 2>/dev/null || true)" ;;
    zoxide) bin="$(command -v zoxide 2>/dev/null || true)" ;;
    ripgrep) bin="$(command -v rg 2>/dev/null || true)" ;;
    fd) bin="$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)" ;;
    eza) bin="$(command -v eza 2>/dev/null || true)" ;;
    bat) bin="$(command -v bat 2>/dev/null || command -v batcat 2>/dev/null || true)" ;;
    mpv) bin="$(command -v mpv 2>/dev/null || true)" ;;
    ffmpeg) bin="$(command -v ffmpeg 2>/dev/null || true)" ;;
    zstd) bin="$(command -v zstd 2>/dev/null || true)" ;;
    yt-dlp) bin="$(command -v yt-dlp 2>/dev/null || true)" ;;
    syncthing) bin="$(command -v syncthing 2>/dev/null || true)" ;;
    podman) bin="$(command -v podman 2>/dev/null || true)" ;;
    docker) bin="$(command -v docker 2>/dev/null || true)" ;;
    lazydocker) bin="$(command -v lazydocker 2>/dev/null || true)" ;;
    flatpak) bin="$(command -v flatpak 2>/dev/null || true)" ;;
    pacman) bin="$(command -v pacman 2>/dev/null || true)" ;;
    yay) bin="$(command -v yay 2>/dev/null || command -v paru 2>/dev/null || true)" ;;
    paccache) bin="$(command -v paccache 2>/dev/null || true)" ;;
    btop) bin="$(command -v btop 2>/dev/null || command -v btop4win 2>/dev/null || true)" ;;
    htop) bin="$(command -v htop 2>/dev/null || true)" ;;
    sqlite3) bin="$(command -v sqlite3 2>/dev/null || true)" ;;
    rustdesk) bin="$(command -v rustdesk 2>/dev/null || true)" ;;
    controld) bin="$(command -v ctrld 2>/dev/null || true)" ;;
    pwsh) bin="$(command -v pwsh 2>/dev/null || true)" ;;
    wsl) bin="$(command -v wsl.exe 2>/dev/null || command -v wsl 2>/dev/null || true)" ;;
  esac

  if [[ -n "$bin" ]]; then
    installed="true"
  fi

  # 1. Safe Version Extraction
  if [[ "$installed" == "true" && -z "$version" ]]; then
    case "$target" in
      pi)
        local pi_real pi_dir pkg_json
        pi_real="$(resolve_realpath "$bin")"
        pi_dir="$(dirname "$pi_real")"
        for pkg_json in "$pi_dir/package.json" "$pi_dir/../package.json"; do
          if [[ -r "$pkg_json" ]]; then
            raw_ver=$(grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+(\.[0-9]+)?' "$pkg_json" 2>/dev/null || true)
            version=$(extract_first_semver_str "$raw_ver")
            [[ -n "$version" ]] && break
          fi
        done
        if [[ -z "$version" ]]; then
          raw_ver=$(run_bounded "$bin" --version 2>&1 || true)
          raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
          version=$(extract_first_semver_str "$raw_ver")
        fi
        ;;
      lazygit)
        raw_ver=$(run_bounded "$bin" --version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
        if [[ "$raw_ver" =~ version=([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
          version="${BASH_REMATCH[1]}"
        else
          version=$(extract_first_semver_str "$raw_ver")
        fi
        ;;
      mpv)
        raw_ver=$(run_bounded "$bin" --no-config --version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
        version=$(extract_first_semver_str "$raw_ver")
        ;;
      ffmpeg)
        # ffmpeg only accepts the single-dash -version; release builds print "n9.0.2" or "9.0.2"
        raw_ver=$(run_bounded "$bin" -hide_banner -version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output | head -n 1 || true)
        version=$(extract_first_semver_str "$raw_ver")
        ;;
      yt-dlp)
        raw_ver=$(run_bounded "$bin" --ignore-config --version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
        version=$(extract_first_semver_str "$raw_ver")
        ;;
      sqlite3)
        raw_ver=$(run_bounded "$bin" -batch -init /dev/null --version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
        version=$(extract_first_semver_str "$raw_ver")
        ;;
      controld)
        raw_ver=$(run_bounded "$bin" --version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
        version=$(extract_first_semver_str "$raw_ver")
        ;;
      wsl)
        local wsl_rc=0
        raw_ver=$(run_bounded "$bin" --version 2>/dev/null) || wsl_rc=$?
        raw_ver=$(printf '%s' "$raw_ver" | tr -d '\0\r')
        if [[ "$wsl_rc" -ne 0 || -z "$raw_ver" || "$raw_ver" == *"wsl.exe"* ]]; then
          installed="false"
        else
          version=$(extract_first_semver_str "$raw_ver")
          [[ -z "$version" ]] && installed="false"
        fi
        ;;
      *)
        raw_ver=$(run_bounded "$bin" --version 2>&1 || true)
        raw_ver=$(printf '%s' "$raw_ver" | clean_output || true)
        version=$(extract_first_semver_str "$raw_ver")
        ;;
    esac
  fi

  if [[ "$installed" != "true" ]]; then
    printf 'not_installed\n' > "$out_dir/status"
    printf 'false\n' > "$out_dir/installed"
    printf '\n' > "$out_dir/version"
    printf '%s\n' "$baseline" > "$out_dir/baseline"
    printf 'false\n' > "$out_dir/schema_ok"
    : > "$out_dir/findings"
    return 0
  fi

  version="${version:-unknown}"
  if [[ "$version" != "unknown" ]]; then
    version_ahead="$(is_version_ahead "$version" "$baseline")"
    if [[ "$version_ahead" == "true" ]]; then
      findings+=("Installed version $version is ahead of verified baseline $baseline; verify flags/schema live")
    fi
  else
    findings+=("Binary installed at $bin, but version extraction failed or timed out")
  fi

  # 2. Live Binary Schema / Flag Introspection (using literal/bash matching to avoid SIGPIPE)
  local out_cap="" err_cap="" rc=0
  case "$target" in
    mise)
      local err_file="$out_dir/mise.err"
      out_cap=$(run_bounded "$bin" settings ls --all 2>"$err_file" || true)
      out_cap=$(printf '%s' "$out_cap" | clean_output || true)
      err_cap=$(clean_output < "$err_file" 2>/dev/null || true)
      if [[ "$out_cap" != *"download_cache"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("mise settings ls --all did not list expected 'download_cache' setting")
      fi
      if grep -qE 'WARN[[:space:]]+deprecated' <<< "$err_cap"; then
        deprecated_cfg=true
        local warn_line
        warn_line=$(grep -m1 -E 'WARN[[:space:]]+deprecated' <<< "$err_cap" || true)
        findings+=("mise stderr warning: $warn_line")
      fi
      ;;
    pi)
      local pi_real pi_dir schema_file="" docs_settings=""
      pi_real="$(resolve_realpath "$bin")"
      pi_dir="$(dirname "$pi_real")"
      for cand in "$pi_dir/settings.schema.json" "$pi_dir/dist/settings.schema.json" "$pi_dir/../settings.schema.json"; do
        if [[ -r "$cand" ]]; then
          schema_file="$cand"
          break
        fi
      done
      if [[ -n "$schema_file" ]]; then
        for prop in compaction cacheWarming defaultTools; do
          if ! grep -q "\"$prop\"" "$schema_file" 2>/dev/null; then
            schema_drift=true
            schema_ok="false"
            findings+=("pi settings.schema.json missing expected property '$prop'")
          fi
        done
      else
        for cand in "$pi_dir/docs/settings.md" "$pi_dir/../docs/settings.md"; do
          if [[ -r "$cand" ]]; then
            docs_settings="$cand"
            break
          fi
        done
        if [[ -n "$docs_settings" ]]; then
          for prop in compaction cacheWarming defaultTools; do
            if ! grep -q "$prop" "$docs_settings" 2>/dev/null; then
              schema_drift=true
              schema_ok="false"
              findings+=("pi docs/settings.md missing expected property '$prop'")
            fi
          done
        fi
      fi
      ;;
    antigravity)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      out_cap=$(printf '%s' "$out_cap" | clean_output || true)
      if [[ "$out_cap" != *"--sandbox"* || "$out_cap" != *"plugin"* || "$out_cap" != *"mcp"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("agy --help missing expected --sandbox, plugin, or mcp options")
      fi
      ;;
    herdr)
      out_cap=$(run_bounded "$bin" --default-config 2>&1 || true)
      out_cap=$(printf '%s' "$out_cap" | clean_output || true)
      if [[ "$out_cap" != *"[ui.toast]"* || "$out_cap" != *"resume_agents_on_restore"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("herdr --default-config missing [ui.toast] or resume_agents_on_restore")
      fi
      local herdr_cfg=""
      for cand in "$xdg_cfg/herdr/config.toml" "$(find_windows_appdata Roaming herdr/config.toml 2>/dev/null || true)"; do
        [[ -n "$cand" && -f "$cand" ]] && { herdr_cfg="$cand"; break; }
      done
      if [[ -n "$herdr_cfg" ]]; then
        rc=0
        out_cap=$(run_bounded "$bin" config check 2>&1) || rc=$?
        out_cap=$(printf '%s' "$out_cap" | clean_output || true)
        if [[ "$rc" -ne 0 ]] || grep -qiE '^[[:space:]]*(\[?(warn|warning|error)\]?:|deprecated)' <<< "$out_cap"; then
          deprecated_cfg=true
          findings+=("herdr config check reported: $(printf '%s' "$out_cap" | tr '\n' ' ' | sed 's/[[:space:]]\+$//')")
        fi
      fi
      ;;
    starship)
      out_cap=$(run_bounded "$bin" print-config --default 2>&1 || true)
      out_cap=$(printf '%s' "$out_cap" | clean_output || true)
      if [[ "$out_cap" != *"[mise]"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("starship print-config --default missing [mise] module")
      fi
      ;;
    lazygit)
      if ! run_bounded "$bin" --help >/dev/null 2>&1 || ! run_bounded "$bin" --config >/dev/null 2>&1; then
        schema_drift=true
        schema_ok="false"
        findings+=("lazygit --help or lazygit --config failed")
      fi
      ;;
    eza)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"--icon"*"[<WHEN>]"* && "$out_cap" != *"--icons="* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("eza --help missing --icons=WHEN flag")
      fi
      ;;
    ripgrep)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"--max-columns-preview"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("rg --help missing --max-columns-preview flag")
      fi
      ;;
    fd)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"--strip-cwd-prefix"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("fd --help missing --strip-cwd-prefix flag")
      fi
      ;;
    fzf)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"--bash"* || "$out_cap" != *"--walker"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("fzf --help missing --bash or --walker flag")
      fi
      ;;
    bat)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"--theme-dark"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("bat --help missing --theme-dark flag")
      fi
      ;;
    yt-dlp)
      out_cap=$(run_bounded "$bin" --ignore-config --help 2>&1 || true)
      if [[ "$out_cap" != *"--js-runtimes"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("yt-dlp --help missing --js-runtimes flag")
      fi
      ;;
    mpv)
      out_cap=$(run_bounded "$bin" --no-config --vo=help 2>&1 || true)
      if [[ "$out_cap" != *"gpu-next"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("mpv --vo=help missing gpu-next output driver")
      fi
      ;;
    syncthing)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"serve"* || "$out_cap" != *"paths"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("syncthing --help missing expected v2 subcommands (serve/paths)")
      fi
      ;;
    uv)
      out_cap=$(run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"cache"* || "$out_cap" != *"tool"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("uv --help missing expected subcommands (cache/tool)")
      fi
      ;;
    gh)
      out_cap=$(run_bounded "$bin" config --help 2>&1 || true)
      if [[ "$out_cap" != *"telemetry"* && "$out_cap" != *"git_protocol"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("gh config --help missing telemetry/git_protocol keys")
      fi
      ;;
    controld)
      out_cap=$(run_bounded "$bin" start --help 2>&1 || run_bounded "$bin" --help 2>&1 || true)
      if [[ "$out_cap" != *"doh3"* && "$out_cap" != *"config"* ]]; then
        schema_drift=true
        schema_ok="false"
        findings+=("ctrld start --help missing doh3/config flags")
      fi
      ;;
  esac

  # 3. Live Deprecated / Invalid User Config Drift Scan (read-only)
  case "$target" in
    mise)
      local mise_dir="${MISE_CONFIG_DIR:-$xdg_cfg/mise}"
      if [[ -f "$mise_dir/settings.toml" ]]; then
        deprecated_cfg=true
        findings+=("Legacy $mise_dir/settings.toml exists (settings should live under [settings] in config.toml)")
      fi
      local mise_files=("$mise_dir/config.toml" "$mise_dir/settings.toml")
      if [[ -d "$mise_dir/conf.d" ]]; then
        local mf_cand
        for mf_cand in "$mise_dir/conf.d"/*.toml; do
          [[ -f "$mf_cand" ]] && mise_files+=("$mf_cand")
        done
      fi
      for mf_cand in "$(find_windows_appdata Roaming mise/config.toml 2>/dev/null || true)" "$(find_windows_appdata Local mise/config.toml 2>/dev/null || true)"; do
        [[ -n "$mf_cand" && -f "$mf_cand" ]] && mise_files+=("$mf_cand")
      done
      local f
      for f in "${mise_files[@]}"; do
        if [[ -r "$f" ]]; then
          if uncommented_match "$f" '(^|[^[:alnum:]_])always_keep_download([[:space:]]*=|$)'; then
            deprecated_cfg=true
            findings+=("$f contains deprecated setting 'always_keep_download' (use 'download_cache')")
          fi
          if uncommented_match "$f" '(^|[^[:alnum:]_])allow_root([[:space:]]*=|$)'; then
            deprecated_cfg=true
            findings+=("$f contains deprecated/removed setting 'allow_root'")
          fi
        fi
      done
      ;;
    antigravity)
      local agy_mcp="$HOME/.gemini/config/mcp_config.json"
      if [[ -r "$agy_mcp" ]]; then
        if uncommented_match "$agy_mcp" '"serverUrl"[[:space:]]*:'; then
          deprecated_cfg=true
          findings+=("$agy_mcp uses legacy 'serverUrl' key (use 'url' for Streamable HTTP MCP servers)")
        fi
        if uncommented_match "$agy_mcp" '"type"[[:space:]]*:[[:space:]]*"sse"'; then
          deprecated_cfg=true
          findings+=("$agy_mcp uses unsupported legacy SSE transport 'type: sse' (use Streamable HTTP or mcp-remote stdio bridge)")
        fi
      fi
      ;;
    lazygit)
      local lg_cfg=""
      for cand in "$xdg_cfg/lazygit/config.yml" "$(find_windows_appdata Roaming lazygit/config.yml 2>/dev/null || true)" "$(find_windows_appdata Local lazygit/config.yml 2>/dev/null || true)"; do
        [[ -n "$cand" && -r "$cand" ]] && { lg_cfg="$cand"; break; }
      done
      if [[ -n "$lg_cfg" ]]; then
        if awk '/^[[:space:]]*#/ {next} /^[[:alpha:]_-]+:/ {sec = $1} sec == "git:" && /^[[:space:]]+(paging|pagers):/ {found=1; exit} END {exit !found}' "$lg_cfg" 2>/dev/null; then
          deprecated_cfg=true
          findings+=("$lg_cfg uses legacy git.paging/git.pagers (migrated to git.pagers[] / diffRenderers)")
        fi
        if awk '/^[[:space:]]*#/ {next} /^[[:alpha:]_-]+:/ {sec = $1} sec == "gui:" && /^[[:space:]]+showIcons:/ {found=1; exit} END {exit !found}' "$lg_cfg" 2>/dev/null; then
          deprecated_cfg=true
          findings+=("$lg_cfg uses deprecated 'gui.showIcons' key (use gui.nerdFontsVersion: \"3\")")
        fi
        if awk '/^[[:space:]]*#/ {next} /^[[:alpha:]_-]+:/ {sec = $1} sec == "os:" && /^[[:space:]]+(editCommand|editCommandTemplate):/ {found=1; exit} END {exit !found}' "$lg_cfg" 2>/dev/null; then
          deprecated_cfg=true
          findings+=("$lg_cfg uses legacy 'os.editCommand/editCommandTemplate' key (use os.editPreset)")
        fi
      fi
      ;;
    starship)
      local ss_cfg=""
      for cand in "${STARSHIP_CONFIG:-}" "$xdg_cfg/starship.toml" "$(find_windows_appdata Roaming starship.toml 2>/dev/null || true)"; do
        [[ -n "$cand" && -r "$cand" ]] && { ss_cfg="$cand"; break; }
      done
      if [[ -n "$ss_cfg" ]]; then
        if awk '/^[[:space:]]*#/ {next} /^\[/ {in_mise = ($0 ~ /^\[mise\]([[:space:]]|$)/); next} in_mise && /\$version/ {found=1; exit} END {exit !found}' "$ss_cfg" 2>/dev/null; then
          deprecated_cfg=true
          findings+=("$ss_cfg [mise] block references unsupported \$version placeholder")
        fi
      fi
      ;;
    fzf)
      if [[ "${FZF_DEFAULT_OPTS:-}" == *"--inline-info"* ]]; then
        deprecated_cfg=true
        findings+=("FZF_DEFAULT_OPTS contains deprecated '--inline-info' flag")
      fi
      for f in "${FZF_DEFAULT_OPTS_FILE:-}" "$xdg_cfg/fzf/fzfrc"; do
        if [[ -n "$f" ]] && uncommented_match "$f" '--inline-info'; then
          deprecated_cfg=true
          findings+=("$f contains deprecated '--inline-info' flag")
        fi
      done
      ;;
    mpv)
      local mpv_cfg=""
      for cand in "$xdg_cfg/mpv/mpv.conf" "$(find_windows_appdata Roaming mpv/mpv.conf 2>/dev/null || true)"; do
        [[ -n "$cand" && -r "$cand" ]] && { mpv_cfg="$cand"; break; }
      done
      if [[ -n "$mpv_cfg" ]]; then
        if uncommented_match "$mpv_cfg" 'profile[[:space:]]*=[[:space:]]*gpu-hq([[:space:]#]|$)'; then
          deprecated_cfg=true
          findings+=("$mpv_cfg uses legacy 'profile=gpu-hq' (prefer high-quality / vo=gpu-next)")
        fi
        if uncommented_match "$mpv_cfg" 'hwdec[[:space:]]*=[[:space:]]*nvdec-copy([[:space:]#]|$)'; then
          deprecated_cfg=true
          findings+=("$mpv_cfg uses legacy 'hwdec=nvdec-copy' (prefer auto-safe or nvdec)")
        fi
        # removed in mpv 0.42 (libplacebo tone mapping handles desaturation)
        if uncommented_match "$mpv_cfg" '^[[:space:]]*tone-mapping-desaturate(-exponent)?[[:space:]]*='; then
          deprecated_cfg=true
          findings+=("$mpv_cfg sets 'tone-mapping-desaturate', removed in mpv 0.42 (delete it; gpu-next tone mapping covers it)")
        fi
      fi
      ;;
    yt-dlp)
      local ytdlp_cfg=""
      for cand in "$xdg_cfg/yt-dlp/config" "$HOME/.yt-dlp/config" "$(find_windows_appdata Roaming yt-dlp/config 2>/dev/null || true)"; do
        [[ -n "$cand" && -r "$cand" ]] && { ytdlp_cfg="$cand"; break; }
      done
      if [[ -n "$ytdlp_cfg" ]]; then
        if uncommented_match "$ytdlp_cfg" '(--(external-)?downloader([[:space:]]+|=)["'\'']?aria2c([[:space:]"'\'']|$))' && \
           ! uncommented_match "$ytdlp_cfg" 'dash,m3u8:native'; then
          deprecated_cfg=true
          findings+=("$ytdlp_cfg sets unscoped global aria2c downloader without dash,m3u8:native (breaks HLS/DASH fragments)")
        fi
        if uncommented_match "$ytdlp_cfg" '(^|[[:space:]])--impersonate([[:space:]=]|$)'; then
          deprecated_cfg=true
          findings+=("$ytdlp_cfg sets global --impersonate (can break standard extractors)")
        fi
      fi
      ;;
    podman)
      local pod_files=("$xdg_cfg/containers/containers.conf")
      if [[ -d "$xdg_cfg/containers/containers.conf.d" ]]; then
        local pf_cand
        for pf_cand in "$xdg_cfg/containers/containers.conf.d"/*.conf; do
          [[ -f "$pf_cand" ]] && pod_files+=("$pf_cand")
        done
      fi
      local pf
      for pf in "${pod_files[@]}"; do
        if [[ -r "$pf" ]]; then
          if uncommented_match "$pf" 'slirp4netns'; then
            deprecated_cfg=true
            findings+=("$pf references removed 'slirp4netns' network backend (use pasta)")
          fi
          if uncommented_match "$pf" '(^|[^[:alnum:]_])log_max_size([[:space:]]*=|$)'; then
            deprecated_cfg=true
            findings+=("$pf contains invalid/typo key 'log_max_size' (use 'log_size_max')")
          fi
        fi
      done
      ;;
    lazydocker)
      local ld_cfg=""
      for cand in "$xdg_cfg/lazydocker/config.yml" "$(find_windows_appdata Roaming lazydocker/config.yml 2>/dev/null || true)"; do
        [[ -n "$cand" && -r "$cand" ]] && { ld_cfg="$cand"; break; }
      done
      if [[ -n "$ld_cfg" ]]; then
        if uncommented_match "$ld_cfg" '^[[:space:]]*optionsColor:'; then
          deprecated_cfg=true
          findings+=("$ld_cfg uses deprecated 'optionsColor' key (use optionsTextColor)")
        fi
      fi
      ;;
    cargo)
      local cargo_home="${CARGO_HOME:-$HOME/.cargo}"
      if [[ -f "$cargo_home/config" ]]; then
        deprecated_cfg=true
        findings+=("Extensionless $cargo_home/config exists (migrate to $cargo_home/config.toml)")
      fi
      ;;
    neovim)
      local nv_dir=""
      for cand in "$xdg_cfg/nvim" "$(find_windows_appdata Local nvim 2>/dev/null || true)"; do
        [[ -n "$cand" && -d "$cand" ]] && { nv_dir="$cand"; break; }
      done
      if [[ -n "$nv_dir" ]]; then
        if grep -RIqs --include='*.lua' --exclude-dir=.git 'nvim-treesitter\.configs' "$nv_dir" 2>/dev/null; then
          deprecated_cfg=true
          findings+=("$nv_dir references removed 'nvim-treesitter.configs' module")
        fi
        if has_mason_lspconfig_deprecated "$nv_dir"; then
          deprecated_cfg=true
          findings+=("$nv_dir uses removed mason-lspconfig 'automatic_installation' option (use automatic_enable)")
        fi
      fi
      ;;
    syncthing)
      local st_major
      st_major=$(echo "$version" | cut -d. -f1 | tr -cd '0-9')
      if [[ -n "$st_major" ]] && (( 10#$st_major >= 2 )); then
        for cand in "$xdg_state/syncthing/index-v0.14.0.db" "$xdg_cfg/syncthing/index-v0.14.0.db" "$xdg_data/syncthing/index-v0.14.0.db" "$(find_windows_appdata Local Syncthing/index-v0.14.0.db 2>/dev/null || true)"; do
          if [[ -n "$cand" && -e "$cand" ]]; then
            deprecated_cfg=true
            findings+=("Leftover v1 database $cand exists alongside Syncthing v2")
            break
          fi
        done
      fi
      ;;
    wsl)
      local wsl_cfg
      wsl_cfg="$(find_wslconfig 2>/dev/null || true)"
      if [[ -n "$wsl_cfg" && -r "$wsl_cfg" ]]; then
        if uncommented_match "$wsl_cfg" '[sS][pP][aA][rR][sS][eE][vV][hH][dD][[:space:]]*=[[:space:]]*[tT][rR][uU][eE]' '^[[:space:]]*[#;]'; then
          deprecated_cfg=true
          findings+=("$wsl_cfg has unsafe 'sparseVhd=true' enabled")
        fi
        if awk '
          /^[[:space:]]*[#;]/ { next }
          /^[[:space:]]*\[/ {
            sec = tolower($0)
            gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", sec)
            next
          }
          sec == "wsl2" && tolower($0) ~ /^[[:space:]]*automemoryreclaim[[:space:]]*=/ { found=1; exit }
          END { exit !found }
        ' "$wsl_cfg" 2>/dev/null; then
          deprecated_cfg=true
          findings+=("$wsl_cfg has 'autoMemoryReclaim' misplaced under [wsl2] (must be under [experimental])")
        fi
      fi
      ;;
  esac

  local status="verified"
  if [[ "$schema_drift" == true ]]; then
    status="schema_drift"
  elif [[ "$deprecated_cfg" == true ]]; then
    status="deprecated_config"
  elif [[ "$version_ahead" == "true" ]]; then
    status="version_ahead"
  fi

  printf '%s\n' "$status" > "$out_dir/status"
  printf '%s\n' "$installed" > "$out_dir/installed"
  printf '%s\n' "$version" > "$out_dir/version"
  printf '%s\n' "$baseline" > "$out_dir/baseline"
  printf '%s\n' "$schema_ok" > "$out_dir/schema_ok"
  printf '%s\n' "$version_ahead" > "$out_dir/version_ahead"
  : > "$out_dir/findings"
  if [[ ${#findings[@]} -gt 0 ]]; then
    printf '%s\n' "${findings[@]}" > "$out_dir/findings"
  fi
}

ALL_TARGETS=(
  mise pi antigravity topgrade neovim herdr lazygit fzf cargo python uv git gh
  starship zoxide ripgrep fd eza bat mpv ffmpeg zstd yt-dlp syncthing podman docker
  lazydocker flatpak pacman yay paccache btop htop sqlite3 rustdesk controld pwsh
)
if is_windows || [[ -f "$HOME/.wslconfig" ]]; then
  ALL_TARGETS+=(wsl)
fi

TARGETS=()
skipped_domain_targets=()
if [[ ${#POSITIONAL[@]} -gt 0 ]]; then
  for raw_t in "${POSITIONAL[@]}"; do
    canon="$(resolve_alias "$raw_t")"
    if is_non_cli_target "$canon"; then
      skipped_domain_targets+=("$raw_t")
      continue
    fi
    seen=false
    for existing in "${TARGETS[@]+"${TARGETS[@]}"}"; do
      if [[ "$existing" == "$canon" ]]; then
        seen=true
        break
      fi
    done
    [[ "$seen" == false ]] && TARGETS+=("$canon")
  done
else
  TARGETS=("${ALL_TARGETS[@]}")
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MAX_JOBS=32
pids=()
for idx in "${!TARGETS[@]}"; do
  mkdir -p "$TMP_DIR/$idx"
  probe_target "${TARGETS[$idx]}" "$TMP_DIR/$idx" </dev/null >/dev/null 2>&1 &
  pids+=($!)
  if (( ${#pids[@]} >= MAX_JOBS )); then
    wait "${pids[0]}" || true
    pids=("${pids[@]:1}")
  fi
done
for pid in "${pids[@]+"${pids[@]}"}"; do
  wait "$pid" || true
done

total=0
cnt_verified=0
cnt_version_ahead=0
cnt_schema_drift=0
cnt_deprecated_config=0
cnt_not_installed=0
any_version_ahead=false

for idx in "${!TARGETS[@]}"; do
  d="$TMP_DIR/$idx"
  st=$(cat "$d/status" 2>/dev/null || echo "not_installed")
  va=$(cat "$d/version_ahead" 2>/dev/null || echo "false")
  [[ "$va" == "true" ]] && any_version_ahead=true
  total=$((total + 1))
  case "$st" in
    verified) cnt_verified=$((cnt_verified + 1)) ;;
    version_ahead) cnt_version_ahead=$((cnt_version_ahead + 1)) ;;
    schema_drift) cnt_schema_drift=$((cnt_schema_drift + 1)) ;;
    deprecated_config) cnt_deprecated_config=$((cnt_deprecated_config + 1)) ;;
    not_installed) cnt_not_installed=$((cnt_not_installed + 1)) ;;
  esac
done

if [[ "$JSON_MODE" == true ]]; then
  printf '{\n'
  printf '  "summary": {\n'
  printf '    "total": %d,\n' "$total"
  printf '    "verified": %d,\n' "$cnt_verified"
  printf '    "version_ahead": %d,\n' "$cnt_version_ahead"
  printf '    "schema_drift": %d,\n' "$cnt_schema_drift"
  printf '    "deprecated_config": %d,\n' "$cnt_deprecated_config"
  printf '    "not_installed": %d\n' "$cnt_not_installed"
  printf '  },\n'
  printf '  "targets": [\n'
  for idx in "${!TARGETS[@]}"; do
    d="$TMP_DIR/$idx"
    t="${TARGETS[$idx]}"
    st=$(cat "$d/status" 2>/dev/null || echo "not_installed")
    inst=$(cat "$d/installed" 2>/dev/null || echo "false")
    ver=$(cat "$d/version" 2>/dev/null || echo "")
    base=$(cat "$d/baseline" 2>/dev/null || echo "")
    sok=$(cat "$d/schema_ok" 2>/dev/null || echo "false")
    va=$(cat "$d/version_ahead" 2>/dev/null || echo "false")
    f_arr=()
    if [[ -s "$d/findings" ]]; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && f_arr+=("$line")
      done < "$d/findings"
    fi
    comma=","
    (( idx == ${#TARGETS[@]} - 1 )) && comma=""
    printf '    {\n'
    printf '      "target": "%s",\n' "$(json_str "$t")"
    printf '      "installed": %s,\n' "$(json_bool "$inst")"
    printf '      "installed_version": "%s",\n' "$(json_str "$ver")"
    printf '      "verified_baseline": "%s",\n' "$(json_str "$base")"
    printf '      "version_ahead": %s,\n' "$(json_bool "$va")"
    printf '      "status": "%s",\n' "$(json_str "$st")"
    printf '      "schema_ok": %s,\n' "$(json_bool "$sok")"
    printf '      "findings": %s\n' "$(to_json_arr "${f_arr[@]+"${f_arr[@]}"}")"
    printf '    }%s\n' "$comma"
  done
  printf '  ]\n'
  printf '}\n'
  exit 0
fi

echo "=== System Optimizer Tool & Config Drift Check ==="
if [[ ${#skipped_domain_targets[@]} -gt 0 ]]; then
  echo "Skipped OS/GUI domain targets (no standalone CLI schema): ${skipped_domain_targets[*]}"
fi
for idx in "${!TARGETS[@]}"; do
  d="$TMP_DIR/$idx"
  t="${TARGETS[$idx]}"
  st=$(cat "$d/status" 2>/dev/null || echo "not_installed")
  ver=$(cat "$d/version" 2>/dev/null || echo "")
  base=$(cat "$d/baseline" 2>/dev/null || echo "")
  va=$(cat "$d/version_ahead" 2>/dev/null || echo "false")
  [[ -z "$ver" ]] && ver="none"
  [[ -z "$base" ]] && base="none"

  badge="NOT INSTALLED"
  case "$st" in
    verified) badge="VERIFIED" ;;
    version_ahead) badge="VERSION AHEAD" ;;
    schema_drift) badge="SCHEMA DRIFT" ;;
    deprecated_config)
      if [[ "$va" == "true" ]]; then
        badge="DEPRECATED CONFIG + VERSION AHEAD"
      else
        badge="DEPRECATED CONFIG"
      fi
      ;;
    not_installed) badge="NOT INSTALLED" ;;
  esac

  notes="matches baseline"
  if [[ "$st" == "not_installed" ]]; then
    notes="binary not found"
  fi
  if [[ -s "$d/findings" ]]; then
    notes=$(awk 'NR>1{printf "; "} {printf "%s", $0}' "$d/findings")
  fi

  printf '[%s] %s (installed: %s, baseline: %s) — %s\n' "$badge" "$t" "$ver" "$base" "$notes"
done

echo ""
printf 'Summary: total=%d verified=%d version_ahead=%d schema_drift=%d deprecated_config=%d not_installed=%d\n' \
  "$total" "$cnt_verified" "$cnt_version_ahead" "$cnt_schema_drift" "$cnt_deprecated_config" "$cnt_not_installed"
if [[ "$any_version_ahead" == true ]] || (( cnt_version_ahead > 0 || cnt_schema_drift > 0 )); then
  echo "Action: For any VERSION AHEAD or SCHEMA DRIFT target, inspect live --help / schema output before applying configuration edits."
fi
