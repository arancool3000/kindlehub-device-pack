# How it works

Notes on the internals of a Paperwhite 11 on 5.19.2 — the device this was
built on — and why each part is built the way it is, plus what was done to make
it run on other Kindles. Useful if you want to change something, verify it on
another model, or understand why an obvious-looking approach was not taken.

---

## The device

```
model        Paperwhite 11 / PW5, codename bellatrix, MediaTek
panel        1236 x 1648, 8bpp greyscale
/            ext3, ~494MB, around 94% full, mounted read-only
/mnt/us      FAT, the partition you see over USB
/var/local   read-write, ~161MB free — the place to put things
```

`/` being both nearly full and read-only is the constraint behind most of the
design here. `mntroot rw` and `mntroot ro` switch it, and every script that
does so restores it with an `EXIT` trap.

## Fullscreen: the window manager places windows by title

The window manager is `awesome`, configured by Lua under `/etc/xdg/awesome`. It
does not lay windows out by application — it parses the **window title**:

```
L:<layer>_N:<name>_..._PC:<T|TS|N>_ID:<app>
```

`PC` is the persistent-chrome reservation, and it is the whole mechanism.
`lab126_chrome_layer.lua` turns it into a pixel offset:

```lua
function chrome_get_persistent_top_offset(PC)
    local offset = 0
    if PC == "T" then offset = chromeLayer.activeBars["T"].height
    elseif string.find(PC, "TS") then
        offset = chromeLayer.activeBars["S"].height + chromeLayer.activeBars["S"].y
    end
    return offset
end
```

and `lab126_application_layer.lua` subtracts it from the window:

```lua
topOffset = chrome_get_persistent_top_offset(appWindow.params.PC)
appClientGeometry.y      = g_screenOne.geometry.y + topOffset
appClientGeometry.height = screenHeight - (topOffset + bottomOffset)
```

The stock browser asks for `PC:TS` — title bar plus search bar, 101 + 115 = 216
pixels. Force `PC` to `N` for the browser and the page gets the whole panel.
That is the entire patch:

```lua
if id == "com.lab126.browser" or string.find(nm, "com.lab126.browser", 1, true) then
    local kh = io.open("/mnt/us/kindlehub_fullscreen", "r")
    if kh then kh:close() updatedWindow.params.PC = "N" end
end
```

**Where it goes matters.** The first attempt patched `prv_position_application`,
at geometry time — and did nothing, because `chrome_set_app_chrome_state()`
reads `params.PC` *before* geometry is computed and had already reserved the
bars. It has to go in the update path, after `PC` is first assigned and before
`chrome_set_app_chrome_state`.

**Why a flag file.** The behaviour is gated on `/mnt/us/kindlehub_fullscreen`
rather than being unconditional in the Lua. `/etc` is not visible over USB, so a
switch living only there could not be turned off from a computer if it
misbehaved. `/mnt/us` is the first thing you see when you plug the Kindle in.

**Why not patch the binary.** `PC:TS` is not a string literal anywhere in the
39MB stripped window-manager binary — the title is assembled at runtime. There
is nothing to patch.

**Why the patch is applied on the device.** The two modules it changes are
Amazon's, marked proprietary, so this pack does not redistribute them. What it
ships is `theme/wm/kh_patch.lua`: the inserted lines and the exact anchor each
one goes after or before. `Fullscreen ON` runs it with KOReader's `luajit`
against the module on the device, and every anchor must be found exactly once
or it writes nothing. The shell then syntax-checks the output and runs
`kh_patch.lua verify`, which strips the inserted blocks back out and demands
the remainder be byte-for-byte the input. On 5.19.2 it additionally md5-checks
the output against the result this was developed with (`3472a42f…` for the
application layer, `60ec1f74…` for the dialog layer). Only then does anything
reach `/etc`.

## Other Kindles

The window manager has barely changed across the 5.x line. The same three
anchors, the same `chrome_get_persistent_top_offset` with the same `T` / `TS`
branches, and the same `blankBackground` special case are in the 5.11.1.1
(Paperwhite 2) and 5.13.2 (Paperwhite 4) modules — the only difference found
was four trailing spaces on the blank line after `log("application is
normal")`, which is why that anchor is matched by line rather than by exact
bytes. `tools/sandbox-test.sh` fetches those two firmwares' modules from public
dumps and runs the whole installer against them on a computer, with `mntroot`,
`mount`, `md5sum` and `eips` stubbed.

What that proves is that the patch *applies* and is *inert when off*. Whether
the browser actually fills the panel on a Paperwhite 4 is a thing only a
Paperwhite 4 can show; the install log and `fullscreen.info` record what is
needed to say so.

Everything else that touches a device-specific file checks first:

| Part | Assumption on the PW11 | What it does elsewhere |
|---|---|---|
| Power button | `event0`, `bd71828-pwrkey` | reads `/proc/bus/input/devices`; the device whose `KEY` bitmap has bit 116 (`KEY_POWER`) wins, then a *pwr/power* name, then a generic button device; touchscreens and sensors are excluded; logs the table and the choice |
| Icons | `/app/KPPMainApp/res` exists | skips as a success if it does not (the pre-SVG UI) |
| Restart art | `bg_reboot.png` is a 1236×1648 regular file | reads the PNG header of the device's file; skips on a size mismatch (naming the size) or a symlink (5.13 links it to `bg_default.png`) |
| Our restart | art matches the panel | asks fbink for the panel size and scales the art if it differs |
| Swipe-back | `/usr/bin/browser` with `--content-shell-host-window-cord=0,215` | skips if the launcher is missing (WebKit browser) or has no `--enable-grayscale-mode` anchor; guards the cord value as *unchanged*, not as `0,215` |
| Backups | known md5s | records each backup's md5 beside it; Undo and Health Check verify against that; a backup from another firmware is refused |

## The Control Centre

Blocked while fullscreen by `lab126_dialog_layer.lua`, which hides the window
when `params.A == "QuickSettingsWindow"` and the flag file exists.

Screenshots are handled in `lab126_button_handling.lua`, a different module,
which is deliberately left alone — so screenshots keep working.

## Power-button gestures

The button is a raw input device, not something lipc exposes:

```
/dev/input/event0        bd71828-pwrkey          (on the Paperwhite 11)
16-byte input_event      type=0100  code=7400  value=01000000 on press
```

The daemon reads it with `dd bs=16 count=1` under a `timeout`, counts presses
inside a one-second window, and acts on 1, 2 or 3. Which `eventN` to read is
decided at start from `/proc/bus/input/devices` (see *Other Kindles* above),
never assumed.

**The button cannot simply be rebound.** Taking the input device away from
`powerd` needs an `EVIOCGRAB` ioctl, which shell cannot issue, and would mean
racing `powerd` for the same key. So it is inverted: `preventScreenSaver=1`
stops *anything* sleeping the device — the power button included — and the
daemon watches the events itself and decides. Sleeping is therefore
synthesised, not passed through: drop the block, set `powerButton 1`, wait,
re-arm. One tap and the cover run the same function.

**The wake press has to be eaten.** evdev hands every reader a copy of the key,
which is what makes the daemon possible at all — but the press that *wakes* the
device is delivered to it too. Left alone it reads as a fresh 1-tap gesture and
sleeps the device again, so the button could never wake it. After a button
sleep the daemon marks `/var/tmp/kh_wake_pending` and swallows the next press;
waking by cover clears the marker instead.

**Only one daemon may run, and `$$` cannot enforce it.** The script backgrounds
itself as `{ ...; } &`, and `$$` does not change in a subshell — it stays the
parent's pid, and the parent exits immediately. A guard written inside the block
can therefore neither identify itself nor find its predecessor, which is why an
earlier `ps | grep BrowserDaemon` take-over never once fired and four daemons
ended up sharing one power button. The take-over now runs in the **parent**,
where `$!` is the block's real pid, recorded in `/var/tmp/kh_browserd.pid`; the
block learns its own pid from `/proc/self/stat`, and only tears down the shared
flag if that pid still owns it. The grace period is longer than the 30-second
blocking read, because a shell defers a `TERM` trap until the current foreground
command returns.

**Cover detection is a magnet, not power.** The cover reports through
`com.lab126.hal` as `magSensorClosed` / `magSensorOpened`. `powerd` never
mentions it, which is why looking there first found nothing.

**Do not use `ps` to check for the browser.** It runs via `chroot` and busybox
`ps` does not show it. Ask the window manager:

```sh
lipc-get-prop com.lab126.winmgr getActiveAppTitle | grep -q com.lab126.browser
```

An earlier version logged "relaunched" without checking, then relaunched an
already-running browser twice more, which is what produced
*"application could not be started"*.

## Icons are SVGs, not jars

The UI reads plain-text SVGs:

```
/app/KPPMainApp/res/<group>/<Name>.svg          959 of them
```

The live chrome config names them directly, e.g.
`file:///app/KPPMainApp/res/KPPUIChrome/LeftChevronDisabled.svg`.

`searchbar-assets.jar`, `systembarresources.jar` and `Reader-assets.jar` were
each patched, installed, md5-verified and survived a restart — and nothing on
screen changed, three times. They are the legacy path and nothing loads them.

`/app/KPPMainApp` is React Native and its bundle is **Hermes bytecode**, not
editable JavaScript. Icons are reachable; wording generally is not.

## Restart

Ours arms a watchdog **before** it stops anything:

```sh
WD="sleep 30; sync; sync; exec $REAL -f"
setsid sh -c "$WD" </dev/null >/dev/null 2>&1 &
```

so a failure partway through still results in a restart 30 seconds later rather
than a device sitting at 12%.

It deliberately **never stops `lab126`, `framework` or `x`**. Copying Amazon's
service list verbatim included `lab126` — the framework the script is itself
running under — and the script died mid-shutdown having stopped the UI.

The `/sbin/reboot` wrapper passes `halt`, `poweroff` and `-f` straight through
to the real binary, and falls through to it if `/mnt/us/kindlehub_reboot.sh` is
missing. That missing-file fallthrough is the off switch.

**The boot progress bar is not real progress** — it is a fixed animation. The
restart artwork also has to leave `y = 630..980` clear, because Amazon overlays
its own text and a white bar on whatever background is there.

## Scriptlets belong in KUAL

Loose `.sh` files in `documents/` get classified by the content indexer as
personal documents and disappear from a Books-filtered library view — they
appear, then vanish one by one. KUAL reads `menu.json` directly and never
consults the indexer.

A KUAL extension needs **both** `menu.json` and `config.xml`. With only
`menu.json`, KUAL ignores the extension and the menu never appears.

## Things that do not work, and why

| | |
|---|---|
| Boot logo | bootloader is locked |
| D-Bus to `awesome` | there is no bus to talk to |
| Binary-patching the chrome token | `PC:TS` is not a literal in the binary |
| Editing UI wording | it is in the Hermes bytecode bundle |
| A browser home page | there is no such mechanism — putting a default URL in `/usr/bin/browser` hijacks Search Kindle and every link tap, because the framework passes no arguments |
| SSH over WiFi to some routers | client isolation. The Kindle can reach the computer; the computer cannot reach the Kindle |
| USB networking | `volumd` holds the UDC, and the native `usbnetd` is diagnostics-only |
