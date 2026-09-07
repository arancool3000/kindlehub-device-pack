#!/bin/bash
# Name: KindleHub Install
# Author: KindleHub
# DontUseFBInk

## THE ONE FILE. Installs everything, in the right order, idempotently.
##
## Safe to re-run: every step checks whether it is already done, verifies what
## it writes, and skips rather than forces if it finds something unexpected.
##
## WHAT IT INSTALLS
##   1. Crash-dump cleanup      removes Amazon's fastmetrics dumps
##   2. UI icons                229 SVGs under /app/KPPMainApp/res
##   3. Fullscreen browser      2 window-manager Lua modules, patched in place
##   4. Restart artwork         blanket's bg_reboot and friends
##   5. Browser controls        power-button gestures + cover sleep
##   6. Swipe-back fix          stops overscroll jumping to the previous tab
##
## NOT installed by default, because it replaces /sbin/reboot and is the one
## change that can leave the device mid-shutdown if it goes wrong:
##   KUAL > KindleHub > Parts > Use Our Restart
##
## EVERYTHING IS REVERSIBLE
##   Every file it overwrites on the read-only root is backed up first to
##   /mnt/us/kindlehub_theme_backup and restored by the matching Undo entry in
##   KUAL. The fullscreen behaviour is additionally gated on a flag file on
##   /mnt/us, so it can be switched off from a computer over USB with no device
##   access at all -- /etc is not visible over USB, so a switch living only
##   there could not be undone if it misbehaved.
##
## REQUIREMENTS
##   A jailbroken Kindle with KUAL, and KOReader for its luajit. It was
##   developed and verified on a Paperwhite 11 (PW5) on firmware 5.19.2. On
##   any other Kindle it still runs: every part checks the exact file it is
##   about to change and skips, rather than guesses, if that file is not what
##   it expects. The firmware is logged, not gated on.

BASE=/mnt/us/kindlehub_theme
BIN=/mnt/us/extensions/kindlehub/bin
BAK=/mnt/us/kindlehub_theme_backup
LOG=/mnt/us/kindlehub_install.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
log() { echo "$(date '+%H:%M:%S') $*"; sync; }
run() {  # run <label> <script>
    if [ -x "$2" ] || [ -f "$2" ]; then
        log "--- $1 ---"
        sh "$2" >/dev/null 2>&1
        return 0
    fi
    log "SKIP $1 (missing $2)"
    return 1
}

OK=0; FAIL=0
step() { if "$@"; then OK=$((OK+1)); else FAIL=$((FAIL+1)); fi; }

## Each part script backgrounds its real work and returns at once, and most of
## them remount / read-write. Started back to back on fixed sleeps they could
## overlap, and the first to finish would remount / read-only underneath the
## others -- which is exactly how / was once left read-write by a half-finished
## script. So after each part, wait for its process to be gone AND for / to be
## read-only again before starting the next. The uninstaller does the same.
root_is_ro() { mount 2>/dev/null | grep ' / ' | grep -q '(ro'; }
settle() {  # settle <ScriptName.sh> <max-seconds>
    first=$(printf '%.1s' "$1"); pat="[$first]${1#?}"
    i=0
    while [ "$i" -lt "${2:-120}" ]; do
        if ! ps 2>/dev/null | grep -q "$pat" && root_is_ro; then return 0; fi
        sleep 1; i=$((i+1))
    done
    log "WARN $1 still running or / still read-write after ${2:-120}s - continuing"
    return 1
}

main() {
    echo "KindleHub Install - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "                                        " 2
    screen "  KINDLEHUB INSTALL                     " 2
    screen "  this takes about a minute            " 4

    ## ---- preflight ----
    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT eject the USB cable first"; screen "Eject the cable first" 6; return 1; }
    FW=$(head -1 /etc/prettyversion.txt 2>/dev/null)
    MODEL=$(tr -d '\0' < /proc/device-tree/model 2>/dev/null)
    [ -n "$MODEL" ] || MODEL=$(grep -m1 '^Hardware' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//')
    log "firmware: $FW"
    log "device  : ${MODEL:-unknown} (serial prefix $(cut -c1-4 /proc/usid 2>/dev/null))"
    log "panel   : $(eips -i 2>/dev/null | grep -m1 -i -E 'xres|width' | tr -s ' ')"
    case "$FW" in
        *5.19.2*) log "firmware: the build KindleHub was developed and verified on" ;;
        *) log "firmware: NOT the build KindleHub was verified on (Paperwhite 11, 5.19.2)"
           log "          each part checks the file it is about to change and skips if it is"
           log "          not what it expects; the fullscreen patch is built from your own"
           log "          window-manager module and checked structurally before it is written."
           log "          Please report how it went: github.com/arancool3000/kindlehub-device-pack" ;;
    esac
    [ -d "$BASE" ] || { log "ABORT $BASE missing - copy the theme folder to your Kindle"; screen "Theme files missing" 6; return 1; }
    [ -x /mnt/us/koreader/luajit ] || log "NOTE KOReader's luajit not found - the fullscreen step will refuse without it"

    ## The 229 icons ship as one archive so the release folder stays small. If
    ## you copied the folder by hand rather than with copy-to-kindle.sh, they
    ## are still packed; unpack them here. Already-unpacked wins, so a user who
    ## edited an icon does not get it silently overwritten by the archive.
    if [ ! -d "$BASE/icons" ] && [ -f "$BASE/icons.tar.gz" ]; then
        log "unpacking icons.tar.gz"
        mkdir -p "$BASE/icons" 2>/dev/null
        if tar -xzf "$BASE/icons.tar.gz" -C "$BASE/icons" 2>/dev/null; then
            log "unpacked $(find "$BASE/icons" -name '*.svg' 2>/dev/null | wc -l) icons"
        else
            log "WARN could not unpack icons.tar.gz - the icon step will skip"
        fi
    fi

    mkdir -p "$BAK" 2>/dev/null
    log "free on /      : $(df / 2>/dev/null | tail -1 | awk '{print $4}')KB"
    log "free on /mnt/us: $(df /mnt/us 2>/dev/null | tail -1 | awk '{print $4}')KB"

    ## ---- 1. crash dumps ----
    screen "1/6  clearing crash dumps            " 6
    log "--- crash dumps ---"
    N=$(ls /mnt/us/documents/fastmetrics_*crash* 2>/dev/null | wc -l)
    rm -f /mnt/us/documents/fastmetrics_*crash*.txt 2>/dev/null
    rm -f /mnt/us/documents/fastmetrics_*crash*.tgz 2>/dev/null
    rm -rf /mnt/us/documents/fastmetrics_*crash*.sdr 2>/dev/null
    rm -f /mnt/us/Indexer_Dump_*.txt 2>/dev/null
    log "removed $N crash artifact(s)"
    OK=$((OK+1))

    ## ---- 2. icons ----
    screen "2/6  installing icons                " 6
    step run "icons" "$BIN/IconsInstall.sh"
    settle IconsInstall.sh 180

    ## ---- 3. fullscreen ----
    screen "3/6  fullscreen browser              " 6
    step run "fullscreen (window manager)" "$BIN/FullscreenInstall.sh"
    settle FullscreenInstall.sh 120

    ## ---- 4. restart artwork ----
    screen "4/6  restart artwork                 " 6
    step run "restart artwork" "$BIN/CustomRestart.sh"
    settle CustomRestart.sh 60

    ## ---- 5. browser controls ----
    screen "5/6  browser controls                " 6
    step run "browser controls" "$BIN/BrowserDaemon.sh"
    sleep 3

    ## ---- 6. swipe-back fix ----
    ## Chromium treats an overscroll as "go back", which in fullscreen lands you
    ## on the previous tab instead of the previous page. This adds two flags to
    ## the browser launcher; it md5-checks the file and refuses if it differs.
    screen "6/6  swipe-back fix                 " 6
    step run "swipe-back fix" "$BIN/SwipeBackOff.sh"
    settle SwipeBackOff.sh 60

    ## ---- report ----
    echo; echo "===== RESULT ====="
    log "$OK step(s) ran, $FAIL skipped"
    echo
    echo "  Installed:"
    echo "    icons        $(find "$BASE/icons" -name '*.svg' 2>/dev/null | wc -l) SVGs"
    echo "    fullscreen   $(grep -q 'KindleHub fullscreen' /etc/xdg/awesome/lab126_application_layer.lua 2>/dev/null && echo patched || echo 'not patched') ($(md5sum /etc/xdg/awesome/lab126_application_layer.lua 2>/dev/null | awk '{print $1}'))"
    echo "    controls     $([ -f /mnt/us/kindlehub_browserd_on ] && echo running || echo 'not running')"
    echo "    swipe-back   $(grep -c 'overscroll-history-navigation' /usr/bin/browser 2>/dev/null) flag(s) in /usr/bin/browser"
    echo "    backups      $(ls "$BAK" 2>/dev/null | wc -l) files in $BAK"
    echo
    echo "  RESTART now, then use KUAL > KindleHub > KindleHub Browser."
    echo "    1 tap of the power button   sleep"
    echo "    2 taps                      show/hide the browser bar"
    echo "    3 taps                      leave fullscreen"
    echo "    close the cover             sleep"
    echo
    echo "  To undo anything: KUAL > KindleHub > Undo."
    echo "  Emergency off for fullscreen, no device access needed:"
    echo "    delete /mnt/us/kindlehub_fullscreen over USB."

    screen "                                        " 4
    screen "                                        " 6
    screen "  INSTALL COMPLETE                      " 2
    screen "  $OK steps ran, $FAIL skipped           " 4
    screen "                                        " 6
    screen "  RESTART NOW                           " 6
    screen "  then KUAL > KindleHub > Browser       " 8
    sync
}

: > "$LOG" 2>/dev/null
{ main; sync; } >> "$LOG" 2>&1 &
exit 0
