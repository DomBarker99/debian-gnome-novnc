#!/usr/bin/env bash
set -Eeuo pipefail
image=${1:?Usage: tests/smoke-test.sh IMAGE ARTIFACT_DIRECTORY}
artifacts=${2:?Artifact directory required}
mkdir -p "$artifacts"
work=$(mktemp -d /tmp/gnome-image-smoke.XXXXXX)
# Newly created disposable test home; never touches a real user's home.
mkdir "$work/home"
chmod 0777 "$work/home"
password=$(openssl rand -hex 4)
if [[ -n ${GITHUB_ACTIONS:-} ]]; then printf '::add-mask::%s\n' "$password"; fi
first="gnome-smoke-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
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
if docker run --name "${first}-missing-password" "$image" > "$artifacts/missing-password.log" 2>&1; then
    echo 'Image incorrectly started without a password.' >&2
    exit 1
fi
grep -F 'runtime VNC_PASSWORD_FILE or VNC_PASSWORD is required' "$artifacts/missing-password.log"

docker run -d --name "$first" --shm-size=1g \
    -p 127.0.0.1:16080:6080 \
    -e VNC_PASSWORD="$password" \
    --mount "type=bind,source=$work/home,target=/home/desktop" "$image" >/dev/null
containers+=("$first")
for ((attempt=0; attempt<180; attempt++)); do
    status=$(docker inspect --format '{{.State.Status}}' "$first")
    [[ $status == running ]] || { docker logs "$first"; exit 1; }
    if docker exec "$first" desktop-healthcheck >/dev/null 2>&1; then break; fi
    sleep 2
done
docker exec "$first" desktop-healthcheck
curl --fail --silent http://127.0.0.1:16080/vnc.html | grep -i novnc >/dev/null

# Confirm that the browser-facing endpoint accepts a WebSocket upgrade.
python3 - <<'PY'
import socket
with socket.create_connection(('127.0.0.1',16080),timeout=10) as sock:
    sock.sendall(b'GET /websockify HTTP/1.1\r\nHost: localhost:16080\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: binary\r\n\r\n')
    result=sock.recv(4096)
    assert b'101 Switching Protocols' in result,result.split(b'\r\n')[0]
print('Browser WebSocket endpoint verified.')
PY

# A claimed window manager can precede the first completed GNOME frame. Launch
# a real application through the existing session, then wait for rendered pixels.
docker exec "$first" bash -c '
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

docker exec -e PI_OFFLINE=1 -e PI_SKIP_VERSION_CHECK=1 "$first" bash -c '
set -Eeuo pipefail
for tool in codex pi node npm pnpm tsc tsx python python3 uv rustc cargo java javac mvn nvim tree-sitter kubectl talosctl docker docker-compose git gh rg fd fzf jq yq sops age pandoc pdftotext tesseract ffmpeg dot plantuml xelatex trash; do
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
' > "$artifacts/tool-versions.log" 2>&1

# Replace the container, retaining only home: this simulates Pod replacement.
docker stop --time 30 "$first" >/dev/null
printf '%s' "$password" > "$work/vnc-password"
chmod 0600 "$work/vnc-password"
sudo chown 1000:1000 "$work/vnc-password"
# The enclosing mktemp directory is private on the host; the test mount is
# read-only. Real deployments should use a managed Secret, not this test file.
docker run -d --name "$second" --shm-size=1g \
    -e VNC_PASSWORD_FILE=/run/secrets/vnc-password \
    --mount "type=bind,source=$work/vnc-password,target=/run/secrets/vnc-password,readonly" \
    --mount "type=bind,source=$work/home,target=/home/desktop" "$image" >/dev/null
containers+=("$second")
for ((attempt=0; attempt<180; attempt++)); do
    [[ $(docker inspect --format '{{.State.Status}}' "$second") == running ]] || { docker logs "$second"; exit 1; }
    if docker exec "$second" desktop-healthcheck >/dev/null 2>&1; then break; fi
    sleep 2
done
docker exec "$second" desktop-healthcheck
docker exec "$second" bash -c 'grep -Fx "persistent home proof" "$HOME/projects/persistence-proof.txt" && grep -Fx "persistent config proof" "$HOME/.config/image-smoke/config.txt"'
echo 'GNOME, authenticated VNC/noVNC, developer tools and persistent-home replacement test passed.'
