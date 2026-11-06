#!/bin/sh
# build.sh [OUTDIR]: builds vptr and ftouch (input for headless Wayland tests).
#
#  vptr [W H]  wlroots virtual pointer (headless sway). Start it before the app,
#              so the seat has a pointer when the app connects. stdin lines:
#              "move X Y" (absolute, in a WxH output; default 1280x800),
#              "down BTN", "up BTN" (272 left, 273 right, 274 middle), "scroll N".
#  ftouch      KWin fake input (nested headless KWin): "down X Y", "move X Y",
#              "up" (touch id 0), "mouse X Y", "press", "release" (left button).
#              KWin only grants it to a client whose .desktop file, on
#              XDG_DATA_DIRS, has X-KDE-Wayland-Interfaces=org_kde_kwin_fake_input
#              and Exec= the binary's absolute path.
#
# Both print "ready", then "ok <line>" after each event is delivered. Drive them
# through a FIFO: mkfifo vp.fifo; tail -f vp.fifo | ./vptr &; echo "move 10 10" > vp.fifo
# The protocol XML is a hand-written subset (the full files aren't installed on
# every host). Needs wayland-scanner and libwayland-client headers.
set -e
SRC=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-.}
mkdir -p "$OUT"
for p in virtual-pointer fake-input; do
	wayland-scanner client-header "$SRC/$p.xml" "$OUT/$p.h"
	wayland-scanner private-code "$SRC/$p.xml" "$OUT/$p.c"
done
cc -O2 -I"$OUT" -o "$OUT/vptr" "$SRC/vptr.c" "$OUT/virtual-pointer.c" -lwayland-client
cc -O2 -I"$OUT" -o "$OUT/ftouch" "$SRC/ftouch.c" "$OUT/fake-input.c" -lwayland-client
echo "built $OUT/vptr $OUT/ftouch"
