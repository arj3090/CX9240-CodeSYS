#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Manufacturing Automation, LLC
# CX9240 one-shot setup, controller side. Run as root from the folder that holds the .deb files:
#     sudo sh setup-controller.sh
# It is started for you by Install-CX9240.ps1 on the PC.
#
# Steps:  1 Beckhoff package login   2 driver package   3 CODESYS runtime
#         4 firewall rule            5 restart and check
# Safe to run again: steps that are already done are skipped or simply repeated.

set -u
cd "$(dirname "$0")" || exit 1
[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
export DEBIAN_FRONTEND=noninteractive
AUTH=/etc/apt/auth.conf.d/bhf.conf
FW=/etc/nftables.conf.d/60-codesys.conf
LOG=/var/log/cx9240-setup.log
: > "$LOG"

say()  { printf '\n=== %s\n' "$*"; }
fail() { printf '\nFAILED: %s\nDetails: %s\n' "$*" "$LOG"; exit 1; }
one()  { # exactly one file matching the pattern, or empty
	set -- $1
	[ $# -eq 1 ] && [ -f "$1" ] && echo "$1"
}

# ---------------------------------------------------------------- 1. Beckhoff login
say "Step 1 of 5: Beckhoff package server login"
try=0
while :; do
	if [ -s "$AUTH" ] && apt-get update >>"$LOG" 2>&1; then
		echo "Package lists updated."
		break
	fi
	try=$((try + 1))
	[ $try -gt 3 ] && fail "could not reach the Beckhoff package servers (wrong login, or no internet)"
	if [ -s "$AUTH" ]; then echo "That login was not accepted, or the servers could not be reached. Try again."; fi
	printf 'myBeckhoff e-mail: '
	read -r BHF_USER
	printf 'myBeckhoff password (not shown): '
	stty -echo 2>/dev/null; read -r BHF_PASS; stty echo 2>/dev/null; echo
	case "$BHF_PASS" in *" "*) echo "Note: passwords containing spaces do not work in this file format.";; esac
	umask 077
	printf 'machine deb.beckhoff.com\nlogin %s\npassword %s\n\nmachine deb-mirror.beckhoff.com\nlogin %s\npassword %s\n' \
		"$BHF_USER" "$BHF_PASS" "$BHF_USER" "$BHF_PASS" > "$AUTH"
	chmod 600 "$AUTH"
	umask 022
	BHF_PASS=
done

# ---------------------------------------------------------------- 2. driver package
say "Step 2 of 5: driver package (a few minutes on a new image)"
DRV=$(one './ccat-cx9240-dkms_*_all.deb')
[ -n "$DRV" ] || fail "driver package ccat-cx9240-dkms_*_all.deb not found next to this script"
echo "Installing $DRV ..."
apt-get install -y "$DRV" >>"$LOG" 2>&1 || fail "driver package did not install"
ip link show eth0 >/dev/null 2>&1 || fail "driver installed but the EtherCAT interface eth0 did not appear"
echo "Driver installed (package version $(dpkg-query -W -f='${Version}' ccat-cx9240-dkms 2>/dev/null)), eth0 present."

# ---------------------------------------------------------------- 3. CODESYS runtime
say "Step 3 of 5: CODESYS runtime"
CM=$(one './codemeter-lite_*_arm64.deb')
RT=$(one './codesyscontrol_linuxarm64_*_arm64.deb')
GW=$(one './codesysedge_edgearm64_*_arm64.deb')
PX=$(one './codesysproxy_proxyarm64_*_arm64.deb')
[ -n "$RT" ] || fail "CODESYS runtime package codesyscontrol_linuxarm64_*_arm64.deb not found next to this script"
for p in "$CM" "$PX" "$RT" "$GW"; do
	[ -n "$p" ] || continue
	echo "Installing $p ..."
	apt-get install -y "$p" >>"$LOG" 2>&1 || fail "$p did not install"
done
[ -n "$CM" ] || echo "Note: codemeter-lite package not supplied, skipped."
[ -n "$PX" ] || echo "Note: codesysproxy package not supplied, skipped."
[ -n "$GW" ] || echo "Note: codesysedge (gateway) package not supplied, skipped."

# ---------------------------------------------------------------- 4. firewall
say "Step 4 of 5: firewall rule for CODESYS"
cat > "$FW" <<'EOF'
table inet filter {
  chain input {
    # CODESYS runtime, gateway and network scan
    tcp dport { 1217, 11740 } accept
    udp dport 1740-1743 accept
  }
}
EOF
systemctl reload nftables >>"$LOG" 2>&1 || fail "firewall rule written but nftables did not reload"
echo "Firewall rule active."

# ---------------------------------------------------------------- 5. restart and check
say "Step 5 of 5: restart and check"
[ -x /usr/lib/ccat-cx9240/codesys-ups-setup.sh ] && /usr/lib/ccat-cx9240/codesys-ups-setup.sh add >>"$LOG" 2>&1
systemctl restart codesyscontrol >>"$LOG" 2>&1
sleep 8

bad=0
check() { # check "label" command...
	label=$1; shift
	if "$@" >/dev/null 2>&1; then printf '  OK    %s\n' "$label"; else printf '  FAIL  %s\n' "$label"; bad=$((bad + 1)); fi
}
echo
check "Driver built for this kernel"        sh -c 'dkms status | grep -q "ccat-cx9240.*installed"'
check "EtherCAT interface eth0 is up"       sh -c 'ip -br link show eth0 | grep -q UP'
check "Driver service running"              systemctl is-active --quiet ccat-ecat
check "CODESYS runtime running"             systemctl is-active --quiet codesyscontrol
check "TC LED service running"              systemctl is-active --quiet codesys-tcled
check "Firewall rule loaded"                sh -c 'nft list chain inet filter input | grep -q 11740'
check "UPS entry in CODESYS configuration"  grep -q power_supply/ups /etc/codesyscontrol/CODESYSControl_User.cfg
check "UPS signal readable"                 test -r /sys/class/power_supply/ups/status

echo
if [ $bad -eq 0 ]; then
	echo "All checks passed. Continue in CODESYS on the PC (Part 3 of the quick install guide)."
	echo "Controller address: $(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)"
else
	echo "$bad check(s) failed. Details: $LOG"
	exit 1
fi
