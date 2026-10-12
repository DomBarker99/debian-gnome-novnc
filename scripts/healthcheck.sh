#!/usr/bin/env bash
set -Eeuo pipefail
[[ -s "$XDG_RUNTIME_DIR/desktop.pids" ]]
while read -r pid; do kill -0 "$pid"; done < "$XDG_RUNTIME_DIR/desktop.pids"
pgrep -u "$(id -u)" -x gnome-shell >/dev/null
wm=$(xprop -root _NET_SUPPORTING_WM_CHECK | awk '{print $NF}')
[[ $wm =~ ^0x[[:xdigit:]]+$ ]]
xprop -id "$wm" _NET_WM_NAME | grep -F 'GNOME Shell' >/dev/null
curl --fail --silent --max-time 5 http://127.0.0.1:6080/vnc.html >/dev/null
