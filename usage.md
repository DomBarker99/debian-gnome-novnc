# Debian 13 GNOME developer desktop with SSH and noVNC

Linux/amd64 Debian 13 with selected GNOME components, Firefox ESR, development SDKs, key-only SSH, and browser desktop access. GNOME, SSH logins and developer tools run as **desktop, UID/GID 1000:1000**. Root is used only for bootstrap and the SSH listener. No Kubernetes workload is deployed by this repository.

- Image: `ghcr.io/dombarker99/debian-gnome-novnc:13`
- Source: https://github.com/DomBarker99/debian-gnome-novnc
- CI: https://github.com/DomBarker99/debian-gnome-novnc/actions/workflows/build-image.yml
- Prefer a tested immutable digest or `sha-<12-character-commit>` tag for repeatable deployment. `13` and `latest` move after successful main-branch CI; pushing source does not update an already digest-pinned workload.

## What is preinstalled

- Selected GNOME Shell/session/settings components, Terminal, Text Editor, Calculator, Files, Firefox ESR and Inkscape. Optional autostarts are suppressed while retaining GNOME appearance. This is not the old full `gnome` metapackage image; Chromium is not included.
- Pi 1.3.0 and Codex 0.163.0, seeded into each private home's normal npm-global prefix, `~/.local`. No provider credentials, extensions or Mac-native computer-use integration are imported.
- GitHub CLI, Railway CLI 5.70.0 (binary only; optional agent/MCP setup is not run), OpenSSH server/client, tmux, SSHFS/FUSE utilities, Nano, AstroNvim v6.1.1 with Neovim 0.12.5, Ghostty terminfo and a Nerd Font fallback.
- Node 24, npm, pnpm, TypeScript and tsx; developer Python 3.14 and document/data/image libraries. Debian's `/usr/bin/python3` remains intact.
- Rust/Cargo, JDK 25, Maven, GCC/G++, Clang/LLVM, CMake, Ninja, GDB and LLDB, plus common development headers.
- kubectl, talosctl, yq, jq, SOPS, age, Git/Git LFS, lazygit, delta, glow, ripgrep, fd and fzf.
- Docker client and Compose, **not a Docker daemon or host socket**.
- LibreOffice Writer and Calc (GUI and headless PDF export); Pillow for Debian's `/usr/bin/python3`.
- PDF, Office-document, image, OCR, audio/video, diagram and practical LaTeX tools; man pages, locales, fonts, network diagnostics, archives and a trash utility.

Sources: [APT packages](packages/apt.txt), [Python packages](packages/python.txt), [SDK/tool versions and checksums](versions.env), [installer](scripts/install-tools.sh), [AstroNvim seed](assets/astronvim-init.lua). Actual Debian versions are recorded in the image at `/usr/local/share/tully-agent/debian-package-versions.tsv`.

The old `packages/node/` lockfile and `scripts/system-bus.conf` remain historical files; this Dockerfile no longer consumes them. Current CLI pins are in `versions.env`; the active bus configuration is `config/system-bus.conf`.

## Runtime configuration

Configure each agent independently. Never bake credentials into build arguments or commit them to source.

| Input | Purpose |
| --- | --- |
| `VNC_RESOLUTION` | Initial desktop size; default `1600x1000`. Bounds: width 640–4096, height 480–2160. |
| `VNC_PASSWORD` | Runtime desktop password supplied as an environment variable. Visible to anyone allowed to inspect the container's environment. |
| `VNC_PASSWORD_FILE` | Alternative: readable mounted secret-file path. Set exactly one password input, not both. |
| `/run/ssh-keys/authorized_keys` | Read-only mounted SSH **public** keys. Bootstrap copies them into root-controlled runtime state. An existing `~/.ssh/authorized_keys` is also supported when no mount is supplied. |
| `/home` | Persistent private home volume, containing `/home/desktop`. Do not share one agent's home between concurrent agents. |

There is **no default VNC password**. Classic VNC authentication uses eight bytes: this image requires exactly **eight non-space printable ASCII characters**, rejecting silent truncation. It is not a substitute for secure transport.

SSH accepts public keys only. Root, password and keyboard-interactive logins are disabled. Do not distribute the operator's private SSH key to agents. Public-key injection and a VNC password are required for the default desktop command; a CLI-only command needs neither.

## Run locally with Docker

Create a private VNC password file outside this repository, readable by container UID/GID 1000. Do not make a credential file world-readable to bypass ownership errors. Replace `/absolute/private/path/vnc-password` below with that path.

```bash
docker run -d --name debian-agent \
  --shm-size=512m \
  -p 127.0.0.1:2221:22 \
  -p 127.0.0.1:6081:6080 \
  --mount type=volume,source=debian-agent-home,target=/home \
  --mount type=bind,source="$HOME/.ssh/id_ed25519.pub",target=/run/ssh-keys/authorized_keys,readonly \
  --mount type=bind,source=/absolute/private/path/vnc-password,target=/run/secrets/vnc-password,readonly \
  -e VNC_PASSWORD_FILE=/run/secrets/vnc-password \
  -e VNC_RESOLUTION=1600x1000 \
  ghcr.io/dombarker99/debian-gnome-novnc:13
```

SSH: `ssh -p 2221 desktop@127.0.0.1`

Browser: http://localhost:6081/vnc.html — enter the chosen VNC password.

For an environment-only password, replace the password-file mount and `VNC_PASSWORD_FILE` argument with `-e VNC_PASSWORD`, supplying its value through your local runtime environment rather than a literal command saved in shell history. Do not configure both inputs.

Native VNC stays bound to container-localhost on port 5901. Browser noVNC listens on container port 6080; SSH listens on port 22. `EXPOSE` is metadata, not an instruction to publish these ports publicly.

## Kubernetes access: local port-forwarding

Use existing workload resources. Substitute the namespace and Deployment name; this is an access command, not a deployment manifest:

```bash
kubectl --context admin@tully_cloud -n AGENT_NAMESPACE \
  port-forward --address 127.0.0.1 deployment/AGENT_NAME 2221:22 6081:6080
```

Leave that command running, then in another terminal:

```bash
ssh -p 2221 desktop@127.0.0.1
ssh -t -p 2221 desktop@127.0.0.1 'tmux new-session -A -s work'
```

Open http://localhost:6081/vnc.html. This requires neither a NodePort nor an SSH tunnel for browser access. Use another local pair, for example `2222:22 6082:6080`, for a second agent. The same local SSH port should consistently identify the same agent/home so known-host verification remains meaningful.

The port-forward process needs cluster access and must remain running. It can exit on laptop sleep, network loss or Pod replacement; rerun it and reconnect. tmux keeps work running after client disconnection, **not** after container/Pod termination. Detach with `Ctrl-b`, then `d`.

Keep access local or behind a trusted VPN/authenticated TLS gateway. This is **not an internet-facing desktop service**. GNOME screen locking is disabled; VNC authentication remains mandatory.

### Display sizing

GNOME initially enters Activities Overview; press `Esc` or Super to return to the desktop. In noVNC settings, prefer **Scaling Mode → Local Scaling** with a fixed `VNC_RESOLUTION` if remote resizing produces clipping or stale redraws. Local Scaling fits the existing framebuffer without changing the remote monitor size. A browser reconnect may clear a stale canvas; persistent rendering faults need separate diagnosis.

## Persistence, ownership and upgrades

Mount the private volume at **`/home`**, not the old image's `/home/desktop` path. Bootstrap creates `/home/desktop` as UID/GID 1000 with mode 0700 and seeds absent tools/configuration. For Kubernetes, `fsGroup: 1000` with `fsGroupChangePolicy: OnRootMismatch` is the validated arrangement; do not recursively loosen permissions on persistent SSH host keys.

This is a changed startup/storage contract from the previous image. **Review migration before attaching an existing old home/PVC.** Publishing this image does not migrate any deployment or data.

For the planned official agents, allocate **50 GiB per private home PVC** and one independent home per agent. This is a planning requirement, not a resize performed by this repository. Shared project files are a separate mount, not shared Firefox/CLI credential state.

Persistent home retains projects, configuration, Firefox profiles/key material, npm installations, caches and normally:

- `~/.pi/agent`: Pi settings, sessions, extensions and file-based credentials.
- `~/.codex`: Codex settings, sessions and file-based credentials.
- `~/.local`: user tools, npm-global packages and application data.
- `~/.config/nvim` and `~/.local/share/nvim`: seeded AstroNvim configuration/plugins.
- `~/.local/state/sshd`: runtime-generated SSH host identity, intentionally **root-owned and private**. Never export its private key or relax permissions.

Pi/Codex and AstroNvim seeds initialize only absent user locations; existing upgrades and personal editor configurations are not overwritten by a new image. New homes suppress automatic standard XDG folders; Firefox itself may still create `Downloads`.

Inside the agent, normal unprivileged upgrades work:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
npm install -g --ignore-scripts @openai/codex@latest
```

Login manually inside the agent using the actual CLI's supported flow. GitHub, Railway, Pi/Codex providers, Firefox accounts and password managers are not pre-authenticated. Anyone with access to the private home/container account may access stored service credentials.

System-wide APT changes live in the disposable container filesystem and do not survive replacement. Add durable system dependencies to `packages/apt.txt` and rebuild. Project dependencies belong with their project/lockfiles in persistent home. Rust's image toolchains live in `/opt/rustup`; user Cargo state stays in home.

`desktop` has passwordless sudo inside the container. Do not add privileged mode, a host Docker socket or Kubernetes API credentials merely to make developer tools work. SSHFS tools are installed, but FUSE device access and mounts are **not** configured by the image. GNOME uses a container-local system-type D-Bus, not the host bus.

The simple existing desktop lifetime is retained: a desktop service exit ends the container and its running processes. Checkpoints/session recovery are still necessary for long-running work; tmux does not protect against Pod replacement.

## Run a CLI without starting the desktop

Any command other than the default `desktop` runs after home initialization as UID/GID 1000, without SSH or VNC startup:

```bash
docker run -it --name pi-session \
  --mount type=volume,source=debian-agent-home,target=/home \
  ghcr.io/dombarker99/debian-gnome-novnc:13 pi
```

Use `codex` or another command as needed. Do not run concurrent containers against the same private home. Desktop health checks do not apply to a CLI-only container.

## Build, test and publication

```bash
docker build --platform linux/amd64 -t debian-gnome-novnc:local .
bash tests/smoke-test.sh debian-gnome-novnc:local /tmp/UNIQUE-TEST-DIRECTORY/artifacts
```

Use a unique pre-created `/tmp` directory for test evidence. Tests create their own disposable home and SSH key, publish only localhost ports, and stop their test containers. They leave test data/stopped containers for inspection; no Docker pruning or unrelated cleanup is performed. Tests require Docker, an SSH client, OpenSSL, curl and Python 3 on the host. `SSH_TEST_PORT`/`HTTP_TEST_PORT` override default host ports 12222/16080 if needed.

CI runs on `main` pushes, pull requests, manual dispatch and a weekly schedule. It builds Linux/amd64, then checks:

- GNOME window-manager health, a real Terminal window, password-authenticated rendered VNC and HTTP/WebSocket noVNC.
- Actual SSH as UID 1000, noninteractive PATH, UTF-8, key-only policy, Ghostty terminfo and tmux disconnect survival.
- Developer/Python/document/compiler tools, user-owned Pi/Codex reinstall, and AstroNvim loading from home.
- Container replacement with the same home: user files, upgraded packages, strict SSH host identity and authenticated VNC still work.

Logs/screenshots are short-lived Actions artifacts; no service credentials are used. Only a successfully tested main-branch image is published to GHCR under **`13`**, **`latest`** and **`sha-<12-character-commit>`**. A final independent anonymous manifest/config read verifies digests, metadata, root-bootstrap entrypoint, ports and absence of VNC password defaults. Runtime checks verify the desktop actually uses UID 1000.

The workflow authenticates publication with `GITHUB_TOKEN`; it is not passed into the build. Package visibility is independent of repository visibility. Anonymous publication checks are required; do not assume a fork's image is public. Kubernetes needs no imagePullSecret for this public package.

The Debian base is digest-pinned. APT packages are refreshed during rebuilds; SDK/direct downloads use version/checksum pins. npm transitive dependencies and some editor plugin resolutions can vary on later builds; the old Node lockfile is not the current installation contract. A tested image digest identifies the exact artifact. Third-party software retains its own licenses and notices.
