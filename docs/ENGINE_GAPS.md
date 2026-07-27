# ENGINE GAPS — the prioritized change list for `/home/nbeerbower/Projects/wobbleweed`

**Scope:** everything Nightshade needs from the engine, as scoped, verifiable work items.
**Governing rule (R1 from `ARCHITECTURE.md`):** wobbleweed is a **reusable retro-3D engine**, not
Nightshade. No engine symbol may contain a game word (`lantern`, `husk`, `ember`, `shade`, `wisp`) or
a specific colour. The engine exposes *parameters*; the game supplies *values*.
**The test for every item below:** could a different PS1-style game use this file unmodified?

**Two invariants across all items:**

1. **`hemlockc` is the only ground truth.** The interpreter emits different geometry and different
   pixels for the same scene (wobbleweed-api §11.2: 404 vs 425 triangles). Every acceptance
   criterion below is evaluated on a `hemlockc`-compiled binary. Interpreted runs are for tooling.
2. **SDL runtime is 2.0.18**, headers are 2.0.20, and `pkg-config` lies. **Never bind a symbol added
   after 2.0.18.** Check the `\version` line in the header doc-comment and smoke-test that the symbol
   resolves. `SDL_RenderGeometry` (2.0.18) is exactly at the boundary.

---

## P0 — Correctness. Nothing else is worth doing until these are true.

### ~~G1. `batch_flush` hands SDL the same memory for several queued draws~~
### G1. NOT A BUG — MISDIAGNOSIS. Demoted from P0 to a P1 *performance* option.
**Files:** `src/batch.hml` (new; supersedes `src/geom.hml`)
**Severity:** none. There is no correctness defect here.

> **Do not implement this as a correctness fix.** The flat-cloudless-sky symptom was **not** SDL
> buffer aliasing. It was the hemlock interpreter/compiler divergence, fixed upstream in
> `ed12be28` and re-verified on `cb7fbfaa`. The **unmodified** `geom.hml` now renders correctly on
> both backends:
> ```
> interpreted: top-left px = 60,100,196   mid px = 82,121,203
> compiled:    top-left px = 60,100,196   mid px = 82,121,203
> ```
> `SDL_RenderGeometry` **copies** vertex data into the render command queue at call time, so
> reusing one buffer between calls was always safe. See `HEMLOCK_ISSUES.md` H-3.

**What survives:** the frame-long disjoint vertex arena is still a plausible *performance* change
(one contiguous fill, no rewind, natural fit for the per-frame arena in G6). It is now folded into
**G6**, where it must be justified by a benchmark like every other budget change.

**Acceptance (if done at all):** a measured throughput delta at 500/2000/3500 triangles. Identical
framebuffer checksum before and after. No pixel may change.

---

### G2. `batch_new(cap)` is never enforced → heap corruption on overflow
**Files:** `src/batch.hml`
**Severity:** silent heap smash. Reproduced: 4000 triangles into `batch_new(16)` dies with
`Object has no field 'tex'` from deep inside the runtime.

**Fix:** `batch_reserve(b, n)` returns a byte cursor or `-1` when `b.n + n > b.cap`. On `-1` the
caller drops the triangle and `stat_inc(STAT_BATCH_OVERFLOW)`. An open world with variable draw
distance *will* exceed any fixed cap; it must degrade, not corrupt.

**Acceptance:** pushing 10× `cap` triangles completes cleanly, renders the first `cap`, and reports
the exact overflow count. Run under `valgrind` with zero invalid writes.

---

### G3. `array.sort(closure)` is quadratic on exactly the data a game produces
**Files:** `src/batch.hml`
**Severity:** the project-ending one. Measured, compiled, 2000 triangles:
1.20 ms random / **106.9 ms already-sorted** / **143.1 ms coplanar**. At 8000 coplanar: **2.4 s per
frame**. Coplanar is a floor. Already-sorted is a chunk list walked front-to-back. These are the two
most common shapes in the game, not corner cases. Recursion depth is O(n) on sorted input, so a large
batch is also a latent stack-overflow crash (`hml_array_sort` is a non-randomized Lomuto quicksort
with a last-element pivot, no median-of-three, no introsort fallback).

**Fix:** O(n) bucketed counting sort on quantized depth, NB = 2048 over the draw distance.
Implementation notes, learned the hard way by recon — obey them:
- **Recompute the bucket index in the scatter pass.** Caching it back onto anything (`t.bk = k`)
  triggers a storage grow + hash rebuild and measures ~2× slower.
- **Counters go in a Hemlock `array<i32>`, not a raw buffer.** 0.78 vs 0.93 ms at 8000 tris; array
  indexing has an inlined fast path, `ptr_deref_i32` does not.
- Preallocate `counts` and `order` once at startup; `clear`/overwrite, never rebuild.

**Acceptance:**
- Sort cost at 2500 triangles < 0.5 ms for **all three** depth distributions (random / ramp / flat),
  measured by `tools/benchframe.hml`.
- Cost varies < 20 % across the three distributions (input-order independence is the point).
- Ordering correct to one bucket quantum: max adjacent-pair depth violation ≤ `FOG_FAR / 2048`.
- 32 000 triangles sorts without a stack overflow.

---

### G4. The painter key is NDC z; it must be view-space depth
**Files:** `src/batch.hml`, `src/emit.hml`
**Severity:** invisible today, fatal at range.

`SDL_Vertex` is 2D, so the vertex `z` never reaches the rasterizer — it is *only* the painter key,
which makes it a free choice. NDC z for `near=0.1` is `1.001 − 0.2001/d`: one bucket of quantization
error is 3.2 cm at 3 m but **35 m at 100 m**. View-space `w` is 3.1 cm everywhere.

**Fix:** `b.depth[k]` is the triangle's view-space depth (average of the three clip `w`). Larger =
farther. The sky is pushed at `depth = FAR`, **not** the current `z = 2.0` (an NDC value that means
nothing in this space).

**Acceptance:** worst adjacent-pair violation ≤ 3.5 cm at every distance out to `FOG_FAR`; a sky quad
and a 70 m hill sort correctly.

---

### ✅ G5. `SDL_SetTextureScaleMode` segfaults the whole GPU path on a real display
### DONE — merged upstream as Wobbleweed PR #2 (`905700c`, merged in `8111c43`). No work required.
**Files:** `src/sdl.hml` — **already on `main`. Do not re-apply; just do not regress it.**

> Verified by the orchestrator on both sides of the change: `examples/walk_gpu.hml` dumps core
> before it and runs clean after. Now merged, so a fresh `main` checkout already has it.
**Severity:** was an instant crash on startup on any real display, hidden by headless testing.

Cause: `RGB24` is not an OpenGL-renderer-native format, so SDL allocates an internal conversion
texture, and SDL 2.0.20 faults in the scale-mode path on those. Fix applied: set
`SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")` once at startup (`SDL_CreateTexture` reads it) and
delete the per-texture call.

**Acceptance:** `examples/walk_gpu.hml` runs on the real display (it does — 121 fps measured),
nearest filtering intact, headless numbers unchanged. Additionally G13 removes the root cause by
never creating a non-native texture.

---

## P1 — The budget rewrite. This decides whether the game is 1870 triangles or 5000.

### G6. Per-vertex object allocation dominates the frame
**Files:** `src/emit.hml` (new), `src/shade.hml` (new), `src/clip.hml` (rewrite)
**Severity:** ~12 heap allocations per triangle, 24 000 per frame at 2000 triangles, ≈ 2 µs of pure
allocation per triangle. Directly responsible for `emit = 10 ms`.

Per triangle today: 3 × `mat_apply` `{x,y,z,w}` + 3 × clip vertex `{x,y,z,w,u,v,l}` + 3 × screen
vertex `{x,y,z,u,v,r,g,b}` + 1 batch record + the nested arrays `clip_tri_near` and `clip_tri_rect`
return *even on the accept path*.

**This is all-or-nothing.** Recon measured a half-measure (`flat`: flatten only the back half) at
**no gain** — within noise of the object path, because the front-half allocations dominate and you
pay to convert representations. Flattening end-to-end is 1.8×–3.3×; writing `SDL_Vertex` bytes at
push time is a further 1.16×–1.27×.

**Fix — `emit.hml` is written to these rules, without exception:**
- Native `f64` locals only. No object or array literal anywhere in the loop.
- The 16 MVP elements hoisted into 16 named `f64` locals **once per frame**, before the loop.
- Every parameter copied into a typed local (`let n: i32 = n0;`) — parameters are never unboxed.
- Return by copy-out (`let out: f64 = acc; return out;`) — a bare-identifier return escapes.
- No closure literal anywhere in a function containing a hot loop (escape analysis is conservative:
  any `EXPR_FUNCTION` later in the block de-optimizes the whole block).
- No `defer` (+70 ns on *every* call to the enclosing function), no `try`/`catch`, no `throw`
  (leaks ~192 B of heap locals per throw when compiled), no template strings.
- Write straight into the vertex arena with `ptr_write_f32` / `ptr_write_u8` on a **hoisted** base
  pointer.
- Fast paths that skip `clip.hml` entirely when all `w > near` and all screen coords are inside the
  guard rect — which is the overwhelming majority of triangles.

**Acceptance:**
- `tools/benchframe.hml`: emit + pack ≤ **3.0 ms at 2500 triangles**, ≤ 12.5 ms at 8000.
- `hemlockc -c --emit-c` shows `double` (not `HmlValue`) for the 16 matrix locals and the 12 named
  hot locals — wired into `tools/ci_unbox.sh`.
- Framebuffer checksum **identical** to the object path on the same scene. The optimization trades no
  image quality; recon proved this for every representation.

---

### G7. Clipping allocates on the accept path
**Files:** `src/clip.hml`
**Severity:** `clip_tri_near` returns `[[a,b,c]]` (two array allocations) and `clip_tri_rect` the
same, on **every** triangle, for a function whose common answer is "yes, unchanged". That is most of
the measured 205 ns and 475 ns per triangle. `clip_half` also takes a closure, so each non-trivial
clip allocates 4 closures.

**Fix:** the fast path becomes a pure predicate returning `CLIP_IN` / `CLIP_OUT` / `CLIP_STRADDLE`,
writing nothing. Straddling triangles — measured at ~7 µs vs ~0.7 µs, i.e. 10× — fall back to a slow
object path that writes into caller-owned buffers. The fallback is allowed to be slow because it is
rare.

**Acceptance:** accept-path cost < 40 ns/triangle. Zero allocations on the accept path (verified by
RSS stability over 10 000 frames). **Budget the straddle rate explicitly:** `stats.hml` counts it; if
it exceeds 10 % of submitted triangles, that is a bug report, not a tuning knob.

---

### G8. No frustum culling; the guard band is 31× the screen area
**Files:** `src/frustum.hml` (new), consumed by the game's chunk walk
**Severity:** every triangle handed to the renderer pays full projection + clip cost even when it is
directly behind the player. For an open world this is fatal — you cannot stream chunks if every
loaded chunk costs full emit.

**Fix, three tiers:**
1. Gribb–Hartmann 6-plane extraction from the MVP (~30 lines), `frustum_sphere` / `frustum_aabb`.
   Six dot products rejects a whole chunk. Expect 3–5× fewer emitted triangles at 70° FOV.
2. A hard distance ring paired with fog, so the cutoff is invisible.
3. Per-triangle backface cull inside the emit loop: after projection, the sign of
   `(bx-ax)*(cy-ay) − (by-ay)*(cx-ax)`. One subtract-multiply-subtract kills ~half the triangles of
   any closed mesh **before they enter the sort**, which matters more than the emit saving.

Planes live in a flat `array<f64>` of 24. No objects.

**Acceptance:** with a 5×5 chunk ring at 70° FOV, ≥ 55 % of chunks are rejected and the reported
submitted-triangle count drops correspondingly; backface cull removes ≥ 40 % of mesh triangles; both
counters appear in `stats.hml`. Rendering is pixel-identical with culling on and off for any camera
that has no geometry behind it.

---

## P2 — Make it a game engine. Nightshade cannot start without these.

### G9. No mouse look
**Files:** `src/sdl.hml`, `src/input.hml` (new)
**Severity:** there is no FPS without it. `poll()` today handles `SDL_QUIT` and `SDL_KEYDOWN` only;
the examples turn with the arrow keys.

**Fix:** `SDL_SetRelativeMouseMode(1)` + `SDL_GetRelativeMouseState(&dx, &dy)`. **Use the API calls,
not `SDL_Event` byte offsets** — the offsets are verified (motion `xrel@28`, `yrel@32`, event 56 B)
but the API cannot silently break. Extend event handling to `SDL_KEYUP` (0x301),
`SDL_MOUSEBUTTONDOWN/UP` (0x401/0x402) and `SDL_MOUSEWHEEL` (0x403) so the input layer can track
press/release edges and weapon switching. `input.hml` owns the held/pressed/released state and the
action map.

**The one real limitation, and it must be handled, not worked around:**
`SDL_SetRelativeMouseMode` returns **-1 under `SDL_VIDEODRIVER=dummy`** ("No relative mode
implementation available"). The `WARP` hint does not rescue it. Mouse look cannot be headless-CI
tested.

**Acceptance:**
- On the real display: relative mode returns 0, `dx`/`dy` are live, cursor hidden.
- Headless: relative mode returns -1, `input_set_relative` reports failure, **the program continues
  and renders normally**. `tools/shot.hml` must never crash on this.
- Edge detection is exact: a key pressed and released within one frame reports one `pressed` and one
  `released`.
- Note for testing: warping the pointer gives `xrel = 0` *by design*, so a warp-based test proves
  nothing. Recon drove real motion with `XTestFakeMotionEvent`.

---

### G10. No frame-rate-independent timing
**Files:** `src/time.hml` (new), `src/sdl.hml`
**Severity:** the examples move by `move_speed` **per frame** with a fixed `delay(4)`. Frame rate
swings 267 → 25 fps here, so the player would move 10× faster looking at the sky. It is also a desync
generator for v2.

**Fix:** `SDL_GetPerformanceCounter` / `SDL_GetPerformanceFrequency` (both 2.0.18; freq = 1e9 on this
box; u64 FFI returns are exact to u64 max — no 2^53 workaround needed). `ticks()` (`SDL_GetTicks`)
is 1 ms resolution and wraps; keep it only for coarse logging. `time.hml` provides the fixed-step
accumulator with a 250 ms spiral-of-death clamp.

`SDL_RenderSetVSync` returns -1 on software renderers and 0 on a real GPU: **treat non-zero as
"unavailable", never as fatal.**

**Acceptance:** a 10 000-frame run with artificially injected stalls advances exactly
`floor(total_ms / TICK_MS)` ticks. Movement distance over 10 s is identical at 30 fps and 240 fps.

---

### G11. Vertex alpha is hardcoded 255; no blend mode is ever set
**Files:** `src/sdl.hml`, `src/batch.hml`, `src/emit.hml`
**Severity:** blocks particles, muzzle flashes, glass, HUD plates, fades, damage vignettes, ghost
building previews, and — most importantly — **distance fog**.

Verified working end-to-end by two independent recon agents: a 50 %-alpha white triangle over pure
blue read back as exactly `(127, 127, 253)`; `BLEND` 255@a128→128, `ADD` 40+60→100, `AlphaMod`
→(128,64,0), `ColorMod` →(0,128,0). Headless and on a real GPU.

**Fix:** `SDL_SetTextureBlendMode` / `SDL_SetRenderDrawBlendMode` externs
(`BLENDMODE_NONE=0, BLEND=1, ADD=2, MOD=4`); `put_vert` writes the caller's alpha at byte offset 11;
blend mode is set per texture at upload (which is what makes blend mode the material model).

**Acceptance:** the four blend modes each produce their exact expected readback bytes, headless and
on the real display, compiled. A fully transparent triangle changes no pixels.

---

### G12. No render target; nothing is chunky where it should be
**Files:** `src/sdl.hml`, `src/target.hml` (new)
**Severity:** `SDL_RenderSetLogicalSize` scales the *rasterization*, so polygon edges are smooth at
window resolution — the signature PS1 look is entirely absent on the shipping path. There is also
nowhere to hang a full-screen effect.

**Fix:** a 320×240 `SDL_TEXTUREACCESS_TARGET` texture in **`ARGB8888` (372645892)** — the format
HOST_FACTS verified end-to-end for targets. Render everything into it, restore the backbuffer with
`SDL_SetRenderTarget(ren, null)`, then `SDL_RenderCopyEx` it to the window at an integer scale with a
shake offset.

**`SDL_RenderCopyEx`'s `angle` is a C `double`.** It must be passed as `f64` — `0.0`, never `0`.
This is the single easiest way to corrupt the call.

**Acceptance:** a diagonal edge in the output PNG shows hard 3×3 pixel blocks at scale 3.
`SDL_RenderGeometry` draws into the target correctly (verified by recon). The full chain
geometry → target → upscale-with-shake → additive flash → alpha HUD is byte-identical on the software
and OpenGL renderers.

---

### G13. Textures are `RGB24`, which no renderer supports natively
**Files:** `src/texture.hml`, `src/atlas.hml` (new), `src/sdl.hml`
**Severity:** SDL silently allocates a conversion texture per upload (a per-frame copy for streaming
textures, and the root cause of the G5 crash class).

**Fix:** all textures become **`SDL_PIXELFORMAT_RGBA32` = 376840196**, whose *memory byte order is
R, G, B, A* — verified by readback, and the natural order for procedural generators. Note the `*8888`
names are packed-integer names, **not** byte order: `ARGB8888` is really B,G,R,A in memory. Keep
`RGB24` (386930691) only for the legacy CPU framebuffer.

`atlas.hml` adds the cell abstraction: cell → UV rect **inset by half a texel** (`+0.5/N`, `-0.5/N`),
without which nearest sampling bleeds neighbouring cells at grazing angles. Plus dirty-rect
`SDL_UpdateTexture` for the incremental sky re-bake.

**Acceptance:** a known RGBA pattern uploaded and read back matches byte-for-byte. No SDL conversion
texture is created (verify by format query). A 32×32 cell at the atlas edge never samples its
neighbour at any grazing angle in a 3-minute camera sweep.

---

### G14. No 2D/HUD layer, no text
**Files:** `src/quad.hml` (new), `src/font.hml` (new), `src/batch.hml`
**Severity:** a CoD-like *is* its HUD. No crosshair, health, ammo, hitmarker, killfeed, prompts,
subtitles, NPC dialogue (which the cozy-hub pillar requires), menus, or debug overlay.

**Fix:** screen-space quads are already the native currency — a HUD layer is just a batch that is
never depth-sorted, flushed last, in the 320×240 target's coordinates. `font.hml` is a **generic**
bitmap font: the caller registers glyphs as packed bitfields and a codepoint→cell map; the engine
bakes them into an atlas and emits 2 triangles per glyph with an optional (+1,+1) shadow pass. The
engine ships **no glyph data** — the game's `hudgen.hml` supplies it (R1).

**Budget caution:** text is triangle-hungry. 200 characters = 400 triangles = 16 % of the budget.
`font_text` takes a triangle budget and truncates rather than overflowing.

**Acceptance:** 250 HUD triangles render in ≤ 0.3 ms in one draw call. Glyphs are pixel-exact (no
filtering) at the target resolution. A text string longer than the budget truncates with a reported
count and never overflows the batch.

---

### G15. No fog
**Files:** `src/shade.hml` (new), `src/emit.hml`
**Severity:** without fog you cannot hide the draw-distance cutoff, so an "infinite" world either
pops or renders far more than the budget allows. It is also the single cheapest mood lever available,
and the current renderer's total absence of atmospheric perspective is *the* reason the baseline
screenshots read as a green rug on a blue wall.

**Fix (generic — colours are parameters):** `shade.hml` owns a `RenderEnv` of flat `f64`s: sun dir +
RGB, ambient RGB, bounce RGB, rim RGB, up to 4 point lights, `fog_near`, `fog_far`, fog tint RGB,
`fog_alpha_max`, `mist_top`, `mist_bottom`, `mist_density`. `emit.hml` folds them in per vertex:

```
d = radial distance camera→vertex        (radial, not view-z — view-z thins fog at screen edges)
t = clamp((d - fog_near) / (fog_far - fog_near), 0, 1)
f = t*t*(3-2*t)                          (smoothstep: crisp near field, hard far falloff)
h = clamp((mist_top - y) / (mist_top - mist_bottom), 0, 1);  f = max(f, h*h*mist_density)
rgb = light * lerp(1, fog_tint, f)
a   = 255                          when f < 0.35        (ARCHITECTURE D7)
a   = 255 * (1 - fog_alpha_max * (f-0.35)/0.65)   otherwise
```

Both channels are needed: the multiply alone cannot reach the sky's brightness; the alpha alone
leaves distant geometry the wrong hue.

**Acceptance:**
- Zero extra triangles, zero extra draw calls, ≤ 0.15 ms added at 2500 triangles.
- **The blend cost is measured, not assumed:** report frame time with `fog_alpha_max = 0` vs the
  shipping value on the software renderer at 320×240. If alpha costs > 1.0 ms, raise the 0.35
  threshold until it does not. (This is the open question behind D7.)
- The far plane becomes `fog_far * 1.06`, not a hardcoded 200.0. Nothing ever appears unfogged.

### G16. Lighting is one hardcoded scalar
**Files:** `src/shade.hml`, `src/emit.hml`, `src/mesh.hml`
**Severity:** `SUN` and `AMBIENT` are module-level constants in both scene files, and the ground is
lit by **one** number computed once for all 256 quads — which is why the ground reads as cardboard.

**Fix:** the full per-vertex model, all inputs, no game knowledge:
`ambient + sun·max(0,N·L) + bounce·max(0,-N.y) + rim·(1-max(0,N·V))³ + Σ up to 4 point lights`
with a `max(0.25, N·L)` floor on point lights so a muzzle flash reads as an omnidirectional pop
rather than a hard spot. Clamp per channel. `mesh_bake_light` bakes static lighting into vertex
colour at build time so it costs nothing at runtime.

**Cost check:** two dots + a cube + a clamp per vertex, ~5 ops per dynamic light; ~60 k float ops per
frame at 4000 vertices with 2 lights. Negligible compiled.

**Acceptance:** 4 dynamic point lights at 2500 triangles cost ≤ 0.4 ms. A point light visibly
brightens nearby geometry in a headless PNG. `ambient + sun` summing to exactly (1,1,1) reproduces a
surface's authored albedo exactly — verify by pixel readback against the source texel.

---

### G17. No billboards / particles
**Files:** `src/billboard.hml` (new)
**Severity:** "juice" in a CoD-like is 70 % particles. No muzzle flash, sparks, blood, smoke, tracers,
explosions, pickup sparkle, rain, dust, damage numbers, or distant-tree impostors.

**Fix:** project the centre once, emit a screen-aligned quad of size
`world_size * proj_scale / w` with atlas UVs and a vertex-colour tint/fade. Plus a stretched variant
(tracers, rain) that orients along a world-space vector. The particle *pool* is the game's — the
engine only provides the emit primitive (R1).

**Acceptance:** 300 billboards (600 triangles) emit in ≤ 0.9 ms. A billboard holds constant screen
size when the camera dollies, and constant world size when it does not.

### G18. No audio
**Files:** `src/audio.hml` (new), `src/sdl.hml`
**Severity:** gunfeel is at least half audio; it is the cheapest juice per byte in the project.

**Fix — SDL2_mixer** (ARCHITECTURE D3). Verified on this box: `Mix_Linked_Version` 2.0.4,
`Mix_OpenAudio(22050, AUDIO_S16LSB, 1, 512)` → 0, `Mix_AllocateChannels(16)`, `Mix_QuickLoad_RAW` on
a procedural Hemlock buffer, **6 overlapping voices**, `Mix_SetPanning` per channel, interpreted and
compiled, dummy and real device.

Three gotchas that will each cost an hour:
1. **`Mix_PlayChannel` and `Mix_LoadWAV` are C preprocessor macros, not exported symbols.**
   `extern fn` against them fails. Bind `Mix_PlayChannelTimed(channel, chunk, loops, -1)` and
   `Mix_LoadWAV_RW(...)`.
2. **`Mix_QuickLoad_RAW` does not copy.** The `Mix_Chunk` points straight at our Hemlock buffer. The
   buffer must outlive every possible playback. `audio.hml` keeps every registered PCM buffer in one
   long-lived table it owns for the process lifetime. A use-after-free here is a crash months later.
3. **Group each library's externs under its own `import`.** An `extern fn` binds to the *most
   recently declared* `import`, not to all libraries. Multi-library FFI works fine once you do this.

`SDL_QueueAudio` + `SDL_MixAudioFormat` stays documented as the fallback behind the same interface
(callback = NULL selects queue mode, so Hemlock never hands a function pointer back to C — pass
`device` as a `ptr`, not a `string`, so NULL works).

**Acceptance:** 8 simultaneous voices with distinct pans play without dropout; ≤ 0.2 ms/frame of
Hemlock time; a 10-minute soak shows no RSS growth and no use-after-free under `valgrind`; audio
initialises or fails gracefully under the dummy driver without aborting the program.

---

## P3 — Structure. Needed once more than one system is real.

### G19. No runtime mesh format; meshes cannot be textured; normals are recomputed every frame
**Files:** `src/mesh.hml` (new)
**Severity:** three defects, one fix. `mesh.uv` is parsed by the OBJ loader and **thrown away** —
both renderers pass hardcoded UV (0,0), so nothing can be textured. `render_mesh_gpu` does three
`v_norm(mat_apply_dir(...))` per **face** per **frame**: 50 trees ≈ 4 800 normalizes and ~10 000
allocations per frame for lighting that never changes. Loading is line-by-line text parsing.

**Fix:** a flat runtime mesh — one `ptr` arena, **24 bytes per vertex** (pos f32×3, uv f32×2, rgb
u8×3, pad u8), non-indexed (the painter sort is per-triangle anyway, and indirection costs more than
the memory saves). Lighting is baked into vertex colour at build time by `mesh_bake_light`. Per frame
the emitter only transforms and packs. For a yaw-only instance, transform the light into model space
once per instance instead of transforming every normal into world space.

**Acceptance:** 20 tree instances (1920 triangles) emit in ≤ 2.3 ms with zero allocations. Textured
meshes sample the atlas correctly. Normals are transformed zero times per frame for a static prop.

### G20. `mat_look_at` degenerates; the vector library is missing FPS primitives
**Files:** `src/vec.hml`
**Severity:** `mat_look_at` breaks when forward is parallel to up. The examples dodge it by clamping
pitch to ±1.4 rad (±80°). An FPS needs ±85° and a proper basis construction. Also missing:
`mat_rot_z`, matrix inverse, `v_lerp`, `v_dist`, `v_reflect`, and every ray/AABB/plane helper — i.e.
everything hitscan, recoil, and collision need.

**Fix:** add `mat_look_dir(eye, yaw, pitch)` building the basis from angles directly (no cross-product
degeneracy, and it is what an FPS camera actually wants), plus `mat_rot_z`, `mat_invert_rigid`,
`v_lerp`, `v_dist`, `v_dist2`, `v_reflect`, `ray_aabb`, `ray_plane`, `aabb_overlap`. These are
setup-time/gameplay APIs — objects are fine here; they are not in the per-vertex loop.

**Acceptance:** pitch of ±89.9° produces a stable, non-degenerate view matrix. `ray_aabb` agrees with
a brute-force reference on 10 000 random cases.

### G21. No engine lifecycle; textures and buffers leak
**Files:** `src/engine.hml` (new), `src/sdl.hml`
**Severity:** `window_close` destroys only `w.tex`; every uploaded `SDL_Texture` leaks, and the
`alloc`'d `b.buf` and `w.ev` are never freed. There is no init/shutdown ordering and no asset
registry.

**Fix:** a thin `engine.hml` owning `engine_init` → `engine_shutdown`, a texture registry with a
`SDL_DestroyTexture` sweep, and a documented teardown order (audio → target → textures → renderer →
window → SDL_Quit). Note `alloc()` is never reclaimed for you; `buffer`/`array`/`object` are
refcounted and must **not** be `free()`d while reachable from a top-level `let`.

**Acceptance:** a 10 000-frame run shows a flat `/proc/self/statm`; `valgrind` reports no
still-reachable SDL textures at exit.

### G22. No per-frame instrumentation
**Files:** `src/stats.hml` (new)
**Severity:** PERF.md exists only because the pipeline was ablatable. Losing that is losing the
ability to answer "why is it slow" ever again.

**Fix:** a fixed-index counter/timer array (no string keys, no objects) compiled into shipping
builds: triangles submitted per layer, rejections per cull stage, straddle-fallback count, batch
overflows, draw calls, and per-stage timings for emit / sort / flush / present. `stat_report_string`
is built at most 4 Hz (a template string is ~165 ns; a per-frame debug overlay is fine, hundreds are
not).

**Acceptance:** total instrumentation overhead ≤ 0.05 ms/frame. Every number in the
`ARCHITECTURE.md` §4 frame graph is reportable by `tools/benchframe.hml`.

---

## P4 — Deliberately not doing

| Not doing | Why |
|---|---|
| **A z-buffer** | `SDL_Vertex` cannot express one. The answer is layers + a fine bucket sort + authoring the world so large surfaces do not interpenetrate. This is what PS1 games actually did. |
| **Fixing the CPU rasterizer** | 8 fps at 320×240 with 560 triangles, ~4.5 Mpixel/s. It is 2–3× short at the lowest interesting resolution before any gameplay. Formally designated offline/test-only and frozen. |
| **A PNG reader** | ARCHITECTURE D4 — all art is procedural. The writer stays for screenshots. |
| **Texture-atlas batching for performance** | PERF §8: 2000 draw calls cost 0.3 ms more than 1. Atlasing is adopted for the *material model* (blend mode is per texture), not for speed. Do not build a batching scheme. |
| **`spawn`/`join` parallel emit** | ARCHITECTURE D10. `spawn()` deep-copies objects; 2500 tris fits single-threaded. The escape hatch if a measured breach cannot be solved by `FOG_FAR`. |
| **`define` structs for hot data** | Measured at 223 ns for 7 fields — identical to a plain object. They are FFI layout descriptors, not value types. |
| **`@inline`** | A literal no-op: it emits `always_inline` on a function gcc then refuses to inline, and you get a build warning. If you need it inlined, write it inline. |
| **Any SDL symbol newer than 2.0.18** | The runtime is 2.0.18; the headers and `pkg-config` say 2.0.20 and are lying. A symbol can exist in the header and fail to resolve at runtime. |

---

## Ordering summary

```
P0  G1 G2 G3 G4 G5     correctness — the renderer is wrong or crashes without these
P1  G6 G7 G8           the budget rewrite — decides 1870 vs 5000 triangles
P2  G9 … G18           the engine becomes a game engine
P3  G19 … G22          structure for a team
```

**Re-measure after P1 and before any content authoring.** Every subsequent design decision — how many
enemies on screen, how far `FOG_FAR` goes, whether a biome can afford 140 billboards — keys off that
number. Recon's expectation is ~5000 triangles renderer-only, 2500 shipping. Confirm it.
