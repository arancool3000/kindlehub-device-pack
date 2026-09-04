# KindleHub

A theming and behaviour pack for a **jailbroken Kindle Paperwhite 11 (PW5)** on
firmware **5.19.2**. It gives you a genuinely fullscreen web browser with
power-button gestures, 229 redrawn UI icons, a themed restart screen, and a few
fixes for things the stock software gets wrong.

Everything it changes is backed up first and reversible from the same menu.

---

## What you get

| | |
|---|---|
| **Fullscreen browser** | The title bar and search bar are gone — the page uses all 1236×1648. Not a "hide the bar" trick; the window manager is told the browser reserves no chrome, so the page is actually laid out full-height. |
| **Power-button gestures** | **2 taps** show or hide the browser bar. **3 taps** leave fullscreen and go Home. A single tap no longer sleeps the device while the browser is up. |
| **Cover-only sleep** | While the browser is running, the device sleeps when you close the magnetic cover and at no other time. |
| **229 UI icons** | Redrawn in one consistent line style across the home screen, library, reader menu, quick settings, browser chrome and settings. |
| **Themed restart** | Your own artwork on the restart screen, and optionally your own restart sequence instead of Amazon's. |
| **Swipe-back fix** | Overscrolling in the browser no longer jumps to the previous *tab*. |
| **WiFi login fix** | One tap to re-authenticate on WPA2-Enterprise networks instead of waiting ~3 minutes for the stock retry. |
| **No more crash dumps** | Clears the `fastmetrics` crash files that pile up in your documents folder. |

## Requirements

- Kindle Paperwhite 11 / PW5 (`bellatrix`), **firmware 5.19.2**
- Jailbroken, with **KUAL** installed and working
- **KOReader** installed — its bundled `luajit` builds the window-manager patch
  from the modules already on your device and syntax-checks the result before
  anything is written. The installer refuses to proceed without it

The installer checks the firmware and **stops on anything other than 5.19.2**.
This is not caution for its own sake: the two window-manager patches are matched
to that build by md5, and applying them to a different one would either be
rejected or break the window manager.

Amazon's own Lua is not included in this pack. `theme/wm/kh_patch.lua` holds
only the lines KindleHub adds and where they go; the installer applies them to
the copies on your Kindle and refuses the result unless its md5 is the known-good
one. See [docs/HOW-IT-WORKS.md](docs/HOW-IT-WORKS.md).

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
tools/                     regenerate the icons (needs python3 only)
docs/                      install, uninstall, troubleshooting, internals
```

Nothing here phones home, and nothing runs at boot except what you explicitly
turn on from the menu.

## Safety

- Every file replaced on the read-only root is **backed up first**, and the
  backup is md5-verified before the write happens.
- A backup is only ever taken from a **pristine** file. If the original is
  already patched, the install refuses rather than saving a patched file as the
  "original" and making Undo useless.
- `/` is remounted read-write only for the moment of the write, and put back
  read-only by an `EXIT` trap even if the script dies partway.
- The patched Lua is **built on the device from its own modules**, accepted
  only if it is byte-for-byte the known-good result, and **parsed by the
  device's own luajit** before it is installed. A syntax error in a
  window-manager module would leave you with no UI at all, so unverified Lua
  is never written.
- **"Use Our Restart" is opt-in** and not part of Install Everything. It
  replaces `/sbin/reboot`. It is safe — it arms a watchdog before it stops
  anything, and never stops the framework it is running under — but it is the
  one change that can leave the device mid-shutdown if the environment is not
  what it expects, so you turn it on deliberately.

## Licence and scope

MIT — see [LICENSE](LICENSE). This is unofficial, not affiliated with Amazon,
and only useful on a device you have already jailbroken yourself. It writes to
the system partition of your Kindle; you are choosing to do that.
