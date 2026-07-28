# MEASURED FRAME BUDGET — after Wave 1

Every number here was measured by the orchestrator on the shipping toolchain
(**Hemlock v2.9.1**, `hemlockc -O1`, headless, 320×240), not taken from a spec.
Supersedes the projected figures in `ARCHITECTURE.md` §8 where they disagree.

> ### ⚠ HOW TO TIME ANYTHING ON THIS MACHINE — READ BEFORE WRITING A PERF ASSERTION
>
> This box **permanently** shares ~17 of its 24 cores with a `llama-server`
> (~1700 % CPU). **That is a fixed constraint — do not wait for a quiet machine,
> and never gate a build on one.** Measure so that contention does not matter.
>
> **The required recipe** (both parts — either alone is insufficient):
> 1. **CPU time, not wall time.** Use `__clock()`. It excludes intervals when the
>    process is descheduled.
> 2. **Minimum of N batches, not the mean.** Preemption can only make a sample
>    *slower*, so the mean drifts with load while the minimum stays near true cost.
>    `TRIALS = 7` works well.
>
> Measured on one byte-identical binary, `probe_batch`'s bucket sort @2500:
> ```
> mean  + wall, load  2.01 : 0.403 ms      <- what an idle box reports
> mean  + wall, load 24.85 : 0.653 ms      +62 %   naive timing
> min-7 + wall, load 34.88 : 0.574 ms      +42 %   min alone
> min-7 + CPU , load 32.99 : 0.521 ms      +29 %   both  <- as good as it gets
> ```
>
> **There is a floor of ~30 % that no methodology removes**, because CPU time does
> not exclude *cache and memory-bandwidth* contention from 17 busy cores. Accept it.
>
> **Therefore: set thresholds to catch regressions, not to certify a quiet
> machine.** `probe_batch`'s sort bound is **1.0 ms**, not the 0.5 ms an idle
> measurement suggests. It still catches everything that matters — the O(n²) sort
> this replaced measured **107–143 ms** on the same input, and a comparison-closure
> sort costs 0.535 ms. A 2× margin loses no real signal and eliminates false
> failures that would otherwise train everyone to ignore red probes.
>
> **Keep the ratio assertions tight.** The load-bearing check is not "0.4 ms" but
> **"cost varies < 40 % across random/ramp/flat"** — that is what proves the sort is
> input-order independent. Contention inflates all three distributions roughly
> equally, so the *ratio* stays honest even when absolute numbers do not. A real
> input-order cliff shows up as thousands of percent, not tens. Measured under full
> load: **7.5 % spread, PASS 60/60**.

## Verdict: **the 2500-triangle budget holds.** Comfortably, in the shipping configuration.

| Stage | Measured @2500 tris | Source |
|---|---|---|
| emit + pack (fog + sun) | **3.57 ms** | `probe_emit` |
| clip accept path | **0.47 ms** (188.6 ns/tri) | `probe_clip` |
| bucket sort | **0.40 ms** | `probe_batch` |
| flush (arena) → `SDL_RenderGeometry` | **0.85 ms** (interp. 2000→3500) | `probe_batch` |
| **TOTAL** | **≈ 5.3 ms** | vs an **11.0 ms** render budget |

**≈ 5.7 ms of headroom, 52 % of the render slice unused.** The frame target is safe.

### Correctness is not in question
- Framebuffer checksum **identical** to the reference object-path implementation
  (`2068028780` both) — the fast kernel is not cutting corners.
- **Zero allocations**: RSS bit-flat at 4032 pages over 10 000 frames.
- Backface cull removes **62.9 %** of a closed mesh.
- Bucket sort: 0.403 / 0.376 / 0.377 ms across random / ramp / flat — **7.3 % spread**,
  i.e. genuinely input-order independent. 32 000 triangles sort in 3.6 ms with a
  worst ordering violation of 0.225 cm.
- Arena flush vs rewind-in-place: **identical checksums**, arena faster at 2000
  (0.709 vs 0.767 ms) and 3500 (1.076 vs 1.252 ms), marginally slower at 500
  (0.284 vs 0.261). Adopting it was justified by measurement, as required.

---

## The two acceptance criteria that failed, and what to do about them

### 1. `emit + pack ≤ 3.0 ms at 2500 triangles` → **measured 3.57 ms**. Accept the miss; raise the target to 3.8 ms.
Unfogged is 2.47 ms and passes. The 1.10 ms delta is the per-vertex fog work on
91 % of vertices — a deliberately pessimistic case (D7 restricts alpha to the far
band precisely so most pixels stay on the opaque path).

**It does not threaten the frame.** Total is 5.3 ms against 11.0 ms. The 3.0 ms
figure was a projection, not a requirement derived from the frame budget.
**Action: restate the criterion as ≤ 3.8 ms and move on.** Do not spend a wave
optimizing a stage that has 5.7 ms of slack behind it.

### 2. `clip accept path < 40 ns/triangle` → **measured 188.6 ns**. The target is impossible as specified. Restate it.
The accept path is specified as *two predicate calls*. Measured cost of two calls
with **empty bodies**:

```
empty 6-arg call       :  59.25 ns
empty 10-arg call      : 103.50 ns
BOTH (the accept path) : 131.50 ns   <-- floor before any body runs
loop overhead only     :  10.75 ns
target was             :  40.00 ns
```

**131.5 ns of an unavoidable calling-convention floor against a 40 ns target.**
No implementation of the bodies can meet it. The predicate logic itself is only
~57 ns, which is fine.

> ### ⚑ NEW PERF RULE — Hemlock calls cost ~10 ns per argument
> 6 args → 59 ns, 10 args → 103 ns. **Argument count, not body complexity,
> dominates small hot functions.** A 10-argument predicate spends more time
> marshalling than computing. Prefer passing an index into a buffer the callee
> already has, or inline the body outright. This belongs in `CLAUDE.md` §4
> alongside A1.

**Action:** restate as **"accept path ≤ 200 ns/triangle, and ≥ 3× faster than the
legacy path"** — both satisfied (188.6 ns; legacy is 738.5 ns/tri and allocates
two arrays per call, so this is a **3.9× improvement** that also removes the
allocation). If clip ever needs to be faster, the fix is to *inline the
predicates into the emit kernel*, not to micro-optimize the bodies.

---

## The one real risk: dynamic point lights

| Lighting configuration | emit + pack | Frame total | Verdict |
|---|---|---|---|
| Fog + sun (shipping) | 3.57 ms | ≈ 5.3 ms | ✅ 52 % headroom |
| Full G16 + **4 point lights** | **8.47 ms** | **≈ 10.2 ms** | ⚠️ 93 % of the render budget |

Four dynamic point lights cost **4.9 ms** — more than the entire rest of the
frame. It technically fits, with ~0.8 ms spare, but that leaves nothing for
overdraw, HUD, post-FX or a bad frame.

### ✅ RATIFIED BY THE PROJECT OWNER — **dynamic point lights are capped at 2.**

`MAX_DYNAMIC_LIGHTS = 2`. Everything else is **baked into vertex colour at
mesh-build time** via `mesh.hml`'s `mesh_bake_light`, so static lanterns, windows,
fires and signage cost **zero per frame**.

Measured consequence — this is what buys the frame back:

| Configuration | emit + pack | Frame total | of 11 ms |
|---|---|---|---|
| Fog + sun only | 3.57 ms | ≈ 5.3 ms | 48 % |
| **+ 2 dynamic lights (shipping cap)** | **≈ 6.0 ms** | **≈ 7.7 ms** | **70 %** |
| + 4 dynamic lights (rejected) | 8.47 ms | ≈ 10.2 ms | 93 % |

Reserve the two dynamic slots for what genuinely must move: **muzzle flash** and
**explosions/fire**. Rarely more than two at once, and when there are, the
nearest two win — priority by `distance² / intensity`, evaluated per frame.

**Implementation notes for whoever owns `shade.hml` and the light manager:**
- `RenderEnv` already reserves 4 light slots. Keep the layout; just never fill
  more than 2. Do not shrink the array — a future budget may afford 3, and
  changing the flat-array layout is a breaking change across `emit.hml`.
- Enforce the cap in the *light manager*, not in `shade.hml`. The engine takes
  a count and must stay generic (**R1**) — a hard-coded 2 in the engine is a game
  rule leaking into a reusable renderer.
- Baked lighting is not free at *build* time. Budget it in the ≤ 400 ms boot
  allowance, behind the title card.

---

## Also fixed while verifying

`examples/probe_batch.hml` printed `array.sort(closure) reference: 1.20 / 106.9 /
143.1 ms` as a **hardcoded string**, not a measurement. Those were v2.8 numbers
copied from the spec; v2.9.1's merge sort makes them wrong by two orders of
magnitude. Removed. **Never print a constant as if it were a measurement** — it
survives long after it stops being true, and it is indistinguishable from real
output.
