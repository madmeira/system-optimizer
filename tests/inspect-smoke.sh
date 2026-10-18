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

targets="bash bat btop cargo controld defender eza full fzf gh git herdr htop kde-plasma lazydocker lazygit
mise mpv neovim pacman pi podman powertoys pwsh ripgrep rustdesk security starship storage system topgrade
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

nv_out="$(env -i PATH="$WORK/bin:$PATH" HOME="$WORK/home" LANG=C bash "$ROOT/scripts/target-inspect.sh" neovim)"
for expected in \
  "Bytecode Loader (vim.loader.enable): [ENABLED]" \
  "Legacy Remote Providers (node/python3/perl/ruby): [DISABLED]" \
  "Treesitter Config Compatibility: [WARNING]" \
  "Neoconf Schema (.neoconf.json): [DEPRECATED KEY]" \
  "Dynamic Project Env Sync (DirChanged -> mise env --json): [ACTIVE]" \
  "Mason LazyVim Extra Lock (opts_extend = {} & mason = false): [LOCKED]"; do
  if [[ "$nv_out" != *"$expected"* ]]; then
    echo "FAIL - neovim synergy check missing: $expected" >&2
    exit 1
  fi
done
echo "ok   - neovim + mise synergy and LazyVim v15 checks verified"
echo "inspect-smoke: $count targets passed"
