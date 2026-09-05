#!/bin/sh
# KindleHub restart -- our own shutdown sequence.
#
# WHAT WENT WRONG IN THE FIRST VERSION, and why this one is built differently
#   It ran, verbatim from Amazon's shutdown.conf:
#       stop wi x wifid wifis lab126 framework sshd usbnetd testd
#   "lab126" IS THE FRAMEWORK RUNNING THIS SCRIPT. Stopping it killed our own
#   parent, so the script died at that exact line and never reached reboot -f.
#   The device sat at "12% stopping services" until a hardware power-hold.
#   Amazon gets away with that line because upstart runs their script, not the
#   framework.
#
# TWO CHANGES, both about surviving our own actions
#   1. A DETACHED WATCHDOG IS ARMED FIRST. Before anything is stopped, a
#      setsid'd child is started that will reboot unconditionally after 30s.
#      setsid puts it in its own session so it is not killed with our process
#      group. If we die mid-sequence, the device still restarts. The guarantee
#      comes before the risk, not after it.
#   2. WE NO LONGER STOP THE FRAMEWORK. reboot -f tears everything down anyway;
#      stopping lab126/x/framework by hand bought nothing and cost us our own
#      life. Only services that are NOT our parent are stopped, and the data
#      safety that actually matters -- sync and dropping caches -- is done
#      explicitly.
#
# Deleting THIS FILE over USB reverts the device to Amazon's restart: the
# /sbin/reboot wrapper falls through when it is missing.

REAL=/sbin/reboot.kh.real
[ -x "$REAL" ] || REAL=/sbin/reboot
ART=/mnt/us/kindlehub_theme/system/shutdown/bg_reboot.png
LOG=/mnt/us/kindlehub_reboot.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
say() { [ -n "$FBINK" ] && "$FBINK" -q -m -y "$1" "$2" 2>/dev/null; }
bar() { [ -n "$FBINK" ] && "$FBINK" -q -P "$1" -y 30 2>/dev/null; }
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG" 2>/dev/null; sync; }

: > "$LOG" 2>/dev/null
log "KindleHub restart starting"

# ---- 0. ARM THE WATCHDOG BEFORE TOUCHING ANYTHING ----
# If any step below kills us, this still restarts the device.
WD="sleep 30; sync; sync; exec $REAL -f"
if command -v setsid >/dev/null 2>&1; then
    setsid sh -c "$WD" </dev/null >/dev/null 2>&1 &
    log "watchdog armed (setsid, 30s)"
else
    nohup sh -c "$WD" </dev/null >/dev/null 2>&1 &
    log "watchdog armed (nohup, 30s)"
fi

# ---- 1. our screen ----
# The art is 1236x1648 (a Paperwhite 11 panel). On any other panel fbink is
# asked to scale it to the screen (w=-1,h=-1) rather than crop it.
if [ -n "$FBINK" ]; then
    "$FBINK" -q -f -c 2>/dev/null
    if [ -f "$ART" ]; then
        SW=$("$FBINK" -e 2>/dev/null | tr ';' '\n' | sed -n 's/^viewWidth=//p' | head -1)
        SH=$("$FBINK" -e 2>/dev/null | tr ';' '\n' | sed -n 's/^viewHeight=//p' | head -1)
        AW=$(printf '%d' "0x$(dd if="$ART" bs=1 skip=16 count=4 2>/dev/null | hexdump -v -e '4/1 "%02X"')" 2>/dev/null)
        AH=$(printf '%d' "0x$(dd if="$ART" bs=1 skip=20 count=4 2>/dev/null | hexdump -v -e '4/1 "%02X"')" 2>/dev/null)
        if [ -n "$SW" ] && [ -n "$AW" ] && { [ "$SW" != "$AW" ] || [ "$SH" != "$AH" ]; }; then
            log "art is ${AW}x${AH}, panel is ${SW}x${SH} - scaling"
            "$FBINK" -q -g file="$ART",w=-1,h=-1 2>/dev/null
        else
            "$FBINK" -q -g file="$ART" 2>/dev/null
        fi
    fi
fi
say 22 "restarting"
bar 10

# ---- 2. only services that are NOT our parent ----
# Deliberately NOT stopped: lab126, x, framework -- stopping those kills this
# script. reboot -f ends them cleanly enough anyway.
killall -q -s KILL passwdlg 2>/dev/null
say 24 "closing dialogs     "
bar 25

say 24 "stopping services   "
for j in cron sshd usbnetd testd wifid wifis; do
    stop "$j" >/dev/null 2>&1
    log "stopped $j"
done
bar 60

# ---- 3. the part that actually protects data ----
say 24 "flushing to disk    "
log "sync + drop_caches"
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
sync
bar 90

say 24 "                    "
bar 100
say 24 "goodbye"
log "calling $REAL -f"
sync

# ---- 4. reboot ----
exec "$REAL" -f
