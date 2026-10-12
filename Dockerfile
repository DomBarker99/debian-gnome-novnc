# syntax=docker/dockerfile:1.10
FROM debian:13

ARG TARGETARCH=amd64
ARG APT_REFRESH=manual
ARG IMAGE_REVISION=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="Debian 13 GNOME noVNC developer desktop" \
      org.opencontainers.image.description="Full GNOME, development SDKs, Codex CLI and Pi; authenticated browser access." \
      org.opencontainers.image.source="https://github.com/DomBarker99/debian-gnome-novnc" \
      org.opencontainers.image.documentation="https://github.com/DomBarker99/debian-gnome-novnc/blob/main/usage.md" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${BUILD_DATE}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY packages/apt.txt /usr/local/share/debian-gnome-novnc/packages/apt.txt
# Cache mounts keep downloaded build data out of the final image without
# stripping documentation, locales or packages. Services don't start in build.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    test "$TARGETARCH" = amd64 \
    && echo "APT refresh: $APT_REFRESH" \
    && printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && DEBIAN_FRONTEND=noninteractive apt-get update \
    && grep -Ev '^([[:space:]]*#|[[:space:]]*$)' /usr/local/share/debian-gnome-novnc/packages/apt.txt \
       | xargs env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    && locale-gen en_US.UTF-8

COPY versions.env /usr/local/share/debian-gnome-novnc/versions.env
COPY packages/python.txt /usr/local/share/debian-gnome-novnc/packages/python.txt
COPY packages/node/package*.json /opt/node-cli/
COPY --chmod=0755 scripts/install-tools.sh /usr/local/libexec/install-tools
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.npm \
    /usr/local/libexec/install-tools

RUN useradd --uid 1000 --user-group --create-home --shell /bin/bash desktop \
    && printf 'desktop ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/desktop \
    && chmod 0440 /etc/sudoers.d/desktop \
    && visudo --check \
    && install -d -o desktop -g desktop /home/desktop/projects
COPY --chmod=0755 scripts/start-desktop.sh /usr/local/bin/start-desktop
COPY --chmod=0755 scripts/gnome-session.sh /usr/local/libexec/desktop-session
COPY --chmod=0755 scripts/healthcheck.sh /usr/local/bin/desktop-healthcheck

ENV HOME=/home/desktop \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DISPLAY=:1 \
    XDG_RUNTIME_DIR=/tmp/gnome-runtime-1000 \
    XAUTHORITY=/tmp/gnome-runtime-1000/Xauthority \
    XDG_SESSION_TYPE=x11 \
    XDG_SESSION_CLASS=user \
    XDG_CURRENT_DESKTOP=GNOME \
    XDG_SESSION_DESKTOP=gnome \
    DESKTOP_SESSION=gnome \
    GNOME_SHELL_SESSION_MODE=user \
    LIBGL_ALWAYS_SOFTWARE=1 \
    GALLIUM_DRIVER=llvmpipe \
    RUSTUP_HOME=/opt/rustup \
    JAVA_HOME=/opt/java \
    NPM_CONFIG_PREFIX=/home/desktop/.local \
    PATH=/home/desktop/.local/bin:/opt/node-cli/node_modules/.bin:/opt/java/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin

USER 1000:1000
WORKDIR /home/desktop
EXPOSE 6080
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD ["/usr/local/bin/desktop-healthcheck"]
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/start-desktop"]
CMD ["desktop"]
