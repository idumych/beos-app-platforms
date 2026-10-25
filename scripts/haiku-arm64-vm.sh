#!/bin/sh
# haiku-arm64-vm.sh CMD …  — a Haiku arm64 test machine in QEMU (no arm64 VirtualBox on x86).
#
#   DIR=<vm dir> (default ~/VMs/haiku-arm64)
#   create IMAGE        copy a nightly haiku-master-hrevNNNNN-arm64-mmc.image, grow it to 2 GB
#   start | stop        boot headless (UEFI, virt, 4 cores, 3 GB) | power off (VM data is kept)
#   shot NAME           screenshot to NAME.png (1024x768)
#   move|click|dclick|rclick X Y    absolute pointer (usb-tablet, QMP)
#   key KEYS            QEMU key names, e.g. key alt-q, key ret, key ctrl-esc
#   type TEXT           type plain text (letters, digits, space . / - _)
#   put FILE [DEST]     copy FILE into the guest (default /myfs/home/); VM must be stopped
#   status              running or stopped
#
# Needs qemu-system-aarch64, edk2 aarch64 firmware (QEMU_EFI.fd), socat, ImageMagick, python3,
# and bfs_shell for `put` (BFS_SHELL=, or the one tools/haiku-arm64/make-sysroot.sh builds).
# The nightly image has no SSH server: drive the desktop, and get files in with `put`.
# Emulated arm64 is slow (TCG): allow ~60 s to boot and a few seconds per action.
set -eu
DIR=${DIR:-$HOME/VMs/haiku-arm64}
HERE=$(cd "$(dirname "$0")" && pwd)
cmd=${1:-}; [ -n "$cmd" ] && shift
running() { [ -S "$DIR/monitor.sock" ] && echo info status | socat - "UNIX-CONNECT:$DIR/monitor.sock" >/dev/null 2>&1; }
hmp() { echo "$1" | socat - "UNIX-CONNECT:$DIR/monitor.sock" >/dev/null; }
firmware() {
	for f in /usr/share/edk2/aarch64/QEMU_EFI.fd /usr/share/AAVMF/AAVMF_CODE.fd \
		/usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/edk2-armvirt/aarch64/QEMU_EFI.fd; do
		[ -f "$f" ] && { echo "$f"; return; }
	done
	echo "haiku-arm64-vm: no aarch64 UEFI firmware (install edk2-aarch64 / qemu-efi-aarch64)" >&2; exit 1
}
case $cmd in
create)
	mkdir -p "$DIR"
	cp "$1" "$DIR/disk.img" && truncate -s 2G "$DIR/disk.img"
	cp "$(firmware)" "$DIR/efi.fd" && truncate -s 64M "$DIR/efi.fd"
	truncate -s 64M "$DIR/vars.fd"
	echo "created $DIR" ;;
start)
	running && { echo "already running"; exit 0; }
	rm -f "$DIR/monitor.sock" "$DIR/qmp.sock"
	( cd "$DIR" && setsid qemu-system-aarch64 -M virt -cpu max -smp 4 -m 3072 \
		-drive if=pflash,format=raw,file=efi.fd,readonly=on -drive if=pflash,format=raw,file=vars.fd \
		-device ramfb -device qemu-xhci -device usb-kbd -device usb-tablet \
		-drive file=disk.img,if=none,format=raw,id=hd0 -device virtio-blk-device,drive=hd0 \
		-netdev user,id=n0 -device virtio-net-device,netdev=n0 \
		-display none -monitor unix:monitor.sock,server,nowait \
		-qmp unix:qmp.sock,server,nowait -serial file:serial.log > qemu.log 2>&1 & )
	for i in $(seq 90); do grep -qa 'first login\|Running first login\|Deskbar' "$DIR/serial.log" 2>/dev/null && break; sleep 2; done
	sleep 10; echo "started (serial log: $DIR/serial.log)" ;;
stop)
	running || { echo "not running"; exit 0; }
	hmp quit; for i in $(seq 20); do running || break; sleep 1; done; echo stopped ;;
status) running && echo running || echo stopped ;;
shot)
	hmp "screendump $DIR/.shot.ppm"; sleep 1; magick "$DIR/.shot.ppm" "$1.png"; echo "$1.png" ;;
move|click|dclick|rclick)
	python3 "$HERE/qmp-input.py" "$DIR/qmp.sock" "$cmd" "$1" "$2" ;;
key)
	for k in "$@"; do hmp "sendkey $k"; sleep 0.2; done ;;
type)
	echo "$*" | sed 's/./&\n/g' | while IFS= read -r c; do
		case $c in
			' ') k=spc ;; .) k=dot ;; /) k=slash ;; -) k=minus ;; _) k=shift-minus ;;
			[A-Z]) k=shift-$(echo "$c" | tr A-Z a-z) ;;
			'') continue ;; *) k=$c ;;
		esac
		hmp "sendkey $k"; sleep 0.05
	done ;;
put)
	running && { echo "haiku-arm64-vm: stop the VM first (bfs_shell writes the disk)" >&2; exit 1; }
	BFS=${BFS_SHELL:-$(command -v bfs_shell || true)}
	[ -n "$BFS" ] || { echo "haiku-arm64-vm: set BFS_SHELL (built by tools/haiku-arm64/make-sysroot.sh)" >&2; exit 1; }
	OFF=$(( $(python3 -c 'import struct,sys; print(struct.unpack_from("<I", open(sys.argv[1],"rb").read(512), 446+16+8)[0])' "$DIR/disk.img") * 512 ))
	DEST=${2:-/myfs/home/}
	printf 'mkdir -p %s\ncp :%s %s\nls -l %s\nexit\n' "${DEST%/*}" "$(readlink -f "$1")" "$DEST" "${DEST%/*}" \
		| "$BFS" --start-offset "$OFF" "$DIR/disk.img" 2>&1 | grep -F "$(basename "$1")" ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
