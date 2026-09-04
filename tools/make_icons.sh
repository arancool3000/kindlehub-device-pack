#!/bin/bash
# Regenerate the icon set and repack theme/icons.tar.gz.
#
# Run on your computer, not the Kindle. Needs python3 and nothing else.
#
#     ./tools/make_icons.sh                     every icon the generators know
#     ./tools/make_icons.sh /path/to/res        only icons that exist there
#
# The optional argument is a copy of the device's /app/KPPMainApp/res. Passing
# it filters the output to names the firmware actually has. The shipped archive
# was built that way against 5.19.2 and holds 229 icons; without the filter you
# get about a dozen more, which simply get skipped at install time because
# IconsInstall.sh never creates an icon the app did not already ask for.
#
# The three generators each cover a different part of the UI; they write into
# the same output tree and are safe to run repeatedly.
#
# DELIBERATELY NOT REDRAWN, and why:
#   * brand marks (Goodreads, Audible, Amazon Kids, the Prime and Unlimited
#     badges) -- redrawing someone's logo in our own style is both wrong and
#     confusing, and the badges carry meaning the shape alone does not.
#   * colour swatches -- the highlighter picker identifies a colour by the
#     swatch art. Restyling those breaks the picker.

set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
RES="${1:-}"
OUT=$(mktemp -d "${TMPDIR:-/tmp}/kh-icons.XXXXXX")
trap 'rm -rf "$OUT"' EXIT

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found" >&2; exit 1; }

cd "$HERE"
for g in gen_svg.py gen_svg2.py gen_svg3.py; do
    [ -f "$g" ] || { echo "ERROR: missing $g" >&2; exit 1; }
    echo "--- $g ---"
    python3 "$g" "$OUT" ${RES:+"$RES"}
done

N=$(find "$OUT" -name '*.svg' | wc -l | tr -d ' ')
[ "$N" -gt 0 ] || { echo "ERROR: no SVGs produced" >&2; exit 1; }

## Every icon carries a KindleHub marker; IconsInstall.sh counts them to prove
## the install actually took, so a marker-less icon would read as a failure.
BAD=$(grep -L 'KindleHub' $(find "$OUT" -name '*.svg') 2>/dev/null | wc -l | tr -d ' ')
[ "$BAD" = "0" ] || { echo "ERROR: $BAD icon(s) have no KindleHub marker" >&2; exit 1; }

tar -czf "$ROOT/theme/icons.tar.gz" -C "$OUT" .
echo
echo "$N icons -> theme/icons.tar.gz ($(du -h "$ROOT/theme/icons.tar.gz" | cut -f1))"
