#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$DBUS_SESSION_BUS_ADDRESS" > "$XDG_RUNTIME_DIR/session-bus.address"
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.desktop.lockdown disable-lock-screen true
gsettings set org.gnome.desktop.session idle-delay 0
version=$(gnome-shell --version | awk '{print $NF}')
gsettings set org.gnome.shell welcome-dialog-last-shown-version "$version"
exec gnome-session --session=gnome --disable-acceleration-check
