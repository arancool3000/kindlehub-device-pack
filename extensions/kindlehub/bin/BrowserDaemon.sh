#!/bin/bash
# Name: Browser Controls ON
# Author: repair
# DontUseFBInk

## Power-button gestures for the fullscreen browser, plus cover-only sleep.
##
##   1 tap   nothing. The device stays awake indefinitely.
##   2 taps  toggle the browser bar (fullscreen on/off)
##   3 taps  leave fullscreen and go Home
##   cover   closing the magnetic cover sleeps the device
##
## WHY THE BUTTON CANNOT SIMPLY BE REBOUND
##   Taking /dev/input/event0 away from powerd needs an EVIOCGRAB ioctl, which
##   shell cannot issue, and would mean racing powerd for the same key. So the
##   problem is inverted: preventScreenSaver=1 stops ANYTHING sleeping the
##   device -- the power button included -- and this daemon watches the events
##   itself. evdev delivers a copy to every reader, so powerd still sees the key;
##   it just is not allowed to act on it.
##
## HOW THE COVER IS DETECTED (measured, not guessed)
##   com.lab126.hal publishes magSensorClosed / magSensorOpened. powerd never
##   mentions the cover, which is why an earlier version that subscribed to
##   powerd did nothing. /proc/interrupts also shows a hall_sensor line.
##
## THE EVENT FORMAT (proven on this device)
##   /dev/input/event0, 16-byte input_event structs. Power key press is
##   type=0100 code=7400 value=01000000 in the hexdump byte order.
##
## WHICH EVENT DEVICE (other Kindles)
##   event0 is the power button on a Paperwhite 11 (bd71828-pwrkey), but not
##   necessarily elsewhere -- an Oasis has page-turn buttons on gpio-keys, and
##   every model orders its devices differently. So the device is found from
##   /proc/bus/input/devices: the one whose KEY bitmap has bit 116 (KEY_POWER)
##   wins, then one whose name says pwr/power, then a generic button device,
##   and touchscreens/sensors are never chosen. The choice and the full table
##   are logged, so a wrong pick is visible rather than silent. event0 is the
##   fallback.
##
## SAFETY
##   * Never spins: every read is a blocking dd with a timeout, and both loops
##     sleep before retrying if a read returns instantly. A busy-wait here would
##     flatten the battery and look exactly like a hung device.
##   * Stops cleanly: delete /mnt/us/kindlehub_browserd_on, or run
##     "Browser Controls OFF". Checked every iteration; on exit it always
##     restores preventScreenSaver=0 so it cannot leave sleep blocked.
##   * Bounded: exits after 24h so a forgotten daemon cannot run forever.

FLAG=/mnt/us/kindlehub_browserd_on
FSFLAG=/mnt/us/kindlehub_fullscreen
LOG=/mnt/us/kindlehub_browserd.log
DEV=/dev/input/event0            # replaced by find_power_input in main
MAXSEC=86400
GAP=1                      # seconds to wait for another tap in the same gesture
DIAG=1                     # log raw events for the first DIAGSEC seconds
DIAGSEC=90

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}
log() { echo "$(date '+%H:%M:%S') $*" >> "$LOG" 2>/dev/null; sync; }

## Which /dev/input/eventN is the power button (see the header). Scores each
## block of /proc/bus/input/devices: +4 if its KEY bitmap has KEY_POWER (116),
## +2 for a pwr/power name, +1 for a generic button name, 0 for anything that
## is a touchscreen or a sensor. Prints the best; event0 if nothing scores.
find_power_input() {
    awk '
      function hexval(c) { return index("0123456789abcdef", tolower(c)) - 1 }
      function haskey(line, n,   w, nw, wl, bpw, idx, bit, word, nib, i) {
        sub(/^B: KEY=/, "", line); nw = split(line, w, " ")
        if (nw < 1) return 0
        wl = 0; for (i = 1; i <= nw; i++) if (length(w[i]) > wl) wl = length(w[i])
        bpw = wl * 4; if (bpw < 32) bpw = 32
        idx = int(n / bpw); bit = n % bpw
        if (idx >= nw) return 0
        word = w[nw - idx]
        while (length(word) < bpw / 4) word = "0" word
        nib = substr(word, length(word) - int(bit / 4), 1)
        return int(hexval(nib) / (2 ^ (bit % 4))) % 2
      }
      function emit(   e, s) {
        if (h != "" && match(h, /event[0-9]+/)) {
          e = substr(h, RSTART, RLENGTH); s = 0
          if (name ~ /pwr|power/) s += 2
          else if (name ~ /button|btn|gpio-keys|keypad|key/) s += 1
          if (name ~ /touch|screen|elan|cyttsp|zforce|pixart|parade|accel|gyro|hall|cover|wacom|pen|stylus|magnet|light/) s = 0
          if (pw) s += 4
          if (s > best) { best = s; bestdev = e }
        }
        name = ""; h = ""; pw = 0
      }
      /^N: Name=/ { name = tolower($0) }
      /^H: Handlers=/ { h = $0 }
      /^B: KEY=/ { pw = haskey($0, 116) }
      /^$/ { emit() }
      END { emit(); if (bestdev != "") print "/dev/input/" bestdev; else print "/dev/input/event0" }
    ' /proc/bus/input/devices 2>/dev/null
}

cleanup() {
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
    rm -f "$FLAG" 2>/dev/null
    log "stopped; preventScreenSaver restored to 0"
    sync
}

## --- one power-button press, or non-zero if none within $1 seconds ---
## Deliberately tolerant: it matches ANY key-DOWN on this device rather than a
## specific keycode. event0 on this model carries only the power button, and
## hard-coding code=7400 from an older note is exactly the kind of assumption
## that has cost several round trips already. The code seen is logged, so if it
## ever does need narrowing the log says what to narrow it to.
##   type  0100 = EV_KEY
##   value 01000000 = key down (00000000 is the release, ignored)
read_press() {
    ## The subshell + 2>/dev/null contains the "Terminated" the shell prints
    ## when timeout kills dd -- harmless, but it buried the real log lines.
    ev=$( { timeout "$1" dd if="$DEV" bs=16 count=1 2>/dev/null | hexdump -v -e '16/1 "%02X"' 2>/dev/null; } 2>/dev/null )
    [ -z "$ev" ] && return 1
    t=$(echo "$ev" | cut -c17-20)
    c=$(echo "$ev" | cut -c21-24)
    v=$(echo "$ev" | cut -c25-32)
    if [ "$DIAG" = "1" ]; then log "raw ev type=$t code=$c value=$v"; fi
    if [ "$t" = "0100" ] && [ "$v" = "01000000" ]; then
        log "key down, code=$c"
        return 0
    fi
    return 1
}

SITE=kindlehub.pro
BDB=/var/local/KPPBrowser.db

## Is the browser actually the foreground app?
##
## "ps | grep kindle_browser" DOES NOT WORK: /usr/bin/browser execs it through
## chroot, and busybox ps does not show that name -- so the check always failed
## and the daemon kept relaunching a browser that was already up. That is what
## produced the extra launches and the "application could not be started"
## dialog. The window manager's own active-app title is authoritative.
browser_up() {
    lipc-get-prop com.lab126.winmgr getActiveAppTitle 2>/dev/null | grep -q 'com.lab126.browser'
}

## The page you were on, so toggling the bar does not throw it away.
## KPPBrowser.db holds bookmark/history/setting tables; the column name is not
## documented anywhere, so try the likely spellings and fall back to the site
## rather than guessing wrong and reopening nothing.
current_url() {
    if command -v sqlite3 >/dev/null 2>&1 && [ -f "$BDB" ]; then
        for q in "select url from history order by rowid desc limit 1;" \
                 "select URL from history order by rowid desc limit 1;" \
                 "select url from bookmark order by rowid desc limit 1;"; do
            u=$(sqlite3 "$BDB" "$q" 2>/dev/null | head -1)
            case "$u" in
                http://*|https://*) echo "$u"; return 0 ;;
            esac
        done
    fi
    echo "$SITE"
}

refresh_browser() {
    ## Cover the screen for the whole swap. Without this you see the library,
    ## and any dialog the framework throws, while the browser is being replaced.
    ## fbink paints straight to the framebuffer, so it sits over whatever the
    ## framework is drawing until the new browser window paints over it.
    overlay() {
        [ -n "$FBINK" ] || return
        "$FBINK" -q -f -c 2>/dev/null
        "$FBINK" -q -m -y 20 "switching" 2>/dev/null
    }
    overlay

    ## Kill, then WAIT FOR IT TO ACTUALLY BE GONE before relaunching. Relaunching
    ## while the old process is still dying is what produced the
    ## "application could not be started" dialog -- appmgrd still considered it
    ## running. Polling for its exit removes the race instead of papering over it
    ## with a fixed sleep.
    killall -q -9 kindle_browser 2>/dev/null
    i=0
    while [ "$i" -lt 8 ]; do
        browser_up || break
        i=$((i+1)); sleep 1
    done
    log "old browser gone after ${i}s"

    URL=$(current_url)
    log "reopening at $URL"
    i=1
    while [ "$i" -le 3 ]; do
        lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser?view=$URL" 2>/dev/null
        ## Poll rather than sleeping a fixed 3s -- usually back much sooner.
        j=0
        while [ "$j" -lt 10 ]; do
            if browser_up; then
                log "browser back (attempt $i, ${j}s)"
                ## Clear any dialog the framework raised during the swap.
                lipc-set-prop com.lab126.pillow pillowAlert '{"action":"dismiss"}' 2>/dev/null
                return 0
            fi
            j=$((j+1)); sleep 1
        done
        overlay
        log "relaunch attempt $i did not take, retrying"
        i=$((i+1))
    done
    log "WARN browser did not come back after 3 attempts"
    screen "  browser did not reopen - tap again    " 2
    return 1
}


toggle_bar() {
    if [ -f "$FSFLAG" ]; then
        rm -f "$FSFLAG"; log "2 taps -> bar SHOWN (fullscreen off)"
        screen "  browser bar shown                 " 2
    else
        touch "$FSFLAG"; log "2 taps -> bar HIDDEN (fullscreen on)"
        screen "  fullscreen                        " 2
    fi
    sync
    refresh_browser
}

exit_fullscreen() {
    rm -f "$FSFLAG" 2>/dev/null; sync
    log "3 taps -> leaving fullscreen, going Home"
    screen "  leaving fullscreen                " 2
    lipc-set-prop com.lab126.appmgrd start app://com.lab126.KPPMainApp 2>/dev/null
}

do_sleep() {
    ## Release the block just long enough for the real sleep to happen, then
    ## re-arm, so the cover works while the button stays inert.
    log "cover closed -> sleeping"
    lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
    sleep 1
    lipc-set-prop com.lab126.powerd powerButton 1 2>/dev/null
    sleep 3
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
    log "re-armed after sleep"
}

## Amazon's fastmetrics dumps a "crash" report whenever the browser is killed
## unexpectedly -- which is exactly what happens when you plug in USB with the
## browser open: the framework tears the app down to enter drive mode. The
## report is ~3.5MB and appears in the library as a book. It is an artefact of
## the teardown, not a fault, so it is simply swept away.
sweep_dumps() {
    n=$(ls /mnt/us/documents/fastmetrics_*crash* 2>/dev/null | wc -l)
    [ "${n:-0}" -eq 0 ] && return
    rm -f /mnt/us/documents/fastmetrics_*crash*.txt 2>/dev/null
    rm -f /mnt/us/documents/fastmetrics_*crash*.tgz 2>/dev/null
    rm -rf /mnt/us/documents/fastmetrics_*crash*.sdr 2>/dev/null
    rm -f /mnt/us/Indexer_Dump_*.txt 2>/dev/null
    log "swept $n crash artifact(s)"
}

## ---- cover watcher, background ----
cover_loop() {
    while [ -f "$FLAG" ]; do
        sweep_dumps
        EV=$(timeout 30 lipc-wait-event -s 30 com.lab126.hal '*' 2>/dev/null | head -1)
        case "$EV" in
            *magSensorClosed*) do_sleep ;;
            *magSensorOpened*) log "cover opened" ;;
        esac
        sleep 1                     # never spin, even if the wait returns at once
    done
}

## ---- button watcher, foreground ----
button_loop() {
    START=$(cut -d. -f1 /proc/uptime)
    while [ -f "$FLAG" ]; do
        NOW=$(cut -d. -f1 /proc/uptime)
        [ $((NOW - START)) -gt "$MAXSEC" ] && { log "24h limit reached"; break; }

        [ "$DIAG" = "1" ] && [ $((NOW - START)) -gt "$DIAGSEC" ] && { DIAG=0; log "raw-event logging off"; }

        if read_press 30; then
            n=1
            while read_press "$GAP"; do n=$((n+1)); [ "$n" -ge 5 ] && break; done
            log "gesture: $n tap(s)"
            case "$n" in
                1) : ;;                      # deliberately nothing: stays awake
                2) toggle_bar ;;
                3) exit_fullscreen ;;
                *) log "ignoring $n taps" ;;
            esac
        else
            sleep 1                          # timeout, not a press - never spin
        fi
    done
}

main() {
    log "Browser controls starting (pid $$)"
    D=$(find_power_input)
    [ -n "$D" ] && [ -e "$D" ] && DEV="$D"
    log "power button device: $DEV"
    [ -e "$DEV" ] || { log "ABORT no $DEV"; screen "No input device" 4; return 1; }

    ## Liveness is tested by looking for a live daemon PROCESS, never by a pid
    ## recorded in the flag: inside "{ ...; } &" the $$ is the parent shell,
    ## which exits at once, and the reused pid then made kill -0 succeed so the
    ## daemon refused to start every time. If an older copy is somehow still
    ## running, take over from it rather than refusing.
    for oldp in $(ps 2>/dev/null | grep '[B]rowserDaemon' | awk '{print $1}'); do
        [ "$oldp" = "$$" ] && continue
        kill "$oldp" 2>/dev/null && log "stopped an older daemon (pid $oldp)"
    done
    ## Record the input devices once, so which eventN is the power button is a
    ## fact in the log rather than something inferred from an old note.
    log "--- input devices (chosen: $DEV) ---"
    cat /proc/bus/input/devices 2>/dev/null | grep -E "^N:|^H:|^B: EV=|^B: KEY=" >> "$LOG" 2>/dev/null

    touch "$FLAG"
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
    log "preventScreenSaver = $(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)"

    screen "                                        " 2
    screen "  BROWSER CONTROLS ON                   " 2
    screen "  1 tap  = nothing (stays awake)        " 4
    screen "  2 taps = show/hide the browser bar    " 5
    screen "  3 taps = leave fullscreen             " 6
    screen "  close the cover to sleep              " 8

    cover_loop &
    COVER_PID=$!
    button_loop
    kill "$COVER_PID" 2>/dev/null
}

## Launch exactly as the version that demonstrably worked did: a background
## block. Do not "improve" this without evidence -- a setsid re-exec was tried
## and was not the problem.
: > "$LOG" 2>/dev/null
{ trap cleanup EXIT INT TERM; main; cleanup; } >> "$LOG" 2>&1 &
exit 0
