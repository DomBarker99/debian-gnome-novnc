#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) == 0 ]] || { echo 'Startup needs root for sshd; desktop and tools run as UID 1000.' >&2; exit 1; }
export HOME=/home/desktop USER=desktop LOGNAME=desktop
install -d -m 0700 -o 1000 -g 1000 "$HOME"
runuser -u desktop -- /usr/local/libexec/agent-home-init
cd "$HOME"
if [[ ${1:-desktop} != desktop ]]; then
    exec runuser -u desktop -- "$@"
fi
install -d -m 0755 /run/sshd
if [[ -r /run/ssh-keys/authorized_keys ]]; then
    install -m 0644 -o root -g root /run/ssh-keys/authorized_keys /run/sshd/authorized_keys
elif [[ ! -s "$HOME/.ssh/authorized_keys" ]]; then
    echo 'Mount SSH public keys at /run/ssh-keys/authorized_keys; no password login is enabled.' >&2
    exit 1
fi
keys="$HOME/.local/state/sshd"
install -d -m 0700 -o root -g root "$keys"
if [[ ! -s "$keys/ssh_host_ed25519_key" ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$keys/ssh_host_ed25519_key"
fi
chmod 0600 "$keys/ssh_host_ed25519_key"
/usr/sbin/sshd -t
/usr/sbin/sshd -E /var/log/sshd.log
# Retain the existing simple desktop lifetime; no sidecars or new supervisor.
exec runuser -u desktop -- /usr/local/bin/start-desktop desktop
