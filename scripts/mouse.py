"""mouse.py ACTION X Y [X2 Y2] -- absolute mouse input for a VirtualBox VM.

ACTION: move, click, rclick, dclick, ctrlclick, altclick, drag (X Y -> X2 Y2).
The VM is taken from $VM (required). Coordinates are screenshot
pixels (0-based); VirtualBox wants 1-based. Needs the virtualbox-sdk package
(Python vboxapi) and a VM whose pointing device is a USB tablet.
"""
import os
import sys
import time

from vboxapi import VirtualBoxManager

LEFT, RIGHT = 1, 2
CTRL, ALT = 0x1D, 0x38

act = sys.argv[1]
x, y = int(sys.argv[2]) + 1, int(sys.argv[3]) + 1

mgr = VirtualBoxManager(None, None)
vb = mgr.getVirtualBox()
session = mgr.getSessionObject(vb)
vm = os.environ.get("VM")
if not vm:
	sys.exit("mouse.py: set VM=<vm name>")
vb.findMachine(vm).lockMachine(
	session, mgr.constants.LockType_Shared)
mouse = session.console.mouse
kbd = session.console.keyboard


def at(px, py, buttons=0):
	mouse.putMouseEventAbsolute(px, py, 0, 0, buttons)
	time.sleep(0.08)


def click(px, py, button=LEFT):
	# Hold the button for a moment: some toolkits (Cosmoe) wedge on
	# zero-length clicks, and real mice never produce them.
	at(px, py)
	at(px, py, button)
	at(px, py)


try:
	if act == "move":
		at(x, y)
	elif act == "click":
		click(x, y)
	elif act == "rclick":
		click(x, y, RIGHT)
	elif act == "dclick":
		click(x, y)
		click(x, y)
	elif act in ("ctrlclick", "altclick"):
		mod = ALT if act == "altclick" else CTRL
		kbd.putScancodes([mod])
		time.sleep(0.05)
		click(x, y)
		kbd.putScancodes([mod | 0x80])
	elif act == "drag":
		x2, y2 = int(sys.argv[4]) + 1, int(sys.argv[5]) + 1
		at(x, y)
		at(x, y, LEFT)
		for i in range(1, 11):
			at(x + (x2 - x) * i // 10, y + (y2 - y) * i // 10, LEFT)
		at(x2, y2)
	else:
		sys.exit("mouse.py: unknown action " + act)
finally:
	session.unlockMachine()
	# vboxapi's teardown prints a harmless traceback at interpreter exit.
	os._exit(0)
