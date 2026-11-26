#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds Stitchy's logo: one ribbon folded into a hexagonal "S" (top band,
right fold, bottom band) in electric blue and ice on a dark glowing tile.

Writes docs/logo/geometry.json (read by Scripts/make-icon.swift for the app
icon) and docs/logo/stitchy-{mark,icon,icon-animated}.svg. 1024 grid, y down.
"""
import json, math
from pathlib import Path

# The ribbon is one outline with a smooth bend at each joint; the creases
# split it into three pieces, and each joint's curve is split exactly where
# its crease meets it, so band and fold share one continuous edge.
V1, V2 = (770, 392), (770, 640)          # joints (top-right, bottom-right)
CROSS = (423, 500)                       # where the bands cross, on the left
TOP_L, TOP_T = (281, 405), (455, 240)    # top band: left end, top corner
BOT_L, BOT_B = (272, 598), (520, 770)    # bottom band: left end, bottom corner
FOLD_X = 529                             # inner edge of the fold

def lerp(a, b, t): return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
def unit_to(a, b, r):
    d = math.hypot(b[0] - a[0], b[1] - a[1]); return (a[0] + (b[0] - a[0]) / d * r, a[1] + (b[1] - a[1]) / d * r)
def on_line(p0, p1, x): return (x, p0[1] + (p1[1] - p0[1]) * (x - p0[0]) / (p1[0] - p0[0]))
def side(p0, p1, q): return (p1[0] - p0[0]) * (q[1] - p0[1]) - (p1[1] - p0[1]) * (q[0] - p0[0])

def split_bend(prev, v, nxt, r, crease):
    """Rounded corner at v (quadratic A–v–B), split where it crosses the crease line."""
    a, b = unit_to(v, prev, r), unit_to(v, nxt, r)
    q = lambda t: lerp(lerp(a, v, t), lerp(v, b, t), t)
    lo, hi = 0.0, 1.0
    s0 = side(*crease, q(0))
    for _ in range(60):
        mid = (lo + hi) / 2
        if (side(*crease, q(mid)) > 0) == (s0 > 0): lo = mid
        else: hi = mid
    t = (lo + hi) / 2
    x = q(t)
    return a, lerp(a, v, t), x, lerp(v, b, t), b   # first half: a→x (ctrl c1); second: x→b (ctrl c2)

def corner(prev, v, nxt, r):
    return unit_to(v, prev, r), v, unit_to(v, nxt, r)

C1 = (CROSS, V1)                          # crease under the top band
C2 = (CROSS, V2)                          # crease over the bottom band
A1, P1a, X1, P1b, B1 = split_bend(TOP_T, V1, V2, 46, C1)
A2, P2a, X2, P2b, B2 = split_bend(V1, V2, BOT_B, 46, C2)
F1, F2 = on_line(CROSS, V1, FOLD_X), on_line(CROSS, V2, FOLD_X)

def cmds_top():
    ca = corner(X1, CROSS, TOP_L, 6); cl = corner(CROSS, TOP_L, TOP_T, 62); ct = corner(TOP_L, TOP_T, V1, 46)
    return [("M", X1), ("L", ca[0]), ("Q", ca[1], ca[2]), ("L", cl[0]), ("Q", cl[1], cl[2]),
            ("L", ct[0]), ("Q", ct[1], ct[2]), ("L", A1), ("Q", P1a, X1), ("Z",)]

def cmds_fold():
    return [("M", F1), ("L", X1), ("Q", P1b, B1), ("L", A2), ("Q", P2a, X2), ("L", F2), ("Z",)]

def cmds_bottom():
    cb = corner(V2, BOT_B, BOT_L, 46); cl = corner(BOT_B, BOT_L, CROSS, 62); ca = corner(BOT_L, CROSS, X2, 6)
    return [("M", X2), ("Q", P2b, B2), ("L", cb[0]), ("Q", cb[1], cb[2]), ("L", cl[0]), ("Q", cl[1], cl[2]),
            ("L", ca[0]), ("Q", ca[1], ca[2]), ("Z",)]

PIECES = {"fold": cmds_fold(), "top": cmds_top(), "bottom": cmds_bottom()}
SHAPES = {
    "fold": {"gradient": {"from": [FOLD_X, 516], "to": [770, 516], "stops": [[0, "#0A2CD0"], [0.5, "#1D55FF"], [1, "#9ADDFF"]]}},
    "top": {"gradient": {"from": [281, 470], "to": [760, 380], "stops": [[0, "#0636FF"], [0.42, "#2F7DFF"], [1, "#A9E4FF"]]}},
    "bottom": {"gradient": {"from": [272, 600], "to": [760, 680], "stops": [[0, "#A5E3FF"], [0.5, "#3D8DFF"], [1, "#0E3FFF"]]}},
}
for k in SHAPES: SHAPES[k]["path"] = [[op] + [round(c, 2) for pt in pts for c in pt] for op, *pts in PIECES[k]]
GAP = [list(CROSS), [round(F1[0], 2), round(F1[1], 2)], [round(F2[0], 2), round(F2[1], 2)]]

def serialize(cmds, tf=lambda p: p):
    out = ""
    for op, *pts in cmds:
        out += op + " ".join(f"{tf(p)[0]:.1f},{tf(p)[1]:.1f}" for p in pts) + " "
    return out.strip()

def rounded_path(points):
    """SVG path with each corner rounded by a quadratic curve of the given radius."""
    n = len(points)
    def unit(a, b):
        dx, dy = b[0] - a[0], b[1] - a[1]; d = math.hypot(dx, dy) or 1
        return dx / d, dy / d, d
    segs = []
    for i, (x, y, r) in enumerate(points):
        px, py, _ = points[i - 1]; nx, ny, _ = points[(i + 1) % n]
        ux1, uy1, d1 = unit((x, y), (px, py)); ux2, uy2, d2 = unit((x, y), (nx, ny))
        r = min(r, d1 / 2, d2 / 2)
        a = (round(x + ux1 * r, 2), round(y + uy1 * r, 2)); b = (round(x + ux2 * r, 2), round(y + uy2 * r, 2))
        segs.append((a, (x, y), b))
    d = f"M{segs[0][2][0]},{segs[0][2][1]} "
    for a, v, b in segs[1:] + segs[:1]:
        d += f"L{a[0]},{a[1]} Q{v[0]},{v[1]} {b[0]},{b[1]} "
    return d + "Z"

root = Path(__file__).resolve().parent.parent / "docs" / "logo"
root.mkdir(parents=True, exist_ok=True)
# Where the ribbon bends: a soft shadow on the fold just under each band, and a fine light line on the crease.
CREASES = [{"a": [round(F1[0], 2), round(F1[1], 2)], "b": [round(X1[0], 2), round(X1[1], 2)], "into": [0.30, 0.95]},
           {"a": [round(F2[0], 2), round(F2[1], 2)], "b": [round(X2[0], 2), round(X2[1], 2)], "into": [0.37, -0.93]}]
(root / "geometry.json").write_text(json.dumps({"shapes": SHAPES, "order": ["fold", "top", "bottom"], "gap": GAP, "creases": CREASES}, indent=1))

def grad(name, g):
    (x1, y1), (x2, y2) = g["from"], g["to"]
    stops = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in g["stops"])
    return f'<linearGradient id="g_{name}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" gradientUnits="userSpaceOnUse">{stops}</linearGradient>'

DEFS = "\n  ".join([grad(k, v["gradient"]) for k, v in SHAPES.items()] + [
    '<linearGradient id="gTile" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#040A24"/><stop offset="0.5" stop-color="#01030C"/><stop offset="1" stop-color="#030820"/></linearGradient>',
    '<clipPath id="cTile"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>',
    '<filter id="fEdge" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="22"/></filter>',
    '<filter id="fOuter" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="26"/></filter>',
    '<filter id="fGlow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="26"/></filter>',
    *[f'<linearGradient id="ao{i}" x1="{(c["a"][0]+c["b"][0])/2}" y1="{(c["a"][1]+c["b"][1])/2}" x2="{(c["a"][0]+c["b"][0])/2 + c["into"][0]*38}" y2="{(c["a"][1]+c["b"][1])/2 + c["into"][1]*38}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#020A40" stop-opacity="0.32"/><stop offset="1" stop-color="#020A40" stop-opacity="0"/></linearGradient>' for i, c in enumerate(CREASES)],
    *[f'<linearGradient id="hl{i}" x1="{c["a"][0]}" y1="{c["a"][1]}" x2="{c["b"][0]}" y2="{c["b"][1]}" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#E6F7FF" stop-opacity="0"/><stop offset="0.55" stop-color="#E6F7FF" stop-opacity="0.45"/><stop offset="1" stop-color="#F4FCFF" stop-opacity="0.9"/></linearGradient>' for i, c in enumerate(CREASES)],
    f'<clipPath id="cFold"><path d="{serialize(PIECES["fold"])}"/></clipPath>',
    '<linearGradient id="g_back" x1="529" y1="380" x2="770" y2="650" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#0A1E9E"/><stop offset="1" stop-color="#2A5CF0"/></linearGradient>',
    '<linearGradient id="g_back2" x1="272" y1="600" x2="738" y2="700" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#2B6BEA"/><stop offset="1" stop-color="#0B26A8"/></linearGradient>',
    '<filter id="fSoft" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="0" stdDeviation="22" flood-color="#1E5BFF" flood-opacity="0.75"/></filter>',
    '<linearGradient id="gShine" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0"/><stop offset="0.5" stop-color="#E6F7FF" stop-opacity="0.55"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
])

PATHS = {k: serialize(PIECES[k]) for k in PIECES}
GAP_PATH = "M" + " L".join(f"{x},{y}" for x, y in GAP) + " Z"

TILE = """<rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="#1E4BFF" stroke-opacity="0.55" stroke-width="18" filter="url(#fOuter)"/>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#gTile)"/>
  <g clip-path="url(#cTile)"><rect x="100" y="100" width="824" height="824" rx="185" fill="none" stroke="#1F52FF" stroke-opacity="0.85" stroke-width="44" filter="url(#fEdge)"/></g>
  <rect x="101.5" y="101.5" width="821" height="821" rx="183.5" fill="none" stroke="#3D74FF" stroke-opacity="0.55" stroke-width="3"/>"""

# Crease lines (shared edges): top band↔fold, fold↔bottom band.
H1 = (F1, X1)
H2 = (F2, X2)
LOOP = 8.0   # seconds

def path_cmds(points):
    """Rounded polygon as commands, so it can be transformed and re-serialised."""
    n = len(points)
    segs = []
    for i, (x, y, r) in enumerate(points):
        px, py, _ = points[i - 1]; nx, ny, _ = points[(i + 1) % n]
        d1 = math.hypot(px - x, py - y) or 1; d2 = math.hypot(nx - x, ny - y) or 1
        r = min(r, d1 / 2, d2 / 2)
        a = (x + (px - x) / d1 * r, y + (py - y) / d1 * r); b = (x + (nx - x) / d2 * r, y + (ny - y) / d2 * r)
        segs.append((a, (x, y), b))
    cmds = [("M", segs[0][2])]
    for a, v, b in segs[1:] + segs[:1]:
        cmds += [("L", a), ("Q", v, b)]
    return cmds

def rotate(p, axis, angle):
    """Rotate 3D point p about the line through axis[0], axis[1] (in the z=0 plane)."""
    (ax, ay), (bx, by) = axis
    ux, uy = bx - ax, by - ay; L = math.hypot(ux, uy); ux, uy = ux / L, uy / L
    x, y, z = p[0] - ax, p[1] - ay, p[2]
    c, s_ = math.cos(angle), math.sin(angle); dot = x * ux + y * uy
    # Rodrigues with k = (ux, uy, 0)
    cx, cy, cz = uy * z, -ux * z, ux * y - uy * x          # k × v
    return (ax + x * c + cx * s_ + ux * dot * (1 - c), ay + y * c + cy * s_ + uy * dot * (1 - c), z * c + cz * s_)

def pose(phi, psi):
    """Fold flipped by phi about H1; bottom band flipped by psi about H2, then carried by the fold."""
    out = {}
    for name, cmds in (("fold", PIECES["fold"]), ("bottom", PIECES["bottom"])):
        def tf(pt):
            q = (pt[0], pt[1], 0.0)
            if name == "bottom": q = rotate(q, H2, psi)
            return rotate(q, H1, phi)
        normal_z = 1.0
        n = (0.0, 0.0, 1.0)
        if name == "bottom": n = rotate((H2[0][0], H2[0][1], 1.0), H2, psi); n = (n[0] - H2[0][0], n[1] - H2[0][1], n[2])
        n0 = rotate((H1[0][0] + n[0], H1[0][1] + n[1], n[2]), H1, phi)
        normal_z = n0[2]
        out[name] = (serialize(cmds, lambda p_: tf(p_)[:2]), normal_z >= 0)
    return out

def ease(t): return t * t * (3 - 2 * t)   # smoothstep

# Timeline (fractions of LOOP): rest → bottom folds up → fold folds up → hold → unfold fold → unfold bottom → rest.
PHASES = [(0.00, 0.28, None), (0.28, 0.42, ("psi", 0, math.pi * 0.98)), (0.42, 0.56, ("phi", 0, math.pi * 0.98)),
          (0.56, 0.62, None), (0.62, 0.76, ("phi", math.pi * 0.98, 0)), (0.76, 0.90, ("psi", math.pi * 0.98, 0)), (0.90, 1.00, None)]
STEPS = 10

def timeline():
    frames, phi, psi = [], 0.0, 0.0
    for a, b, move in PHASES:
        if move is None:
            frames.append((a, phi, psi)); continue
        key, v0, v1 = move
        for i in range(STEPS + 1):
            t = i / STEPS; v = v0 + (v1 - v0) * ease(t)
            if key == "phi": phi = v
            else: psi = v
            frames.append((a + (b - a) * t, phi, psi))
    frames.append((1.0, 0.0, 0.0))
    # Drop duplicate times (keep the last), keep order.
    seen, out = {}, []
    for f in frames: seen[round(f[0], 4)] = f
    return [seen[k] for k in sorted(seen)]

def animated_piece(name, front, back):
    """Two copies sharing one motion: the front face, and the back face shown while turned over."""
    frames = timeline()
    poses = [pose(phi, psi)[name] for _, phi, psi in frames]
    times = ";".join(f"{t:.4f}" for t, _, _ in frames)
    dvals = ";".join(d for d, _ in poses)
    move = f'<animate attributeName="d" dur="{LOOP}s" repeatCount="indefinite" keyTimes="{times}" values="{dvals}"/>'
    def side(fill, show_front):
        vis = ";".join("1" if up == show_front else "0" for _, up in poses)
        return (f'<path d="{poses[0][0]}" fill="{fill}" opacity="{1 if show_front else 0}">{move}'
                f'<animate attributeName="opacity" dur="{LOOP}s" repeatCount="indefinite" calcMode="discrete" keyTimes="{times}" values="{vis}"/></path>')
    return side(back, False) + side(front, True)

def fold_point(pt, phi):
    q = rotate((pt[0], pt[1], 0.0), H1, phi)
    return q[0], q[1]

def mark(animated=False):
    union = "".join(f'<path d="{PATHS[k]}"/>' for k in ("fold", "top", "bottom"))
    shade = [f'<rect x="100" y="100" width="824" height="824" fill="url(#ao{i})" clip-path="url(#cFold)"/>' for i in range(len(CREASES))]
    lines = [f'<line x1="{c["a"][0]}" y1="{c["a"][1]}" x2="{c["b"][0]}" y2="{c["b"][1]}" stroke="url(#hl{i})" stroke-width="3" stroke-linecap="round"/>'
             for i, c in enumerate(CREASES)]
    if not animated:
        out = [f'<g filter="url(#fGlow)" fill="#1E5BFF" opacity="0.55">{union}</g>',
               f'<path d="{PATHS["fold"]}" fill="url(#g_fold)"/>', *shade,
               *[f'<path d="{PATHS[k]}" fill="url(#g_{k})"/>' for k in ("top", "bottom")],
               f'<path d="{GAP_PATH}" fill="#01030C"/>', *lines]
        return "\n  ".join(out)
    frames = timeline()
    times = ";".join(f"{t:.4f}" for t, _, _ in frames)
    # Crease shading rests on the still fold; it eases out while the paper moves and back when it settles.
    moving = ";".join("1" if (phi < 0.01 and psi < 0.01) else "0" for _, phi, psi in frames)
    fade = f'<animate attributeName="opacity" dur="{LOOP}s" repeatCount="indefinite" keyTimes="{times}" values="{moving}"/>'
    # The lower crease travels with the fold.
    c2 = CREASES[1]
    vals = []
    for _, phi, _ in frames:
        a, b = fold_point(c2["a"], phi), fold_point(c2["b"], phi)
        vals.append(f"M{a[0]:.1f},{a[1]:.1f} L{b[0]:.1f},{b[1]:.1f}")
    crease2 = (f'<path d="{vals[0]}" stroke="url(#hl1)" stroke-width="3" stroke-linecap="round" fill="none">'
               f'<animate attributeName="d" dur="{LOOP}s" repeatCount="indefinite" keyTimes="{times}" values="{";".join(vals)}"/>{fade}</path>')
    out = [f'<path d="{GAP_PATH}" fill="#01030C"/>',
           '<g filter="url(#fSoft)">',
           f'  <path d="{PATHS["top"]}" fill="url(#g_top)"/>',
           "  " + animated_piece("fold", "url(#g_fold)", "url(#g_back)"),
           f'  <g opacity="1">{"".join(shade)}{fade}</g>',
           "  " + animated_piece("bottom", "url(#g_bottom)", "url(#g_back2)"),
           "</g>",
           lines[0], crease2,
           f'<clipPath id="cMark">{union}</clipPath>',
           '<g clip-path="url(#cMark)"><rect class="shine" x="-420" y="0" width="230" height="1024" fill="url(#gShine)"/></g>']
    return "\n  ".join(out)

CSS = """<style>
    .shine { transform: skewX(-18deg); animation: shine 8s cubic-bezier(.45,0,.2,1) infinite; }
    @keyframes shine { 0%, 4% { transform: skewX(-18deg) translateX(0); } 24%, 100% { transform: skewX(-18deg) translateX(1600px); } }
    @media (prefers-reduced-motion: reduce) { .shine { display: none; } }
  </style>"""

def svg(body, extra=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">\n'
            f'  <title>Stitchy</title>\n  <defs>\n  {DEFS}\n  </defs>\n  {extra}\n  {body}\n</svg>\n')

for old in root.glob("stitchy-*.svg"): old.unlink()
(root / "stitchy-mark.svg").write_text(svg(mark()))
(root / "stitchy-icon.svg").write_text(svg(TILE + "\n  " + mark()))
(root / "stitchy-icon-animated.svg").write_text(svg(TILE + "\n  " + mark(animated=True), CSS))
anim = (root / "stitchy-icon-animated.svg").read_text().replace('width="1024" height="1024"', 'width="460" height="460"', 1)
(root / "preview.html").write_text('<!doctype html><meta charset="utf-8"><title>Stitchy logo</title>'
                                   '<body style="margin:0;background:#000;display:grid;place-items:center;min-height:100vh">' + anim + '</body>\n')
print("Wrote geometry.json, preview.html and", ", ".join(p.name for p in sorted(root.glob("stitchy-*.svg"))))
