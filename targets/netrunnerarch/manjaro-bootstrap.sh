#!/bin/bash
# last edited 02. March 2014
# This script is inspired on the archbootstrap script.
# Modified archinstall-bootstrap.sh to be used to bootstrap manjaro. Source:
# https://wiki.archlinux.org/index.php/Fast_Arch_Install_from_existing_Linux_System

set -x

FIRST_PACKAGE=(filesystem)
BASH_PACKAGES=(glibc ncurses readline bash)
PACMAN_PACKAGES=(acl archlinux-keyring manjaro-keyring attr bzip2 coreutils curl e2fsprogs expat gnupg gpgme keyutils krb5 libarchive libassuan libgpg-error libgcrypt libssh2 lzo2 openssl pacman xz zlib)
CORE_PACKAGES=(pacman-mirrorlist tar libcap arch-install-scripts util-linux systemd nano vim)
# EXTRA_PACKAGES=(manjaroiso git base base-devel)
PACKAGES=(${FIRST_PACKAGE[*]} ${BASH_PACKAGES[*]} ${PACMAN_PACKAGES[*]} ${CORE_PACKAGES[*]})

[ "$MIRROR" ] || MIRROR='http://vm1.sorch.info/manjaro/stable' 
[ "$ARCH" ] || ARCH=`uname -m`
[ "$CHROOT_DIR" ] || CHROOT_DIR=/tmp/manjaro
[ "$PKG_TMP_DIR" ] || PKG_TMP_DIR=/tmp/manjaro-pkg

LIST=`mktemp`

mkdir -p "$PKG_TMP_DIR"
mkdir -p "$CHROOT_DIR"
# Create a list of filenames for the arch packages
wget -q -O- "$MIRROR/core/$ARCH/" | sed -n "s|.*href=\"\\([^\"]*xz\\)\".*|\\1|p" >> $LIST
# Download and extract each package.
for PACKAGE in ${PACKAGES[*]}; do
        FILE=`grep "$PACKAGE-[0-9]" $LIST|head -n1`
        wget "$MIRROR/core/$ARCH/$FILE" -c -O "$PKG_TMP_DIR/$FILE"
        xz -dc "$PKG_TMP_DIR/$FILE" | tar x -k -C "$CHROOT_DIR"
        rm -f "$CHROOT_DIR/.PKGINFO" "$CHROOT_DIR/.MTREE" "$CHROOT_DIR/.INSTALL"
done

#for PACKAGE in ${EXTRA_PACKAGES[*]}; do
#        FILE=`grep "$PACKAGE-[0-9]" $LIST|head -n1`
#        wget "$MIRROR/extra/$ARCH/$FILE" -c -O "$PKG_TMP_DIR/$FILE"
#        xz -dc "$PKG_TMP_DIR/$FILE" | tar x -k -C "$CHROOT_DIR"
#        rm -f "$CHROOT_DIR/.PKGINFO" "$CHROOT_DIR/.MTREE" "$CHROOT_DIR/.INSTALL"
#done
# Create mount points
mount -o bind /proc "$CHROOT_DIR/proc/"
mount -o bind /sys "$CHROOT_DIR/sys/"
mount -o bind /dev "$CHROOT_DIR/dev/"
mkdir -p "$CHROOT_DIR/dev/pts"
mount -t devpts devpts "$CHROOT_DIR/dev/pts/"

# Hash for empty password  Created by doing: openssl passwd -1 -salt ihlrowCo and entering an empty password (just press enter)
# echo 'root:$1$ihlrowCo$sF0HjA9E8up9DYs258uDQ0:10063:0:99999:7:::' > "$CHROOT_DIR/etc/shadow"
# echo "myhost" > "$CHROOT_DIR/etc/hostname"
[ -f "/etc/resolv.conf" ] && cp "/etc/resolv.conf" "$CHROOT_DIR/etc/"

mkdir -p "$CHROOT_DIR/etc/pacman.d/"
echo "Server = $MIRROR/\$repo/$ARCH" >> "$CHROOT_DIR/etc/pacman.d/mirrorlist"

chroot $CHROOT_DIR pacman-key --init
chroot $CHROOT_DIR pacman-key --populate archlinux manjaro
chroot $CHROOT_DIR pacman -Syu pacman --force --noconfirm
chroot $CHROOT_DIR pacman-mirrors -g -c United_States

[ -f "/etc/resolv.conf" ] && cp "/etc/resolv.conf" "$CHROOT_DIR/etc/"
chroot $CHROOT_DIR pacman -Syu base base-devel --force --noconfirm

if [ "$ADDITIONAL_PACKAGES" ]; then
    chroot $CHROOT_DIR pacman -Syu $ADDITIONAL_PACKAGES --force --noconfirm
fi

umount "$CHROOT_DIR/dev/pts"
umount "$CHROOT_DIR/dev"
umount "$CHROOT_DIR/sys"
umount "$CHROOT_DIR/proc"
