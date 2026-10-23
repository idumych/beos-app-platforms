#!/usr/bin/env python3
"""redactshot.py OUT.png (--vm NAME | --file IN.png) [--fixed X0,Y0,X1,Y1]...
                [--panel-bottom PX]

Screenshot a VM with private areas blacked out, for apps that show account
IDs, keys or e-mail addresses. The raw screen is grabbed into memory through
vboxapi (needs the virtualbox-sdk package) and never written to disk; only
the redacted image is saved.

  --fixed X0,Y0,X1,Y1  black out this rectangle (repeatable). Use positions
                       found in an earlier, already-redacted screenshot.
  --panel-bottom PX    also black out the bottom PX pixels of every window
                       panel (blocks of the most common light-grey colour,
                       one per window): for apps whose private line sits at
                       the bottom of the window.

With --panel-bottom and no --fixed, an image where no window panel is found
is blacked out completely (fail safe).
"""
import io
import os
import sys

import numpy as np
from PIL import Image


def panel_boxes(a):
	"""Bounding boxes of light-grey panel blocks (one per window)."""
	r, g, b = (a[..., i].astype(int) for i in range(3))
	grey = (abs(r - g) < 4) & (abs(g - b) < 4) & (r >= 200) & (r <= 240)
	if not grey.any():
		return []
	vals, counts = np.unique(r[grey], return_counts=True)
	panel = (r == vals[counts.argmax()]) & grey
	cols = panel.sum(axis=0) > 150
	boxes, x, w = [], 0, len(cols)
	while x < w:
		if not cols[x]:
			x += 1
			continue
		x0 = x
		while x < w and cols[x]:
			x += 1
		x1 = x - 1
		if x1 - x0 >= 150:
			rows = np.where(panel[:, x0:x1 + 1].sum(axis=1) > (x1 - x0) * 0.3)[0]
			if len(rows) and rows.max() - rows.min() >= 250:
				boxes.append((x0, rows.min(), x1, rows.max()))
	return boxes


def redact(img, fixed, panel_bottom):
	a = np.array(img.convert("RGB"))
	h, w = a.shape[:2]
	areas = []
	for x0, y0, x1, y1 in fixed:
		a[y0:y1, x0:x1] = 0
		areas.append((x0, y0, x1, y1))
	if panel_bottom:
		boxes = panel_boxes(a)
		if not boxes and not fixed:
			a[:] = 0
			return Image.fromarray(a), None
		for x0, y0, x1, y1 in boxes:
			top = max(0, y1 - panel_bottom)
			a[top:min(h, y1 + 6), max(0, x0 - 6):min(w, x1 + 7)] = 0
			areas.append((int(x0), int(top), int(x1), int(y1)))
	return Image.fromarray(a), areas


def grab(vm):
	sys.path.insert(0, "/usr/lib/virtualbox/sdk/bindings/xpcom/python")
	from vboxapi import VirtualBoxManager
	mgr = VirtualBoxManager(None, None)
	vbox = mgr.getVirtualBox()
	session = mgr.getSessionObject(vbox)
	vbox.findMachine(vm).lockMachine(session, mgr.constants.LockType_Shared)
	try:
		disp = session.console.display
		w, h, _, _, _, _ = disp.getScreenResolution(0)
		png = disp.takeScreenShotToArray(0, w, h, mgr.constants.BitmapFormat_PNG)
		return Image.open(io.BytesIO(bytes(png)))
	finally:
		session.unlockMachine()


def main():
	args = sys.argv[1:]
	out = args.pop(0)
	fixed, panel_bottom, vm, src = [], 0, None, None
	while args:
		opt = args.pop(0)
		if opt == "--vm":
			vm = args.pop(0)
		elif opt == "--file":
			src = args.pop(0)
		elif opt == "--fixed":
			fixed.append(tuple(int(v) for v in args.pop(0).split(",")))
		elif opt == "--panel-bottom":
			panel_bottom = int(args.pop(0))
		else:
			sys.exit(__doc__)
	if not fixed and not panel_bottom:
		sys.exit("redactshot: give --fixed and/or --panel-bottom")
	img = Image.open(src) if src else grab(vm)
	red, areas = redact(img, fixed, panel_bottom)
	red.save(out)
	print(out, "redacted:", areas if areas is not None else "WHOLE IMAGE")
	sys.stdout.flush()
	os._exit(0)  # skip vboxapi's noisy teardown


main()
