#!/bin/bash
# Name: Custom Restart
# Author: repair
# DontUseFBInk

## Themes the screen you actually see when you pick Restart from the power menu.
##
## WHY THIS WAS MISSED UNTIL NOW
##   The restart screen does NOT come from f_display or from
##   /opt/amazon/low_level_screens. /etc/upstart/shutdown_showimage does:
##       BLANKET_SHUTDOWN_PARAM_REBOOT="reboot"
##       lipc-send-event com.lab126.hal.shutdown showScreen -s "$BLANKET_SHUTDOWN_PARAM"
##   so blanket draws it, from /usr/share/blanket/shutdown/bg_<param>.png.
##
##   KindleHub Setup already replaced bg_shipping, bg_cust_service, bg_critbatt
##   and bg_fontupdate there -- but NOT bg_reboot, which is the only one you see
##   on a normal restart. That is why every restart still looked stock.
##
## WHAT IT DOES
##   Lists what blanket actually has, then replaces the reboot screen (and any
##   other shutdown screen we ship art for) with the KindleHub version. Only
##   files that ALREADY EXIST are overwritten, symlinked screens are left
##   alone, the PNG dimensions are compared first (the art is 1236x1648, a
##   Paperwhite 11 panel; a different panel is skipped with a note), and every
##   original is backed up. "Restart Artwork OFF" puts them all back.
##
##   It does not touch shutdown.conf or /sbin/reboot -- no change to how the
##   device restarts, only to what it shows.

BASE=/mnt/us/kindlehub_theme/system/shutdown
LOW=/mnt/us/kindlehub_theme/system/low_level
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
restore_ro() {
    if [ "$RW" = "1" ]; then
        sync; mntroot ro >/dev/null 2>&1
        mount | grep ' / ' | grep -q '(ro' && RW=0; sync
    fi
}

## png_dims <file> -- prints WIDTHxHEIGHT from the PNG header, or nothing if
## the file is not a PNG. Read straight from the IHDR chunk with dd + hexdump,
## because the device has no image tools. Bytes 0-7 are the signature and
## 16-23 are width and height, big-endian.
png_dims() {
    [ -f "$1" ] || return 1
    sig=$(dd if="$1" bs=1 count=8 2>/dev/null | hexdump -v -e '8/1 "%02X"' 2>/dev/null)
    [ "$sig" = "89504E470D0A1A0A" ] || return 1
    h=$(dd if="$1" bs=1 skip=16 count=8 2>/dev/null | hexdump -v -e '8/1 "%02X"' 2>/dev/null)
    [ ${#h} -eq 16 ] || return 1
    w=$(printf '%d' "0x$(echo "$h" | cut -c1-8)" 2>/dev/null)
    hh=$(printf '%d' "0x$(echo "$h" | cut -c9-16)" 2>/dev/null)
    [ -n "$w" ] && [ -n "$hh" ] || return 1
    echo "${w}x${hh}"
}

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo "Custom restart - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - theming the restart" 2

    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT - eject first"; screen "Eject the cable first" 4; return 1; }

    echo; echo "===== WHAT BLANKET ACTUALLY HAS ====="
    screen "1/4  reading blanket screens        " 4
    ls -la "$DST"/ 2>/dev/null | sed 's/^/  /'
    echo "  --- and the other blanket dirs, for reference ---"
    ls /usr/share/blanket/ 2>/dev/null | sed 's/^/    /'

    ## Make sure we have art for the reboot screen; it is the whole point.
    [ -f "$BASE/bg_reboot.png" ] || cp "$LOW/reboot.png" "$BASE/bg_reboot.png" 2>/dev/null
    [ -f "$BASE/bg_reboot.png" ] || { log "ABORT no reboot artwork staged"; return 1; }

    echo; echo "===== INSTALLING ====="
    screen "2/4  backing up + installing        " 4
    FREE=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
    log "free on /: ${FREE}KB"
    [ "${FREE:-0}" -lt 1500 ] && { log "ABORT under 1.5MB free"; screen "Not enough space on /" 6; return 1; }

    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; return 1; fi

    OK=0; SKIP=0
    for f in "$BASE"/bg_*.png; do
        [ -f "$f" ] || continue
        n=$(basename "$f")
        t="$DST/$n"
        if [ ! -f "$t" ]; then log "skip  $n (blanket has no such screen)"; SKIP=$((SKIP+1)); continue; fi
        ## On some firmware (5.13 on a Paperwhite 4, for one) bg_reboot.png is a
        ## symlink to the shared bg_default.png. Copying through it would change
        ## every screen that shares the default, so it is left alone.
        if [ -L "$t" ]; then log "skip  $n (it is a symlink to $(readlink "$t" 2>/dev/null) on this firmware)"; SKIP=$((SKIP+1)); continue; fi
        ## The artwork is drawn for one panel size. On a different panel it
        ## would be cropped or float in a corner, so the sizes must match.
        want=$(png_dims "$t"); have=$(png_dims "$f")
        if [ -n "$want" ] && [ "$want" != "$have" ]; then
            log "skip  $n (this device's screen art is $want, ours is $have - draw one that size and put it in kindlehub_theme/system/shutdown/)"
            SKIP=$((SKIP+1)); continue
        fi
        [ -f "$BAK/sys_shutdown_$n.orig" ] || cp "$t" "$BAK/sys_shutdown_$n.orig" 2>/dev/null
        if cp "$f" "$t" 2>/dev/null; then
            chmod 644 "$t" 2>/dev/null
            log "OK    $n -> $t ($(wc -c < "$t") bytes)"
            OK=$((OK+1))
        else
            log "FAIL  $t"
        fi
    done
    restore_ro
    log "installed $OK, skipped $SKIP"

    echo; echo "===== VERIFY ====="
    screen "3/4  verifying                      " 4
    ls -la "$DST"/ 2>/dev/null | sed 's/^/  /'
    log "/ is: $(mount | grep ' / ' | grep -o '(r[ow]')"

    echo; echo "===== HOW THE RESTART ITSELF WORKS ====="
    screen "4/4  done                           " 4
    ## Recorded so the next step (making it faster) starts from fact.
    echo "  reboot binary: $(ls -la /sbin/reboot 2>/dev/null)"
    echo "  shutdown.conf runs on: $(grep -m1 'start on' /etc/upstart/shutdown.conf 2>/dev/null)"
    echo "  boot bar config: $(grep -c 'kindlehub' /etc/upstart/splash.conf 2>/dev/null) kindlehub markers"
    echo "  (our splash.conf drives the boot bar from real milestones already)"

    if [ "$OK" -gt 0 ]; then
        screen "                                        " 4
        screen "  RESTART SCREEN THEMED ($OK)           " 3
        screen "  restart to see it                     " 5
        echo; echo "  Pick Restart from the power menu to see it."
        echo "  \"Undo > Restart Artwork OFF\" restores Amazon's originals."
    else
        screen "Nothing installed - see log" 4
    fi
    sync
}

: > "$LOG" 2>/dev/null
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
