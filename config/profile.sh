# Shared by SSH login shells and desktop terminals; no credentials here.
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/opt/java/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
export NPM_CONFIG_PREFIX="$HOME/.local"
export RUSTUP_HOME=/opt/rustup JAVA_HOME=/opt/java
export DISPLAY=:1 XDG_RUNTIME_DIR=/tmp/gnome-runtime-1000
export XAUTHORITY="$XDG_RUNTIME_DIR/Xauthority"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/system-bus"
if [ -r "$XDG_RUNTIME_DIR/session-bus.address" ]; then
    export DBUS_SESSION_BUS_ADDRESS="$(head -n 1 "$XDG_RUNTIME_DIR/session-bus.address")"
fi
