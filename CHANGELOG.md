# Changelog

## 1.1.0

**Runs on any jailbroken Kindle, not only a Paperwhite 11 on 5.19.2.** The
firmware is now logged rather than gated on, and every part checks the exact
file it is about to change and skips, with a note, if it is not what it
expects.

**Fullscreen**
- `kh_patch.lua` matches its first anchor by line rather than by exact bytes:
  the blank line after `log("application is normal")` carries four spaces on
  5.11 and 5.13 firmware and nothing on 5.19.2. On 5.19.2 the output is still
  byte-identical to the known-good module
- New `kh_patch.lua verify` mode strips KindleHub's blocks back out of the
  patched module and demands the remainder be byte-for-byte the original. The
  installer runs it on every firmware; on the verified build it also keeps the
  md5 gate
- The anchors were checked against 5.11.1.1 (Paperwhite 2) and 5.13.2
  (Paperwhite 4) firmware dumps as well as 5.19.2; `tools/sandbox-test.sh`
  reproduces that check on a computer
- The backup's md5 is recorded beside it (`*.orig.md5`) and a
  `fullscreen.info` file records firmware and md5s, so `Fullscreen OFF` and
  Health Check verify against what *this* device had. A backup that belongs
  to a different firmware is refused with instructions, never restored
- A module that already carries the KindleHub marker is treated as installed
  whatever its md5

**Other parts**
- Browser controls find the power button from `/proc/bus/input/devices`
  (KEY_POWER bit, then the device name) instead of assuming `event0`; the
  choice and the whole table are logged
- Restart artwork compares PNG dimensions with the device's own screen art
  and skips symlinked screens (5.13 links `bg_reboot.png` to
  `bg_default.png`), so nothing is cropped and nothing shared is overwritten;
  our restart sequence scales the art to the panel
- Swipe-back fix guards the browser's window-cord value as "unchanged from
  what this device had" rather than a fixed `0,215`, and skips cleanly on
  firmware with the older WebKit browser
- Icons skip cleanly, as a success, on firmware without the SVG-based UI
- Health Check reports the firmware as information, checks backups against
  their recorded md5s, and knows which parts do not apply to this firmware

## 1.0.1

**Amazon's Lua is no longer shipped.** The two window-manager modules are
proprietary, so the pack now carries only the lines KindleHub adds
(`theme/wm/kh_patch.lua`) and builds the patched modules on the device, from
the copies already on it, using KOReader's `luajit`. The result is installed
only if it is byte-for-byte the known-good module (md5-checked), then
syntax-checked as before. A device that still holds the earlier first-attempt
patch is upgraded from its pristine backup. KOReader is therefore required for
Fullscreen ON, not just recommended.

**Fixes**
- `SSH Off` now deletes exactly the firewall rules `SSH On` inserts. It was
  deleting a different rule spec that had never been added, so the port stayed
  open after "off"
- `SSH On` no longer stacks a new ICMP rule on every run
- Health Check no longer reports a running browser daemon as a stale flag. The
  daemon deliberately writes an empty flag and is checked by process, as the
  launcher does; the doctor now checks the same way
- `Install Everything` waits for each part to finish and for `/` to be
  read-only again before starting the next, instead of fixed sleeps. Parts
  run in the background and remount `/`, so back-to-back starts could overlap
- Messages that named Undo entries by old names now use the menu's labels

## 1.0

First public release. Targets Paperwhite 11 (PW5) on firmware 5.19.2.

**Browser**
- Fullscreen browser via the window manager's `PC` chrome reservation, gated on
  a flag file on `/mnt/us` so it can be switched off over USB
- Power-button gestures: 2 taps toggle the bar, 3 taps leave fullscreen
- Cover-only sleep while the browser is up, using the magnetic sensor
- Control Centre suppressed while fullscreen; screenshots left working
- Swipe-back fix — overscroll no longer jumps to the previous tab

**Appearance**
- 229 redrawn UI icons across home, library, reader menu, quick settings,
  browser chrome and settings
- Themed restart artwork, drawn to leave Amazon's text overlay area clear

**System**
- Our own restart sequence, opt-in, watchdog-armed before it stops anything
- `/sbin/reboot` wrapper that falls through to Amazon's when disarmed
- WPA2-Enterprise reconnect fix
- `fastmetrics` crash-dump cleanup

**Packaging**
- One installer, firmware-gated, idempotent, md5-verified
- One uninstaller that restores every original and waits for `/` between steps
- Read-only Health Check
- `copy-to-kindle.sh` for the computer side, with verification and eject
- Reproducible icon build from `tools/`
