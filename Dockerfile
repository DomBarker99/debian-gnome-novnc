# syntax=docker/dockerfile:1.10
FROM debian:13@sha256:913f6706df59a68922d1dd08f78c2476560a8d367897200a6005b00e5f67c2d5
ARG TARGETARCH=amd64
ARG APT_REFRESH=manual
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY packages/apt.txt /usr/local/share/tully-agent/packages/apt.txt
# The custom HostKey path prevents Debian postinst from baking default host keys.
COPY config/sshd_config /etc/ssh/sshd_config
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    test "$TARGETARCH" = amd64 \
    && echo "APT refresh: $APT_REFRESH" \
    && printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && DEBIAN_FRONTEND=noninteractive apt-get update \
    && grep -Ev '^([[:space:]]*#|[[:space:]]*$)' /usr/local/share/tully-agent/packages/apt.txt \
       | xargs env DEBIAN_FRONTEND=noninteractive UCF_FORCE_CONFFOLD=1 apt-get install -y --no-install-recommends \
    && locale-gen en_US.UTF-8 \
    && test -z "$(find /etc/ssh -maxdepth 1 -name 'ssh_host_*_key' -print)"

COPY versions.env /usr/local/share/tully-agent/versions.env
COPY packages/python.txt /usr/local/share/tully-agent/packages/python.txt
COPY assets/ /usr/local/share/tully-agent/assets/
COPY --chmod=0755 scripts/install-tools.sh /usr/local/libexec/install-agent-tools
RUN --mount=type=tmpfs,target=/tmp \
    --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.npm \
    /usr/local/libexec/install-agent-tools
# Only public software seeds: Git's zero-byte .promisor markers can be root-only.
RUN find /usr/local/share/agent-cli-seed /usr/local/share/agent-home-seed -type d ! -perm -005 -exec chmod a+rx {} + \
    && find /usr/local/share/agent-cli-seed /usr/local/share/agent-home-seed -type f ! -perm -004 -exec chmod a+r {} +

RUN useradd --uid 1000 --user-group --create-home --shell /bin/bash desktop \
    && printf 'desktop ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/desktop \
    && chmod 0440 /etc/sudoers.d/desktop \
    && visudo --check \
    && install -d -m 1777 /tmp/.X11-unix /tmp/.ICE-unix
COPY config/system-bus.conf /usr/local/share/tully-agent/system-bus.conf
COPY config/profile.sh /etc/profile.d/agent.sh
COPY config/bashrc /usr/local/share/tully-agent/bashrc
COPY --chown=1000:1000 config/bashrc /home/desktop/.bashrc
COPY config/ssh-env.conf /etc/ssh/sshd_config.d/agent-env.conf
RUN printf '\nInclude /etc/ssh/sshd_config.d/*.conf\n' >> /etc/ssh/sshd_config
COPY --chmod=0755 scripts/home-init.sh /usr/local/libexec/agent-home-init
COPY --chmod=0755 scripts/start-desktop.sh /usr/local/bin/start-desktop
COPY --chmod=0755 scripts/gnome-session.sh /usr/local/libexec/desktop-session
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/agent-entrypoint
COPY --chmod=0755 scripts/healthcheck.sh /usr/local/bin/desktop-healthcheck

# locale-gen ignores a disabled /etc/locale.gen entry; compile the declared locale explicitly.
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

ARG IMAGE_REVISION=unknown
ARG BUILD_DATE=unknown
LABEL org.opencontainers.image.title="Debian 13 GNOME SSH/noVNC developer desktop" \
      org.opencontainers.image.description="Selected GNOME, Firefox, SSH, upgradeable Pi/Codex, Railway CLI and AstroNvim; no credentials." \
      org.opencontainers.image.source="https://github.com/DomBarker99/debian-gnome-novnc" \
      org.opencontainers.image.documentation="https://github.com/DomBarker99/debian-gnome-novnc/blob/main/usage.md" \
      org.opencontainers.image.revision="${IMAGE_REVISION}" \
      org.opencontainers.image.created="${BUILD_DATE}"
ENV HOME=/home/desktop \
    LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    DISPLAY=:1 XDG_RUNTIME_DIR=/tmp/gnome-runtime-1000 \
    XAUTHORITY=/tmp/gnome-runtime-1000/Xauthority \
    DBUS_SYSTEM_BUS_ADDRESS=unix:path=/tmp/gnome-runtime-1000/system-bus \
    XDG_SESSION_TYPE=x11 XDG_SESSION_CLASS=user XDG_CURRENT_DESKTOP=GNOME \
    XDG_SESSION_DESKTOP=gnome DESKTOP_SESSION=gnome GNOME_SHELL_SESSION_MODE=user \
    LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
    RUSTUP_HOME=/opt/rustup JAVA_HOME=/opt/java \
    NPM_CONFIG_PREFIX=/home/desktop/.local \
    PI_TELEMETRY=0 \
    PATH=/home/desktop/.local/bin:/home/desktop/.cargo/bin:/opt/java/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin
# Root is only the SSH/bootstrap entry point; GNOME, SSH logins, and tools use UID 1000.
USER 0:0
# Root bootstrap creates /home/desktop on an initially empty /home PVC.
WORKDIR /
EXPOSE 22 6080
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 CMD ["/usr/local/bin/desktop-healthcheck"]
ENTRYPOINT ["/usr/bin/tini", "-g", "--", "/usr/local/bin/agent-entrypoint"]
CMD ["desktop"]
