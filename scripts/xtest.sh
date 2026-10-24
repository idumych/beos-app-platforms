#!/bin/sh
# xtest.sh STEP...  drive a Cosmoe app under Xvfb :99 + Openbox.
#
# Start the display first (keep both running in the background):
#   Xvfb :99 -screen 0 1280x800x24 -nolisten tcp &
#   DISPLAY=:99 openbox &
#
#   XDISPLAY=:N        X display to use (default :99; pick another if one is in use)
#   APP=<cmd>          what to launch (a binary or an AppImage; required)
#   APP_NAME=<name>    its process name, for pkill (default: basename of APP)
#   LIBDIR=<dir>       LD_LIBRARY_PATH for a local build (unset for AppImages)
#   HOME_DIR=<dir>     throwaway home (default $SCRATCH/home)
#   SCRATCH=<dir>      logs, screenshots, fake xdg-open (default /tmp/beos-xtest)
#
# Steps:
#   start            (re)launch the app; its output goes to $SCRATCH/app.log
#   c:x,y  r:x,y     left / right click, button held 150 ms (zero-length
#                    clicks froze upstream Cosmoe windows; fixed in Kireji)
#   cc:x,y ac:x,y    ctrl- / alt-click
#   d:x1,y1,x2,y2    drag
#   k:<keys>         xdotool key names, e.g. k:ctrl+r k:Return
#   t:<text>         type text
#   w:<secs>         wait
#   shot:<name>      screenshot to $SCRATCH/<name>.png
#
# The app never sees the user's real session: WAYLAND_DISPLAY is removed,
# COSMOE_BACKEND=x11, HOME is a throwaway, and xdg-open is replaced by a
# stub that appends its arguments to $SCRATCH/xdg-open.log.
SCRATCH=${SCRATCH:-/tmp/beos-xtest}
HOME_DIR=${HOME_DIR:-$SCRATCH/home}
APP=${APP:?set APP=<binary or AppImage>}
APP_NAME=${APP_NAME:-$(basename "$APP" | sed "s/-.*AppImage$//; s/\.AppImage$//")}
export DISPLAY=${XDISPLAY:-:99}
mkdir -p "$SCRATCH/fakebin" "$HOME_DIR"

press() {	# press X Y BUTTON
	# Hover first: a menu item clicked the instant the pointer lands on it is ignored.
	xdotool mousemove "$1" "$2"
	sleep 0.3
	xdotool mousedown "$3"
	sleep 0.15
	xdotool mouseup "$3"
}

for step in "$@"; do
	v=${step#*:}
	x=$(echo "$v" | cut -d, -f1)
	y=$(echo "$v" | cut -d, -f2)
	case "$step" in
	start)
		pkill -x "$APP_NAME"; sleep 1
		printf '#!/bin/sh\necho "xdg-open $*" >> "%s/xdg-open.log"\n' "$SCRATCH" \
			> "$SCRATCH/fakebin/xdg-open"
		chmod +x "$SCRATCH/fakebin/xdg-open"
		( env -u WAYLAND_DISPLAY -u XDG_CONFIG_HOME -u XDG_DATA_HOME \
			PATH="$SCRATCH/fakebin:$PATH" HOME="$HOME_DIR" COSMOE_BACKEND=x11 \
			${LIBDIR:+LD_LIBRARY_PATH="$LIBDIR"} \
			$APP > "$SCRATCH/app.log" 2>&1 & )
		sleep 7 ;;
	c:*)  press "$x" "$y" 1 ;;
	r:*)  press "$x" "$y" 3 ;;
	cc:*) xdotool keydown ctrl; press "$x" "$y" 1; xdotool keyup ctrl ;;
	ac:*) xdotool keydown alt; press "$x" "$y" 1; xdotool keyup alt ;;
	d:*)
		x2=$(echo "$v" | cut -d, -f3); y2=$(echo "$v" | cut -d, -f4)
		xdotool mousemove "$x" "$y" mousedown 1; sleep 0.2
		for i in 1 2 3 4 5 6 7 8; do
			xdotool mousemove $((x + (x2 - x) * i / 8)) $((y + (y2 - y) * i / 8))
			sleep 0.05
		done
		sleep 0.2; xdotool mouseup 1 ;;
	k:*)  xdotool key --delay 80 $v ;;
	t:*)  xdotool type --delay 60 "$v" ;;
	w:*)  sleep "$v" ;;
	shot:*) import -window root "$SCRATCH/$v.png" && echo "$SCRATCH/$v.png" ;;
	*) echo "xtest.sh: unknown step '$step'" >&2; exit 1 ;;
	esac
done
