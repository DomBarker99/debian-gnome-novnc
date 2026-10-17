#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/share/tully-agent/versions.env
[[ $(dpkg --print-architecture) == amd64 ]] || { echo 'This image currently targets Linux/amd64.' >&2; exit 1; }
work=$(mktemp -d /tmp/image-tools.XXXXXX)

fetch() {
    local url=$1 checksum=$2 output=$3
    curl --fail --location --retry 3 --connect-timeout 20 --max-time 300 --output "$output" "$url"
    printf '%s  %s\n' "$checksum" "$output" | sha256sum --check --strict
}

fetch "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" "$NODE_SHA256" "$work/node.tar.xz"
tar -xJf "$work/node.tar.xz" --strip-components=1 -C /usr/local

fetch "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" "$UV_SHA256" "$work/uv.tar.gz"
tar -xzf "$work/uv.tar.gz" -C "$work"
install -m 0755 "$work/uv-x86_64-unknown-linux-gnu/uv" /usr/local/bin/uv
install -m 0755 "$work/uv-x86_64-unknown-linux-gnu/uvx" /usr/local/bin/uvx
UV_PYTHON_INSTALL_DIR=/opt/python UV_PYTHON_CACHE_DIR="$work/python-cache" uv python install "$PYTHON_VERSION"
python_bin=$(find /opt/python -path "*/bin/python${PYTHON_VERSION%.*}" -type f -print -quit)
[[ -n "$python_bin" ]] || { echo 'Developer Python installation missing.' >&2; exit 1; }
ln -s "$python_bin" /usr/local/bin/python
ln -s "$python_bin" /usr/local/bin/python3
# Only the isolated /opt Python is modified; Debian /usr/bin/python3 stays intact.
uv pip install --python "$python_bin" --system --break-system-packages \
    --only-binary=numpy,scipy,matplotlib,lxml,Pillow,pandas \
    --requirement /usr/local/share/tully-agent/packages/python.txt
ln -s "$(dirname "$python_bin")/pip" /usr/local/bin/pip
ln -s "$(dirname "$python_bin")/pip3" /usr/local/bin/pip3

fetch "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" "$RUSTUP_SHA256" "$work/rustup-init"
chmod 0755 "$work/rustup-init"
RUSTUP_HOME=/opt/rustup CARGO_HOME="$work/cargo" "$work/rustup-init" -y --no-modify-path --profile default --default-toolchain "$RUST_VERSION"
install -m 0755 "$work/cargo/bin/rustup" /usr/local/bin/rustup
for tool in cargo rustc rustdoc rustfmt cargo-fmt cargo-clippy clippy-driver; do
    ln -s /usr/local/bin/rustup "/usr/local/bin/$tool"
done

fetch "https://github.com/adoptium/temurin25-binaries/releases/download/${JAVA_TAG}/OpenJDK25U-jdk_x64_linux_hotspot_${JAVA_RELEASE}.tar.gz" "$JAVA_SHA256" "$work/java.tar.gz"
mkdir -p /opt/java
tar -xzf "$work/java.tar.gz" --strip-components=1 -C /opt/java

fetch "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-x86_64.tar.gz" "$NEOVIM_SHA256" "$work/neovim.tar.gz"
mkdir -p /opt/neovim
tar -xzf "$work/neovim.tar.gz" --strip-components=1 -C /opt/neovim
ln -s /opt/neovim/bin/nvim /usr/local/bin/nvim

fetch "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" "$KUBECTL_SHA256" "$work/kubectl"
install -m 0755 "$work/kubectl" /usr/local/bin/kubectl
fetch "https://github.com/siderolabs/talos/releases/download/v${TALOS_VERSION}/talosctl-linux-amd64" "$TALOS_SHA256" "$work/talosctl"
install -m 0755 "$work/talosctl" /usr/local/bin/talosctl
fetch "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" "$YQ_SHA256" "$work/yq"
install -m 0755 "$work/yq" /usr/local/bin/yq
fetch "https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}/sops-v${SOPS_VERSION}.linux.amd64" "$SOPS_SHA256" "$work/sops"
install -m 0755 "$work/sops" /usr/local/bin/sops
fetch "https://github.com/tree-sitter/tree-sitter/releases/download/v${TREE_SITTER_VERSION}/tree-sitter-linux-x64.gz" "$TREE_SITTER_SHA256" "$work/tree-sitter.gz"
gzip -dc "$work/tree-sitter.gz" > /usr/local/bin/tree-sitter
chmod 0755 /usr/local/bin/tree-sitter
ln -s /usr/bin/fdfind /usr/local/bin/fd

# Developer CLIs stay system-wide; Pi/Codex use a standard npm-global seed.
# First boot copies each agent package into the user's persistent ~/.local prefix.
npm install -g --prefix /usr/local --ignore-scripts --no-audit --no-fund \
    "pnpm@$PNPM_VERSION" "tsx@$TSX_VERSION" "typescript@$TYPESCRIPT_VERSION"
npm install -g --prefix /usr/local/share/agent-cli-seed --ignore-scripts --include=optional --no-audit --no-fund \
    "@earendil-works/pi-coding-agent@$PI_VERSION" "@openai/codex@$CODEX_VERSION"

# Binary only: do not run Railway's optional agent/MCP setup installer.
fetch "https://github.com/railwayapp/cli/releases/download/v${RAILWAY_VERSION}/railway-v${RAILWAY_VERSION}-x86_64-unknown-linux-gnu.tar.gz" \
    "$RAILWAY_SHA256" "$work/railway.tar.gz"
tar -xzf "$work/railway.tar.gz" -C "$work"
install -m 0755 "$work/railway" /usr/local/bin/railway

# Ghostty terminfo and a server-side Nerd Font fallback for AstroNvim.
tic -x -o /usr/share/terminfo /usr/local/share/tully-agent/assets/xterm-ghostty.terminfo
fetch "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/NerdFontsSymbolsOnly.zip" \
    "$NERD_FONT_SHA256" "$work/nerd-symbols.zip"
mkdir -p /usr/local/share/fonts/nerd-symbols
unzip -q "$work/nerd-symbols.zip" -d /usr/local/share/fonts/nerd-symbols
fc-cache -f

# Preinstall the AstroNvim core so a new home does not need a first-launch download.
home_seed=/usr/local/share/agent-home-seed
mkdir -p "$home_seed/config/nvim" "$home_seed/data/nvim/lazy/lazy.nvim"
sed -e "s/@ASTRONVIM_VERSION@/$ASTRONVIM_VERSION/g" -e "s/@LAZY_VERSION@/$LAZY_VERSION/g" \
    /usr/local/share/tully-agent/assets/astronvim-init.lua > "$home_seed/config/nvim/init.lua"
# Lazy records Git revisions in its lockfile, so its seed needs real Git metadata.
git clone --filter=blob:none --branch "$LAZY_VERSION" https://github.com/folke/lazy.nvim.git "$home_seed/data/nvim/lazy/lazy.nvim"
test "$(git -C "$home_seed/data/nvim/lazy/lazy.nvim" rev-parse HEAD)" = "$LAZY_COMMIT"
export XDG_CONFIG_HOME="$home_seed/config" XDG_DATA_HOME="$home_seed/data"
export XDG_STATE_HOME="$work/nvim-state" XDG_CACHE_HOME="$work/nvim-cache"
nvim --headless '+Lazy! sync' '+lua if vim.v.errmsg ~= "" then print(vim.v.errmsg); vim.cmd("cquit 1") end' +qa
nvim --headless '+lua for _,m in ipairs({"astrocore","astroui","astrolsp"}) do if not pcall(require,m) then vim.cmd("cquit 1") end end; if vim.v.errmsg ~= "" then print(vim.v.errmsg); vim.cmd("cquit 1") end' +qa

PATH=/usr/local/share/agent-cli-seed/bin:$PATH PI_OFFLINE=1 PI_TELEMETRY=0 pi --version
/usr/local/share/agent-cli-seed/bin/codex --version
railway --version
infocmp xterm-ghostty >/dev/null
# Record versions without copying host inventory, user profiles, or credentials.
dpkg-query -W -f='${Package}\t${Version}\n' > /usr/local/share/tully-agent/debian-package-versions.tsv
