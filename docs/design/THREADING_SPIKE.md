# THREADING SPIKE — can Hemlock parallelise the vertex-transform stage?

**Verdict: (a) IT ALREADY WORKS.** No Hemlock change is required. Measured **4.6×–5.8× p50
speedup** on a faithful 3000-triangle emit microbenchmark at 8–12 workers, with the frame-time
*tail* getting tighter, not looser. **Architecture decision D10 (and rule N10) should be narrowed,
not kept.**

The one ask for the Hemlock team is a **documentation change**, not a compiler change (§7).

All work was done in `/tmp/thread_spike/`. Nothing outside this file was modified.

---

## 0. Method and honesty notes

**RULE 0 — compiler verified.** `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)`; the
`CLAUDE.md` check prints `107` then `5120738502741017561`. PASS.

**RULE T — timing.** `@stdlib/time`'s `clock()` is CPU time and sums across threads, so it cannot
measure parallel wall-clock speedup. Every **speedup** number below is **wall clock**, from
`clock_gettime(CLOCK_MONOTONIC)` via FFI (self-cost measured at **74–92 ns/call**). `clock()` is
used **only** for the CPU-efficiency column, and is labelled as such. Every measurement states the
`loadavg` it was taken at. The box has 24 cores and **intermittent** background load from other
agents; runs at loadavg 2.1, 4.7 and 11.6 are all reported and they agree within ~10%.

**Which statistic.** `min`-of-N is reported because the brief asked for the floor, but for a 60 fps
game **p50 / p99 / max are the honest numbers** and they are reported alongside. Where min and p50
disagree (notably the contended run) the p50 comparison is used, because min-of-N on a serial
baseline can catch a lucky quiet moment and flatter the parallel case.

**Where the benchmark is conservative.** The modelled kernel does the MVP transform, near test,
three perspective divides, viewport scale + pixel snap, guard-band test, backface cross and the
60-byte pack — but *not* `uv_pack`, lighting or fog. It runs at **~930 ns/tri** against the real
`emit_tri_world`'s measured ~2.3–2.5 µs/tri. So the real kernel has **~2.5× more compute per
triangle** than the model, which makes the real compute:dispatch ratio *better*. The speedups below
are a floor, not a ceiling.

---

## 1. Dispatch + join round-trip — "the whole ballgame"

Persistent `ThreadPool`, empty 2-argument task body, 2000 reps × 4 runs, loadavg 2.1–3.8.
**Wall clock.**

| workers | MIN round-trip | MEAN round-trip | % of a 16.67 ms frame (mean) |
|---|---|---|---|
| 2 | 3.98–5.82 µs | 7.65–8.58 µs | 0.05 % |
| 4 | 5.74–8.71 µs | 14.4–18.3 µs | 0.09–0.11 % |
| **8** | **12.2–16.7 µs** | **24.3–32.0 µs** | **0.15–0.19 %** |
| 16 | 31.0–35.6 µs | 50.0–61.6 µs | 0.30–0.37 % |
| 24 | 48.6–53.5 µs | 76.1–96.9 µs | 0.46–0.58 % |

**The floor is ~4 µs at 2 workers and ~12 µs at 8.** The brief's requirement was "tens of
microseconds"; the pool delivers that with room to spare. This was the risk that could have killed
the idea, and it does not.

**Sustained:** 300,000 consecutive frames × 8 workers (2.4 M submits) held a **24.6 µs** mean
round-trip with **zero drift**, and peak RSS was **flat at 2304 KB** across 1 k / 60 k / 300 k
frames. The pool does not leak and does not degrade.

---

## 2. Are concurrent disjoint writes to one shared arena correct?

**Yes — and the docs explicitly guarantee it.**

**Measured.** 8 workers each filled a 60,000-byte disjoint slice of one `alloc()` region with an
index-derived pattern; every byte verified after join. **300 runs (144 MB written), zero bad
bytes** — for *both* `ptr`-passed-as-`submit2`-argument and `ptr`-captured-by-closure. Separately,
the 3000-triangle benchmark's FNV-1a checksum over the whole 180 KB output arena was **identical to
the serial result on every one of 400 frames × 7 worker counts × many runs**.

**`ptr` is genuinely shared, not copied.** The arena address observed inside a pool worker equals
the address in `main` (`133033740324880` both).

**The docs guarantee it, they do not merely fail to forbid it.**
`hemlock/docs/advanced/memory-model.md` § "The unsafe fragment" states:

> **Shared `ptr` / FFI memory.** Tasks share raw pointers freely. You order accesses with channels,
> `join()`, or `@stdlib/atomic`, and you keep the allocation alive until every task is done with it
> (`join()` before `free()`).

That is exactly our pattern. And the soundness is not luck — it follows from the document's own
happens-before edges:

1. Main writes the source data and the MVP, then `submit2` → `work_queue.send` → the worker's
   `recv` (**edge 4, channel send→recv**). So the worker sees everything main wrote.
2. Workers write **disjoint** byte ranges, so no two workers ever touch the same location — there
   is no conflicting access to order.
3. Each worker's writes precede its `result_ch.send` (program order), which happens-before
   `future.get()` returning in main (**edge 4 again**). So main sees every byte.

The chain is complete. **D10's premise — "`spawn()` deep-copies objects, so shared render state is
a trap" — is obsolete for the emit stage**, because the emit stage no longer has objects. It has
one flat byte arena, and flat byte arenas are the case Hemlock explicitly supports.

---

## 3. Does the win survive the boxing rules? — Yes, `submit2` costs nothing

Inspected with `hemlockc -O2 --emit-c`. A worker invoked via `submit2` compiles to:

```c
HmlValue hml_fn_xform_slice(HmlClosureEnv *_closure_env, HmlValue arena, HmlValue w)
```

Parameters are boxed `HmlValue` — **but the generated C is byte-identical to the same function
never passed as a first-class value.** Passing a function to `submit2` adds **zero** boxing.
Parameters are simply never unboxed in Hemlock, which `CLAUDE.md` §4 rule A1 already documents and
which the codebase already works around. Annotated locals unbox correctly in both cases
(`int64_t base`, `double x`, `double y` in the emitted C).

**Conclusion: no evaporating win. The existing A1 copy-params-into-typed-locals idiom is the whole
fix, and it is already the house style.**

---

## 4. The realistic end-to-end microbenchmark

3000 triangles, MVP transform of 3 vertices, near test, 3 perspective divides, viewport scale +
pixel snap, guard-band test, backface cross, 60-byte pack into a shared arena. 400 frames per
configuration. Modelled on `wobbleweed/src/emit.hml` `emit_tri_world` + `pack_v`.
**Wall clock. Checksum-verified against serial on every run.**

### Idle box — loadavg 4.7, `-O3`

| workers | p50 | p99 | max | speedup (p50) | speedup (min) | efficiency (speedup_min / W) |
|---|---|---|---|---|---|---|
| serial | 2778 µs | 3294 µs | 3561 µs | 1.00× | 1.00× | — |
| 4 | 771 µs | 1290 µs | 1313 µs | 3.60× | 3.80× | 95 % |
| 6 | 750 µs | 918 µs | 1138 µs | 3.71× | 5.33× | 89 % |
| **8** | **602 µs** | **789 µs** | **1028 µs** | **4.61×** | **6.64×** | **83 %** |
| **12** | **477 µs** | **662 µs** | **822 µs** | **5.82×** | **6.92×** | **58 %** |
| 16 | 461 µs | 848 µs | 1223 µs | 6.02× | 8.08× | 51 % |

**The tail gets better, not worse.** Serial max is 3561–4792 µs across runs; at 12 workers max is
590–822 µs. Parallelising does not introduce stutter here — it removes it, because the serial
kernel's own worst frames are longer than the parallel version's.

**CPU-time efficiency** (`clock()`, 400 frames, same run): serial 1.121 s; 4w 1.239 s (+11 %);
6w 1.383 s (+23 %); 8w **1.530 s (+36 %)**; 12w 1.675 s (+49 %); 16w 1.965 s (+75 %). We burn
36 % more total CPU at 8 workers to finish 4.6× sooner. On a plugged-in desktop that is a trade
worth making; on a phone it is a battery decision, not a correctness one.

### Contended box — 17 busy cores, loadavg 7.8→9.6, `-O2`

| workers | p50 | p99 | speedup (p50) |
|---|---|---|---|
| serial | 6234 µs | 6338 µs | 1.00× |
| 4 | 1630 µs | 3158 µs | 3.82× |
| 6 | 1975 µs | 2762 µs | 3.16× |
| 8 | 1617 µs | 3501 µs | 3.86× |
| **12** | **1186 µs** | **2432 µs** | **5.26×** |
| 16 | 1311 µs | 2641 µs | 4.76× |

Under heavy contention serial p50 more than doubles (2778 → 6234 µs) while the parallel stage stays
inside ~1.2 ms. **The win does not evaporate when the machine is busy — it gets more valuable.**

### What this means for the actual frame *(extrapolation, not a measurement)*

Nightshade is ~7 ms/frame with transform+pack at 82–88 % (≈5.7–6.2 ms). At the measured p50 speedup
of 4.6× (8 workers), that stage becomes ≈1.3 ms and the frame ≈2.2 ms — headroom goes from ~9.7 ms
to ~14.5 ms. On a target with 2.5× weaker single-thread CPU the serial frame would be ~17.5 ms and
**miss 60 fps outright**; with 6–8 cores it lands back around 4–6 ms. That is the case for treating
this as decisive rather than optional — but it is arithmetic on measured inputs, not a measurement.

---

## 5. Thread-count sweet spot

**6–12 workers. Use 8 as the default; do not exceed 12.**

- Efficiency is ≥83 % through 8 workers and falls off a cliff at 12→16 (58 % → 51 %).
- 16 and 24 workers buy little wall time and cost 75 %+ extra CPU, which matters on a shared box
  and on battery.
- 12 gave the tightest tail on the idle box (max 822 µs) *and* the best p50 under contention.
- The plateau at ~8× is **not** memory bandwidth — it is Amdahl serial work in the submit loop.
  See §6.

---

## 6. Why it plateaus at ~8× — the submit loop is serial on the calling thread

Splitting the round-trip into the submit loop and the join wait (3000 reps, loadavg 3.3, wall clock):

| workers | SUBMIT loop (min) | ns/task | JOIN wait (min) |
|---|---|---|---|
| 2 | 1.91 µs | ~1230 | 0.88 µs |
| 4 | 4.27 µs | ~2250 | 1.01 µs |
| 8 | 10.2 µs | ~2150 | 1.75 µs |
| 12 | 19.0 µs | ~3140 | 2.79 µs |
| 16 | 25.1 µs | ~2660 | 3.65 µs |
| 24 | 42.7 µs | ~3250 | 5.42 µs |

Cost is **~1.2 µs/task floor, ~2.1–3.2 µs/task typical, paid serially on the submitting thread**;
the join wait is comparatively free. Cause is visible in `stdlib/async.hml`: every `submit`/
`submit1`/`submit2` allocates a fresh `channel(1)` **plus** a Future object carrying two closures.

At 8 workers this is 10 µs against 347 µs of slice work — **3 %, irrelevant**. At 24 workers it is
43 µs of un-parallelisable serial work against 116 µs of slice work — **37 %**, which is exactly
why the curve flattens. This is a real, measured explanation for the ceiling, and it is the only
number in this document that a compiler engineer could act on.

---

## 7. Hazards for the actual port — three of them, all confirmed by measurement AND by the docs

Everything below was measured empirically **and** matches `hemlock/docs/advanced/memory-model.md`
exactly. The current `emit.hml` hits two of these.

| | pattern | result | verdict |
|---|---|---|---|
| ✅ | Concurrent **reads** of a shared `array<f64>` written before the pool starts | 200 runs × 8 workers × 20 000 elements, **0 mismatches**, array length intact | **SAFE.** Rule A5 (`array<f64>` for hot float data) survives threading. |
| ✅ | Disjoint writes into one shared `alloc()` arena | 144 MB written, **0 bad bytes**; checksum-identical to serial | **SAFE.** Documented in "The unsafe fragment". |
| ❌ | **Writing a shared mutable module global** (`g_c_sub`, `g_c_written`, `g_c_bf`, `g_c_near`, `g_c_guard`, `g_c_straddle` in `emit.hml`) | expected 160 000 increments, got **27 342–41 053** — **74–83 % of updates lost** | **RACES.** Doc: "Module globals are plain C globals — a concurrent read and write is a C-level data race." **Give each worker its own counter slot in a `ptr`, 64 bytes apart, and sum after the join.** |
| ❌ | **`.push()` to a shared array** (the straddle list, `g_str`/`g_str_n` in `emit.hml`) | **SIGSEGV**, then heap corruption → **SIGABRT in `hml_array_push`** | **HARD CRASH.** Doc: "element storage reallocates under a concurrent reader — use-after-free." **Each worker must append to its own preallocated region; concatenate after the join.** |

### The subtle one: per-frame MVP rewrite

`emit_set_mvp16()` rewrites `g_m0..g_m15` **every frame**, and the pool's worker threads are created
once at startup — so those globals get written while worker threads exist. The memory model's
*normative* rule says a binding reachable from more than one live task must be treated as read-only
after the first spawn, which would forbid this.

But the document's own happens-before edges permit it inside a strict fork-join barrier: worker's
read (frame N−1) → `result_ch.send` → main's `get()` (edge 4) → main's write (program order) →
`work_queue.send` → worker's read (frame N, edge 4). No unordered conflicting pair exists.

**Verified, not just argued: 40 000 frames (2 × 20 000 runs), 8 workers, 4096 values/frame,
rewriting the shared globals between every join and the next submit — zero divergence from the
serial reference.**

**Porting rule: shared globals may be rewritten per frame, but only in the window between the join
of frame N−1 and the submit of frame N. Never while any task is in flight.**

---

## 8. The pattern that works

```hemlock
// startup, once
let g_pool = ThreadPool(8);          // NOT per frame
let g_arena: ptr = alloc(MAX_TRI * 60);
let g_cnt: ptr = alloc(64 * 16);     // per-worker counters, 64 B apart (no false sharing)

// worker: reads shared read-only state, writes ONLY its own disjoint byte range
fn emit_slice(p_lo: i32, p_hi: i32): i32 {
    let lo: i32 = p_lo;  let hi: i32 = p_hi;      // A1: copy params to typed locals
    let m0: f64 = g_m0;  /* ... the 16 MVP elements, A4 ... */
    // ... transform, write 60 bytes at g_arena + tri*60 ...
    // NO writes to module globals. NO .push() to a shared array.
}

// per frame
emit_set_mvp16(...);                  // safe here: all workers idle
let futs = [];
let k: i32 = 0;
while (k < NW) {
    futs.push(g_pool.submit2(emit_slice, (n * k) / NW, (n * (k + 1)) / NW));
    k = k + 1;
}
k = 0;
while (k < NW) { futs[k].get(); k = k + 1; }   // the barrier
// arena is now fully written and visible; sum the per-worker counters here
```

**Ergonomic friction (workaround is free):** `submit` / `submit1` / `submit2` cap at **two**
arguments, and a real kernel wants `(arena, lo, hi, matrix, …)`. The workaround — keep the
read-only state in module globals or capture it by closure, and pass only `(lo, hi)` — is what the
code above does and it costs **nothing** measurable. A `submitN(fn, args_array)` would be nicer but
the measurements do **not** justify asking for it.

---

## 9. What to hand the Hemlock team

**No compiler change is needed.** Do not ask for one. The precise, small, evidence-backed asks are:

1. **Documentation (the only real ask).** `docs/advanced/memory-model.md`'s normative rule —
   *"after the first `spawn`, a binding reachable from more than one live task must be treated as
   read-only"* — is **stricter than the document's own happens-before edges require**, and it
   forbids a pattern that §7 shows to be sound over 40 000 frames: rewriting a shared binding inside
   a strict fork-join barrier. Add one sentence sanctioning it, e.g. *"A shared binding may be
   written between a join that retired every reader and the submit that starts the next batch; the
   join and submit edges order the write against all reads."*
   Also worth adding to `stdlib/docs/async.md`: **the disjoint-slice-into-one-arena pattern is
   supported**, with the three hazards from §7 named. Today a careful reader of the async docs would
   conclude threading a renderer is forbidden, and they would be wrong.

2. **Optional, not needed now — per-submit cost.** `ThreadPool.submit*` costs **~1.2 µs floor /
   ~2.5 µs typical per task, paid serially on the submitting thread**, because each submit allocates
   a fresh `channel(1)` plus a Future object holding two closures (`stdlib/async.hml`). At 8 workers
   this is 3 % of the parallel stage and irrelevant. At 16–24 workers it is 25–43 µs of Amdahl-serial
   work per dispatch and it is **precisely what caps the speedup at ~8×** (§6). If Hemlock ever wants
   the pool to scale past ~12 workers, the fix is to make submit allocate nothing: preallocate one
   result slot per pending task in the pool and return a lightweight handle. **Nightshade does not
   need this.**

3. **Fix two doc bugs found in passing.** `docs/reference/builtins.md` documents
   `ptr_offset(ptr, bytes)`; the real signature is `ptr_offset(ptr, offset, element_size)` — the
   two-argument form does not compile. (`CLAUDE.md` §4 already records this; it is still wrong
   upstream.) And `stdlib/docs/async.md` never mentions that `submit*` is limited to two arguments.

---

## 10. Open — NOT measured

**WASM.** `hemlockc --target wasm --threads` could not be exercised: **`emcc` is not installed on
this box** (`sh: 1: emcc: not found`, C compilation status 127). Whether `ThreadPool` maps onto Web
Workers + `SharedArrayBuffer`, and what the dispatch round-trip costs there, is **completely
unmeasured**. That is the single biggest remaining unknown, since WASM/phone is the target where
parallelism stops being optional. It belongs to the WASM spike, not this one.

**Real integration.** This spike measured a faithful *model* of the emit kernel, not the kernel
itself. `emit_tri_world` still has to be refactored off its shared mutable counters and straddle
list (§7) before any of this can be turned on, and the interaction with the bucket sort in
`batch.hml`, with `SDL_RenderGeometry`, and with the straddle/clip path is untested.

---

## Appendix — recommended change to D10 / rule N10

Rule N10 currently reads: *"`spawn` anywhere in the frame path — it deep-copies objects."*

That is still true of `spawn` and should stay. But it should not be read as banning the pool.
Suggested replacement:

> **N10** — `spawn()` anywhere in the frame path: it deep-copies every argument. Use one persistent
> `ThreadPool` created at startup instead (dispatch+join measured at 12–24 µs for 8 workers). Inside
> a pool worker: **never** write a module global, **never** `.push()` a shared array (both corrupt —
> see `docs/design/THREADING_SPIKE.md` §7). Write only disjoint ranges of a flat `ptr` arena.

---

*Spike run 2026-07-30 on 24 cores, `hemlockc 2.9.1`. Benchmarks in `/tmp/thread_spike/`:
`t1_dispatch.hml` (§1), `t2_disjoint.hml` (§2), `t3_boxing.hml`/`t3b_direct.hml` (§3),
`t4_frame.hml` (§4), `t5_hazards.hml` (§7), `t6_leak.hml` (§1), `t7_perframe_globals.hml` (§7),
`t8_submitcost.hml` (§6). No file outside this one was modified.*
