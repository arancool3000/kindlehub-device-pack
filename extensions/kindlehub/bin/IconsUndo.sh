#!/bin/bash
# Name: Undo Icons
# Author: repair
# DontUseFBInk

## Restores every original UI icon from the backup taken by "Install Icons",
## byte-for-byte. Safe to run even if only some were replaced.

BAK=/mnt/us/kindlehub_theme_backup/icons_orig
DST=/app/KPPMainApp/res
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
        mount | grep ' / ' | grep -q '(ro' && RW=0; sync
    fi
}

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo; echo "Undo icons - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - restoring icons" 2

    [ -d "$BAK" ] || { log "ABORT no backup at $BAK"; screen "No icon backup found" 4; return 1; }
    N=$(find "$BAK" -name '*.svg' 2>/dev/null | wc -l)
    log "$N originals in backup"

    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; return 1; fi

    OK=0
    for f in $(find "$BAK" -name '*.svg' 2>/dev/null); do
        rel=${f#$BAK/}
        cp "$f" "$DST/$rel" 2>/dev/null && { chmod 644 "$DST/$rel" 2>/dev/null; OK=$((OK+1)); } \
            || log "FAIL restoring $rel"
    done
    restore_ro
    log "restored $OK of $N"

    LEFT=0
    for f in $(find "$BAK" -name '*.svg' 2>/dev/null); do
        rel=${f#$BAK/}
        grep -q 'KindleHub' "$DST/$rel" 2>/dev/null && LEFT=$((LEFT+1))
    done
    log "icons still carrying the KindleHub marker: $LEFT (want 0)"
    screen "                                        " 4
    screen "  ICONS RESTORED ($OK)                  " 3
    screen "  RESTART to see them                   " 5
    sync
}

{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
