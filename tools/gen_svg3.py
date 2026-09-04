"""Third batch: the big untouched groups (KUIComponents, KPPUISetting, KPPUIAaMenu).

Deliberately SKIPPED: the colour swatches (aqua/black/blue/gray/green/none/
orange/pink/purple/red/yellow and their _selected pairs) and lasso_color /
lasso_recolor. Those encode a COLOUR the user is choosing, not an idea -- redraw
them as black glyphs and the highlighter picker stops being usable.

Many names come in Normal/Selected pairs. The convention here: Selected = the
same glyph inside a filled pill, which reads clearly at e-ink sizes without
needing colour.
"""
import os, sys
from gen_svg import HEAD, stroke, fill, circle

def rect(x,y,w,h,r=0,sw=8):
    return ('        <rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" '
            'stroke="#000000" stroke-width="%s" stroke-linejoin="round"/>'%(x,y,w,h,r,sw))
def frect(x,y,w,h,r=0):
    return '        <rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="#000000"/>'%(x,y,w,h,r)
def sel(body):
    """Selected state: glyph knocked out of a filled rounded square."""
    return (frect(6,6,88,88,16) + "\n" +
            body.replace('stroke="#000000"','stroke="#FFFFFF"').replace('fill="#000000"','fill="#FFFFFF"'))

def lines(ys, w=8, x0=18, x1=82):
    return stroke(" ".join("M%s,%s L%s,%s"%(x0,y,x1,y) for y in ys), w)

CHEV_L="M62,18 L30,50 L62,82"; CHEV_R="M38,18 L70,50 L38,82"
CHEV_U="M18,62 L50,30 L82,62"; CHEV_D="M18,38 L50,70 L82,38"

G = {}

# ---------------- KUIComponents ----------------
K = {
 "checkmark": stroke("M20,52 L40,72 L80,28"),
 "close": stroke("M22,22 L78,78 M78,22 L22,78"),
 "chevron-down": stroke(CHEV_D), "chevron-up": stroke(CHEV_U),
 "chevron-double-left":  stroke("M56,22 L30,50 L56,78 M80,22 L54,50 L80,78",7),
 "chevron-double-right": stroke("M44,22 L70,50 L44,78 M20,22 L46,50 L20,78",7),
 "expand-down": stroke("M50,20 L50,74 M30,54 L50,74 L70,54") + "\n" + stroke("M20,86 L80,86",6),
 "copy": rect(14,14,52,52,6) + "\n" + rect(34,34,52,52,6),
 "cut": (circle(28,76,12,7) + "\n" + circle(72,76,12,7) + "\n" +
         stroke("M34,66 L70,16 M66,66 L30,16",7)),
 "delete": (stroke("M24,30 L76,30 M40,30 L40,20 L60,20 L60,30") + "\n" +
            stroke("M30,30 L34,84 L66,84 L70,30") + "\n" + stroke("M44,42 L44,72 M56,42 L56,72",6)),
 "edit-text": stroke("M22,78 L22,62 L66,18 L82,34 L38,78 Z") + "\n" + stroke("M58,26 L74,42",6),
 "more": (fill("M22,50 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0") + "\n" +
          fill("M50,50 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0") + "\n" +
          fill("M78,50 m-7,0 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0")),
 "move": (stroke("M50,14 L50,86 M14,50 L86,50") + "\n" +
          stroke("M40,24 L50,14 L60,24 M40,76 L50,86 L60,76 M24,40 L14,50 L24,60 M76,40 L86,50 L76,60",6)),
 "line-basic":        stroke("M16,50 L84,50"),
 "line-arrow":        stroke("M16,50 L78,50 M60,34 L78,50 L60,66"),
 "line-solid-arrow":  stroke("M16,50 L66,50") + "\n" + fill("M62,34 L88,50 L62,66 Z"),
 "double-line-arrow": stroke("M22,50 L78,50 M38,34 L22,50 L38,66 M62,34 L78,50 L62,66"),
 "double-solid-arrow":stroke("M30,50 L70,50") + "\n" + fill("M34,34 L8,50 L34,66 Z") + "\n" + fill("M66,34 L92,50 L66,66 Z"),
 "side-panel-docked-left":   rect(12,20,76,60,4) + "\n" + frect(12,20,26,60,4),
 "side-panel-docked-right":  rect(12,20,76,60,4) + "\n" + frect(62,20,26,60,4),
 "side-panel-overlay-left":  rect(12,20,76,60,4) + "\n" + rect(20,28,26,44,3,6),
 "side-panel-overlay-right": rect(12,20,76,60,4) + "\n" + rect(54,28,26,44,3,6),
 "side-panel-scroll-up":   rect(12,20,76,60,4) + "\n" + stroke("M36,58 L50,42 L64,58",7),
 "side-panel-scroll-down": rect(12,20,76,60,4) + "\n" + stroke("M36,42 L50,58 L64,42",7),
 "side-panel-trigger-left":  stroke("M64,20 L36,50 L64,80",8) + "\n" + stroke("M84,16 L84,84",6),
 "side-panel-trigger-right": stroke("M36,20 L64,50 L36,80",8) + "\n" + stroke("M16,16 L16,84",6),
}
for i,w in enumerate([3,5,8,12,17], start=1):
    K["thickness-level-%d"%i] = stroke("M16,50 L84,50", w)
G["KUIComponents"] = K

# ---------------- KPPUISetting ----------------
S = {
 "Accessibility": circle(50,20,8,7) + "\n" + stroke("M22,38 L78,38 M50,38 L50,60 M50,60 L36,86 M50,60 L64,86"),
 "AlertIcon": stroke("M50,14 L88,82 L12,82 Z") + "\n" + stroke("M50,40 L50,60",7) + "\n" + fill("M50,72 m-4,0 a4,4 0 1,0 8,0 a4,4 0 1,0 -8,0"),
 "InfoIcon": circle(50,50,32) + "\n" + stroke("M50,46 L50,70",8) + "\n" + fill("M50,32 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0"),
 "GearIcon": circle(50,50,12) + "\n" + stroke("M50,14 L50,26 M50,74 L50,86 M14,50 L26,50 M74,50 L86,50 M25,25 L33,33 M67,67 L75,75 M75,25 L67,33 M33,67 L25,75"),
 "Device": rect(28,12,44,76,8) + "\n" + fill("M50,76 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0"),
 "Display": rect(12,22,76,50,5) + "\n" + stroke("M36,84 L64,84 M50,72 L50,84",7),
 "Download": stroke("M50,16 L50,64 M30,46 L50,66 L70,46") + "\n" + stroke("M18,80 L82,80"),
 "DarkDownloadError": stroke("M50,16 L50,56 M32,40 L50,58 L68,40",7) + "\n" + stroke("M18,76 L82,76",7) + "\n" + stroke("M64,64 L86,86 M86,64 L64,86",7),
 "Darkmode": fill("M62,14 A38,38 0 1 0 86,62 A30,30 0 0 1 62,14 Z"),
 "Lightmode": circle(50,50,18) + "\n" + stroke("M50,12 L50,24 M50,76 L50,88 M12,50 L24,50 M76,50 L88,50 M23,23 L32,32 M68,68 L77,77 M77,23 L68,32 M32,68 L23,77",7),
 "Help": circle(50,50,32) + "\n" + stroke("M38,40 C38,26 62,26 62,40 C62,50 50,50 50,60",7) + "\n" + fill("M50,74 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0"),
 "House": stroke("M14,48 L50,16 L86,48") + "\n" + stroke("M26,44 L26,84 L74,84 L74,44") + "\n" + stroke("M42,84 L42,60 L58,60 L58,84",7),
 "Library": stroke("M20,20 L20,80 M36,20 L36,80 M52,22 L52,80") + "\n" + stroke("M64,26 L80,74"),
 "Legal": stroke("M28,16 L60,16 L74,32 L74,84 L28,84 Z M60,16 L60,32 L74,32") + "\n" + stroke("M38,48 L64,48 M38,62 L64,62",6),
 "ManageApps": (rect(16,16,30,30,5) + "\n" + rect(54,16,30,30,5) + "\n" + rect(16,54,30,30,5) + "\n" + rect(54,54,30,30,5)),
 "Wifi": (stroke("M14,40 C34,22 66,22 86,40") + "\n" + stroke("M26,53 C40,41 60,41 74,53") + "\n" +
          stroke("M38,66 C46,60 54,60 62,66") + "\n" + fill("M50,80 m-6,0 a6,6 0 1,0 12,0 a6,6 0 1,0 -12,0")),
 "YourAccount": circle(50,34,18) + "\n" + stroke("M18,86 C18,62 82,62 82,86"),
 "PenMenu": stroke("M22,78 L22,62 L66,18 L82,34 L38,78 Z") + "\n" + stroke("M58,26 L74,42",6),
 "Pageturn_forward_back": stroke("M20,50 L44,50 M34,38 L44,50 L34,62",7) + "\n" + stroke("M80,50 L56,50 M66,38 L56,50 L66,62",7) + "\n" + stroke("M50,18 L50,82",5),
 "Pageturn_back_forward": stroke("M44,50 L20,50 M30,38 L20,50 L30,62",7) + "\n" + stroke("M56,50 L80,50 M70,38 L80,50 L70,62",7) + "\n" + stroke("M50,18 L50,82",5),
 "Standard": lines([32,44,56,68],7),
 "Large":    lines([30,50,70],10),
}
S["StandardNew"] = S["Standard"] + "\n" + fill("M80,22 m-10,0 a10,10 0 1,0 20,0 a10,10 0 1,0 -20,0")
S["LargeNew"]    = S["Large"]    + "\n" + fill("M80,22 m-10,0 a10,10 0 1,0 20,0 a10,10 0 1,0 -20,0")
G["KPPUISetting"] = S

# ---------------- KPPUIAaMenu ----------------
A = {
 "Close": stroke("M22,22 L78,78 M78,22 L22,78"),
 "Delete": stroke("M24,30 L76,30 M40,30 L40,20 L60,20 L60,30") + "\n" + stroke("M30,30 L34,84 L66,84 L70,30"),
 "Edit": stroke("M22,78 L22,62 L66,18 L82,34 L38,78 Z") + "\n" + stroke("M58,26 L74,42",6),
 "Save": stroke("M20,20 L20,80 L80,80 L80,34 L66,20 Z") + "\n" + stroke("M34,20 L34,44 L64,44 L64,20",6) + "\n" + stroke("M34,80 L34,58 L66,58 L66,80",6),
 "Error": circle(50,50,32) + "\n" + stroke("M50,28 L50,56",8) + "\n" + fill("M50,72 m-5,0 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0"),
 "BookFormat": stroke("M20,22 L46,28 L46,80 L20,74 Z M80,22 L54,28 L54,80 L80,74 Z"),
 # alignment
 "Alignment_Justified":    lines([26,42,58,74],7),
 "Alignment_Ragged":       stroke("M18,26 L82,26 M18,42 L64,42 M18,58 L78,58 M18,74 L54,74",7),
 "Alignment_Ragged_Right": stroke("M82,26 L18,26 M82,42 L36,42 M82,58 L22,58 M82,74 L46,74",7),
 # columns
 "One_Column_Active":   rect(20,18,60,64,4),
 "Two_Column_Inactive": rect(14,18,32,64,4) + "\n" + rect(54,18,32,64,4),
}
A["Two_Column_Active"] = A["Two_Column_Inactive"]
for n,ys in (("S",[34,46,58,70]),("M",[30,46,62,78]),("L",[26,50,74])):
    A["Spacing_%s"%n]          = lines(ys,7)
    A["Vertical_Spacing_%s"%n] = stroke(" ".join("M%s,18 L%s,82"%(x,x) for x in
                                  ([34,46,58,70] if n=="S" else [30,46,62,78] if n=="M" else [30,50,70])),7)
for n,(x0,x1) in (("No",(14,86)),("Na",(30,70)),("W",(38,62))):
    A["Margins_%s"%n]          = rect(x0,18,x1-x0,64,3) + "\n" + lines([32,44,56,68],5,x0+8,x1-8)
    A["Vertical_Margins_%s"%n] = rect(18,x0,64,x1-x0,3)
A["Orientation_Vertical"]  = rect(30,14,40,72,6)
A["Orientation_Landscape"] = rect(14,30,72,40,6)
A["Vertical_Orientation_Vertical"]  = A["Orientation_Vertical"]
A["Vertical_Orientation_Landscape"] = A["Orientation_Landscape"]
A["PageColor_Normal"] = rect(16,16,68,68,6)
A["PageColor_Night"]  = frect(16,16,68,68,6)
A["PageColor_Normal_DarkMode"] = A["PageColor_Normal"]
A["PageColor_Night_DarkMode"]  = A["PageColor_Night"]
for n,ys in (("Compact",[32,42,52,62,72]),("Standard",[32,48,64]),("Large",[34,58]),
             ("LowVision",[40]),("Custom",[32,48,64]),("User",[32,48,64])):
    w = 7 if n in ("Compact","Standard","Custom","User") else 11
    body = lines(ys,w)
    if n == "Custom": body += "\n" + stroke("M70,74 L86,74 M78,66 L78,82",6)
    if n == "User":   body = circle(50,32,14,7) + "\n" + stroke("M24,80 C24,60 76,60 76,80",7)
    A["%sNormal"%n] = body
# every *_Selected pair
for k in [k for k in list(A) if not k.endswith("_Selected")]:
    base = k[:-6] if k.endswith("Normal") else k
    A[(base + "Selected") if k.endswith("Normal") else (k + "_Selected")] = sel(A[k])
G["KPPUIAaMenu"] = A

def main():
    out = sys.argv[1] if len(sys.argv)>1 else "svgout"
    src = sys.argv[2] if len(sys.argv)>2 else None
    n=0; skipped=[]
    for group, icons in G.items():
        d=os.path.join(out,group); os.makedirs(d,exist_ok=True)
        for name,body in icons.items():
            if src and not os.path.exists(os.path.join(src,group,name+".svg")):
                skipped.append(group+"/"+name); continue
            open(os.path.join(d,name+".svg"),"w").write(HEAD.format(title="KindleHub / "+name, body=body))
            n+=1
        print("  %-20s %d written"%(group,len([k for k in icons if not (src and not os.path.exists(os.path.join(src,group,k+'.svg')))])))
    print("  %d written; %d skipped (no such icon on device)"%(n,len(skipped)))
    if skipped: print("   ", ", ".join(skipped[:12]), "..." if len(skipped)>12 else "")

if __name__=="__main__": main()
