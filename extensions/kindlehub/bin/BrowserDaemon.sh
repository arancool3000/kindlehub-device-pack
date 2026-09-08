#!/bin/bash
# Name: Browser Controls ON
# Author: repair
# DontUseFBInk

## Power-button gestures for the fullscreen browser, plus cover sleep.
##
##   1 tap   sleep, exactly as closing the cover does
##   2 taps  toggle the browser bar (fullscreen on/off)
##   3 taps  toggle fullscreen: leave to Home, or bring the browser back
##   cover   closing the magnetic cover sleeps the device
##
## WHY ONE TAP HAS TO SWALLOW THE NEXT PRESS
##   evdev hands every reader a copy of the key, which is what lets this daemon
##   watch the button at all -- but it also means the press that WAKES the
##   device is delivered here too. Left alone that press reads as a fresh 1-tap
##   gesture and puts the device straight back to sleep, so the button could
##   never wake it. After a button sleep the next press is therefore swallowed.
##   If you open the cover instead, the cover watcher clears the marker so your
##   next press is not eaten.
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
WAKE=/var/tmp/kh_wake_pending   # set after a button sleep; the wake press is eaten
PIDF=/var/tmp/kh_browserd.pid   # real pid of the running daemon, written by the parent
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

## MYPID is this block's REAL pid. $$ is the parent's and the parent has already
## exited, so it cannot be used here -- but the redirection below is performed by
## this subshell, so /proc/self resolves to us.
read MYPID _ < /proc/self/stat 2>/dev/null

CLEANED=0
cleanup() {
    [ "$CLEANED" = "1" ] && return 0
    CLEANED=1
    ## Only tear down the shared state if we still OWN it. A daemon that is being
    ## replaced can take up to 30s to notice its TERM (it sits in a blocking dd),
    ## by which time the new one has already claimed the flag -- clearing it here
    ## unconditionally deleted the new daemon's flag and dropped
    ## preventScreenSaver, leaving the user with no daemon and no explanation.
    ## If /proc/self/stat could not be read we cannot prove ownership. Assume we
    ## ARE the owner in that case: a lone daemon that fails to restore
    ## preventScreenSaver leaves the power button dead until a reboot, which is
    ## worse and hits everyone, whereas clobbering only matters when a newer
    ## daemon exists at all.
    if [ -z "$MYPID" ] || [ "$(cat "$PIDF" 2>/dev/null)" = "$MYPID" ]; then
        lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
        rm -f "$WAKE" "$FLAG" "$PIDF" 2>/dev/null
        log "stopped; preventScreenSaver restored to 0"
    else
        log "stopped (pid $MYPID); a newer daemon owns the flag - left alone"
    fi
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

    ## The history DB is written lazily, so its newest row can be a page you
    ## left ages ago -- which is why a toggle could throw you back to an old
    ## site. Record every candidate once per toggle so the right source can be
    ## chosen from evidence rather than guessed at.
    log "url sources: history=$(current_url)"
    log "  history db mtime: $(ls -l "$BDB" 2>/dev/null | awk '{print $6, $7, $8}')"
    log "  winmgr title: $(lipc-get-prop com.lab126.winmgr getActiveAppTitle 2>/dev/null)"
    for kp in currentURL currentUrl url location; do
        kv=$(lipc-get-prop com.lab126.browser "$kp" 2>/dev/null)
        [ -n "$kv" ] && log "  browser.$kp = $kv"
    done
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

## 3 taps is the way IN and the way OUT of the fullscreen browser. 2 taps
## toggles the bar while you stay in it; 3 taps leaves it entirely, and pressing
## 3 again brings it back rather than leaving you to find KUAL.
toggle_fullscreen() {
    ## Branch on whether the browser is actually up, NOT on FSFLAG. FSFLAG means
    ## "bar hidden" and 2 taps clears it while you are still in the browser, so
    ## keying off it made 3 taps re-open the browser you were already in.
    if browser_up; then
        rm -f "$FSFLAG" 2>/dev/null; sync
        log "3 taps -> leaving fullscreen, going Home"
        screen "  leaving fullscreen                " 2
        lipc-set-prop com.lab126.appmgrd start app://com.lab126.KPPMainApp 2>/dev/null
    else
        touch "$FSFLAG"; sync
        URL=$(current_url)
        log "3 taps -> fullscreen back on, opening at $URL"
        screen "  fullscreen                        " 2
        lipc-set-prop com.lab126.appmgrd start "app://com.lab126.browser?view=$URL" 2>/dev/null
    fi
}

do_sleep() {
    ## Release the block just long enough for the real sleep to happen, then
    ## re-arm, so the next press or cover close still reaches us.
    log "${1:-cover closed} -> sleeping"
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
            *magSensorClosed*) do_sleep "cover closed" ;;
            *magSensorOpened*)
                ## Woken by the cover, not the button, so there is no wake press
                ## to swallow -- clear the marker or the next real press is eaten.
                [ -f "$WAKE" ] && { rm -f "$WAKE"; log "cover opened (wake press no longer expected)"; } \
                               || log "cover opened" ;;
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
                1) do_sleep "1 tap"
                   : > "$WAKE"
                   while [ -f "$FLAG" ] && [ -f "$WAKE" ]; do
                       if read_press 30; then
                           rm -f "$WAKE"; log "swallowed the wake press"
                       fi
                   done ;;
                2) toggle_bar ;;
                3) toggle_fullscreen ;;
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

    ## Whether an older daemon was stopped is decided in the PARENT, before this
    ## block is backgrounded -- see the launcher at the end of the file. It is
    ## reported here so it lands in the freshly truncated log.
    log "${TAKEOVER:-previous daemon: not checked}"
    ## Proves /proc/self resolved to this block and not to the exited parent.
    ## If this is empty, cleanup falls back to unconditional teardown.
    log "my pid (from /proc/self/stat): ${MYPID:-UNREADABLE}"
    ## Record the input devices once, so which eventN is the power button is a
    ## fact in the log rather than something inferred from an old note.
    log "--- input devices (chosen: $DEV) ---"
    cat /proc/bus/input/devices 2>/dev/null | grep -E "^N:|^H:|^B: EV=|^B: KEY=" >> "$LOG" 2>/dev/null

    touch "$FLAG"
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 2>/dev/null
    log "preventScreenSaver = $(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)"

    screen "                                        " 2
    screen "  BROWSER CONTROLS ON                   " 2
    screen "  1 tap  = sleep                        " 4
    screen "  2 taps = show/hide the browser bar    " 5
    screen "  3 taps = fullscreen in / out          " 6
    screen "  or close the cover to sleep           " 8

    cover_loop &
    COVER_PID=$!
    button_loop
    kill "$COVER_PID" 2>/dev/null
}

## Launch exactly as the version that demonstrably worked did: a background
## block. Do not "improve" this without evidence -- a setsid re-exec was tried
## and was not the problem.
##
## STOPPING THE PREVIOUS DAEMON HAS TO HAPPEN HERE, IN THE PARENT.
##   $$ does not change inside "{ ...; } &" -- it stays the parent's pid, and
##   the parent exits immediately. So a guard written inside the block can
##   neither identify itself nor be identified, which is why the old
##   "ps | grep BrowserDaemon" take-over never once fired and four daemons
##   ended up reading the same power button and each relaunching the browser.
##   $! here is the real pid of the block, so it is recorded and reused.
OLD=$(cat "$PIDF" 2>/dev/null)
if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    ## Pids get reused, so confirm it is ours before killing anything.
    OLDCMD=$(tr '\0' ' ' < "/proc/$OLD/cmdline" 2>/dev/null)
    if echo "$OLDCMD" | grep -q 'BrowserDaemon'; then
        ## The grace period MUST exceed the longest blocking read (timeout 30 in
        ## read_press and in cover_loop): a shell defers a TERM trap until the
        ## current foreground command returns, so a 10s wait ended before the old
        ## daemon had even noticed, and the parent started a second one.
        kill "$OLD" 2>/dev/null
        i=0
        while [ "$i" -lt 35 ] && kill -0 "$OLD" 2>/dev/null; do sleep 1; i=$((i+1)); done
        if kill -0 "$OLD" 2>/dev/null; then
            kill -9 "$OLD" 2>/dev/null
            j=0
            while [ "$j" -lt 5 ] && kill -0 "$OLD" 2>/dev/null; do sleep 1; j=$((j+1)); done
            TAKEOVER="previous daemon (pid $OLD) ignored TERM for ${i}s, killed it"
        else
            TAKEOVER="stopped the previous daemon (pid $OLD) after ${i}s"
        fi
    else
        ## Report the cmdline verbatim. If the launcher ever stops putting the
        ## script name in argv this check would silently never match, and the
        ## duplicate daemons would come straight back -- the log must show it.
        TAKEOVER="stale pidfile: pid $OLD is [$OLDCMD], not ours"
    fi
else
    TAKEOVER="no previous daemon was running"
fi

## Sweep any daemon the pidfile does not know about -- orphans from before the
## pidfile existed, or a cover watcher left behind by a kill -9. Safe here and
## ONLY here: the new block does not exist yet, so nothing of ours is running.
## $$ IS valid in this parent (it is the real shell); it is only inside
## "{ ...; } &" that it silently becomes the parent's and matches nothing.
## The pattern is anchored to the .sh so it cannot match BrowserDaemonOff.sh.
SWEPT=0
for p in $(ps 2>/dev/null | grep '[B]rowserDaemon\.sh' | awk '{print $1}'); do
    [ "$p" = "$$" ] && continue
    kill -9 "$p" 2>/dev/null && SWEPT=$((SWEPT+1))
done
[ "$SWEPT" -gt 0 ] && TAKEOVER="$TAKEOVER; swept $SWEPT orphaned daemon process(es)"
export TAKEOVER

: > "$LOG" 2>/dev/null
{ trap cleanup EXIT; trap 'cleanup; exit 143' INT TERM; main; cleanup; } >> "$LOG" 2>&1 &
echo $! > "$PIDF" 2>/dev/null
exit 0
