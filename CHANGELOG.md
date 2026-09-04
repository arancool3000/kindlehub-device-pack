# Changelog

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
