#!/bin/bash
# Name: Fullscreen ON
# Author: repair
# DontUseFBInk

## Makes the stock browser fill the whole panel, by patching the window
## manager's own Lua -- the place the geometry is actually decided.
##
## HOW IT WORKS (read out of the device's own code, not guessed)
##   /etc/xdg/awesome/lab126_application_layer.lua positions every app:
##       topOffset = chrome_get_persistent_top_offset(appWindow.params.PC)
##       appClientGeometry.y      = screen.y + topOffset
##       appClientGeometry.height = screenHeight - (topOffset + bottomOffset)
##   and in lab126_chrome_layer.lua:
##       if PC == "T"  then offset = T.height
##       elseif string.find(PC, "TS") then offset = S.height + S.y
##   S.height + S.y = 115 + 101 = 216 -- exactly the strip above the browser,
##   and exactly the --content-shell-host-window-cord=0,215 in /usr/bin/browser.
##   PC == "N" matches neither branch, so the offset is 0 and the window gets
##   the entire 1236x1648, the same as blankBackground already does.
##
##   The patch sets params.PC = "N" for com.lab126.browser only.
##
## WHERE THE PATCHED FILE COMES FROM
##   Amazon's Lua is proprietary, so this pack does not ship it. It ships
##   theme/wm/kh_patch.lua, which holds only the lines KindleHub adds and the
##   exact places they go. This script runs that, with KOReader's luajit,
##   against the module already on YOUR Kindle, and installs the result only
##   if its md5 is the known-good one. The patched file is built here from
##   your own copy, and a wrong result cannot be installed.
##
## WHY EVERYTHING BEFORE THIS FAILED
##   winmgr chromeState (does not exist), chromebar configureChrome (accepted,
##   no effect), pillow (no-op), appreg default-chrome-style=NH (no effect),
##   binary patching (PC:TS is not a literal, count 0), awesome-client (awesome
##   is on no dbus at all). None of them touched this function.
##
## SAFETY -- this writes to the read-only root, so it is built to be undoable
##   * The behaviour is gated on a FLAG FILE at /mnt/us/kindlehub_fullscreen.
##     /etc is not visible over USB, so a switch living there could not be undone
##     from your Mac. Deleting that flag file over USB turns fullscreen off with
##     no root access required.
##   * The patch body is wrapped in pcall, so a runtime error inside it cannot
##     stop awesome from starting.
##   * The generated module is md5-checked against the known-good result, and
##     SYNTAX-CHECKED with the device's own luajit, before it is installed. If
##     either fails, nothing is written.
##   * The original is backed up and md5-verified, and the current file's md5 is
##     checked against the expected original first -- if your file differs from
##     the one this patch was built against, it refuses rather than guessing.
##   * "Fullscreen OFF" restores the original.

SRCDIR=/mnt/us/kindlehub_theme/wm
PATCHER=$SRCDIR/kh_patch.lua
GEN=$SRCDIR/generated
DSTDIR=/etc/xdg/awesome
SRC=$GEN/lab126_application_layer.lua
DST=$DSTDIR/lab126_application_layer.lua
## Second module: blocks the Control Centre while fullscreen. Screenshots are
## in lab126_button_handling.lua, which is untouched, so they keep working.
SRC2=$GEN/lab126_dialog_layer.lua
DST2=$DSTDIR/lab126_dialog_layer.lua
ORIG2_MD5=ef4eb9bbf1899bab1a362184b1889717
NEW2_MD5=60ec1f749bc285c98450d10c92108cef
BAK=/mnt/us/kindlehub_theme_backup
FLAG=/mnt/us/kindlehub_fullscreen
LOG=/mnt/us/kindlehub_fullscreen.log
ORIG_MD5=27ab0e2ec6519eb0428418493bd783f8
OLD_PATCH_MD5=d4389f9c816de56ebce6cee5ca477a16   # the first, wrongly-placed patch
NEW_MD5=3472a42f133a8bd13a104386cb0a49a3
LUAJIT=/mnt/us/koreader/luajit

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

md5of() { md5sum "$1" 2>/dev/null | awk '{print $1}'; }

## build <mode> <input> <output> <expected-md5>
## Runs the patcher, then refuses the result unless it is byte-for-byte the
## known-good module. Nothing outside $GEN is touched here.
build() {
    rm -f "$3" 2>/dev/null
    R=$("$LUAJIT" "$PATCHER" "$1" "$2" "$3" 2>&1)
    log "$R"
    if [ ! -f "$3" ]; then
        log "ABORT the patcher produced no output"
        return 1
    fi
    G=$(md5of "$3")
    log "generated md5: $G (want $4)"
    if [ "$G" != "$4" ]; then
        log "ABORT generated module is not the known-good result - nothing written"
        rm -f "$3" 2>/dev/null
        return 1
    fi
    return 0
}

## lua_ok <file> -- parse it with the device's own luajit; never install unparsed Lua
lua_ok() {
    R=$("$LUAJIT" -e "local f,e=loadfile('$1') if f then print('LUA_OK') else print('LUA_ERR '..tostring(e)) end" 2>&1)
    log "luajit: $R"
    case "$R" in *LUA_OK*) return 0 ;; *) return 1 ;; esac
}

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo "Fullscreen ON - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - fullscreen browser" 2

    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT - eject the cable first"; screen "Eject the cable first" 4; return 1; }
    [ -f "$PATCHER" ] || { log "ABORT patcher not staged at $PATCHER"; screen "Patch file missing" 4; return 1; }
    [ -f "$DST" ] || { log "ABORT $DST missing"; return 1; }
    if [ ! -x "$LUAJIT" ]; then
        log "ABORT no luajit at $LUAJIT - the patch is built and verified with it"
        log "      install KOReader, then run this again"
        screen "KOReader (luajit) needed - aborted" 4; return 1
    fi

    echo; echo "===== CHECKS ====="
    screen "1/6  checking your file matches     " 4
    CUR=$(md5of "$DST")
    log "device file md5: $CUR"
    log "expected orig:   $ORIG_MD5"
    if [ "$CUR" = "$NEW_MD5" ]; then
        log "already patched - just ensuring the flag file exists"
        touch "$FLAG"; screen "Already installed. Flag set." 4
        screen "Restart to apply." 6; return 0
    fi
    if [ "$CUR" = "$OLD_PATCH_MD5" ]; then
        log "device holds the earlier patch (set PC too late in the flow) - upgrading it"
    elif [ "$CUR" != "$ORIG_MD5" ]; then
        log "ABORT device file is neither the original nor our earlier patch"
        log "      refusing to overwrite something unexpected"
        screen "File differs - refusing (see log)" 4; return 1
    fi

    ## ---- build the patched module from the device's own copy ----
    screen "2/6  building the patch             " 4
    mkdir -p "$GEN" 2>/dev/null
    ## Build from the pristine module. If the device still holds the earlier
    ## patch, that is the backup taken when it was installed, not the live file.
    IN="$DST"
    if [ "$CUR" = "$OLD_PATCH_MD5" ]; then
        if [ "$(md5of "$BAK/lab126_application_layer.lua.orig")" = "$ORIG_MD5" ]; then
            IN="$BAK/lab126_application_layer.lua.orig"; log "building from the pristine backup"
        else
            log "ABORT device holds the earlier patch and there is no pristine backup to build from"
            screen "No pristine backup - refusing" 4; return 1
        fi
    fi
    build application "$IN" "$SRC" "$NEW_MD5" || { screen "Patch did not verify - aborted" 4; return 1; }

    ## ---- syntax check with the device's own lua ----
    screen "3/6  syntax-checking the patch      " 4
    if ! lua_ok "$SRC"; then
        log "ABORT the patched lua does not parse - nothing written"
        screen "Patch does not parse - aborted" 4; return 1
    fi

    ## ---- back up ----
    screen "4/6  backing up the original        " 4
    mkdir -p "$BAK" 2>/dev/null
    if [ ! -f "$BAK/lab126_application_layer.lua.orig" ]; then
        ## Only ever back up a PRISTINE file - never a patched one, or the
        ## "original" would itself contain a patch and Undo would be useless.
        if [ "$CUR" = "$ORIG_MD5" ]; then
            cp "$DST" "$BAK/lab126_application_layer.lua.orig" 2>/dev/null
            B=$(md5of "$BAK/lab126_application_layer.lua.orig")
            [ "$B" = "$ORIG_MD5" ] || { log "ABORT backup did not verify"; return 1; }
            log "OK backup written and md5-verified"
        else
            log "ABORT no pristine backup exists and the device file is already patched"
            return 1
        fi
    else
        B=$(md5of "$BAK/lab126_application_layer.lua.orig")
        log "OK backup already exists (md5 $B, want $ORIG_MD5)"
    fi

    ## ---- install ----
    screen "5/6  installing                     " 4
    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then RW=1
    else log "FAIL could not remount /"; return 1; fi
    cp "$SRC" "$DST" 2>/dev/null && chmod 644 "$DST" 2>/dev/null
    restore_ro
    AFTER=$(md5of "$DST")
    log "installed md5: $AFTER"

    ## ---- second module: Control Centre block ----
    screen "6/6  control centre block           " 4
    CUR2=$(md5of "$DST2")
    if [ "$CUR2" = "$NEW2_MD5" ]; then
        log "OK control centre block already installed"
    elif [ "$CUR2" != "$ORIG2_MD5" ]; then
        log "SKIP dialog layer is not the expected original (md5 $CUR2) - left alone"
    elif ! build dialog "$DST2" "$SRC2" "$NEW2_MD5"; then
        log "SKIP dialog layer patch did not verify - left alone"
    elif ! lua_ok "$SRC2"; then
        log "SKIP dialog patch does not parse - left alone"
    else
        [ -f "$BAK/lab126_dialog_layer.lua.orig" ] || cp "$DST2" "$BAK/lab126_dialog_layer.lua.orig" 2>/dev/null
        if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then
            RW=1
            cp "$SRC2" "$DST2" 2>/dev/null && chmod 644 "$DST2" 2>/dev/null
            restore_ro
            log "OK control centre block installed (md5 $(md5of "$DST2"))"
        else
            log "FAIL could not remount / for the dialog layer"
        fi
    fi

    ## ---- flag ----
    touch "$FLAG"
    log "flag file: $FLAG"

    if [ "$AFTER" = "$NEW_MD5" ]; then
        log "RESULT installed and verified"
        screen "                                        " 4
        screen "  FULLSCREEN INSTALLED                  " 3
        screen "  RESTART, then open the browser        " 5
        screen "                                        " 7
        screen "  to turn off: delete the file          " 7
        screen "  kindlehub_fullscreen from your Mac    " 8
        echo
        echo "  Restart for awesome to reload the patched module."
        echo "  OFF switch, no root needed: delete /mnt/us/kindlehub_fullscreen"
        echo "  over USB, then restart. \"Fullscreen OFF\" does both properly."
    else
        log "RESULT md5 mismatch after write"
        screen "Install did not verify - see log" 4
    fi
    sync
}

: > "$LOG" 2>/dev/null
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
