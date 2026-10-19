#!/bin/sh
# make-vm.sh NAME IMAGE [efi]  create a test VM from an ISO or raw disk image
# and boot it headless.
#
# The image is copied (converted to VDI), never modified. Haiku-family
# anyboot ISOs boot as a writable hard disk with BIOS; pass "efi" for
# UEFI-only images such as VitruvianOS's raw disks.
set -eu
NAME=$1
IMAGE=$2
FIRMWARE=${3:-bios}

if VBoxManage showvminfo "$NAME" >/dev/null 2>&1; then
	echo "make-vm: a VM called '$NAME' already exists" >&2
	exit 1
fi

DIR="$HOME/VirtualBox VMs/$NAME"
mkdir -p "$DIR"
VBoxManage convertfromraw "$IMAGE" "$DIR/disk.vdi" --format VDI >/dev/null

if [ "$FIRMWARE" = efi ]; then
	OSTYPE=Debian_64; GFX=vmsvga
else
	OSTYPE=Other_64; GFX=vboxsvga
fi
VBoxManage createvm --name "$NAME" --ostype "$OSTYPE" --register >/dev/null
VBoxManage modifyvm "$NAME" --firmware "$FIRMWARE" --memory 4096 --cpus 4 \
	--graphicscontroller "$GFX" --vram 64 --nic1 nat --audio-enabled off \
	--mouse usbtablet --usbohci on --ioapic on
VBoxManage storagectl "$NAME" --name SATA --add sata --portcount 2
VBoxManage storageattach "$NAME" --storagectl SATA --port 0 --device 0 \
	--type hdd --medium "$DIR/disk.vdi"
VBoxManage startvm "$NAME" --type headless
echo "Booting $NAME; take a screenshot in ~45 s: VM=$NAME sh $(dirname "$0")/vm.sh shot:boot"
