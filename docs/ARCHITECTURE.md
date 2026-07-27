# NIGHTSHADE — ARCHITECTURE

**Status:** Source of truth. Supersedes every recon document where they disagree.
**Author:** Lead architect, post-recon.
**Read with:** `ENGINE_GAPS.md` (what changes in wobbleweed), `BUILD_PLAN.md` (who builds what, when),
`/CLAUDE.md` (the rules every agent obeys).

---

## 0. DECISIONS — where recon disagreed, and what we are doing

Recon delivered seven strong documents that conflict in eleven places. Each is settled here. Do not
relitigate; if you think a decision is wrong, change it *in this file* and say so.

| # | Conflict | **Decision** | Why |
|---|---|---|---|
| D1 | Triangle budget: 2200 (gamedesign) / 2500 (perf) / ~8000 (wobbleweed-api) | **2500 steady, 3500 hard clamp, 5000 renderer ceiling** | perf measured 2.88 µs/tri marginal on the *proposed* pipeline including fill, sort, and present. The 8000 figure came from `bench_flat.hml`, which has no sort, no clip, no lighting, no fog, one draw call — it is a ceiling, not a budget. gamedesign's 6.6 µs/tri was derived from the *unfixed* pipeline. 2500 is the measured, defensible number and it leaves 5.9–8.3 ms for the sim. |
| D2 | Draw distance: 140 m (gamedesign) vs **`FOG_FAR` ≤ 72 m** (artdir) | **`FOG_FAR` ≤ 72 m, hard.** Far plane = `FOG_FAR * 1.06`. | artdir tied it to arithmetic: 120 m of ground alone is 1414 triangles, 57 % of the whole budget, before a single enemy. Ground tris ≈ `(π/4)·FOG_FAR²/16·2`. **Consequence, accepted:** Longshadow falloff retunes `r0/r1` from 55/110 to **34/68 m**, "max useful" 72 m; Chalk Downs' "140 m sightline" becomes 72 m. gamedesign's weapon table §2.4 is amended in `src/sim/weapons.hml` accordingly. |
| D3 | Audio: hand-rolled mixer on `SDL_QueueAudio` (sdl-ffi) vs **SDL2_mixer** (HOST_FACTS) | **SDL2_mixer**, `Mix_QuickLoad_RAW` on Hemlock-synthesized PCM buffers. | HOST_FACTS is later and orchestrator-verified on this box: 8/8 probes pass, 6 overlapping voices, `Mix_SetPanning` works, interpreted and compiled. C does the mixing; we spend zero frame budget on it. sdl-ffi's advice was written before `libsdl2-mixer-dev` was installed. `SDL_QueueAudio` stays as a documented fallback behind the same `audio.hml` interface. |
| D4 | PNG reader: "write one, it unblocks all art" (wobbleweed-api) vs "ship zero image files" (artdir) | **No PNG reader. All art is procedural.** PNG *writer* stays, for screenshots. | artdir's position is stronger creatively and removes a whole subsystem. It also removes the atlas-authoring pipeline, the asset-hot-reload problem, and the "artist can't contribute" objection (there is no artist; there is `texgen.hml`). "The entire game's art is 1400 lines of code" is a real asset. |
| D5 | Meshes: OBJ files (gamedesign/wobbleweed-api) vs procedural | **Procedural.** `src/art/meshgen.hml` builds every mesh at boot with a tiny box/prism/lathe/fan DSL. `assets/` stays empty. The engine keeps `obj.hml` as a generic feature; Nightshade does not import it. | Same reasoning as D4, plus it dodges the OBJ loader's real defects (UVs discarded, no groups, no `.mtl`, CRLF bug) and makes per-instance variation free. At ≤ 260 tris an asset, a parametric builder is *better* than a modelling tool. |
| D6 | Day cycle: 16 min (gamedesign) vs 24 min (artdir) | **16 minutes.** artdir's 7 keyframes are remapped onto gamedesign's Dawn 2 / Day 7 / Dusk 2 / Night 5 by phase fraction. | gamedesign owns pacing; artdir owns the colours. Both survive. Mapping table is in `src/art/tod.hml`. |
| D7 | Fog via vertex alpha "is free" (artdir) vs "every blended screenful costs 0.8 ms in software" (perf) | **Tint-multiply always; alpha only in the far band.** `a = 255` when `f < 0.35`; alpha ramps 255→`255*(1-FOG_ALPHA_MAX)` over `f ∈ [0.35, 1]`. | artdir's compositing argument is correct and the far band is exactly where it matters. But a full-screen blend path in the software fallback is real money. Restricting alpha to `f > 0.35` keeps ~80 % of on-screen pixels on the opaque path. **This must be measured** — acceptance criterion on task W2-7. |
| D8 | Texture format: `ARGB8888` (perf) vs `RGBA32` (sdl-ffi) | **`RGBA32` (376840196) for atlases; `ARGB8888` (372645892) for the render target.** | Both are renderer-native (so neither trips the conversion-texture crash class). `RGBA32` == `ABGR8888` on LE and its *memory byte order is R,G,B,A* — the natural order for procedural generators, verified by pixel readback. The render target is never CPU-touched, so use the format HOST_FACTS already verified end-to-end for `SDL_TEXTUREACCESS_TARGET`. |
| D9 | Chunky pixels: `SDL_RenderSetLogicalSize` (today) vs offscreen target | **Offscreen 320×240 `TARGET` texture, `SDL_RenderCopyEx` upscale.** | Logical size scales *rasterization*, so polygon edges are smooth at window resolution — the PS1 look is absent on the shipping path. sdl-ffi proved the full target→upscale→shake→additive→HUD chain works identically on software and GPU. It is also the only place to hang post-FX. |
| D10 | Parallelism: "4x untapped, the biggest remaining lever" (perf) | **Single-threaded v1. `spawn` is banned in the frame path.** | net recon verified `spawn()` deep-copies objects, which makes shared render state a trap. 2500 tris fits single-threaded with headroom. Revisit only if a measured budget breach cannot be solved by `FOG_FAR`. |
| D11 | Painter sort granularity: per-triangle bucket (perf) vs per-chunk (wobbleweed-api §12.1) | **Per-triangle bucket sort, NB = 2048, key = view-space depth `w`.** | 0.39 ms at 2000 tris, input-order independent, correct to a 3.5 cm quantum over a 72 m range. Per-chunk sorting cannot order a tree against the ground it stands on. Layers (below) do the coarse work; the bucket does the fine work. |

**One more decision, unprompted by conflict:** the world is a **heightfield, not voxels**. gamedesign
cut block-digging; without digging there is no reason to pay for voxel storage or voxel meshing. This
deletes an entire subsystem. `buffer`-of-`u16` heightmaps replace `array<i32>` voxel chunks and the
hemlock-lang footprint advice (A6) applies to heightmaps and light bakes instead.

---

## 1. THE SHAPE OF THE THING

Three repositories, three responsibilities, one hard rule between them.

```
/home/nbeerbower/Projects/wobbleweed     GENERIC retro-3D engine. Knows about triangles,
                                          textures, sound, input, time. Knows NOTHING about
                                          lanterns, Husks, ember, or violet.
/home/nbeerbower/Projects/nightshade     THE GAME. Owns every constant with a name from the GDD.
/home/nbeerbower/Projects/gn.hml         WebSocket transport. Imported ONLY from src/net/. v2.
```

> **RULE R1 — The engine must never learn a game word.** If a wobbleweed symbol contains `lantern`,
> `husk`, `ember`, `shade`, `wisp`, or a specific colour, it is in the wrong repository. The test:
> could a different PS1-style game use this file unmodified? If no, it belongs in nightshade.

The engine exposes *parameters*; the game supplies *values*. `shade.hml` has a `RenderEnv` with
`sun_r/sun_g/sun_b/fog_near/fog_far/...`. `tod.hml` fills it from the ART_BIBLE keyframe table. The
engine never sees `#FF9E44`.

### 1.1 The three walls

```
        ┌──────────────────────────────────────────────────────┐
        │ src/sim/**        NO SDL. NO wobbleweed. NO net.      │  ← runs headless, is the server
        │                   NO @stdlib/random. NO wall clock.   │
        └──────────────────────┬───────────────────────────────┘
                               │ reads (never writes)
        ┌──────────────────────▼───────────────────────────────┐
        │ src/render/**     reads RenderSnapshot + RenderEnv.   │  ← may import wobbleweed
        │                   MAY NOT import src/net/**.          │
        │                   MAY NOT write any sim structure.    │
        └──────────────────────┬───────────────────────────────┘
                               │
        ┌──────────────────────▼───────────────────────────────┐
        │ src/game/**       the only place that imports all     │
        │                   three. Owns the loop.               │
        └──────────────────────────────────────────────────────┘
        src/net/**   may import src/sim/** (field names) + gn.hml. Nothing else.
        src/art/**   may import wobbleweed + src/core/**. Pure generators, no state.
        src/core/**  leaf. Imports @stdlib only.
```

Enforced by `tools/ci_imports.sh` (grep). It is crude and it catches the mistake every time.

The practical test, from net recon and adopted verbatim: **`hemlock tools/simtest.hml` must run
10 000 ticks with no SDL linked.** If it cannot build, the wall is broken.

### 1.2 Two naming rules that are load-bearing, not stylistic

Both come from verified compiler behaviour, and both are enforced by `tools/ci_imports.sh`.

1. **Every top-level variable is `g_`-prefixed. No local is ever `g_`-prefixed.**
   `codegen_stmt` refuses to unbox a local by **name match against top-level variables, with no scope
   awareness**. One `let acc = 0;` at file scope makes *every* function-local `acc` in the entire
   program a boxed `HmlValue` — measured **423 ms vs 222 ms** for two byte-identical functions whose
   only difference is a variable name. There is no warning and no diagnostic.

2. **Every function parameter is `p_`-prefixed.**
   `hemlockc`'s inliner does not alpha-rename inlined bodies. When a caller has a local whose name
   matches a callee's parameter, the inlined arithmetic binds to the caller's *boxed* local and the
   emitted C is invalid (`HEMLOCK_ISSUES.md` H-1 — fixed only on branch
   `fix/inliner-param-name-collision`, **not on `main`**). `fn mix(s: i32)` and `let s = ...` at a call
   site is a hard build failure; `fn mix(p_s: i32)` never is. The failure is loud rather than silent,
   which is the good outcome — but `s`, `x`, `i`, `n`, `v` are exactly the names both a math helper
   and its caller will reach for, so this *will* happen.

   Note the interaction with unboxing: parameters are never unboxed anyway, so the first line of every
   hot function is `let x: f64 = p_x;` — which the `p_` convention makes read naturally.

---

## 2. DATA LAYOUT — the measured foundation

Everything in this section is dictated by numbers, not taste.

### 2.1 The three costs that decide everything

| Fact | Measured | Source |
|---|---|---|
| Object literal, 8 fields | **260 ns** (~32 ns/field) | PERF §4, HEMLOCK §3 |
| Flat array write / `ptr_write_f32` | **3.5 ns / 7.5 ns** | PERF §4 |
| `array.sort(closure)`, 2000 tris, coplanar depths | **143 ms** | PERF §6 |
| Bucket counting sort, same | **0.39 ms** | PERF §7 |
| `array<i32>` per element vs `buffer(u8)` | **16.03 B vs 1.03 B** | HEMLOCK §2 |

**One object allocation costs as much as 15–30 flat writes.** That single ratio produces every rule
below.

### 2.2 Container policy

| Data | Container | Why |
|---|---|---|
| Per-vertex render data, per-frame | **raw `ptr` written as `SDL_Vertex` bytes** | `flatsdl` beat `flatraw` by 16–27 % and `obj` by 1.8–3.3× (PERF §7). Flush becomes a `memcpy`. |
| Per-triangle metadata (depth, tex, layer) | **parallel Hemlock `array`s** | array indexing has an inlined fast path; `ptr_deref_i32` does not (PERF §6, HEMLOCK §4). |
| Sort counters (`counts[NB+1]`) | **Hemlock `array<i32>`** | measured *faster* than a raw buffer: 0.78 vs 0.93 ms at 8000 tris. |
| Entity state (≤ 512 entities) | **SoA parallel `array<f64>` / `array<i32>`** | 0.150 vs 0.265 ms/tick (HEMLOCK §6). Also mandatory for history/snapshot (net §7.3). |
| Particles (≤ 512) | **SoA parallel `array<f64>`** | same. |
| Chunk heightmaps, baked light, biome ids | **`buffer` of `u16`/`u8`** | 16× footprint saving; access only ~10 % slower. |
| Cached chunk meshes | **one `ptr` arena, 24 B/vertex** | uploaded once at build, transformed per frame. |
| Setup-time math (camera, matrices, tool code) | `object` via `vec.hml` | fine; not per-frame. |

### 2.3 The vertex buffer contract — **the single most important interface in the project**

`emit.hml` (producer) and `batch.hml` (consumer) never share a struct. They share this byte layout.
Both are written against this table; neither may change it without changing this document.

**One `Batch` owns, allocated once at startup, never reallocated:**

```
b.vbuf   : ptr             cap * 60 bytes   — 3 × SDL_Vertex, written at push time
b.obuf   : ptr             cap * 60 bytes   — gather target handed to SDL_RenderGeometry
b.depth  : array<f64>      cap              — VIEW-SPACE depth (clip w). Larger = farther.
b.tex    : array           cap              — SDL_Texture* (ptr) or null
b.order  : array<i32>      cap              — sort permutation, written by the sort
b.counts : array<i32>      NB + 1           — counting-sort histogram (NB = 2048)
b.n      : i32                              — triangles pushed this frame
b.cap    : i32                              — HARD LIMIT. Overflow drops and counts. Never smashes.
```

**`SDL_Vertex`, 20 bytes, little-endian** (verified against the real ABI dump):

| Offset | Type | Field | Note |
|---:|---|---|---|
| 0 | f32 | `pos.x` | screen px, **already `floor(v + 0.5)`** — the PS1 jitter, keep it |
| 4 | f32 | `pos.y` | ditto |
| 8 | u8 | `color.r` | lighting × fog tint, 0..255 |
| 9 | u8 | `color.g` | |
| 10 | u8 | `color.b` | |
| 11 | u8 | `color.a` | **fog alpha — no longer hardcoded 255** |
| 12 | f32 | `uv.u` | affine (that is the warble; it is a feature) |
| 16 | f32 | `uv.v` | |

Triangle *k* occupies `vbuf[k*60 .. k*60+59]`: vertex A at `+0`, B at `+20`, C at `+40`.

**Invariants (violating any of these is a bug, not a style question):**

1. `SDL_Vertex` is 2D. The vertex `z` does not exist. **Depth lives only in `b.depth[k]` and is only
   ever the painter key.** That makes the key a free choice, and the choice is **view-space `w`**
   (3.5 cm quantum everywhere) not NDC z (35 m quantum at 100 m). PERF §6.
2. Screen x/y stay pixel-snapped.
3. The sky is pushed with `depth = FAR` so it sorts first. Never `z = 2.0` (an NDC-space value).
4. The viewmodel is pushed with `depth = 0.05` so it sorts last within `LAYER_WORLD` and needs no
   layer of its own.
5. Nothing writes into `vbuf` except `emit.hml`, `quad.hml`, `billboard.hml`, and `font.hml`, and
   they all go through `batch_reserve()` which returns a cursor and bumps `b.n`, or returns `-1` on
   overflow. **`b.cap` is enforced.** (wobbleweed-api §11.3 was a heap-corruption bug.)

### 2.4 Layers

Blend mode is a property of an SDL texture, therefore **blend mode is the material model**
(ART_BIBLE T3). Four textures, four batches, four flushes:

| # | Batch | Texture | Blend | Sorted? | cap | typical |
|---|---|---|---|---|---|---|
| 0 | `LAYER_SKY` | `TEX_SKY` 512×160 | none | no | 16 | 2–4 tris |
| 1 | `LAYER_WORLD` | `ATLAS_WORLD` 256×256 | `BLEND` | **bucket sort** | 3500 | ~1900 tris |
| 2 | `LAYER_FX` | `ATLAS_FX` 128×128 | `ADD` | bucket sort | 768 | ~120 tris |
| 3 | `LAYER_HUD` | `ATLAS_HUD` 128×128 | `BLEND` | no (insertion order) | 768 | ~250 tris |

Result: **5–7 draw calls per frame.** Note this is chosen for *correctness and art direction*, not
performance — PERF §8 proved 2000 draw calls cost 0.3 ms more than 1. Do not add a fifth texture, and
do not build a batching scheme to reduce draw calls. Neither buys anything.

---

## 3. THE FIXED-TIMESTEP SIM / INTERPOLATED RENDER SPLIT

Non-negotiable, and it is cheap now and a rewrite later (net §16, anti-patterns 1, 7, 19).

```hemlock
// src/game/main.hml — the whole loop, verbatim in shape
let g_acc: f64 = 0.0;
let g_prev = clock_now();          // engine time.hml, SDL_GetPerformanceCounter
let g_tick = 0;

while (g_running == 1) {
    let now = clock_now();
    let frame_ms: f64 = clock_ms_between(g_prev, now);
    g_prev = now;
    if (frame_ms > 250.0) { frame_ms = 250.0; }     // spiral-of-death clamp
    g_acc = g_acc + frame_ms;

    input_sample(g_input);                           // EVERY frame: accumulate mouse, latch clicks

    while (g_acc >= TICK_MS) {
        let cmd = input_make_command(g_input, g_tick);   // quantized AT CONSTRUCTION
        transport_send_command(g_net, cmd);              // loopback in v1
        server_tick(g_server, g_tick);                   // authoritative sim_step
        client_apply(g_client, g_tick);                  // v1: read back; v2: predict+reconcile
        g_acc = g_acc - TICK_MS;
        g_tick++;                                        // ++ not +1 (2.3x, HEMLOCK A11)
    }

    let alpha: f64 = g_acc / TICK_MS;
    snapshot_build(g_rsnap, g_world, alpha);         // interpolated, SoA, zero allocation
    frame_render(g_rsnap);                           // reads ONLY g_rsnap and g_env
}
```

Rules that make this worth doing:

- **`TICK_DT` is a compile-time constant** (`1.0/60.0`). No gameplay function ever sees a measured
  delta. Variable-dt physics is not reproducible, and prediction is a reproduction problem.
- **The sim loop runs 0, 1, or N times per frame.** Any system that assumes one step per frame is
  broken and will prove it the first time someone alt-tabs.
- **`clock_now()` is the only clock.** Never `time_ms()`, never a frame counter, never wall clock.
- **Render never mutates sim state.** Structurally: `frame_render` receives `g_rsnap`, not `g_world`.
- **`sim_apply_command(world, slot, cmd)` is pure w.r.t. the world.** No sound, no particle, no
  shake, no `print`. Cosmetic effects come from a separate `sim_effects()` pass that is skipped when
  `world.replaying == 1`. Replaying 8 commands must produce 0 sounds. (net §9.3; CI test.)
- **Every field of the movement model lives in `PredictedState`.** Coyote time, slide timer, bhop
  window — all of it. A movement variable outside that struct is a rubber-band bug in v2 that only
  reproduces in one movement state.

### 3.1 RenderSnapshot

```
RenderSnapshot (SoA, preallocated to MAX_RENDER_ENTS = 256, reused, zero allocation per frame)
  count                    : i32
  id[]                     : array<i32>   stable entity id (negative = client-local cosmetic)
  x[], y[], z[]            : array<f64>   INTERPOLATED between tick n-1 and n by alpha
  yaw[], pitch[]           : array<f64>   INTERPOLATED
  model[], frame[]         : array<i32>
  tint[]                   : array<i32>   packed 0xRRGGBB
  flags[]                  : array<i32>   bit 0 visible, 1 hit-flash, 2 muzzle, 3 dissolve, ...
  cam_x/y/z, cam_yaw, cam_pitch, cam_roll : f64     roll = view kick, client-only
  cam_fov                  : f64          hip/ADS/sprint lerp
```

In v1 `snapshot_build` interpolates between the previous and current *local* tick. In v2 the same
function, same signature, same output, interpolates between two *network* snapshots at
`latest - INTERP_DELAY_MS`. That substitution being a one-function change is the entire reason this
struct exists.

---

## 4. THE FRAME GRAPH — exactly what happens, in order

```
── SIM (0..N times, fixed dt, see §3) ─────────────────────────────────────────
  1  input_sample                          every frame, before the tick loop
  2  input_make_command                    once per tick, quantized
  3  sim_step(world, tick):                fixed order, treat as API (net §18.2)
       a apply queued commands (player-slot order, then seq)
       b movement integration + terrain/AABB collision
       c weapons: fire, reload, cooldowns, recoil_aim
       d projectiles
       e AI steering
       f damage resolution + death
       g pickups / interactions / lantern channel / block placement
       h day-cycle tick, chunk streaming decisions
       i history_capture
       j sim_effects  (SKIPPED when world.replaying == 1)

── SNAPSHOT ───────────────────────────────────────────────────────────────────
  4  snapshot_build(g_rsnap, world, alpha)      interpolate; zero allocation
  5  fx_update(frame_ms)                        client-only particles, decals, shake, streaks
  6  tod_eval(g_env, world.day_t, weather)      fills the engine RenderEnv (sun/ambient/fog/mist)
  7  skygen_rebake_slice()                      20 rows/frame if ToD moved; SDL_UpdateTexture rect

── VIEW ───────────────────────────────────────────────────────────────────────
  8  view_build(g_view, g_rsnap)                camera basis, shake, recoil_view, FOV lerp
  9  emit_set_mvp(g_view.mvp)                   hoists all 16 matrix elements into f64 locals
 10  frustum_from_mvp(g_frustum, g_view.mvp)    Gribb–Hartmann, 6 planes

── EMIT (all four batches reset first; no allocation past this line) ───────────
 11  batch_reset × 4
 12  emit_sky(SKY)                              2–4 tris, depth = FAR, u by yaw, v by pitch
 13  terrain_emit(WORLD)                        ring walk → frustum_sphere per chunk → LOD pick
                                                → emit cached chunk vertex buffer
 14  entity_emit(WORLD)                         enemies, NPCs, props, pickups; LOD by distance
                                                + one contact-shadow quad per entity (mandatory)
 15  viewmodel_emit(WORLD)                      depth = 0.05, fog f = 0, never culled
 16  fx_emit(FX)                                particles, tracers, muzzle, glow cards, loot beams
 17  (overflow of any batch increments a stat and drops the triangle — never corrupts)

── RASTER ─────────────────────────────────────────────────────────────────────
 18  target_begin()                             SDL_SetRenderTarget(320×240 ARGB8888 TARGET)
 19  sdl_clear(sky zenith colour)               so a dropped sky frame is never black
 20  batch_flush(SKY)                           insertion order, 1 draw call
 21  batch_sort_flush(WORLD)                    bucket sort NB=2048 on view depth, then tex runs
 22  batch_sort_flush(FX)                       additive
 23  postfx_emit(HUD) → composite MOD quad, vignette ring (16 tris), speed lines, flashes
 24  hud_build(HUD)                             §9 of ART_BIBLE, ≤ 250 tris
 25  batch_flush(HUD)                           insertion order
 26  target_end(); target_present()             SDL_RenderCopyEx integer upscale + screen shake
 27  sdl_present()
 28  stats_frame_end()                          per-stage timers + counters, always compiled in
```

**Ablation is mandatory from day one.** `stats.hml` keeps per-frame counters for: triangles
submitted per layer, triangles rejected by frustum / backface / near-plane / guard band, triangles
sent to the slow clip path, batch overflows, draw calls, and the timing of stages 11–17, 21, 22, 26.
The only reason PERF.md could be written is that the pipeline was ablatable. Keep it that way.

---

## 5. FILE LIST — every `.hml` that will exist

**Ownership rule:** within a wave, every file has exactly one owning task. No two implementation
agents ever edit the same file in the same wave. The owning task id is in `BUILD_PLAN.md`.

### 5.1 `wobbleweed/src/` — the engine (shipping path)

| File | Purpose | Public exports |
|---|---|---|
| `sdl.hml` | The entire OS surface: SDL2 + SDL2_mixer FFI, window/renderer lifecycle. **Every extern grouped under its own `import`** (extern binds to the most recent import). | `window_open, window_close, sdl_clear, sdl_present, draw_tris_at, create_target, set_target, copy_ex, create_static_tex, update_tex, update_tex_rect, set_tex_blend, set_draw_blend, read_pixels, poll_events, keystate, held, set_relative_mouse, rel_mouse_delta, mouse_buttons, show_cursor, perf_counter, perf_freq, set_hint, sdl_error`; constants `KEY_*`, `SC_*`, `BLEND_NONE/BLEND/ADD/MOD`, `FMT_RGBA32`, `FMT_ARGB8888`, `TEXACCESS_TARGET/STATIC/STREAMING`; mixer: `mix_open, mix_alloc_channels, mix_quickload_raw, mix_play, mix_set_panning, mix_set_volume, mix_playing, mix_halt, mix_close` |
| `time.hml` | Monotonic clock + fixed-step accumulator. | `clock_now, clock_ms_between, clock_new, clock_accumulate, FIXED_TICK_MS` |
| `stats.hml` | Per-frame counters and stage timers. Compiled into shipping builds. | `stat_reset, stat_inc, stat_add, stat_begin, stat_end, stat_get, stat_report_string, STAT_*` (index constants) |
| `vec.hml` | vec3 + row-major 4×4 for **setup-time** use. Extended with the FPS primitives recon found missing. | existing + `mat_rot_z, mat_invert_rigid, v_lerp, v_dist, v_dist2, v_reflect, ray_aabb, ray_plane, aabb_overlap, mat_look_dir` (yaw/pitch basis — never `mat_look_at`, which degenerates at ±90°) |
| `frustum.hml` | Gribb–Hartmann 6-plane extraction + tests. Flat `array<f64>` of 24, no objects. | `frustum_from_mvp, frustum_sphere, frustum_aabb` |
| `clip.hml` | **Allocation-free** near/guard-band predicates + a rare slow path. Returns a status code; writes through to caller buffers. Never returns `[[a,b,c]]`. | `CLIP_IN, CLIP_OUT, CLIP_STRADDLE, clip_near_status, clip_rect_status, clip_near_slow, clip_rect_slow` |
| `shade.hml` | `RenderEnv`: the light + fog parameter block, and the scalar shade/fog kernel used by `emit.hml`. Generic: colours are inputs. | `env_new, env_set_sun, env_set_ambient, env_set_bounce, env_set_fog, env_set_mist, env_add_light, env_clear_lights, env_field_*` (flat `array<f64>` accessors so the hot loop reads an array, not an object) |
| `batch.hml` | The 4-layer flat triangle pool: reserve, bucket sort, texture-run flush. **Replaces `geom.hml`.** | `batch_new, batch_reset, batch_reserve, batch_commit, batch_flush, batch_sort_flush, batch_overflow_count, LAYER_SKY/WORLD/FX/HUD, VSTRIDE, TSTRIDE, NB` |
| `emit.hml` | The hot kernel: transform + project + light + fog + pack, on native `f64` locals, straight into `vbuf`. Zero objects. | `emit_set_mvp, emit_set_env, emit_set_viewport, emit_mesh_buf, emit_quad_world, emit_tri_world, emit_stats` |
| `quad.hml` | Screen-space quads (no projection): HUD, full-screen overlays, bars. | `quad_screen, quad_screen_uv, quad_fullscreen, quad_ring` |
| `billboard.hml` | World-anchored camera-facing quad, sized `world_size * proj_scale / w`. | `billboard_world, billboard_stretched` (for tracers/rain) |
| `atlas.hml` | RGBA8 atlas buffer, cell UV rects **with half-texel inset**, upload, dirty-rect update. | `atlas_new, atlas_px, atlas_cell_uv, atlas_upload, atlas_update_rows, atlas_free` |
| `font.hml` | Generic bitmap font: register glyphs from packed bitfields, blit into an atlas, emit text as quads. | `font_new, font_add_glyph, font_bake, font_text, font_text_shadowed, font_width` |
| `mesh.hml` | Runtime mesh format (one flat `ptr`, 24 B/vertex: pos f32×3, uv f32×2, rgb u8×3, pad) + builder + instanced emit. | `mesh_new, mesh_begin, mesh_vert, mesh_tri, mesh_end, mesh_emit, mesh_emit_yaw, mesh_tri_count, mesh_bake_light` |
| `target.hml` | Offscreen 320×240 render target, integer upscale present, shake offset. | `target_new, target_begin, target_end, target_present, target_set_shake` |
| `input.hml` | Held/pressed/released keys, relative mouse with **graceful failure under the dummy driver**, buttons, wheel. Action-map layer. | `input_new, input_sample, input_down, input_pressed, input_released, input_mouse_dx, input_mouse_dy, input_button, input_wheel, input_set_relative` |
| `audio.hml` | SDL2_mixer device + a chunk table that **owns the PCM buffers forever** (`Mix_QuickLoad_RAW` does not copy). | `audio_init, audio_shutdown, audio_register_pcm, audio_play, audio_play_panned, audio_set_volume, audio_stop_all, audio_voices_active` |
| `engine.hml` | init/shutdown ordering, the engine handle, texture-destroy sweep. | `engine_init, engine_shutdown, engine_handle` |
| `png.hml` | PNG **writer** (unchanged). Screenshots only. | `write_png` |
| `obj.hml` | OBJ loader (unchanged). Generic engine feature; Nightshade does not import it. | `load_obj, palette` |
| `texture.hml` | RGBA8 procedural texture container (converted from RGB24). | `tex_new, tex_set, tex_get, tex_fill, tex_blit` |

**Frozen legacy — present, buildable, and forbidden to Nightshade:**
`geom.hml`, `framebuffer.hml`, `raster.hml`, `sky.hml`, `postfx.hml`, `scene.hml`, `scene_gpu.hml`.
They keep the existing examples and the `tools/bench` regression comparisons alive. Each gets a
one-line `// LEGACY — not on the shipping path. See ENGINE_GAPS.md.` header and nothing else.
`tools/ci_imports.sh` fails the build if anything under `nightshade/src/` imports one.

### 5.2 `nightshade/src/core/` — leaf modules (import `@stdlib` only)

| File | Purpose | Exports |
|---|---|---|
| `config.hml` | Every tunable constant, all `g_`-prefixed. Resolution, tick, budgets, `FOG_FAR` cap, chunk size, entity caps, atlas sizes. **Nothing else in the game hardcodes a number that appears here.** | `g_TICK_HZ, g_TICK_MS, g_TICK_DT, g_RES_W, g_RES_H, g_MAX_TRIS_WORLD, g_MAX_TRIS_FX, g_MAX_TRIS_HUD, g_FOG_FAR_CAP, g_CHUNK_M, g_CHUNK_GRID, g_RING_RADIUS, g_MAX_ENTS, g_MAX_PARTICLES, g_NB_BUCKETS, ...` |
| `mathx.hml` | Hand-inlined scalar helpers + the noise stack. **All hashing in `i64` with an explicit 32-bit mask** (i32 `*` throws). | `xhash2, xhash3, h01, vnoise, fbm2, bayer4, smoothstep, clampf, lerpf, minf, maxf, absf, deg2rad` |

### 5.3 `nightshade/src/art/` — the procedural art pipeline

| File | Purpose | Exports |
|---|---|---|
| `palette.hml` | Every colour from ART_BIBLE §3, as `g_`-prefixed packed `i32` (0xRRGGBB) plus `pal_r/g/b` unpackers. **Nothing anywhere else names a colour.** | `g_GRASS_MID, g_NS_CORE, g_UI_AMBER, … (≈110 constants), pal_r, pal_g, pal_b, pal_pack, pal_lerp` |
| `tod.hml` | The ART_BIBLE §5 keyframe table remapped onto the 16-minute day (D6), interpolation, weather overrides, lightning. Writes the engine `RenderEnv`. | `tod_eval, tod_phase, tod_sky_keys, tod_set_weather, tod_lightning_fire, TOD_DAWN..TOD_DEEP, WX_CLEAR/OVERCAST/RAIN/STORM/BLOOM` |
| `texgen.hml` | ART_BIBLE §7.2 primitives + §7.3 generators + the §7.4 8×8 packer → `ATLAS_WORLD` (256×256). | `texgen_build_world_atlas, tg_grass, tg_dirt, tg_stone, tg_wood, tg_metal, tg_concrete, tg_leaf, tg_snow, tg_ramp_pick, tg_grain, CELL_*` (cell index constants) |
| `skygen.hml` | ART_BIBLE §11 panorama: dithered gradient, two cloud layers with lit-top/shadow-bottom, sun/moon/halo, star field with a fixed seed. Incremental re-bake, 20 rows/frame. | `skygen_build, skygen_mark_dirty, skygen_rebake_slice, skygen_tex` |
| `fxgen.hml` | `ATLAS_FX` (128×128, 16×16 cells): muzzle ×3, tracer, sparks, explosion ×6, ember, smoke ×3, glow cards ×2, enemy eye, loot beam, rain streak, lightning, dust, splash, XP mote. | `fxgen_build_atlas, FX_MUZZLE_0, FX_TRACER, FX_GLOW_S, FX_GLOW_L, …` |
| `hudgen.hml` | `ATLAS_HUD` (128×128): `FONT_MICRO` 4×6 and `FONT_BIG` 8×12 as packed bitfields, icons, crosshair parts, minimap chrome, vignette gradient strip. | `hudgen_build_atlas, hud_font_micro, hud_font_big, HUD_ICON_*` |
| `meshgen.hml` | The procedural mesh DSL and every world mesh: tree LOD0/1/2, bush, rock, crate, barrel, lantern post, enemy ×6 (rigid parts), NPC, weapon viewmodels ×6. Bakes vertex colour + AO at build time. | `mg_box, mg_prism, mg_taper, mg_fan_disc, mg_lathe, meshgen_build_all, MESH_TREE0, MESH_HUSK, MESH_SPARROW_VM, …` |
| `biome.hml` | Per-biome palettes, texture cell selection, prop density, `FOG_FAR` override, triangle-budget policy. (Wave 4.) | `biome_of, biome_params, BIOME_HOLLOWFIELD..BIOME_DEEPSHADE` |
| `weather.hml` | Weather state machine + rain/snow/fog-bank emitters. (Wave 4.) | `weather_step, weather_emit` |
| `hubgen.hml` | Ember Hollow's modular building meshes and layout. (Wave 4.) | `hubgen_build, hub_layout` |

### 5.4 `nightshade/src/sim/` — the simulation (headless; the future dedicated server)

| File | Purpose | Exports |
|---|---|---|
| `rng.hml` | Seeded xorshift128 with **separate streams**, seeded from `(world_seed, stream_id, tick, entity_id)`. `@stdlib/random` is banned here. | `rng_seed, rng_next, rng_f01, rng_range, rng_pick, RNG_LOOT, RNG_SPREAD, RNG_AI, RNG_WORLDGEN, RNG_DIRECTOR` |
| `command.hml` | `InputCommand` (9 integers, **no bools, no floats, no nulls**) + button bits + quantize/dequantize. Quantized **at construction** so prediction uses the exact value the server will. | `cmd_new, cmd_set, cmd_yaw, cmd_pitch, cmd_move_x, cmd_move_y, BTN_FIRE..BTN_INV, q_ang, dq_ang` |
| `world.hml` | The SoA `World`: identity / transform / state / owner-only / server-only groups, sparse-set ids, `world_spawn`/`world_despawn` (swap-with-last), kind-partitioned id ranges. | `world_new, world_spawn, world_despawn, world_slot_of, world_id_of, world_reset, KIND_*, ID_PLAYER_BASE, ID_AI_BASE, ID_PROJ_BASE, ID_PICKUP_BASE` |
| `history.hml` | Transform ring buffer, `HISTORY_TICKS = 32`, flat `px[(slot*32)+ring]`. Called every tick even in v1. | `history_new, history_capture, history_sample` |
| `chunk.hml` | Chunk storage: `buffer(u16)` heights (cm), `buffer(u8)` biome + baked light, sparse edit overlay, dirty flags, LRU cache. | `chunk_key, chunk_get, chunk_height_at, chunk_normal_at, chunk_set_edit, chunk_evict, CHUNK_N` |
| `worldgen.hml` | Pure `f(seed, cx, cz) → chunk`. 3-octave value noise height, temperature/moisture biome fields, per-chunk POI hash roll. No I/O, no globals. | `worldgen_chunk, worldgen_height, worldgen_biome, worldgen_poi_roll, worldgen_shade_tier` |
| `daycycle.hml` | tick → day fraction, phase, shade-tier phase bonus, dusk-horn edge. Pure. | `day_frac, day_phase, day_tier_bonus, day_is_night, PHASE_DAWN..PHASE_NIGHT` |
| `movement.hml` | The movement model from GDD §2.3: walk/sprint/crouch/ADS, accel/friction/air control, jump, slide, slide-jump, mantle, step-up, fall damage, swept capsule vs heightfield. **`PredictedState` lives here.** | `move_apply, predicted_capture, predicted_restore, PS_FIELDS` |
| `weapons.hml` | The GDD §2.4 data table as parallel `array`s (never objects), falloff, spread/bloom, recoil arrays, ADS/sprint-to-fire timings. **Amended per D2.** | `wpn_dmg_at, wpn_rpm, wpn_mag, wpn_recoil, wpn_spread, wpn_ads_time, WPN_SPARROW..WPN_EMBERLANCE` |
| `combat.hml` | Hitscan: DDA ray vs heightfield + ray vs entity AABB, headshot volume, damage application, hit events. Authoritative. | `combat_raycast, combat_apply_damage, combat_fire` |
| `projectiles.hml` | The one projectile (Emberlance): arc integration, AoE, burn DoT. | `proj_spawn, proj_step` |
| `ai.hml` | Steering only, no navmesh: seek, 1.2 m separation, whisker avoidance at ±35°, attack ranges, wind-up tells. Server-only fields. | `ai_step, ai_spawn, ai_kind_params` |
| `director.hml` | Wave director: `budget(tier,wave)`, alive/on-screen caps, spawn ring biased behind the view cone, composition tables per tier. | `director_reset, director_step, director_wave_state` |
| `progression.hml` | XP curve `500+250L+25L²`, level, unlock ladder, Wickmarks, Ember Streaks (Flare/Drone/Dawnfall). | `prog_add_xp, prog_level, prog_unlocked, prog_streak_step, UNLOCK_*` |
| `loot.hml` | Rarity weights by shade tier, affix pool roll-without-replacement, the six hand-authored Relics. | `loot_roll, loot_affix_value, RARITY_*, AFFIX_*, RELIC_*` |
| `lantern.hml` | Lantern posts, the 2.5 s channel, tiers and radii, Wick Lines (90 m link), fast travel, respawn. (Wave 4.) | `lantern_place, lantern_light, lantern_tier_radius, wickline_rebuild, lantern_nearest` |
| `poi.hml` | POI placement from the chunk hash roll and their contents. (Wave 4.) | `poi_for_chunk, poi_populate, POI_*` |
| `build.hml` | 1 m grid structure placement, town plot, validation. (Wave 4.) | `build_place, build_remove, build_valid` |
| `almanac.hml` | 60 critters / 24 relics / 18 enemies, donation, museum wings. (Wave 4.) | `almanac_record, almanac_pct` |
| `contracts.hml` | Two daily contracts, generation, tracking, rewards. (Wave 4.) | `contract_roll, contract_step` |
| `snapshot.hml` | `snapshot_write(world, viewer_slot, baseline)` / `snapshot_read`. **Always takes a viewer** so interest management has a home. | `snapshot_write, snapshot_read, snapshot_size` |
| `sim.hml` | `sim_step(world, tick)` — the fixed system order of §4.3. The order is API. | `sim_step, sim_apply_command, sim_effects` |

### 5.5 `nightshade/src/net/` — v1 loopback, v2 gn.hml

| File | Purpose | Exports |
|---|---|---|
| `transport.hml` | `Transport` interface + `LoopbackTransport` with **fake-latency, fake-jitter and real-serializer debug modes** (`NS_FAKE_LATENCY_MS`, `NS_FAKE_JITTER_MS`, `NS_LOOPBACK_SERIALIZE`). `NetTransport` is a v2 stub. | `transport_loopback, transport_send_command, transport_poll_snapshot, transport_send_event, transport_stats` |
| `protocol.hml` | `net_id` constants (reserved now, unused in v1), packet builders/parsers, blob strides. | `NET_C_INPUT, NET_S_SNAPSHOT, NET_S_EVENT, …, proto_write_input, proto_read_input, proto_write_snapshot, proto_read_snapshot` |
| `quantize.hml` | `q_pos/dq_pos/q_ang/dq_ang/q_vel`. The authority quantizes its own state to the wire grid so both sides compare identical numbers. | `q_pos, dq_pos, q_ang, dq_ang, q_vel, dq_vel` |
| `packing.hml` | Fixed-stride blob writer/reader respecting the **255-byte buffer element cap** — 20 B/entity stride, 12 entities per 240 B blob. | `pack_new, pack_u8/u16/u32/i32, pack_flush, unpack_new, unpack_u8/u16/u32/i32` |

### 5.6 `nightshade/src/render/`

| File | Purpose | Exports |
|---|---|---|
| `render_snapshot.hml` | The `RenderSnapshot` SoA of §3.1 + `snapshot_build(rs, world, alpha)`. In v2 the same function reads network snapshots. | `rsnap_new, rsnap_build, rsnap_build_from_net, rsnap_field_*` |
| `view.hml` | Camera basis from yaw/pitch (never `mat_look_at`), FOV lerp (70 hip / 58 ADS / 78 sprint), screen shake, `recoil_view` (which **never leaves the client**), the MVP. | `view_new, view_build, view_shake, view_mvp, view_eye` |
| `chunkmesh.hml` | Chunk → cached flat vertex arena (LOD0 128 tris / LOD1 32 / LOD2 8) with baked per-vertex lighting, AO in creases, biome tint, and low-frequency value patchiness. Rebuilt only when dirty. | `cmesh_build, cmesh_get, cmesh_invalidate, cmesh_budget_step` |
| `terrain_render.hml` | Ring walk, per-chunk frustum sphere test, LOD selection by distance, skirts, `emit_mesh_buf` per chunk. | `terrain_emit, terrain_stats` |
| `entity_render.hml` | Entities/props/pickups → mesh instances with LOD, hit-flash tint, dissolve scale, **one contact-shadow quad each (mandatory)**, emissive markers into `LAYER_FX`. | `entity_emit` |
| `viewmodel.hml` | First-person weapon: idle sway, footstep bob, fire kick, reload stages, sprint tilt, ADS lerp. `depth = 0.05`, fog `f = 0`. | `vm_new, vm_step, vm_emit, vm_fire, vm_reload_stage` |
| `fx.hml` | Client-only particle SoA (cap 512, negative ids), tracers, muzzle flashes, impact bursts, ember motes, damage numbers, decals, glow cards. | `fx_new, fx_update, fx_emit, fx_spawn_muzzle, fx_spawn_impact, fx_spawn_tracer, fx_spawn_number, fx_spawn_dissolve` |
| `hud.hml` | ART_BIBLE §9 verbatim: crosshair with real spread bloom, hitmarker, health, ammo, compass, minimap, killfeed, XP bar, popups, damage vignette, hit-direction arcs, reload bar, interact prompt. ≤ 250 tris, hard-capped. | `hud_new, hud_build, hud_event, hud_set_tri_cap` |
| `postfx_geo.hml` | Vignette ring (static + damage summed into the same 16 tris), composite MOD overlay (dither + grain + edge bleed, 3 pre-baked variants cycled per frame), sprint speed lines, lightning/level-up flashes. | `postfx_build_overlay, postfx_emit, postfx_flash, postfx_set_vignette` |
| `world_render.hml` | The frame-graph orchestrator: owns the four batches, calls stages 11–27 of §4 in order. **The only file that knows the layer order.** | `frame_render, frame_init, frame_batches` |
| `map.hml` | The world map screen: lit lanterns, Wick Lines, discovered chunks, the obelisk records. (Wave 4.) | `map_build, map_toggle` |
| `menu.hml` | Title, pause, level-up card, unlock card, settings. (Wave 4.) | `menu_build, menu_input, menu_state` |

### 5.7 `nightshade/src/game/`

| File | Purpose | Exports |
|---|---|---|
| `main.hml` | Entry point. The loop of §3. Init order, shutdown order, the title card during asset generation. | `main` |
| `client.hml` | input → command → transport; snapshot → RenderSnapshot; the client event log that drives HUD and audio. | `client_new, client_apply, client_events` |
| `server.hml` | The authoritative host. In v1 it runs in-process behind `LoopbackTransport`; in v2 it is the file that `tools/dedicated.hml` links. | `server_new, server_tick, server_apply_command` |
| `assets.hml` | Boot sequence: build all atlases and meshes, synthesize all SFX, upload textures, set blend modes. Reports timing. | `assets_build, assets_atlas, assets_mesh, assets_sfx` |
| `audiobank.hml` | Procedural SFX synthesis → S16 mono PCM `buffer`s → `audio_register_pcm`. Gunshots, impacts, footsteps ×4 per surface, hit clicks (pitch chain), chimes, bell, dusk horn, ambience. | `bank_build, SFX_SPARROW, SFX_HIT, SFX_KILL, SFX_STEP_GRASS, …` |
| `hub.hml` | Ember Hollow: layout, the 5 NPCs' placement, bench/well/board/museum/plots. (Wave 4.) | `hub_init, hub_step, hub_emit` |
| `npc.hml` | NPC state, daily line rotation, head-turn, interaction prompts. (Wave 4.) | `npc_step, npc_line` |
| `save.hml` | Save/load on: entering town, sleeping, lighting a lantern, quitting. Binary, versioned. | `save_write, save_read, save_exists` |

### 5.8 `nightshade/src/data/`

| File | Purpose |
|---|---|
| `dialogue.hml` | Every NPC line, as arrays of strings. Data only, no logic. (Wave 4.) |

### 5.9 `nightshade/tools/`

| File | Purpose |
|---|---|
| **`shot.hml`** | **The visual verification harness.** Headless: builds assets, places a scripted camera + world state from a named scene id or CLI args, renders exactly one frame through the real `frame_render`, reads pixels back, writes PNG. The harsh visual critic runs this every iteration. See §7. |
| `simtest.hml` | Headless 10 000-tick sim runner with scripted input. **Must build and run with no SDL linked.** CI gate for the sim/render wall. |
| `replay.hml` | Records a command stream + per-tick position hash; replays and compares bit-for-bit. CI gate for determinism. |
| `packetdump.hml` | Hexdump + decode of a captured `S_SNAPSHOT`; asserts every field's byte offset. |
| `palette_preview.hml` | Dumps a PNG swatch sheet of the whole palette and every ToD keyframe applied to a test sphere. **Built before texgen**, so palette errors are caught before they are baked into fifty tiles. |
| `texview.hml` | Dumps `ATLAS_WORLD`, `ATLAS_FX`, `ATLAS_HUD`, `TEX_SKY` to PNG, with a grid overlay and cell labels. |
| `benchframe.hml` | Per-stage frame ablation against the live renderer; prints the §4 stage table. Regression gate for the budget. |
| `ci_imports.sh` | Greps the import wall (§1.1), the `g_` prefix rule, and the legacy-import ban. |
| `ci_unbox.sh` | `hemlockc -c --emit-c` + grep for `double`/`int32_t` on the ~12 hottest locals named in `CLAUDE.md`. |
| `bench/**` | The recon benchmark corpus. Frozen. Re-run with `run_all.sh` / `sweep.sh` to detect toolchain regressions. |
| `probes/**`, `probes-host/**` | The recon FFI probes. Frozen. Re-run after any SDL binding change. |

**Totals:** 22 engine modules (15 new/rewritten, 7 frozen legacy), 51 game modules, 10 tools.

---

## 6. HOW ASSETS ARE PRODUCED

**There are no asset files.** `nightshade/assets/` contains a `README.md` explaining why it is empty.

```
boot (behind a title card, budget ≤ 400 ms compiled):
  palette.hml         constants — no work
  texgen_build_world_atlas()   256×256 RGBA   ≈ 2.3 M ops    → atlas_upload(RGBA32, BLEND)
  fxgen_build_atlas()          128×128 RGBA   ≈ 0.4 M ops    → atlas_upload(RGBA32, ADD)
  hudgen_build_atlas()         128×128 RGBA   fonts+icons    → atlas_upload(RGBA32, BLEND)
  skygen_build()               512×160 RGBA   ≈ 2.0 M ops    → atlas_upload(RGBA32, NONE)
  meshgen_build_all()          ~40 meshes into one mesh arena
  bank_build()                 ~60 SFX synthesized to S16 PCM buffers → audio_register_pcm
  postfx_build_overlay()       3 × 320×240 dither/grain variants → atlas_upload(RGBA32, MOD)
```

Runtime regeneration: **only the sky**, and only incrementally — 20 rows per frame on a rolling
cursor when the ToD keyframe blend moves, uploaded with a dirty-rect `SDL_UpdateTexture`. A full sky
refresh takes 8 frames and never causes a hitch.

Per-instance variation is free and mandatory: random yaw, 0.85–1.25 scale, ±8 % vertex-colour jitter.
Twenty trees from one mesh and nobody notices.

The three rules that keep this from becoming mush (ART_BIBLE §7.1, restated because they are the
difference between "procedural" and "television static"):

1. **Structure lives at 4–10 texel wavelength. Anything finer than 3 texels must be grain (±6
   luminance), not structure.** This is the fix for the current `tex_grass` shimmer.
2. **Ordered 4×4 Bayer dither at every ramp boundary, always.** One array lookup. It is the single
   most PS1-authentic technique available.
3. **≤ 12 colours per tile, from at most 2 palette families plus black; minimum albedo luminance
   72.** Vertex colour multiplies, so a texture authored dark can never be made bright.

---

## 7. THE VISUAL VERIFICATION HARNESS

`tools/shot.hml` is not a debug utility. It is the primary quality instrument and it is built in
Wave 1, before there is anything worth photographing.

```
hemlockc -O1 tools/shot.hml -o /tmp/shot
SDL_VIDEODRIVER=dummy /tmp/shot --scene ridge_golden --out docs/shots/ridge_golden.png
SDL_VIDEODRIVER=dummy /tmp/shot --scene <id> --cam x,y,z --look yaw,pitch --tod 18.25 \
    --weather storm --seed 1337 --out <path>
```

Requirements:

- Renders through the **real** `frame_render`. Not a parallel code path. If `shot.hml` and the game
  can diverge, the harness is worthless.
- Deterministic: fixed seed, fixed tick, no wall clock. The same command produces the same PNG bytes.
- Scene ids include the five ART_BIBLE money shots (`ridge_golden`, `muzzle_fog`, `hub_dawn`,
  `ns_bloom`, `storm_assault`) plus `hud_worst_case` (the HUD over noon sky, snow, a muzzle flash,
  and `CONCRETE_HI`) and `budget_worst` (the densest legal frame).
- Prints the `stats.hml` frame report to stdout alongside the PNG: triangle counts per layer, cull
  rejections, draw calls, stage timings. **A screenshot without its budget report is not evidence.**
- **Compiled only — for performance and portability.** `hemlockc` is the shipping target, so it is
  the only thing worth photographing: compiled is ~5–18× the interpreter, and the shipped artifact
  is a self-contained binary. Verify what you ship.

  > **Corrected premise.** An earlier draft justified this by citing wobbleweed-api §11.2 (the
  > interpreter emitting 404 triangles vs the compiler's 425, with different pixels). **That
  > divergence has been fixed upstream** in hemlock `ed12be28` ("codegen: fix 30+
  > interpreter/compiler divergences"), re-verified on `cb7fbfaa`: both backends now report
  > `total=425 sky=4` and byte-identical sampled pixels. The same fix also invalidated the
  > `geom.hml` "vertex buffer reuse" bug — see `HEMLOCK_ISSUES.md` H-3.
  >
  > Do not restate the divergence as a live fact. The compiled-only rule stands on performance and
  > portability, which do not expire when a bug is fixed.

---

## 8. BUDGETS — the numbers every task is measured against

| Line | Budget | Basis |
|---|---|---|
| Frame | **16.67 ms** (60 fps floor) | non-negotiable; a gorgeous 40 fps FPS is a bad FPS |
| Triangles submitted | **2500 steady, 3500 hard clamp** | PERF §3 (2.88 µs/tri marginal, 0.7 ms fixed) |
| Render (emit + sort + flush + present) | **≤ 11.0 ms** | 2500 tris @ 8.4 ms + 4 layers of overdraw headroom |
| Simulation | **≤ 2.0 ms** | net §17.1 |
| Networking (v1 loopback) | ≤ 0.3 ms | net §17.1; measured 0.026 ms for 32 packed entities |
| Input + audio + HUD build | ≤ 1.0 ms | |
| Slack | ≥ 1.3 ms | |
| Overdraw | ≤ 4 screenfuls | 0.8 ms each at 320×240 on the software fallback |
| Boot (asset generation) | ≤ 400 ms | behind a title card |
| Sky re-bake | ≤ 0.6 ms/frame | 20 rows/frame |
| Draw calls | **unbudgeted** | PERF §8: 2000 calls cost 0.3 ms more than 1 |
| Memory | ≤ 96 MB RSS after 10 000 frames | `bench_leaks`-style smoke test; no growth |

**When the budget breaks, turn `FOG_FAR` down first.** It is the designed dial, it is on-aesthetic,
and ground triangles scale with its square. Only after that: cut props, then LOD earlier, then cut
overdraw. Never cut the frame rate.

Typical legal combat frame (ART_BIBLE §8.3, checked against D1):
500 ground + 400 props/trees + 5 enemies × 90 + 300 structure + 250 HUD + 120 FX + 18 post = **2038**.

---

## 9. WHAT IS NOT BEING BUILT

Restating gamedesign §9 because architecture decisions keep leaking toward these:

Multiplayer (v2 — but every *shape* in §3 is v1), vehicles, swimming, ragdolls, skeletal skinning,
destructible/voxel terrain, inventory tetris, town raids, dialogue trees, voiced dialogue, fishing
minigames, bullet ballistics, prone, difficulty settings, recipe discovery, a z-buffer, dynamic
shadow maps, real bloom/DOF/motion blur/chromatic aberration, save-anywhere, controller support
(v1.1, behind the command struct), resolution options.

And two additions from this document: **no PNG reader** (D4) and **no OBJ art pipeline** (D5).
