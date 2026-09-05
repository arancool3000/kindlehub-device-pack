#!/bin/bash
# Name: Fullscreen OFF
# Author: repair
# DontUseFBInk
## Restores the original window-manager modules and clears the flag file.
## Either one alone is enough to stop fullscreen; this does both.
##
## The backup's md5 was recorded beside it when it was taken
## (<name>.orig.md5), so the restore is verified against the file this device
## actually had, whatever firmware it is on. The Paperwhite 11 / 5.19.2 value
## is the fallback for backups taken by 1.0.x, which did not record one.

DST=/etc/xdg/awesome/lab126_application_layer.lua
BAK=/mnt/us/kindlehub_theme_backup/lab126_application_layer.lua.orig
FLAG=/mnt/us/kindlehub_fullscreen
LOG=/mnt/us/kindlehub_fullscreen.log
INFO=/mnt/us/kindlehub_theme_backup/fullscreen.info
ORIG_MD5=27ab0e2ec6519eb0428418493bd783f8

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
md5of() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }
## want_md5 <backup> <fallback> -- the recorded md5 if there is one
want_md5() { if [ -s "$1.md5" ]; then head -1 "$1.md5"; else echo "$2"; fi; }

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo; echo "Fullscreen OFF - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - fullscreen off" 2

    rm -f "$FLAG" 2>/dev/null && log "flag file removed (this alone disables it)"

    ## restore the dialog layer too, so Control Centre comes back
    B2=/mnt/us/kindlehub_theme_backup/lab126_dialog_layer.lua.orig
    D2=/etc/xdg/awesome/lab126_dialog_layer.lua
    if [ -f "$B2" ]; then
        if grep -q 'KindleHub' "$B2" 2>/dev/null; then
            log "WARN dialog backup is itself patched - not restoring it"
        elif mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then
            RW=1; cp "$B2" "$D2" 2>/dev/null && chmod 644 "$D2" 2>/dev/null; restore_ro
            W=$(want_md5 "$B2" ef4eb9bbf1899bab1a362184b1889717); A=$(md5of "$D2")
            [ "$A" = "$W" ] && log "OK dialog layer restored and verified (control centre back)" \
                            || log "WARN dialog layer restored but md5 $A is not the recorded $W"
        fi
    fi

    if [ -f "$BAK" ]; then
        if grep -q 'KindleHub' "$BAK" 2>/dev/null; then
            log "ABORT backup is itself patched - refusing to restore it; flag removed so behaviour is off anyway"
            return 0
        fi
        if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
        else log "FAIL could not remount /; flag removed so behaviour is off anyway"; return 0; fi
        cp "$BAK" "$DST" 2>/dev/null && chmod 644 "$DST" 2>/dev/null
        restore_ro
        W=$(want_md5 "$BAK" "$ORIG_MD5"); A=$(md5of "$DST")
        log "restored md5: $A (want $W)"
        [ "$A" = "$W" ] && log "OK original restored and verified" || log "WARN md5 mismatch"
        rm -f "$INFO" 2>/dev/null
    else
        log "no backup found; flag removed, which is enough to disable it"
    fi
    screen "                                        " 4
    screen "  FULLSCREEN OFF                        " 3
    screen "  restart to apply                      " 5
    sync
}
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
