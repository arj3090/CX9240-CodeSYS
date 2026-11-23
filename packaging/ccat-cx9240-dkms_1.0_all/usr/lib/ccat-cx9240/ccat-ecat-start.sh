#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Manufacturing Automation, LLC
# Bring up the CX9240 internal EtherCAT master (CCAT FPGA) as eth0. Run by ccat-ecat.service.
set -e
modprobe ccat
modprobe ccat_netdev dbg_frames=0
modprobe ccat_cx_shim
i=0
while [ ! -e /sys/class/net/eth0 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
[ -e /sys/class/net/eth0 ] || { echo "ccat-ecat: eth0 did not appear" >&2; exit 1; }
sysctl -qw net.ipv6.conf.eth0.disable_ipv6=1
ip link set eth0 up
i=0
while [ "$(cat /sys/class/net/eth0/carrier 2>/dev/null)" != "1" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
ip -br link show eth0
