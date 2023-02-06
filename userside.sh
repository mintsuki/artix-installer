#!/bin/bash

set -e

ORIG_DIR=`pwd`

export PATH="$HOME/.local/bin:$PATH"

cat <<'EOF' >>$HOME/.bashrc
upgrade() {
sudo bash -c '
    set -e

    while ! pacman -Syu --noconfirm; do
        true
    done
    pacman -Qdtq | pacman -Rs - --noconfirm || true

    while ! aura -Auax --noconfirm; do
        true
    done
    pacman -Qdtq | pacman -Rs - --noconfirm || true

    ARCH_SUPP_TMPDIR=$(mktemp -d)
    cd $ARCH_SUPP_TMPDIR
    wget -r -nd --no-parent -A "artix-archlinux-support-*.pkg.tar.zst" https://universe.artixlinux.org/x86_64/
    wget -r -nd --no-parent -A "archlinux-keyring-*.pkg.tar.zst" https://universe.artixlinux.org/x86_64/
    wget -r -nd --no-parent -A "archlinux-mirrorlist-*.pkg.tar.zst" https://universe.artixlinux.org/x86_64/
    pacman --needed --noconfirm -U *
    cd
    rm -rf $ARCH_SUPP_TMPDIR
    pacman -Qdtq | pacman -Rs - --noconfirm || true

    sync
'
}
EOF

cd
xdg-user-dirs-update

cd
rm -rf artix-installer
