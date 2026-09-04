# Installing

## Before you start

Check all four. The installer checks the first two itself and stops if they are
wrong, but the other two it cannot see.

1. **Firmware is 5.19.2.** Settings → Device Options → Device Info. Anything
   else and the install stops — the window-manager patches are md5-matched to
   this build.
2. **The device is a Paperwhite 11 (PW5).** Other Kindles have a different
   screen size and a different window manager layout.
3. **KUAL works.** Open it before you start. If it says *"application error"*,
   the per-boot unsigned-app patch has not run this boot — run your jailbreak's
   hotfix and open KUAL again.
4. **KOReader is installed.** The installer uses its `luajit` at
   `/mnt/us/koreader/luajit` to build the patched window-manager modules from
   the ones on your device, and to syntax-check the result before writing it.
   Without it the fullscreen step refuses to run, because a Lua syntax error
   in the window manager means no UI at all.

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
   exist are replaced; nothing new is created.
3. **Fullscreen** — the two window-manager Lua modules, patched in place from
   your device's own copies and md5-verified before they are written.
4. **Restart artwork** — your artwork into `/usr/share/blanket/shutdown`.
5. **Browser controls** — starts the power-button and cover daemon.
6. **Swipe-back fix** — two Chromium flags added to `/usr/bin/browser`.

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
