#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Manufacturing Automation, LLC
# Build the ccat-cx9240-dkms .deb from the source tree next to this script.
# Run on any Debian/Ubuntu system, including WSL on the Windows PC:
#     wsl -d Debian -- sh /mnt/<drive>/<path-to-repo>/packaging/build-deb.sh
# The tree is copied to a Linux folder first so that file modes are right
# (a Windows folder cannot hold them).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TREE=ccat-cx9240-dkms_1.0_all
VER=$(sed -n 's/^Version: //p' "$HERE/$TREE/DEBIAN/control" | tr -d '\r')
OUT="ccat-cx9240-dkms_${VER}_all.deb"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cp -r "$HERE/$TREE" "$WORK/"
cd "$WORK"
find "$TREE" -type f -exec sed -i 's/\r$//' {} +
find "$TREE" -type d -exec chmod 755 {} +
find "$TREE" -type f -exec chmod 644 {} +
chmod 755 "$TREE/DEBIAN/postinst" "$TREE/DEBIAN/prerm" "$TREE"/usr/lib/ccat-cx9240/*.sh
dpkg-deb --root-owner-group --build "$TREE" "$OUT"
cp "$OUT" "$HERE/"
echo "Built $HERE/$OUT"
dpkg-deb -I "$OUT" | grep -E "Package|Version|Depends|Conflicts"
