#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

if [[ ${1:-desktop} != desktop ]]; then
    exec "$@"
fi
[[ $# -le 1 ]] || { echo 'Configure the desktop with environment variables, not extra arguments.' >&2; exit 1; }
[[ $(id -u) == 1000 ]] || { echo 'Run this desktop as UID/GID 1000:1000.' >&2; exit 1; }
[[ -w "$HOME" ]] || { echo 'Home must be writable by UID/GID 1000; configure volume ownership or fsGroup.' >&2; exit 1; }

resolution=${VNC_RESOLUTION:-1600x1000}
[[ $resolution =~ ^[0-9]{3,4}x[0-9]{3,4}$ ]] || { echo 'VNC_RESOLUTION must be WIDTHxHEIGHT.' >&2; exit 1; }
width=${resolution%x*}; height=${resolution#*x}
((width >= 640 && width <= 4096 && height >= 480 && height <= 2160)) || { echo 'Resolution outside supported bounds.' >&2; exit 1; }

if [[ -n ${VNC_PASSWORD_FILE:-} && -n ${VNC_PASSWORD:-} ]]; then
    echo 'Set either VNC_PASSWORD_FILE or VNC_PASSWORD, not both.' >&2
    exit 1
elif [[ -n ${VNC_PASSWORD_FILE:-} ]]; then
    [[ -r $VNC_PASSWORD_FILE ]] || { echo 'VNC password file is not readable.' >&2; exit 1; }
    password=$(<"$VNC_PASSWORD_FILE")
elif [[ -n ${VNC_PASSWORD:-} ]]; then
    password=$VNC_PASSWORD
else
    echo 'A runtime VNC_PASSWORD_FILE or VNC_PASSWORD is required; there is no default password.' >&2
    exit 1
fi
# Classic VNC authentication uses only eight bytes. Reject silent truncation.
[[ $password =~ ^[[:graph:]]{8}$ && $(LC_ALL=C printf '%s' "$password" | wc -c) -eq 8 ]] || {
    echo 'VNC authentication requires exactly 8 printable ASCII bytes. Keep console access private.' >&2
    exit 1
}

mkdir -p "$XDG_RUNTIME_DIR" "$HOME/.config" "$HOME/.cache" "$HOME/.local/bin" "$HOME/projects"
chmod 0700 "$XDG_RUNTIME_DIR"
printf '%s' "$password" | tigervncpasswd -f > "$XDG_RUNTIME_DIR/vnc.passwd"
unset password VNC_PASSWORD VNC_PASSWORD_FILE
: > "$XAUTHORITY"
xauth -f "$XAUTHORITY" add "$DISPLAY" . "$(openssl rand -hex 16)"

pids=()
stop_children() {
    trap - EXIT INT TERM
    if ((${#pids[@]})); then
        kill "${pids[@]}" 2>/dev/null || true
        wait "${pids[@]}" 2>/dev/null || true
    fi
}
trap stop_children EXIT
trap 'exit 0' INT TERM

# Native VNC never listens on the container network interface.
Xtigervnc "$DISPLAY" -geometry "$resolution" -depth 24 -localhost yes \
    -SecurityTypes VncAuth -PasswordFile "$XDG_RUNTIME_DIR/vnc.passwd" \
    -auth "$XAUTHORITY" -nolisten tcp -AlwaysShared &
pids+=("$!")
for ((attempt=0; attempt<60; attempt++)); do
    if xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then break; fi
    kill -0 "${pids[0]}" 2>/dev/null || { echo 'VNC display server exited.' >&2; exit 1; }
    sleep 1
done
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || { echo 'VNC display did not become ready.' >&2; exit 1; }

dbus-run-session -- /usr/local/libexec/desktop-session &
pids+=("$!")
websockify --web=/usr/share/novnc/ 0.0.0.0:6080 127.0.0.1:5901 &
pids+=("$!")
printf '%s\n' "${pids[@]}" > "$XDG_RUNTIME_DIR/desktop.pids"
echo "GNOME desktop starting on $DISPLAY; noVNC port 6080; home $HOME."

set +e
wait -n "${pids[@]}"
status=$?
set -e
echo "A desktop service exited (status $status); stopping the container." >&2
# A long-running desktop service should not exit even with status zero.
exit 1
