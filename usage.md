# Debian 13 GNOME developer desktop

A Linux/amd64 container image based on **debian:13**, not slim. It installs the full Debian GNOME desktop, TigerVNC and noVNC, software graphics rendering, development SDKs, Codex CLI and Pi. There are no Kubernetes manifests in this repository.

Image: `ghcr.io/dombarker99/debian-gnome-novnc:13`

Source: https://github.com/DomBarker99/debian-gnome-novnc

## What is preinstalled

- Full GNOME 48, its desktop applications and LibreOffice; Firefox ESR, Chromium and Inkscape.
- Node 24, npm, pnpm, TypeScript and tsx.
- Codex CLI 0.162.1 and Pi 1.1.0, with their npm dependency graph locked.
- Developer Python 3.14 and common data, document, image, HTTP and test libraries. Debian's `/usr/bin/python3` is preserved for system applications.
- Rust/Cargo, JDK 25, Maven, GCC/G++, Clang/LLVM, CMake, Ninja, GDB and LLDB; common native development headers.
- Neovim 0.12, tmux, ripgrep, fd, fzf, Git/Git LFS, GitHub CLI, lazygit, delta and glow.
- kubectl 1.37, talosctl 1.14, Mike Farah yq v4, jq, SOPS, age, GnuPG and SSH client.
- Docker client and Compose. **No Docker daemon, Docker socket or privileged access is provided.**
- PDF, Office-document, image, OCR, audio/video, diagram and practical LaTeX tools.
- Man pages, locales, fonts, shell completion, network diagnostics, archives and a Linux trash utility.

Exact lists: [APT packages](packages/apt.txt), [Python packages](packages/python.txt), [Node CLI tools](packages/node/package.json), [SDK versions and checksums](versions.env). The image also records the actual Debian package versions at `/usr/local/share/debian-gnome-novnc/debian-package-versions.tsv`.

Heavy ML/model stacks, extra agents, provider-specific cloud CLIs, virtualization and CAD are not included in the baseline. No Mac binaries, private source, user profiles, credentials or history are copied into the image.

## Run a desktop locally

Create a password file outside this repository. Classic VNC authentication supports only eight bytes, so this image requires **exactly eight non-space printable ASCII characters** and rejects silent truncation. There is no default password.

For a password file already at `/absolute/private/path/vnc-password`:

```bash
docker run -d --name debian-gnome \
  --shm-size=1g \
  -p 127.0.0.1:6080:6080 \
  --mount type=volume,source=debian-gnome-home,target=/home/desktop \
  --mount type=bind,source=/absolute/private/path/vnc-password,target=/run/secrets/vnc-password,readonly \
  -e VNC_PASSWORD_FILE=/run/secrets/vnc-password \
  ghcr.io/dombarker99/debian-gnome-novnc:13
```

Open http://localhost:6080/vnc.html and enter the runtime password. The named Docker volume is initialized from the image on first use. Bind mounts and Kubernetes volumes instead need appropriate ownership/permissions.

`VNC_PASSWORD` is also supported for convenience, but a mounted secret file avoids storing the cleartext password in container environment metadata. Set only one of the two variables. Passwords are never build arguments, source files or image defaults.

`VNC_RESOLUTION` defaults to `1600x1000`; supported bounds are 640–4096 pixels wide and 480–2160 pixels high. Native VNC listens only on container localhost; the browser-facing noVNC server listens on port 6080. No native VNC port is exposed.

Keep browser access behind localhost port-forwarding, a VPN or an appropriately authenticated TLS gateway. This image is **not an internet-facing desktop service**. GNOME screen locking is disabled because the container account has no PAM login password; VNC authentication remains required.

## Persistent home and agents

The desktop runs as UID/GID **1000:1000**, with home `/home/desktop`. A future Kubernetes workload can mount its PVC there and arrange writable ownership, for example with `fsGroup: 1000`. A completely empty home volume is supported; startup creates user directories. No workload is deployed by this repository.

Home persistence retains projects, user settings, caches, project virtual environments, `node_modules`, and normally:

- `~/.codex`: Codex settings, sessions and file-based credentials.
- `~/.pi/agent`: Pi settings, sessions, extensions and saved credentials.
- `~/.cargo`: Cargo downloads and user-installed Rust programs.
- `~/.local`: user-installed utilities; npm's user installation prefix.

Authenticate separately inside the running environment. Existing host credentials are not imported. Anyone with access to this home volume or the container account can access credentials stored there; do not share that volume with untrusted workloads.

The image installs the Linux Pi CLI, not a copy of the Mac application or its native computer-use integrations. Additional extensions/integrations require separate configuration.

Runtime system-wide APT installs modify the container's disposable filesystem and **do not survive replacement**. Add lasting system dependencies to `packages/apt.txt` and rebuild. Project lockfile dependencies should be installed in the project beneath persistent home. Preinstalled libraries do not override a project's requested versions.

Preinstalled Rust toolchains live in `/opt/rustup`; Cargo's user cache stays in home. Update the image for new system SDK versions. A separately configured user Rustup installation is another option when persistent per-user toolchains are required.

`desktop` has passwordless sudo **inside the container** for development convenience. Do not use privileged mode or mount the host Docker socket simply to make tools work. The container is not a VM: hardware control, display managers, systemd-managed services and some desktop settings may be unavailable. GNOME uses a container-local system-type D-Bus instance; it does not connect to the host bus or activate privileged host services.

A 5 GiB home volume is suitable for a small test but may be insufficient for multiple development projects, dependency caches and build outputs. The image itself uses the node's image storage, not the home PVC.

## Run a CLI without starting the desktop

Any command other than the default `desktop` command runs directly, without requiring a VNC password:

```bash
docker run -it --name codex-session \
  --mount type=volume,source=debian-gnome-home,target=/home/desktop \
  ghcr.io/dombarker99/debian-gnome-novnc:13 codex
```

Use `pi` in place of `codex` for Pi. Desktop-only health checks do not apply to a CLI-only container.

## Build and publishing

```bash
docker build --platform linux/amd64 -t debian-gnome-novnc:local .
```

CI builds on pushes to `main`, pull requests, manual dispatch and a weekly schedule. It checks GNOME Shell's window manager, authenticated VNC framebuffer rendering, HTTP/WebSocket noVNC access, developer tools and Python imports, then replaces the test container to verify persistent home. Test screenshots and logs are retained as short-lived Actions artifacts.

Only a successfully tested image is pushed to GHCR, under `13`, `latest` and a commit-specific `sha-…` tag. The first push creates the GHCR package. GitHub initially makes the package private; its visibility must be changed to public once in package settings. This cannot subsequently be reversed to private.

The workflow's `GITHUB_TOKEN` authenticates publication; it is never passed to the image build. Kubernetes needs no `imagePullSecret` once the package is public. No secrets are required for building or the isolated tests.

APT receives current Debian security packages during scheduled rebuilds. SDK/direct-Python versions are pinned and require reviewed updates; weekly builds do not silently upgrade those pins. Upstream executable downloads are SHA-256 checked, and npm transitive versions/integrities are recorded in the lockfile. Third-party software retains its own licenses and notices.
