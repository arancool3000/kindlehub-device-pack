#!/bin/bash
# Name: Divert Restart To Ours
# Author: repair
# DontUseFBInk

## Makes the OFFICIAL Kindle restart button run OUR restart instead of Amazon's.
##
## HOW
##   The Restart menu item ends up calling /sbin/reboot. We move the real binary
##   aside to /sbin/reboot.kh.real and put a small wrapper in its place. The
##   wrapper runs /mnt/us/kindlehub_reboot.sh, which does the whole shutdown
##   sequence itself -- our artwork, our progress bar, our text -- and finishes
##   with the real reboot.
##
##   Because we never call shutdown_showimage, Amazon's "Your Kindle is
##   restarting." text and its white progress bar are never drawn. That overlay
##   is what was landing on top of the KindleHub wordmark.
##
## WHAT OUR RESTART ACTUALLY DOES (same work, same order as shutdown.conf)
##   killall passwdlg
##   stop wi x wifid wifis lab126 framework sshd usbnetd testd
##   stop cron ; stop filesystems ; sync ; drop_caches ; stop system
##   reboot -f
##
## THREE WAYS OUT, because this is /sbin on the read-only root
##   1. Delete /mnt/us/kindlehub_reboot.sh over USB. The wrapper falls through
##      to Amazon's path when it is missing. No root access needed.
##   2. "Amazon's Restart Back" (under Undo) puts the original binary back.
##   3. Holding the power button ~8s force-restarts in hardware regardless of
##      any of this.
##
## The wrapper deliberately passes halt, poweroff and any -f straight to the
## real binary -- halt/poweroff are symlinks to reboot and behave by argv[0],
## and -f is the final step of both Amazon's sequence and ours, so without that
## passthrough it would recurse.

SRCW=/mnt/us/kindlehub_theme/wm/reboot_wrapper.sh
SRCR=/mnt/us/kindlehub_theme/wm/kindlehub_reboot.sh
DSTW=/sbin/reboot
REAL=/sbin/reboot.kh.real
KH=/mnt/us/kindlehub_reboot.sh
BAK=/mnt/us/kindlehub_theme_backup
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
    echo "Divert restart - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - diverting the restart" 2

    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT eject the cable first"; screen "Eject the cable first" 4; return 1; }
    [ -f "$SRCW" ] || { log "ABORT wrapper not staged"; screen "Wrapper missing" 4; return 1; }
    [ -f "$SRCR" ] || { log "ABORT our restart script not staged"; screen "Restart script missing" 4; return 1; }

    echo; echo "===== BEFORE ====="
    screen "1/5  inspecting /sbin/reboot        " 4
    ls -la /sbin/reboot /sbin/halt /sbin/poweroff "$REAL" 2>/dev/null | sed 's/^/  /'
    file /sbin/reboot 2>/dev/null | sed 's/^/  /'
    log "reboot md5: $(md5sum /sbin/reboot 2>/dev/null | awk '{print $1}')"

    ## Already diverted?
    if [ -f "$REAL" ] && head -1 "$DSTW" 2>/dev/null | grep -q '^#!'; then
        log "already diverted - refreshing our restart script only"
        cp "$SRCR" "$KH" 2>/dev/null; chmod 755 "$KH" 2>/dev/null
        log "refreshed $KH"
        screen "Already diverted. Script refreshed." 4
        screen "Restart to see it." 6
        return 0
    fi

    ## ---- install OUR restart script to /mnt/us first ----
    screen "2/5  installing our restart         " 4
    cp "$SRCR" "$KH" 2>/dev/null && chmod 755 "$KH" 2>/dev/null
    sh -n "$KH" 2>/dev/null || { log "ABORT our restart script does not parse"; screen "Script does not parse" 6; return 1; }
    log "OK $KH installed and parses"

    ## ---- validate the wrapper before it becomes /sbin/reboot ----
    screen "3/5  validating the wrapper         " 4
    TMP=/tmp/kh_reboot_wrapper.$$
    cp "$SRCW" "$TMP" 2>/dev/null
    sh -n "$TMP" 2>/dev/null || { log "ABORT wrapper does not parse - nothing written"; rm -f "$TMP"; screen "Wrapper does not parse" 6; return 1; }
    log "OK wrapper parses"

    ## ---- swap ----
    screen "4/5  swapping /sbin/reboot          " 4
    mkdir -p "$BAK" 2>/dev/null
    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; rm -f "$TMP"; return 1; fi

    ## Keep a copy of the real binary on /mnt/us too, so it can be restored even
    ## if something goes wrong with the one on /.
    [ -f "$BAK/reboot.orig" ] || cp /sbin/reboot "$BAK/reboot.orig" 2>/dev/null
    if [ ! -f "$REAL" ]; then
        cp /sbin/reboot "$REAL" 2>/dev/null && chmod 755 "$REAL" 2>/dev/null
    fi
    if [ ! -x "$REAL" ]; then
        log "ABORT could not create $REAL - leaving /sbin/reboot untouched"
        restore_ro; rm -f "$TMP"; screen "Could not back up reboot" 6; return 1
    fi
    log "real binary preserved at $REAL ($(wc -c < "$REAL") bytes)"

    cat "$TMP" > "$DSTW" && chmod 755 "$DSTW"
    rm -f "$TMP"
    restore_ro

    ## ---- verify ----
    screen "5/5  verifying                      " 4
    echo; echo "===== AFTER ====="
    ls -la /sbin/reboot /sbin/halt /sbin/poweroff "$REAL" 2>/dev/null | sed 's/^/  /'
    head -3 "$DSTW" 2>/dev/null | sed 's/^/  /'
    OKW=0; head -1 "$DSTW" | grep -q '^#!/bin/sh' && OKW=1
    OKR=0; [ -x "$REAL" ] && OKR=1
    OKS=0; [ -x "$KH" ] && OKS=1
    log "wrapper=$OKW realbinary=$OKR ourscript=$OKS"

    if [ "$OKW$OKR$OKS" = "111" ]; then
        log "RESULT diverted"
        screen "                                        " 4
        screen "  RESTART IS NOW OURS                   " 3
        screen "  use the normal Restart menu item      " 5
        screen "                                        " 7
        screen "  OFF: delete kindlehub_reboot.sh       " 7
        screen "  from /mnt/us over USB                 " 8
        echo
        echo "  Pick Restart from the power menu as normal - it now runs ours."
        echo "  To revert without root: delete /mnt/us/kindlehub_reboot.sh."
        echo "  To revert fully: run \"Undo > Amazon's Restart Back\"."
        echo "  Hardware fallback: hold power ~8s."
    else
        log "RESULT incomplete - see the flags above"
        screen "Divert incomplete - see log" 4
    fi
    sync
}

: > "$LOG" 2>/dev/null
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
