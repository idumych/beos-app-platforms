# The original on BeOS 5: a reference VM for ports of BeOS apps

A port of a BeOS app is checked against the original **running on BeOS**,
not against Haiku and not against the decompiled code alone. Haiku's
app_server, fonts and control drawing aren't BeOS's, so a Haiku screenshot
says how Haiku draws the port, not what the original looked like. In Gobe
Productive every coordinate in the decompiled layout code matched the
port, yet BeOS showed the ToolBar was wrong: the element *sizes* came from
subclass constructors (28×28 tools, edges shared), the bar sat beside the
other bars rather than under them, and the pop-up triangles were blue, not
red (a packed colour read with the wrong byte order). The user put it as:
"There is no guarantee that haiku is rendering these things accurately."

Source of the setup: Adafruit's "Build a BeBox with BeOS and VirtualBox"
(learn.adafruit.com/build-a-bebox-with-beos-and-virtualbox, `?view=all`
or each page's `.md`). Steps that differ from it are marked.

## 1. Get BeOS (ask the user first)

BeOS 5.0.3 Pro, Intel and PPC, from archive.org:
`https://archive.org/details/BeosVersion5.0.3IntelAndPpc`. The item's
files (list them with `curl -s https://archive.org/metadata/<id>`) are
`BeOS_Tools.bin` (772 MB, md5 `fffb618c7a48ea2091cb554e51dcf59d`) and a
`.cue` whose FILE line names someone else's path. Downloading software
needs the user's go-ahead. Put it in its own folder in the app's dev repo,
git-ignored, and write your own cue next to it:

    FILE "BeOS_Tools.bin" BINARY
      TRACK 01 MODE1/2352
        INDEX 01 00:00:00
      TRACK 02 MODE1/2352
        INDEX 01 10:48:58
      TRACK 03 MODE1/2352
        INDEX 01 46:07:03

## 2. The VM

    V=BeOS-<App>; D=<dev repo>/vm/beos
    VBoxManage createvm --name $V --ostype Other --register --basefolder $D
    VBoxManage modifyvm $V --memory 512 --cpus 1 --vram 32 --graphicscontroller vboxsvga \
      --hwvirtex off --nested-paging off --vtx-vpid off --boot1 dvd --boot2 disk \
      --boot3 none --boot4 none --audio-driver none --audio-controller sb16 \
      --nic1 nat --nictype1 82543GC --usb off --mouse ps2 --keyboard ps2
    VBoxManage createmedium disk --filename $D/beos.vdi --size 8192 --format VDI
    VBoxManage storagectl $V --name IDE --add ide --controller PIIX3
    VBoxManage storageattach $V --storagectl IDE --port 0 --device 0 --type hdd --medium $D/beos.vdi
    VBoxManage storageattach $V --storagectl IDE --port 1 --device 0 --type dvddrive --medium $D/iso/BeOS_Tools.cue

One CPU, VT-x and nested paging off, PIIX3, PS/2 mouse (there is no
USB tablet driver: `scripts/beos-mouse.py`, §4). Audio off (the guide
mentions kernel panics with it on). No network: files go in on a CD (§5).

## 3. Install

1. `startvm --type headless`. The guide says to press Space at the purple
   boot screen for a fail-safe video mode; headless, it boots past it too
   fast. Without it the installer runs at 640×480 in grey: fine.
2. Licence: Enter (Agree is the default button).
3. More Options (the triangle) → Setup partitions… opens Drive Setup.
   Select the disk (`/dev/disk/ide/ata/0/master/0/raw`) → Setup →
   Partition → intel… → Layout → 1 100% Partition → partition 1's type
   pop-up → BeOS (it lists ~40 types; BeOS is first) → tick Active → OK →
   Proceed.
4. Expand the disk's row (its triangle), select the partition, Setup →
   Initialize → BeOS → Be File System…: **block size 2048** (the guide
   warns other sizes cause trouble), Initialize, confirm, **Mount** (the
   default button). Close Drive Setup (its close box, top left).
5. The installer picks the new volume ("untitled - 8.0 GB [Be File
   System]"): Begin (default). About 3 minutes.
6. Boot manager: Yes → Install Boot Menu, Next → MBR backup path, Next →
   rescue disk: No → keep the partition, Next → default partition and
   **Wait 5 Seconds** (so it boots unattended) → Next → Next → Yes → Done.
7. Quit (the installer reboots). **Then power off** and detach or swap the
   CD with the VM off. Swapping the CD during that reboot, or any warm
   reset (`controlvm reset`), ends in `PANIC: boot device not found` every
   time; a cold start (`poweroff`, then `startvm`) boots.

First boot: an alert "The graphics card in this machine is not supported"
(click **Don't nag**) and NetPositive with "Read Me First".

## 4. Driving it

**No SSH.** Input is VirtualBox's keyboard and a relative mouse;
everything else goes through a Terminal.

- **Mouse:** `VM=$V python3 scripts/beos-mouse.py click X Y` (also
  `move`, `rclick`, `dclick`, `drag`). It finds BeOS's hand pointer in a
  screenshot and steers it with 1-pixel relative steps: BeOS accelerates,
  so blind moves land 1.3–1.5× too far. Over a text field the pointer is
  an I-beam the script can't find: click beside the field, or skip it (a
  default name is often fine). **Events closer than ~30 ms desync BeOS's
  PS/2 driver**: the pointer disappears and nothing moves. Only a reboot
  (cold) brings it back.
- **Menus by keyboard** once one is open: Right enters a submenu, Up/Down
  move (an overflowing menu scrolls as the selection moves), Enter
  chooses. Long menus are faster this way than with the steered mouse.
- **A Terminal:** `VM=$V sh scripts/beos-terminal.sh` (Be menu →
  Applications → Terminal by keyboard; set `N` if the Applications folder
  has more entries than a fresh install).
- **Typing:** `VBoxManage controlvm $V keyboardputstring '<text>'`, then
  `keyboardputscancode 1c 9c` for Enter. Keys go to the **focused** window:
  a Tracker window takes them as type-ahead and Enter opens what it
  selected. Screenshot first if a click may have focused something else.
- **Shut down:** `sync; shutdown` in the Terminal, then `poweroff` once it
  says "It's now safe to turn off the computer". Saving the VM's state
  (`savestate`) is fine and resumes where it was.

## 5. Video mode and files in

**1024×768 colour** (the default is 640×480 grey): in the Terminal,

    cd ~/config/settings/kernel/drivers
    cp sample/kernel . && echo "disk_cache_size 16384" >> kernel
    echo "mode 1024 768 16" > vesa

then shut down and cold-start. `mode 1024 768 32` was not taken (BeOS fell
back to 640×480 grey); 16 is what works. 16-bit colour shifts greys and
tints white (f8fcf8): compare positions and sizes, not exact colours.

**Files in on a CD image** (no network needed): put the app's installer
and test documents in a folder, `xorriso -as mkisofs -R -J -V FILES -o
files.iso <folder>`, attach it as the DVD, boot, and in the Terminal:

    mkdir -p /cd; mount -t iso9660 /dev/disk/ide/atapi/1/master/0/raw /cd
    mkdir -p ~/app && cp /cd/* ~/app/ && chmod +x ~/app/Install*

(BeOS doesn't mount the data CD on its own.) Run the installer from the
Terminal (`cd ~/app && ./Install* &`); the 2000-era installers (Package
Builder style) ask to put a link in the Be menu's Applications and to
register online (No).

Launch the original with a document from the Terminal so it comes up
the same way every time:

    cd "/boot/apps/Gobe Productive 2.0"; "./Gobe Productive" Samples/Resume &

## 6. Comparing the port with it

1. Open the same document in the original (BeOS) and in the port (Haiku
   VM and/or Linux under Xvfb), with the same bars shown.
2. Measure with PIL, not by eye: per bar, the columns of the elements'
   dark borders along a row, and rows along a column, **relative to the
   bar's own origin** (the windows sit at different places; the original
   may have the ToolBar left of the bars). Example output that settled
   it: original FormatBar edges 7..127, 130..160, 163..182 vs port
   4..124, 127..157, 160..179 — the same offsets, three pixels apart.
3. Put crops side by side at 2–3× (`-filter point -resize 300%`) to see
   drawing differences: outline style, icon offset, indicator colour,
   text overflowing a box.
4. Read the original's draw code for each difference before changing the
   port, and say in the port's comment which function it follows.

What the decompiled coordinates didn't show, and BeOS did (§4b in
porting.md has the decompiling side):

- **Element sizes set in subclass constructors** (`TToolBarElement`:
  `(x + 28) - 1`), not in the layout function that places them.
- **Which bar is beside which:** a toolbar column left of every other bar,
  from the menu bar down, not under them.
- **Packed colours:** gcc2 x86 passes `rgb_color` as a 32-bit value;
  `0xffff0000` is bytes 00 00 ff ff in memory, i.e. red 0, green 0,
  **blue 255**, alpha 255. Symmetric greys (`0xffd8d8d8`) hide the
  mistake; a single asymmetric value (a pop-up triangle) shows it. List
  every asymmetric packed constant in the decompiled code and check each.
- **Font fitting:** BeOS code shrinks a font "until it fits" with
  `GetHeight()`'s ascent + descent; a port that guessed 1.2 × the size
  (Bitstream fonts' proportion) overflows with Noto and other taller
  fonts. Do what the original does.
- **Saved per-document UI state** (which bars a document opens with):
  the sample opened with a spelling bar on BeOS that the port never shows.

Keep the screenshots of the original out of the public tree unless the
user asks for them there (a README comparison, as Gobe Productive's
"Next to the original" section, is the user's call).
