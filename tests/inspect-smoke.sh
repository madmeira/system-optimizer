#!/usr/bin/env bash
# inspect-smoke.sh - every target of scripts/target-inspect.sh must run to the end (exit 0) without
# writing to stderr, in a clean environment (no FZF_*, RIPGREP_*, ... variables, empty HOME).
# A crash such as "unbound variable" or an arithmetic error would otherwise go unnoticed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=test-env.sh
source "$ROOT/tests/test-env.sh"

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
sandboxing security sqlite3 ssh starship storage syncthing sysctl-security system topgrade uac uv windows-terminal winget wsl yay yt-dlp zoxide
chromium falkon dolphin kate konsole ffmpeg zstd stremio"
domain_and_browser_targets=" system security full kernel storage memory cpu boot network firewall ssh sysctl-security sandboxing package-audit execution-policy uac defender chrome chromium edge brave firefox librewolf falkon dolphin kate konsole ffmpeg zstd stremio "
failed=0; count=0
for t in $targets; do
  count=$((count + 1))
  if env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" "$t" > "$WORK/out" 2> "$WORK/err"; then rc=0; else rc=$?; fi
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

nv_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" neovim)"
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
tone-mapping=bt.2446a
ytdl-raw-options=no-check-certificates=
EOF
touch "$WORK/home/.pi/agent/sessions/recent.jsonl"
touch -d "40 days ago" "$WORK/home/.pi/agent/sessions/stale.jsonl"

batch_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" starship mpv pi)"
for expected in \
  "=== Target Inspection: starship ===" \
  "[WARNING] Redundant Language Tokens in 'format': \$nodejs \$rust" \
  "=== Target Inspection: mpv ===" \
  "[MISCONFIGURED] tone-mapping uses a vo=gpu-next-only curve with vo=gpu" \
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
  out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" eza)"
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
  out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$WORK/home/.gitconfig" \
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
out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/nogit" HOME="$WORK/home" LANG=C "$WORK/nogit/bash" "$ROOT/scripts/target-inspect.sh" git)"
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
if [[ "$*" == *"--failed"* ]]; then echo "● foo.service loaded failed failed Foo"
elif [[ "$1" == is-enabled ]]; then echo disabled; exit 1
else echo inactive; exit 3; fi
EOF
chmod +x "$WORK/fake/sysctl" "$WORK/fake/systemctl"
# systemctl prints "inactive" AND exits 3: every field must still be a single line
for t in storage firewall; do
  out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" "$t")"
  if grep -qxE '[[:space:]]*(inactive|disabled)\)?' <<< "$out"; then
    echo "FAIL - $t printed a systemctl fallback on its own line (\$(systemctl ... || echo ...) bug)" >&2; exit 1
  fi
done
out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" storage)"
[[ "$out" == *"fstrim.timer Status: inactive (disabled)"* ]] || { echo "FAIL - storage fstrim line is not 'inactive (disabled)'" >&2; exit 1; }
echo "ok   - storage and firewall keep systemctl status on one line"
out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" kernel)"
[[ "$out" == *"kernel.kptr_restrict: 0 [WARNING]"* ]] || { echo "FAIL - kernel check did not warn on kptr_restrict=0" >&2; exit 1; }
out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" boot)"
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
printf '{\n  "apiKey": "my-json-secret-value",\n  "defaultModel": "gpt-5",\n  "reserveTokens": 16384\n}\n' > "$WORK/home/.pi/agent/settings.json"
printf '{\n  "defaultModel": "claude-4"\n}\n' > "$WORK/remote/.pi/agent/settings.json"
printf "alias ls='ls --color'\nalias a=task-run-beta\n" > "$WORK/remote/.zshrc"
out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/ssh:$PATH" HOME="$WORK/home" FAKE_REMOTE="$WORK/remote" bash "$ROOT/scripts/host-diff.sh" fakehost)"
for leaked in "sk-abc12345678" "pw0rd" "my-json-secret-value"; do
  [[ "$out" != *"$leaked"* ]] || { echo "FAIL - host-diff printed a secret: $leaked" >&2; exit 1; }
done
for expected in "[DIFFERENT] .zshrc" "export OPENAI=<value hidden>" "export EDITOR=nvim" "alias ls='eza --icons=auto'" \
                "alias a=task-run-alpha" "alias a=task-run-beta" "[DIFFERENT] .pi/agent/settings.json" '"apiKey": <redacted>' \
                '"reserveTokens": 16384'; do
  [[ "$out" == *"$expected"* ]] || { echo "FAIL - host-diff output missing: $expected" >&2; exit 1; }
done
rm -rf "$WORK/home/.pi" "$WORK/remote/.pi"
# 255 = dead connection, 1 = the file exists but cat could not read it: neither may look like a missing file
for code in 255 1; do
  if env -i "${SO_TEST_ENV[@]}" PATH="$WORK/ssh:$PATH" HOME="$WORK/home" FAKE_REMOTE="$WORK/remote" FAKE_SSH_EXIT="$code" bash "$ROOT/scripts/host-diff.sh" fakehost >/dev/null 2>&1; then
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
out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$empty_home" LANG=C bash "$ROOT/scripts/target-inspect.sh" eza)"
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
rg_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" FZF_DEFAULT_COMMAND="fd --type f" LANG=C bash "$ROOT/scripts/target-inspect.sh" ripgrep)"
[[ "$rg_out" == *"FZF Backend: [CONFIGURED] (fd is active in FZF_DEFAULT_COMMAND; rg serves content search)"* ]] || { echo "FAIL - ripgrep did not recognize fd in FZF_DEFAULT_COMMAND" >&2; exit 1; }
printf '[credential]\n\thelper = manager\n' > "$WORK/home/.gitconfig"
gh_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$WORK/home/.gitconfig" LANG=C bash "$ROOT/scripts/target-inspect.sh" gh)"
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
sb_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/fake:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" sandboxing)"
[[ "$sb_out" == *"systemd Service Exposure: [WARNING] 1 unsafe/exposed (>=8.0), 0 medium, 1 OK"* ]] || { echo "FAIL - sandboxing did not warn on unsafe systemd unit" >&2; exit 1; }

printf '#!/usr/bin/env bash\necho "Flatpak 1.15.8"\n' > "$WORK/bin/flatpak"
printf '#!/usr/bin/env bash\necho "Docker version 27.1.1"\n' > "$WORK/bin/docker"
chmod +x "$WORK/bin/flatpak" "$WORK/bin/docker"
mkdir -p "$WORK/home/.local/share/flatpak/overrides" "$WORK/home/.docker"
printf '[Context]\nfilesystems=host;\n' > "$WORK/home/.local/share/flatpak/overrides/global"
fp_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" flatpak)"
[[ "$fp_out" == *"[WARNING] grants filesystems=host across all Flatpak apps"* ]] || { echo "FAIL - flatpak did not warn on filesystems=host" >&2; exit 1; }
printf '[Context]\nfilesystems=!host;\n' > "$WORK/home/.local/share/flatpak/overrides/global"
fp_ok="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" flatpak)"
[[ "$fp_ok" == *"[OK] no global filesystem=host escape"* ]] || { echo "FAIL - flatpak warned on negated !host override" >&2; exit 1; }
rm -rf "$WORK/home/.local/share/flatpak"

printf '{\n  "auths": {\n    "https://index.docker.io/v1/": {\n      "auth": "dXNlcjpwYXNz"\n    }\n  }\n}\n' > "$WORK/home/.docker/config.json"
dk_warn="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" docker)"
[[ "$dk_warn" == *"[WARNING] base64 auth token stored without credsStore"* ]] || { echo "FAIL - docker did not warn on plaintext auth without credsStore" >&2; exit 1; }
printf '{\n  "credsStore": "secretservice",\n  "auths": {}\n}\n' > "$WORK/home/.docker/config.json"
dk_ok="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" docker)"
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
det_json="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/detect-targets.sh" --json)"
[[ "$det_json" == *'"python"'* && "$det_json" == *'"bat"'* && "$det_json" == *'"fd"'* ]] || { echo "FAIL - detect-targets missed python3/batcat/fdfind canonicalization" >&2; exit 1; }
[[ "$det_json" != *'"topgrade"'* ]] || { echo "FAIL - detect-targets included uninstalled topgrade in balanced_top" >&2; exit 1; }
for deb_t in python fd; do
  deb_ins="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/target-inspect.sh" "$deb_t")"
  [[ "$deb_ins" == *"Status: INSTALLED"* ]] || { echo "FAIL - target-inspect $deb_t missed Debian binary fallback" >&2; exit 1; }
done
deb_bat="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/target-inspect.sh" bat)"
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
uv_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" uv)"
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

agy_out1="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" antigravity)"
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
agy_out_mis="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" agy)"
[[ "$agy_out_mis" == *"Global Skill Discovery (system-optimizer): [MISCONFIGURED]"* ]] || {
  echo "FAIL - antigravity inspection did not flag standalone skills.json without skills/system-optimizer/SKILL.md" >&2
  exit 1
}
mkdir -p "$WORK/home/.gemini/config/skills/system-optimizer"
printf -- '---\nname: system-optimizer\ndescription: test\n---\n' > "$WORK/home/.gemini/config/skills/system-optimizer/SKILL.md"
agy_out2="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" agy)"
[[ "$agy_out2" == *"Global Skill Discovery (system-optimizer): [REGISTERED]"* ]] || {
  echo "FAIL - antigravity inspection did not detect skills/system-optimizer/SKILL.md registration" >&2
  exit 1
}
agy_det="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/detect-targets.sh" --json)"
[[ "$agy_det" == *'"antigravity"'* ]] || {
  echo "FAIL - detect-targets did not detect antigravity when agy is on PATH" >&2
  exit 1
}
rm -rf "$WORK/home/.gemini"
echo "ok   - antigravity (agy) detection, settings, credential mode, legacy MCP, and global skill discovery verified"

# --- startup-file fallbacks, fzf false positives, permission tags, and the new app targets
mkdir -p "$WORK/home/.local/share/socket/completion" "$WORK/home/.local/share/zoxide" "$WORK/bin2"
cat > "$WORK/home/.bashrc" <<'EOF'
[[ $- != *i* ]] && return
export FZF_DEFAULT_COMMAND="rg --files --hidden"
export FZF_CTRL_T_OPTS='--preview "bat --style=numbers --color=always {}"'
export RIPGREP_CONFIG_PATH="$HOME/.config/ripgrep/config"
export ZSTD_NBTHREADS=999
eval "$(fzf --bash)"
source "$HOME/.local/share/socket/completion/socket-completion.bash"
EOF
printf '#!/usr/bin/env bash\necho "0.75.0 (test)"\n' > "$WORK/bin2/fzf"
printf '#!/usr/bin/env bash\necho "*** Zstandard CLI (64-bit) v1.5.7 ***"\n' > "$WORK/bin2/zstd"
chmod +x "$WORK/bin2/fzf" "$WORK/bin2/zstd"
fz_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin2:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" fzf)"
[[ "$fz_out" != *"Legacy key-bindings/completion sourcing"* ]] || { echo "FAIL - fzf flagged another tool's *completion.bash as legacy fzf sourcing" >&2; exit 1; }
[[ "$fz_out" == *"Syntax Previewer (bat): [CONFIGURED] (bat previews via FZF_CTRL_T_OPTS"* ]] || { echo "FAIL - fzf missed bat preview in FZF_CTRL_T_OPTS" >&2; exit 1; }
[[ "$fz_out" == *"FZF_DEFAULT_COMMAND: rg --files --hidden (from startup file"* ]] || { echo "FAIL - fzf did not fall back to ~/.bashrc for FZF_DEFAULT_COMMAND" >&2; exit 1; }
[[ "$fz_out" == *"Search Generator (ripgrep): [CONFIGURED]"* ]] || { echo "FAIL - fzf did not use the startup-file FZF_DEFAULT_COMMAND" >&2; exit 1; }
zs_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin2:$PATH" HOME="$WORK/home" LANG=C _SO_DETECTED_THREADS=4 bash "$ROOT/scripts/target-inspect.sh" zstd)"
[[ "$zs_out" == *"Threads: [WARNING] 999 exceeds the 4 hardware thread(s)"* ]] || { echo "FAIL - zstd did not warn on ZSTD_NBTHREADS above the thread count" >&2; exit 1; }
rm -f "$WORK/home/.bashrc"
echo "ok   - env fallback to startup files, fzf legacy/bat detection, zstd thread check"

printf 'x\n' > "$WORK/home/.local/share/zoxide/db.zo"
chmod 644 "$WORK/home/.local/share/zoxide/db.zo"; chmod 700 "$WORK/home/.local/share/zoxide"
zo_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" zoxide)"
[[ "$zo_out" == *"db.zo (mode: 644, dir: 700 [OK])"* ]] || { echo "FAIL - db.zo in a 0700 directory still gets a 0600 recommendation" >&2; exit 1; }
chmod 755 "$WORK/home/.local/share/zoxide"
zo_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" zoxide)"
[[ "$zo_out" == *"db.zo (mode: 644 -> recommend 0600"* ]] || { echo "FAIL - db.zo in a 0755 directory is not flagged" >&2; exit 1; }
rm -rf "$WORK/home/.local/share/zoxide"
echo "ok   - permission tags accept a 0700 parent directory and still flag an open one"

mkdir -p "$WORK/home/.config" "$WORK/home/.local/share/konsole" "$WORK/home/.librewolf"
printf -- '--ozone-platform=wayland # native wayland\n# whole-line comment\n--enable-gpu-rasterization\n' > "$WORK/home/.config/brave-flags.conf"
br_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" brave)"
[[ "$br_out" == *"Inline Comments: [WARNING]"* && "$br_out" == *"brave-flags.conf:1:--ozone-platform=wayland # native wayland"* ]] || { echo "FAIL - brave did not flag an inline # comment in brave-flags.conf" >&2; exit 1; }
printf 'defaultPref("media.hardware-video-decoding.force-enabled", true);\n' > "$WORK/home/.librewolf/librewolf.overrides.cfg"
lw_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" librewolf)"
[[ "$lw_out" == *"librewolf.overrides.cfg"* && "$lw_out" == *"Hardware Video Decoding: [OK]"* ]] || { echo "FAIL - librewolf ignored librewolf.overrides.cfg" >&2; exit 1; }
printf '[Desktop Entry]\nDefaultProfile=Main.profile\n' > "$WORK/home/.config/konsolerc"
printf '[Scrolling]\nHistoryMode=2\n' > "$WORK/home/.local/share/konsole/Main.profile"
ks_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" konsole)"
[[ "$ks_out" == *"Scrollback: [WARNING] unlimited"* ]] || { echo "FAIL - konsole did not flag unlimited scrollback" >&2; exit 1; }
printf '[General]\nDays Meta Infos=365\nSave Meta Infos=true\n' > "$WORK/home/.config/katerc"
kt_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" kate)"
[[ "$kt_out" == *"Document Meta History: [NOTE] kept 365 day(s)"* ]] || { echo "FAIL - kate did not read 'Days Meta Infos' (INI key with spaces)" >&2; exit 1; }
rm -rf "$WORK/home/.config/brave-flags.conf" "$WORK/home/.librewolf" "$WORK/home/.config/konsolerc" "$WORK/home/.local/share/konsole" "$WORK/home/.config/katerc"
echo "ok   - brave inline comments, librewolf overrides, konsole scrollback, and kate INI keys are inspected"

# python_ok: a runtime-manager warning before the version line is still a Python
printf '#!/usr/bin/env bash\necho "mise WARN some notice" >&2\necho "Python 3.15.2"\n' > "$WORK/bin2/python3"
chmod +x "$WORK/bin2/python3"
py_out="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/bin2:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" python3)"
[[ "$py_out" == *"Status: INSTALLED"* && "$py_out" != *"Microsoft Store"* ]] || { echo "FAIL - python3 with a warning before 'Python 3.x' was not recognized" >&2; exit 1; }
echo "ok   - python_ok accepts a version line after a runtime-manager warning"

# stremio: Flatpak server-settings.json parsing, LIBVA_DRIVER_NAME override check, dir/file perm tags, and detection
mkdir -p "$WORK/home/.var/app/com.stremio.Stremio/.stremio-server" "$WORK/home/.local/share/flatpak/overrides"
chmod 755 "$WORK/home/.var/app/com.stremio.Stremio/.stremio-server"
cat > "$WORK/home/.var/app/com.stremio.Stremio/.stremio-server/server-settings.json" <<'EOF'
{
    "serverVersion": "4.22.6",
    "cacheSize": null,
    "btMaxConnections": 500,
    "btDownloadSpeedSoftLimit": 2621440,
    "btDownloadSpeedHardLimit": 3670016,
    "remoteHttps": "https://remote.example",
    "localAddonEnabled": true,
    "transcodeHardwareAccel": false
}
EOF
chmod 644 "$WORK/home/.var/app/com.stremio.Stremio/.stremio-server/server-settings.json"
printf 'export LIBVA_DRIVER_NAME=i965\n' > "$WORK/home/.bashrc"
st_warn="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" stremio)"
for expected in \
  "cacheSize: [WARNING] unlimited (null)" \
  "btMaxConnections: [WARNING] 500" \
  "P2P Speed Limits: [NOTE] Default P2P speed cap" \
  "transcodeHardwareAccel: [NOTE] disabled" \
  "remoteHttps: [WARNING] remote HTTPS endpoint configured (https://remote.example)" \
  "localAddonEnabled: [NOTE] enabled" \
  "Flatpak LIBVA_DRIVER_NAME: [NOTE] Host sets LIBVA_DRIVER_NAME=i965"; do
  [[ "$st_warn" == *"$expected"* ]] || { echo "FAIL - stremio warning check missing: $expected" >&2; exit 1; }
done

chmod 700 "$WORK/home/.var/app/com.stremio.Stremio/.stremio-server"
cat > "$WORK/home/.var/app/com.stremio.Stremio/.stremio-server/server-settings.json" <<'EOF'
{
    "serverVersion": "4.22.6",
    "cacheSize": 2147483648,
    "btMaxConnections": 100,
    "btDownloadSpeedSoftLimit": 0,
    "btDownloadSpeedHardLimit": 0,
    "remoteHttps": "",
    "localAddonEnabled": false,
    "transcodeHardwareAccel": true
}
EOF
printf '[Environment]\nLIBVA_DRIVER_NAME=i965\n' > "$WORK/home/.local/share/flatpak/overrides/com.stremio.Stremio"
st_ok="$(env -i "${SO_TEST_ENV[@]}" PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" stremio)"
for expected in \
  "(mode: 644, dir: 700 [OK])" \
  "cacheSize: [OK] 2.00 GiB" \
  "btMaxConnections: [OK] 100" \
  "P2P Speed Limits: [OK]" \
  "transcodeHardwareAccel: [OK] enabled" \
  "remoteHttps: [OK] disabled" \
  "localAddonEnabled: [OK] disabled" \
  "Flatpak LIBVA_DRIVER_NAME: [OK] i965 forwarded in override"; do
  [[ "$st_ok" == *"$expected"* ]] || { echo "FAIL - stremio healthy check missing: $expected" >&2; exit 1; }
done
st_det="$(env -i "${SO_TEST_ENV[@]}" PATH="$WORK/deb" HOME="$WORK/home" LANG=C "$WORK/deb/bash" "$ROOT/scripts/detect-targets.sh" --json)"
[[ "$st_det" == *'"stremio"'* ]] || { echo "FAIL - detect-targets missed Flatpak stremio directory" >&2; exit 1; }
rm -rf "$WORK/home/.var" "$WORK/home/.local/share/flatpak" "$WORK/home/.bashrc"
echo "ok   - stremio detection, server-settings.json parsing, LIBVA override check, and perm tags verified"

echo "inspect-smoke: $count targets passed"
