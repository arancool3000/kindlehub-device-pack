#!/bin/bash
# Name: Undo Divert
# Author: repair
# DontUseFBInk
## Puts Amazon's /sbin/reboot binary back and removes our restart script.
## Either action alone is enough to stop the divert; this does both.

REAL=/sbin/reboot.kh.real
DSTW=/sbin/reboot
KH=/mnt/us/kindlehub_reboot.sh
BAK=/mnt/us/kindlehub_theme_backup/reboot.orig
LOG=/mnt/us/kindlehub_divert.log

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
    echo; echo "Undo divert - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - restoring Amazon restart" 2

    ## Removing our script alone already reverts the behaviour.
    rm -f "$KH" 2>/dev/null && log "removed $KH (this alone reverts it)"

    SRC=""
    [ -x "$REAL" ] && SRC="$REAL"
    [ -z "$SRC" ] && [ -f "$BAK" ] && SRC="$BAK"
    if [ -z "$SRC" ]; then
        log "no saved binary found; our script is gone so restarts are normal again"
        screen "Script removed - restarts normal" 4; return 0
    fi

    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /; script removed so behaviour is reverted anyway"; return 0; fi
    cp "$SRC" "$DSTW" 2>/dev/null && chmod 755 "$DSTW" 2>/dev/null
    rm -f "$REAL" 2>/dev/null
    restore_ro

    log "restored /sbin/reboot from $SRC"
    file /sbin/reboot 2>/dev/null | sed 's/^/  /'
    ls -la /sbin/reboot 2>/dev/null | sed 's/^/  /'
    screen "                                        " 4
    screen "  AMAZON RESTART RESTORED              " 3
    sync
}
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
