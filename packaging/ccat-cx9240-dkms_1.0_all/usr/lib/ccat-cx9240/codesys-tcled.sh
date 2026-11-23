#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Manufacturing Automation, LLC
# Show the CODESYS runtime state on the CX9240 "TC" LED:
#   green = application running (the runtime is cycling the EtherCAT bus)
#   red   = stopped, no application, or runtime not running
#
# Detection needs no code in the PLC project: while an application with an EtherCAT master
# runs, the runtime sends frames on the bus interface every cycle; when the application is
# stopped it sends none. (Thread activity was tried first and does not work: the task
# threads keep waking while the application is stopped.)
# Limit: a project without an EtherCAT master on this interface always shows red.
LEDS=/sys/class/leds
IF=${TCLED_IF:-eth0}
HOLD=${TCLED_HOLD:-1.5}      # seconds without frames before showing red
POLL=${TCLED_POLL:-0.5}

set_led() { # $1 = red|green  $2 = reason
	[ "$1" = "$cur" ] && return
	cur=$1
	echo 0 > "$LEDS/blue:tc/brightness"
	if [ "$1" = green ]; then echo 0 > "$LEDS/red:tc/brightness"; echo 1 > "$LEDS/green:tc/brightness"
	else echo 0 > "$LEDS/green:tc/brightness"; echo 1 > "$LEDS/red:tc/brightness"; fi
	echo "codesys-tcled: $1 ($2)"
}

cur=; last=; idle=0
trap "set_led red \"service stopped\"; exit 0" TERM INT
set_led red "starting"
while :; do
	now=
	if pgrep -f codesyscontrol.bin >/dev/null 2>&1; then
		now=$(cat "/sys/class/net/$IF/statistics/tx_packets" 2>/dev/null)
	fi
	if [ -z "$now" ]; then
		set_led red "runtime not running or $IF missing"; last=; idle=0
	elif [ -n "$last" ] && [ "$now" != "$last" ]; then
		idle=0; set_led green "bus frames being sent"
	else
		idle=$(awk "BEGIN{print $idle + $POLL}")
		[ "$(awk "BEGIN{print ($idle >= $HOLD)}")" = 1 ] && set_led red "no bus frames for ${HOLD}s"
	fi
	last=$now
	sleep "$POLL"
done
