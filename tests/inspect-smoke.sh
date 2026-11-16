#!/usr/bin/env bash
# inspect-smoke.sh - every target of scripts/target-inspect.sh must run to the end (exit 0) without
# writing to stderr, in a clean environment (no FZF_*, RIPGREP_*, ... variables, empty HOME).
# A crash such as "unbound variable" or an arithmetic error would otherwise go unnoticed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    echo "SKIP - inspect-smoke (the Windows branch of target-inspect.sh is checked on a real Windows host)"
    exit 0 ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home"

targets="antigravity bash bat boot brave btop cargo chrome controld cpu defender docker edge execution-policy eza fd firefox firewall flatpak full fzf gh git herdr htop
kde-plasma kernel lazydocker lazygit librewolf makepkg memory mise mpv neovim network paccache package-audit pacman pi podman powertoys pwsh python ripgrep rustdesk
sandboxing security sqlite3 ssh starship storage syncthing sysctl-security system topgrade uac uv windows-terminal winget wsl yay yt-dlp zoxide"
domain_and_browser_targets=" system security full kernel storage memory cpu boot network firewall ssh sysctl-security sandboxing package-audit execution-policy uac defender chrome edge brave firefox librewolf "
failed=0; count=0
for t in $targets; do
  count=$((count + 1))
  if env -i PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" "$t" > "$WORK/out" 2> "$WORK/err"; then rc=0; else rc=$?; fi
  if [[ "$rc" -ne 0 || -s "$WORK/err" ]]; then
    failed=$((failed + 1))
    echo "FAIL - target '$t': exit $rc, stderr: $(head -n 2 "$WORK/err" | cut -c1-200)" >&2
  elif [[ "$domain_and_browser_targets" == *" $t "* ]] && grep -q 'Status: NOT FOUND IN PATH' "$WORK/out"; then
    failed=$((failed + 1))
    echo "FAIL - target '$t' fell through to generic NOT FOUND IN PATH" >&2
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "inspect-smoke: $failed of $count targets failed" >&2
  exit 1
fi
echo "ok   - all $count targets run to the end without errors or domain fallthrough"

# Neovim + Mise synergy checks: verify target-inspect.sh neovim detects LazyVim v15 issues and Mason lock state
mkdir -p "$WORK/home/.config/nvim/lua/plugins" "$WORK/home/.config/nvim/lua/config" "$WORK/bin"
cat > "$WORK/bin/nvim" <<'EOF'
#!/usr/bin/env bash
echo "NVIM v0.12.6"
EOF
cat > "$WORK/bin/mise" <<'EOF'
#!/usr/bin/env bash
echo "2026.10.7"
EOF
chmod +x "$WORK/bin/nvim" "$WORK/bin/mise"
cat > "$WORK/home/.config/nvim/init.lua" <<'EOF'
vim.loader.enable()
vim.g.loaded_node_provider = 0
EOF
cat > "$WORK/home/.config/nvim/lua/plugins/treesitter.lua" <<'EOF'
require("nvim-treesitter.configs").setup({})
EOF
cat > "$WORK/home/.config/nvim/lua/plugins/mason.lua" <<'EOF'
return {
  { "mason-org/mason.nvim", opts_extend = {}, opts = { PATH = "append" } },
  { "neovim/nvim-lspconfig", opts = { servers = { lua_ls = { mason = false } } } },
}
EOF
cat > "$WORK/home/.config/nvim/lua/config/autocmds.lua" <<'EOF'
vim.api.nvim_create_augroup("mise_env_sync", { clear = true })
EOF
cat > "$WORK/home/.config/nvim/.neoconf.json" <<'EOF'
{"neodev": {}}
EOF
mkdir -p "$WORK/home/.config/mise"
cat > "$WORK/home/.config/mise/config.toml" <<'EOF'
[tools]
rust = { version = "latest", components = "rust-analyzer" }
EOF

nv_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" neovim)"
for expected in \
  "Bytecode Loader (vim.loader.enable): [ENABLED]" \
  "Legacy Remote Providers (node/python3/perl/ruby): [DISABLED]" \
  "Treesitter Config Compatibility: [WARNING]" \
  "Neoconf Schema (.neoconf.json): [DEPRECATED KEY]" \
  "Dynamic Project Env Sync (DirChanged -> mise env --json): [ACTIVE]" \
  "Mise Rust Analyzer Component: [CONFIGURED]" \
  "Mason LazyVim Extra Lock (opts_extend = {} & mason = false): [LOCKED]"; do
  if [[ "$nv_out" != *"$expected"* ]]; then
    echo "FAIL - neovim synergy check missing: $expected" >&2
    exit 1
  fi
done
echo "ok   - neovim + mise synergy and LazyVim v15 checks verified"

# Multi-target batch inspection + starship redundant format token + mpv TLS warning + pi stale sessions
mkdir -p "$WORK/home/.config/mpv" "$WORK/home/.pi/agent/sessions"
cat > "$WORK/home/.config/starship.toml" <<'EOF'
format = "$directory$nodejs$rust$mise$character"
[mise]
disabled = false
[nodejs]
disabled = true
EOF
cat > "$WORK/home/.config/mpv/mpv.conf" <<'EOF'
vo=gpu
ytdl-raw-options=no-check-certificates=
EOF
touch "$WORK/home/.pi/agent/sessions/recent.jsonl"
touch -d "40 days ago" "$WORK/home/.pi/agent/sessions/stale.jsonl"

batch_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" starship mpv pi)"
for expected in \
  "=== Target Inspection: starship ===" \
  "[WARNING] Redundant Language Tokens in 'format': \$nodejs \$rust" \
  "=== Target Inspection: mpv ===" \
  "[SECURITY WARNING] 'no-check-certificates' found" \
  "=== Target Inspection: pi ===" \
  "Saved Sessions: 2 session files" \
  "1 stale >30d)"; do
  if [[ "$batch_out" != *"$expected"* ]]; then
    echo "FAIL - multi-target / starship / mpv / pi check missing: $expected" >&2
    exit 1
  fi
done
echo "ok   - multi-target batch inspection, starship format check, mpv TLS warning, and pi stale session count verified"

# a bare "--icons" in a recommended alias breaks "ls <path>" on recent eza (the path becomes the option's value)
if grep -rnE -- '--icons([^=a-z]|$)' "$ROOT/scripts" "$ROOT/references" "$ROOT/SKILL.md" "$ROOT/README.md" >&2; then
  echo "FAIL - a recommendation uses --icons without a value; write --icons=auto" >&2
  exit 1
fi
echo "ok   - eza aliases are recommended as --icons=auto"

# the eza inspector must read the user's real aliases, not only print advice
eza_check() { # <alias line or empty> <expected text>
  if [[ -n "$1" ]]; then printf '%s\n' "$1" > "$WORK/home/.zshrc"; else rm -f "$WORK/home/.zshrc"; fi
  out="$(env -i PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" eza)"
  if [[ "$out" != *"$2"* ]]; then
    echo "FAIL - eza alias check: for '${1:-<no .zshrc>}' expected: $2" >&2
    exit 1
  fi
}
eza_check "alias ls='eza --icons'"       "Icons flag: [MISCONFIGURED]"
eza_check "alias ls='eza --icons=auto'"  "Icons flag: [OK]"
eza_check "# alias ls='eza --icons'"     "eza alias: [NOT CONFIGURED]"
eza_check ""                             "eza alias: [NOT CONFIGURED]"
rm -f "$WORK/home/.zshrc"
echo "ok   - eza alias check reads shell startup files"

# remote-run.sh must refuse anything that is not a plain script name, before it touches ssh
if bash "$ROOT/scripts/remote-run.sh" somehost '../x.sh; id' >/dev/null 2>&1; then
  echo "FAIL - remote-run.sh accepted a script name with a path or shell characters" >&2
  exit 1
fi
echo "ok   - remote-run.sh validates the script name"

# inspectors that used to print advice only must now read the config and tag what they find
cfg_check() { # <target> <relative file> <file content> <expected text>
  local f="$WORK/home/$2"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$3" > "$f"
  # GIT_CONFIG_*: the git cases must not read the machine's /etc/gitconfig or a global config
  out="$(env -i PATH="$PATH" HOME="$WORK/home" LANG=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$WORK/home/.gitconfig" \
    bash "$ROOT/scripts/target-inspect.sh" "$1")"
  rm -f "$f"
  if [[ "$out" != *"$4"* ]]; then
    echo "FAIL - $1 config check: for '$3' expected: $4" >&2
    exit 1
  fi
}
cfg_check yt-dlp  .config/yt-dlp/config              "--no-check-certificate"                     "[SECURITY WARNING] --no-check-certificate"
cfg_check rustdesk .config/rustdesk/RustDesk2.toml    "verification-method = 'use-permanent-password'" "[NOTE]"
cfg_check controld .config/controld/ctrld.toml        'ip = "0.0.0.0"'                              "binds 0.0.0.0"
cfg_check git     .gitconfig                         $'[safe]\n\tdirectory = *'                 "safe.directory: [WARNING]"
cfg_check git     .gitconfig                         "[user]"                                     "credential.helper: unset [NOT CONFIGURED]"
cfg_check bat     .zshrc                             "export BAT_THEME=ansi"                      "BAT_THEME=ansi"
cfg_check sqlite3 .sqliterc                          ".headers on"                                "Active ~/.sqliterc"
echo "ok   - git, bat, yt-dlp, sqlite3, rustdesk and controld inspectors read the real config"

# a word that merely contains "eza" is not an eza alias
eza_check "export PATH=\$PATH:~/mezzanine" "eza alias: [NOT CONFIGURED]"
rm -f "$WORK/home/.zshrc"
# no git installed: no git verdicts (a minimal PATH with the tools the script needs, but no git)
mkdir -p "$WORK/nogit"
for b in bash env grep sed awk cat stat tr head wc dirname uname date mktemp sort cut; do
  p="$(command -v "$b" || true)"; [[ -n "$p" ]] && ln -sf "$p" "$WORK/nogit/$b"
done
out="$(env -i PATH="$WORK/nogit" HOME="$WORK/home" LANG=C "$WORK/nogit/bash" "$ROOT/scripts/target-inspect.sh" git)"
if [[ "$out" == *"Git Findings"* ]]; then
  echo "FAIL - git inspector printed verdicts although git is not installed" >&2
  exit 1
fi
echo "ok   - eza matches whole words only; git verdicts need git installed"

# the [WARNING] branches of kernel and boot, with fake sysctl / systemctl first on PATH
mkdir -p "$WORK/fake"
printf '#!/usr/bin/env bash\necho 0\n' > "$WORK/fake/sysctl"
cat > "$WORK/fake/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--failed"* ]]; then echo "● foo.service loaded failed failed Foo"; else echo inactive; fi
EOF
chmod +x "$WORK/fake/sysctl" "$WORK/fake/systemctl"
out="$(env -i PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" kernel)"
[[ "$out" == *"kernel.kptr_restrict: 0 [WARNING]"* ]] || { echo "FAIL - kernel check did not warn on kptr_restrict=0" >&2; exit 1; }
out="$(env -i PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" boot)"
[[ "$out" == *"Failed Units: [WARNING] 1 unit(s): foo.service"* ]] || { echo "FAIL - boot check did not name the failed unit" >&2; exit 1; }
echo "ok   - kernel and boot inspectors warn on bad values"

# host-diff.sh with a fake ssh: secrets must not be printed, and a dead connection must not look like a missing file
mkdir -p "$WORK/ssh" "$WORK/remote"
cat > "$WORK/ssh/ssh" <<'EOF'
#!/usr/bin/env bash
cmd="${*: -1}"
[[ "$cmd" == true ]] && exit 0
[[ -n "${FAKE_SSH_EXIT:-}" ]] && exit "$FAKE_SSH_EXIT"
f="${cmd#test -f ~/}"; f="${f%% *}"
[[ -f "$FAKE_REMOTE/$f" ]] || exit 3
cat "$FAKE_REMOTE/$f"
EOF
chmod +x "$WORK/ssh/ssh"
cat > "$WORK/home/.zshrc" <<'EOF'
export OPENAI=sk-abc12345678
export DB_URL=postgres://user:pw0rd@host/db
export EDITOR=nvim
alias ls='eza --icons=auto'
alias a=task-run-alpha
EOF
mkdir -p "$WORK/home/.pi/agent" "$WORK/remote/.pi/agent"
printf '{\n  "apiKey": "my-json-secret-value",\n  "defaultModel": "gpt-5"\n}\n' > "$WORK/home/.pi/agent/settings.json"
printf '{\n  "defaultModel": "claude-4"\n}\n' > "$WORK/remote/.pi/agent/settings.json"
printf "alias ls='ls --color'\nalias a=task-run-beta\n" > "$WORK/remote/.zshrc"
out="$(env -i PATH="$WORK/ssh:$PATH" HOME="$WORK/home" FAKE_REMOTE="$WORK/remote" bash "$ROOT/scripts/host-diff.sh" fakehost)"
for leaked in "sk-abc12345678" "pw0rd" "my-json-secret-value"; do
  [[ "$out" != *"$leaked"* ]] || { echo "FAIL - host-diff printed a secret: $leaked" >&2; exit 1; }
done
for expected in "[DIFFERENT] .zshrc" "export OPENAI=<value hidden>" "export EDITOR=nvim" "alias ls='eza --icons=auto'" \
                "alias a=task-run-alpha" "alias a=task-run-beta" "[DIFFERENT] .pi/agent/settings.json" '"apiKey": <redacted>'; do
  [[ "$out" == *"$expected"* ]] || { echo "FAIL - host-diff output missing: $expected" >&2; exit 1; }
done
rm -rf "$WORK/home/.pi" "$WORK/remote/.pi"
# 255 = dead connection, 1 = the file exists but cat could not read it: neither may look like a missing file
for code in 255 1; do
  if env -i PATH="$WORK/ssh:$PATH" HOME="$WORK/home" FAKE_REMOTE="$WORK/remote" FAKE_SSH_EXIT="$code" bash "$ROOT/scripts/host-diff.sh" fakehost >/dev/null 2>&1; then
    echo "FAIL - host-diff treated ssh exit $code as a missing file" >&2
    exit 1
  fi
done
rm -f "$WORK/home/.zshrc"
echo "ok   - host-diff hides secrets, keeps different words apart and stops on ssh or read errors"

# a not-found verdict names the files it read; git booleans accept yes/on/1
eza_check "source ~/.zsh_aliases" "files they source are not followed"
rm -f "$WORK/home/.zshrc"
cfg_check git .gitconfig $'[push]\n\tautoSetupRemote = yes' "push.autoSetupRemote: true [OK]"
cfg_check git .gitconfig $'[push]\n\tautoSetupRemote = maybe' "push.autoSetupRemote: invalid value 'maybe'"
# no startup file at all: the sentence must not run into the next one
empty_home="$WORK/empty"; mkdir -p "$empty_home"
out="$(env -i PATH="$PATH" HOME="$empty_home" LANG=C bash "$ROOT/scripts/target-inspect.sh" eza)"
[[ "$out" == *"no startup file found (files they source"* ]] || { echo "FAIL - eza not-found message is glued together" >&2; exit 1; }
echo "ok   - not-found messages name the files read; git booleans are normalised"

# starship command_timeout must be an integer (500), never 500ms
if grep -rnF 'command_timeout = 500ms' "$ROOT/scripts" "$ROOT/references" "$ROOT/SKILL.md" "$ROOT/README.md" >&2; then
  echo "FAIL - starship command_timeout uses '500ms' instead of integer 500" >&2
  exit 1
fi
# ripgrep accepts fd in FZF_DEFAULT_COMMAND; gh respects git credential.helper
printf '#!/usr/bin/env bash\necho "ripgrep 14.1.0"\n' > "$WORK/bin/rg"
printf '#!/usr/bin/env bash\necho "gh version 2.60.0"\n' > "$WORK/bin/gh"
chmod +x "$WORK/bin/rg" "$WORK/bin/gh"
rg_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" FZF_DEFAULT_COMMAND="fd --type f" LANG=C bash "$ROOT/scripts/target-inspect.sh" ripgrep)"
[[ "$rg_out" == *"FZF Backend: [CONFIGURED] (fd is active in FZF_DEFAULT_COMMAND; rg serves content search)"* ]] || { echo "FAIL - ripgrep did not recognize fd in FZF_DEFAULT_COMMAND" >&2; exit 1; }
printf '[credential]\n\thelper = manager\n' > "$WORK/home/.gitconfig"
gh_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$WORK/home/.gitconfig" LANG=C bash "$ROOT/scripts/target-inspect.sh" gh)"
[[ "$gh_out" == *"Git Credential Helper: [CONFIGURED]"* ]] || { echo "FAIL - gh ignored configured git credential.helper" >&2; exit 1; }
rm -f "$WORK/home/.gitconfig"
echo "ok   - starship integer timeout, ripgrep+fd synergy, and gh+git credential helper verified"
# sandboxing, flatpak, docker, detect-targets canonicalization, and elevated remediation script contract
cat > "$WORK/fake/systemd-analyze" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "security" ]]; then
  printf 'UNIT                                 EXPOSURE PREDICATE HAPPY\nfoo.service                               9.2 UNSAFE    😨\nbar.service                               2.1 OK        🙂\n'
fi
EOF
chmod +x "$WORK/fake/systemd-analyze"
sb_out="$(env -i PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" sandboxing)"
[[ "$sb_out" == *"systemd Service Exposure: [WARNING] 1 unsafe/exposed (>=8.0), 0 medium, 1 OK"* ]] || { echo "FAIL - sandboxing did not warn on unsafe systemd unit" >&2; exit 1; }

printf '#!/usr/bin/env bash\necho "Flatpak 1.15.8"\n' > "$WORK/bin/flatpak"
printf '#!/usr/bin/env bash\necho "Docker version 27.1.1"\n' > "$WORK/bin/docker"
chmod +x "$WORK/bin/flatpak" "$WORK/bin/docker"
mkdir -p "$WORK/home/.local/share/flatpak/overrides" "$WORK/home/.docker"
printf '[Context]\nfilesystems=host;\n' > "$WORK/home/.local/share/flatpak/overrides/global"
fp_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" flatpak)"
[[ "$fp_out" == *"[WARNING] grants filesystems=host across all Flatpak apps"* ]] || { echo "FAIL - flatpak did not warn on filesystems=host" >&2; exit 1; }
printf '[Context]\nfilesystems=!host;\n' > "$WORK/home/.local/share/flatpak/overrides/global"
fp_ok="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" flatpak)"
[[ "$fp_ok" == *"[OK] no global filesystem=host escape"* ]] || { echo "FAIL - flatpak warned on negated !host override" >&2; exit 1; }
rm -rf "$WORK/home/.local/share/flatpak"

printf '{\n  "auths": {\n    "https://index.docker.io/v1/": {\n      "auth": "dXNlcjpwYXNz"\n    }\n  }\n}\n' > "$WORK/home/.docker/config.json"
dk_warn="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" docker)"
[[ "$dk_warn" == *"[WARNING] base64 auth token stored without credsStore"* ]] || { echo "FAIL - docker did not warn on plaintext auth without credsStore" >&2; exit 1; }
printf '{\n  "credsStore": "secretservice",\n  "auths": {}\n}\n' > "$WORK/home/.docker/config.json"
dk_ok="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" docker)"
[[ "$dk_ok" == *"Docker Credentials ($WORK/home/.docker/config.json): [OK]"* ]] || { echo "FAIL - docker did not report OK with credsStore" >&2; exit 1; }
rm -rf "$WORK/home/.docker"
echo "ok   - sandboxing, flatpak, and docker config checks verified"

# detect-targets on Linux: python3 -> python, batcat -> bat, fdfind -> fd, and balanced_top omits uninstalled topgrade
mkdir -p "$WORK/deb"
for b in bash env grep sed awk cat tr head wc dirname uname; do
  p="$(command -v "$b" || true)"; [[ -n "$p" ]] && ln -sf "$p" "$WORK/deb/$b"
done
printf '#!/bin/sh\necho "Python 3.12.3"\n' > "$WORK/deb/python3"
printf '#!/bin/sh\necho "batcat 0.24.0"\n' > "$WORK/deb/batcat"
printf '#!/bin/sh\necho "fdfind 10.1.0"\n' > "$WORK/deb/fdfind"
chmod +x "$WORK/deb/python3" "$WORK/deb/batcat" "$WORK/deb/fdfind"
det_json="$(env -i PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/detect-targets.sh" --json)"
[[ "$det_json" == *'"python"'* && "$det_json" == *'"bat"'* && "$det_json" == *'"fd"'* ]] || { echo "FAIL - detect-targets missed python3/batcat/fdfind canonicalization" >&2; exit 1; }
[[ "$det_json" != *'"topgrade"'* ]] || { echo "FAIL - detect-targets included uninstalled topgrade in balanced_top" >&2; exit 1; }
for deb_t in python fd; do
  deb_ins="$(env -i PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/target-inspect.sh" "$deb_t")"
  [[ "$deb_ins" == *"Status: INSTALLED"* ]] || { echo "FAIL - target-inspect $deb_t missed Debian binary fallback" >&2; exit 1; }
done
deb_bat="$(env -i PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/target-inspect.sh" bat)"
[[ "$deb_bat" == *"Binary: $WORK/deb/batcat"* ]] || { echo "FAIL - target-inspect bat missed batcat fallback" >&2; exit 1; }
echo "ok   - detect-targets canonicalizes python3/batcat/fdfind and omits uninstalled topgrade"

# SKILL.md & optimization-guide.md elevated remediation script contract
for needle in "apply-elevated-" 'Never invoke `sudo`' "umask 077" "chmod 0700"; do
  grep -qF -- "$needle" "$ROOT/SKILL.md" || { echo "FAIL - SKILL.md missing elevated script requirement: $needle" >&2; exit 1; }
done
grep -qF -- "WindowsBuiltInRole]::Administrator" "$ROOT/references/optimization-guide.md" || { echo "FAIL - optimization-guide.md missing PowerShell elevation template" >&2; exit 1; }
echo "ok   - elevated remediation script workflow documented in SKILL.md and optimization-guide.md"

# 2026 tool updates: uv, paccache, mise download_cache / deprecated always_keep_download, lazygit diffRenderers, wsl sparseVhd warning, Phase 2.5 dynamic gate
printf '#!/usr/bin/env bash\nif [[ "${1:-}" == "--version" ]]; then echo "uv 0.13.8"; elif [[ "${1:-}" == "cache" ]]; then echo "%s/uv-cache"; elif [[ "${1:-}" == "tool" ]]; then printf "ruff v0.11.0\n"; fi\n' "$WORK" > "$WORK/bin/uv"
chmod +x "$WORK/bin/uv"
mkdir -p "$WORK/uv-cache" "$WORK/home/.config/uv"
printf 'compile-bytecode = true\n' > "$WORK/home/.config/uv/uv.toml"
uv_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" uv)"
[[ "$uv_out" == *"=== Target Inspection: uv ==="* && "$uv_out" == *"compile-bytecode"* ]] || { echo "FAIL - uv target inspection missing expected output" >&2; exit 1; }

cfg_check mise .config/mise/config.toml $'[settings]\nalways_keep_download = true\nallow_root = true' "[DEPRECATED]"
cfg_check lazygit .config/lazygit/config.yml $'git:\n  paging:\n    pager: delta' "diffRenderers"
cfg_check wsl .wslconfig $'[wsl2]\nsparseVhd=true' "sparseVhd"
for needle in "tool-drift-check.sh" "Phase 2.5" "SCHEMA DRIFT" "DEPRECATED CONFIG"; do
  grep -qF -- "$needle" "$ROOT/SKILL.md" || { echo "FAIL - SKILL.md missing dynamic drift gate requirement: $needle" >&2; exit 1; }
done
echo "ok   - 2026 targets (uv, mise, lazygit, wsl) and Phase 2.5 dynamic drift gate verified"

# Antigravity (agy) target inspection: settings, oauth_creds mode, legacy MCP serverUrl/sse, and skills.json registration
printf '#!/usr/bin/env bash\necho "1.5.9"\n' > "$WORK/bin/agy"
chmod +x "$WORK/bin/agy"
mkdir -p "$WORK/home/.gemini/antigravity-cli/brain/session-1" "$WORK/home/.gemini/config"
cat > "$WORK/home/.gemini/antigravity-cli/settings.json" <<EOF
{
  "allowNonWorkspaceAccess": true,
  "colorScheme": "tokyo night",
  "model": "Orchestrator",
  "trustedWorkspaces": ["$WORK/home", "$WORK/repos"]
}
EOF
printf '{"token":"dummy"}\n' > "$WORK/home/.gemini/oauth_creds.json"
chmod 644 "$WORK/home/.gemini/oauth_creds.json"
printf '{"mcpServers":{"legacy":{"serverUrl":"https://example.com/sse","type":"sse"}}}\n' > "$WORK/home/.gemini/config/mcp_config.json"

agy_out1="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" antigravity)"
for expected in \
  "Version: 1.5.9" \
  "model: Orchestrator" \
  "colorScheme: tokyo night" \
  "allowNonWorkspaceAccess: true" \
  "[SECURITY WARNING] trustedWorkspaces includes '/' or '\$HOME'" \
  "[SECURITY WARNING] $WORK/home/.gemini/oauth_creds.json has mode 644" \
  "Global Skill Discovery (system-optimizer): [NOT REGISTERED]" \
  "[DEPRECATED] Legacy MCP 'serverUrl' or 'type: sse'"; do
  if [[ "$agy_out1" != *"$expected"* ]]; then
    echo "FAIL - antigravity inspection missing: $expected" >&2
    exit 1
  fi
done

printf '{"entries":[{"path":"~/.pi/agent/skills"}]}\n' > "$WORK/home/.gemini/config/skills.json"
agy_out2="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" agy)"
[[ "$agy_out2" == *"Global Skill Discovery (system-optimizer): [REGISTERED]"* ]] || {
  echo "FAIL - antigravity inspection did not detect skills.json registration" >&2
  exit 1
}
agy_det="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/detect-targets.sh" --json)"
[[ "$agy_det" == *'"antigravity"'* ]] || {
  echo "FAIL - detect-targets did not detect antigravity when agy is on PATH" >&2
  exit 1
}
rm -rf "$WORK/home/.gemini"
echo "ok   - antigravity (agy) detection, settings, credential mode, legacy MCP, and skills.json verified"
echo "inspect-smoke: $count targets passed"
