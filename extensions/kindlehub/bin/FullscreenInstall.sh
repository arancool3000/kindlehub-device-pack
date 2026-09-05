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
##   the entire panel, the same as blankBackground already does. The same
##   function, with the same branches, is in 5.11 and 5.13 firmware too.
##
##   The patch sets params.PC = "N" for com.lab126.browser only.
##
## WHERE THE PATCHED FILE COMES FROM
##   Amazon's Lua is proprietary, so this pack does not ship it. It ships
##   theme/wm/kh_patch.lua, which holds only the lines KindleHub adds and the
##   exact places they go. This script runs that, with KOReader's luajit,
##   against the module already on YOUR Kindle, and installs the result only
##   after it has been checked. The patched file is built here from your own
##   copy, and a wrong result cannot be installed.
##
## ON A KINDLE THIS HAS NOT BEEN TESTED ON
##   The build KindleHub was developed on is a Paperwhite 11 on 5.19.2, and on
##   that build the result is required to be byte-for-byte the known-good
##   module. On any other firmware the md5 cannot be known in advance, so the
##   gate is structural instead, and it is strict:
##     * every anchor must be found exactly once in your module, or the
##       patcher writes nothing;
##     * the result must parse with the device's own luajit;
##     * stripping KindleHub's blocks back out of the result must give back
##       your original, byte for byte (kh_patch.lua verify).
##   Everything KindleHub inserts is wrapped in pcall and does nothing unless
##   the flag file exists, so the worst case on an untested firmware is
##   "nothing changes", not "no UI". Deleting the flag over USB makes the
##   inserted code fully inert; Fullscreen OFF puts the original back.
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
##   * The generated module is checked (md5 on the verified build, structurally
##     everywhere) and SYNTAX-CHECKED with the device's own luajit before it is
##     installed. If either fails, nothing is written.
##   * The original is backed up, the backup is md5-verified against the file
##     it was taken from, and that md5 is recorded beside it so Undo and Health
##     Check can prove the backup is pristine on any firmware.
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
BAK=/mnt/us/kindlehub_theme_backup
FLAG=/mnt/us/kindlehub_fullscreen
LOG=/mnt/us/kindlehub_fullscreen.log
INFO=$BAK/fullscreen.info

## The verified build: Paperwhite 11 (PW5), firmware 5.19.2.
ORIG_MD5=27ab0e2ec6519eb0428418493bd783f8      # application layer, Amazon's
NEW_MD5=3472a42f133a8bd13a104386cb0a49a3       # application layer, patched
OLD_PATCH_MD5=d4389f9c816de56ebce6cee5ca477a16 # the first, wrongly-placed patch
ORIG2_MD5=ef4eb9bbf1899bab1a362184b1889717     # dialog layer, Amazon's
NEW2_MD5=60ec1f749bc285c98450d10c92108cef      # dialog layer, patched

## The comment lines kh_patch.lua inserts. Their presence is what "already
## patched" means on a firmware whose md5s are not known in advance.
MARK_APP='KindleHub fullscreen'
MARK_DLG='KindleHub: suppress Control Centre'

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

## The interpreter the patch is built and checked with. KOReader's luajit is
## the one this was developed with; the others are accepted if a firmware
## happens to ship one.
LUAJIT=""
for l in /mnt/us/koreader/luajit /usr/bin/luajit /usr/bin/lua; do
    [ -x "$l" ] && { LUAJIT="$l"; break; }
done

## build <mode> <input> <output>
## Runs the patcher. Refuses the result unless it parses AND stripping the
## KindleHub blocks back out reproduces the input byte for byte. Nothing
## outside $GEN is touched here.
build() {
    rm -f "$3" 2>/dev/null
    R=$("$LUAJIT" "$PATCHER" "$1" "$2" "$3" 2>&1)
    log "$R"
    if [ ! -f "$3" ]; then
        log "ABORT the patcher produced no output"
        return 1
    fi
    if ! lua_ok "$3"; then
        log "ABORT the patched lua does not parse - nothing written"
        rm -f "$3" 2>/dev/null
        return 1
    fi
    R=$("$LUAJIT" "$PATCHER" verify "$1" "$2" "$3" 2>&1)
    log "$R"
    case "$R" in
        *"byte-for-byte the original"*) ;;
        *) log "ABORT structural check failed - nothing written"; rm -f "$3" 2>/dev/null; return 1 ;;
    esac
    return 0
}

## lua_ok <file> -- parse it with the device's own luajit; never install unparsed Lua
lua_ok() {
    R=$("$LUAJIT" -e "local f,e=loadfile('$1') if f then print('LUA_OK') else print('LUA_ERR '..tostring(e)) end" 2>&1)
    log "luajit: $R"
    case "$R" in *LUA_OK*) return 0 ;; *) return 1 ;; esac
}

## backup <live-file> <backup-file> <current-md5>
## Takes the backup only if there is none. Verifies it against the md5 of the
## file it was copied from and records that md5 beside it. Refuses to keep a
## backup that carries a KindleHub marker: Undo would restore a patched file.
backup() {
    if [ -f "$2" ]; then
        if grep -q 'KindleHub' "$2" 2>/dev/null; then
            log "ABORT existing backup $2 is itself patched - Undo would be useless"
            return 1
        fi
        B=$(md5of "$2")
        ## The live file is pristine here, so a backup that differs from it was
        ## taken from a different firmware. Restoring it later would put an old
        ## build's module on a new build. Refuse, and say what to do.
        if [ "$B" != "$3" ]; then
            log "ABORT existing backup $2 (md5 $B) is not this firmware's file ($3)"
            log "      if the firmware was updated since KindleHub was installed, delete"
            log "      $BAK over USB and run this again"
            return 1
        fi
        log "OK backup already exists and matches (md5 $B)"
        [ -f "$2.md5" ] || echo "$B" > "$2.md5"
        return 0
    fi
    cp "$1" "$2" 2>/dev/null || { log "ABORT could not write backup $2"; return 1; }
    B=$(md5of "$2")
    if [ "$B" != "$3" ]; then
        log "ABORT backup did not verify ($B vs $3)"; rm -f "$2"; return 1
    fi
    echo "$3" > "$2.md5"
    log "OK backup written and md5-verified ($3)"
    return 0
}

main() {
    log() { echo "$(date '+%H:%M:%S') $*"; sync; }
    echo "Fullscreen ON - $(date '+%Y-%m-%d %H:%M:%S')"
    screen "KindleHub - fullscreen browser" 2

    mount 2>/dev/null | grep -q " /mnt/us " || { log "ABORT - eject the cable first"; screen "Eject the cable first" 4; return 1; }
    [ -f "$PATCHER" ] || { log "ABORT patcher not staged at $PATCHER"; screen "Patch file missing" 4; return 1; }
    [ -f "$DST" ] || { log "ABORT $DST missing - this firmware does not use the awesome window manager"; screen "No window manager module - skipped" 4; return 1; }
    if [ -z "$LUAJIT" ]; then
        log "ABORT no luajit - the patch is built and verified with it"
        log "      install KOReader (it ships one at /mnt/us/koreader/luajit), then run this again"
        screen "KOReader (luajit) needed - aborted" 4; return 1
    fi
    log "lua: $LUAJIT"

    FW=$(head -1 /etc/prettyversion.txt 2>/dev/null)
    log "firmware: $FW"

    echo; echo "===== CHECKS ====="
    screen "1/6  checking your file             " 4
    CUR=$(md5of "$DST")
    log "device file md5: $CUR"
    VERIFIED=0
    if [ "$CUR" = "$NEW_MD5" ] || grep -q "$MARK_APP" "$DST" 2>/dev/null; then
        [ "$CUR" = "$NEW_MD5" ] && log "already patched (verified build) - just ensuring the flag file exists" \
                                 || log "already patched (md5 $CUR) - just ensuring the flag file exists"
        touch "$FLAG"; screen "Already installed. Flag set." 4
        screen "Restart to apply." 6; return 0
    fi
    if [ "$CUR" = "$ORIG_MD5" ]; then
        VERIFIED=1
        log "this is the build KindleHub was verified on (Paperwhite 11, 5.19.2)"
    elif [ "$CUR" = "$OLD_PATCH_MD5" ]; then
        VERIFIED=1
        log "device holds the earlier patch (set PC too late in the flow) - upgrading it"
    else
        log "NOTE this is not the build KindleHub was verified on"
        log "     the patch will be built from your module and checked structurally:"
        log "     every anchor found exactly once, result parses, result minus"
        log "     KindleHub's lines is your original byte for byte. If any of that"
        log "     fails, nothing is written."
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
    build application "$IN" "$SRC" || { screen "Patch did not verify - aborted" 4; return 1; }

    ## ---- on the verified build the result must be the known-good module ----
    screen "3/6  verifying the result           " 4
    G=$(md5of "$SRC")
    if [ "$VERIFIED" = "1" ]; then
        log "generated md5: $G (want $NEW_MD5)"
        if [ "$G" != "$NEW_MD5" ]; then
            log "ABORT generated module is not the known-good result - nothing written"
            rm -f "$SRC" 2>/dev/null
            screen "Patch did not verify - aborted" 4; return 1
        fi
    else
        log "generated md5: $G (structurally verified; no known-good md5 for this firmware)"
    fi

    ## ---- back up ----
    screen "4/6  backing up the original        " 4
    mkdir -p "$BAK" 2>/dev/null
    if [ "$CUR" = "$OLD_PATCH_MD5" ]; then
        log "OK pristine backup already exists (md5 $ORIG_MD5)"
        [ -f "$BAK/lab126_application_layer.lua.orig.md5" ] || echo "$ORIG_MD5" > "$BAK/lab126_application_layer.lua.orig.md5"
    else
        backup "$DST" "$BAK/lab126_application_layer.lua.orig" "$CUR" || return 1
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
    ## Best effort: a firmware without a Control Centre has nothing to block,
    ## and the anchor is still there in 5.11 and 5.13, so it installs harmlessly.
    screen "6/6  control centre block           " 4
    DLG=skipped
    CUR2=$(md5of "$DST2")
    if [ ! -f "$DST2" ]; then
        log "SKIP no dialog layer module on this firmware"
    elif [ "$CUR2" = "$NEW2_MD5" ] || grep -q "$MARK_DLG" "$DST2" 2>/dev/null; then
        log "OK control centre block already installed"; DLG=installed
    elif [ "$VERIFIED" = "1" ] && [ "$CUR2" != "$ORIG2_MD5" ]; then
        log "SKIP dialog layer is not the expected original (md5 $CUR2) - left alone"
    elif ! build dialog "$DST2" "$SRC2"; then
        log "SKIP dialog layer patch did not verify - left alone"
    elif [ "$VERIFIED" = "1" ] && [ "$(md5of "$SRC2")" != "$NEW2_MD5" ]; then
        log "SKIP dialog layer result is not the known-good module ($(md5of "$SRC2")) - left alone"
    elif ! backup "$DST2" "$BAK/lab126_dialog_layer.lua.orig" "$CUR2"; then
        log "SKIP dialog layer backup did not verify - left alone"
    else
        if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then
            RW=1
            cp "$SRC2" "$DST2" 2>/dev/null && chmod 644 "$DST2" 2>/dev/null
            restore_ro
            log "OK control centre block installed (md5 $(md5of "$DST2"))"; DLG=installed
        else
            log "FAIL could not remount / for the dialog layer"
        fi
    fi

    ## ---- flag + record ----
    touch "$FLAG"
    log "flag file: $FLAG"
    {
        echo "installed=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "firmware=$FW"
        echo "verified_build=$VERIFIED"
        echo "application_orig_md5=$CUR"
        echo "application_patched_md5=$AFTER"
        echo "dialog_orig_md5=$CUR2"
        echo "dialog=$DLG"
    } > "$INFO" 2>/dev/null
    sync

    if [ "$AFTER" = "$G" ]; then
        if [ "$VERIFIED" = "1" ]; then
            log "RESULT installed and verified"
            screen "                                        " 4
            screen "  FULLSCREEN INSTALLED                  " 3
            screen "  RESTART, then open the browser        " 5
        else
            log "RESULT installed on an untested firmware ($FW) - structurally verified"
            log "       please report whether it works: github.com/arancool3000/kindlehub-device-pack"
            screen "                                        " 4
            screen "  FULLSCREEN INSTALLED (untested fw)    " 3
            screen "  RESTART, then open the browser        " 5
        fi
        screen "                                        " 7
        screen "  to turn off: delete the file          " 7
        screen "  kindlehub_fullscreen from your Mac    " 8
        echo
        echo "  Restart for awesome to reload the patched module."
        echo "  OFF switch, no root needed: delete /mnt/us/kindlehub_fullscreen"
        echo "  over USB, then restart. \"Fullscreen OFF\" does both properly."
    else
        log "RESULT md5 mismatch after write ($AFTER vs $G)"
        screen "Install did not verify - see log" 4
    fi
    sync
}

: > "$LOG" 2>/dev/null
{ trap restore_ro EXIT INT TERM; main; restore_ro; sync; } >> "$LOG" 2>&1 &
exit 0
