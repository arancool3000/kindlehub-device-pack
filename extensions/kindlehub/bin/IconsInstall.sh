#!/bin/bash
# Name: Install Icons
# Author: repair
# DontUseFBInk

## Replaces the real UI icons with KindleHub ones.
##
## WHY THIS IS THE RIGHT TARGET, AFTER THREE THAT WERE NOT
##   searchbar-assets.jar, systembarresources.jar and Reader-assets.jar were each
##   patched, installed, md5-verified and survived a restart -- and nothing on
##   screen changed, three times. The App Probe explains it: the UI reads
##       /app/KPPMainApp/res/<group>/<Name>.svg
##   959 plain-text SVGs. The jars are the legacy path and nothing loads them.
##   The live chrome config names these files directly, e.g.
##       file:///app/KPPMainApp/res/KPPUIChrome/LeftChevronDisabled.svg
##
## WHAT IT REPLACES
##   Only names that ALREADY EXIST are overwritten -- no new files are created,
##   so the app cannot be handed an icon it did not ask for. Every original is
##   copied to the backup first, and "Icons OFF" restores them byte-for-byte.
##
## SPACE
##   / is 94% full with ~28M free. These SVGs are ~1KB each and replace files of
##   about the same size, so the net change is close to zero. The script still
##   checks free space before writing and refuses if it is tight.

SRC=/mnt/us/kindlehub_theme/icons
DST=/app/KPPMainApp/res
BAK=/mnt/us/kindlehub_theme_backup/icons_orig
LOG=/mnt/us/kindlehub_icons.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}

RW=0
restore_ro() {
    if [ "$RW" = "1" ]; then
        sync; mntroot ro >/dev/null 2>&1
        mount | grep ' / ' | grep -q '(ro' && RW=0
        sync
    fi
}

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo "Install icons - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - installing icons" 2

    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT - eject first"; screen "Eject the USB cable first" 4; return 1; }
    [ -d "$SRC" ] || { log "ABORT no $SRC"; screen "Icon files not found" 4; return 1; }
    [ -d "$DST" ] || { log "ABORT no $DST"; return 1; }

    N=$(find "$SRC" -name '*.svg' 2>/dev/null | wc -l)
    log "$N replacement icons staged"
    [ "$N" -gt 0 ] || { log "ABORT nothing to install"; return 1; }

    ## ---- space check ----
    FREE=$(df /  2>/dev/null | tail -1 | awk '{print $4}')
    log "free on /: ${FREE}KB"
    if [ "${FREE:-0}" -lt 2000 ]; then
        log "ABORT under 2MB free on / - refusing to write"
        screen "Not enough free space on /" 4; return 1
    fi

    ## ---- back up originals ----
    screen "1/3  backing up originals           " 4
    mkdir -p "$BAK" 2>/dev/null
    B=0
    for f in $(find "$SRC" -name '*.svg' 2>/dev/null); do
        rel=${f#$SRC/}                     # e.g. KPPUIChrome/Close.svg
        orig="$DST/$rel"
        [ -f "$orig" ] || { log "skip $rel (no such icon on device)"; continue; }
        mkdir -p "$BAK/$(dirname "$rel")" 2>/dev/null
        [ -f "$BAK/$rel" ] || cp "$orig" "$BAK/$rel" 2>/dev/null
        B=$((B+1))
    done
    log "$B originals backed up to $BAK"

    ## ---- install ----
    screen "2/3  writing icons                  " 4
    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then
        RW=1
    else
        log "FAIL could not remount /"; return 1
    fi
    OK=0; SKIP=0
    for f in $(find "$SRC" -name '*.svg' 2>/dev/null); do
        rel=${f#$SRC/}
        orig="$DST/$rel"
        ## Only ever overwrite something that already exists.
        [ -f "$orig" ] || { SKIP=$((SKIP+1)); continue; }
        if cp "$f" "$orig" 2>/dev/null; then
            chmod 644 "$orig" 2>/dev/null; OK=$((OK+1))
        else
            log "FAIL writing $rel"
        fi
    done
    restore_ro
    log "installed $OK, skipped $SKIP (not present on device)"

    ## ---- verify ----
    screen "3/3  verifying                      " 4
    V=0
    for f in $(find "$SRC" -name '*.svg' 2>/dev/null); do
        rel=${f#$SRC/}
        grep -q 'KindleHub' "$DST/$rel" 2>/dev/null && V=$((V+1))
    done
    log "verified $V of $OK now carry the KindleHub marker"
    log "/ is: $(mount | grep ' / ' | grep -o '(r[ow]')"

    if [ "$V" -gt 0 ]; then
        screen "                                        " 4
        screen "  ICONS INSTALLED                       " 3
        screen "  $V icons replaced                      " 5
        screen "                                        " 7
        screen "  RESTART to see them                   " 7
        echo; echo "  The UI caches its icons, so restart before judging the result."
        echo "  \"Undo > Icons OFF\" restores every original byte-for-byte."
    else
        screen "Nothing was installed - see log" 4
    fi
    sync
}

: > "$LOG" 2>/dev/null
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
