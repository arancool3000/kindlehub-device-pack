#!/bin/bash
# Name: Undo Restart
# Author: repair
# DontUseFBInk
## Restores Amazon's original blanket shutdown screens from the backups taken
## by "Custom Restart". Only touches images; nothing about how the device
## restarts was changed in the first place.

DST=/usr/share/blanket/shutdown
BAK=/mnt/us/kindlehub_theme_backup
LOG=/mnt/us/kindlehub_restart_theme.log

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
    echo; echo "Undo restart theme - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - restoring restart screen" 2
    N=$(ls "$BAK"/sys_shutdown_bg_*.orig 2>/dev/null | wc -l)
    log "$N backups found"
    [ "$N" -gt 0 ] || { log "ABORT no backups"; screen "No backups found" 4; return 1; }

    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; return 1; fi
    OK=0
    for b in "$BAK"/sys_shutdown_bg_*.orig; do
        n=$(basename "$b" .orig); n=${n#sys_shutdown_}
        [ -f "$DST/$n" ] || continue
        cp "$b" "$DST/$n" 2>/dev/null && { chmod 644 "$DST/$n"; OK=$((OK+1)); log "restored $n"; }
    done
    restore_ro
    log "restored $OK"
    screen "                                        " 4
    screen "  RESTART SCREEN RESTORED ($OK)         " 3
    sync
}
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
