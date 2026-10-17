#!/usr/bin/env bash
set -Eeuo pipefail
[[ $(id -u) == 1000 ]] || { echo 'Initialize home as desktop UID 1000.' >&2; exit 1; }
umask 077
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/node_modules" "$HOME/.local/share" "$HOME/.local/state" "$HOME/.config" "$HOME/.cache" "$HOME/projects"
[[ -e "$HOME/.profile" ]] || cp /etc/skel/.profile "$HOME/.profile"
[[ -e "$HOME/.bashrc" ]] || cp /usr/local/share/tully-agent/bashrc "$HOME/.bashrc"
seed=/usr/local/share/agent-cli-seed
for pair in 'pi:@earendil-works/pi-coding-agent' 'codex:@openai/codex'; do
    tool=${pair%%:*}; package=${pair#*:}
    target="$HOME/.local/lib/node_modules/$package"
    if [[ ! -e "$target/package.json" ]]; then
        mkdir -p "$(dirname "$target")"
        cp -a --no-preserve=ownership "$seed/lib/node_modules/$package" "$target"
    fi
    if [[ ! -e "$HOME/.local/bin/$tool" && ! -L "$HOME/.local/bin/$tool" ]]; then
        ln -s "$(readlink "$seed/bin/$tool")" "$HOME/.local/bin/$tool"
    fi
done
home_seed=/usr/local/share/agent-home-seed
if [[ ! -d "$HOME/.config/nvim" ]]; then
    stage=$(mktemp -d "$HOME/.config/.nvim-seed.XXXXXX")
    cp -a --no-preserve=ownership "$home_seed/config/nvim/." "$stage/"
    mv "$stage" "$HOME/.config/nvim"
fi
if [[ ! -d "$HOME/.local/share/nvim" ]]; then
    stage=$(mktemp -d "$HOME/.local/share/.nvim-seed.XXXXXX")
    cp -a --no-preserve=ownership "$home_seed/data/nvim/." "$stage/"
    mv "$stage" "$HOME/.local/share/nvim"
fi
# Keep fresh homes clean; never remove or overwrite existing user folders/settings.
if [[ ! -e "$HOME/.config/user-dirs.dirs" ]]; then
    for name in DESKTOP DOWNLOAD TEMPLATES PUBLICSHARE DOCUMENTS MUSIC PICTURES VIDEOS; do
        printf 'XDG_%s_DIR="$HOME"\n' "$name"
    done > "$HOME/.config/user-dirs.dirs"
fi
[[ -e "$HOME/.config/user-dirs.conf" ]] || printf 'enabled=False\n' > "$HOME/.config/user-dirs.conf"
[[ -e "$HOME/.config/gnome-initial-setup-done" ]] || printf 'yes\n' > "$HOME/.config/gnome-initial-setup-done"
# Image defaults suppress optional autostarts, without replacing personal overrides.
auto="$HOME/.config/autostart"
mkdir -p "$auto"
keep=' at-spi-dbus-bus.desktop gnome-keyring-pkcs11.desktop gnome-keyring-secrets.desktop gnome-keyring-ssh.desktop im-launch.desktop org.gnome.SettingsDaemon.A11ySettings.desktop org.gnome.SettingsDaemon.Keyboard.desktop org.gnome.SettingsDaemon.MediaKeys.desktop org.gnome.SettingsDaemon.XSettings.desktop org.gnome.SettingsDaemon.Sound.desktop '
for source in /etc/xdg/autostart/*.desktop; do
    name=${source##*/}
    if [[ $keep != *" $name "* && ! -e "$auto/$name" ]]; then
        printf '[Desktop Entry]\nType=Application\nName=Disabled in agent image\nHidden=true\n' > "$auto/$name"
    fi
done
sessions="$HOME/.config/gnome-session/sessions"
mkdir -p "$sessions"
if [[ ! -e "$sessions/gnome.session" ]]; then
    printf '[GNOME Session]\nName=GNOME\nRequiredComponents=org.gnome.Shell;org.gnome.SettingsDaemon.A11ySettings;org.gnome.SettingsDaemon.Keyboard;org.gnome.SettingsDaemon.MediaKeys;org.gnome.SettingsDaemon.XSettings;org.gnome.SettingsDaemon.Sound;\n' > "$sessions/gnome.session"
fi
