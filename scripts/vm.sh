#!/bin/sh
# vm.sh STEP...  drive a headless VirtualBox VM.
#
#   VM=<name>      which VM (required)
#   SCRATCH=<dir>  where screenshots go (default /tmp/beos-vm)
#
# Steps, run in order:
#   k:<hex,…>               raw scancodes, e.g. k:1c,9c (Enter), k:1d,13,93,9d (Ctrl+R)
#   t:<text>                type text (no newline; follow with k:1c,9c)
#   m:<action>,x,y[,x2,y2]  mouse via mouse.py: click rclick dclick ctrlclick
#                           altclick move drag
#   w:<seconds>             wait
#   shot:<name>             screenshot to $SCRATCH/<name>.png
VM=${VM:?set VM=<vm name>}
SCRATCH=${SCRATCH:-/tmp/beos-vm}
HERE=$(dirname "$0")
export VM
mkdir -p "$SCRATCH"
for step in "$@"; do
	case "$step" in
	k:*) VBoxManage controlvm "$VM" keyboardputscancode $(echo "${step#k:}" | tr ',' ' ') ;;
	t:*) VBoxManage controlvm "$VM" keyboardputstring "${step#t:}" ;;
	m:*) python3 "$HERE/mouse.py" $(echo "${step#m:}" | tr ',' ' ') ;;
	w:*) sleep "${step#w:}" ;;
	shot:*) VBoxManage controlvm "$VM" screenshotpng "$SCRATCH/${step#shot:}.png" \
		&& echo "$SCRATCH/${step#shot:}.png" ;;
	*) echo "vm.sh: unknown step '$step'" >&2; exit 1 ;;
	esac
done
