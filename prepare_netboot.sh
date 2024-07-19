#/bin/bash
wget https://dl-cdn.alpinelinux.org/alpine/v3.18/releases/x86_64/alpine-minirootfs-3.18.0-x86_64.tar.gz
mkdir alpine-netboot
cd alpine-netboot
tar -xzvf ../alpine-minirootfs-3.18.0-x86_64.tar.gz
sudo chroot . /bin/ash
apk update
apk add dislocker fuse ntfs-3g openldap-clients krb5 bash
exit
