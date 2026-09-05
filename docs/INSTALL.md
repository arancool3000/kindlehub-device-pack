# Installing

## Before you start

Check all three.

1. **KUAL works.** Open it before you start. If it says *"application error"*,
   the per-boot unsigned-app patch has not run this boot — run your jailbreak's
   hotfix and open KUAL again.
2. **KOReader is installed.** The installer uses its `luajit` at
   `/mnt/us/koreader/luajit` to build the patched window-manager modules from
   the ones on your device, and to syntax-check the result before writing it.
   Without it the fullscreen step refuses to run, because a Lua syntax error
   in the window manager means no UI at all.
3. **Know what to expect on your model.** KindleHub was verified on a
   Paperwhite 11 (PW5) on firmware 5.19.2. On any other Kindle the installer
   still runs, logs your firmware and device, and each part checks the file it
   is about to change: the fullscreen patch is built from your own module and
   verified structurally, and parts that do not apply to your firmware (SVG
   icons on the older UI, the swipe-back fix on the WebKit browser, restart art
   on a different panel size) skip with a note in the log. The README's
   *What works where* table has the detail.

## Copying it across

### With the script

Plug the Kindle in, wait for it to mount, then on your computer:

```bash
./copy-to-kindle.sh
```

It finds the Kindle by looking for a `documents` and a `system` folder rather
than by volume name, checks this release is complete before writing anything,
copies both trees, unpacks the icons, removes the `._*` files macOS scatters
over FAT volumes, verifies what landed, and ejects.

If your Kindle mounts somewhere unusual, pass the path:

```bash
./copy-to-kindle.sh /Volumes/Kindle
```

### By hand

Copy two things to the root of the Kindle:

| From | To |
|---|---|
| `extensions/kindlehub/` | `<Kindle>/extensions/kindlehub/` |
| `theme/` | `<Kindle>/kindlehub_theme/` |

You can leave `icons.tar.gz` packed — the installer unpacks it on the device if
it does not find an `icons` folder. Then **eject the Kindle properly**. The
install refuses to run while the cable is attached, because writing to the
system partition during a USB session is how filesystems get corrupted.

## Installing on the device

> KUAL → KindleHub → **Install Everything**

It takes about a minute and shows its progress on screen. Six steps:

1. **Crash dumps** — deletes the `fastmetrics` crash files and indexer dumps
   from your documents folder.
2. **Icons** — 229 SVGs into `/app/KPPMainApp/res`. Only names that already
   exist are replaced; nothing new is created. Firmware without that folder
   (the older, non-SVG UI) is skipped.
3. **Fullscreen** — the two window-manager Lua modules, patched in place from
   your device's own copies. Parsed with the device's luajit and stripped back
   to the original for comparison before they are written; on 5.19.2 the
   result must also be byte-for-byte the known-good module.
4. **Restart artwork** — your artwork into `/usr/share/blanket/shutdown`, if
   the device's screen art is the same size (1236×1648) and not a symlink.
5. **Browser controls** — starts the power-button and cover daemon. The power
   button's input device is found from `/proc/bus/input/devices`.
6. **Swipe-back fix** — two Chromium flags added to `/usr/bin/browser`.
   Firmware with the older WebKit browser has no such file and is skipped.

Then **restart**. The icons are cached by the UI and the window manager only
reloads its Lua at startup, so nothing looks different until you do.

A full log is written to `/mnt/us/kindlehub_install.log`, readable over USB.

## After the restart

Run **KUAL → KindleHub → Health Check**. It is read-only and takes a few
seconds. It reports the state of every part, and in particular whether `/` was
left mounted read-write — which should never happen, but is worth knowing about
before you restart again.

Then open the browser with **KUAL → KindleHub → KindleHub Browser**.

## Installing only some of it

Everything is in **KUAL → KindleHub → Parts**, and each piece is independent:

| Entry | What it needs |
|---|---|
| Icons ON | nothing |
| Fullscreen ON | KOReader (for luajit) |
| Restart Artwork ON | nothing |
| Use Our Restart | **opt-in, read the warning in the README** |
| Swipe-Back OFF | nothing |
| SSH ON / OFF | KOReader (it uses KOReader's dropbear) |

`Use Our Restart` is deliberately not part of Install Everything.
