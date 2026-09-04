#!/bin/sh
# KindleHub /sbin/reboot wrapper.
#
# The framework's Restart button ends up calling /sbin/reboot. This intercepts
# that and runs OUR restart instead, so the official button diverts to ours.
#
# Three things must still pass straight through to the real binary, or the
# device could not shut down at all:
#   * halt / poweroff -- they are SYMLINKS to reboot and behave by argv[0]
#   * an explicit -f  -- that is shutdown.conf's own final step, and ours too;
#                        without this passthrough it would recurse forever
#   * a missing script -- if /mnt/us/kindlehub_reboot.sh is gone (deleted over
#                        USB to revert, or /mnt/us not mounted) we fall through
#                        to Amazon's normal path. That is the OFF switch.

REAL=/sbin/reboot.kh.real
KH=/mnt/us/kindlehub_reboot.sh

[ -x "$REAL" ] || exec /bin/busybox reboot "$@"     # last-ditch, should not happen

case "$(basename "$0")" in
    halt|poweroff) exec "$REAL" "$@" ;;
esac

for a in "$@"; do
    case "$a" in
        -f|--force) exec "$REAL" "$@" ;;
    esac
done

if [ -x "$KH" ]; then
    exec "$KH"
fi

exec "$REAL" "$@"
