"""KindleHub replacements for the device's real UI icons.

The icons are 100x100 SVGs at /app/KPPMainApp/res/<group>/<Name>.svg -- plain
text, one shape, black on transparent. This writes drop-in replacements in the
same geometry so nothing needs rescaling.

Style rules, chosen for a 300dpi e-ink panel rendered at ~40px:
  * stroke weight 8 at 100 scale -- thinner than that greys out and disappears
  * round caps and joins, so ends stay solid rather than fraying
  * every glyph inside a 12..88 box, matching Amazon's own optical margin
  * geometry only, no gradients or opacity: the panel is 1-bit in these regions
"""
import os, sys

HEAD = ('<?xml version="1.0" encoding="UTF-8"?>\n'
        '<svg width="100px" height="100px" viewBox="0 0 100 100" version="1.1" '
        'xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">\n'
        '    <title>{title}</title>\n'
        '    <g id="KindleHub" stroke="none" stroke-width="1" fill="none" fill-rule="evenodd">\n'
        '{body}\n'
        '    </g>\n</svg>\n')

def stroke(d, w=8):
    return ('        <path d="%s" fill="none" stroke="#000000" stroke-width="%s" '
            'stroke-linecap="round" stroke-linejoin="round"/>' % (d, w))
def fill(d):
    return '        <path d="%s" fill="#000000" stroke="none"/>' % d

def circle(cx, cy, r, w=8):
    return ('        <circle cx="%s" cy="%s" r="%s" fill="none" stroke="#000000" '
            'stroke-width="%s"/>' % (cx, cy, r, w))

# --- the set -------------------------------------------------------------
# Browser nav bar first: these are the ones named in the live chrome config.
ICONS = {
 "KPPUIChrome": {
  # bold chevrons, heavier than Amazon's thin arrows so they read at a glance
  "LeftChevron":          stroke("M62,18 L30,50 L62,82"),
  "RightChevron":         stroke("M38,18 L70,50 L38,82"),
  # disabled = same glyph, lighter weight (the renderer does not grey for us)
  "LeftChevronDisabled":  stroke("M62,18 L30,50 L62,82", 4),
  "RightChevronDisabled": stroke("M38,18 L70,50 L38,82", 4),
  "Close":                stroke("M22,22 L78,78 M78,22 L22,78"),
  "Refresh":              (stroke("M78,50 A28,28 0 1 1 69.8,30.2") + "\n" +
                           fill("M82,16 L84,40 L60,34 Z")),
  "More":                 (fill("M50,20 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0") + "\n" +
                           fill("M50,50 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0") + "\n" +
                           fill("M50,80 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")),
  "Search":               circle(44, 44, 24) + "\n" + stroke("M61,61 L84,84"),
  "Go":                   stroke("M20,50 L74,50 M52,28 L74,50 L52,72"),
  "Add":                  stroke("M50,18 L50,82 M18,50 L82,50"),
  "Store":                (stroke("M18,34 L82,34 L74,84 L26,84 Z") + "\n" +
                           stroke("M36,34 C36,18 64,18 64,34")),
  "Library":              (stroke("M20,20 L20,80 M36,20 L36,80 M52,22 L52,80") + "\n" +
                           stroke("M64,26 L80,74", 8)),
  "Settings":             (circle(50, 50, 12) + "\n" +
                           stroke("M50,14 L50,26 M50,74 L50,86 M14,50 L26,50 M74,50 L86,50" +
                                  " M25,25 L33,33 M67,67 L75,75 M75,25 L67,33 M33,67 L25,75")),
  "Sync":                 (stroke("M22,50 A28,28 0 0 1 72,32") + "\n" + fill("M76,18 L78,42 L54,36 Z") +
                           "\n" + stroke("M78,50 A28,28 0 0 1 28,68") + "\n" + fill("M24,82 L22,58 L46,64 Z")),
  "Delete":               (stroke("M24,30 L76,30 M40,30 L40,20 L60,20 L60,30") + "\n" +
                           stroke("M30,30 L34,84 L66,84 L70,30") + "\n" +
                           stroke("M44,42 L44,72 M56,42 L56,72", 6)),
  "Browser":              (circle(50, 50, 32) + "\n" + stroke("M18,50 L82,50") + "\n" +
                           stroke("M50,18 C34,34 34,66 50,82 C66,66 66,34 50,18")),
 },
 "KPPUIQuickSettings": {
  "Wifi-On":   (stroke("M14,40 C34,22 66,22 86,40") + "\n" +
                stroke("M26,53 C40,41 60,41 74,53") + "\n" +
                stroke("M38,66 C46,60 54,60 62,66") + "\n" + fill("M50,80 m-6,0 a6,6 0 1,0 12,0 a6,6 0 1,0 -12,0")),
  "Wifi-Off":  (stroke("M26,53 C40,41 60,41 74,53", 6) + "\n" +
                fill("M50,80 m-6,0 a6,6 0 1,0 12,0 a6,6 0 1,0 -12,0") + "\n" +
                stroke("M18,18 L82,82")),
  "Airplane-On":  fill("M50,12 L58,12 L58,42 L88,58 L88,66 L58,58 L58,76 L68,84 L68,90 L50,86 L32,90 L32,84 L42,76 L42,58 L12,66 L12,58 L42,42 L42,12 Z"),
  "Airplane-Off": (fill("M50,12 L58,12 L58,42 L88,58 L88,66 L58,58 L58,76 L68,84 L68,90 L50,86 L32,90 L32,84 L42,76 L42,58 L12,66 L12,58 L42,42 L42,12 Z")
                   + "\n" + stroke("M16,16 L84,84", 9)),
  "Darkmode-On":  fill("M62,14 A38,38 0 1 0 86,62 A30,30 0 0 1 62,14 Z"),
  "Darkmode-Off": stroke("M62,14 A38,38 0 1 0 86,62 A30,30 0 0 1 62,14 Z", 7),
  "Settings-On":  (circle(50, 50, 12) + "\n" +
                   stroke("M50,14 L50,26 M50,74 L50,86 M14,50 L26,50 M74,50 L86,50"
                          " M25,25 L33,33 M67,67 L75,75 M75,25 L67,33 M33,67 L25,75")),
  "Settings-Off": (circle(50, 50, 12, 6) + "\n" +
                   stroke("M50,14 L50,26 M50,74 L50,86 M14,50 L26,50 M74,50 L86,50", 6)),
 },
}

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "svgout"
    n = 0
    for group, icons in ICONS.items():
        d = os.path.join(out, group)
        os.makedirs(d, exist_ok=True)
        for name, body in icons.items():
            svg = HEAD.format(title="KindleHub / %s" % name, body=body)
            open(os.path.join(d, name + ".svg"), "w").write(svg)
            n += 1
        print("  %-22s %d icons" % (group, len(icons)))
    print("  %d SVGs written to %s" % (n, out))

if __name__ == "__main__":
    main()
