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

targets="bash bat btop cargo controld defender eza fd full fzf gh git herdr htop kde-plasma lazydocker lazygit
mise mpv neovim pacman pi podman powertoys pwsh ripgrep rustdesk security sqlite3 starship storage syncthing system topgrade
windows-terminal winget wsl yay yt-dlp zoxide network chrome edge python"
failed=0; count=0
for t in $targets; do
  count=$((count + 1))
  if env -i PATH="$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" "$t" > "$WORK/out" 2> "$WORK/err"; then rc=0; else rc=$?; fi
  if [[ "$rc" -ne 0 || -s "$WORK/err" ]]; then
    failed=$((failed + 1))
    echo "FAIL - target '$t': exit $rc, stderr: $(head -n 2 "$WORK/err" | cut -c1-200)" >&2
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "inspect-smoke: $failed of $count targets failed" >&2
  exit 1
fi
echo "ok   - all $count targets run to the end without errors"

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
printf "alias ls='ls --color'\nalias a=task-run-beta\n" > "$WORK/remote/.zshrc"
out="$(env -i PATH="$WORK/ssh:$PATH" HOME="$WORK/home" FAKE_REMOTE="$WORK/remote" bash "$ROOT/scripts/host-diff.sh" fakehost)"
for leaked in "sk-abc12345678" "pw0rd"; do
  [[ "$out" != *"$leaked"* ]] || { echo "FAIL - host-diff printed a secret: $leaked" >&2; exit 1; }
done
for expected in "[DIFFERENT] .zshrc" "export OPENAI=<value hidden>" "export EDITOR=nvim" "alias ls='eza --icons=auto'" \
                "alias a=task-run-alpha" "alias a=task-run-beta"; do
  [[ "$out" == *"$expected"* ]] || { echo "FAIL - host-diff output missing: $expected" >&2; exit 1; }
done
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
echo "inspect-smoke: $count targets passed"
