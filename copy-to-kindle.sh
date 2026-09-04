#!/bin/bash
# KindleHub - copy this release onto a Kindle plugged into a Mac or Linux box.
#
# Run it from a terminal on your COMPUTER, not on the Kindle:
#
#     ./copy-to-kindle.sh
#
# It copies the KUAL extension and the theme payload, unpacks the icons, and
# ejects the Kindle. Nothing is installed on the device by this script -- you
# still do that from KUAL > KindleHub > Install Everything, which is deliberate:
# the install writes to a read-only root filesystem and must not be racing a
# USB session. The Kindle also refuses to install while the cable is attached.

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

## ---- find the Kindle ----
KINDLE="${1:-}"
if [ -z "$KINDLE" ]; then
    for v in /Volumes/* /media/*/* /mnt/*; do
        [ -d "$v" ] || continue
        ## A Kindle root always has these two. Checking for them rather than the
        ## volume name means a renamed device is still found, and a random USB
        ## stick called "Kindle" is not.
        if [ -d "$v/documents" ] && [ -d "$v/system" ]; then KINDLE="$v"; break; fi
    done
fi
[ -n "$KINDLE" ] || die "no Kindle found. Plug it in, wait for it to mount, then re-run.
       If it is mounted somewhere unusual, pass the path:  ./copy-to-kindle.sh /Volumes/Kindle"
[ -d "$KINDLE/documents" ] || die "$KINDLE does not look like a Kindle (no documents folder)"
say "Kindle: $KINDLE"

## ---- sanity-check this release before writing anything ----
for p in "$HERE/extensions/kindlehub/menu.json" \
         "$HERE/extensions/kindlehub/config.xml" \
         "$HERE/extensions/kindlehub/bin/KindleHubInstall.sh" \
         "$HERE/theme/icons.tar.gz" \
         "$HERE/theme/wm/kh_patch.lua"; do
    [ -f "$p" ] || die "this release is incomplete - missing ${p#$HERE/}"
done

FREE_KB=$(df -k "$KINDLE" | tail -1 | awk '{print $4}')
say "free on Kindle: $((FREE_KB / 1024))MB"
[ "${FREE_KB:-0}" -gt 20000 ] || die "under 20MB free on the Kindle - free some space first"

## ---- copy ----
say "copying the KUAL extension..."
mkdir -p "$KINDLE/extensions" || die "cannot write to $KINDLE"
rm -rf "$KINDLE/extensions/kindlehub"
cp -R "$HERE/extensions/kindlehub" "$KINDLE/extensions/kindlehub" || die "copy failed"

say "copying the theme payload..."
rm -rf "$KINDLE/kindlehub_theme"
mkdir -p "$KINDLE/kindlehub_theme"
cp -R "$HERE/theme/." "$KINDLE/kindlehub_theme/" || die "copy failed"

say "unpacking icons..."
mkdir -p "$KINDLE/kindlehub_theme/icons"
tar -xzf "$HERE/theme/icons.tar.gz" -C "$KINDLE/kindlehub_theme/icons" || die "could not unpack icons.tar.gz"

## macOS sprays ._AppleDouble files and .DS_Store over FAT volumes. The Kindle's
## indexer picks them up and KUAL can trip over them, so clear them out.
find "$KINDLE/extensions/kindlehub" "$KINDLE/kindlehub_theme" \
     \( -name '._*' -o -name '.DS_Store' \) -delete 2>/dev/null

## ---- verify what actually landed ----
N_ICONS=$(find "$KINDLE/kindlehub_theme/icons" -name '*.svg' 2>/dev/null | wc -l | tr -d ' ')
N_BIN=$(find "$KINDLE/extensions/kindlehub/bin" -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
say ""
say "  icons     $N_ICONS"
say "  scripts   $N_BIN"
say "  menu      $([ -f "$KINDLE/extensions/kindlehub/menu.json" ] && echo present || echo MISSING)"
say "  config    $([ -f "$KINDLE/extensions/kindlehub/config.xml" ] && echo present || echo MISSING)"
[ "$N_ICONS" -ge 200 ] || die "only $N_ICONS icons landed - something went wrong, do not eject blind"
[ "$N_BIN"   -ge 15  ] || die "only $N_BIN scripts landed - something went wrong"

## ---- eject ----
sync
say ""
say "ejecting..."
if command -v diskutil >/dev/null 2>&1; then
    diskutil eject "$KINDLE" >/dev/null 2>&1 || die "could not eject - eject it yourself before installing"
elif command -v udisksctl >/dev/null 2>&1; then
    udisksctl unmount -b "$(findmnt -no SOURCE "$KINDLE")" >/dev/null 2>&1 || say "could not unmount automatically - eject it yourself"
else
    say "no eject tool found - eject the Kindle yourself before installing"
fi

say ""
say "Done. On the Kindle:"
say "    KUAL  >  KindleHub  >  Install Everything"
say "then restart when it tells you to."
