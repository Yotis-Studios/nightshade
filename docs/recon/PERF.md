# Nightshade — Render Performance Recon

**Status:** measured, reproducible, source of truth for the render architecture.
**Author:** performance engineer (recon phase)
**All numbers in this document were produced by running code on this machine.** Nothing is
estimated, extrapolated from vendor docs, or copied from another engine. Where a number is a
fit or an extrapolation it is labelled as such.

---

## 0. Executive summary

1. **The current wobbleweed GPU path collapses on realistic scenes.** Not because of triangle
   throughput — because `array.sort()` with a comparison closure degenerates to **O(n²)** on the
   depth distributions real game geometry produces. A 2000-triangle frame takes **17.5 ms**
   with randomly-ordered depths and **145 ms** with coplanar depths (a ground plane). At 8000
   triangles the worst case is **2.4 seconds per frame**.
2. **Replacing the sort with an O(n) bucketed depth sort is the single biggest win:**
   up to **33x** on the sort-dominated cases, and it never loses.
3. **Object allocation is the fundamental throughput limit.** A Hemlock object literal costs
   97–260 ns; the shipping pipeline allocates ~10 short-lived objects per triangle. Flattening
   vertices into flat buffers is worth **1.8x–3.3x** on top of the sort fix.
4. **Combined, the proposed pipeline is 3.6x–52x faster** than the shipping one on identical
   scenes, and renders a **byte-identical image** (verified by framebuffer checksum).
5. **Draw calls are essentially free** — 1 draw call and 2000 draw calls cost the same. Do not
   contort the architecture to batch by texture.
6. **On a real GPU, internal resolution is free** (320x240 and 960x720 both cost 5.9 ms).
   It only costs on the software renderer (~100 Mpix/s).
7. **Recommended budget: 2500 triangles/frame at 60 fps**, internal resolution **320x240**.
8. **Found and fixed a crash that made the entire GPU path unusable on a real display.**

---

## 1. Method

### Machine
| | |
|---|---|
| CPU | AMD Ryzen 9 7900 (12 cores / 24 threads, up to 5.48 GHz) |
| OS | Ubuntu 22.04, kernel 6.8.0-94 |
| SDL | libsdl2 **2.0.20** |
| Compiler | `hemlockc` 2.8.1, backing C compiler gcc 11.4.0, `-O3` (hemlockc default) |
| GPU renderer | SDL `opengl` renderer |
| Headless renderer | SDL `software` renderer via `SDL_VIDEODRIVER=dummy` |

**Everything is single-threaded.** The renderer uses one core; the other 23 are idle. That is a
large amount of headroom this design currently leaves on the table (see §12).

### Harness
All benchmarks live in `/home/nbeerbower/Projects/nightshade/tools/bench/`:

| File | Purpose |
|---|---|
| `bench_pipeline.hml` | The main benchmark. Drives a synthetic but pipeline-faithful scene; every stage individually ablatable; all four vertex representations; both sorts. |
| `geom_bench.hml` | Instrumented copy of `wobbleweed/src/geom.hml` plus the optimization prototypes. |
| `bench_micro.hml` | Cost of individual Hemlock operations (property read, object literal, array index, pointer write, closure call). |
| `bench_clip.hml` | Cost of `clip_tri_near` / `clip_tri_rect` in accept, reject and straddle cases. |
| `bench_bucket.hml` | Ordering-table size vs cost vs depth quantum. |
| `diag_renderer.hml`, `diag_update.hml`, `diag_seq.hml`, `diag_wobble.hml` | Diagnostics that isolated the accelerated-renderer crash (§11). |
| `sweep.sh` | Runs the whole matrix into `results/`. |
| `analyze.py` | Turns `results/*.txt` into the tables below. |

Reproduce everything with:
```sh
cd /home/nbeerbower/Projects/nightshade/tools/bench
./sweep.sh && python3 analyze.py
```
Raw output is committed in `tools/bench/results/`; `results/ANALYSIS.txt` is the generated
report this document is written from.

### Scene design (why the numbers mean what they say)

The benchmark scene is a stack of screen-filling grids of quads. Two properties were designed in
deliberately so that the variables separate:

- **Tessellation is decoupled from fill.** Layer 0 exactly fills the viewport. Increasing the
  triangle count subdivides the same screen area, so *per-triangle CPU cost* changes while
  *total rasterized pixels* stays constant. Overdraw is varied independently with `BENCH_LAYERS`,
  where each layer is another full screen of pixels.
- **Depth is decoupled from screen position.** Each quad's world x/y are scaled by its own |z|,
  so a quad lands on exactly the same screen tile no matter what depth it is placed at. This
  means the *depth distribution* can be changed without changing a single rasterized pixel —
  which is what makes the sort measurements in §6 trustworthy.

Three depth distributions are tested, because the sort's behaviour depends entirely on this:

| Mode | What it is | Real-world analogue |
|---|---|---|
| `random` | depths scrambled | geometry submitted in arbitrary order |
| `ramp` | depth increases monotonically with emission order | **a ground plane; a chunk list walked front-to-back** |
| `flat` | all triangles coplanar → **all sort keys equal** | **a floor, a wall, a ceiling** |

`ramp` and `flat` are not adversarial corner cases invented to make the code look bad. They are
the two most common shapes in a voxel/chunked open-world game. That is the core of §6.

### Timing
`SDL_GetTicks()` (1 ms resolution) over 120 timed frames after 10 warm-up frames, so quantisation
is ~0.008 ms/frame. Slow configurations use fewer frames (down to 3) — noted where relevant.
Each run is a fresh process. Every configuration passes a complete set of `BENCH_*` environment
variables via `env`, so no setting can leak between runs.

### Honesty caveats
- The scene is synthetic. It has one texture per draw-call run, no skinned meshes, no
  transparency sorting, and no game logic running alongside. Real frames will be somewhat worse.
- Triangles are fully on-screen in the main sweep, so both clip functions take their fast paths.
  The cost of *actual* clipping is measured separately in §10.
- `SDL_GetTicks` at 1 ms granularity means single-frame measurements are noisy; all reported
  figures are means over many frames.
- The accelerated-renderer fill isolation (§9) produced nonsensical (negative) values and is
  reported as unusable rather than dressed up — see the note there.

---

## 2. Headline result

Identical scene, identical output image, shipping pipeline vs proposed pipeline.
Depth distribution `ramp` (i.e. a ground plane — the realistic case), 320x240, headless software renderer:

| Triangles | Shipping (`obj` + closure sort + ndc key) | Proposed (`flatsdl` + bucket sort + view key) | Speedup |
|---:|---:|---:|---:|
| 500 | 9.12 ms (110 fps) | **2.52 ms (397 fps)** | 3.6x |
| 1000 | 26.25 ms (38 fps) | **3.78 ms (265 fps)** | 6.9x |
| 2000 | 84.12 ms (12 fps) | **6.94 ms (144 fps)** | 12.1x |
| 4000 | 314.88 ms (3 fps) | **12.47 ms (80 fps)** | 25.3x |
| 8000 | 1270.75 ms (0.8 fps) | **24.28 ms (41 fps)** | 52.3x |

Same comparison on the **real display / OpenGL renderer** (320x240 internal, 3x window):

| Triangles | Shipping | Proposed | Speedup |
|---:|---:|---:|---:|
| 500 | 7.70 ms (130 fps) | **1.57 ms (638 fps)** | 4.9x |
| 1000 | 23.40 ms (43 fps) | **2.97 ms (337 fps)** | 7.9x |
| 2000 | 84.60 ms (12 fps) | **6.01 ms (166 fps)** | 14.1x |
| 4000 | 317.30 ms (3 fps) | **11.54 ms (87 fps)** | 27.5x |
| 8000 | 1273.90 ms (0.8 fps) | **24.26 ms (41 fps)** | 52.5x |

**Correctness:** every path — `obj`, `flat`, `flatraw`, `flatsdl`, with both sorts and both depth
keys — produces framebuffer checksum `265113440` on the same scene. The optimizations are not
trading image quality for speed.

---

## 3. The budget

### Marginal cost per triangle (proposed pipeline, 320x240, software renderer)

From the measured series 500→2.51 ms, 1000→4.03, 2000→6.92, 4000→12.68, 8000→26.34:

| Range | µs per triangle |
|---|---|
| 500 → 1000 | 3.04 |
| 1000 → 2000 | 2.89 |
| 2000 → 4000 | 2.88 |
| 4000 → 8000 | 3.42 |

**Marginal cost ≈ 3.0 µs per triangle.** Fixed per-frame cost ≈ 0.7 ms (clear + present + one
screenful of fill).

### Hard ceilings (render only, nothing else running)

| Target | Frame budget | Max triangles (proposed) | Max triangles (shipping, best case) |
|---|---|---|---|
| 60 fps | 16.67 ms | **~5000** | ~1870 |
| 30 fps | 33.3 ms | **~10500** | ~3650 |

The shipping figures use the `random` depth distribution — i.e. the *best* case for the current
sort. On `ramp`/`flat` geometry the shipping pipeline cannot hit 60 fps at any useful triangle
count (2000 triangles = 12 fps).

### Recommended shipping budget

A game is not just a renderer. Reserving ~40% of the frame for game logic, physics, AI, world
streaming, audio and input:

> ### **Budget: 2500 triangles/frame at 60 fps, 320x240 internal resolution.**
> - Render cost at 2500 tris with **one** screenful of fill: **8.4 ms** of a 16.67 ms frame.
> - Draw calls: **unlimited in practice** — do not budget them (see §8).
> - Hard ceiling before the renderer alone misses 60 fps: 5000 triangles.

Overdraw is charged on top, at ~0.8 ms per extra screenful at 320x240 (§9). The tradeoff, using
the measured 2.88 µs/triangle marginal cost:

| Triangles | Render, 1 layer | Render, 4 layers | Left for game logic (4 layers) |
|---:|---:|---:|---:|
| 2000 | 6.9 ms | 9.3 ms | **7.3 ms** |
| **2500** | **8.4 ms** | **10.8 ms** | **5.9 ms** |
| 3000 | 9.8 ms | 12.2 ms | 4.5 ms |
| 4000 | 12.7 ms | 15.1 ms | 1.6 ms |

2500 triangles with up to 4 layers of overdraw leaves **~5.9 ms/frame** for game logic — tight but
workable, and this is the *software-renderer* fallback case. On the GPU path fill is free (§9), so
the same budget leaves ~8.3 ms. If the game logic turns out to need more, cut overdraw before
cutting triangles: each avoided screenful buys back 0.8 ms.

This is comfortably a PS1-era budget and entirely on-aesthetic. For reference the PS1 pushed
roughly 1500–4000 textured triangles per frame in real games.

**If the design needs more than 5000 triangles/frame**, the options in priority order are:
parallelism (§12, ~4x available and untouched), then reducing per-triangle work further, then
dropping to 30 fps. Do not attempt it by raising the triangle count alone.

---

## 4. Layer 0 — what Hemlock operations actually cost

Everything else follows from this table. Measured over 2,000,000 iterations each, empty-loop
baseline subtracted (`bench_micro.hml`, compiled `-O3`).

| Operation | ns/op | Notes |
|---|---:|---|
| f64 arithmetic (6 ops) | 13.0 | ~2 ns per arithmetic op — arithmetic is *not* the problem |
| object property read | 7.5–11.0 | compiles to `hml_object_get_field_required(obj,"x")`: djb2 hash + `strcmp` |
| object property write (existing field) | 4.0 | |
| **object literal, 3 fields** | **97.0** | |
| **object literal, 4 fields** | **124.5** | |
| **object literal, 8 fields** | **260.5** | ~32 ns per field |
| array index read | 11.5–13.9 | has a real fast path: `hml_array_get_i32_fast` |
| array index write | 3.5 | |
| `array.push(f64)` | 12.5 | |
| `ptr_write_f64` | 8.0 | |
| `ptr_deref_f64` | 10.0 | |
| `ptr_write_f32` / `ptr_write_u8` | 7.5 | |
| `ptr_write_f64` direct to buffer | 1.5 | no `ptr_offset` call in the loop |
| static function call (2 args) | 11.5 | |
| closure call (2 args) | 21.5 | |
| **sort comparator call (2 obj args, 2 field reads)** | **62.0** | this is the per-comparison cost of `array.sort()` |

### The two facts that drive the whole architecture

**(a) Object creation costs ~32 ns per field.** Hemlock objects are name-keyed field arrays with
an eagerly-built hash table. Constructing `{x,y,z,u,v,r,g,b}` costs 260 ns — roughly **130
floating-point operations' worth of time to store 8 numbers**.

**(b) Property access is string-keyed.** `v.x` compiles to a function call that hashes the string
`"x"` and `strcmp`s it against the field names. Arrays get an inlined fast path; objects do not.
Verified by reading the generated C:

```c
HmlValue _tmp88 = hml_object_get_field_required(_tmp89, "x");
```

Consequence: **in the render hot loop, per-vertex data must not live in objects.**

---

## 5. Where the time goes today (ablation)

Cumulative timings with the pipeline truncated after each stage; the delta column is that
stage's own cost. Shipping code path, 320x240, software renderer.

### 2000 triangles, `random` depth (best case for the current sort)

| Stage | Cumulative | Delta | % frame |
|---|---:|---:|---:|
| frame overhead (clear+present) | 0.13 ms | 0.13 ms | 0.8% |
| + transform (`cv` / `mat_apply`) | 5.57 ms | **5.43 ms** | **30.7%** |
| + `clip_tri_near` | 6.00 ms | 0.43 ms | 2.5% |
| + `to_screen` (perspective divide) | 10.43 ms | **4.43 ms** | **25.1%** |
| + `clip_tri_rect` | 10.33 ms | ~0 ms | ~0% |
| + `batch_tri` push | 12.13 ms | 1.80 ms | 10.2% |
| + painter sort | 15.03 ms | 2.90 ms | 16.4% |
| + `put_vert` | 16.72 ms | 1.68 ms | 9.5% |
| + `SDL_RenderGeometry` | 17.68 ms | 0.97 ms | 5.5% |

### 8000 triangles, `ramp` depth (a ground plane — the realistic case)

| Stage | Cumulative | Delta | % frame |
|---|---:|---:|---:|
| frame overhead | 0.50 ms | 0.50 ms | 0.0% |
| + transform | 23.02 ms | 22.52 ms | 1.6% |
| + `clip_tri_near` | 24.23 ms | 1.22 ms | 0.1% |
| + `to_screen` | 39.13 ms | 14.90 ms | 1.0% |
| + `clip_tri_rect` | 43.70 ms | 4.57 ms | 0.3% |
| + `batch_tri` push | 55.10 ms | 11.40 ms | 0.8% |
| **+ painter sort** | **1343.00 ms** | **1287.90 ms** | **90.7%** |
| + `put_vert` | 1352.33 ms | 9.33 ms | 0.7% |
| + `SDL_RenderGeometry` | 1419.33 ms | 67.00 ms | 4.7% |

### Two conclusions

1. **`SDL_RenderGeometry` — the actual GPU submission — is 1–5% of the frame.** The renderer is
   not GPU-bound, not fill-bound, and not draw-call-bound. It is bound by CPU-side vertex
   bookkeeping in Hemlock. Every optimization must target that.
2. **The sort is either 16% of the frame or 91% of the frame depending on nothing but the order
   the geometry happens to arrive in.** That is not a performance characteristic you can ship.

---

## 6. Finding 1 — the painter's sort is quadratic on real geometry

### Root cause

`geom.hml` sorts with:
```hemlock
tris.sort(fn(p, q) {
    if (p.depth > q.depth) { return 0 - 1; }
    if (p.depth < q.depth) { return 1; }
    return 0;
});
```
In the **compiled** runtime `array.sort()` is `hml_array_sort()` in
`runtime/src/builtins_array.c`, which is a textbook quicksort with a **last-element pivot** and
no median-of-three, no introsort fallback, and no equal-element partitioning:

```c
static int partition(HmlValue *arr, int low, int high, SortContext *ctx) {
    HmlValue pivot = arr[high];          /* last element as pivot */
    ...
}
```

That pivot choice has two classic worst cases, and **both are the normal case for game geometry**:
- **All keys equal** — a coplanar surface (floor, wall, ceiling). Every partition is maximally
  unbalanced.
- **Already sorted keys** — a ground plane tessellated front-to-back, or chunks walked in depth
  order.

Each comparison is a **dynamic closure call costing 62 ns** (§4), so the quadratic term is
expensive per unit as well as quadratic in count.

*(Note: the **interpreter** uses a different implementation — insertion sort — which is
unconditionally O(n²). This document benchmarks the compiled path, as the game ships compiled.)*

### Measured cost

Sort cost isolated by differencing against a no-sort run (`obj` path, view depth key):

| Triangles | Depth | Closure sort | Bucketed sort | No sort | **Closure sort cost** | **Bucket sort cost** |
|---:|---|---:|---:|---:|---:|---:|
| 500 | random | 4.93 ms | 4.67 ms | 4.53 ms | 0.40 ms | 0.13 ms |
| 500 | ramp | 8.87 ms | 4.78 ms | 4.45 ms | 4.42 ms | 0.33 ms |
| 500 | flat | 12.18 ms | 4.53 ms | 4.42 ms | 7.75 ms | 0.11 ms |
| 2000 | random | 17.88 ms | 17.86 ms | 15.57 ms | 2.31 ms | 2.29 ms |
| 2000 | ramp | 85.62 ms | 17.52 ms | 15.80 ms | **69.83 ms** | 1.72 ms |
| 2000 | flat | 143.12 ms | 18.36 ms | 15.30 ms | **127.83 ms** | 3.06 ms |
| 8000 | random | 77.73 ms | 75.90 ms | 62.98 ms | 14.75 ms | 12.92 ms |
| 8000 | ramp | 1396.33 ms | 72.29 ms | 63.01 ms | **1333.32 ms** | 9.28 ms |
| 8000 | flat | 2409.67 ms | 72.24 ms | 65.59 ms | **2344.08 ms** | 6.65 ms |

Doubling the triangle count on `ramp` data multiplies the sort cost by ~4 — clean O(n²).

**End-to-end speedup from swapping the sort alone: 1.0x (random) to 33.4x (flat, 4000 tris).**
It is never a loss.

### Secondary hazard: recursion depth

With a last-element pivot on sorted input the recursion depth is O(n). Measured: 16000 triangles
= 5.1 s/frame, 32000 = 20.0 s/frame, both survived without stack overflow, but the depth grows
linearly with triangle count and there is no introsort depth limit in the runtime. A large batch
is a latent stack-overflow crash as well as a performance cliff.

### The fix — a bucketed (counting) depth sort

Quantise depth into a fixed ordering table and counting-sort. This is exactly what PS1 hardware
did (an "ordering table"), so it is period-correct as well as fast. O(n + NB), no comparisons, no
closure calls, and — critically — **completely insensitive to input order**.

Prototype in `geom_bench.hml` (`sort_bucket` / `flat_sort` / `sdlv_sort`).

**Implementation notes learned the hard way:**
- Do **not** cache the bucket index back onto the triangle object (`t.bk = k`). Adding a *new*
  field to an existing Hemlock object triggers a storage grow + hash-table rebuild. Doing that
  made the sort **~2x slower than recomputing the index** in the scatter pass. Recompute it.
- A plain Hemlock array is a **better** counter store than a raw `alloc()` buffer, because array
  indexing has an inlined fast path while `ptr_deref_i32`/`ptr_write_i32` are real calls. Measured
  at 8000 triangles, NB=2048: array 0.78 ms vs pointer buffer 0.93 ms.

### Choosing the depth key — use view depth, not ndc z

The `z` a geom vertex carries is used for **exactly one thing**: the painter sort key.
`SDL_Vertex` is 2D, so it never reaches the rasterizer. That makes the key a free choice.

The shipping code uses **ndc z**, which for `near=0.1, far=200` is
`ndc_z = 1.001 − 0.2001/d`. That is violently nonlinear: the entire range from 3 m to 23 m is
squeezed into ndc 0.934–0.992. Bucketing that uniformly wastes almost the whole table.

Quantisation error of one bucket, NB=4096, converted to world distance:

| Distance from camera | ndc z key | **view depth key** |
|---|---|---|
| 3 m | 3.2 cm | **3.1 cm** |
| 23 m | 1.87 m | **3.1 cm** |
| 100 m | ~35 m | **3.1 cm** |

Verified empirically — worst adjacent-pair depth violation over a full frame:

| Sort | Key | Inversions | Max violation |
|---|---|---|---|
| closure | ndc | 0 / 9995 | 0.0 |
| bucket | ndc | 2325 / 9995 | 0.000706 ndc (= exactly one bucket) |
| closure | view | 0 / 9995 | 0.0 |
| bucket | view | 1300 / 9995 | 0.0296 m (= exactly one bucket) |

Both bucketed sorts are correct **to within one bucket quantum** — which is the definition of an
ordering table, and visually irrelevant when the quantum is 3 cm. But with the ndc key the
quantum *becomes 35 m at 100 m distance*, which would visibly mis-order distant geometry. With
the view-depth key it is 3 cm everywhere.

> **Store view-space depth (`w`) in the vertex `z` field, not ndc z.** Same ordering, same code
> path, dramatically better numerical behaviour, zero cost.

### Ordering-table size

Cost of the table itself (clear + prefix scan, per frame) vs its depth quantum over a 128 m draw
distance (`bench_bucket.hml`):

| NB | quantum | cost @2000 tris | cost @8000 tris |
|---:|---:|---:|---:|
| 256 | 50.0 cm | 0.17 ms | 0.68 ms |
| 1024 | 12.5 cm | 0.20 ms | 0.72 ms |
| **2048** | **6.25 cm** | **0.24 ms** | **0.78 ms** |
| 4096 | 3.1 cm | 0.31 ms | 0.84 ms |
| 16384 | 0.8 cm | 0.74 ms | 1.26 ms |

> **Recommendation: NB = 2048 over a 128 m draw distance (6.25 cm quantum).** 4096 is also fine;
> beyond that the fixed cost grows for no visible benefit.

---

## 7. Finding 2 — flatten the vertices

### Where the allocations are

Per triangle, the shipping pipeline creates roughly:
- 3 × `mat_apply` result `{x,y,z,w}` — 4 fields
- 3 × `cv` clip vertex `{x,y,z,w,u,v,l}` — 7 fields
- 3 × `to_screen` geom vertex `{x,y,z,u,v,r,g,b}` — 8 fields
- 1 × `batch_tri` record `{tex,depth,a,b,c}` — 5 fields
- plus the nested arrays returned by `clip_tri_near` and `clip_tri_rect` even on the accept path

At ~32 ns/field that is **roughly 2 µs of pure allocation per triangle**, which matches the
measured 30.7% transform + 25.1% projection in §5.

### Four representations measured

- `obj` — shipping representation (objects everywhere)
- `flat` — front half unchanged, back half (batch/sort/pack) in flat f64 buffers
- `flatraw` — no vertex objects at all; transform/project/cull on scalars into flat f64 buffers
- `flatsdl` — as `flatraw`, but **writes `SDL_Vertex` bytes directly at push time**, so the flush
  is one 60-byte `memcpy` per triangle

Bucketed sort, view key, random depth, 320x240:

| Triangles | `obj` | `flat` | `flatraw` | **`flatsdl`** | flatsdl vs obj |
|---:|---:|---:|---:|---:|---:|
| 500 | 4.59 ms | 4.82 ms | 2.90 ms | **2.51 ms** | 1.83x |
| 1000 | 8.68 ms | 8.87 ms | 4.78 ms | **4.03 ms** | 2.15x |
| 2000 | 17.67 ms | 16.09 ms | 8.42 ms | **6.92 ms** | 2.55x |
| 4000 | 41.83 ms | 32.38 ms | 15.73 ms | **12.68 ms** | 3.30x |
| 8000 | 77.50 ms | 63.94 ms | 33.42 ms | **26.34 ms** | 2.94x |

**`flat` is not worth doing.** Flattening only the back half is within noise of `obj` — the
allocations in the front half dominate, and you pay to convert between representations. This is
an all-or-nothing optimization: **eliminate vertex objects from the whole path, or don't bother.**

`flatsdl` beats `flatraw` by a further 16–27% purely by choosing the *right* flat layout: storing
vertices already in `SDL_Vertex` form turns the flush from 32 pointer operations per triangle
into a single `memcpy`.

### Where the time goes after the fix

Proposed path (`flatsdl` + bucket + view key), ablated:

| Stage | 2000 tris | | 8000 tris | |
|---|---:|---:|---:|---:|
| | delta | % | delta | % |
| transform + project + cull | 2.98 ms | 42.4% | 12.32 ms | 49.4% |
| push `SDL_Vertex` | 2.31 ms | 32.9% | 9.72 ms | 39.0% |
| bucketed sort | 0.39 ms | 5.6% | 0.61 ms | 2.4% |
| `memcpy` gather | 0.22 ms | 3.1% | 0.97 ms | 3.9% |
| `SDL_RenderGeometry` | 1.12 ms | 16.0% | 1.32 ms | 5.3% |
| **total** | **7.02 ms** | | **24.93 ms** | |

The sort has gone from 91% of the frame to **2.4%**. The remaining cost is honest work:
transforming and packing vertices. Further gains would have to come from parallelism (§12) or
from submitting fewer triangles (culling — the architect's domain).

---

## 8. Finding 3 — draw calls are free

2000 triangles, proposed path, varying the number of distinct textures:

| Textures | Draw calls | ms/frame | fps |
|---:|---:|---:|---:|
| 1 | 1 | 6.89 | 145.1 |
| 8 | 8 | 6.71 | 149.1 |
| 64 | 64 | 6.72 | 148.9 |
| 256 | 304 | 6.83 | 146.3 |

And the deliberately pathological case, where textures are interleaved so that after the depth
sort **every single triangle is its own draw call**:

| Textures | Draw calls | ms/frame | fps |
|---:|---:|---:|---:|
| 2 | 2000 | 7.18 | 139.2 |
| 8 | 2000 | 7.43 | 134.5 |
| 32 | 2000 | 7.23 | 138.2 |

**2000 draw calls cost 0.3–0.5 ms more than 1 draw call.** On the accelerated renderer the same
holds (1 call 5.98 ms, 304 calls 6.26 ms).

> **Do not design around draw-call batching.** Per-call overhead is ~0.25 µs and irrelevant at
> this scale. Texture atlasing, material sorting and batching schemes should be adopted only if
> they help authoring or memory — they will not help performance. Keep the simple
> "one draw call per same-texture run after the depth sort" flush; it costs nothing even when it
> degenerates.

This is a genuinely useful licence: the painter's sort is free to reorder triangles across
materials, which is what makes correct transparency and PS1-style layering easy.

---

## 9. Finding 4 — resolution and fill rate

### Software renderer (headless), proposed path, 2000 triangles

| Resolution | 1 layer | 2 layers | 4 layers |
|---|---|---|---|
| 320x240 | 6.85 ms (146 fps) | 13.30 ms (75 fps) | 26.97 ms (37 fps) |
| 480x360 | 7.93 ms (126 fps) | 14.95 ms (67 fps) | 30.17 ms (33 fps) |
| 640x480 | 9.02 ms (111 fps) | 17.63 ms (57 fps) | 34.55 ms (29 fps) |
| 960x720 | 13.17 ms (76 fps) | 24.45 ms (41 fps) | 48.38 ms (21 fps) |

### Fill cost isolated (stage 7 = everything but the draw; stage 8 = with the draw)

| Resolution | Layers | No draw | With draw | Fill cost | Per screenful | Mpix/s |
|---|---:|---:|---:|---:|---:|---:|
| 320x240 | 4 | 23.48 ms | 26.88 ms | 3.40 ms | 0.85 ms | 90.4 |
| 320x240 | 8 | 48.92 ms | 53.37 ms | 4.45 ms | 0.56 ms | 138.1 |
| 480x360 | 4 | 23.12 ms | 30.18 ms | 7.07 ms | 1.77 ms | 97.8 |
| 640x480 | 4 | 22.85 ms | 34.53 ms | 11.68 ms | 2.92 ms | 105.2 |
| 640x480 | 8 | 47.47 ms | 68.80 ms | 21.33 ms | 2.67 ms | 115.2 |

**Software rasterizer fill rate ≈ 100 Mpixel/s** (textured + Gouraud). Cost per full screen:

| Resolution | Pixels | Cost per screenful of overdraw |
|---|---:|---:|
| 320x240 | 76.8 k | **~0.8 ms** |
| 480x360 | 172.8 k | ~1.8 ms |
| 640x480 | 307.2 k | ~2.9 ms |

### Accelerated renderer — resolution is free

Same test on the real display (2000 triangles):

| Resolution | 1 layer | 2 layers | 4 layers |
|---|---|---|---|
| 320x240 | 5.88 ms | 11.85 ms | 23.83 ms |
| 480x360 | 5.92 ms | 12.12 ms | 24.85 ms |
| 640x480 | 5.88 ms | 11.82 ms | 24.07 ms |
| 960x720 | 5.80 ms | 12.18 ms | 26.20 ms |

**Internal resolution costs nothing on a GPU.** Going from 320x240 to 960x720 — nine times the
pixels — changes the frame time by less than noise. The cost that *does* scale with `layers` here
is the CPU-side cost of the extra triangles (each layer adds 2000 more), not the pixels.

*(The accelerated fill-isolation run produced negative "fill cost" at 1–2 layers — the stage-7
no-draw case measured **slower** than stage 8. This is an artefact of how the OpenGL renderer and
compositor behave when a frame contains no geometry, not a real measurement. It is reported here
as unusable rather than converted into a misleading Mpix/s figure. The resolution table above is
the reliable result.)*

### Recommendation

> **Internal resolution: 320x240.**

Reasoning:
1. It is the right aesthetic. PS1 games ran 320x240; the chunky pixels and vertex jitter are the
   look Nightshade is going for. Present it upscaled 3x–4x with nearest-neighbour.
2. It is the only choice that is safe on **both** renderers. On the GPU any resolution is free,
   but the software renderer is the fallback whenever OpenGL is unavailable, and there 640x480
   costs 2.9 ms/screenful — 17% of the frame budget for one layer of overdraw, and the game will
   have several.
3. At 320x240 a screenful of overdraw costs 0.8 ms, so the budget comfortably absorbs **4 layers
   of overdraw (3.2 ms)** even in the software fallback.

480x360 is a defensible option if the art direction wants more detail and the GPU path is
guaranteed; it costs 1.8 ms/screenful in software. **Do not go to 640x480** — it spends a quarter
of the frame budget on fill in the software fallback for no aesthetic gain.

---

## 10. Finding 5 — clipping

The main sweep keeps every triangle on screen, so both clip functions take their early-exit path.
Measured separately (`bench_clip.hml`), per triangle:

| Case | ns/triangle | vs fast path |
|---|---:|---:|
| `clip_tri_near` — all in front (accept) | 205 | 1.0x |
| `clip_tri_near` — all behind (reject) | 155 | 0.8x |
| `clip_tri_near` — straddling, 1 vertex behind | **1735** | 8.5x |
| `clip_tri_near` — straddling, 2 vertices behind | **1590** | 7.8x |
| `clip_tri_rect` — fully inside (accept) | 475 | 1.0x |
| `clip_tri_rect` — straddling the guard band | **5515** | 11.6x |

Two things follow.

**(a) A straddling triangle costs ~7 µs versus ~0.7 µs for an interior one — 10x.** Straddlers are
normally a small fraction (screen border + near plane), so at 5% of a 2000-triangle frame the
extra cost is ~0.7 ms. That is affordable, and it validates the proposed design: **the flat path
may reject straddling triangles and fall back to the object path for them.** The fallback is
allowed to be slow because it is rare. Budget it explicitly: if more than ~10% of triangles
straddle, revisit.

**(b) Even the accept fast path allocates.** `clip_tri_near` returns `[[a,b,c]]` — two array
allocations — and `clip_tri_rect` the same, on *every* triangle. That is most of the 205 ns and
475 ns above, for a function that in the common case decides "yes, keep it unchanged". The
proposed path removes this by making the fast path a pure predicate that returns a status and
writes through to caller-owned buffers, with no allocation.

---

## 11. Finding 6 — the GPU path crashed on every real display (fixed)

**This was a hard blocker, not a performance issue: the entire wobbleweed GPU path segfaulted on
startup on any real display.** It went unnoticed because all previous benchmarking was headless,
where SDL selects the `software` renderer and the bug does not trigger.

### Symptom
```
*** Hemlock runtime: fatal SIGSEGV (invalid memory access) ***
  libSDL2-2.0.so.0(+0x653ba)
  _mod4_fn_upload_texture+0x701
  hml_fn_main+0x2df
```
Reproduced with the stock `examples/walk_gpu.hml`, so it was pre-existing in wobbleweed and not
introduced by this work.

### Diagnosis
Bisected with `diag_renderer.hml` / `diag_update.hml` / `diag_seq.hml`:

1. The OpenGL renderer's native texture formats are `ARGB8888, ABGR8888, RGB888, BGR888` +
   YUV. **`RGB24` — the format wobbleweed uses for every texture — is not among them.**
   (The software renderer does not list it either, but does not trip the bug.)
2. `SDL_CreateTexture(RGB24, ...)` **succeeds** (SDL transparently allocates an internal
   conversion "native" texture).
3. `SDL_UpdateTexture(...)` **succeeds**, returns 0, sets no error.
4. **`SDL_SetTextureScaleMode(t, SDL_SCALEMODE_NEAREST)` segfaults** — the third and last call in
   `upload_texture`. Confirmed by toggling exactly that call: with it, crash; without it,
   `SURVIVED`.
5. Repeating the identical sequence with a renderer-native format (`ARGB8888`) survives.

So: SDL 2.0.20 faults in the scale-mode path when the texture is one of its internal
format-conversion textures.

### Fix applied to `wobbleweed/src/sdl.hml`
Set the scale-quality hint once at startup — `SDL_CreateTexture` reads it, so it applies to every
texture on every renderer — and drop the per-texture call:

```hemlock
// in window_open(), right after SDL_Init:
SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0");   // 0 = nearest

// in upload_texture(): SDL_SetTextureScaleMode(...) removed
```

**Verified:** `examples/walk_gpu.hml` now runs on the real display at 121 fps (previously: instant
crash), nearest-neighbour filtering intact, and all headless numbers unchanged.

### Follow-up recommendation
Nightshade should upload textures in **`ARGB8888`**, a renderer-native format, rather than
`RGB24`. Beyond avoiding this class of bug entirely, it removes SDL's per-texture conversion copy.
This means changing `texture.hml` to produce 4-byte-per-pixel buffers. Not required for
correctness now that the hint fix is in, but it is the robust choice and should be done before
the texture pipeline grows.

---

## 12. Compiled vs interpreted — and the parallelism left on the table

### Compilation is mandatory (confirmed independently)

2000 triangles, 320x240, same source:

| Path | Interpreted (`hemlock`) | Compiled (`hemlockc -O3`) | Speedup |
|---|---:|---:|---:|
| shipping `obj` + closure | 316 ms/frame (3.2 fps) | 17.5 ms/frame (57 fps) | **18x** |
| proposed `flatsdl` + bucket | 34 ms/frame (29 fps) | 6.9 ms/frame (145 fps) | **4.9x** |

Two observations:
- The brief's "must compile with `hemlockc`" is confirmed — 18x on the current code.
- **The proposed pipeline is far less compiler-dependent** (4.9x instead of 18x), because it
  avoids the runtime object machinery that the interpreter is slowest at. It is 9x faster than
  the shipping path *even when interpreted*. This makes iteration on an interpreted build
  genuinely usable (29 fps), which is a real workflow win.

### Unused parallelism

The renderer is single-threaded on a 12-core/24-thread machine. Hemlock has `spawn`/`join` and
channels. The pipeline's dominant cost — transform + project + pack, 82–88% of the proposed
frame — is embarrassingly parallel over chunks: each worker transforms its own triangles into its
own flat buffer, then a single-threaded pass merges the per-worker depth histograms and does the
final gather.

**This is not measured here** (it is an architecture change, not a micro-optimization) and is
flagged as the highest-leverage remaining lever if the triangle budget ever needs to exceed 5000.
A conservative 4x on the parallel portion would move the 60 fps ceiling from ~5000 to roughly
15000 triangles.

---

## 13. Ranked optimizations, with measured speedups

| # | Optimization | Measured gain | Effort | Risk |
|---|---|---|---|---|
| **1** | **Replace `array.sort()` + closure with a bucketed counting sort** | **1.0x–33.4x** (33x on coplanar, 19x on ground-plane, ~1x on random) | Low — one self-contained function | Very low; verified correct to one bucket quantum |
| **2** | **Eliminate vertex objects: `flatsdl` layout end-to-end** | **1.8x–3.3x** on top of #1 | High — rewrites the vertex path | Medium; validated by identical framebuffer checksum |
| **3** | Store view depth (`w`) in the vertex `z` field instead of ndc z | 0x speed, but turns the bucket sort's worst-case ordering error from **35 m to 3 cm** at 100 m | Trivial | None — same ordering |
| **4** | Write `SDL_Vertex` bytes at push time; flush is a `memcpy` | **1.16x–1.27x** over a plain flat f64 layout | Low, once #2 is done | Low |
| **5** | Make the clip fast paths allocation-free (predicate + caller buffers) | Removes 205 ns + 475 ns/triangle of pure allocation (~0.7 ms at 1000 tris) | Medium | Low |
| **6** | Fix `SDL_SetTextureScaleMode` crash (§11) | **Unblocks the real display entirely** (was: instant segfault) | Trivial — **already applied** | None |
| **7** | Upload textures as `ARGB8888` instead of `RGB24` | Removes SDL's per-texture conversion; avoids the §11 bug class | Medium | Low |
| **8** | Parallelise transform/pack across cores | **Not measured**; ~4x on 82–88% of the frame is plausible | High | Medium |
| — | ~~Batch draw calls by texture~~ | **No gain — do not do this** (§8) | — | — |
| — | ~~Flatten only the back half (`flat`)~~ | **No gain — within noise of `obj`** (§7) | — | — |

**Do #1, #3 and #6 immediately** — they are small, safe, and between them convert an unshippable
renderer into a working one. #2 and #4 together are the difference between a 1870-triangle budget
and a 5000-triangle budget, and should be done before content authoring fixes the art budget.

---

## 14. Recommended render architecture

Concrete shape for the implementation team, all of it validated by the prototypes in
`tools/bench/geom_bench.hml`.

### Per-frame data layout
```
tri_verts : ptr    // max_tris * 60 bytes — SDL_Vertex[3], written at push time
tri_depth : ptr    // max_tris * 8 bytes  — f64 view-space depth
tri_tex   : ptr    // max_tris * 8 bytes  — SDL_Texture*
tri_idx   : ptr    // max_tris * 4 bytes  — i32 sort permutation
counts    : array  // NB+1 i32 — Hemlock array, NOT a raw buffer (measured faster)
out_verts : ptr    // max_tris * 60 bytes — gather target handed to SDL
```

### Per-frame flow
1. **Emit.** For each visible chunk, for each triangle: transform by the combined MVP on scalars
   (no vertex objects), near-plane accept/reject, perspective divide, viewport transform with the
   PS1 pixel snap, guard-band accept/reject, then write three `SDL_Vertex` structs plus depth and
   texture into the flat buffers. Straddling triangles go to a slow object-path fallback.
2. **Sort.** Counting sort on view depth, NB = 2048 over the draw distance, descending (farthest
   first), producing `tri_idx`. Recompute the bucket index in the scatter pass; never write it
   back onto anything.
3. **Flush.** Walk `tri_idx`; `memcpy` 60 bytes per triangle into `out_verts`; issue one
   `SDL_RenderGeometry` per same-texture run. Do not try to minimise the run count.

### Invariants to preserve
- `SDL_Vertex` is 2D — the vertex `z` is *only* the painter key. Keep it view depth.
- Screen x/y must stay snapped to whole pixels (`floor(v + 0.5)`) — that is the PS1 vertex jitter
  and it is a feature.
- Affine UVs (no perspective correction) — that is the PS1 texture warble and it is a feature.
- The sky quad must sort behind everything: with a view-depth key, give it a large depth
  (e.g. the far plane), **not** the current `z = 2.0` which is an ndc-space value.

### Instrumentation to build in from day one
Keep a per-frame counter of: triangles submitted, triangles rejected by each cull stage,
triangles sent to the straddle fallback, draw calls, and the four stage timings from §7. The
whole reason this document could be written is that the pipeline was ablatable; keep it that way.

---

## 15. Answers to the specific questions asked

**1. Triangles/second through the current pipeline.**
Shipping path, 320x240, software renderer, best case (`random` depth):

| Triangles/frame | ms/frame | fps | triangles/second |
|---:|---:|---:|---:|
| 500 | 4.74 | 210.9 | 105,000 |
| 1000 | 9.06 | 110.4 | 110,000 |
| 2000 | 17.53 | 57.0 | 114,000 |
| 4000 | 34.58 | 28.9 | 116,000 |
| 8000 | 74.72 | 13.4 | 107,000 |

**~110,000 triangles/second**, flat across the range. On realistic (`ramp`) geometry it collapses
to 55,000 → 5,800 tri/s as the sort goes quadratic. The proposed pipeline sustains
**~290,000–315,000 triangles/second** at 2000–8000 triangles/frame, regardless of depth
distribution.

**2. Where the time goes.** §5 (shipping) and §7 (proposed). Summary at 2000 tris shipping:
transform 31%, projection 25%, sort 16% (up to 91% on realistic geometry), `batch_tri` 10%,
`put_vert` 10%, `SDL_RenderGeometry` **5.5%**.

**3. Is a bucketed O(n) sort a big win?** **Yes — the biggest single win.** 1.0x to 33.4x
depending on depth distribution, never a loss, and it removes an O(n²) cliff and a latent
stack-overflow. Prototyped and verified correct to one bucket quantum. §6.

**4. Is flattening vertices into f64 buffers a big win?** **Yes, but only if done end-to-end.**
Flattening the whole path: 1.8x–3.3x. Flattening only the back half: **no gain**. Best layout is
not raw f64 at all but `SDL_Vertex` bytes written at push time, which is a further 1.16x–1.27x. §7.

**5. Many small draw calls vs few batched ones.** **No meaningful difference.** 1 call 6.89 ms,
2000 calls 7.18–7.43 ms, at 2000 triangles. Per-call overhead ~0.25 µs. Do not architect around
it. §8.

**6. Resolution scaling, software vs accelerated.**
Software: ~100 Mpix/s; 0.8 / 1.8 / 2.9 ms per screenful of overdraw at 320x240 / 480x360 / 640x480.
Accelerated: **free** — 320x240 and 960x720 both 5.9 ms at 2000 triangles.
**Recommended internal resolution: 320x240.** §9.

**Hard budget:** §3 — **2500 triangles/frame at 60 fps**, costing 8.4 ms with one screenful of
fill or 10.8 ms with four, leaving 5.9–8.3 ms for game logic; renderer-only ceiling 5000
triangles; draw calls unbudgeted.

---

## 16. Appendix — raw data

| File | Contents |
|---|---|
| `tools/bench/results/ANALYSIS.txt` | The generated report this document is written from |
| `tools/bench/results/e0_micro.txt` | Hemlock primitive costs (§4) |
| `tools/bench/results/e1_sweep.txt` | Triangle sweep × depth distribution (§2, §15) |
| `tools/bench/results/e2_ablation.txt` | Stage ablation, shipping path (§5) |
| `tools/bench/results/e3_sort.txt` | Sort strategy comparison (§6) |
| `tools/bench/results/e3_verify.txt` | Sort-order correctness / quantisation (§6) |
| `tools/bench/results/e4_path.txt` | Vertex representation + proposed-path ablation (§7) |
| `tools/bench/results/e4_checksum.txt` | Framebuffer identity across all paths (§2) |
| `tools/bench/results/e5_drawcalls.txt` | Draw-call scaling (§8) |
| `tools/bench/results/e6_res.txt` | Resolution scaling, software (§9) |
| `tools/bench/results/e7_fill.txt` | Fill-rate isolation, software (§9) |
| `tools/bench/results/e8_display.txt` | Real display / OpenGL renderer (§2, §9) |
| `tools/bench/results/e9_bucket.txt` | Ordering-table size vs cost (§6) |
| `tools/bench/results/e10_clip.txt` | Clip function costs (§10) |

### Changes made to shared code during this recon
- `wobbleweed/src/sdl.hml` — added `SDL_SetHint` extern; set `SDL_RENDER_SCALE_QUALITY=0` in
  `window_open()`; removed the crashing `SDL_SetTextureScaleMode()` call from `upload_texture()`.
  **This is a bug fix, not a benchmark hack** — see §11. Nothing else in wobbleweed was modified;
  all measurements of the "shipping" path are of the unmodified render code.
