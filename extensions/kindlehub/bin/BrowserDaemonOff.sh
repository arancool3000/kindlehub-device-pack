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
  rm -f "$FLAG" 2>/dev/null
  ## The daemon notices the flag within ~30s; clear the block now so sleep works
  ## immediately rather than making the user wait for it.
  lipc-set-prop com.lab126.powerd preventScreenSaver 0 2>/dev/null
  sleep 2
  for p in $(ps 2>/dev/null | grep '[B]rowserDaemon' | awk '{print $1}'); do kill "$p" 2>/dev/null; done
  echo "$(date '+%H:%M:%S') preventScreenSaver = $(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null)"
  screen "                                        " 2
  screen "  BROWSER CONTROLS OFF                   " 2
  screen "  normal sleep restored                  " 4
  sync
} >> "$LOG" 2>&1 &
exit 0
