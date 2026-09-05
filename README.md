# KindleHub

A theming and behaviour pack for **jailbroken Kindles**. It gives you a
genuinely fullscreen web browser with power-button gestures, 229 redrawn UI
icons, a themed restart screen, and a few fixes for things the stock software
gets wrong.

It was developed and verified on a **Paperwhite 11 (PW5) on firmware 5.19.2**.
On any other Kindle it still runs: every part checks the exact file it is about
to change and skips, rather than guesses, if that file is not what it expects.
The fullscreen patch is built on the device from your own window-manager module
and checked structurally before anything is written. See
[What works where](#what-works-where).

Everything it changes is backed up first and reversible from the same menu.

---

## What you get

| | |
|---|---|
| **Fullscreen browser** | The title bar and search bar are gone — the page uses the whole panel (1236×1648 on a Paperwhite 11). Not a "hide the bar" trick; the window manager is told the browser reserves no chrome, so the page is actually laid out full-height. |
| **Power-button gestures** | **2 taps** show or hide the browser bar. **3 taps** leave fullscreen and go Home. A single tap no longer sleeps the device while the browser is up. |
| **Cover-only sleep** | While the browser is running, the device sleeps when you close the magnetic cover and at no other time. |
| **229 UI icons** | Redrawn in one consistent line style across the home screen, library, reader menu, quick settings, browser chrome and settings. |
| **Themed restart** | Your own artwork on the restart screen, and optionally your own restart sequence instead of Amazon's. |
| **Swipe-back fix** | Overscrolling in the browser no longer jumps to the previous *tab*. |
| **WiFi login fix** | One tap to re-authenticate on WPA2-Enterprise networks instead of waiting ~3 minutes for the stock retry. |
| **No more crash dumps** | Clears the `fastmetrics` crash files that pile up in your documents folder. |

## Requirements

- A **jailbroken Kindle** with **KUAL** installed and working
- **KOReader** installed — its bundled `luajit` builds the window-manager patch
  from the modules already on your device and syntax-checks the result before
  anything is written. The fullscreen step refuses to run without it

Amazon's own Lua is not included in this pack. `theme/wm/kh_patch.lua` holds
only the lines KindleHub adds and where they go; the installer applies them to
the copies on your Kindle and refuses the result unless it checks out. See
[docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

## What works where

**Verified** means run on the device, looked at, and used daily. **Untested**
means the code path exists and was checked against that firmware's files, but
nobody has yet pressed the button on that hardware. If you do, please
[report how it went](https://github.com/arancool3000/kindlehub-device-pack/issues)
— the install log names your firmware and every md5 involved.

| Part | Paperwhite 11 · 5.19.2 | Any other Kindle |
|---|---|---|
| Fullscreen browser | verified; result is byte-checked against the known-good module | patch built from *your* module and accepted only if every anchor is found exactly once, it parses, and stripping it back out gives your original byte for byte. The anchors are present in 5.11.1.1 (Paperwhite 2) and 5.13.2 (Paperwhite 4) firmware as well as 5.19.2 — untested on those devices |
| Power-button gestures | verified | the power button's input device is found from `/proc/bus/input/devices` (KEY_POWER bit, then name), never assumed |
| Cover-only sleep | verified | needs a magnetic cover sensor; harmless without one |
| 229 UI icons | verified | only on firmware with the newer SVG-based UI (`/app/KPPMainApp/res`); older firmware is skipped with a note |
| Restart artwork | verified | only if the device's screen art is 1236×1648 and not a symlink; otherwise skipped with a note saying what size to draw |
| Our restart sequence | verified | generic; scales the art to the panel |
| Swipe-back fix | verified | only for the Chromium browser (`/usr/bin/browser`); the older WebKit browser has nothing to fix and is skipped |
| WiFi fix, SSH, crash-dump cleanup | verified | generic |

The worst case on an untested firmware is that a part skips or that fullscreen
changes nothing: everything KindleHub inserts into the window manager is
wrapped in `pcall` and does nothing at all unless the flag file exists, so
deleting that file over USB makes it inert, and `Fullscreen OFF` restores the
original.

## Install

On your computer, with the Kindle plugged in:

```bash
./copy-to-kindle.sh
```

Then on the Kindle, **after it has ejected**:

> KUAL → KindleHub → **Install Everything**

Restart when it tells you to. Full detail, including copying by hand:
[docs/INSTALL.md](docs/INSTALL.md).

## Using the browser

Open the browser the normal way, or use **KUAL → KindleHub → KindleHub Browser**,
which turns the gesture controls on first and refuses to hide the bar if they
did not start — so you can never end up fullscreen with no way out.

| Gesture | What it does |
|---|---|
| 2 taps of the power button | show / hide the browser bar |
| 3 taps | leave fullscreen and go Home |
| close the cover | sleep |

The Control Centre is suppressed while fullscreen so a stray swipe from the top
does not drop a panel over the page. **Screenshots still work** — they are
handled in a different module, which is left untouched.

## Turning it off

> KUAL → KindleHub → Undo → **Uninstall Everything**

Every original file is restored from `/mnt/us/kindlehub_theme_backup`.

If something goes wrong and you cannot reach the menu, fullscreen and the custom
restart both have an off switch that needs no device access at all — plug the
Kindle into a computer and delete a file. See
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## How it is put together

```
copy-to-kindle.sh          copies this onto the Kindle and ejects it
extensions/kindlehub/      the KUAL menu -> /mnt/us/extensions/kindlehub
  menu.json  config.xml    both are required; without config.xml KUAL
  bin/*.sh                 ignores the extension entirely
theme/                     payload -> /mnt/us/kindlehub_theme
  icons.tar.gz             229 SVGs
  wm/                      kh_patch.lua (what KindleHub adds to the two
                           window-manager modules, applied on the device),
                           the restart wrapper and our restart script
  system/                  restart artwork
tools/                     regenerate the icons (needs python3 only), and
                           sandbox-test.sh to exercise the installer on a
                           computer against other firmwares' modules
docs/                      install, uninstall, troubleshooting, internals
```

Nothing here phones home, and nothing runs at boot except what you explicitly
turn on from the menu.

## Safety

- Every file replaced on the read-only root is **backed up first**, the backup
  is md5-verified against the file it came from, and that md5 is **recorded
  beside it** so Undo and Health Check can prove the backup is pristine on any
  firmware.
- A backup is only ever taken from a **pristine** file. If the original is
  already patched, or a backup from a different firmware is found, the install
  refuses rather than saving the wrong thing as the "original".
- `/` is remounted read-write only for the moment of the write, and put back
  read-only by an `EXIT` trap even if the script dies partway.
- The patched Lua is **built on the device from its own modules**, **parsed by
  the device's own luajit**, and **stripped back to the original and compared**
  before it is installed. On the verified build it must also be byte-for-byte
  the known-good result. A syntax error in a window-manager module would leave
  you with no UI at all, so unverified Lua is never written.
- **"Use Our Restart" is opt-in** and not part of Install Everything. It
  replaces `/sbin/reboot`. It is safe — it arms a watchdog before it stops
  anything, and never stops the framework it is running under — but it is the
  one change that can leave the device mid-shutdown if the environment is not
  what it expects, so you turn it on deliberately.

## Licence and scope

MIT — see [LICENSE](LICENSE), and [NOTICE.md](NOTICE.md) for the trademark and
at-your-own-risk notice. This is unofficial, not affiliated with Amazon, and only
useful on a device you have already jailbroken yourself. It writes to the system
partition of your Kindle; you are choosing to do that.
