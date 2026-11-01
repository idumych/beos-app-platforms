"""beos-mouse.py ACTION X Y [X2 Y2] -- mouse input for a VirtualBox guest
that only has a PS/2 mouse (BeOS 5: no USB tablet, so mouse.py's absolute
positions don't work).

The pointer is steered: find BeOS's hand pointer in a screenshot, move it
by relative steps, look again, correct (BeOS accelerates the mouse, so a
blind move of N steps lands 1.3-1.5 N away). X, Y are screenshot pixels;
the hand's fingertip ends on them.

ACTION: move, click, rclick, dclick, drag (X Y -> X2 Y2). $VM names the VM.

Traps (see references/beos.md):
- Over a text field the pointer is an I-beam, which isn't found: target a
  spot next to the field, or type with keyboardputstring after a click
  that already landed.
- Events closer than ~30 ms make BeOS's PS/2 driver lose the mouse (the
  pointer vanishes and moves do nothing): reboot the guest (cold) to get it
  back. Keep EVENT_GAP at 0.03 or more.
- Needs the virtualbox-sdk package (Python vboxapi) and PIL.
"""
import io
import os
import subprocess
import sys
import time

from PIL import Image
from vboxapi import VirtualBoxManager

LEFT, RIGHT = 1, 2
EVENT_GAP = float(os.environ.get("EVENT_GAP", "0.03"))

# BeOS's hand pointer: '#' black, 'o' white, '.' anything
HAND = [
	"..###............",
	"..#oo#...........",
	"..#oo#...........",
	"...#oo#####......",
	"...#oo#oo#o###...",
	"....#oo#oo#o#o#..",
	"....#oooooooooo#.",
	"..####ooooooooo#.",
	".#oo##ooooooooo#.",
	".#oooo#oooooooo#.",
	"..##ooooooooooo#.",
	"....##ooooooooo#.",
	"......#oooooooo..",
	".......#ooooo....",
]
HOT = (3, 1)	# the fingertip, in HAND

mgr = VirtualBoxManager(None, None)
vb = mgr.getVirtualBox()
session = mgr.getSessionObject(vb)
vb.findMachine(os.environ["VM"]).lockMachine(session, mgr.constants.LockType_Shared)
mouse = session.console.mouse


def rel(dx, dy, buttons=0):
	mouse.putMouseEvent(dx, dy, 0, 0, buttons)
	time.sleep(EVENT_GAP)


def locate():
	"""where the hand pointer's fingertip is on screen, or None"""
	png = subprocess.run(["VBoxManage", "controlvm", os.environ["VM"], "screenshotpng",
		"/dev/stdout"], capture_output=True).stdout
	im = Image.open(io.BytesIO(png)).convert("L")
	W, H = im.size
	p = im.load()
	cells = [(x, y, c == "#") for y, row in enumerate(HAND) for x, c in enumerate(row) if c != "."]
	for y in range(H - len(HAND)):
		for x in range(W - len(HAND[0])):
			if p[x + 2, y] >= 40:	# the fingertip's top
				continue
			if all((p[x + cx, y + cy] < 40) if black else (p[x + cx, y + cy] > 215)
					for cx, cy, black in cells):
				return x + HOT[0], y + HOT[1]
	return None


def go(x, y, buttons=0):
	"""steered to x, y: moved, found on screen, corrected"""
	for _ in range(12):
		at = locate()
		if at is None:
			# over something that hides or changes it: nudged, looked for again
			rel(15, 15, buttons)
			time.sleep(0.25)
			continue
		dx, dy = x - at[0], y - at[1]
		if dx == 0 and dy == 0:
			return True
		# one-pixel steps move about 1.3 pixels; undershoot, then correct
		sx = round(dx / 1.3) or (1 if dx > 0 else -1)
		sy = round(dy / 1.3) or (1 if dy > 0 else -1)
		if dx == 0:
			sx = 0
		if dy == 0:
			sy = 0
		while sx or sy:
			ex = (sx > 0) - (sx < 0)
			ey = (sy > 0) - (sy < 0)
			rel(ex, ey, buttons)
			sx -= ex
			sy -= ey
		time.sleep(0.25)
	return False


def press(buttons, times=1):
	for _ in range(times):
		rel(0, 0, buttons)
		time.sleep(0.12)
		rel(0, 0, 0)
		time.sleep(0.12)


act = sys.argv[1]
x, y = int(sys.argv[2]), int(sys.argv[3])
if not go(x, y):
	print(f"beos-mouse: the pointer wasn't steered to {x},{y}", file=sys.stderr)
if act == "click":
	press(LEFT)
elif act == "rclick":
	press(RIGHT)
elif act == "dclick":
	press(LEFT, 2)
elif act == "drag":
	x2, y2 = int(sys.argv[4]), int(sys.argv[5])
	rel(0, 0, LEFT)
	time.sleep(0.2)
	go(x2, y2, LEFT)
	time.sleep(0.2)
	rel(0, 0, 0)
session.unlockMachine()
