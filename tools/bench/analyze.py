#!/usr/bin/env python3
"""analyze.py — turn tools/bench/results/*.txt into the tables in docs/recon/PERF.md."""
import sys, os, glob, re

RES = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "results")

def load(fn):
    rows = []
    p = os.path.join(RES, fn)
    if not os.path.exists(p):
        return rows
    for line in open(p):
        line = line.strip()
        if not line.startswith("RESULT"):
            continue
        d = {}
        for tok in line.split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                d[k] = v
        if "FAILED" in line:
            d["failed"] = True
        rows.append(d)
    return rows

def f(d, k, default=0.0):
    try:
        return float(d.get(k, default))
    except ValueError:
        return default

def i(d, k, default=0):
    try:
        return int(float(d.get(k, default)))
    except ValueError:
        return default

def sect(t):
    print("\n" + "=" * 78)
    print(t)
    print("=" * 78)

# ---------------------------------------------------------------- E1 sweep --
sect("E1  shipping pipeline: ms/frame by triangle count x depth distribution")
rows = load("e1_sweep.txt")
tris = sorted({i(r, "tris") for r in rows})
print(f"{'tris':>7} | " + " | ".join(f"{d:>22}" for d in ("random", "ramp", "flat")))
for t in tris:
    cells = []
    for dep in ("random", "ramp", "flat"):
        m = [r for r in rows if i(r, "tris") == t and r.get("depth") == dep]
        if m and not m[0].get("failed"):
            ms = f(m[0], "ms_per_frame"); fps = f(m[0], "fps")
            cells.append(f"{ms:10.2f} ms {fps:7.1f} fps")
        else:
            cells.append(" " * 22)
    print(f"{t:>7} | " + " | ".join(cells))

# ------------------------------------------------------------ E2 ablation --
sect("E2  stage ablation, SHIPPING path (cumulative ms, then per-stage delta)")
rows = load("e2_ablation.txt")
NAMES = {0: "frame overhead", 1: "+ transform (cv/mat_apply)", 2: "+ clip_tri_near",
         3: "+ to_screen (divide)", 4: "+ clip_tri_rect", 5: "+ batch_tri push",
         6: "+ painter sort", 7: "+ put_vert", 8: "+ SDL_RenderGeometry"}
for t in sorted({i(r, "tris") for r in rows}):
    for dep in ("random", "ramp"):
        sub = {i(r, "stage"): f(r, "ms_per_frame")
               for r in rows if i(r, "tris") == t and r.get("depth") == dep and not r.get("failed")}
        if not sub:
            continue
        print(f"\n-- {t} tris, depth={dep} --")
        print(f"{'stage':<30}{'cumulative':>12}{'delta':>12}{'% of frame':>12}")
        total = sub.get(8, 0.0)
        prev = 0.0
        for s in range(9):
            if s not in sub:
                continue
            cum = sub[s]; delta = cum - prev; prev = cum
            pct = (delta / total * 100.0) if total else 0.0
            print(f"{NAMES[s]:<30}{cum:>10.2f}ms{delta:>10.2f}ms{pct:>11.1f}%")

# ---------------------------------------------------------------- E3 sort --
sect("E3  sort strategy: ms/frame (obj path, view depth key)")
rows = load("e3_sort.txt")
print(f"{'tris':>7} {'depth':>7} | {'closure':>12} {'bucket':>12} {'no sort':>12} | "
      f"{'closure cost':>13} {'bucket cost':>12} {'speedup':>9}")
for t in sorted({i(r, "tris") for r in rows}):
    for dep in ("random", "ramp", "flat"):
        g = {r.get("sort"): f(r, "ms_per_frame")
             for r in rows if i(r, "tris") == t and r.get("depth") == dep and not r.get("failed")}
        if len(g) < 3:
            continue
        c, b, n = g.get("closure", 0), g.get("bucket", 0), g.get("none", 0)
        cc, bc = c - n, b - n
        sp = (c / b) if b else 0
        print(f"{t:>7} {dep:>7} | {c:>10.2f}ms {b:>10.2f}ms {n:>10.2f}ms | "
              f"{cc:>11.2f}ms {bc:>10.2f}ms {sp:>8.2f}x")

# ------------------------------------------------------- E3 verify (order) --
sect("E3v sort correctness: adjacent inversions and worst depth violation")
for r in load("e3_verify.txt"):
    print(f"  sort={r.get('sort'):<8} key={r.get('key'):<5} "
          f"inversions={r.get('inversions'):<12} max_violation={r.get('maxviol')}")

# ---------------------------------------------------------------- E4 path --
sect("E4  vertex representation: ms/frame (bucket sort, view key, random depth)")
rows = [r for r in load("e4_path.txt") if r.get("label") == "e4"]
paths = ["obj", "flat", "flatraw", "flatsdl"]
print(f"{'tris':>7} | " + " | ".join(f"{p:>11}" for p in paths) + " |  vs obj")
for t in sorted({i(r, "tris") for r in rows}):
    g = {r.get("path"): f(r, "ms_per_frame") for r in rows if i(r, "tris") == t}
    if not g:
        continue
    cells = " | ".join(f"{g.get(p, 0):>9.2f}ms" for p in paths)
    sp = g.get("obj", 0) / g.get("flatsdl", 1) if g.get("flatsdl") else 0
    print(f"{t:>7} | {cells} |  {sp:.2f}x")

sect("E4s SHIPPING (obj+closure+ndc, ramp) vs PROPOSED (flatsdl+bucket+view, ramp)")
rows = load("e4_path.txt")
print(f"{'tris':>7} | {'shipping':>14} | {'proposed':>14} | {'speedup':>8}")
for t in sorted({i(r, "tris") for r in rows if r.get("label") in ("e4_ship", "e4_prop")}):
    s = [r for r in rows if r.get("label") == "e4_ship" and i(r, "tris") == t]
    p = [r for r in rows if r.get("label") == "e4_prop" and i(r, "tris") == t]
    if not s or not p:
        continue
    sm, pm = f(s[0], "ms_per_frame"), f(p[0], "ms_per_frame")
    print(f"{t:>7} | {sm:>10.2f}ms {'':>1} | {pm:>10.2f}ms {'':>1} | {sm/pm if pm else 0:>7.1f}x")

sect("E4a stage ablation, PROPOSED path")
rows = [r for r in load("e4_path.txt") if r.get("label") == "e4_abl"]
# NOTE: the flat paths do not implement stages 0-3 separately — they bail at the
# same point for any STAGE <= 4 — so stage 0 and stage 4 both measure
# "transform + project + cull" and stage 0 is skipped here.
PN = {4: "transform+project+cull", 5: "+ push SDL_Vertex",
      6: "+ bucketed sort", 7: "+ memcpy gather", 8: "+ SDL_RenderGeometry"}
for t in sorted({i(r, "tris") for r in rows}):
    sub = {i(r, "stage"): f(r, "ms_per_frame") for r in rows if i(r, "tris") == t and i(r, "stage") != 0}
    if not sub:
        continue
    print(f"\n-- {t} tris (proposed path) --")
    print(f"{'stage':<30}{'cumulative':>12}{'delta':>12}{'% of frame':>12}")
    total = sub.get(8, 0.0); prev = 0.0
    for s in sorted(sub):
        cum = sub[s]; delta = cum - prev; prev = cum
        pct = (delta / total * 100.0) if total else 0.0
        print(f"{PN.get(s, str(s)):<30}{cum:>10.2f}ms{delta:>10.2f}ms{pct:>11.1f}%")

# ------------------------------------------------------------- E4 checksum --
sect("E4c image identity across paths (all must match)")
for r in load("e4_checksum.txt"):
    print(f"  label={r.get('label'):<8} path={r.get('path'):<8} sort={r.get('sort'):<8} "
          f"key={r.get('key'):<5} csum={r.get('csum')}")

# ----------------------------------------------------------- E5 drawcalls --
sect("E5  draw calls (2000 tris, proposed path)")
for lbl in ("e5", "e5_inter"):
    rows = [r for r in load("e5_drawcalls.txt") if r.get("label") == lbl]
    if not rows:
        continue
    print(f"\n-- {'texture-run batching' if lbl=='e5' else 'INTERLEAVED (worst case)'} --")
    print(f"{'textures':>9} {'draw calls':>11} {'ms/frame':>10} {'fps':>8}")
    for r in sorted(rows, key=lambda r: i(r, "tex")):
        print(f"{i(r,'tex'):>9} {i(r,'calls'):>11} {f(r,'ms_per_frame'):>9.2f}ms {f(r,'fps'):>8.1f}")

# ----------------------------------------------------------------- E6 res --
sect("E6  resolution scaling, SOFTWARE renderer (proposed path)")
rows = load("e6_res.txt")
print(f"{'resolution':>11} | " + " | ".join(f"{l+' layer':>20}" for l in ("1", "2", "4")))
for res in ("320x240", "480x360", "640x480", "960x720"):
    cells = []
    for lay in (1, 2, 4):
        m = [r for r in rows if r.get("res") == res and i(r, "layers") == lay]
        cells.append(f"{f(m[0],'ms_per_frame'):8.2f}ms {f(m[0],'fps'):6.1f}fps" if m else " " * 20)
    print(f"{res:>11} | " + " | ".join(cells))

# ---------------------------------------------------------------- E7 fill --
def fill_table(fn, label_filter, title):
    sect(title)
    rows = [r for r in load(fn) if (label_filter is None or r.get("label") == label_filter)]
    if not rows:
        print("  (no data)")
        return
    print(f"{'resolution':>11} {'layers':>7} {'no draw':>11} {'with draw':>11} "
          f"{'fill cost':>11} {'per screen':>11} {'Mpix/s':>9}")
    for res in sorted({r.get("res") for r in rows}):
        w, h = (int(x) for x in res.split("x"))
        for lay in sorted({i(r, "layers") for r in rows if r.get("res") == res}):
            g = {i(r, "stage"): f(r, "ms_per_frame")
                 for r in rows if r.get("res") == res and i(r, "layers") == lay}
            if 7 not in g or 8 not in g:
                continue
            fill = g[8] - g[7]
            per = fill / lay
            mpix = (w * h / 1e6) / (per / 1000.0) if per > 0 else 0
            print(f"{res:>11} {lay:>7} {g[7]:>9.2f}ms {g[8]:>9.2f}ms "
                  f"{fill:>9.2f}ms {per:>9.2f}ms {mpix:>9.1f}")

fill_table("e7_fill.txt", None, "E7  fill-rate isolation, SOFTWARE renderer")

# ------------------------------------------------------------- E8 display --
rows = load("e8_display.txt")
if rows:
    sect("E8  REAL DISPLAY, accelerated OpenGL renderer")
    print("\n-- triangle sweep (320x240 internal, 3x window) --")
    print(f"{'tris':>7} | {'proposed':>16} | {'shipping':>16} | {'speedup':>8}")
    for t in sorted({i(r, "tris") for r in rows if r.get("label") in ("e8_prop", "e8_ship")}):
        p = [r for r in rows if r.get("label") == "e8_prop" and i(r, "tris") == t]
        s = [r for r in rows if r.get("label") == "e8_ship" and i(r, "tris") == t]
        pm = f(p[0], "ms_per_frame") if p and not p[0].get("failed") else 0
        pf = f(p[0], "fps") if p and not p[0].get("failed") else 0
        sm = f(s[0], "ms_per_frame") if s and not s[0].get("failed") else 0
        sf = f(s[0], "fps") if s and not s[0].get("failed") else 0
        print(f"{t:>7} | {pm:>8.2f}ms {pf:>6.1f}f | {sm:>8.2f}ms {sf:>6.1f}f | "
              f"{(sm/pm if pm else 0):>7.1f}x")

    print("\n-- resolution (2000 tris x layers) --")
    rr = [r for r in rows if r.get("label") == "e8_res"]
    print(f"{'resolution':>11} | " + " | ".join(f"{l+' layer':>20}" for l in ("1", "2", "4")))
    for res in ("320x240", "480x360", "640x480", "960x720"):
        cells = []
        for lay in (1, 2, 4):
            m = [r for r in rr if r.get("res") == res and i(r, "layers") == lay]
            cells.append(f"{f(m[0],'ms_per_frame'):8.2f}ms {f(m[0],'fps'):6.1f}fps" if m else " " * 20)
        print(f"{res:>11} | " + " | ".join(cells))

    fill_table("e8_display.txt", "e8_fill", "E8f fill-rate isolation, ACCELERATED renderer")

    print("\n-- draw calls, accelerated --")
    for r in sorted([r for r in rows if r.get("label") == "e8_calls"], key=lambda r: i(r, "tex")):
        print(f"  textures={i(r,'tex'):>4} calls={i(r,'calls'):>5} "
              f"ms={f(r,'ms_per_frame'):7.2f} fps={f(r,'fps'):6.1f}")

# ---------------------------------------------------------------- budget ---
sect("BUDGET: triangles affordable at 60 fps (16.67 ms) and 30 fps (33.3 ms)")
def budget(fn, label, path_filter=None, extra=None):
    rows = [r for r in load(fn) if (label is None or r.get("label") == label)]
    if path_filter:
        rows = [r for r in rows if r.get("path") == path_filter]
    if extra:
        rows = [r for r in rows if all(r.get(k) == v for k, v in extra.items())]
    pts = sorted(((i(r, "tris"), f(r, "ms_per_frame")) for r in rows if not r.get("failed")))
    pts = [(t, m) for t, m in pts if m > 0]
    if len(pts) < 2:
        return None
    # linear fit ms = a + b*tris
    n = len(pts)
    sx = sum(t for t, _ in pts); sy = sum(m for _, m in pts)
    sxx = sum(t * t for t, _ in pts); sxy = sum(t * m for t, m in pts)
    den = n * sxx - sx * sx
    if den == 0:
        return None
    b = (n * sxy - sx * sy) / den
    a = (sy - b * sx) / n
    return a, b

for name, fn, lbl, pf in (
    ("shipping  (obj+closure+ndc, random depth)", "e1_sweep.txt", "e1", None),
    ("proposed  (flatsdl+bucket+view)", "e4_path.txt", "e4", "flatsdl"),
):
    r = budget(fn, lbl, pf, {"depth": "random"} if lbl == "e1" else None)
    if not r:
        continue
    a, b = r
    print(f"\n{name}")
    print(f"  ms/frame ~= {a:.3f} + {b*1000:.4f} ms per 1000 tris  "
          f"({1000/(b*1000)*1:.0f} tris/ms marginal)")
    for target, budget_ms in (("60 fps", 16.67), ("30 fps", 33.3)):
        n = (budget_ms - a) / b if b > 0 else 0
        print(f"  {target}: {n:>8.0f} triangles/frame  ({n*(1000/budget_ms)/1e6:.2f} M tri/s)")
