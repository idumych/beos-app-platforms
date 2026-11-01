#!/bin/sh
# beos-terminal.sh   open a Terminal in a BeOS 5 VM at 1024x768 ($VM).
#
# The Be menu (top right, the "Be OS" logo) is opened with beos-mouse.py,
# then Applications > Terminal is chosen with the keyboard: Right enters the
# submenu, Down N times reaches Terminal, Enter launches it. N counts the
# Applications folder's entries above Terminal, alphabetically: 26 on a
# fresh BeOS 5 Pro install, 27 once an installer has added its own link
# (Gobe Productive). Override with N=. After that, type with
#   VBoxManage controlvm "$VM" keyboardputstring '<command>'
#   VBoxManage controlvm "$VM" keyboardputscancode 1c 9c        # Enter
# Typing goes to the focused window: check with a screenshot that it's the
# Terminal (a Tracker window takes the keys as type-ahead and Enter opens
# what it selected).
HERE=$(dirname "$0")
N=${N:-26}
python3 "$HERE/beos-mouse.py" click 963 11 2>/dev/null		# the Be menu
sleep 1
python3 "$HERE/beos-mouse.py" move 822 168 2>/dev/null		# Applications
sleep 1
VBoxManage controlvm "$VM" keyboardputscancode e0 4d e0 cd	# Right
sleep 0.5
i=0
while [ $i -lt "$N" ]; do
	VBoxManage controlvm "$VM" keyboardputscancode e0 50 e0 d0	# Down
	sleep 0.15
	i=$((i + 1))
done
VBoxManage controlvm "$VM" keyboardputscancode 1c 9c		# Enter
sleep 4
