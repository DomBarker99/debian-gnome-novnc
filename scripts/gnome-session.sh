#!/usr/bin/env bash
set -Eeuo pipefail
# Container accounts have no PAM login password, so screen locking would strand
# the session. Browser/VNC authentication remains mandatory at the boundary.
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.lockdown disable-lock-screen true
gsettings set org.gnome.desktop.session idle-delay 0
if [[ ! -e "$HOME/.config/gnome-initial-setup-done" ]]; then
    printf 'yes\n' > "$HOME/.config/gnome-initial-setup-done"
fi
# GNOME 48 falls back to its supported non-systemd session manager. Do not use
# removed --builtin options, Flashback, another window manager, or privileged mode.
exec gnome-session --session=gnome --disable-acceleration-check
