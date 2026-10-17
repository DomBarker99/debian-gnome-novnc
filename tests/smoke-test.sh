#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:?Usage: tests/smoke-test.sh IMAGE ARTIFACT_DIRECTORY}
artifacts=${2:?Artifact directory required}
mkdir -p "$artifacts"
work=$(mktemp -d /tmp/gnome-image-smoke.XXXXXX)
# Newly created disposable test home/key; never touches a real user's home/key.
mkdir "$work/home"
ssh-keygen -q -t ed25519 -N '' -f "$work/id_ed25519"
chmod 0644 "$work/id_ed25519.pub"
password=$(openssl rand -hex 4)
if [[ -n ${GITHUB_ACTIONS:-} ]]; then printf '::add-mask::%s\n' "$password"; fi
first="gnome-smoke-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$$"
ssh_port=${SSH_TEST_PORT:-12222}
http_port=${HTTP_TEST_PORT:-16080}
ssh_args=(-i "$work/id_ed25519" -p "$ssh_port" -o BatchMode=yes
    -o IdentitiesOnly=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes
    -o "UserKnownHostsFile=$work/known_hosts")
second="${first}-replacement"
containers=()
finish() {
    local status=$?
    trap - EXIT
    for name in "${containers[@]}"; do
        docker logs "$name" > "$artifacts/${name}.log" 2>&1 || true
        docker stop --time 20 "$name" >/dev/null 2>&1 || true
    done
    exit "$status"
}
trap finish EXIT

# Confirm no public/default password exists, before starting the real test.
if docker run --name "${first}-missing-password" \
    --mount "type=bind,source=$work/id_ed25519.pub,target=/run/ssh-keys/authorized_keys,readonly" \
    "$image" > "$artifacts/missing-password.log" 2>&1; then
    echo 'Image incorrectly started without a password.' >&2
    exit 1
fi
grep -F 'runtime VNC_PASSWORD_FILE or VNC_PASSWORD is required' "$artifacts/missing-password.log"

docker run -d --name "$first" --shm-size=1g \
    -p "127.0.0.1:$http_port:6080" -p "127.0.0.1:$ssh_port:22" \
    -e VNC_PASSWORD="$password" \
    --mount "type=bind,source=$work/id_ed25519.pub,target=/run/ssh-keys/authorized_keys,readonly" \
    --mount "type=bind,source=$work/home,target=/home" "$image" >/dev/null
containers+=("$first")
for ((attempt=0; attempt<180; attempt++)); do
    status=$(docker inspect --format '{{.State.Status}}' "$first")
    [[ $status == running ]] || { docker logs "$first"; exit 1; }
    if docker exec "$first" desktop-healthcheck >/dev/null 2>&1; then break; fi
    sleep 2
done
docker exec "$first" desktop-healthcheck
curl --fail --silent "http://127.0.0.1:$http_port/vnc.html" | grep -i novnc >/dev/null

# Real SSH, not just a running daemon; retain strict host identity on replacement.
public_host_key=$(docker exec "$first" ssh-keygen -y -f /home/desktop/.local/state/sshd/ssh_host_ed25519_key)
printf '[127.0.0.1]:%s %s\n' "$ssh_port" "$public_host_key" > "$work/known_hosts"
ssh "${ssh_args[@]}" desktop@127.0.0.1 'set -eu
    test "$(id -u)" = 1000
    test "$HOME" = /home/desktop
    test "$(npm config get prefix)" = "$HOME/.local"
    test "$(command -v pi)" = "$HOME/.local/bin/pi"
    test "$(command -v codex)" = "$HOME/.local/bin/codex"
    test "$(locale charmap)" = UTF-8
    pi --version; codex --version; railway --version; infocmp xterm-ghostty >/dev/null
' > "$artifacts/ssh.log" 2>&1
docker exec "$first" /usr/sbin/sshd -T > "$artifacts/sshd-policy.log"
for policy in 'passwordauthentication no' 'kbdinteractiveauthentication no' 'permitrootlogin no' 'authenticationmethods publickey'; do
    grep -Fx "$policy" "$artifacts/sshd-policy.log"
done
docker exec "$first" bash -c 'test -z "$(find /etc/ssh -maxdepth 1 -name "ssh_host_*_key" -print)"'
# Fresh home has no generated standard folders before any application is launched.
docker exec --user 1000:1000 "$first" bash -c '
    for folder in Desktop Downloads Documents Music Pictures Public Templates Videos; do
        test ! -e "$HOME/$folder" || exit 1
    done
'

# Confirm that the browser-facing endpoint accepts a WebSocket upgrade.
HTTP_TEST_PORT="$http_port" python3 - <<'PY'
import os
import socket
with socket.create_connection(('127.0.0.1',int(os.environ['HTTP_TEST_PORT'])),timeout=10) as sock:
    sock.sendall(b'GET /websockify HTTP/1.1\r\nHost: localhost:16080\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: binary\r\n\r\n')
    result=sock.recv(4096)
    assert b'101 Switching Protocols' in result,result.split(b'\r\n')[0]
print('Browser WebSocket endpoint verified.')
PY

# A claimed window manager can precede the first completed GNOME frame. Launch
# a real application through the existing session, then wait for rendered pixels.
docker exec --user 1000:1000 "$first" bash -c '
export DBUS_SESSION_BUS_ADDRESS=$(< "$XDG_RUNTIME_DIR/session-bus.address")
gnome-terminal --title="Developer image smoke test" -- bash -c "echo Debian 13 GNOME developer desktop; echo; node --version; echo; echo Persistent home: /home/desktop; sleep 600"
'
terminal_ready=false
for ((attempt=0; attempt<30; attempt++)); do
    if docker exec "$first" bash -c '\
        for window in $(xprop -root _NET_CLIENT_LIST | grep -oE "0x[[:xdigit:]]+"); do
            if xprop -id "$window" _NET_WM_NAME | grep -F "Developer image smoke test" >/dev/null; then exit 0; fi
        done
        exit 1'; then
        terminal_ready=true
        break
    fi
    sleep 2
done
[[ $terminal_ready == true ]] || { echo 'GNOME Terminal did not create its application window.' >&2; exit 1; }
docker cp tests/vnc_probe.py "$first:/tmp/vnc_probe.py"
rendered=false
for ((attempt=0; attempt<45; attempt++)); do
    if docker exec -e VNC_TEST_PASSWORD="$password" "$first" python3 /tmp/vnc_probe.py > "$artifacts/vnc-probe.log" 2>&1; then
        rendered=true
        break
    fi
    sleep 2
done
docker cp "$first:/tmp/gnome-framebuffer.png" "$artifacts/gnome-framebuffer.png" || true
if [[ $rendered != true ]]; then
    echo 'Authenticated VNC did not produce a rendered desktop/application within 90 seconds.' >&2
    exit 1
fi

docker exec --user 1000:1000 -e PI_OFFLINE=1 -e PI_SKIP_VERSION_CHECK=1 "$first" bash -c '
set -Eeuo pipefail
for tool in codex pi node npm pnpm tsc tsx python python3 uv rustc cargo java javac mvn nvim nano tmux railway ssh sshfs tree-sitter kubectl talosctl docker docker-compose git gh rg fd fzf jq yq sops age pandoc pdftotext tesseract ffmpeg dot plantuml xelatex trash; do
    command -v "$tool" >/dev/null || { echo "Missing command: $tool"; exit 1; }
done
codex --version
pi --version
node --version
pnpm --version
tsc --version
python --version
uv --version
rustc --version
java -version
nvim --version | head -n 3
kubectl version --client -o yaml
talosctl version --client
yq --version
python3 - <<"PY"
import importlib
from pathlib import Path
for name in ["requests","httpx","rich","yaml","lxml","jinja2","numpy","scipy","matplotlib","PIL","pypdf","fpdf","reportlab","docx","pptx","odf","xlsxwriter","sympy","networkx","tiktoken","markdown","pytest","bs4","pandas","openpyxl"]:
    importlib.import_module(name)
print("All preloaded Python libraries imported.")
from docx import Document
from pptx import Presentation
from reportlab.pdfgen.canvas import Canvas
import xlsxwriter
import numpy as np
import matplotlib
matplotlib.use("Agg")
from matplotlib import pyplot as plt
folder = Path("/tmp/document-smoke")
folder.mkdir()
doc = Document(); doc.add_paragraph("DOCX smoke test"); doc.save(folder / "sample.docx")
slides = Presentation(); slides.slides.add_slide(slides.slide_layouts[6]); slides.save(folder / "sample.pptx")
book = xlsxwriter.Workbook(folder / "sample.xlsx"); book.add_worksheet().write(0, 0, "XLSX smoke test"); book.close()
pdf = Canvas(str(folder / "sample.pdf")); pdf.drawString(40, 40, "PDF smoke test"); pdf.save()
plt.plot(np.arange(5)); plt.savefig(folder / "plot.png"); plt.close()
assert all(path.stat().st_size > 100 for path in folder.iterdir())
print("DOCX, PPTX, XLSX, PDF and plot generation passed.")
PY
compile_dir=$(mktemp -d /tmp/compiler-smoke.XXXXXX)
printf "int main(void) { return 0; }\\n" > "$compile_dir/main.c"
gcc "$compile_dir/main.c" -o "$compile_dir/c-test"
"$compile_dir/c-test"
printf "fn main() {}\\n" > "$compile_dir/main.rs"
rustc "$compile_dir/main.rs" -o "$compile_dir/rust-test"
"$compile_dir/rust-test"
printf "public class ImageSmoke { public static void main(String[] args) {} }\\n" > "$compile_dir/ImageSmoke.java"
javac "$compile_dir/ImageSmoke.java"
java -cp "$compile_dir" ImageSmoke
node -e "console.log(\"Node execution passed.\")"
printf "persistent home proof\n" > "$HOME/projects/persistence-proof.txt"
mkdir -p "$HOME/.config/image-smoke"
printf "persistent config proof\n" > "$HOME/.config/image-smoke/config.txt"
nvim --headless "+lua local ok,err=pcall(function() local p=require(\"lazy.core.config\").plugins; assert(p.astrocore.dir:find(vim.env.HOME,1,true)==1); assert(require(\"astrocore\")) end); if not ok or vim.v.errmsg ~= \"\" then print(err); vim.cmd(\"cquit 1\") end" +qa
source /usr/local/share/tully-agent/versions.env
npm install -g --ignore-scripts --no-audit --no-fund "@earendil-works/pi-coding-agent@$PI_VERSION" "@openai/codex@$CODEX_VERSION"
test "$(pi --version)" = "$PI_VERSION"
codex --version | grep -F "$CODEX_VERSION"
' > "$artifacts/tool-versions.log" 2>&1

# A synthetic secret-file fixture in the disposable home tests the other input
# path. Never copy private keys or this password into retained CI artifacts.
printf '%s' "$password" | docker exec --user 1000:1000 -i "$first" bash -c '
    umask 077; mkdir -p "$HOME/.local/state/image-smoke"
    cat > "$HOME/.local/state/image-smoke/vnc-password"
'
ssh "${ssh_args[@]}" desktop@127.0.0.1 "tmux new-session -d -s smoke 'sleep 3; printf done > /home/desktop/projects/tmux-proof.txt'"
sleep 5
ssh "${ssh_args[@]}" desktop@127.0.0.1 'test "$(cat ~/projects/tmux-proof.txt)" = done'


# Replace the container, retaining only home: this simulates Pod replacement.
docker stop --time 30 "$first" >/dev/null
docker run -d --name "$second" --shm-size=1g \
    -p "127.0.0.1:$ssh_port:22" \
    -e VNC_PASSWORD_FILE=/home/desktop/.local/state/image-smoke/vnc-password \
    --mount "type=bind,source=$work/id_ed25519.pub,target=/run/ssh-keys/authorized_keys,readonly" \
    --mount "type=bind,source=$work/home,target=/home" "$image" >/dev/null
containers+=("$second")
for ((attempt=0; attempt<180; attempt++)); do
    [[ $(docker inspect --format '{{.State.Status}}' "$second") == running ]] || { docker logs "$second"; exit 1; }
    if docker exec "$second" desktop-healthcheck >/dev/null 2>&1; then break; fi
    sleep 2
done
docker exec "$second" desktop-healthcheck
docker exec --user 1000:1000 "$second" bash -c 'grep -Fx "persistent home proof" "$HOME/projects/persistence-proof.txt" && grep -Fx "persistent config proof" "$HOME/.config/image-smoke/config.txt"'
# Strict checking against the first container key also proves host-key persistence.
ssh "${ssh_args[@]}" desktop@127.0.0.1 'set -eu
    test -f ~/projects/tmux-proof.txt
    source /usr/local/share/tully-agent/versions.env
    test "$(pi --version)" = "$PI_VERSION"
    codex --version | grep -F "$CODEX_VERSION"
    test "$(stat -c %u ~/.local/lib/node_modules/@openai/codex/package.json)" = 1000
' >> "$artifacts/ssh.log" 2>&1
docker cp tests/vnc_probe.py "$second:/tmp/vnc_probe.py"
docker exec -e VNC_TEST_PASSWORD="$password" "$second" python3 /tmp/vnc_probe.py > "$artifacts/vnc-replacement.log" 2>&1
echo 'GNOME, authenticated VNC/noVNC, key-only SSH, user upgrades, tmux and persistent-home replacement tests passed.'
