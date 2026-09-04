"""Second batch of KindleHub icon replacements.

Same 100x100 geometry and weight rules as gen_svg.py. Deliberately SKIPPED:
  * brand marks (Goodreads, Audible, AmazonKids, Kindle Plus/Unlimited, Prime,
    KSO, msft_doc_icon) -- third-party or Amazon logos, not ours to redraw
  * large illustrations (BoyUnderTree, welcome_to_kindle, Read-your-way,
    gpc-navigating-your-kindle, day_one_*) -- artwork, not glyphs
"""
import os, sys
from gen_svg import HEAD, stroke, fill, circle

def rect(x, y, w, h, r=0, sw=8):
    return ('        <rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" '
            'stroke="#000000" stroke-width="%s" stroke-linejoin="round"/>' % (x, y, w, h, r, sw))

# reusable pieces
CHEV_L  = "M62,18 L30,50 L62,82"
CHEV_R  = "M38,18 L70,50 L38,82"
CHEV_U  = "M18,62 L50,30 L82,62"
CHEV_D  = "M18,38 L50,70 L82,38"
BOOK    = "M20,22 L46,28 L46,80 L20,74 Z M80,22 L54,28 L54,80 L80,74 Z"
PAGE    = "M28,16 L60,16 L74,32 L74,84 L28,84 Z M60,16 L60,32 L74,32"

ICONS = {
 "KPPUIChrome": {
  "BackArrow":     stroke("M20,50 L80,50 M42,28 L20,50 L42,72"),
  "DownArrow":     stroke("M50,20 L50,80 M28,58 L50,80 L72,58"),
  "UpEnabled":     stroke(CHEV_U),
  "UpDisabled":    stroke(CHEV_U, 4),
  "DownEnabled":   stroke(CHEV_D),
  "DownDisabled":  stroke(CHEV_D, 4),
  "Aa":            fill("M12,74 L26,74 L30,62 L48,62 L52,74 L66,74 L46,24 L32,24 Z M34,52 L39,37 L44,52 Z")
                   + "\n" + fill("M72,74 L86,74 L86,44 C86,34 72,32 66,38 L70,45 C74,41 80,42 80,47 L80,49 C68,49 62,54 62,62 C62,70 70,77 80,71 L80,74 Z M74,66 C70,68 68,66 68,62 C68,58 74,57 80,57 L80,63 Z"),
  "Book":          stroke(BOOK),
  "AboutThisBook": stroke(BOOK) + "\n" + circle(50, 50, 3),
  "CloseBook":     stroke(BOOK) + "\n" + stroke("M38,38 L62,62 M62,38 L38,62", 6),
  "ExitBook":      stroke(BOOK) + "\n" + stroke("M50,30 L50,54 M40,44 L50,54 L60,44", 6),
  "Bookmarks":     stroke("M28,16 L72,16 L72,86 L50,68 L28,86 Z"),
  "Bookmarked":    fill("M28,16 L72,16 L72,86 L50,68 L28,86 Z"),
  "Annotations":   stroke("M18,24 L82,24 M18,44 L82,44 M18,64 L58,64") + "\n" + fill("M66,58 L84,76 L64,82 Z"),
  "Highlights":    fill("M16,62 L52,26 L68,42 L32,78 L16,78 Z") + "\n" + stroke("M60,34 L76,18 L86,28 L70,44", 7),
  "Clip":          stroke("M70,32 L38,64 C30,72 42,84 50,76 L82,44 C94,32 74,12 62,24 L30,56"),
  "Edit":          stroke("M22,78 L22,62 L66,18 L82,34 L38,78 Z") + "\n" + stroke("M58,26 L74,42", 6),
  "Export":        stroke("M50,72 L50,18 M32,36 L50,18 L68,36") + "\n" + stroke("M20,60 L20,84 L80,84 L80,60"),
  "Share":         circle(26, 50, 11) + "\n" + circle(74, 28, 11) + "\n" + circle(74, 72, 11)
                   + "\n" + stroke("M36,45 L64,32 M36,55 L64,68", 6),
  "Move":          stroke("M50,14 L50,86 M14,50 L86,50")
                   + "\n" + stroke("M40,24 L50,14 L60,24 M40,76 L50,86 L60,76 M24,40 L14,50 L24,60 M76,40 L86,50 L76,60", 6),
  "Sort":          stroke("M18,28 L58,28 M18,50 L48,50 M18,72 L38,72")
                   + "\n" + stroke("M72,24 L72,76 M62,66 L72,76 L82,66", 7),
  "Sections":      stroke("M18,26 L82,26 M18,50 L82,50 M18,74 L82,74"),
  "TOC":           fill("M18,24 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0")
                   + "\n" + fill("M18,50 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0")
                   + "\n" + fill("M18,76 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0")
                   + "\n" + stroke("M34,24 L84,24 M34,50 L84,50 M34,76 L84,76", 7),
  "History":       circle(50, 50, 32) + "\n" + stroke("M50,28 L50,52 L68,62", 7),
  "GoTo":          circle(50, 50, 32) + "\n" + stroke("M38,50 L64,50 M54,40 L64,50 L54,60", 7),
  "Trash":         stroke("M24,30 L76,30 M40,30 L40,20 L60,20 L60,30")
                   + "\n" + stroke("M30,30 L34,84 L66,84 L70,30")
                   + "\n" + stroke("M44,42 L44,72 M56,42 L56,72", 6),
  "FolderIcon":    stroke("M16,26 L42,26 L50,36 L84,36 L84,80 L16,80 Z"),
  "AddCollection": stroke("M16,26 L42,26 L50,36 L84,36 L84,80 L16,80 Z")
                   + "\n" + stroke("M50,48 L50,70 M39,59 L61,59", 7),
  "AddRemove":     stroke("M18,50 L46,50") + "\n" + stroke("M68,36 L68,64 M54,50 L82,50"),
  "Downloaded":    circle(50, 50, 32) + "\n" + stroke("M36,50 L46,62 L66,38", 7),
  "Error":         circle(50, 50, 32) + "\n" + stroke("M50,28 L50,56", 8) + "\n" + fill("M50,72 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0"),
  "Legal":         stroke(PAGE) + "\n" + stroke("M38,48 L64,48 M38,62 L64,62", 6),
  "NotebookIcon":  stroke("M28,16 L80,16 L80,84 L28,84 Z M28,32 L20,32 M28,50 L20,50 M28,68 L20,68"),
  "QuickNotebookIcon": stroke("M28,16 L80,16 L80,84 L28,84 Z M28,32 L20,32 M28,50 L20,50 M28,68 L20,68")
                   + "\n" + fill("M58,30 L48,54 L56,54 L50,72 L68,46 L58,46 Z"),
  "Accessibility": circle(50, 20, 8, 7) + "\n" + stroke("M22,38 L78,38 M50,38 L50,60 M50,60 L36,86 M50,60 L64,86"),
  "DarkMode":      fill("M62,14 A38,38 0 1 0 86,62 A30,30 0 0 1 62,14 Z"),
  "DisableTouchscreen": stroke("M38,30 L38,60 M50,22 L50,58 M62,32 L62,58")
                   + "\n" + stroke("M26,52 L26,66 C26,82 40,88 54,88 L64,88 C76,88 78,74 78,62 L78,44", 7)
                   + "\n" + stroke("M16,16 L84,84", 9),
  "DoubleTapGesture": circle(50, 44, 20) + "\n" + fill("M50,44 m-6,0 a6,6 0 1,0 12,0 a6,6 0 1,0 -12,0")
                   + "\n" + stroke("M28,76 L72,76", 7),
  "VocabBuilder":  stroke(PAGE) + "\n" + stroke("M38,46 L64,46 M38,60 L54,60", 6),
  "XRay":          circle(50, 50, 30) + "\n" + stroke("M32,32 L68,68 M68,32 L32,68", 7),
  "Awards":        circle(50, 38, 22) + "\n" + stroke("M36,58 L30,88 L50,78 L70,88 L64,58"),
  "ScribeAI":      stroke("M22,78 L22,62 L66,18 L82,34 L38,78 Z")
                   + "\n" + fill("M74,60 L78,70 L88,74 L78,78 L74,88 L70,78 L60,74 L70,70 Z"),
  "KidsExit":      stroke("M56,20 L24,20 L24,80 L56,80") + "\n" + stroke("M48,50 L84,50 M70,36 L84,50 L70,64"),
  "ContextMenuIconPlaceHolder": circle(50, 50, 28, 6),
 },
 "KPPUIQuickSettings": {
  "Bluetooth-On":     fill("M46,10 L74,34 L54,50 L74,66 L46,90 Z M54,28 L54,42 L64,35 Z M54,58 L54,72 L64,65 Z")
                      + "\n" + stroke("M46,50 L26,34 M46,50 L26,66", 8),
  "Bluetooth-Off":    stroke("M46,10 L74,34 L54,50 L74,66 L46,90 L46,10", 6)
                      + "\n" + stroke("M46,50 L26,34 M46,50 L26,66", 6),
  "OrientationLock-on":  rect(30, 14, 40, 72, 8) + "\n" + fill("M50,74 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0")
                      + "\n" + stroke("M42,34 L42,28 A8,8 0 0 1 58,28 L58,34 M38,34 L62,34 L62,52 L38,52 Z", 6),
  "OrientationLock-off": rect(30, 14, 40, 72, 8, 6) + "\n" + fill("M50,74 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0")
                      + "\n" + stroke("M18,18 L82,82", 8),
  "Right-Chevron":    stroke(CHEV_R),
  "Sync-On":          (stroke("M22,50 A28,28 0 0 1 72,32") + "\n" + fill("M76,18 L78,42 L54,36 Z")
                       + "\n" + stroke("M78,50 A28,28 0 0 1 28,68") + "\n" + fill("M24,82 L22,58 L46,64 Z")),
  "Sync-Off":         (stroke("M22,50 A28,28 0 0 1 72,32", 6) + "\n" + stroke("M78,50 A28,28 0 0 1 28,68", 6)
                       + "\n" + stroke("M18,18 L82,82", 8)),
  "Browser":          circle(50, 50, 32) + "\n" + stroke("M18,50 L82,50") + "\n"
                      + stroke("M50,18 C34,34 34,66 50,82 C66,66 66,34 50,18"),
 },
 "KPPUIBrowser": {
  "RightChevron": stroke(CHEV_R),
  "UpArrow":      stroke("M50,80 L50,20 M28,42 L50,20 L72,42"),
  "DownArrow":    stroke("M50,20 L50,80 M28,58 L50,80 L72,58"),
 },
 "KPPUIComponents": {
  "Checkmark":    stroke("M20,52 L40,72 L80,28"),
  "Close":        stroke("M22,22 L78,78 M78,22 L22,78"),
  "LeftChevron":  stroke(CHEV_L),
  "RightChevron": stroke(CHEV_R),
  "UpArrow":      stroke("M50,80 L50,20 M28,42 L50,20 L72,42"),
  "DownArrow":    stroke("M50,20 L50,80 M28,58 L50,80 L72,58"),
 },
 "KPPHome": {
  "Chevron-Up":              stroke(CHEV_U),
  "Chevron-right":           stroke(CHEV_R),
  "close":                   stroke("M22,22 L78,78 M78,22 L22,78"),
  "double-chevron-left":     stroke("M56,22 L30,50 L56,78 M80,22 L54,50 L80,78", 7),
  "double-chevron-left-active":  fill("M58,18 L66,26 L42,50 L66,74 L58,82 L26,50 Z")
                              + "\n" + fill("M82,18 L90,26 L66,50 L90,74 L82,82 L50,50 Z"),
  "double-chevron-right":    stroke("M44,22 L70,50 L44,78 M20,22 L46,50 L20,78", 7),
  "double-chevron-right-active": fill("M42,18 L34,26 L58,50 L34,74 L42,82 L74,50 Z")
                              + "\n" + fill("M18,18 L10,26 L34,50 L10,74 L18,82 L50,50 Z"),
 },
 "KPPLibrary": {
  "search":            circle(44, 44, 24) + "\n" + stroke("M61,61 L84,84"),
  "sort":              stroke("M18,28 L58,28 M18,50 L48,50 M18,72 L38,72")
                       + "\n" + stroke("M72,24 L72,76 M62,66 L72,76 L82,66", 7),
  "adjust":            stroke("M22,30 L78,30 M22,50 L78,50 M22,70 L78,70", 7)
                       + "\n" + fill("M38,30 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")
                       + "\n" + fill("M64,50 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")
                       + "\n" + fill("M44,70 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0"),
  "collections":       stroke("M16,26 L42,26 L50,36 L84,36 L84,80 L16,80 Z"),
  "deep_stack":        stroke("M20,64 L50,78 L80,64 M20,50 L50,64 L80,50 M20,36 L50,50 L80,36 M50,22 L80,36"),
  "book_icon":         stroke(BOOK),
  "doc_icon":          stroke(PAGE),
  "pdf_icon":          stroke(PAGE) + "\n" + stroke("M38,58 L38,74 M38,58 L48,58 L48,66 L38,66", 5),
  "dictionary_icon":   stroke(BOOK) + "\n" + stroke("M50,36 L50,66", 6),
  "info":              circle(50, 50, 32) + "\n" + stroke("M50,46 L50,70", 8)
                       + "\n" + fill("M50,32 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0"),
  "star":              fill("M50,12 L61,38 L89,40 L67,58 L74,86 L50,70 L26,86 L33,58 L11,40 L39,38 Z"),
  "ellipsis_vertical": (fill("M50,22 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")
                        + "\n" + fill("M50,50 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")
                        + "\n" + fill("M50,78 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")),
  "option_close":      circle(50, 50, 30) + "\n" + stroke("M38,38 L62,62 M62,38 L38,62", 7),
  "option_close_invert": fill("M50,50 m-32,0 a32,32 0 1,0 64,0 a32,32 0 1,0 -64,0")
                       + '\n        <path d="M38,38 L62,62 M62,38 L38,62" fill="none" stroke="#FFFFFF" stroke-width="7" stroke-linecap="round"/>',
  "cancel_download_badge": circle(50, 50, 30) + "\n" + stroke("M38,38 L62,62 M62,38 L38,62", 7),
  "download_status_badge": circle(50, 50, 30) + "\n" + stroke("M50,32 L50,62 M38,50 L50,62 L62,50", 7),
  "series_grouping":   stroke("M22,30 L22,82 M36,24 L36,82") + "\n" + rect(50, 18, 30, 64, 4),
  "series_grouping_dark": fill("M18,30 L26,30 L26,82 L18,82 Z M32,24 L40,24 L40,82 L32,82 Z M50,18 L80,18 L80,82 L50,82 Z"),
 },
}

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "svgout"
    n = 0
    for group, icons in ICONS.items():
        d = os.path.join(out, group); os.makedirs(d, exist_ok=True)
        for name, body in icons.items():
            open(os.path.join(d, name + ".svg"), "w").write(
                HEAD.format(title="KindleHub / %s" % name, body=body))
            n += 1
        print("  %-22s %d icons" % (group, len(icons)))
    print("  %d more SVGs written" % n)

if __name__ == "__main__":
    main()
