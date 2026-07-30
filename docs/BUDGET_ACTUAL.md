# MEASURED FRAME BUDGET — after Wave 1

Every number here was measured by the orchestrator on the shipping toolchain
(**Hemlock v2.9.1**, `hemlockc -O1`, headless, 320×240), not taken from a spec.
Supersedes the projected figures in `ARCHITECTURE.md` §8 where they disagree.

> ## ⬛ 2026-07-29 — THE TRIANGLE CEILING WAS RE-DERIVED FROM SCRATCH.
> **Read §T below before quoting any triangle number from the rest of this file.**
> The short version, all of it measured by `tools/benchframe.hml --sweep` across
> 513–7 971 drawn triangles:
>
> * **The frame is not linear in "triangles". It is linear in *two* variables**,
>   and every single-number triangle budget ever written for this project has
>   been a projection of that plane onto one axis:
>   `frame_ms = 0.636 µs·SOURCE + 1.492 µs·DRAWN + 1.670 ms`, **R² = 0.9996**.
> * **The 16.67 ms crossing is content-dependent: 3 900–4 600 drawn triangles**,
>   not one number.
> * **`g_TRIS_STEADY` moves 2500 → 3000. `g_TRIS_CLAMP` stays at 3500.**
>   **`g_TRIS_CEILING` moves 5000 → 3500 because 5000 CRASHES** (§T.7).
> * The reason the gain is +20 % and not +200 % is that **the 9.35 ms of
>   "headroom" was never spendable**: 2.48 ms of it is a screenshot readback the
>   game does not run, and most of the rest is the reserve `ARCHITECTURE` §8
>   already allocated to net, audio, input and slack. §T.5 shows the arithmetic.
> * **A budget above 3500 is currently blocked by a crash, not by milliseconds.**

> ### ⚠ HOW TO TIME ANYTHING ON THIS MACHINE — READ BEFORE WRITING A PERF ASSERTION
>
> This box **permanently** shares ~17 of its 24 cores with a `llama-server`
> (~1700 % CPU). **That is a fixed constraint — do not wait for a quiet machine,
> and never gate a build on one.** Measure so that contention does not matter.
>
> > **CORRECTION, 2026-07-29 — "permanently" is not true, and that is worse, not
> > better.** For this entire wave `pgrep llama` was **empty** and loadavg sat at
> > **~2.1**. The load is **intermittent**, so a number's meaning now depends on
> > when it was taken, and two honest measurements of the same binary can differ
> > by 28 % with nothing to tell them apart afterwards. Re-measured directly with
> > 17 synthetic busy cores, `benchframe` default gate, two repetitions:
> > `idle 7.541 / loaded 9.549 = ×1.266` and `idle 7.682 / loaded 9.865 = ×1.284`
> > (per stage: EMIT ×1.282, RENDER ×1.281). **So the historical ~29 % is right —
> > but it must be re-derived, not inherited, and every perf report should now
> > state the loadavg it was taken at.** §T.5 applies ×1.28 explicitly.
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

> **SUPERSEDED IN PART, 2026-07-29 — see §T.** The verdict stands (the budget
> holds), but the stage table below is a *2500-triangle* snapshot taken against a
> frame that still carried the 2.48 ms screenshot readback, and its "≈ 5.7 ms of
> headroom" is not spendable on triangles: §T.5 itemises where it goes. The
> steady budget is now **3000** and the per-triangle cost is **two numbers, not
> one** (§T.2).

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

---

# §T. THE TRIANGLE CEILING, RE-DERIVED — 2026-07-29

Everything in this section was measured with `tools/benchframe.hml --sweep` on
Hemlock v2.9.1, `hemlockc -O1`, native 320×240, `read_pixels_rect` **excluded**.
Reproduce with:

```sh
hemlockc -O1 tools/benchframe.hml -o /tmp/bf
SDL_VIDEODRIVER=dummy /tmp/bf --sweep --csv --no-gate     # the ladder + every fit
SDL_VIDEODRIVER=dummy /tmp/bf --burst                     # peak/mean over whole laps
```

## T.0 Why the old number was wrong in both directions at once

`2500 steady / 3500 clamp / 5000 ceiling` carried the note *"measured at 2.88 µs
marginal per triangle"*. That figure was taken on the pre-emit-kernel pipeline,
against a frame that **included the 2.48 ms screenshot readback**, and expressed
as a single cost per *drawn* triangle. All three of those are now known to be
wrong, and they do not all push the same way:

| What was wrong | Direction |
|---|---|
| The frame carried a 2.48 ms readback the game never runs | budget was too **low** |
| Cost was expressed per DRAWN triangle only | budget was **meaningless without a content ratio** |
| `g_TRIS_CEILING = 5000` was never executed — it crashes | budget was dangerously too **high** |

## T.1 The measurement

The independent variable is `g_villagers`: extra 220-triangle NPC instances
pushed through `world_prop_add`, so they take the same LOD, bounding-sphere,
per-instance-light, fog and mandatory-contact-blob path every real prop takes.
**The independent variable is measured, never nominal** — every row reports the
mean and peak of `STAT_TRIS_DRAWN` over every frame of every trial.

Three levers reach the range: the terrain ring (fog override) for 500–800, a
5-column villager fan for 1 300–4 400, and an 11-column fan for 2 500–8 000.
Per RULE T every point is a minimum over 3 interleaved passes × 7 trials × 90
frames — interleaved so a point's minimum is spread across the whole run rather
than over seven consecutive trials one load spike can poison together.

Two measurement defects were found and fixed in the harness itself:

* **Saturation.** A 5-column fan reaches its triangle count by getting *deeper*,
  and past ~48 villagers the extra bodies are transformed in full and then die
  in the kernel: `v40 → v48 → v56 → v72` went `3483 → 3717 → 3780 → 3783` drawn
  while SOURCE went `11 382 → 13 130 → 14 731 → 17 892`. The last sixteen
  villagers added **3 161 source triangles and three drawn ones**, with
  `batch_overflow` at 0 the whole time. Those rows are real frames and useless
  as cost-per-drawn-triangle points — the denominator stopped moving. Left in
  they dragged the drawn-unit slope from ~3.8 to 4.570 µs and R² down to 0.938.
  They are now detected (`SAT`) and excluded, and the 11-column fan exists
  precisely because the 5-column one cannot be pushed past ~3 780 drawn.
* **The burst factor was measured on a quarter of the world.** `sweep_point`
  rewinds to frame 0 and times 90 frames; the camera loop is 360 frames long and
  **the worst frame of the lap is #252**, which the timed window never sees. The
  window reported `peak/mean = 1.137`. Measured over whole laps it is
  **1.32–1.70, worst 1.703 — and the worst case is the SHIPPING frame itself**
  (`SHIP v0`: lap mean 1 409.6, lap peak 2 401, vs the window's 1 295.8 / 1 451).
  Sizing content on 1.14 when the truth is 1.70 overstates it by 50 %, and the
  frames it drops are exactly the cresting-a-ridge frames a player notices.
  `--burst` prints both columns side by side so the gap cannot be forgotten:

  ```
  point        lapmean  lappeak  burst   winmean  winpeak  winburst
  SHIP v0       1409.6     2401  1.703    1295.8     1451    1.120
  v2            1591.4     2380  1.495    1456.8     1636    1.123
  v10           2266.9     3224  1.422    2052.0     2333    1.137
  v19           2861.7     3782  1.322    2583.0     2833    1.097
  ```

  (Rows above `v19` in that table read ~1.003 because they are pinned against
  the shipping `g_CAP_WORLD`; a saturated row has no burst to measure.)

## T.2 THE RESULT: the frame is linear — in two variables

Fitting cost against DRAWN alone makes the marginal cost appear to **climb**
(3.375 → 5.953 µs across the high ladder, a 76 % spread). Fitting against SOURCE
alone makes it appear to **fall**. Neither is a renderer effect, and chasing
either one is chasing a parameterisation error:

* **TRANSFORM is paid per SOURCE triangle.** Every triangle the kernel touches is
  projected, lit and fogged *before* anything decides whether it survives. A
  backface-culled triangle costs nearly as much as a drawn one right up to the
  moment it is thrown away.
* **FILL is paid per DRAWN triangle.** Only survivors are sorted, packed into the
  arena and handed to `SDL_RenderGeometry`.

Fit both and the bend disappears completely:

```
frame_ms = 0.636 µs × SOURCE  +  1.492 µs × DRAWN  +  1.670 ms
    27 rows · 513–7 971 drawn · 551–31 810 source · THREE independent content
    levers · R² = 0.9996 · worst residual 0.334 ms over a 15× range
```

Cross-checked on a second, independent dataset at the shipping batch capacity
(17 rows, 513–3 717 drawn): `0.443 µs·SOURCE + 2.122 µs·DRAWN + 1.238 ms`,
**R² = 0.9988**. The two runs agree on total cost to within ~0.3 ms everywhere
they overlap; they split it differently between the two terms because a dataset
whose drawn/source ratio barely varies cannot separate them (collinearity). Use
the 27-row model — it is the one with the ratio spread.

> ### ⚑ THE RULE THIS REPLACES
> **"N triangles" is not a budget. "N triangles at a drawn/source ratio of r" is.**
> The same drawn triangle costs 2.20 µs in open terrain and 4.03 µs in a deep
> crowd, and the difference is entirely how much transform work died in the
> kernel to produce it.
>
> | drawn/source `r` | all-in µs per DRAWN triangle | what has this ratio |
> |---|---|---|
> | 0.90 | 2.20 | open terrain, few props |
> | 0.70 | 2.40 | terrain + light prop mix |
> | **0.52** | **2.71** | **the shipping frame, measured** |
> | 0.40 | 3.08 | a settlement with buildings |
> | 0.35 | 3.31 | a dense near-field crowd, measured (`W v48`) |
> | 0.25 | 4.03 | a deep receding crowd, measured (`v72`) |

## T.3 Where the frame crosses 16.67 ms — MEASURED, not extrapolated

Software renderer, idle box, `read_pixels_rect` excluded, no reserve applied:

| Content | drawn | source | frame |
|---|---|---|---|
| 11-column fan, `W v48` | **4 595.6** | 13 158 | **16.650 ms** ← lands on the line |
| 5-column fan, `v56` | **3 983.2** | 14 934 | **16.862 ms** |

**The crossing is 3 900–4 600 drawn triangles, and *which* number depends on the
content, not on the renderer.** Note the two rows: `W v48` and `v48` draw the
same 13 158 SOURCE triangles, but the wide fan draws 4 595 of them against the
narrow fan's 3 746 — and costs 16.650 ms against 15.540 ms. Same transform
bill, 850 more survivors, 1.11 ms more. That 1.31 µs/survivor is the fill term
in T.2, measured directly rather than fitted.

## T.4 Does it stay linear? Yes. Nothing bends up to 7 971 drawn.

The task asked specifically whether fill and overdraw scale differently from
transform. They do not, over the whole range measured:

| | spread across the high ladder |
|---|---|
| per SOURCE triangle | 0.857 – 1.049 µs — **22 %** |
| per DRAWN triangle | 3.375 – 5.953 µs — 76 % |
| two-term residual | **±0.334 ms over a 15× range** |

The 76 % is composition (the drawn/source ratio falls as the fan densifies), not
the renderer: the two-term model absorbs it entirely. **No fill or overdraw
non-linearity was detected at any point up to 7 971 drawn / 31 810 source.**
`present` is triangle-independent by construction and stayed at 0.446–0.457 ms
across every row of every run, which is the control that says the table is not
just contention.

Two things genuinely are *not* linear, and both are step functions rather than
curves:

* **`batch_reserve` is a wall, not a slope.** Past `g_CAP_WORLD` the whole mesh
  is skipped *before* any transform runs, so an overflowing row measures a
  *cheaper* frame drawing *fewer* triangles. Such rows are marked `OVF` and
  excluded. **Raising `g_TRIS_CLAMP` without raising `g_CAP_WORLD` changes
  nothing at all.**
* **Declared capacity is not free.** Measured between the cap-3500 and cap-9000
  binaries on identical content: +0.09 ms at 1 296 drawn rising to +0.32 ms at
  3 483 — about **2–3 %**, proportional to occupancy. This is *much smaller*
  than the "≈0.19 ms per 1 000 triangles of declared capacity" recorded earlier
  in `benchframe.hml`'s own comment block, which would have predicted +1.05 ms
  flat. The older figure should not be relied on; the effect is real but minor.

## T.5 The arithmetic, so the +20 % is not mistaken for pessimism

Start from the raw crossing and subtract only things that are documented
obligations, showing the running total:

```
  16.670 ms   the 60 fps deadline
-  1.300      ARCHITECTURE §8 required slack
-  0.300      §8 net
-  0.852      §8 "input + audio + HUD build" MINUS the 0.148 ms of HUD build
              benchframe already measures
  ---------
  14.218 ms   deadline for the part benchframe actually times
```

`benchframe`'s net frame already contains sim, world registry, emit, sort,
flush, HUD build and present. It does **not** contain net, audio or input — that
is the 2.452 ms above, and it is reserve, not headroom.

Solving the T.2 model at the shipping mix (`r = 0.52`, **2.714 µs** per drawn):

```
  idle box    (14.218        - 1.670) / 0.002714  =  4 623 drawn  <- the honest ceiling
  loaded box  (14.218 / 1.28 - 1.670) / 0.002714  =  3 477 drawn
```

**The ×1.28 is measured, not inherited.** `CLAUDE.md` §1.2 states as fact that a
`llama-server` permanently holds ~17 of 24 cores. **On 2026-07-29 that was not
true** — `pgrep llama` was empty and loadavg sat at ~2.1 for this entire wave, so
every number above is a near-idle number. Rather than assume the historical
29 %, the inflation was re-measured directly with 17 synthetic busy cores:

```
  run 1   idle 7.541 ms   loaded 9.549 ms   ×1.266
  run 2   idle 7.682 ms   loaded 9.865 ms   ×1.284
  per stage, run 1: EMIT ×1.282, RENDER total ×1.281
```

So the ceiling is **~3 480 drawn on the box CI actually runs on**, and ~4 620 on
a quiet one. **`g_TRIS_CLAMP = 3500` was already right** — it sits within 1 % of
the derated hard cap, which is exactly what a clamp should be. What was wrong was
`g_TRIS_STEADY`, which had 28 % of unexplained margin under it:

```
  CLAMP  = the derated hard cap                     3 477  ->  3500  (unchanged)
  STEADY = the comfortable peak, 90 % of deadline   3 068  ->  3000  (was 2500)
```

Checking both against the deadline rather than trusting the algebra:

```
  peak 3000 drawn : 9.812 ms idle net -> x1.28 = 12.559 + 2.452 reserve = 15.01 ms   90 % of 16.67
  peak 3500 drawn : 11.169 ms         -> x1.28 = 14.296 + 2.452         = 16.75 ms  100 % — the wall
```

Both are bounds on **peak** drawn triangles, which is what `benchframe`'s gate
already asserts against. **If you are sizing CONTENT by its typical frame rather
than its worst one, divide by the measured full-lap burst factor of 1.70**: a
mean of 2 000 drawn peaks at ~3 400, and conversely a 3 500 peak clamp means the
*mean* may only sit at about **2 060**. That is the number a settlement designer
should budget against, and it is why "the average frame has headroom" keeps
being a trap.

## T.6 What that buys, in villagers — the question this was asked for

Measured marginal cost of one extra near-field villager (full 220-triangle mesh
plus its mandatory 2-triangle contact blob): **+222 SOURCE, +81 DRAWN**, and
from T.2 that is **0.262 ms** on an idle box, **0.335 ms** on a loaded one.

| Frame | villagers that fit inside 16.67 ms with the full reserve |
|---|---|
| on top of the **worst** frame of the lap (2 255 drawn) | **12** |
| on top of a **typical** frame (1 296 drawn) | **22** |

`DIRECTION.md` §6 says *"an NPC mesh is 220 triangles. Ten villagers is 2 200 —
the entire current budget."* **That is right for the worst frame and pessimistic
by 2× for a typical one**, and neither number needs any LOD work to reach. With
`SETTLEMENT.md` §7.4's LOD ladder (48-triangle ambient villagers) the same
budget carries roughly **4× more bodies**, so a town of 30 was always affordable
and is now affordable with measurements behind it.

## T.7 ⚠ THE CEILING IS NOW SET BY A CRASH, NOT BY MILLISECONDS

**`g_TRIS_CEILING = 5000` has never been executed. It throws.**

Raising `g_CAP_WORLD` (`src/render/world_render.hml:224`) above its shipping
3500 makes `frame_render()` throw on the **accelerated** renderer:

```
Uncaught exception: Type mismatch in typed array - expected element of specific type
```

Reproduced, minimal:

```sh
# an X display present, i.e. NOT SDL_VIDEODRIVER=dummy
sed -i 's/g_CAP_WORLD: i32 = 3500/g_CAP_WORLD: i32 = 5000/' src/render/world_render.hml
hemlockc -O1 tools/benchframe.hml -o /tmp/bf && /tmp/bf --sweep --quick --passes 1 --no-gate
```

* Throws inside `frame_render()`, at lap frame **250** — the peak-geometry ridge
  frame — with 19 villagers and ~3 750–3 900 drawn.
* Reproduced at **`g_CAP_WORLD` = 5000 and 9000**. **Absent at 3500.**
* **Absent on the software renderer at every cap** — the identical binary
  completes the whole sweep to 7 971 drawn under `SDL_VIDEODRIVER=dummy`.
* Not a `batch_reserve` overflow: `STAT_BATCH_OVERFLOW` is 0 at the throw.

**Consequence for this budget.** The timing says ~4 620 drawn is reachable on a
quiet box. Delivering it needs `g_CAP_WORLD > 3500`, and that currently crashes
the renderer players will actually run. So the deliverable clamp today is
**3500, set by the bug rather than by the frame time**, and
**`g_TRIS_CEILING` is corrected 5000 → 3500 so no code plans against a number
that has never survived a frame.**

This is a bug in `src/render/world_render.hml`, which this task does not own.
**Reported, not fixed.** Until it is fixed, ~1 200 drawn triangles per frame of
genuinely measured headroom are unreachable.

## T.8 Software vs accelerated — both numbers, as asked

The headless/CI path *is* the software renderer (`SDL_RenderSetVSync` returns
−1 under `SDL_VIDEODRIVER=dummy`), so **every number in this section is already
the pessimistic one** and the budget above holds on the fallback by
construction. Measured on the shipping scene, same binary, same frame:

| | software (CI) | accelerated | ratio |
|---|---|---|---|
| whole frame incl. readback | 7.497 ms | **4.742 ms** | 1.58× |
| `read_pixels_rect` | 2.482 ms | **0.225 ms** | 11.0× |
| gate | PASS 30/30 | PASS 30/30 | |

The readback collapsing from 2.482 ms to 0.225 ms is the bulk of the difference,
and it is a cost only `shot.hml` pays. **The budget is not
accelerated-renderer-dependent: it was derived on the slower of the two.**

**What is missing:** the accelerated *sweep* could not be run — it dies at
`W v16` on the T.7 crash, because reaching those counts requires the raised cap.
So the claim "fill scales linearly to 8 000 drawn" is **verified on the software
rasteriser only**. The GPU fill path is unmeasured above ~3 500 drawn. Given
software fill is the slower of the two by 1.58× on the shipping frame, the
software result is the safe bound, but it is not proof about the GPU.

## T.9 Threading — recorded, as asked, NOT implemented

`D10` banned threading because `spawn()` deep-copies objects. The measurements
say the objection is now weak and the prize is large:

| row | emit | frame | emit share |
|---|---|---|---|
| `SHIP v0` | 3.571 ms | 5.489 ms | 65 % |
| `W v48` (the crossing) | 13.522 ms | 16.650 ms | **81 %** |
| `W v132` | 29.319 ms | 33.981 ms | **86 %** |

**Emit share rises with triangle count, so it dominates exactly where the
ceiling is.** The emit kernel now writes native `f64` into flat pre-allocated
buffers, so a worker needs a buffer range and an index — not an object graph —
which is the specific thing `D10` was worried about.

Rough arithmetic at the crossing row, assuming a perfect 4-way split of emit and
zero for everything else: `13.522/4 + 3.128 = 6.51 ms` against 16.650 — which
would move the ceiling from ~4 600 to somewhere near **11 000 drawn**. Halve
that for real-world scaling and it is still a 2× ceiling.

**Recommendation: worth revisiting, and worth a spike before any more LOD
austerity is designed into the settlement.** It is a larger, cheaper win than
every triangle-shaving measure in `SETTLEMENT.md` §7 combined. Not implemented
here; out of scope for this task.
