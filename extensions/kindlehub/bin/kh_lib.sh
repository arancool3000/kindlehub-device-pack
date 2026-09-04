#!/bin/sh
# KindleHub shared helpers.
#
# Every function here exists because something went wrong in a specific way and
# this is the fix. The comments name the failure so it is not reintroduced.
#
#   . /mnt/us/extensions/kindlehub/bin/kh_lib.sh

# ---------------------------------------------------------------- screen / log
kh_find_fbink() {
    for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
        [ -x "$d/fbink" ] && { echo "$d/fbink"; return 0; }
    done
    return 1
}
KH_FBINK=$(kh_find_fbink 2>/dev/null)
kh_screen() {
    if [ -n "$KH_FBINK" ]; then "$KH_FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
# FAT buffers writes: without the sync a log is empty if the device is pulled or
# the script is killed. Every log line syncs, deliberately.
kh_log() { echo "$(date '+%H:%M:%S') $*"; sync; }

# ------------------------------------------------------------------ preflight
# Scripts that write to / must not run while the host holds the USB storage.
kh_require_ejected() {
    if ! mount 2>/dev/null | grep -q " /mnt/us "; then
        kh_log "ABORT /mnt/us is not mounted - eject the USB cable first"
        kh_screen "Eject the cable first" 4
        return 1
    fi
    return 0
}
# The Lua patches are md5-matched to one build; refuse elsewhere rather than
# writing a patch that does not belong.
kh_require_fw() {
    fw=$(head -1 /etc/prettyversion.txt 2>/dev/null)
    case "$fw" in
        *"${1:-5.19.2}"*) return 0 ;;
        *) kh_log "ABORT firmware '$fw' is not ${1:-5.19.2}"; kh_screen "Unsupported firmware" 4; return 1 ;;
    esac
}
# / is ~94% full; refuse rather than half-write and corrupt something.
kh_require_space() {
    free=$(df / 2>/dev/null | tail -1 | awk '{print $4}')
    if [ "${free:-0}" -lt "${1:-1500}" ]; then
        kh_log "ABORT only ${free}KB free on / (need ${1:-1500}KB)"
        kh_screen "Not enough space on /" 4
        return 1
    fi
    kh_log "free on /: ${free}KB"
    return 0
}

# --------------------------------------------------------------- root fs guard
# A probe once found / left mounted rw by a script that failed before restoring
# it. On a nearly-full ext3 that is how a power loss corrupts something. Always:
#   kh_rw || exit 1 ; trap kh_ro EXIT INT TERM
KH_RW=0
kh_rw() {
    if mntroot rw >/dev/null 2>&1 && mount | grep ' / ' | grep -q '(rw'; then
        KH_RW=1; return 0
    fi
    kh_log "FAIL could not remount / read-write"
    return 1
}
kh_ro() {
    [ "$KH_RW" = "1" ] || return 0
    sync; mntroot ro >/dev/null 2>&1
    mount | grep ' / ' | grep -q '(ro' && KH_RW=0
    sync
}

# ------------------------------------------------------------------- installs
# Only ever overwrite a file whose current md5 is one we expect, and only after
# backing it up. Guessing here is how you overwrite something unrecognised.
#   kh_install <src> <dst> <backup-dir> <expected-orig-md5> [already-md5]
kh_install() {
    src="$1"; dst="$2"; bak="$3"; want="$4"; done_md5="$5"
    [ -f "$src" ] || { kh_log "SKIP $dst (no source $src)"; return 1; }
    [ -f "$dst" ] || { kh_log "SKIP $dst (not present on this device)"; return 1; }
    cur=$(md5sum "$dst" 2>/dev/null | awk '{print $1}')
    if [ -n "$done_md5" ] && [ "$cur" = "$done_md5" ]; then
        kh_log "OK   $dst already installed"; return 0
    fi
    if [ -n "$want" ] && [ "$cur" != "$want" ]; then
        kh_log "SKIP $dst - md5 $cur is not the expected original $want"
        return 1
    fi
    mkdir -p "$bak" 2>/dev/null
    b="$bak/$(basename "$dst").orig"
    if [ ! -f "$b" ]; then
        cp "$dst" "$b" 2>/dev/null || { kh_log "FAIL backing up $dst"; return 1; }
        # Never record a patched file as the "original" -- Undo would be useless.
        [ -n "$want" ] && [ "$(md5sum "$b" | awk '{print $1}')" != "$want" ] && {
            kh_log "FAIL backup of $dst did not verify"; rm -f "$b"; return 1; }
    fi
    cp "$src" "$dst" 2>/dev/null && chmod 644 "$dst" 2>/dev/null || { kh_log "FAIL writing $dst"; return 1; }
    kh_log "OK   $dst written ($(md5sum "$dst" | awk '{print $1}'))"
    return 0
}

# Validate Lua with the device's own interpreter BEFORE it reaches the window
# manager. A syntax error in /etc/xdg/awesome leaves no UI to fix it from.
kh_lua_ok() {
    for l in /mnt/us/koreader/luajit /usr/bin/lua /usr/bin/luajit; do
        [ -x "$l" ] || continue
        r=$("$l" -e "local f,e=loadfile('$1') if f then print('OK') else print('ERR '..tostring(e)) end" 2>&1)
        case "$r" in *OK*) return 0 ;; *) kh_log "lua check failed: $r"; return 1 ;; esac
    done
    kh_log "no lua interpreter to verify with - refusing"
    return 1
}

# ----------------------------------------------------------------- daemon flag
# A bare flag file is NOT proof a daemon is alive. One left behind by a killed
# daemon made the launcher skip startup, so the power button slept the device
# and no gestures worked. Store the PID and check it.
kh_daemon_alive() {
    [ -s "$1" ] || return 1
    p=$(cat "$1" 2>/dev/null)
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}
kh_daemon_claim() { echo $$ > "$1"; }

# ------------------------------------------------------------------ app state
# "ps | grep kindle_browser" NEVER matches: /usr/bin/browser execs it through
# chroot. Ask the window manager instead.
kh_browser_up() {
    lipc-get-prop com.lab126.winmgr getActiveAppTitle 2>/dev/null | grep -q 'com.lab126.browser'
}
# Poll for a condition instead of sleeping a fixed guess.
#   kh_wait_for <seconds> <command...>
kh_wait_for() {
    n="$1"; shift; i=0
    while [ "$i" -lt "$n" ]; do
        "$@" && return 0
        i=$((i+1)); sleep 1
    done
    return 1
}

# --------------------------------------------------------------------- hygiene
# Amazon dumps a ~3.5MB "crash" report whenever the browser is torn down to
# enter USB drive mode. It is an artefact of the teardown, not a fault.
kh_sweep_dumps() {
    n=$(ls /mnt/us/documents/fastmetrics_*crash* 2>/dev/null | wc -l)
    [ "${n:-0}" -eq 0 ] && return 0
    rm -f /mnt/us/documents/fastmetrics_*crash*.txt 2>/dev/null
    rm -f /mnt/us/documents/fastmetrics_*crash*.tgz 2>/dev/null
    rm -rf /mnt/us/documents/fastmetrics_*crash*.sdr 2>/dev/null
    rm -f /mnt/us/Indexer_Dump_*.txt 2>/dev/null
    kh_log "swept $n crash artifact(s)"
}

# NEVER stop these from a scriptlet: they are the framework running you, so
# stopping them kills the script mid-sequence. This hung a device at
# "12% stopping services" until a hardware power-hold.
KH_NEVER_STOP="lab126 framework x"
kh_safe_to_stop() {
    for bad in $KH_NEVER_STOP; do [ "$1" = "$bad" ] && return 1; done
    return 0
}
