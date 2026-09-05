#!/bin/bash
# Exercise Fullscreen ON / OFF on a computer, against window-manager modules
# from other firmwares, without a Kindle.
#
#   tools/sandbox-test.sh                # fetch 5.11.1.1 + 5.13.2 modules, run both
#   tools/sandbox-test.sh <app.lua> <dlg.lua> [expected-patched-app-md5]
#                                        # run against modules you supply, e.g.
#                                        # the .orig backups from your own device
#
# WHAT IT DOES
#   Builds a throwaway tree with /etc/xdg/awesome, /mnt/us and KOReader's
#   luajit under it, rewrites the device paths in a COPY of the three scripts
#   to point there, stubs mntroot / mount / md5sum / eips / ps on PATH, and
#   runs Fullscreen ON, Health Check, Fullscreen ON again (must be a no-op)
#   and Fullscreen OFF under a POSIX shell. Then it checks: the patched module
#   carries both markers, parses, strips back to the original, the backup and
#   its recorded md5 match, / is read-only again, and OFF restores the
#   original byte for byte.
#
# WHAT IT PROVES
#   That the patch applies to that firmware's module and is undone cleanly.
#   It cannot prove the browser fills the panel on that hardware; only the
#   hardware can. Report that at
#   https://github.com/arancool3000/kindlehub-device-pack/issues
#
# NEEDS: luajit (brew install luajit / apt install luajit), curl for the
#   fetch mode, and one of dash, ash, busybox sh or bash. Amazon's modules are
#   fetched from public firmware dumps on GitHub and are never committed here.
set -u
HERE=$(cd "$(dirname "$0")/.." && pwd)
WORK=${TMPDIR:-/tmp}/kh-sandbox.$$
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

LUAJIT=$(command -v luajit || true)
[ -n "$LUAJIT" ] || { echo "luajit not found on PATH"; exit 2; }
for s in dash ash bash; do command -v "$s" >/dev/null 2>&1 && { SH=$(command -v "$s"); break; }; done
MD5() { if command -v md5sum >/dev/null 2>&1; then md5sum "$1" | awk '{print $1}'; else md5 -q "$1"; fi; }

fail=0
say() { printf "  %-60s %s\n" "$1" "$2"; }
check() { if eval "$2"; then say "$1" "ok"; else say "$1" "FAIL"; fail=1; fi; }

one() {  # one <label> <app.lua> <dlg.lua> [expected-md5]
    label=$1; app=$2; dlg=$3; want=${4:-}
    SB=$WORK/$label; rm -rf "$SB"
    mkdir -p "$SB/bin" "$SB/etc/xdg/awesome" "$SB/mnt/us/kindlehub_theme/wm" "$SB/mnt/us/koreader"
    cp "$app" "$SB/etc/xdg/awesome/lab126_application_layer.lua"
    cp "$dlg" "$SB/etc/xdg/awesome/lab126_dialog_layer.lua"
    cp "$HERE/theme/wm/kh_patch.lua" "$SB/mnt/us/kindlehub_theme/wm/"
    ln -s "$LUAJIT" "$SB/mnt/us/koreader/luajit"
    echo ro > "$SB/state"
    printf '#!/bin/sh\necho "$1" > "%s/state"\n' "$SB" > "$SB/bin/mntroot"
    printf '#!/bin/sh\nst=$(cat "%s/state"); echo "/dev/root on / type ext3 ($st,relatime)"; echo "/dev/mmcblk0p4 on %s/mnt/us type vfat (rw)"\n' "$SB" "$SB" > "$SB/bin/mount"
    if command -v md5sum >/dev/null 2>&1; then printf '#!/bin/sh\nexec %s "$@"\n' "$(command -v md5sum)" > "$SB/bin/md5sum"
    else printf '#!/bin/sh\nfor f in "$@"; do echo "$(md5 -q "$f")  $f"; done\n' > "$SB/bin/md5sum"; fi
    printf '#!/bin/sh\nexit 0\n' > "$SB/bin/eips"
    printf '#!/bin/sh\necho "  1 root init"\n' > "$SB/bin/ps"
    chmod +x "$SB"/bin/*
    for s in FullscreenInstall.sh FullscreenOff.sh KindleHubDoctor.sh; do
        sed -e "s|/mnt/us|$SB/mnt/us|g" -e "s|/etc/xdg/awesome|$SB/etc/xdg/awesome|g" \
            -e "s|/etc/prettyversion.txt|$SB/etc/prettyversion.txt|g" \
            "$HERE/extensions/kindlehub/bin/$s" > "$SB/$s"
    done
    echo "Kindle (sandbox $label)" > "$SB/etc/prettyversion.txt"
    run() {
        PATH="$SB/bin:$PATH" "$SH" "$SB/$1" >/dev/null 2>&1
        i=0; while [ $i -lt 100 ]; do pgrep -f "$SB/$1" >/dev/null 2>&1 || break; sleep 0.2; i=$((i+1)); done; sleep 0.3
    }
    A=$SB/etc/xdg/awesome/lab126_application_layer.lua; D=$SB/etc/xdg/awesome/lab126_dialog_layer.lua
    a0=$(MD5 "$A"); d0=$(MD5 "$D")
    echo "== $label (app $a0, dialog $d0) =="
    run FullscreenInstall.sh
    LOG=$SB/mnt/us/kindlehub_fullscreen.log
    check "installer reports RESULT installed" "grep -q 'RESULT installed' '$LOG'"
    check "application layer carries both markers" "[ \$(grep -c 'KindleHub fullscreen' '$A') -eq 2 ]"
    check "application layer parses" "'$LUAJIT' -e \"assert(loadfile('$A'))\""
    check "strips back to the original" "'$LUAJIT' '$HERE/theme/wm/kh_patch.lua' verify application '$SB/mnt/us/kindlehub_theme_backup/lab126_application_layer.lua.orig' '$A' >/dev/null 2>&1"
    check "backup md5 recorded and matches" "[ \$(cat '$SB/mnt/us/kindlehub_theme_backup/lab126_application_layer.lua.orig.md5') = $a0 ]"
    check "dialog layer patched" "grep -q 'KindleHub: suppress' '$D'"
    check "/ read-only after install" "[ \$(cat '$SB/state') = ro ]"
    [ -n "$want" ] && check "patched md5 is the expected $want" "[ \$(MD5 '$A') = $want ]"
    a1=$(MD5 "$A")
    run KindleHubDoctor.sh
    # Only the FULLSCREEN section is meaningful here: the sandbox has no KUAL
    # menu, icons or daemon, so the other sections flag things on purpose.
    sed -n '/=== 3. FULLSCREEN ===/,/=== 4\./p' "$SB/mnt/us/kindlehub_doctor.txt" > "$SB/doctor_fs.txt"
    check "health check: both backups pristine, nothing flagged" "grep -q 'application-layer backup is pristine' '$SB/doctor_fs.txt' && grep -q 'dialog-layer backup is pristine' '$SB/doctor_fs.txt' && ! grep -q -E 'PROB|WARN' '$SB/doctor_fs.txt'"
    run FullscreenInstall.sh
    check "second run is a no-op" "grep -q 'already patched' '$LOG' && [ \$(MD5 '$A') = $a1 ]"
    run FullscreenOff.sh
    check "OFF restores the application layer" "[ \$(MD5 '$A') = $a0 ]"
    check "OFF restores the dialog layer" "[ \$(MD5 '$D') = $d0 ]"
    check "OFF clears the flag" "[ ! -f '$SB/mnt/us/kindlehub_fullscreen' ]"
    check "/ read-only after OFF" "[ \$(cat '$SB/state') = ro ]"
}

if [ $# -ge 2 ]; then
    one supplied "$1" "$2" "${3:-}"
else
    echo "fetching window-manager modules from public firmware dumps..."
    P2=https://raw.githubusercontent.com/birdsofsummer/kpw2_rom/master/tt/etc/xdg/awesome
    P4=https://raw.githubusercontent.com/libxzr/sysdump_amazon_rex/master/rootfs.img.gz/fwo_rootfs.img/etc/xdg/awesome
    mkdir -p "$WORK/pw2" "$WORK/pw4"
    for f in lab126_application_layer.lua lab126_dialog_layer.lua; do
        curl -fsSL --max-time 60 -o "$WORK/pw2/$f" "$P2/$f" || { echo "could not fetch $P2/$f"; exit 2; }
        curl -fsSL --max-time 60 -o "$WORK/pw4/$f" "$P4/$f" || { echo "could not fetch $P4/$f"; exit 2; }
    done
    one "pw2-5.11.1.1" "$WORK/pw2/lab126_application_layer.lua" "$WORK/pw2/lab126_dialog_layer.lua"
    one "pw4-5.13.2"   "$WORK/pw4/lab126_application_layer.lua" "$WORK/pw4/lab126_dialog_layer.lua"
    echo
    echo "To run against your own device's modules (the .orig files in"
    echo "kindlehub_theme_backup on the Kindle, or /etc/xdg/awesome over SSH):"
    echo "  tools/sandbox-test.sh app.lua dialog.lua"
fi
echo
[ $fail = 0 ] && echo "sandbox: all checks passed (shell: $SH)" || { echo "sandbox: FAILURES (shell: $SH)"; exit 1; }
