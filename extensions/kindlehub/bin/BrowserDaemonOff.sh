#!/bin/bash
# Name: Browser Controls OFF
# Author: repair
# DontUseFBInk
## Stops the button/cover daemon and restores normal sleep. Deleting
## /mnt/us/kindlehub_browserd_on by hand does the same thing.

FLAG=/mnt/us/kindlehub_browserd_on
LOG=/mnt/us/kindlehub_browserd.log

FBINK=""
for d in /mnt/us/libkh/bin /mnt/us/koreader /var/tmp; do
    [ -x "$d/fbink" ] && { FBINK="$d/fbink"; break; }
done
screen() {
    if [ -n "$FBINK" ]; then "$FBINK" -q -y "${2:-1}" "$1" 2>/dev/null
    else eips 1 "${2:-1}" "$1" 2>/dev/null; fi
}

{
  echo "$(date '+%H:%M:%S') stopping browser controls"
  rm -f "$FLAG" /var/tmp/kh_wake_pending 2>/dev/null
  ## The daemon notices the flag within ~30s; clear the block now so sleep works
  ## immediately rather than making the user wait for it.
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  sleep 2
  ## Kill by the recorded pid first, confirming via /proc that it is really ours.
  ## Then wait: the daemon sits in a 30s blocking read and a shell defers a TERM
  ## trap until that returns, so removing the pidfile immediately -- as this used
  ## to -- left a live daemon that no later take-over could find.
  OLD=$(cat /var/tmp/kh_browserd.pid 2>/dev/null)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
      if tr '\0' ' ' < "/proc/$OLD/cmdline" 2>/dev/null | grep -q 'BrowserDaemon'; then
          kill "$OLD" 2>/dev/null
          i=0
          while [ "$i" -lt 35 ] && kill -0 "$OLD" 2>/dev/null; do sleep 1; i=$((i+1)); done
          kill -0 "$OLD" 2>/dev/null && { kill -9 "$OLD" 2>/dev/null; sleep 2
              echo "$(date '+%H:%M:%S') pid $OLD ignored TERM for ${i}s, killed it"; } \
            || echo "$(date '+%H:%M:%S') pid $OLD stopped after ${i}s"
      fi
  fi
  ## Anchored to the .sh: the bare word also matches THIS script
  ## (BrowserDaemonOff.sh), and this block would have signalled itself.
  for p in $(ps 2>/dev/null | grep '[B]rowserDaemon\.sh' | awk '{print $1}'); do kill -9 "$p" 2>/dev/null; done
  rm -f /var/tmp/kh_browserd.pid 2>/dev/null
  echo "$(date '+%H:%M:%S') preventScreenSaver = $(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)"
  screen "                                        " 2
  screen "  BROWSER CONTROLS OFF                   " 2
  screen "  normal sleep restored                  " 4
  sync
} >> "$LOG" 2>&1 &
exit 0
