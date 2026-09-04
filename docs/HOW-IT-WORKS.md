# How it works

Notes on the internals of a Paperwhite 11 on 5.19.2, and why each part is built
the way it is. Useful if you want to change something, port it to another
firmware, or understand why an obvious-looking approach was not taken.

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
or it writes nothing. The shell then md5-checks the output against the result
this was developed with (`3472a42f…` for the application layer, `60ec1f74…`
for the dialog layer) and syntax-checks it, before anything reaches `/etc`. A
different firmware fails the anchor check, the md5 check, or both, and the
device is left untouched.

## The Control Centre

Blocked while fullscreen by `lab126_dialog_layer.lua`, which hides the window
when `params.A == "QuickSettingsWindow"` and the flag file exists.

Screenshots are handled in `lab126_button_handling.lua`, a different module,
which is deliberately left alone — so screenshots keep working.

## Power-button gestures

The button is a raw input device, not something lipc exposes:

```
/dev/input/event0        bd71828-pwrkey
16-byte input_event      type=0100  code=7400  value=01000000 on press
```

The daemon reads it with `dd bs=16 count=1` under a `timeout`, counts presses
inside a window, and acts on 2 or 3. While the browser is up it holds
`preventScreenSaver` so a single press does not sleep the device.

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
