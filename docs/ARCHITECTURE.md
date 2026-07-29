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
| `mathx.hml` | Scalar helpers + the noise stack. **All hashing in `u64` with an explicit 32-bit mask.** *(Corrected by W2-2: `i64` also traps — two masked 32-bit values multiplied reach 2^64, which overflows i64. `u64` wraps on both backends and is the only container in which "mask after every multiply" is total. Verified: `i64 9223372036854775807 * 2` throws; the same in u64 wraps.)* Zero imports; calls the `__floor` / `__clamp` builtins directly. | `xhash2, xhash3, h01, h01_3, vnoise, fbm2, bayer4, bayer4i, smoothstep, smooth01, clampf, clamp01, lerpf, minf, maxf, absf, absi, mini, maxi, clampi, floori, deg2rad, rad2deg` |

#### 5.2a `config.hml` / `mathx.hml` — exact signatures (added by W2-2)

`config.hml` exports **~250 `g_`-prefixed constants** in 18 numbered sections: fixed timestep,
resolution, triangle budget, millisecond budget, camera/fog/light, shade tier + its fog ladder,
world/chunk/LOD, entity caps, player, weapon+enemy *shapes*, wave director, day cycle,
progression, lanterns, atlases/texture rules, audio, net shapes, juice timings. The two
load-bearing ones are `g_FOG_FAR_CAP = 72.0` and `g_MAX_DYNAMIC_LIGHTS = 2`.

**Deliberately NOT in `config.hml`:** colours (they are `art/palette.hml`) and per-row data
*tables* — the six weapons, the six enemies, the loot bands, the ToD keyframes and the HUD
element rects are parallel arrays living in their owning modules. `config.hml` carries the
*shape* of each (row counts, index constants, caps) so the owning module can size itself.
Two GDD ladders are rescaled by D2 (`72/140`) and the derivation is commented in place: the
per-tier fog distances (140/120/95/75/55/38 → 72/62/49/39/28/20 m) and the LOD ring radii
(48/96 → 24/48 m).

```hemlock
// ---- scalar helpers: thin wrappers over the __clamp/__min/__max/__abs builtins.
//      In an INNERMOST loop call the builtin directly — measured 12.2 ns vs
//      13.7 ns hand-inlined ifs, 19.3 ns for @stdlib's alias, 22.0 ns for these.
fn absf(p_a: f64): f64
fn minf(p_a: f64, p_b: f64): f64
fn maxf(p_a: f64, p_b: f64): f64
fn clampf(p_v: f64, p_lo: f64, p_hi: f64): f64
fn clamp01(p_v: f64): f64                       // the case that dominates
fn lerpf(p_a: f64, p_b: f64, p_t: f64): f64
fn smooth01(p_t: f64): f64                      // t*t*(3-2t), t clamped to [0,1]
fn smoothstep(p_e0: f64, p_e1: f64, p_x: f64): f64      // GLSL semantics
fn deg2rad(p_d: f64): f64
fn rad2deg(p_r: f64): f64
fn absi(p_a: i32): i32
fn mini(p_a: i32, p_b: i32): i32
fn maxi(p_a: i32, p_b: i32): i32
fn clampi(p_v: i32, p_lo: i32, p_hi: i32): i32
fn floori(p_x: f64): i32                        // floor, NOT truncate: floori(-2.1) == -3

// ---- hashing.  Returns a full 32-bit value carried in a u64.
fn xhash2(p_x: i32, p_y: i32, p_seed: i32): u64
fn xhash3(p_x: i32, p_y: i32, p_z: i32, p_seed: i32): u64
fn h01(p_x: i32, p_y: i32, p_seed: i32): f64            // xhash2 mapped to [0,1)
fn h01_3(p_x: i32, p_y: i32, p_z: i32, p_seed: i32): f64

// ---- ordered dither (ART_BIBLE §7.2).  Dither EVERY ramp boundary.
fn bayer4i(p_x: i32, p_y: i32): i32             // 0..15
fn bayer4(p_x: i32, p_y: i32): f64              // 0..15/16, the threshold form

// ---- value noise.  `p_cell` is the lattice cell size in the SAME UNITS as
//      x and y (texels for texgen, metres for worldgen); `p_wrap` is the
//      repeat length in those units, and <= 0 disables wrapping.
//      GUARANTEE: when p_cell divides p_wrap,
//          vnoise(x + wrap, y, cell, wrap, s) == vnoise(x, y, cell, wrap, s)
//      BIT-EXACTLY, which is what makes a 32x32 atlas cell seamless.
//      fbm2 is 3 octaves at 0.60/0.28/0.12 with cell halving and seeds
//      s, s+31, s+97 (ART_BIBLE §7.2 verbatim); it tiles when cell*4 divides
//      wrap.  Both return [0, 1).
fn vnoise(p_x: f64, p_y: f64, p_cell: f64, p_wrap: i32, p_seed: i32): f64
fn fbm2(p_x: f64, p_y: f64, p_cell: f64, p_wrap: i32, p_seed: i32): f64
```

> **COST, MEASURED (W2-2, `hemlockc -O1`, `__clock` min-of-7, load avg 4.0).** `xhash2` **280 ns**,
> `vnoise` **1.25 µs**, `fbm2` **3.7 µs** per call. Hemlock's `u64` arithmetic is boxed (~11 ns per
> operation), and `vnoise` runs 44 of them across its four inlined corner hashes. **Consequence for
> `texgen.hml` (W2-5) and `skygen.hml` (W2-6): do not call `fbm2` per texel.** Measured on the
> ART_BIBLE §7.3 grass recipe (two `fbm2` + one `h01` + one `bayer4` per texel): **8.02 ms for one
> 32×32 tile → 514 ms for a 64-tile atlas**, against a 200 ms budget. The same tile's *lattice* is
> only 84 hash evaluations (2×2 + 4×4 + 8×8 corners) — **0.08 ms** — so evaluate each octave's
> lattice once per tile and bilinear-interpolate per texel, which is 100× cheaper and produces the
> identical field. `vnoise`/`fbm2` remain the right call for per-vertex worldgen (81 samples per
> chunk), for tools, and for any lattice-sparse use.

### 5.3 `nightshade/src/art/` — the procedural art pipeline

| File | Purpose | Exports |
|---|---|---|
| `palette.hml` | Every colour from ART_BIBLE §3, as `g_`-prefixed packed `i32` (0xRRGGBB) plus `pal_r/g/b` unpackers. **Nothing anywhere else names a colour.** Also carries the ART_BIBLE §5.1 per-keyframe sky/cloud colours (`g_SKY_ZENITH_DAWN` … `g_CLOUD_SHADOW_DEEP`, 5 rows × 7 keyframes), the §4.4 emissive `g_WINDOW_LIGHT` and the §13.7 `g_DEBUG_MAGENTA`, because the "no hex outside this file" law (CLAUDE.md §8, `ci_imports.sh` R4) has to hold for `tod.hml` and `skygen.hml` too. **125 colour constants.** Zero imports; pure data. | `g_GRASS_MID, g_NS_CORE, g_UI_AMBER, … (125 colour constants), pal_r, pal_g, pal_b, pal_pack, pal_lerp, pal_lerp_q, pal_lum, pal_table, pal_names, pal_families, pal_selftest, g_PAL_COUNT, g_PAL_FAM_SKY..g_PAL_FAM_DEBUG, g_PAL_FAM_COUNT, g_PAL_SELFTEST_ASSERTS` |
| `tod.hml` | The ART_BIBLE §5 keyframe table remapped onto the 16-minute day (D6), interpolation, weather overrides, lightning. Writes the engine `RenderEnv`. | `tod_eval, tod_phase, tod_sky_keys, tod_set_weather, tod_lightning_fire, TOD_DAWN..TOD_DEEP, WX_CLEAR/OVERCAST/RAIN/STORM/BLOOM` |
| `texgen.hml` | ART_BIBLE §7.2 primitives + §7.3 generators + the §7.4 8×8 packer → `ATLAS_WORLD` (256×256). | `texgen_build_world_atlas, tg_grass, tg_dirt, tg_stone, tg_wood, tg_metal, tg_concrete, tg_leaf, tg_snow, tg_ramp_pick, tg_grain, CELL_*` (cell index constants) |
| `skygen.hml` | ART_BIBLE §11 panorama: dithered gradient, two cloud layers with lit-top/shadow-bottom, sun/moon/halo, star field with a fixed seed. Incremental re-bake, 20 rows/frame. | `skygen_build, skygen_mark_dirty, skygen_rebake_slice, skygen_tex`, plus the key-block interface in §5.3.1 |

#### 5.3.2 `meshgen_vm_bob` — the held-object bob (added by the lantern-viewmodel task)

The viewmodel is a **lantern**, not a gun (playtest 2026-07-27: *"the gun is just like floating in
front of the pov camera ... maybe do something easier for fps pov? like a torch?"*). A held lamp has
to move or it reads as pasted on. The motion curve belongs with the model, but the transform is
applied by the renderer, so `meshgen.hml` publishes the curve and `world_render.hml` consumes it:

```hemlock
// meshgen.hml — pure, allocation-free, writes 3 metres-offsets into p_out.
//   p_phase   walk-cycle phase in radians (2 per stride); free-running when idle
//   p_speed   0..1, horizontal speed / run speed
//   p_out     caller-owned array<f64> of length >= 3: [right, up, forward]
export fn meshgen_vm_bob(p_phase: f64, p_speed: f64, p_out: array<f64>);
```

**Call site — `world_render.hml` stage 15, six lines.** The viewmodel offset is currently the
constants `1.05 / 0.26 / -0.34`; the bob adds to them in the same camera basis that is already
computed there:

```hemlock
meshgen_vm_bob(g_vm_phase, g_vm_speed, g_vm_bob);   // g_vm_bob: array<f64> len 3, allocated once
let bo_r: f64 = 0.26 + g_vm_bob[0];
let bo_u: f64 = 0.0 - 0.34 + g_vm_bob[1];
let bo_f: f64 = 1.05 + g_vm_bob[2];
let vx: f64 = g_camx + ffx * bo_f + rrx * bo_r + uux * bo_u;
// (same for vy, vz)
```

`g_vm_phase` / `g_vm_speed` come from the movement state the renderer already receives in the
snapshot. Amplitudes are 1.4 cm vertical / 0.9 cm lateral at a full sprint — 3 px and 2 px at
320×240 — plus a 0.35 cm idle sway that never stops. **Until this call site exists the lantern is
static**; nothing else about it depends on the wiring.

| `fxgen.hml` | `ATLAS_FX` (128×128, 16×16 cells): muzzle ×3, tracer, sparks, explosion ×6, ember, smoke ×3, glow cards ×2, enemy eye, loot beam, rain streak, lightning, dust, splash, XP mote. | `fxgen_build_atlas, FX_MUZZLE_0, FX_TRACER, FX_GLOW_S, FX_GLOW_L, …` |
| `hudgen.hml` | `ATLAS_HUD` (128×128): `FONT_MICRO` 4×6 and `FONT_BIG` 8×12 as packed bitfields, icons, crosshair parts, minimap chrome, vignette gradient strip. **`hudgen_uv` returns WHOLE-TEXEL uv edges, not `atlas_rect_uv`'s half-texel inset** — ATLAS_HUD is blitted 1:1, and at 1:1 the inset drops a texel of the mandatory §9.1 outline off every sprite (measured; `hudgen_selftest` asserts the whole-texel form). | `hudgen_build_atlas, hud_font_micro, hud_font_big, hudgen_rect, hudgen_uv, hudgen_xh_place, HUD_XH_GAP, HUD_XH_LEN, HUD_ICON_*` |
| `meshgen.hml` | The procedural mesh DSL and every world mesh: tree LOD0/1/2, bush, rock, crate, barrel, lantern post, contact blob, enemy ×6 × 3 LODs (rigid parts), NPC, the LANTERN viewmodel (slot 28, the only one the renderer is bound to) and five retained gun viewmodels — **34 meshes, 2494 triangles, built in ~29 ms**. Bakes vertex colour + creased AO at build time, then applies a soft luminance floor of 72 (`MG_LUM_FLOOR`) so no vertex in the game is darker than the atlas minimum. UVs are bound per MATERIAL, not per atlas cell: `assets.hml` calls `meshgen_set_material_uv(MG_MAT_*, u0,v0,u1,v1)` with texgen's `CELL_*` rects **before** `meshgen_build_all()`. | `mg_box, mg_box_ex, mg_prism, mg_taper, mg_fan_disc, mg_lathe, mg_spike, mg_panel, mg_ground_quad, mg_set_jitter, meshgen_build_all, meshgen_bake_all, meshgen_set_material_uv, meshgen_set_sun_azimuth, meshgen_mesh, meshgen_name, meshgen_tris, meshgen_budget, meshgen_kind, meshgen_radius, meshgen_view_yaw, meshgen_count, meshgen_enemy_mesh, mg_head_shoulder, mg_head_width, mg_shoulder_width, mg_protrusion, mg_protrusion_axis, MESH_TREE0/1/2, MESH_BUSH, MESH_ROCK, MESH_CRATE, MESH_BARREL, MESH_LANTERN, MESH_BLOB, MESH_WISP0..MESH_BULWARK2 (class ×3 LODs), MESH_NPC, MESH_LANTERN_VM (= MESH_SPARROW_VM, the alias), MESH_TINKER_VM..MESH_EMBERLANCE_VM, MESH_COUNT, ENEMY_WISP..ENEMY_BULWARK, MG_MAT_*, MG_KIND_*, MG_LUM_FLOOR, MG_VM_LUM_FLOOR, meshgen_vm_bob` |
| `biome.hml` | Per-biome palettes, texture cell selection, prop density, `FOG_FAR` override, triangle-budget policy. (Wave 4.) | `biome_of, biome_params, BIOME_HOLLOWFIELD..BIOME_DEEPSHADE` |
| `weather.hml` | Weather state machine + rain/snow/fog-bank emitters. (Wave 4.) | `weather_step, weather_emit` |
| `hubgen.hml` | Ember Hollow's modular building meshes and layout. (Wave 4.) | `hubgen_build, hub_layout` |

#### 5.3a `tod.hml` — exact signatures (added by W2-4; `skygen.hml` and the view code code against these)

```hemlock
tod_eval(env: array<f64>, day_t: f64, wx: i32)   // frame graph stage 6; fills the RenderEnv
tod_sky_keys(out: array<f64>)                    // out.length >= TODSKY_COUNT (22); 0..1 colours
tod_phase(day_t: f64): i32                       // TOD_PHASE_DAWN/DAY/DUSK/NIGHT
tod_phase_t(day_t: f64): f64                     // 0..1 through the current phase (the dusk horn)
tod_phase_start(phase: i32): f64
tod_is_night(day_t: f64): i32
tod_key_anchor(key: i32): f64                    // day fraction of TOD_DAWN..TOD_DEEP
tod_key_field(key: i32, field: i32): f64         // raw keyframe row, for tools
tod_clock_hours(day_t: f64): f64                 // the ART_BIBLE wall clock, for the debug overlay
tod_t_from_tick(tick: i32): f64                  // tick -> day fraction (57 600 ticks/day)
tod_wrap(t: f64): f64
tod_set_weather(wx: i32)                         // immediate; passing a new wx to tod_eval crossfades
tod_weather(): i32      tod_weather_mix(): f64
tod_lightning_fire()    tod_lightning_active(): i32
tod_lightning_frame(): i32                       // -1 idle, 0/1 flash, 2 recovery
tod_lightning_alpha(): f64                       // alpha of the full-screen additive quad fx_emit draws
tod_set_mist_band(bottom_y: f64, thickness: f64) // §6.4; view code sets it per frame
tod_set_bounce_tint(r: f64, g: f64, b: f64)      // biome.hml tints the grass bounce
tod_state(field: i32): f64   tod_mist_density(): f64   tod_reset()
```

`TODSKY_*` indices: `ZENITH_R/G/B 0-2, MID 3-5, HORIZON 6-8, CLOUD_LIT 9-11, CLOUD_SHADOW 12-14,
STAR_ALPHA 15, HALO 16, MOON 17 (0 sun … 1 moon, crossfades), BODY_X/Y/Z 18-20, CLOUD_COVER 21`.
`TODSKY_BODY_*` is also the key-light direction, so the disc and the shadows can never disagree.
**`tod_eval` sets `RIM` to zero** (ART_BIBLE §4.2 — rim is per entity class, not per environment);
entity emit sets its own rim from the horizon band it reads out of `tod_sky_keys`.

#### 5.3.1 The `skygen` <-> `tod` key block (added by W2-6)

`skygen.hml` does **not** import `tod.hml`. The dependency is inverted: skygen publishes a flat
`array<f64>` layout, tod fills it, and the caller hands it over. Flat, not an object — it is copied
once per re-bake and read from the row loop, and A7/N8 both say a struct buys nothing here. This
keeps skygen unit-testable with no ToD clock and keeps `src/art/**` free of a cycle.

```
skygen_keys_new(): array<f64>              // a zeroed block of SKYK_COUNT (26)
skygen_keys_default(k: array<f64>)         // the NOON keyframe, from palette.hml only
skygen_set_keys(k: array<f64>)             // takes effect at the next mark_dirty/build
skygen_set_clock(t_seconds: f64)           // drives cloud drift (0.6 / 1.4 px/s)
skygen_set_features(mask: i32)             // SKYF_CLOUDS/STARS/SUN/MOON/MILKYWAY/ALL
skygen_init()                              // idempotent; no SDL
skygen_bake_all(): i32                     // CPU-only full bake, no window needed
skygen_build(win): ptr                     // bake + atlas_upload(BLEND_NONE)
skygen_mark_dirty()                        // snapshot keys, schedule a rolling re-bake
skygen_rebake_slice(): i32                 // next slice + one dirty-rect upload; 0 when clean
skygen_dirty_rows(): i32
skygen_set_slice_rows(n: i32)              // the rows/frame dial, default SKY_ROWS_PER_SLICE
skygen_slice_rows(): i32
skygen_tex() / skygen_atlas() / skygen_w() / skygen_h()
skygen_sun_uv(out, off) / skygen_moon_uv(out, off) / skygen_sun_is_up(): i32
skygen_seam(out, off)                      // the fog-derived horizon colour, rgb 0..255
skygen_row_cloud(y): i32 / skygen_star_count(): i32     // bake statistics, for the harness
```

Key block slots (`SKYK_*`, channels 0..255, multipliers and alphas 0..1):

| Slot | Field | Slot | Field |
|---|---|---|---|
| 0..2 | `SKY_ZENITH` r,g,b | 15..17 | `FOG_TINT_MUL` r,g,b (0..1) |
| 3..5 | `SKY_MID` r,g,b | 18 | `STAR_ALPHA` |
| 6..8 | `SKY_HORIZON` r,g,b | 19..21 | `SUN_DIR` x,y,z |
| 9..11 | `CLOUD_LIT` r,g,b | 22 | sun halo radius, px (34; 56 at DAWN/GOLDEN) |
| 12..14 | `CLOUD_SHADOW` r,g,b | 23 | sun halo falloff exponent (1.8; 1.2 at DAWN/GOLDEN) |
| | | 24 | `MOON_PHASE` 0..1 (0 new, 0.5 full) |
| | | 25 | `CLOUD_COVER_BIAS`, subtracted from the coverage threshold |

**`tod.hml` (W2-4) owes exactly one function against this**: fill a caller-supplied
`array<f64>` of `SKYK_COUNT` from the interpolated §5.1 keyframe plus the weather override. The
name reserved in §5.3 is `tod_sky_keys`; W2-6 assumed nothing about its signature.

**§11.5 reconciliation.** The §5.1 table authors `SKY_HORIZON` and `FOG_TINT_MUL` independently and
they do not agree (NOON implies a "mid-grey" of (221,250,247); GOLDEN implies (266,219,155)).
skygen derives the panorama's horizon band from the fog, per §11.5, at the authored horizon's
luminance: `seam = FOG_TINT_MUL * (luma(SKY_HORIZON) / luma(FOG_TINT_MUL))`. The seam therefore
carries the fog's hue — which is what shows as a skyline seam — at the art director's value.

### 5.4 `nightshade/src/sim/` — the simulation (headless; the future dedicated server)

| File | Purpose | Exports |
|---|---|---|
| `rng.hml` | Seeded xorshift128 (4x32-bit lanes) with **separate streams**, seeded from `(world_seed, stream_id, tick, entity_id)` through splitmix64. `@stdlib/random` is banned here; the module imports **nothing**. State is a caller-owned 4-slot `array` so reseeding allocates nothing. **W2-9 signatures:** `rng_new(): array` · `rng_seed(st, world_seed, stream, tick, entity)` · `rng_u32(st): u64` (0..2^32-1, the core draw) · `rng_next(st): i32` (0..2^31-1) · `rng_f01(st): f64` [0,1) · `rng_f11(st): f64` (-1,1) · `rng_pick(st, n): i32` [0,n) rejection-sampled · `rng_range(st, lo, hi): i32` **inclusive** · `rng_chance(st, num, den): i32` 0/1 · `rng_copy(dst, src)` · `rng_state_hash(st): i32`. | `rng_new, rng_seed, rng_u32, rng_next, rng_f01, rng_f11, rng_pick, rng_range, rng_chance, rng_copy, rng_state_hash, RNG_LOOT, RNG_SPREAD, RNG_AI, RNG_WORLDGEN, RNG_DIRECTOR, RNG_STREAMS, RNG_LANES` |
| `command.hml` | `InputCommand` (9 integers, **no bools, no floats, no nulls**) + button bits + quantize/dequantize. Quantized **at construction** so prediction uses the exact value the server will. Imports **nothing**. **W2-9 signatures:** `cmd_new(): object` · `cmd_set(c, tick, dt_ms, mx: f64, my: f64, yaw_rad: f64, pitch_rad: f64, buttons, weapon, seq)` — takes RADIANS and [-1,1] axes, quantizes and clamps inside · `cmd_copy(dst, src)` · `cmd_yaw(c): f64` [0,TAU) · `cmd_pitch(c): f64` (-PI,PI] · `cmd_move_x/y(c): f64` [-1,1] · `cmd_btn(c, bit): i32` 0/1 · `cmd_wire_ok(c): i32` 0 = legal, else a bit per bad field · `cmd_hash(c): i32` · `q_ang(f64): i32` / `dq_ang(i32): f64` / `q_axis(f64): i32` / `dq_axis(i32): f64`. **`q_ang` ROUNDS, it does not truncate** — NETWORKING.md §11.1's pseudo-code truncates and is therefore not idempotent; `src/net/quantize.hml` (W2-12) must round to match. | `cmd_new, cmd_set, cmd_copy, cmd_yaw, cmd_pitch, cmd_move_x, cmd_move_y, cmd_btn, cmd_wire_ok, cmd_hash, BTN_FIRE..BTN_INV, BTN_ALL, q_ang, dq_ang, q_axis, dq_axis, CMD_FIELDS, CMD_STRIDE, ANG_STEPS, ANG_SCALE, AXIS_STEPS, CMD_TAU, CMD_PI, CMD_MAX_TICK, CMD_MAX_DT_MS, CMD_MAX_WEAPON` |
| `world.hml` | The SoA `World`: identity / transform / state / owner-only / server-only groups, sparse-set ids, `world_spawn`/`world_despawn` (swap-with-last), kind-partitioned id ranges. Imports nothing — pure storage. **Signatures (W2-10, as built):** `world_new(): object` (cap = `WORLD_CAP_DEFAULT` 512, mirrors `g_MAX_ENTS`) · `world_new_cap(cap): object` · `world_spawn(w, kind, owner): i32` returns a slot or `SLOT_NONE` (-1); refuses `KIND_PLAYER` · `world_spawn_player(w, pslot): i32` (a player id **is** its slot, 1..64, positional per NETWORKING §7.1) · `world_despawn(w, slot): i32` / `world_despawn_id(w, id): i32` · `world_slot_of(w, id): i32` / `world_id_of(w, slot): i32` / `world_alive(w, id): i32` · `world_check(w): i32` (0 = consistent; tools/CI, O(cap)) · `world_reset(w)` keeps the id allocators, `world_reset_session(w, seed)` rewinds them. Per-entity systems **hoist the field arrays** (`let px = w.px;` — never annotate the hoist, see W2-10 report) rather than calling an accessor. | `world_new, world_new_cap, world_spawn, world_spawn_player, world_despawn, world_despawn_id, world_slot_of, world_id_of, world_alive, world_kind_of, world_owner_of, world_count, world_cap, world_tick, world_set_tick, world_seed, world_set_seed, world_replaying, world_set_replaying, world_check, world_reset, world_reset_session, world_id_class, world_kind_range_base, world_next_id, world_spawn_count, world_despawn_count, world_spawn_fail_count, KIND_NONE/PLAYER/AI/NPC/PROJECTILE/PICKUP/PROP/LANTERN/COSMETIC/COUNT, ID_NONE, ID_PLAYER_BASE, ID_PLAYER_MAX, ID_AI_BASE, ID_AI_MAX, ID_PROJ_BASE, ID_PROJ_MAX, ID_PICKUP_BASE, ID_PICKUP_MAX, ID_COSMETIC_BASE, ID_COSMETIC_MIN, SLOT_NONE, WORLD_CAP_DEFAULT, EF_VISIBLE/DEAD/HIT_FLASH/GROUNDED/INVULN/NO_REPLICATE` |
| `history.hml` | Transform ring buffer, `HISTORY_TICKS = 32`, flat `px[(slot*32)+ring]`. Called every tick even in v1. Every cell also stores the occupying **id**, because `world_despawn` recycles slots — a slot-only rewind would return the wrong body. **Signatures (W2-10, as built):** `history_new(cap): object` · `history_capture(h, w)` (once per tick, O(live count), 0.024 ms @256) · `history_sample(h, slot, id, tick, out): i32` writes `out[HIST_PX..HIST_PITCH]`, returns 1/0, never allocates · `history_find_slot(h, id, tick): i32` is the O(n) fallback when the slot changed · `history_sample_id(h, id, tick, out): i32` combines the two. | `history_new, history_reset, history_capture, history_sample, history_sample_id, history_find_slot, history_ring_of, history_head_tick, history_count_at, history_depth, history_capture_count, HISTORY_TICKS, HISTORY_MASK, HIST_PX, HIST_PY, HIST_PZ, HIST_YAW, HIST_PITCH, HIST_FIELDS, HIST_MISS` |
| `chunk.hml` | Chunk storage: `buffer(u16)` heights (cm), `buffer(u8)` biome + baked light, sparse edit overlay, dirty flags, LRU cache with pins. **Built by W3-2 — exact signatures and the injected-source contract are in §5.4b.** | `chunk_key, chunk_get, chunk_height_at, chunk_normal_at, chunk_set_edit, chunk_evict, CHUNK_N` (full list in §5.4b) |
| `worldgen.hml` | Pure `f(seed, cx, cz) → chunk`. 3-octave value noise height, temperature/moisture biome fields, per-chunk POI hash roll. No I/O, no globals. **Built by W3-1 — exact signatures and the chunk buffer contract are in §5.4a.** | `worldgen_chunk, worldgen_chunk_height_m, worldgen_height, worldgen_height_cm, worldgen_height_rel, worldgen_temp, worldgen_moist, worldgen_relief, worldgen_relief_tm, worldgen_biome, worldgen_biome_tmd, worldgen_shade_tier, worldgen_tier_jitter, worldgen_chunk_dist, worldgen_poi_roll, worldgen_poi_x, worldgen_poi_z, worldgen_block_of, worldgen_is_lantern_chunk, worldgen_lantern_x, worldgen_lantern_z, WG_*` |
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

#### 5.4a `worldgen.hml` — exact signatures (added by W3-1; `chunk.hml`, `poi.hml`, `daycycle.hml` and the terrain renderer code against these)

Everything is a pure function of `(seed, world position)` or `(seed, chunk coordinate)`. No state,
no I/O, no wall clock, no mutable top-level variable. The module imports **only** `src/core/mathx.hml`.

```hemlock
// ---- the fields, at any world point (metres)
worldgen_height(seed: i32, wx: f64, wz: f64): f64          // terrain height, metres
worldgen_height_cm(seed: i32, wx: f64, wz: f64): i32       // the stored form, rounded, 0..65535
worldgen_height_rel(seed, wx, wz, relief: f64): f64        // the formula, given a precomputed relief
worldgen_temp(seed: i32, wx: f64, wz: f64): f64            // [0,1)
worldgen_moist(seed: i32, wx: f64, wz: f64): f64           // [0,1)
worldgen_relief(seed: i32, wx: f64, wz: f64): f64          // [0.40, 1.70], continuous
worldgen_relief_tm(t: f64, m: f64): f64
worldgen_biome(seed: i32, wx: f64, wz: f64): i32           // WG_BIOME_*
worldgen_biome_tmd(t: f64, m: f64, d_from_town: f64): i32

// ---- per chunk
worldgen_chunk_dist(cx: i32, cz: i32): f64                 // chunk centre to town, metres
worldgen_shade_tier(seed: i32, cx: i32, cz: i32, phase_bonus: i32): i32   // 0..5
worldgen_tier_jitter(seed: i32, cx: i32, cz: i32): i32     // -1 | 0 | +1
worldgen_poi_roll(seed: i32, cx: i32, cz: i32): i32        // WG_POI_*
worldgen_poi_x(seed: i32, cx: i32, cz: i32): f64           // world metres
worldgen_poi_z(seed: i32, cx: i32, cz: i32): f64
worldgen_block_of(c: i32): i32                             // chunk coord -> lantern-block coord
worldgen_is_lantern_chunk(seed: i32, cx: i32, cz: i32): i32
worldgen_lantern_x(seed: i32, bx: i32, bz: i32): f64       // BLOCK coords, not chunk coords
worldgen_lantern_z(seed: i32, bx: i32, bz: i32): f64

// ---- the batched form: one chunk into caller-owned buffers.  W3-2 calls this.
worldgen_chunk(seed: i32, cx: i32, cz: i32, heights: buffer, biomes: buffer): i32   // -> 81, or 0
worldgen_chunk_height_m(heights: buffer, i: i32, j: i32): f64

// ---- the `chunk.hml` injected-source adapter (W3-2's documented contract),
//      with the arguments in worldgen's own (seed, cx, cz) order.
worldgen_chunk_at(seed, cx, cz, heights: buffer, hoff: i32,
                  attrs: buffer, aoff: i32): i32        // -> META word, or -1
worldgen_meta_poi(meta: i32): i32                       // WG_POI_*
worldgen_meta_tier(meta: i32): i32                      // shade tier at phase 0
worldgen_meta_jitter(meta: i32): i32                    // -1 | 0 | +1
```

`worldgen_chunk_at` writes 81 u16-LE heights at `hoff`, 81 biome bytes at `aoff` and 81 **baked-light
bytes at `aoff + 81` filled with 255**. Worldgen does not bake light — light depends on sun angle and
time of day, neither of which is a property of the world — so the slot is seeded "fully lit" and an
un-baked chunk renders flat bright and obviously unfinished rather than black, which would look
exactly like night and hide the bug. `chunk.hml`'s `chunk_set_light` is where the real bake writes
back. The META word packs bits 0‑2 POI kind, bits 3‑5 shade tier at phase 0, bits 6‑7 jitter + 1.

**The chunk buffer contract.** `worldgen_chunk` writes `WG_CHUNK_SAMPLES` = 81 samples row-major
with x fastest, `index = j*9 + i`, sample `(i,j)` at world `(cx*32 + i*4, cz*32 + j*4)`:

| buffer | layout | minimum size |
|---|---|---|
| `heights` | **u16 little-endian centimetres** at byte offset `index*2` — identical to `heights.read_u16_le(index*2)` | 162 bytes |
| `biomes` | `u8` `WG_BIOME_*` at byte offset `index` | 81 bytes |

It returns 81 on success and **0** if either buffer is undersized — never a partial write, never a
throw. Column `i=8` of chunk `(cx,cz)` and column `i=0` of `(cx+1,cz)` are the same world metres and
therefore the same bytes: the grid is C0-continuous by construction, with no stitching pass.

**Constants:** `WG_CHUNK_N, WG_CHUNK_SAMPLES, WG_CHUNK_M, WG_GRID_M, WG_HEIGHT_STRIDE,
WG_HEIGHT_SCALE_CM, WG_BASE_M, WG_AMP_M, WG_CELL0_M, WG_CELL1_M, WG_CELL2_M, WG_TEMP_CELL_M,
WG_MOIST_CELL_M, WG_BIOME_HOLLOWFIELD..WG_BIOME_DEEPSHADE, WG_BIOME_COUNT,
WG_POI_NONE/LANTERN/RUIN/CARAVAN/SHRINE/BURROW, WG_POI_COUNT, WG_TIER_MAX, WG_TIER_M,
WG_TOWN_TIER_R_M, WG_TOWN_BIOME_R_M, WG_LANTERN_BLOCK_C, WG_LANTERN_INSET_M, WG_LANTERN_MAX_D_M`.

> **Why the biome indices are `WG_`-prefixed.** §5.3 gives `src/art/biome.hml` (Wave 4) the exports
> `BIOME_HOLLOWFIELD..BIOME_DEEPSHADE`, and the import wall forbids `src/art/**` from importing
> `src/sim/**`. Two unprefixed enums naming the same six things in two directories that cannot see
> each other is a divergence waiting to happen. **The indices belong in `src/core/config.hml`**,
> which both zones may import; until someone owns that move, `worldgen.hml` prefixes its copy.

> **Lanterns are structural, not rolled.** GDD §4.4 asks for both "1 per ~4 chunks" *and*
> "guaranteed 1 within 120 m of anywhere". A probability roll delivers the first and can never
> deliver the second. `worldgen` places exactly one lantern per **2×2-chunk block**, inside the
> middle half of the block, which bounds the walk to the nearest lantern at
> `sqrt(48² + 48²) = 67.9 m`. The other four POIs still roll per chunk, with their probabilities
> divided by 0.75 so the world-wide frequency lands on the GDD's 1-in-6 / 1-in-10 / 1-in-14 /
> 1-in-20 rather than 25 % short of it.

#### 5.4b `chunk.hml` — exact signatures (added by W3-2; `chunkmesh.hml`, `terrain_render.hml`, `movement.hml`, `combat.hml`, `build.hml` and the boot path code against these)

One store object owns every loaded chunk. It is allocated **once**, at `chunk_store_new`, and never
grows: two byte arenas (heights, attributes), one 12-byte-per-entry overlay arena, and a fixed set of
per-chunk `array<i32>` tables. Measured RSS over a 10 000-frame streaming traversal: **flat, 0 KB
growth** (`tools/probe_chunk.hml` §9).

```hemlock
// ---- construction.  cap = hard chunk cap; edit_cap = hard overlay cap.
chunk_store_new(): object                                  // g_CHUNK_CACHE (64), 4096 edits, g_WORLD_SEED_DEFAULT
chunk_store_new_cap(cap: i32, edit_cap: i32, seed: i32): object
chunk_set_source(cs: object, f): i32                       // THE GENERATOR — see the contract below
chunk_has_source(cs): i32
chunk_cap(cs): i32 · chunk_resident(cs): i32 · chunk_seed(cs): i32
chunk_set_seed(cs, seed): i32                              // drops residency, KEEPS edits

// ---- keys and coordinates
chunk_key(cx: i32, cz: i32): i32                           // 30-bit pack; identity is (cx,cz), not the key
chunk_sample_index(ix: i32, iz: i32): i32                  // si = iz*9 + ix, -1 if out of range
chunk_at_m(w: f64): i32                                    // world metres -> chunk coordinate (floor)

// ---- residency.  A slot is stable while pinned or until the next evicting get.
chunk_get(cs, cx, cz): i32                                 // slot, or SLOT_NONE (-1): no source, or all pinned
chunk_find(cs, cx, cz): i32                                // lookup WITHOUT loading
chunk_evict(cs, cx, cz): i32                               // 1 evicted / 0 absent / -1 REFUSED (pinned)
chunk_evict_lru(cs): i32 · chunk_drop_all(cs): i32
chunk_pin_ring(cs, ccx, ccz, r): i32                       // unpin all, load+pin (2r+1)^2, return count
chunk_pin(cs, cx, cz, on): i32 · chunk_pinned(cs, slot): i32

// ---- dirty flags: CDIRTY_HEIGHT | CDIRTY_LIGHT | CDIRTY_MESH (CDIRTY_ALL = 7)
chunk_dirty(cs, slot): i32 · chunk_mark_dirty(cs, slot, bits): i32 · chunk_clear_dirty(cs, slot, bits): i32
chunk_meta(cs, slot): i32                                  // the opaque i32 the source returned

// ---- samples.  si = iz*CHUNK_N + ix, 0..80.
chunk_height_gen(cs, slot, si): i32                        // GENERATED cm, edits excluded
chunk_height_cm(cs, slot, si): i32                         // EFFECTIVE cm, edit applied
chunk_biome(cs, slot, si): i32 · chunk_light(cs, slot, si): i32
chunk_set_light(cs, slot, si, v): i32                      // dirties LIGHT|MESH, not HEIGHT

// ---- the two the sim calls.  Bilinear, inside one chunk, no neighbour fetch.
chunk_height_at(cs, wx: f64, wz: f64): f64                 // METRES, or CHUNK_H_MISS (-1000000.0)
chunk_normal_at(cs, wx: f64, wz: f64, out: array<f64>): i32 // out[0..2], analytic gradient of the same patch

// ---- the sparse edit overlay: the world diff, keyed by (cx, cz, si), NEVER baked
chunk_set_edit(cs, cx, cz, si, cm): i32                    // 1 ok / 0 refused (full or out of range)
chunk_clear_edit(cs, cx, cz, si): i32 · chunk_edit_get(cs, cx, cz, si): i32   // cm or EDIT_NONE (-1)
chunk_edit_count(cs): i32 · chunk_edit_cap(cs): i32 · chunk_edit_full_count(cs): i32
chunk_edits_in(cs, cx, cz): i32 · chunk_clear_edits(cs): i32
chunk_edits_bytes(cs): i32                                 // 12 + 16*count
chunk_edits_save(cs, dst: buffer): i32                     // bytes written, -1 if dst too small
chunk_edits_load(cs, src: buffer): i32                     // edits loaded, -1 on bad magic/version/truncation

// ---- counters and accounting (every refusal is visible)
chunk_load_count · chunk_evict_count · chunk_hit_count · chunk_miss_count
chunk_refused_count · chunk_no_source_count · chunk_sample_miss_count
chunk_height_bytes(cs): i32 · chunk_attr_bytes(cs): i32 · chunk_overlay_bytes(cs): i32
chunk_table_entries(cs): i32 · chunk_bytes_per_sample(cs): f64      // 2.00, by construction
```

**Constants:** `CHUNK_N (9), CHUNK_CELLS (8), CHUNK_SAMPLES (81), CHUNK_M (32.0), CHUNK_CELL_M (4.0),
CHUNK_CM_PER_M (100.0), CHUNK_H_MAX_CM (65535), CHUNK_H_STRIDE_B (162), CHUNK_A_STRIDE_B (162),
CHUNK_EDIT_ENTRY_B (12), CHUNK_EDIT_CAP_DEFAULT (4096), SLOT_NONE (-1), EDIT_NONE (-1),
CHUNK_H_MISS (-1000000.0), CDIRTY_NONE/HEIGHT/LIGHT/MESH/ALL, CHUNK_SAVE_MAGIC/VER/HDR_B/REC_B`.

**THE INJECTED-SOURCE CONTRACT.** `chunk.hml` does **not** import `worldgen.hml` — W3-1 and W3-2 were
built in the same sub-wave, and a content dependency inside a wave is exactly what the
WAVE-CONSTRUCTION RULE forbids. The store is handed a generator instead:

```hemlock
fn source(hbuf: buffer, hoff: i32, abuf: buffer, aoff: i32, cx: i32, cz: i32, seed: i32): i32
//   writes 81 u16 LE centimetre heights at BYTE offset hoff of hbuf, si = iz*9 + ix
//   writes 81 biome bytes at aoff, then 81 baked-light bytes at aoff + 81
//   returns one opaque i32, stored verbatim as the chunk's META word
```

With no source installed, `chunk_get` **refuses** (returns `SLOT_NONE`, increments
`chunk_no_source_count`). There is deliberately no fallback terrain in the file to accidentally ship.

**The five-line adapter to `worldgen.hml`** belongs to the boot path (W3-13 / `src/game/main.hml`).
`worldgen_chunk` writes from offset 0 of two dedicated buffers and range-checks their length, so the
adapter owns two scratch buffers allocated **once** (162 B and 81 B) and `memcpy`s 243 B into the
arena per chunk load — ~50 ns against a ≥ 100 µs generation, and zero per-frame allocation:

```hemlock
let g_ws_h: buffer = buffer(162);        // startup, once
let g_ws_b: buffer = buffer(81);
fn ns_chunk_source(p_hbuf: buffer, p_hoff: i32, p_abuf: buffer, p_aoff: i32,
                   p_cx: i32, p_cz: i32, p_seed: i32): i32 {
    worldgen_chunk(p_seed, p_cx, p_cz, g_ws_h, g_ws_b);
    memcpy(ptr_offset(buffer_ptr(p_hbuf), p_hoff, 1), buffer_ptr(g_ws_h), 162);
    memcpy(ptr_offset(buffer_ptr(p_abuf), p_aoff, 1), buffer_ptr(g_ws_b), 81);
    // light is baked later by the day cycle / lanterns; the META word carries the POI roll
    let meta: i32 = worldgen_poi_roll(p_seed, p_cx, p_cz);
    return meta;
}
```

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
| `render_snapshot.hml` | The `RenderSnapshot` SoA of §3.1 + `rsnap_build(rs, world, alpha)`. In v2 the same function reads network snapshots. **§4 stage 4 and §6.3 spell it `snapshot_build`; both names exist and are the same function** (W3-6). Discrete fields (`model/frame/tint/flags`) are sample-and-held at tick n-1 for `alpha < 1` and tick n at `alpha == 1`, so BOTH endpoints reproduce a raw tick state exactly. Entities are matched across ticks by **id**, never by slot. The `rsnap_field_*` arrays must be re-hoisted every frame. | `rsnap_new, rsnap_new_cap, rsnap_reset, rsnap_build, snapshot_build, rsnap_build_from_net, rsnap_netframe_new, rsnap_set_viewer, rsnap_viewer, rsnap_set_eye_height, rsnap_set_cull_radius, rsnap_set_cam, rsnap_set_cam_roll, rsnap_set_cam_fov, rsnap_count, rsnap_cap, rsnap_index_of, rsnap_field_{id,x,y,z,yaw,pitch,model,frame,tint,flags}, rsnap_cam_{x,y,z,yaw,pitch,roll,fov}, rsnap_{alpha,source,builds,rolls,dropped,culled,pops,rehomed,cur_tick,prev_tick}, rsnap_ang_lerp, rsnap_ang_delta, flags_from_sim, RSNAP_CAP, RSF_{VISIBLE,HIT_FLASH,MUZZLE,DISSOLVE,LOCAL,DEAD}, RSNAP_SRC_{SIM,NET}, RSNAP_MISS` |
| `view.hml` | Camera basis from yaw/pitch (never `mat_look_at`), FOV lerp (70 hip / 58 ADS / 78 sprint), screen shake, `recoil_view` (which **never leaves the client**), the MVP. | `view_new, view_build, view_shake, view_mvp, view_eye` |
| `chunkmesh.hml` | Chunk → cached flat vertex arena (LOD0 128 tris / LOD1 32 / LOD2 8) with baked per-vertex lighting, AO in creases, biome tint, and low-frequency value patchiness. Rebuilt only when dirty. | `cmesh_build, cmesh_get, cmesh_invalidate, cmesh_budget_step` |
| `terrain_render.hml` | Ring walk, per-chunk frustum sphere test, LOD selection by distance, skirts, `emit_mesh_buf` per chunk. | `terrain_emit, terrain_stats` |
| `entity_render.hml` | Entities/props/pickups → mesh instances with LOD, hit-flash tint, dissolve scale, **one contact-shadow quad each (mandatory)**, emissive markers into `LAYER_FX`. | `entity_emit` |
| `viewmodel.hml` | First-person weapon: idle sway, footstep bob, fire kick, reload stages, sprint tilt, ADS lerp. `depth = 0.05`, fog `f = 0`. | `vm_new, vm_step, vm_emit, vm_fire, vm_reload_stage` |
| `fx.hml` | Client-only particle SoA (cap 512, negative ids), tracers, muzzle flashes, impact bursts, ember motes, damage numbers, decals, glow cards. | `fx_new, fx_update, fx_emit, fx_spawn_muzzle, fx_spawn_impact, fx_spawn_tracer, fx_spawn_number, fx_spawn_dissolve` |
| `hud.hml` | ART_BIBLE §9 verbatim: crosshair with real spread bloom, hitmarker, health, ammo, compass, minimap, killfeed, XP bar, popups, damage vignette, hit-direction arcs, reload bar, interact prompt. ≤ 250 tris, hard-capped. | `hud_new, hud_build, hud_event, hud_set_tri_cap` |
| `postfx_geo.hml` | Vignette ring (static + damage summed into the same 16 tris), composite MOD overlay (dither + grain + edge bleed, 3 pre-baked variants cycled per frame), sprint speed lines, lightning/level-up flashes. | `postfx_build_overlay, postfx_emit, postfx_flash, postfx_set_vignette` |
| `world_render.hml` | The frame-graph orchestrator: owns the four batches, the RenderEnv, the view/MVP/frustum, the sky mapping and the render-world registry; runs **stages 8–23 (`frame_render`) and 25–28 (`frame_present`)** of §4 in order. **The only file that knows the layer order.** Stage 6 (`tod_eval`), stage 7 (skygen) and stage 24 (the HUD) are the CALLER's — see 5.6b. | `frame_init, frame_batches, frame_begin, frame_render, frame_present, frame_bind_textures, frame_bind_fx_atlas, frame_bind_assets, frame_set_camera, frame_set_clear, frame_set_sheet_clear, frame_set_options, frame_set_hud_solid_uv, frame_set_vignette_colour, frame_set_flash_colour, frame_env, frame_mvp, frame_frustum, frame_batch_sky/world/fx/hud, frame_camera_x/y/z, world_clear, world_chunk_add, world_prop_add, world_fx_add, world_chunk_count, world_chunk_mesh, world_prop_count, world_prop_tag/x/y/z/scale, world_fx_count, terrain_set, terrain_seed, terrain_ridge, terrain_h, vnoise2, h2, sky_basis, sky_uv_at, sky_u, sky_v, g_D2R, g_NEAR, g_GUARD, g_CAP_*, g_FXK_SPRITE/RAIN/TRACER, g_LOD_FOG_CARD` |
| `map.hml` | The world map screen: lit lanterns, Wick Lines, discovered chunks, the obelisk records. (Wave 4.) | `map_build, map_toggle` |
| `menu.hml` | Title, pause, level-up card, unlock card, settings. (Wave 4.) | `menu_build, menu_input, menu_state` |

#### 5.6a `view.hml` — exact signatures (added by W3-5)

The §4 stage-8 sketch reads `view_build(g_view, g_rsnap)`. **The shipped signature
is `view_build(view, dt_seconds, tick)`**, with the camera pushed in beforehand.
Two reasons, both load-bearing:

1. `view.hml` must be drivable by an *interactive* caller (the walkaround reads
   the mouse every frame and there is no snapshot in sight) as well as by a
   scripted one. A `RenderSnapshot` parameter would make mouse-look impossible
   without faking a snapshot.
2. The FOV lerp, the `recoil_view` decay and the shake envelope all run on
   **frame** time, which no snapshot carries. `dt` has to be an argument.

`view_apply_camera` is the one-line bridge W3-7 uses to feed it a snapshot's
`cam_*` fields. `cam_fov` from the snapshot goes to `view_set_fov_target` — the
snapshot carries the *target*, the lerp itself is client-side presentation.

```hemlock
fn view_new(): object                                  // preallocated; call view_build once
fn view_build(v: object, dt_seconds: f64, tick: i32)   // stage 8, once per frame

// camera input — either bridge from a snapshot, or drive it live
fn view_apply_camera(v, x, y, z, yaw, pitch)           // rsnap cam_x/y/z + cam_yaw/cam_pitch
fn view_set_eye(v, x, y, z)
fn view_set_angles(v, yaw, pitch)                      // ABSOLUTE; pitch clamps to +/-85 deg
fn view_look(v, dyaw, dpitch)                          // relative, radians
fn view_look_mouse(v, dx, dy, sens)                    // relative, raw SDL counts; +dy looks down
fn view_sens_scale(v): f64                             // the ADS slowdown
fn view_wrap_pi(a: f64): f64

// projection
fn view_set_viewport(v, w, h)   fn view_set_aspect(v, a)   fn view_set_near(v, n)
fn view_set_fog_far(v, fog_far)                        // clamps to 72; far = fog_far * 1.06
fn view_set_fov_mode(v, mode)   fn view_set_fov_target(v, deg)   fn view_snap_fov(v)
fn view_fov_for_mode(mode: i32): f64
constants g_VIEW_HIP / g_VIEW_ADS / g_VIEW_SPRINT

// client-only cosmetics — see the recoil_view wall below
fn view_kick(v, dpitch, dyaw, droll)   fn view_kick_fire(v, scale, lateral)
fn view_clear_kick(v)                  fn view_set_roll(v, roll)
fn view_shake(v, amount01)             fn view_shake_fire(v)
fn view_clear_shake(v)                 fn view_set_seed(v, seed: i32)

// readers
fn view_mvp(v): array                  // retained; hand to emit_set_mvp / frustum_from_mvp
fn view_matrix(v): array               fn view_mvp_at(v, i): f64
fn view_eye(v): object                 fn view_eye_x|y|z(v): f64
fn view_aim_yaw|aim_pitch(v): f64      // AUTHORITATIVE. Recoil-free. Goes to cmd_set.
fn view_aim_forward_x|y|z(v): f64      // AUTHORITATIVE. What a bullet uses.
fn view_render_yaw|render_pitch|render_roll(v): f64   // CLIENT-ONLY. MVP only.
fn view_kick_pitch|kick_yaw|kick_roll(v): f64
fn view_fov|fov_target|aspect|near|far|fog_far|trauma|shake_x|shake_y(v): f64
fn view_fov_mode(v): i32               fn view_tick(v): i32
fn view_project(v, x, y, z, out: array<f64>): i32      // cold; [sx, sy, w, ndc_z]
```

**The two angle pairs are the whole point of the module.** `view_aim_*` is
bit-identical to what the caller set and is the pair that reaches
`sim_apply_command`; `view_render_*` is `aim + recoil_view` and reaches nothing
but the MVP. Screen shake is deliberately **not** in the MVP — it is a
present-time translation via `target_set_shake`, so frustum culling stays stable
while the screen shakes.

#### 5.6b `src/render/**` MAY NOT IMPORT `src/art/**` — found by W3-0a, and it is load-bearing

`ci_imports.sh` R1 allows the render zone wobbleweed, `src/core/**`, `src/sim/**` and `@stdlib/*`.
It does **not** allow `src/art/**`, and CLAUDE.md §3's table says the same. That is a real
constraint, not an oversight in the script: it is what keeps the renderer testable without an art
pipeline and what stops colour from leaking into geometry code.

**Consequence, discovered while extracting the frame graph out of `tools/shot.hml`:** everything
art-derived must arrive at a render module as a **handle or a number**, never as an import.
`world_render.hml` therefore takes texture handles, an atlas handle, mesh handles, atlas cell ids,
uv rects and rgb triples through `frame_bind_*` / `frame_set_*` / `world_*_add`, and §4's stages 6
(`tod_eval`) and 7 (`skygen_rebake_slice`) stay with the caller — which is where §4 already puts
them, in the SNAPSHOT block above VIEW. Two knock-ons for the rest of Wave 3:

* `hud.hml`, `fx.hml`, `entity_render.hml`, `postfx_geo.hml` and `terrain_render.hml` hit the same
  wall. Each needs the same treatment: the art module is called by `src/game/assets.hml` (or by the
  tool), and the render module is handed the result.
* The frame graph is consequently **two calls with a hole in the middle** — `frame_render()` ends
  after stage 23 (the vignette, already in `LAYER_HUD`), the caller emits stage 24 into
  `frame_batch_hud()`, and `frame_present()` runs 25–28. `LAYER_HUD` is flushed in insertion order,
  so this preserves the postfx-under-HUD order exactly; it is the only structural difference
  between the extracted graph and the Wave-2 function it came from.

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
| `meshgen.hml` | **(added by W2-8.)** The driver for `src/art/meshgen.hml`. `--verify` is the W2-8 acceptance suite (163 assertions: budgets, asymmetry, head:shoulder, protrusions, weapon silhouettes, the luminance floor, determinism). `--contact-sheet <png>` renders every mesh at 32×32, 12 px and 6 px on light and dark backgrounds for the visual critic; `--inspect <png>` at 96 px; `--big <id> --out <png>` at 256 px. Software-rasterized in Hemlock: **no SDL is linked.** |
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
