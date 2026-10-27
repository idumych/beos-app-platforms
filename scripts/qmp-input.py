#!/usr/bin/env python3
# qmp-input.py SOCK ACTION X Y   — ACTION: move | click | dclick | rclick
# Absolute pointer on QEMU's usb-tablet through QMP; X, Y in screen pixels.
# Screen size from QW/QH (default 1024x768; Haiku x86_64 under -vga std picks 1280x800).
import json, os, socket, sys, time
sock, action, x, y = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
W, H = int(os.environ.get('QW', 1024)), int(os.environ.get('QH', 768))
s = socket.socket(socket.AF_UNIX); s.connect(sock); f = s.makefile('rw')
def cmd(c):
    f.write(json.dumps(c) + '\n'); f.flush()
    while True:
        r = json.loads(f.readline())
        if 'return' in r or 'error' in r: return r
f.readline(); cmd({'execute': 'qmp_capabilities'})
def ev(events): cmd({'execute': 'input-send-event', 'arguments': {'events': events}})
def move():
    ev([{'type': 'abs', 'data': {'axis': 'x', 'value': x * 32767 // (W - 1)}},
        {'type': 'abs', 'data': {'axis': 'y', 'value': y * 32767 // (H - 1)}}])
def btn(b, down): ev([{'type': 'btn', 'data': {'button': b, 'down': down}}])
move(); time.sleep(0.2)
if action in ('click', 'dclick', 'rclick'):
    b = 'right' if action == 'rclick' else 'left'
    for _ in range(2 if action == 'dclick' else 1):
        btn(b, True); time.sleep(0.15); btn(b, False); time.sleep(0.1)
