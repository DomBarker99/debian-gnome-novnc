#!/usr/bin/env bash
set -Eeuo pipefail
source /usr/local/share/debian-gnome-novnc/versions.env
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
    --requirement /usr/local/share/debian-gnome-novnc/packages/python.txt
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

npm ci --prefix /opt/node-cli --ignore-scripts --omit=dev --no-audit --no-fund --registry=https://registry.npmjs.org
# Record the actual Debian packages without copying any host inventory or state.
dpkg-query -W -f='${Package}\t${Version}\n' > /usr/local/share/debian-gnome-novnc/debian-package-versions.tsv
