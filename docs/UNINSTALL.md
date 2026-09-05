# Removing KindleHub

## The normal way

> KUAL → KindleHub → Undo → **Uninstall Everything**

It runs the six Undo steps in order and restores every original file from
`/mnt/us/kindlehub_theme_backup`. It takes a couple of minutes, mostly because
of the icons. Restart when it finishes.

It **waits between steps**. Each Undo script backgrounds itself and returns
immediately, and most of them remount `/` read-write. Run back to back they
would overlap, and the first to finish would remount `/` read-only underneath
the others. So each step waits for `/` to be read-only again before starting,
and is skipped rather than raced if it is not.

Two things are left in place on purpose:

- `/mnt/us/kindlehub_theme_backup` — the original files. Deleting these would
  make any later Undo impossible.
- `/mnt/us/extensions/kindlehub` — this menu. Removing it mid-run would delete
  the script that is running.

Delete both over USB once you are happy with the result.

## Removing one piece

Each has its own entry under **Undo**:

| Entry | Restores |
|---|---|
| Icons OFF | every original SVG, byte for byte |
| Fullscreen OFF | `lab126_application_layer.lua` and `lab126_dialog_layer.lua` |
| Restart Artwork OFF | Amazon's `/usr/share/blanket/shutdown` images |
| Amazon's Restart Back | the real `/sbin/reboot` |
| Swipe-Back ON | `/usr/bin/browser` |

## If you cannot reach the menu

Two of the changes have an off switch that needs no device access at all. Plug
the Kindle into a computer and delete a file:

| Delete | Effect |
|---|---|
| `kindlehub_fullscreen` | the browser goes back to having its bars |
| `kindlehub_browserd_on` | the power button behaves normally again |
| `kindlehub_reboot.sh` | the `/sbin/reboot` wrapper falls through to Amazon's real one |

These live at the top level of the Kindle, visible over USB. This is why the
switches are on `/mnt/us` and not in `/etc` — `/etc` is not visible over USB, so
a switch that lived only there could not be undone if it misbehaved.

Then eject and restart. The Lua patch is still installed after deleting
`kindlehub_fullscreen`, but it does nothing without the flag file.

## Verifying you are back to stock

Run **Health Check**, or over USB read `/mnt/us/kindlehub_uninstall.log`. The
window manager should be back to Amazon's original — the md5 recorded when the
backup was taken, in `kindlehub_theme_backup/lab126_application_layer.lua.orig.md5`
(and the dialog layer's beside it). On a Paperwhite 11 / 5.19.2 those are:

```
lab126_application_layer.lua   27ab0e2ec6519eb0428418493bd783f8
lab126_dialog_layer.lua        ef4eb9bbf1899bab1a362184b1889717
```

Either way, the file should contain no line mentioning KindleHub; the
uninstall log says so explicitly.
