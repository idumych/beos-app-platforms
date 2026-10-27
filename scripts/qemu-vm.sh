#!/bin/sh
# qemu-vm.sh CMD …  — a Haiku-family x86_64 test machine (Renku, Haiku) in QEMU/KVM.
#
#   DIR=<vm dir> (default ~/VMs/haiku-x86_64)   SSH_PORT (default 2225)
#   AUDIO=wav|pipewire|none (default wav)   QCPU (default host)   QSMP (default 4)
#   create IMAGE     copy an anyboot ISO as a raw disk, grown to 4 GB (the BFS volume
#                    itself doesn't grow: ~300 MB free, enough for gcc and an app)
#   start | stop     boot headless | hard power-off (shut down from inside first)
#   shot NAME        screenshot to NAME.png (the guest picks 1280x800 under -vga std)
#   move|click|dclick|rclick X Y    absolute pointer through QMP (usb-tablet);
#                    set QW/QH to the screen size (default 1280x800 here)
#   key KEYS         QEMU key names: alt-q, ret, alt-sysrq-d (kernel debugger) …
#   type TEXT        plain text: letters, digits, space . / - _ | ' " : &
#   status
#
# AUDIO=wav writes everything the guest's sound card plays to $DIR/audio-<time>.wav
# (44.1 kHz s16 stereo; the newest is linked as $DIR/audio.wav). The file grows only
# while the guest's HDA stream runs, so each sound the guest plays is one contiguous
# block: note the size before and after. AUDIO=pipewire plays it on the host instead.
# Serial log: $DIR/serial.log (Renku writes kernel output there by default).
# SSH: 127.0.0.1:$SSH_PORT -> guest 22 (set it up once with serve-ssh-setup.sh; QEMU's
# user network reaches the host's LAN IP).
#
# KVM can't run while any VirtualBox VM is running ("KVM: entry failed, hardware
# error 0x0", VM paused with internal-error): power VirtualBox VMs off first.
# Needs qemu-system-x86_64, socat, ImageMagick, python3.
set -eu
DIR=${DIR:-$HOME/VMs/haiku-x86_64}
AUDIO=${AUDIO:-wav}
SSH_PORT=${SSH_PORT:-2225}
export QW=${QW:-1280} QH=${QH:-800}
HERE=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}; [ -n "$cmd" ] && shift
running() { [ -S "$DIR/monitor.sock" ] && echo info status | socat - "UNIX-CONNECT:$DIR/monitor.sock" >/dev/null 2>&1; }
hmp() { echo "$1" | socat - "UNIX-CONNECT:$DIR/monitor.sock" >/dev/null; }
case $cmd in
create)
	mkdir -p "$DIR"
	cp "$1" "$DIR/disk.img" && truncate -s 4G "$DIR/disk.img"
	echo "created $DIR" ;;
start)
	running && { echo "already running"; exit 0; }
	rm -f "$DIR/monitor.sock" "$DIR/qmp.sock"
	case $AUDIO in
		wav) WAV=$DIR/audio-$(date +%H%M%S).wav; ln -sf "$WAV" "$DIR/audio.wav"
			AD="-audiodev wav,id=snd0,path=$WAV" ;;
		pipewire) AD="-audiodev pipewire,id=snd0" ;;
		*) AD="-audiodev none,id=snd0" ;;
	esac
	# shellcheck disable=SC2086
	( cd "$DIR" && setsid qemu-system-x86_64 -enable-kvm -cpu "${QCPU:-host}" \
		-smp "${QSMP:-4}" -m 4096 \
		-drive file=disk.img,format=raw,if=none,id=hd0 -device ahci,id=ahci \
		-device ide-hd,drive=hd0,bus=ahci.0 \
		-netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$SSH_PORT-:22" -device e1000,netdev=n0 \
		$AD -device intel-hda -device hda-output,audiodev=snd0 \
		-vga std -device qemu-xhci -device usb-tablet -display none \
		-monitor unix:monitor.sock,server,nowait -qmp unix:qmp.sock,server,nowait \
		-serial file:serial.log > qemu.log 2>&1 & )
	sleep 2; running && echo "started (serial: $DIR/serial.log)" || { cat "$DIR/qemu.log"; exit 1; } ;;
stop)
	running || { echo "not running"; exit 0; }
	hmp quit; for i in $(seq 20); do running || break; sleep 1; done; echo stopped ;;
status)
	running && echo info status | socat - "UNIX-CONNECT:$DIR/monitor.sock" | grep -a 'VM status' || echo stopped ;;
shot)
	hmp "screendump $DIR/.shot.ppm"; sleep 1; magick "$DIR/.shot.ppm" "$1.png"; echo "$1.png" ;;
move|click|dclick|rclick)
	python3 "$HERE/qmp-input.py" "$DIR/qmp.sock" "$cmd" "$1" "$2" ;;
key)
	for k in "$@"; do hmp "sendkey $k"; sleep 0.2; done ;;
type)
	printf '%s\n' "$*" | sed 's/./&\n/g' | while IFS= read -r c; do
		case $c in
			' ') k=spc ;; .) k=dot ;; /) k=slash ;; -) k=minus ;; _) k=shift-minus ;;
			'|') k=shift-backslash ;; "'") k=apostrophe ;; '"') k=shift-apostrophe ;;
			:) k=shift-semicolon ;; '&') k=shift-7 ;;
			[A-Z]) k=shift-$(echo "$c" | tr A-Z a-z) ;;
			'') continue ;; *) k=$c ;;
		esac
		hmp "sendkey $k"; sleep 0.05
	done ;;
*) sed -n '2,27p' "$0"; exit 2 ;;
esac
