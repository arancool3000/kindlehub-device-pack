# Troubleshooting

Start with **KUAL → KindleHub → Health Check**. It is read-only, takes a few
seconds, and reports the state of every part. Most of what follows is a symptom
it will already have named.

Logs are plain text at the top level of the Kindle, readable over USB:

```
kindlehub_install.log      kindlehub_fullscreen.log
kindlehub_browserd.log     kindlehub_icons.log
kindlehub_uninstall.log    kindlehub_divert.log
```

---

## Emergency stops

**Fullscreen with no way out.** Plug into a computer, delete
`kindlehub_fullscreen` from the top level of the Kindle, eject, restart.

**The power button is doing something strange.** Delete
`kindlehub_browserd_on`, eject. Sleep goes back to normal within about 30
seconds; the daemon notices the file is gone.

**Stuck on the custom restart screen.** Hold the power button for **8 seconds**.
The device force-restarts. Then delete `kindlehub_reboot.sh` over USB — the
`/sbin/reboot` wrapper falls through to Amazon's real one when that file is
missing, so the divert is disarmed without needing root.

---

## KUAL

**KUAL opens with "application error" straight away.**
Not this package. The per-boot unsigned-app patch has not run this boot. Run
your jailbreak's hotfix and open KUAL again. Because this can happen after any
restart, do not put recovery tools inside KUAL — that is why the emergency
switches above are files on `/mnt/us` instead.

**KUAL opens but there is no KindleHub menu.**
`config.xml` is missing from `/mnt/us/extensions/kindlehub/`. KUAL needs
**both** `menu.json` and `config.xml`; with only `menu.json` it ignores the
extension silently. Copy the folder across again — `copy-to-kindle.sh` checks
for both before it writes anything.

---

## Fullscreen

**It installed, I restarted, the bars are still there.**
Check three things in `kindlehub_fullscreen.log`:

- the log says `RESULT installed` (on a Paperwhite 11 / 5.19.2 the installed
  md5 is `3472a42f133a8bd13a104386cb0a49a3`; on other firmware the log says
  *structurally verified* and records the md5 it produced)
- the flag file `/mnt/us/kindlehub_fullscreen` exists
- you actually restarted — the window manager only reads its Lua at startup

If all three hold and this is not a Paperwhite 11 on 5.19.2, the patch applied
but your firmware lays the browser out differently. Please open an issue with
`kindlehub_fullscreen.log` and `kindlehub_theme_backup/fullscreen.info`; that
is exactly the report that gets another model verified.

**"installed on an untested firmware".**
Not an error. The patch was built from your module and passed every structural
check, but nobody has confirmed the result on your model yet. Restart and try
the browser; report either way.

**"KOReader (luajit) needed — aborted".**
KOReader is not installed, so there is no `luajit` at `/mnt/us/koreader/luajit`.
The patched module is built from your device's own copy with it, and verified
with it — a syntax error in a window-manager module leaves you with no UI.
Install KOReader.

**"anchor found 0 times" or "anchor found 2 times".**
The patcher could not find the single place its lines go in your module. Your
firmware's window manager is laid out differently from every version this was
checked against (5.11, 5.13, 5.19), or something else has already modified the
file. Nothing was written; `kindlehub_fullscreen.log` shows which insertion
failed. Open an issue with the log.

**"Patch did not verify — aborted" or "structural check failed".**
The patched module either did not parse with your device's luajit, or
stripping KindleHub's lines back out did not reproduce your original, or (on
5.19.2) it was not byte-for-byte the known-good file. Nothing was written.

**"existing backup … is not this firmware's file".**
`/mnt/us/kindlehub_theme_backup` holds a backup taken on a different firmware
— usually because the Kindle was updated after KindleHub was installed.
Restoring it later would put an old build's module on the new build, so the
install refuses. Delete the backup folder over USB and run again; a fresh
backup of the current file is taken.

**"No pristine backup — refusing".**
Your device holds the earlier first-attempt patch and the backup of the
original is missing. The patch is built from the original, so it cannot
proceed. Run `Fullscreen OFF` if a backup exists elsewhere, or restore
`lab126_application_layer.lua` from the firmware.

---

## Browser controls

**2 taps and 3 taps do nothing, and one tap sleeps the device.**
The daemon is not running. Run **Browser Controls ON**, then read
`kindlehub_browserd.log` — it logs the pid it started with, the input device it
found, and the value of `preventScreenSaver`. That distinguishes "never started"
from "started but not seeing events".

**The daemon is running but taps are not seen (not a Paperwhite 11).**
The log's `--- input devices ---` section lists every input device with its
name, handlers and `KEY=` bitmap, and the line above it names the one chosen.
The chooser prefers the device whose `KEY` bitmap has bit 116 (`KEY_POWER`),
then a name containing *pwr* or *power*. If it picked the wrong one, open an
issue with that section of the log; it is a one-line fix.

If the log shows *"raw-event logging off"* more than once, several copies were
running and fighting over the same input events. **Browser Controls OFF** stops
all of them; turn it back on afterwards.

**The gestures worked yesterday and do nothing today.**
The daemon exits after 24 hours on purpose, so a forgotten one cannot run
forever holding `preventScreenSaver`. Run **Browser Controls ON** again, or open
**KindleHub Browser**, which starts it for you.

**Gestures work but the browser bar does not come back.**
The bar is drawn by the window manager from the flag file, so the toggle needs
the browser to be relaunched. That is what the 2-tap gesture does. If it says it
switched but nothing changed, the browser did not come back up — check the log
for `getActiveAppTitle`.

> Note: you cannot tell whether the browser is running with `ps`. It runs inside
> a chroot and busybox `ps` does not show it. The daemon asks the window manager
> instead: `lipc-get-prop com.lab126.winmgr getActiveAppTitle`.

---

## Icons

**Installed, restarted, they look the same.**
Read `kindlehub_icons.log` for the verified count. If it installed 200-odd and
verified them, the UI is showing cached art — restart again.

**Some icons never change.**
Expected. Brand marks (Goodreads, Audible, Amazon Kids, the Prime and Unlimited
badges) and the highlighter colour swatches are deliberately not redrawn: the
badges carry meaning the shape alone does not, and restyling a colour swatch
breaks the colour picker.

**"skip <name> (no such icon on device)".**
Also expected. Nothing is ever created that the app did not already ask for, so
an icon the firmware does not have is skipped rather than added.

**"this firmware has no /app/KPPMainApp/res".**
Older firmware draws its UI from jars rather than SVG files, so there is
nothing for the icon part to replace. It skips as a success.

---

## Restart artwork

**"this device's screen art is WxH, ours is 1236x1648".**
The art is drawn for a Paperwhite 11 panel and would be cropped on any other
size, so it is skipped. Draw a PNG of the size the log names, leaving the
middle band clear for Amazon's text overlay, and put it at
`kindlehub_theme/system/shutdown/bg_reboot.png`; run **Restart Artwork ON**.

**"it is a symlink to … on this firmware".**
On some firmware `bg_reboot.png` is a link to the shared `bg_default.png`.
Writing through it would change every screen that shares the default, so it is
left alone.

---

## Filesystem

**Health Check says `/` is mounted read-write.**
Something failed partway through. Nothing here leaves it that way deliberately —
every script puts `/` back with an `EXIT` trap. Fix it before restarting:

```bash
mntroot ro
```

**"Not enough free space on /".**
The root filesystem is about 494MB and normally sits around 94% full. Free some
space, or install fewer parts. The icons are roughly a wash — each replaces a
file of about the same size.

---

## USB

**Crash files keep appearing when I plug in.**
`fastmetrics_*_crash_*.txt` and `.tgz` appearing on connect are a USB-mode
artefact of the content indexer, not a real crash — the browser is killed when
the volume is unmounted from under it and the indexer records that. Install
Everything clears them; **Health Check** counts any that have come back.

**The Kindle will not mount, or mounts and vanishes.**
Nothing to do with this package. Try a different cable — many are charge-only.
