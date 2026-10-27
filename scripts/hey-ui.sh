# hey-ui.sh — shell functions for driving a Haiku app's views with `hey`,
# for when the VM's pointer can't click (PS/2; see references/porting.md §6).
# Copy it into the guest and source it:
#
#   scp scripts/hey-ui.sh <guest>:/tmp/ && ssh <guest>
#   APP=EasyPaint VIEW='View canvas of View scroller of Window "Untitled"' . /tmp/hey-ui.sh
#   drag 30 60 200 30          # primary-button drag in view coordinates
#   drag 220 110 300 180 2     # secondary button
#   click 60 140
#   win COPY                   # send a message (4-char code) to WIN
#   app 'tool with tool="int32(5)"'  # send to the application
#
# Mouse messages reach the view through BWindow::DispatchMessage, so the
# app's own MouseDown/MouseMoved/MouseUp run. Address windows by title:
# indices change as windows open and close.
APP=${APP:?set APP=<app name or signature>}
VIEW=${VIEW:?set VIEW='View <name> of … of Window "<title>"'}
WIN=${WIN:-Window 0}
# Specifiers keep their quotes through eval, so titles may contain spaces.
h(){ eval "hey \"\$APP\" $*" >/dev/null 2>&1; }
down(){ h "let $VIEW do _MDN with be:view_where='BPoint($1,$2)' and buttons='int32(${3:-1})' and clicks='int32(1)'"; }
move(){ h "let $VIEW do _MMV with be:view_where='BPoint($1,$2)' and buttons='int32(${3:-1})'"; }
up(){ h "let $VIEW do _MUP with be:view_where='BPoint($1,$2)' and buttons='int32(0)'"; }
drag(){ down $1 $2 ${5:-1}; move $(( ($1+$3)/2 )) $(( ($2+$4)/2 )) ${5:-1}; move $3 $4 ${5:-1}; up $3 $4; }
click(){ down $1 $2 ${3:-1}; up $1 $2; }
win(){ h "let $WIN do $*"; sleep 0.3; }
app(){ h "$*"; sleep 0.3; }
