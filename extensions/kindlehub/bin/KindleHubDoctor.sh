#!/bin/bash
# Name: KindleHub Doctor
# Author: repair
# DontUseFBInk

## READ-ONLY. Checks every part of the install and reports what is wrong.
##
## Each check exists because that exact thing broke at some point:
##   * / left mounted read-write by a script that failed before restoring it
##   * a stale daemon flag from a killed daemon, which silently disabled the
##     power-button gestures and let the button sleep the device again
##   * a restart script that stopped the framework running it, hanging the
##     device at "12% stopping services"
##   * a backup that had itself been taken from an already-patched file, making
##     Undo useless
##   * scripts in the KUAL menu whose target file did not exist
##   * crash dumps accumulating in the library
##
## Nothing is changed. It only looks and reports.

BIN=/mnt/us/extensions/kindlehub/bin
BAK=/mnt/us/kindlehub_theme_backup
BASE=/mnt/us/kindlehub_theme
OUT=/mnt/us/kindlehub_doctor.txt
ORIG_APP_MD5=27ab0e2ec6519eb0428418493bd783f8
ORIG_DLG_MD5=ef4eb9bbf1899bab1a362184b1889717

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
PROB=0
ok()   { echo "  OK    $*"; }
warn() { echo "  WARN  $*"; PROB=$((PROB+1)); }
bad()  { echo "  PROB  $*"; PROB=$((PROB+1)); }

main() {
    echo "KindleHub Doctor - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - checking everything" 2

    echo; echo "=== 1. FILESYSTEM ==="
    screen "1/8  filesystem                     " 4
    M=$(mount | grep ' / ')
    case "$M" in
        *"(ro"*) ok "/ is read-only" ;;
        *)       bad "/ is READ-WRITE - a script did not restore it. Risk of corruption on power loss." ;;
    esac
    FREE=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
    [ "${FREE:-0}" -lt 1500 ] && warn "only ${FREE}KB free on / - installs will refuse" || ok "${FREE}KB free on /"
    ok "$(df /mnt/us 2>/dev/null | tail -1 | awk '{print $4}')KB free on /mnt/us"

    echo; echo "=== 2. FIRMWARE ==="
    screen "2/8  firmware                       " 4
    FW=$(head -1 /etc/prettyversion.txt 2>/dev/null)
    case "$FW" in
        *5.19.2*) ok "firmware $FW (the build KindleHub was verified on)" ;;
        *) ok "firmware $FW - not the verified build (5.19.2 on a Paperwhite 11); each part checks its own file" ;;
    esac
    [ -x /mnt/us/koreader/luajit ] && ok "KOReader's luajit present" || warn "no /mnt/us/koreader/luajit - Fullscreen ON needs it to build and check the patch"
    [ -f /etc/xdg/awesome/lab126_application_layer.lua ] && ok "awesome window manager present" || bad "no /etc/xdg/awesome/lab126_application_layer.lua - fullscreen cannot work on this firmware"

    echo; echo "=== 3. FULLSCREEN ==="
    screen "3/8  fullscreen                     " 4
    A=/etc/xdg/awesome/lab126_application_layer.lua
    D=/etc/xdg/awesome/lab126_dialog_layer.lua
    AM=$(md5sum "$A" 2>/dev/null | awk '{print $1}')
    DM=$(md5sum "$D" 2>/dev/null | awk '{print $1}')
    grep -q 'KindleHub fullscreen' "$A" 2>/dev/null && ok "application layer patched ($AM)" || warn "application layer NOT patched - fullscreen will not work"
    grep -q 'KindleHub' "$D" 2>/dev/null && ok "dialog layer patched (control centre block)" || warn "dialog layer not patched - control centre still opens in fullscreen"
    [ -f "$BAK/fullscreen.info" ] && echo "  $(grep -E '^(firmware|verified_build)=' "$BAK/fullscreen.info" | tr '\n' ' ')"
    ## A backup is pristine if it carries no KindleHub line and matches the
    ## md5 recorded when it was taken (1.1.0+). Backups from 1.0.x recorded
    ## nothing, so the Paperwhite 11 / 5.19.2 values are the fallback.
    check_backup() {  # check_backup <label> <backup> <fallback-md5>
        [ -f "$2" ] || { warn "no $1 backup - Undo unavailable"; return; }
        B=$(md5sum "$2" | awk '{print $1}')
        if grep -q 'KindleHub' "$2" 2>/dev/null; then
            bad "$1 backup is NOT pristine - it contains KindleHub lines, Undo would restore a patched file"
        elif [ -s "$2.md5" ]; then
            [ "$B" = "$(head -1 "$2.md5")" ] && ok "$1 backup is pristine (md5 $B, as recorded)" \
                                              || bad "$1 backup md5 $B is not the recorded $(head -1 "$2.md5")"
        elif [ "$B" = "$3" ]; then
            ok "$1 backup is pristine ($B)"
        else
            warn "$1 backup has no recorded md5 and is not the 5.19.2 original ($B) - taken on another firmware?"
        fi
    }
    check_backup "application-layer" "$BAK/lab126_application_layer.lua.orig" "$ORIG_APP_MD5"
    check_backup "dialog-layer" "$BAK/lab126_dialog_layer.lua.orig" "$ORIG_DLG_MD5"
    [ -f /mnt/us/kindlehub_fullscreen ] && ok "fullscreen flag set (browser will be fullscreen)" \
                                        || ok "fullscreen flag clear (browser shows its bar)"

    echo; echo "=== 4. BROWSER CONTROLS ==="
    screen "4/8  browser controls               " 4
    ## The flag is deliberately EMPTY: a pid recorded from inside "{ ...; } &"
    ## is the parent shell's, which exits at once, so the daemon and the
    ## launcher both test for a live PROCESS instead. Do the same here.
    F=/mnt/us/kindlehub_browserd_on
    DP=$(ps 2>/dev/null | grep '[B]rowserDaemon' | awk '{print $1}' | head -1)
    if [ -n "$DP" ]; then
        [ -f "$F" ] && ok "daemon running as pid $DP" \
                    || warn "daemon running (pid $DP) but its flag is gone - it will stop itself within 30s"
    elif [ -f "$F" ]; then
        bad "STALE flag with no daemon process - gestures are off and the power button will sleep the device. Run Browser Controls ON."
    else
        ok "controls not running (power button sleeps normally)"
    fi
    echo "  preventScreenSaver = $(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)"

    echo; echo "=== 5. RESTART ==="
    screen "5/8  restart                        " 4
    K=/mnt/us/kindlehub_reboot.sh
    if [ -f "$K" ]; then
        sh -n "$K" 2>/dev/null && ok "our restart script parses" || bad "our restart script does NOT parse - restarts may hang"
        if grep -qE '^[^#]*stop .*(lab126|framework)' "$K"; then
            bad "restart script stops the framework - IT WILL HANG. Delete $K now."
        else ok "restart script does not stop the framework"; fi
        grep -q 'watchdog armed' "$K" && ok "reboot watchdog present" || bad "no reboot watchdog - a failure mid-way would hang the device"
    else
        ok "our restart not enabled (Amazon's restart in use)"
    fi
    if [ -f /sbin/reboot.kh.real ]; then
        ok "original reboot binary preserved at /sbin/reboot.kh.real"
        head -1 /sbin/reboot 2>/dev/null | grep -q '^#!' && ok "/sbin/reboot is our wrapper" || warn "/sbin/reboot is not our wrapper"
    else
        ok "/sbin/reboot is untouched"
    fi

    echo; echo "=== 6. KUAL MENU ==="
    screen "6/8  kual menu                      " 4
    MJ=/mnt/us/extensions/kindlehub/menu.json
    [ -f /mnt/us/extensions/kindlehub/config.xml ] && ok "config.xml present" || bad "config.xml MISSING - KUAL will not load the extension at all"
    if [ -f "$MJ" ]; then
        MISS=0
        for a in $(grep -o '"\./bin/[A-Za-z0-9_]*\.sh"' "$MJ" 2>/dev/null | tr -d '"'); do
            [ -f "/mnt/us/extensions/kindlehub/$a" ] || { bad "menu points at missing $a"; MISS=$((MISS+1)); }
        done
        [ "$MISS" = "0" ] && ok "every menu entry resolves to a file"
    else bad "menu.json missing"; fi
    NP=0
    for f in "$BIN"/*.sh; do sh -n "$f" 2>/dev/null || { bad "does not parse: $(basename "$f")"; NP=$((NP+1)); }; done
    [ "$NP" = "0" ] && ok "all $(ls "$BIN"/*.sh 2>/dev/null | wc -l) scripts parse"

    echo; echo "=== 7. ICONS ==="
    screen "7/8  icons                          " 4
    N=$(find "$BASE/icons" -name '*.svg' 2>/dev/null | wc -l)
    ok "$N replacement icons staged"
    if [ ! -d /app/KPPMainApp/res ]; then
        ok "this firmware has no /app/KPPMainApp/res - its UI does not use SVG icons, so the icon part does not apply"
    else
        I=$(grep -l 'KindleHub' /app/KPPMainApp/res/KPPUIChrome/*.svg 2>/dev/null | wc -l)
        [ "${I:-0}" -gt 0 ] && ok "$I KindleHub icons installed on device" || warn "no KindleHub icons installed yet - run Install Icons"
    fi

    echo; echo "=== 8. HYGIENE ==="
    screen "8/8  hygiene                        " 4
    C=$(ls /mnt/us/documents/fastmetrics_*crash* 2>/dev/null | wc -l)
    [ "${C:-0}" -gt 0 ] && warn "$C crash artifact(s) in documents - the daemon sweeps these when running" || ok "no crash artifacts"
    S=$(ls /mnt/us/documents/*.sh 2>/dev/null | wc -l)
    D=$(ls -d /mnt/us/documents/*.sh.sdr 2>/dev/null | wc -l)
    [ "$S" -gt "$D" ] && warn "$S scriptlets but only $D .sdr sidecars - some will vanish from the library" || ok "every scriptlet has an .sdr sidecar"

    echo; echo "=== RESULT ==="
    if [ "$PROB" = "0" ]; then
        echo "  Everything checks out."
        screen "                                    " 4
        screen "  ALL CHECKS PASSED" 4
    else
        echo "  $PROB problem(s) or warning(s) above."
        screen "                                    " 4
        screen "  $PROB ISSUE(S) - see the report" 4
    fi
    screen "Plug in: kindlehub_doctor.txt" 6
    sync
}

: > "$OUT" 2>/dev/null
{ main; sync; } >> "$OUT" 2>&1 &
exit 0
