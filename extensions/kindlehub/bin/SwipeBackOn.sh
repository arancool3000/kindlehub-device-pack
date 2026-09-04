#!/bin/bash
# Name: Swipe-Back ON
# Author: repair
# DontUseFBInk
## Restores the browser wrapper from the backup taken by "Swipe-Back OFF",
## bringing Chromium's overscroll history navigation back.

BR=/usr/bin/browser
BAK=/mnt/us/kindlehub_theme_backup/browser.swipe.orig
LOG=/mnt/us/kindlehub_swipe.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
RW=0
restore_ro() { if [ "$RW" = "1" ]; then sync; mntroot ro >/dev/null 2>&1; mount | grep ' / ' | grep -q '(ro' && RW=0; sync; fi; }

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo; echo "Swipe-back ON - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - restoring swipe-back" 2
    [ -f "$BAK" ] || { log "ABORT no backup at $BAK"; screen "No backup found" 4; return 1; }
    bash -n "$BAK" 2>/dev/null || { log "ABORT backup does not parse - refusing"; return 1; }
    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; return 1; fi
    cat "$BAK" > "$BR" && chmod 755 "$BR"
    restore_ro
    log "restored; md5 $(md5sum "$BR" | awk '{print $1}')"
    bash -n "$BR" && log "wrapper parses"
    screen "                                        " 4
    screen "  SWIPE-BACK RESTORED                   " 3
    sync
}
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
