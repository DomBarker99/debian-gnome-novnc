# debian-gnome-novnc

[![Build, test and publish image](https://github.com/DomBarker99/debian-gnome-novnc/actions/workflows/build-image.yml/badge.svg)](https://github.com/DomBarker99/debian-gnome-novnc/actions/workflows/build-image.yml)

This container image provides a Debian 13 GNOME developer desktop, reachable over key-only SSH and in a browser through noVNC. It gives coding agents such as Pi and Codex an isolated Linux workspace with a persistent private home.

Image: `ghcr.io/dombarker99/debian-gnome-novnc:13` (linux/amd64)

## Highlights

- **Desktop and tools:** selected GNOME components, Firefox ESR, and a developer toolchain: Node 24, Python 3.14, Rust, JDK 25, GCC/Clang, kubectl, talosctl and more.
- **Unprivileged by default:** the desktop, SSH sessions and tools run as `desktop` (UID/GID 1000). SSH accepts public keys only. VNC needs a password supplied at runtime and has no default.
- **Persistent home:** `/home` is a volume. Projects, upgraded tools and the SSH host identity survive container replacement.
- **Tested before publishing:** CI builds the image and tests rendered GNOME and VNC/noVNC access, SSH, developer tools, and persistence across container replacement. Only then does it publish to GHCR.

## Getting started

[usage.md](usage.md) is the full guide. It covers the `docker run` command and required secrets, Kubernetes port-forwarding, persistence, upgrades, and how to build and test locally.

After starting the container as shown there:

- SSH: `ssh -p 2221 desktop@127.0.0.1`
- Browser desktop: http://localhost:6081/vnc.html

## Repository layout

| Path | Contents |
| --- | --- |
| `Dockerfile` | Image definition (digest-pinned Debian 13 base) |
| `packages/`, `versions.env` | APT and Python package lists; pinned tool versions and checksums |
| `scripts/` | Entrypoint, home initialization, desktop startup, health check and tool installer |
| `config/` | Shell, SSH and D-Bus configuration |
| `tests/` | Smoke tests and publication checks run by CI |
| `.github/workflows/build-image.yml` | Build, test and publish pipeline |
