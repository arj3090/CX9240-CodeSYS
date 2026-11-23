#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Manufacturing Automation, LLC
# Let CODESYS programs read the CX9240 internal UPS status.
# Adds (or removes) a named file path "$ups$" -> /sys/class/power_supply/ups in the CODESYS
# runtime's user config, so IEC code can open '$ups$/status' with the SysFile library.
#
#   codesys-ups-setup.sh add      add the entry if CODESYS is installed and it is missing
#   codesys-ups-setup.sh remove   remove the entry again
#
# Safe to run repeatedly. Restarts codesyscontrol only when it changed the file and the
# runtime is running, because the runtime reads this file only at start.
set -e
CFG=/etc/codesyscontrol/CODESYSControl_User.cfg
UPSDIR=/sys/class/power_supply/ups
ENTRY="$UPSDIR, \$ups\$"
MARK="$UPSDIR,"

[ -f "$CFG" ] || { echo "ccat-ups: CODESYS user config not found ($CFG), nothing to do"; exit 0; }
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

case "${1:-add}" in
add)
	if grep -qF "$MARK" "$CFG"; then
		echo "ccat-ups: CODESYS already has the UPS path entry"; exit 0
	fi
	if grep -q '^\[SysFile\]' "$CFG"; then
		# existing section: insert with the next free PlaceholderFilePath index
		N=$(sed -n 's/^PlaceholderFilePath\.\([0-9][0-9]*\)=.*/\1/p' "$CFG" | sort -n | tail -1)
		N=$(( ${N:-0} + 1 ))
		awk -v line="PlaceholderFilePath.$N=$ENTRY" \
			'{print} /^\[SysFile\]/ && !done {print line; done=1}' "$CFG" > "$TMP"
	else
		cat "$CFG" > "$TMP"
		printf '\n[SysFile]\nPlaceholderFilePath.1=%s\n' "$ENTRY" >> "$TMP"
	fi
	;;
remove)
	grep -qF "$MARK" "$CFG" || exit 0
	grep -vF "$MARK" "$CFG" > "$TMP" || true
	;;
*)
	echo "usage: $0 add|remove" >&2; exit 2 ;;
esac

# write back in place so owner and mode of the config file stay as CODESYS set them
cat "$TMP" > "$CFG"
echo "ccat-ups: updated $CFG ($1)"
if systemctl is-active --quiet codesyscontrol.service 2>/dev/null; then
	echo "ccat-ups: restarting codesyscontrol so the change takes effect"
	systemctl restart codesyscontrol.service || true
fi
