#!/bin/bash
# Name: Swipe-Back OFF
# Author: repair
# DontUseFBInk

## Stops a horizontal swipe from navigating back through browser history.
##
## WHAT IT ACTUALLY IS
##   Not a Kindle gesture and not the window manager: it is Chromium's own
##   "overscroll history navigation" -- drag past the edge of a page and it goes
##   back. lab126_ew.lua sounded like a candidate but is Embedded Window
##   Host/Client, nothing to do with gestures.
##
##   That is why it bites hardest in fullscreen: swiping to move between home
##   screen pages overscrolls the page instead, and you land somewhere from
##   your history.
##
##   Two flag spellings are added because Chromium renamed this between
##   versions and the build here is not identifiable from outside:
##       --overscroll-history-navigation=0
##       --disable-features=OverscrollHistoryNavigation
##   An unrecognised flag is ignored by Chromium, so having both is safe.
##
## SAFETY
##   The wrapper is backed up before the first change and the edit is
##   SYNTAX-CHECKED before it replaces the real file -- a broken /usr/bin/browser
##   means no browser at all. It deliberately does NOT touch
##   --content-shell-host-window-cord: that value must match the geometry the
##   window manager allocates, and changing it alone breaks the launch entirely.
##   The guard compares it with what the device had, not with a fixed number,
##   because it differs between panels. "Swipe-Back ON" restores the original.
##   A firmware with no /usr/bin/browser (the older WebKit browser) is skipped.

BR=/usr/bin/browser
BAK=/mnt/us/kindlehub_theme_backup
LOG=/mnt/us/kindlehub_swipe.log
F1="--overscroll-history-navigation=0"
F2="--disable-features=OverscrollHistoryNavigation"

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
    echo "Swipe-back OFF - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - disabling swipe-back" 2

    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT eject the cable first"; screen "Eject the cable first" 4; return 1; }
    ## Older firmware runs the WebKit browser (mesquite) and has no Chromium
    ## launcher at /usr/bin/browser. There is no overscroll navigation to turn
    ## off there, so this is a clean skip.
    if [ ! -f "$BR" ]; then
        log "SKIP no $BR on this firmware - its browser is not Chromium, nothing to change"
        screen "No Chromium launcher - skipped" 4; return 0
    fi
    if ! grep -q -- '--enable-grayscale-mode' "$BR" 2>/dev/null; then
        log "SKIP $BR has no --enable-grayscale-mode line to anchor on - left untouched"
        screen "Launcher differs - skipped" 4; return 0
    fi
    mkdir -p "$BAK" 2>/dev/null

    log "current md5: $(md5sum "$BR" | awk '{print $1}')"
    if grep -q -- "$F1" "$BR" 2>/dev/null; then
        log "already disabled"
        screen "Already off." 4; screen "Restart the browser to be sure." 6; return 0
    fi

    [ -f "$BAK/browser.swipe.orig" ] || cp "$BR" "$BAK/browser.swipe.orig" 2>/dev/null

    ## Build and validate before it goes anywhere near /usr/bin.
    TMP=/tmp/kh_browser_swipe.$$
    sed "s|--enable-grayscale-mode|--enable-grayscale-mode $F1 $F2|" "$BR" > "$TMP" 2>/dev/null
    if ! grep -q -- "$F1" "$TMP" 2>/dev/null; then
        log "FAIL anchor --enable-grayscale-mode not found; wrapper untouched"
        rm -f "$TMP"; screen "Could not patch - see log" 4; return 1
    fi
    if ! bash -n "$TMP" 2>/dev/null; then
        log "FAIL edited wrapper does not parse; original left in place"
        rm -f "$TMP"; screen "Edit did not parse - aborted" 4; return 1
    fi
    ## Guard the one value that must never change. It is 0,215 on a Paperwhite
    ## 11 and something else on a different panel, so the rule is "unchanged
    ## from what this device had", not a fixed number.
    C0=$(grep -o -- '--content-shell-host-window-cord=[0-9,]*' "$BR" 2>/dev/null | head -1)
    C1=$(grep -o -- '--content-shell-host-window-cord=[0-9,]*' "$TMP" 2>/dev/null | head -1)
    if [ "$C0" != "$C1" ]; then
        log "FAIL the window cord changed ('$C0' -> '$C1') - refusing (that breaks the launch)"
        rm -f "$TMP"; return 1
    fi
    log "window cord unchanged: ${C0:-none present}"

    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; rm -f "$TMP"; return 1; fi
    cat "$TMP" > "$BR" && chmod 755 "$BR"
    rm -f "$TMP"
    restore_ro

    if grep -q -- "$F1" "$BR" 2>/dev/null && bash -n "$BR" 2>/dev/null; then
        log "OK flags added; wrapper parses; md5 $(md5sum "$BR" | awk '{print $1}')"
        screen "                                        " 4
        screen "  SWIPE-BACK DISABLED                   " 3
        screen "  close and reopen the browser          " 5
        echo; echo "  Flags only take effect at browser launch, so close and"
        echo "  reopen it (3 taps then reopen, or just restart)."
    else
        log "FAIL verification after write"
        screen "Verification failed - see log" 4
    fi
    sync
}

: > "$LOG" 2>/dev/null
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
