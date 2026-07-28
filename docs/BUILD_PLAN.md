# NIGHTSHADE — BUILD PLAN

**Reads with:** `ARCHITECTURE.md` (what exists and why), `ENGINE_GAPS.md` (the engine work items,
`G1`–`G22`), `/CLAUDE.md` (the rules).

**71 tasks in 7 waves.** Every task inside a wave owns a **disjoint** set of files, so all tasks in a
wave run fully in parallel. Ownership is exclusive **within a wave**; a later wave may edit a file an
earlier wave created.

---

## How a wave works

1. Every task codes against the signatures written in `ARCHITECTURE.md` §5 and in its own task block
   below. **A task may reference a module it cannot yet compile against** — that is what the written
   signature is for. Do not invent a signature; if one is missing, add it to `ARCHITECTURE.md` §5 and
   say so in the task report.
2. Every task ships with its own verification program. No task is "done" because it compiles.
3. **A wave closes on a gate** — the orchestrator runs the gate; if it fails the wave does not close.

### Universal acceptance criteria (every task, all 71)

| | Criterion |
|---|---|
| A | `hemlockc --check <file>` clean (instantaneous) |
| B | `hemlockc -O1` builds the module's verification program with zero warnings |
| C | `tools/ci_imports.sh` passes: import wall intact, no legacy-module import, every top-level variable `g_`-prefixed |
| D | No object/array literal, no closure, no `defer`, no `try`, no `throw`, no template string in any function that runs per-frame or per-element |
| E | The task's verification program prints `PASS n/n` and exits 0, run **compiled**, headless |
| F | **Every parameter of a HOT function is `p_`-prefixed.** ⚠ **Rationale corrected — H-1 is fixed and merged** (hemlock PR #627, `e2946c1c`, in `main` at `cb7fbfaa`; re-verified on the merged build). A caller local sharing a parameter name no longer breaks the build — the compiler just declines to inline, costing **0.9 ns/call** (~0.3 % of frame budget). The convention survives on rule **A1** instead: parameters are never unboxed, so a hot function copies them into typed locals, and that idiom needs two distinct names. Measured **1.19×, 8.4 ns/call**. Apply to hot functions; a cold `fn f(x, y, z)` is fine and clearer. Do not cite H-1 as a live bug. See `CLAUDE.md` §4. |

---

## ⛔ WAVE-CONSTRUCTION RULE — learned the hard way in Wave 2. Read before scheduling any wave.

**A consumer and its producers must never be in the same parallel wave.**

Wave 2 put `W2-11 shot.hml` — the visual verification harness — in the *same* parallel wave as
`W2-3` palette, `W2-4` tod, `W2-5` texgen, `W2-6` skygen, `W2-7` fx/hud and `W2-8` meshgen, which
are exactly the seven modules it must render. When the harness agent started, none of them existed.
It did the only thing it could: wrote ~650 lines of **stand-in art** and rendered that instead.

The result was worse than a build failure, because everything looked fine:

- every committed screenshot depicted throwaway art, not the game
- `docs/shots/tex_world.png` was labelled "ATLAS_WORLD" and showed soft cloudy mush, while the real
  `texgen.hml` was producing 41 excellent tiles — so the evidence on disk **libelled a module that
  had actually succeeded**
- a real "weather bands are identical" bug was filed against `tod.hml` that was purely a property of
  the stand-in
- the failure was invisible to the probes: every probe passed, because each tested its own module

**The tell:** an agent reporting that a dependency "did not exist at any point while I was building".
That sentence is a scheduling defect, not an agent defect. The author disclosed it honestly and the
gate caught it — but only because the gate was told to *look at the images* rather than check that
files existed.

### Rules that follow

1. **A task that renders, integrates, or verifies another task's output belongs in the NEXT wave.**
   Harnesses, contact sheets, integration smoke tests, golden-image tests: all downstream.
2. **A "signatures only" dependency is legitimate; a "content" dependency is not.** Coding against a
   signature from `ARCHITECTURE.md` §5 works because the signature is written down in advance.
   Coding against *pixels that do not exist yet* cannot work — there is nothing to stand in for but
   invention.
3. **Never let an agent stub a dependency that is scheduled in its own wave.** If it must stub to
   proceed, the wave is mis-scheduled. Stop and re-schedule rather than accept the stub.
4. **Gates must inspect artefacts, not filenames.** "The PNG exists and the probe passed" would have
   green-lit this. "Read the PNG and say whether it is the real art" caught it.

---

## Wave 0 — Engine foundation (3 tasks)

Everything in every later wave imports at least one of these three. They are mutually independent.

### W0-1 — SDL + SDL_mixer FFI surface
- **Owns:** `wobbleweed/src/sdl.hml`, `wobbleweed/examples/probe_sdl.hml`
- **Deps:** none
- **Implements:** G9 (partly), G11, G12 (partly), G13 (partly), G18 (partly). **G5 is already merged upstream (wobbleweed PR #2, `905700c`) — do not re-apply it; do not regress it.** The `SDL_SetHint("SDL_RENDER_SCALE_QUALITY","0")` call in `window_open` and the *absence* of `SDL_SetTextureScaleMode` are load-bearing; a regression test asserts both.
- **Do:** the complete OS surface listed in `ARCHITECTURE.md` §5.1. Externs for window/renderer/target/texture/geometry/blend/pixels/events/keyboard/relative-mouse/buttons/wheel/perf-counter/hint/error, plus SDL2_mixer. Constants exported as named `let`s.
- **Acceptance:**
  - Every declared extern resolves at runtime (probe calls each one at least once).
  - **Each library's externs are grouped under its own `import`** — `libSDL2-2.0.so.0` block and `libSDL2_mixer-2.0.so.0` block. Verify both libraries' symbols resolve in the same binary.
  - Binds `Mix_PlayChannelTimed` / `Mix_LoadWAV_RW`, **never** `Mix_PlayChannel` / `Mix_LoadWAV` (macros, not symbols).
  - No symbol newer than SDL 2.0.18. Task report lists every bound symbol with its `\version` line from the header.
  - `SDL_RenderCopyEx`'s `angle` parameter is typed `f64` and the probe passes `0.0`.
  - `SDL_SetRelativeMouseMode` returning -1 headless is reported, not fatal.
  - `SDL_RenderSetVSync` returning -1 is reported, not fatal.
- **Verified by:** `probe_sdl.hml` — ≥ 45 assertions, run four ways: interpreted + compiled × dummy + real display. Must print `PASS 45/45` in all four. Includes pixel readbacks for BLEND/ADD/MOD/ColorMod and an `Mix_QuerySpec` check.

### W0-2 — Vector / matrix library
- **Owns:** `wobbleweed/src/vec.hml`, `wobbleweed/examples/probe_vec.hml`
- **Deps:** none
- **Implements:** G20
- **Do:** keep every existing export byte-compatible (legacy modules import them). Add `mat_look_dir(eye, yaw, pitch)`, `mat_rot_z`, `mat_invert_rigid`, `v_lerp`, `v_dist`, `v_dist2`, `v_reflect`, `ray_aabb`, `ray_plane`, `aabb_overlap`.
- **Acceptance:** `mat_look_dir` is stable and non-degenerate at pitch ±89.9°; `mat_invert_rigid(m) · m == identity` to 1e-12; `ray_aabb` agrees with a brute-force reference on 10 000 seeded random cases; every pre-existing export produces identical results to the current implementation on 1000 seeded inputs.
- **Verified by:** `probe_vec.hml`, unit assertions.

### W0-3 — Clock and instrumentation
- **Owns:** `wobbleweed/src/time.hml`, `wobbleweed/src/stats.hml`, `wobbleweed/examples/probe_time.hml`
- **Deps:** W0-1 (signatures only)
- **Implements:** G10, G22
- **Do:** `clock_now`/`clock_ms_between` on `SDL_GetPerformanceCounter` (u64 FFI returns are exact — no 2^53 workaround). Fixed-step accumulator with a 250 ms clamp. `stats.hml`: fixed-index counter/timer arrays, no string keys, no objects; `stat_report_string` built at ≤ 4 Hz.
- **Acceptance:** injected stalls of 5/50/500 ms advance exactly `floor(total_ms / TICK_MS)` ticks; the 500 ms stall clamps to 250 and does not spiral; instrumentation overhead ≤ 0.05 ms/frame over 10 000 frames; `STAT_*` index constants cover every counter named in `ARCHITECTURE.md` §4.
- **Verified by:** `probe_time.hml` assertions + a 10 000-iteration overhead measurement.

> **GATE 0:** all three probes print `PASS n/n` compiled and headless; `probe_sdl.hml` also passes on
> the real display. `hemlockc -O1 examples/walk_gpu.hml` still builds and runs (legacy unbroken).

---

## Wave 1 — Engine core (11 tasks)

All eleven code against `ARCHITECTURE.md` §2.3 (the vertex buffer contract) and §5.1 (signatures).

### W1-1 — Triangle batch: pool, bucket sort, flush
- **Owns:** `wobbleweed/src/batch.hml`, `wobbleweed/examples/probe_batch.hml`
- **Deps:** W0-1, W0-3
- **Implements:** **G2, G3, G4** — the surviving P0 renderer bugs. **G1 is not one of them:** the "shared vertex buffer" defect was a misdiagnosis of the hemlock backend divergence, which is fixed upstream (`ed12be28`, see `HEMLOCK_ISSUES.md` H-3). `SDL_RenderGeometry` copies vertex data into the command queue at call time, so buffer reuse was always safe. The disjoint-arena layout is still adopted here — but as a *performance* choice (one contiguous fill, no rewind, and it is the natural shape for the frame arena), and it must be justified by a benchmark like anything else.
- **Do:** the 4-layer pool of `ARCHITECTURE.md` §2.3–2.4. `batch_reserve` returns a byte cursor or -1. Counting sort, NB = 2048, counters in a Hemlock `array<i32>`, bucket index **recomputed** in the scatter pass, `counts`/`order` preallocated once. Flush walks `order`, `memcpy`s 60 B per triangle into a disjoint region of `obuf`, and issues one `SDL_RenderGeometry` per same-texture run at `ptr_offset(obuf, run_start*20, 1)`.
- **Acceptance:**
  - Sort < 0.5 ms at 2500 tris for random **and** ramp **and** flat depth distributions, varying < 20 % between them.
  - Ordering correct to one bucket quantum (max adjacent violation ≤ `FOG_FAR/2048`).
  - 32 000 triangles sorts without stack overflow.
  - 10× cap overflow renders the first `cap` triangles cleanly and reports the exact drop count; `valgrind` reports zero invalid writes.
  - The disjoint-arena flush is **benchmarked, not assumed**: report throughput at 500 / 2000 / 3500 triangles against a rewind-in-place reference, and the framebuffer checksum must be **identical**. If it is not faster, say so and keep it anyway only for the arena shape.
- **Verified by:** `probe_batch.hml` (assertions + timings) and `examples/repro_batchbuf_bug.hml` re-run on both backends (it must now pass on both — that is the H-3 regression guard).

### W1-2 — The emit kernel
- **Owns:** `wobbleweed/src/emit.hml`, `wobbleweed/examples/probe_emit.hml`
- **Deps:** W0-2, W1-1/W1-3/W1-4 (signatures only)
- **Implements:** **G6**, G8 (backface cull), G15/G16 (consumes them)
- **Do:** transform + near test + perspective divide + viewport + pixel snap + guard test + backface cull + `shade`/fog + pack, entirely on native `f64` locals, straight into the cursor `batch_reserve` returned. 16 MVP elements hoisted into 16 named locals once per frame. Every parameter copied into a typed local. Copy-out returns. Straddling triangles go to the `clip.hml` slow path.
- **Acceptance:**
  - Emit + pack ≤ **3.0 ms at 2500 triangles**, ≤ 12.5 ms at 8000.
  - `hemlockc -c --emit-c /tmp/e.c` shows `double` (not `HmlValue`) for the 16 matrix locals and the 12 named hot locals.
  - Framebuffer checksum **identical** to a reference object-path implementation on the same scene.
  - Zero allocations: RSS flat over 10 000 frames.
  - Backface cull removes ≥ 40 % of a closed mesh's triangles; reported in `stats`.
- **Verified by:** `probe_emit.hml` (checksum + timing + RSS) and `tools/ci_unbox.sh`.

### W1-3 — Lighting + fog parameter block
- **Owns:** `wobbleweed/src/shade.hml`, `wobbleweed/examples/probe_shade.hml`
- **Deps:** W0-2
- **Implements:** **G15, G16**
- **Do:** `RenderEnv` as a flat `array<f64>` with exported index constants (`ENV_SUN_X`, `ENV_AMB_R`, `ENV_FOG_NEAR`, `ENV_LIGHT0_X` …) so the emit loop reads an array, never an object. The full lighting model and the fog/mist curve of `ENGINE_GAPS.md` G15/G16. Up to 4 point lights. **No colour constants** — every colour is an input (R1).
- **Acceptance:** `ambient + sun` summing to (1,1,1) with `N·L = 1` reproduces the authored texel exactly on readback; 4 point lights at 2500 tris cost ≤ 0.4 ms; radial (not view-z) fog distance verified by equal fog at screen centre and screen corner for equidistant vertices; far plane derived as `fog_far * 1.06`.
- **Verified by:** `probe_shade.hml` pixel readbacks + timing.

### W1-4 — Clipping and frustum culling
- **Owns:** `wobbleweed/src/clip.hml`, `wobbleweed/src/frustum.hml`, `wobbleweed/examples/probe_clip.hml`
- **Deps:** W0-2
- **Implements:** **G7, G8**
- **Do:** rewrite `clip.hml` so the fast path is a pure predicate returning `CLIP_IN`/`CLIP_OUT`/`CLIP_STRADDLE` and allocates nothing; the slow path writes into caller-owned buffers and keeps no closures. New `frustum.hml`: Gribb–Hartmann extraction into a flat `array<f64>` of 24, plus `frustum_sphere` / `frustum_aabb`.
- **Acceptance:** accept-path cost < 40 ns/triangle; zero allocations on the accept path (RSS flat over 10 000 frames); slow path produces geometry identical to the current `clip_tri_near` on 10 000 seeded straddling triangles; `frustum_sphere` agrees with a brute-force 6-plane reference on 10 000 cases; a 5×5 ring at 70° FOV rejects ≥ 55 % of chunks.
- **Verified by:** `probe_clip.hml`.

### W1-5 — Render target and upscale present
- **Owns:** `wobbleweed/src/target.hml`, `wobbleweed/examples/probe_target.hml`
- **Deps:** W0-1
- **Implements:** **G12**
- **Do:** 320×240 `ARGB8888` `TEXTUREACCESS_TARGET`; begin/end; `SDL_RenderCopyEx` integer upscale with a shake offset and `angle` as `f64 0.0`.
- **Acceptance:** a diagonal edge in the output PNG shows hard 3×3 blocks at scale 3; `SDL_RenderGeometry` into the target produces the expected readback; the full chain (geometry → target → shake upscale → additive quad → alpha HUD quad) is byte-identical on the software and OpenGL renderers.
- **Verified by:** `probe_target.hml` + headless PNG diff against a committed golden.

### W1-6 — Input layer
- **Owns:** `wobbleweed/src/input.hml`, `wobbleweed/examples/probe_input.hml`
- **Deps:** W0-1
- **Implements:** **G9**
- **Do:** held/pressed/released edges for keys and mouse buttons, wheel, relative mouse deltas accumulated across all events in a frame, action map. `input_set_relative` returns a status; failure is reported and non-fatal.
- **Acceptance:** a key pressed and released inside one frame reports exactly one `pressed` and one `released`; three motion events in one frame sum into one delta; headless, relative mode fails and the program renders normally; on the real display the delta is live (drive it with `XTestFakeMotionEvent` — warping gives `xrel = 0` by design and proves nothing).
- **Verified by:** `probe_input.hml` with synthetic event injection, plus a manual real-display run.

### W1-7 — Audio
- **Owns:** `wobbleweed/src/audio.hml`, `wobbleweed/examples/probe_audio2.hml`
- **Deps:** W0-1
- **Implements:** **G18**
- **Do:** `Mix_OpenAudio(22050, AUDIO_S16LSB, 1, 512)`, 16 channels, a PCM registry that **owns every buffer for the process lifetime** (`Mix_QuickLoad_RAW` does not copy), play/pan/volume/halt, voice accounting. Graceful init failure.
- **Acceptance:** 8 simultaneous voices with distinct pans, no dropout; ≤ 0.2 ms/frame Hemlock time; a 10-minute soak shows flat RSS and clean `valgrind`; init failure under the dummy driver is reported and non-fatal; the registry is provably alive after the caller drops its reference (free the caller's handle, then play — must not crash).
- **Verified by:** `probe_audio2.hml`, run on the real device and headless.

### W1-8 — Texture container and atlas
- **Owns:** `wobbleweed/src/texture.hml`, `wobbleweed/src/atlas.hml`, `wobbleweed/examples/probe_atlas.hml`
- **Deps:** W0-1
- **Implements:** **G13**
- **Do:** convert `texture.hml` to RGBA8 (4 B/px). `atlas.hml`: buffer + cell grid, `atlas_cell_uv` with **half-texel inset**, `atlas_upload` in `RGBA32` (376840196), `atlas_update_rows` via dirty-rect `SDL_UpdateTexture`. **The engine ships no texture content** — the three generators in `texture.hml` move to the game (R1) or are deleted.
- **Acceptance:** a known RGBA pattern round-trips byte-for-byte through upload + `SDL_RenderReadPixels`; no SDL conversion texture is created (verify by format query); a 32×32 cell at the atlas edge never samples its neighbour across a 3-minute grazing-angle sweep; `atlas_update_rows` updates exactly the requested rows.
- **Verified by:** `probe_atlas.hml` + headless PNG.

### W1-9 — Screen quads and bitmap font
- **Owns:** `wobbleweed/src/quad.hml`, `wobbleweed/src/font.hml`, `wobbleweed/examples/probe_font.hml`
- **Deps:** W1-1, W1-8 (signatures)
- **Implements:** **G14**
- **Do:** `quad.hml`: screen-space quads with no projection (rect, uv-rect, full-screen, ring). `font.hml`: **generic** — the caller registers glyphs as packed bitfields plus a codepoint→cell map; the engine bakes them into an atlas and emits 2 tris/glyph with an optional (+1,+1) shadow pass. `font_text` takes a triangle budget and truncates. **No glyph data in the engine.**
- **Acceptance:** 250 HUD triangles in ≤ 0.3 ms, one draw call; glyphs pixel-exact at 320×240 with no filtering; a string exceeding its budget truncates, reports the count, and never overflows the batch; the ring primitive produces the 16-triangle vignette shape.
- **Verified by:** `probe_font.hml` + headless PNG diff against a golden.

### W1-10 — Meshes and billboards
- **Owns:** `wobbleweed/src/mesh.hml`, `wobbleweed/src/billboard.hml`, `wobbleweed/examples/probe_mesh.hml`
- **Deps:** W1-2, W1-3 (signatures)
- **Implements:** **G17, G19**
- **Do:** flat mesh arena, 24 B/vertex (pos f32×3, uv f32×2, rgb u8×3, pad), non-indexed; builder (`mesh_begin`/`mesh_vert`/`mesh_tri`/`mesh_end`); `mesh_bake_light` bakes lighting into vertex colour at build time; `mesh_emit` / `mesh_emit_yaw` transform-and-pack only. `billboard.hml`: camera-facing quad sized `world_size * proj_scale / w`, plus a stretched variant for tracers and rain.
- **Acceptance:** 20 tree instances (1920 tris) emit in ≤ 2.3 ms with zero allocations; a static prop performs zero normal transforms per frame; a billboard holds constant screen size under a dolly and constant world size under rotation; 300 billboards emit in ≤ 0.9 ms.
- **Verified by:** `probe_mesh.hml` timings + headless PNG.

### W1-11 — Engine lifecycle and legacy quarantine
- **Owns:** `wobbleweed/src/engine.hml`, and a one-line `// LEGACY` header on each of `geom.hml`, `framebuffer.hml`, `raster.hml`, `sky.hml`, `postfx.hml`, `scene.hml`, `scene_gpu.hml`; `wobbleweed/README.md`
- **Deps:** all of Wave 1 (signatures)
- **Implements:** **G21**, plus wobbleweed-api §12.25 (the README overstates guarantees)
- **Do:** `engine_init` → `engine_shutdown` with a documented teardown order (audio → target → textures → renderer → window → `SDL_Quit`), a texture registry with a destroy sweep. Mark the seven legacy modules. Correct the README's false "byte-identical between interpreter and compiled" claim.
- **Acceptance:** a 10 000-frame run shows flat `/proc/self/statm`; `valgrind` reports no still-reachable SDL textures at exit; the legacy modules still compile and `examples/walk_gpu.hml` still runs.
- **Verified by:** `examples/probe_lifecycle.hml` + `valgrind`.

> **GATE 1:** every Wave-1 probe passes compiled and headless. `hemlockc -O1` builds all of
> `wobbleweed/src` in one translation unit. `examples/walk_gpu.hml` still runs (legacy unbroken).

---

## Wave 2 — Engine integration + game foundations (13 tasks)

### W2-1 — Engine integration smoke: the full pipeline in one program
- **Owns:** `wobbleweed/examples/probe_pipeline.hml`
- **Deps:** all of Wave 1
- **Do:** one program that exercises the whole engine: build a 2-cell atlas, a font, two meshes; set up a `RenderEnv`; render a fogged, lit, sorted, 4-layer frame into the target; upscale; read back; write PNG. This is the engine's own golden test and the proof Wave 1 links.
- **Acceptance:** compiles and runs headless and on the real display; PNG matches a committed golden byte-for-byte; the printed stats table has every field of `ARCHITECTURE.md` §4; total frame ≤ 8.0 ms at 2500 synthetic triangles.
- **Verified by:** headless PNG diff + stats table.

### W2-2 — Config and math primitives
- **Owns:** `nightshade/src/core/config.hml`, `nightshade/src/core/mathx.hml`, `nightshade/tools/probe_mathx.hml`
- **Deps:** none
- **Do:** every tunable from `ARCHITECTURE.md` §8 and the GDD as a `g_`-prefixed constant. `mathx.hml`: hand-inlined `clampf/lerpf/minf/maxf/absf/smoothstep`, `xhash2`/`xhash3` (**all mixing in `i64` with an explicit `& 0xFFFFFFFF` mask** — `i32 *` throws), `h01`, `vnoise`, `fbm2`, `bayer4`.
- **Acceptance:** `xhash2` produces identical values interpreted and compiled over 1 M inputs and never throws; `vnoise` tiles seamlessly when `period` divides the tile size (verify by comparing edge columns); inlined `clampf` measured faster than `@stdlib` `clamp` (19.6 → 14.0 ns).
- **Verified by:** `probe_mathx.hml` unit assertions.

### W2-3 — Palette
- **Owns:** `nightshade/src/art/palette.hml`
- **Deps:** none
- **Do:** every colour from ART_BIBLE §3 as a `g_`-prefixed packed `i32`, plus `pal_r/g/b/pack/lerp`.
- **Acceptance:** ~110 constants, all present; **no constant has two equal channels or all-round-number channels** (the untinted-colour tell) except the three explicitly exempt UI colours; every world-atlas albedo has luminance ≥ 72; a CI grep finds zero hex colours anywhere else in `nightshade/src/`.
- **Verified by:** `tools/palette_preview.hml` (W2-11) + a grep assertion in `ci_imports.sh`.

### W2-4 — Time of day
- **Owns:** `nightshade/src/art/tod.hml`, `nightshade/tools/probe_tod.hml`
- **Deps:** W2-3, W1-3 (signatures)
- **Do:** the ART_BIBLE §5 keyframe table remapped onto the 16-minute day (D6: Dawn 2 / Day 7 / Dusk 2 / Night 5), linear interpolation between keyframes, the four weather overrides, the corrupted-zone override, the 2-frame lightning sequence. Writes the engine `RenderEnv`.
- **Acceptance:** `ambient + sun` sums to ≤ (1,1,1) per channel at every keyframe **and at every interpolated point**; ambient never drops below 0.14 in any channel; `fog_far` never exceeds 72 m in any state; ambient is always the complement of the sun (never grey); a full 16-minute sweep produces no discontinuity > 4 % per frame in any channel.
- **Verified by:** `probe_tod.hml` sweeps all 57 600 ticks of a day and asserts every invariant.

### W2-5 — World texture atlas generator
- **Owns:** `nightshade/src/art/texgen.hml`
- **Deps:** W2-2, W2-3, W1-8 (signatures)
- **Do:** ART_BIBLE §7.2 primitives and §7.3 generators (grass, dirt, stone with the `a−b` ridge trick, wood, metal with the mandatory broad specular sweep, concrete, leaf, snow) packed into the §7.4 8×8 layout.
- **Acceptance:** every tile has ≤ 12 distinct colours from ≤ 2 palette families plus black; every tile's luminance range is 60–130; **no tile is a solid colour**; every ramp boundary is Bayer-dithered; a horizontal FFT-free check confirms no dominant frequency finer than 3 texels (the shimmer test); build time ≤ 200 ms compiled.
- **Verified by:** `tools/texview.hml` PNG + an automated per-tile histogram assertion inside the generator's self-test mode.

### W2-6 — Sky generator
- **Owns:** `nightshade/src/art/skygen.hml`
- **Deps:** W2-2, W2-3, W2-4, W1-8 (signatures)
- **Do:** ART_BIBLE §11: 512×160 panorama, gamma-1.35 gradient with per-row Bayer dither, two cloud layers with the **lit-top / shadowed-bottom split**, sun disc with a hard edge + halo, moon with phase, three star tiers with the 1-px cross, a Milky Way band, a fixed constellation seed. Incremental re-bake, 20 rows/frame, dirty-rect upload.
- **Acceptance:** no visible banding (max adjacent-row luminance step ≤ 2 after dither); clouds never touch the horizon line; the horizon band matches `fog_tint` applied to mid-grey (no skyline seam); the sun position tracks `SUN_DIR`; a full re-bake completes in 8 frames with ≤ 0.6 ms/frame; constellations are identical across runs.
- **Verified by:** `tools/texview.hml` PNG + assertions.

### W2-7 — FX and HUD atlas generators
- **Owns:** `nightshade/src/art/fxgen.hml`, `nightshade/src/art/hudgen.hml`
- **Deps:** W2-2, W2-3, W1-8/W1-9 (signatures)
- **Do:** `ATLAS_FX` cells (muzzle ×3, tracer, sparks ×2, explosion ×6, ember, smoke ×3, glow cards ×2, enemy eye, loot beam, rain streak, lightning ×2, dust, splash, XP mote). `ATLAS_HUD`: `FONT_MICRO` 4×6 and `FONT_BIG` 8×12 as packed bitfields (**`FONT_BIG` drawn separately, not scaled**), icons, crosshair parts, minimap chrome, vignette gradient strip.
- **Acceptance:** every glyph renders pixel-exact at 320×240; `FONT_BIG` digits have a 2-px stroke weight; the additive FX cells have a black (0,0,0) background so `ADD` composites correctly; every FX cell fits its 16×16 slot with a 1-px margin.
- **Verified by:** `tools/texview.hml` PNG with cell labels + a glyph-coverage assertion (all of A–Z, 0–9 and the named punctuation present).

### W2-8 — Procedural mesh library
- **Owns:** `nightshade/src/art/meshgen.hml`
- **Deps:** W2-3, W1-10 (signatures)
- **Do:** the DSL (`mg_box`, `mg_prism`, `mg_taper`, `mg_fan_disc`, `mg_lathe`) and every mesh: the ART_BIBLE §8.4 tree (kinked 6-sided tapered trunk, 3 rotated offset canopy discs with a top/bottom value break, one asymmetric branch stub) at LOD0/1/2, bush, rock, crate, barrel, lantern post, the six enemies as rigid part hierarchies, NPC, and six viewmodel weapons. Bake vertex colour and creased AO at build time.
- **Acceptance:** triangle counts match the ART_BIBLE §8.3 budgets within ±10 %; **every mesh is asymmetric** (a bilaterally symmetric silhouette has no orientation cue at 12 px); the six enemy classes have distinct head:shoulder ratios and distinct signature protrusions ≥ 0.45 m; the six weapons have distinct 32×32 silhouettes; no baked vertex colour has luminance below 72.
- **Verified by:** a `meshgen --contact-sheet` mode that renders every mesh at 12 px, 6 px and 32×32 into one PNG for the visual critic.

### W2-9 — Sim: RNG and the input command
- **Owns:** `nightshade/src/sim/rng.hml`, `nightshade/src/sim/command.hml`, `nightshade/tools/probe_sim_core.hml`
- **Deps:** W2-2
- **Do:** xorshift128 with separate streams seeded from `(world_seed, stream_id, tick, entity_id)`. `InputCommand`: 9 integers, **no bools, no floats, no nulls**, quantized **at construction** (`yaw_q` is a u16 *in the struct*; the sim dequantizes and uses the dequantized value).
- **Acceptance:** the same `(seed, stream, tick, id)` yields the same value across 1 M draws, interpreted and compiled; streams are statistically independent (chi-square over 100 k draws); no `@stdlib/random` import anywhere under `src/sim/`; a round-trip `q_ang`→`dq_ang`→`q_ang` is idempotent; `sim_apply_command` given the same `(world, slot, cmd)` twice produces identical world state.
- **Verified by:** `probe_sim_core.hml`.

### W2-10 — Sim: world and history
- **Owns:** `nightshade/src/sim/world.hml`, `nightshade/src/sim/history.hml`
- **Deps:** W2-2, W2-9 (signatures)
- **Do:** the SoA `World` grouped by replication class (identity / transform / state / owner-only / server-only), sparse-set id↔slot, `world_spawn`/`world_despawn` (swap-with-last, fix `sparse`), kind-partitioned id ranges, negative ids reserved for client cosmetics. `history.hml`: 32-tick ring, flat `px[(slot*32)+ring]`, captured every tick.
- **Acceptance:** 512 spawn/despawn cycles leave `sparse`/`dense` consistent; ids are never reused within a session; **every field carries a one-word comment naming its replication group**; `history_capture` at 256 entities costs ≤ 0.08 ms/tick; no field is an object, an entity reference, or a closure.
- **Verified by:** `probe_sim_core.hml` extension + a CI grep for `.target =` object assignment.

### W2-11 — The visual verification harness ★
- **Owns:** `nightshade/tools/shot.hml`, `nightshade/tools/palette_preview.hml`, `nightshade/tools/texview.hml`, `nightshade/docs/shots/` (directory + README)
- **Deps:** W2-1, W2-3
- **Do:** `shot.hml` per `ARCHITECTURE.md` §7 — headless, deterministic, renders through the **real** `frame_render` (in Wave 2 that is `probe_pipeline`'s composition; it is rewired to the game's in W3-7 and the file is re-owned then), CLI: `--scene --cam --look --tod --weather --seed --out`. Prints the `stats` frame report next to the PNG. `palette_preview.hml` dumps a swatch sheet and every ToD keyframe on a test sphere — **build this before texgen finishes** so palette errors are caught before fifty tiles are baked. `texview.hml` dumps all four textures with grid and labels.
- **Acceptance:** the same command produces byte-identical PNGs across runs; runs compiled only and refuses to run interpreted with a clear error; never crashes when `SDL_SetRelativeMouseMode` fails; `--scene list` enumerates every registered scene; a screenshot without its stats report is impossible (both are written or neither).
- **Verified by:** two runs of the same command diffed; a `--scene list` smoke test.

### W2-12 — Networking shapes (v1 loopback)
- **Owns:** `nightshade/src/net/transport.hml`, `nightshade/src/net/protocol.hml`, `nightshade/src/net/quantize.hml`, `nightshade/src/net/packing.hml`
- **Deps:** W2-9, W2-10 (signatures)
- **Do:** `LoopbackTransport` with `NS_FAKE_LATENCY_MS`, `NS_FAKE_JITTER_MS` and `NS_LOOPBACK_SERIALIZE` modes; reserved `net_id`s; packed fixed-stride blobs (20 B/entity, **12 entities per 240 B blob** — the buffer element cap is 255 B); `q_pos/dq_pos/q_ang/dq_ang/q_vel`.
- **Acceptance:** `NS_LOOPBACK_SERIALIZE=1` round-trips every command and snapshot through the real codec with zero throws and zero field loss; **no bool and no null ever enters a packet** (CI grep + a runtime assertion in the packer); a 32-entity snapshot builds+parses in ≤ 0.05 ms compiled; `gn.hml` is imported from nowhere but `src/net/`.
- **Verified by:** `tools/packetdump.hml` (W4-13) in Wave 4; in Wave 2, unit assertions inside `transport.hml`'s self-test mode.

### W2-13 — Headless sim runner and determinism gate
- **Owns:** `nightshade/tools/simtest.hml`, `nightshade/tools/replay.hml`, `nightshade/tools/ci_imports.sh`, `nightshade/tools/ci_unbox.sh`
- **Deps:** W2-9, W2-10 (signatures)
- **Do:** `simtest.hml` runs 10 000 ticks of scripted input **with no SDL linked**. `replay.hml` records a command stream + per-tick position hash and replays it. `ci_imports.sh` enforces the import wall, the `g_` prefix rule, the legacy-import ban, the "no hex colour outside palette.hml" rule and the "no `@stdlib/random` in `src/sim`" rule. `ci_unbox.sh` greps the emitted C for `double`/`int32_t` on the 12 named hot locals.
- **Acceptance:** `hemlock tools/simtest.hml` runs 10 000 ticks with zero SDL symbols in the binary (verified with `nm`); `replay.hml` reproduces the hash bit-for-bit; both CI scripts fail loudly on a deliberately introduced violation of each rule they check.
- **Verified by:** the scripts themselves, plus a negative test per rule.

> **GATE 2:** `probe_pipeline` golden PNG passes; `shot.hml --scene atlas_sheet` produces the four
> atlases; `palette_preview` sheet reviewed by the visual critic; `simtest` runs SDL-free;
> both CI scripts pass and fail correctly.

---

## W3-0 — Extract the frame graph, then build the walkaround  ★ DO THIS FIRST IN WAVE 3

**Why this is task zero.** The project owner wants to *play* the world and give human feedback
before gameplay is designed against untested assumptions. That request is worth more than its face
value, because delivering it forces an architectural fix we owe anyway.

`tools/shot.hml` currently defines its own `frame_render` (line 2195). `ARCHITECTURE.md` §5 assigns
that function to `src/render/world_render.hml`, and `ci_imports.sh` **R7** now fails the build the
moment `world_render.hml` exists while `shot.hml` still has a private copy. A naive walkaround would
add a *third* frame graph and make the drift worse.

So:

1. **Extract** `frame_render` / `frame_init` / `frame_batches` out of `tools/shot.hml` into
   `src/render/world_render.hml`, unchanged in behaviour. This is W3-7's deliverable, done first
   because two consumers now need it.
2. **Rewire `shot.hml`** to import it. R7 must go green, and **every one of the 9 scenes must still
   render byte-identically** to its committed PNG — that is the proof the extraction was behaviour-
   preserving. A single changed pixel means it was not.
3. **Build `tools/walk.hml`** — interactive, importing the *same* `world_render.hml`:
   - mouse-look (`SDL_SetRelativeMouseMode`, verified working in W0-1) + WASD, shift to sprint
   - **a fly toggle** (F): noclip free-cam for inspecting the world, vs walking at player height
   - live time-of-day scrub (`[` / `]`) and a weather toggle — the day cycle is the game's metronome
     and it should be feel-able, not screenshot-able
   - scene/POI teleports on the number keys, reusing `shot.hml`'s scene registry
   - an on-screen frame budget readout: triangles submitted/drawn, draw calls, ms, using `stats.hml`
   - runs on the real display at ×3 upscale, 60 fps target
4. **Ship it as a build the owner can run**, with the controls printed on start.

**Acceptance:**
- R7 PASS with `world_render.hml` present.
- All 9 `shot.hml` scenes byte-identical to their committed PNGs after the extraction.
- `walk.hml` holds 60 fps on the real display at the 2500-triangle budget; the readout proves it.
- `hemlockc -O1` builds both; neither defines a second frame graph
  (`grep -c "fn frame_render" tools/*.hml` must be 0).

**This is the first time anyone will move through this world.** Expect it to surface things no
screenshot can: movement speed, fog density at walking pace, terrain readability while turning,
whether the horizon has anything worth walking toward.

---

## ⚠ WAVE 3 IS RESEQUENCED — run it as three sub-waves, not one

Applying the wave-construction rule above. As originally written, Wave 3 contains a **five-deep
dependency chain inside a single "parallel" wave**:

    W3-1 worldgen -> W3-2 chunk storage -> W3-3 meshing -> W3-4 terrain render -> W3-7 frame graph

and `W3-7` is an *integrator* that composes five renderers (`W3-4`, `W3-8`, `W3-9`, `W3-10`,
`W3-11`) built at the same moment. That is exactly the shape that produced the stand-in harness in
Wave 2. Signature-level dependencies are fine; **integration and content dependencies are not.**

Run instead as:

| Sub-wave | Tasks | Why it can be parallel |
|---|---|---|
| **3a** | W3-1 worldgen, W3-2 chunk storage, W3-5 camera, W3-6 snapshot, W3-12 day cycle, W3-13 asset boot, W3-14 audio bank | all pure producers; depend only on Wave 2, which is complete |
| **3b** | W3-3 meshing, W3-8 HUD, W3-9 post-FX, W3-10 client FX, W3-11 entity rendering | consume 3a's real output; disjoint from each other |
| **3c** | W3-4 terrain rendering, W3-7 frame graph | the integrators — they need 3b's real output, not a promise of it |

`GATE 3` (the art-direction milestone) runs after **3c**, because it judges a composed frame.

**Same check applies to later waves before launching them:**
- **Wave 4**: `W4-9` (sim step/snapshots) and `W4-11` (the game loop) are integrators of W4-1..W4-8;
  `W4-13` benches the result. Split as 4a producers -> 4b `W4-9`/`W4-10` -> 4c `W4-11`/`W4-12`/`W4-13`.
- **Wave 6**: `W6-3` (the money shots) and `W6-4` (budget enforcement) judge everything else, and
  `W6-5` gates on the whole system. They are last by construction — keep them there.

## Wave 3 — World and render (14 tasks)

**Wave 3 exit is the ART_BIBLE first milestone** — see GATE 3. It is the most important gate in the
project: if the picture does not beat `wobbleweed/docs/*.png` by an enormous margin, no gameplay code
gets written.

### W3-1 — World generation (pure)
- **Owns:** `nightshade/src/sim/worldgen.hml`
- **Deps:** W2-2, W2-9
- **Do:** pure `f(seed, cx, cz)`: 3-octave value-noise height on a 4 m grid, temperature/moisture fields selecting biome, per-chunk POI hash roll, shade tier `clamp(floor(d/200) + noise_tier + phase_bonus, 0, 5)`. No I/O, no globals, no wall clock.
- **Acceptance:** the same `(seed, cx, cz)` gives identical output 1 M times, interpreted and compiled; chunk edges are C0-continuous with neighbours (no seams); generation ≤ **2.0 ms per chunk** compiled; height variation is ≥ ±1.5 m over any 32 m chunk (a flat horizon is an anti-goal).
- **Verified by:** unit assertions + a `--heightmap` PNG dump of a 9×9 chunk region.

### W3-2 — Chunk storage
- **Owns:** `nightshade/src/sim/chunk.hml`
- **Deps:** W3-1
- **Do:** `buffer(u16)` heights in cm, `buffer(u8)` biome + baked light, a **sparse edit overlay** (never bake player edits into the generated array — that makes the diff untransmittable), dirty flags, LRU cache with a hard chunk cap.
- **Acceptance:** ≤ 1.5 bytes per height sample (vs 16 for an `array<i32>`); `chunk_height_at` and `chunk_normal_at` are bilinear-correct against a reference; the edit overlay round-trips through save/load; the LRU never exceeds its cap and never evicts a chunk inside the render ring.
- **Verified by:** unit assertions + a memory report at a 15×15 loaded region.

### W3-3 — Chunk meshing
- **Owns:** `nightshade/src/render/chunkmesh.hml`
- **Deps:** W3-2, W1-10
- **Do:** chunk → cached flat vertex arena at LOD0 (128 tris) / LOD1 (32) / LOD2 (8) with skirts; bake per-vertex `N·L`, creased AO (×0.55 over 0.8 m), biome tint, and low-frequency value patchiness `fbm(worldx, worldz, 24 m) → ×0.86–1.0`. Rebuild only when dirty, amortized over frames.
- **Acceptance:** ≤ 9.5 KB per LOD0 chunk; one chunk meshes in ≤ 0.7 ms; a 5×5 ring rebuild is spread so no frame spends > 1.0 ms meshing; LOD seams are hidden by skirts (no sky visible through a seam in a 3-minute sweep); **the ground is visibly lit per-vertex, not by one scalar** (the §1.3 fix).
- **Verified by:** headless PNG at three camera heights + timing.

### W3-4 — Terrain rendering
- **Owns:** `nightshade/src/render/terrain_render.hml`
- **Deps:** W3-3, W1-2, W1-4
- **Do:** ring walk, per-chunk `frustum_sphere`, LOD by distance (0–48 / 48–96 / beyond, clamped to `FOG_FAR`), emit cached buffers. **Chunks activate at `FOG_FAR` and never closer.**
- **Acceptance:** ≥ 55 % of ring chunks culled at 70° FOV; ground triangles ≈ `(π/4)·FOG_FAR²/16·2` ± 15 %; ≤ 520 ground triangles at `FOG_FAR = 72`; nothing ever pops in unfogged (verify by a 60-second traversal capture at 4 fps, no frame with `f < 0.95` on a newly-activated chunk).
- **Verified by:** `benchframe` counters + a traversal PNG sequence.

### W3-5 — Camera and view
- **Owns:** `nightshade/src/render/view.hml`
- **Deps:** W0-2, W2-10
- **Do:** basis from yaw/pitch via `mat_look_dir` (±85° clamp), FOV lerp (70 hip / 58 ADS / 78 sprint, 0.15 s), screen shake, `recoil_view` (which **never leaves the client** and never affects the bullet), the MVP with far plane `fog_far * 1.06`.
- **Acceptance:** pitch ±85° stable; the FOV lerp is frame-rate independent (identical at 30 and 240 fps); `recoil_view` provably does not appear in any value that reaches `sim_apply_command` (CI grep + assertion); shake is deterministic from tick + seed.
- **Verified by:** unit assertions + a two-frame-rate comparison.

### W3-6 — Render snapshot
- **Owns:** `nightshade/src/render/render_snapshot.hml`
- **Deps:** W2-10
- **Do:** the SoA struct of `ARCHITECTURE.md` §3.1, preallocated to 256, `rsnap_build(rs, world, alpha)` interpolating positions and angles between tick n−1 and n; `rsnap_build_from_net` as a v2 stub with the identical signature.
- **Acceptance:** zero allocations per frame (RSS flat over 10 000 frames); at `alpha = 0` and `alpha = 1` the output equals the raw tick states exactly; angle interpolation takes the short way around ±π; ≤ 0.1 ms at 256 entities.
- **Verified by:** unit assertions.

### W3-7 — The frame graph
- **Owns:** `nightshade/src/render/world_render.hml`, and **re-owns** `nightshade/tools/shot.hml` (rewiring it to the real `frame_render`)
- **Deps:** W3-4, W3-5, W3-6, W1-1, W1-5
- **Do:** own the four batches; execute stages 11–27 of `ARCHITECTURE.md` §4 in order; enforce the per-layer caps; report every stat.
- **Acceptance:**
  - Total frame ≤ **11.0 ms** at 2500 triangles on the software renderer.
  - **The D7 fog-alpha measurement:** report frame time at `fog_alpha_max = 0` vs shipping. If alpha costs > 1.0 ms, raise the 0.35 threshold and report the new value. **This task owns that answer.**
  - Draw calls ≤ 8.
  - Batch overflow at 3500 triangles drops and reports; never corrupts.
  - `shot.hml` renders through this file and nothing else.
- **Verified by:** `benchframe` stage table + `shot.hml` PNGs.

### W3-8 — HUD
- **Owns:** `nightshade/src/render/hud.hml`
- **Deps:** W1-9, W2-7, W3-6
- **Do:** the ART_BIBLE §9.2/§9.3 layout at exact pixel rects: crosshair with real spread bloom, hitmarker, health bar + numeral, ammo mag + reserve, weapon name, compass, minimap, killfeed (hard-capped), XP bar, XP popups, damage vignette, hit-direction arcs, reload bar, interact prompt, objective marker, low-ammo chevrons. 1-px `UI_BLACK` shadow on every glyph and line; a 55 %-alpha plate behind every text block.
- **Acceptance:** worst case ≤ **250 triangles**, hard-capped with the killfeed truncating first; every element is legible against all four worst backgrounds (noon sky, snow, muzzle flash, `CONCRETE_HI`) — verified by the `hud_worst_case` scene; build cost ≤ 0.25 ms; strings rebuilt at ≤ 4 Hz, not per frame.
- **Verified by:** `shot.hml --scene hud_worst_case` PNG, reviewed by the visual critic.

### W3-9 — Post-FX geometry
- **Owns:** `nightshade/src/render/postfx_geo.hml`
- **Deps:** W1-9, W2-7
- **Do:** the vignette ring (static + damage summed into the **same** 16 triangles, colour lerped toward `UI_DANGER`), the composite `MOD` overlay (PS1 4×4 dither + ±5 grain + the 3-px red/cyan edge bleed, **3 pre-baked variants cycled per frame** for free animated grain), sprint speed lines, lightning and level-up flashes, the corrupted-zone tint. Scanlines and interlace exist as options, **default off**.
- **Acceptance:** ≤ 50 triangles and ≤ 2 full-screen blended fills total; **the composite overlay's cost is measured** — if it exceeds 12 % of frame time on the software renderer it becomes a setting defaulting on only at ≥ 720 p window sizes; the vignette is always on; no attempt at bloom, DOF, motion blur or real chromatic aberration.
- **Verified by:** `benchframe` delta with the overlay on and off + PNG.

### W3-10 — Client FX
- **Owns:** `nightshade/src/render/fx.hml`
- **Deps:** W1-10, W2-7, W3-6
- **Do:** SoA particle pool (cap 512, **negative ids**, client-only, never replicated): muzzle flashes, tracers, impact bursts with material tint, ember motes that home to the player, damage numbers, kill-dissolve, decals, glow cards behind every emissive.
- **Acceptance:** 300 live particles cost ≤ 0.35 ms sim + ≤ 0.9 ms emit; zero allocations per frame; every particle id is negative; a muzzle flash also pushes a dynamic point light into the `RenderEnv` (the engine's best-looking capability); **every emissive larger than 6 px on screen gets a glow card** — this is the bloom substitute and it is mandatory.
- **Verified by:** `shot.hml --scene muzzle_fog` PNG + timing.

### W3-11 — Entity rendering
- **Owns:** `nightshade/src/render/entity_render.hml`
- **Deps:** W2-8, W3-6, W1-10
- **Do:** entities/props/pickups → mesh instances with distance LOD (0/1/2), hit-flash vertex tint, dissolve scale, emissive markers into `LAYER_FX`, **one contact-shadow quad per entity — mandatory, no exceptions**, violet rim light on hostiles.
- **Acceptance:** an enemy is identifiable by class at **12 px (30 m)** and detectable as a threat at **6 px (60 m)** — verified against the meshgen contact sheet; every entity and prop has a contact blob (assertion: shadow count == entity count); rim light appears on hostiles and nowhere else; 8 enemies at LOD1 cost ≤ 1.2 ms.
- **Verified by:** `shot.hml --scene readability_12px` and `--scene readability_6px`.

### W3-12 — Day cycle (sim side)
- **Owns:** `nightshade/src/sim/daycycle.hml`
- **Deps:** W2-2
- **Do:** pure tick → day fraction, phase (Dawn 2 / Day 7 / Dusk 2 / Night 5 = 16 min), shade-tier phase bonus, the dusk-horn edge event.
- **Acceptance:** phase boundaries land on exact tick counts; a full day is exactly 57 600 ticks; the dusk-horn edge fires exactly once per day; pure — no wall clock, no globals.
- **Verified by:** `simtest` running 3 full days and asserting the event log.

### W3-13 — Asset boot
- **Owns:** `nightshade/src/game/assets.hml`
- **Deps:** W2-5, W2-6, W2-7, W2-8, W1-8
- **Do:** the boot sequence of `ARCHITECTURE.md` §6: build all four atlases, all meshes, upload with the correct blend mode per texture, report per-stage timing behind a title card.
- **Acceptance:** total boot ≤ **400 ms** compiled with the per-stage breakdown printed; exactly **four** SDL textures exist afterwards (a fifth is an anti-goal); each has the right blend mode (`BLEND`/`ADD`/`BLEND`/`NONE`); a second call is idempotent.
- **Verified by:** boot timing report + a texture-count assertion.

### W3-14 — Audio bank
- **Owns:** `nightshade/src/game/audiobank.hml`
- **Deps:** W1-7, W2-2
- **Do:** synthesize ~60 SFX to S16 mono PCM buffers: six gunshots, impacts per material, four footsteps per surface × four surfaces, the **pitch-rising hit-click chain** (+2 semitones per consecutive hit to +8, reset after 0.6 s), the kill chime, the ember-pickup arpeggio, the lantern bell, the dusk horn (two long notes), dry-fire, reload stages, ambience beds.
- **Acceptance:** total PCM ≤ 6 MB; synthesis ≤ 150 ms; the pitch chain is audibly monotonic (verified by measuring the dominant frequency of each step); **the gun is the loudest thing in the mix, always**; every buffer is registered with `audio_register_pcm` and never freed.
- **Verified by:** an offline WAV dump of every sample + a spectral assertion on the pitch chain.

> **GATE 3 — THE ART DIRECTION GATE.** `shot.hml --scene milestone_golden`: one 32 m chunk of
> undulating terrain with the new grass, per-vertex lighting, the full fog model, height mist, the
> re-baked sky, three trees, one contact-shadowed crate, at `GOLDEN`. **If it does not beat
> `wobbleweed/docs/*.png` by an enormous margin in the visual critic's judgement, the wave does not
> close and no gameplay code is written.** Plus: frame ≤ 11.0 ms at 2500 tris; boot ≤ 400 ms; the D7
> fog-alpha answer is reported.

---

## Wave 4 — Gameplay (13 tasks)

### W4-1 — Movement
- **Owns:** `nightshade/src/sim/movement.hml`
- **Deps:** W2-9, W2-10, W3-2
- **Do:** GDD §2.3 exactly: walk 4.4 / sprint 7.0 (±40° cone) / crouch 2.3 / ADS 2.9, accel 60, friction 8.0, air control 0.35, g = 22, jump 6.6, capsule r = 0.40, step-up 0.35, slide (≥6.0 → burst 9.2 → 3.0 over 0.75 s, cd 0.90), **slide-jump keeping 85 % horizontal — this is the protected skill tech**, mantle 0.6–1.4 m over 0.35 s, fall damage above 6 m. Swept capsule vs heightfield. **`PredictedState` captures every variable, including coyote time, slide timer and the bhop window.**
- **Acceptance:** every GDD number reproduced within 1 % in a scripted test (apex 0.99 m, air time 0.60 s, a slide clears a 4 m gap a walk cannot, slide-jump chains downhill to ~11 m/s); `predicted_capture`/`predicted_restore` round-trips exactly; replaying 8 commands from a captured state reproduces the state bit-for-bit; every waist-high ledge in a test course is mantleable.
- **Verified by:** `simtest.hml --course movement` printing the measured table + `replay.hml`.

### W4-2 — Weapons data and firing
- **Owns:** `nightshade/src/sim/weapons.hml`
- **Deps:** W2-9
- **Do:** the GDD §2.4 tables as parallel arrays — damage near/far, HS multiplier, RPM, mag, reserve, reload/empty, pellets, falloff `r0/r1` (**Longshadow amended to 34/68 per D2**), ADS/sprint-to-fire/swap times, hipfire spread base→cap, bloom, ADS spread, and the deterministic recoil arrays with jitter only on `kick_h`. `recoil_aim` goes in the command; `recoil_view` does not.
- **Acceptance:** the GDD §2.4 TTK matrix reproduces exactly (Sparrow vs Husk 261 ms near; Bellows one-shots a Husk ≤ 6 m; Longshadow one-shots a Husk in the head at any range); recoil is deterministic given the same seed; **no weapon's max useful range exceeds `FOG_FAR`**.
- **Verified by:** a `weapons --ttk` self-test printing the matrix, diffed against the GDD table.

### W4-3 — Combat and hit registration
- **Owns:** `nightshade/src/sim/combat.hml`
- **Deps:** W4-2, W3-2, W2-10
- **Do:** hitscan only: DDA ray vs heightfield, ray vs entity AABB with a head volume, damage application with falloff, the Warden front plate (75 % DR while intact), hit/kill/damage events onto the event bus. Aim direction comes **from the command**, never from the camera matrix.
- **Acceptance:** a ray fired at a known target at 10/30/70 m hits within the expected spread cone 95 % of the time; damage matches `wpn_dmg_at`; **every one of the five hit-feedback signals is emitted as an event in the same tick** (hitmarker, flash, number, impact, audio) — a missing one is a failed test; no camera-matrix reference exists in the file (CI grep).
- **Verified by:** `simtest.hml --course combat` + event-log assertions.

### W4-4 — Projectiles
- **Owns:** `nightshade/src/sim/projectiles.hml`
- **Deps:** W4-3
- **Do:** the one projectile (Emberlance): 6.0 m/s arc, 3.5 m AoE, 60 impact + 12/s burn for 5 s.
- **Acceptance:** arc integration is frame-rate independent (identical at any tick count); burn ticks exactly 5 times per second in sim time; AoE hits every entity within 3.5 m and none beyond.
- **Verified by:** `simtest` assertions.

### W4-5 — AI
- **Owns:** `nightshade/src/sim/ai.hml`
- **Deps:** W2-10, W3-2
- **Do:** steering only, **no A\***: seek, 1.2 m separation, whisker raycasts at ±35° for Husks, per-class speeds/ranges/wind-up tells from the GDD §2.2 table. Server-only fields; nothing an AI does may influence a client-predicted value.
- **Acceptance:** 14 alive agents cost ≤ 0.5 ms/tick; agents never stack (min pairwise distance ≥ 0.9 m over 10 000 ticks); every class's wind-up tell is emitted as an event before the damage (0.45 s for Husk, 1.4 s for Spitter); no `ai_*` field is read by any predicted code path (CI grep).
- **Verified by:** `simtest.hml --course ai` + timing.

### W4-6 — The wave director
- **Owns:** `nightshade/src/sim/director.hml`
- **Deps:** W4-5, W3-12
- **Do:** `budget(tier, wave) = 60 + 45*tier + 18*wave`, alive cap 14, on-screen cap 8 (defer spawns that would exceed it), spawn ring 24–40 m biased behind the view cone, 1.2 s cadence, 8 s wave gap, the five tier composition tables.
- **Acceptance:** the full budget is always spent; the caps are never exceeded over 100 simulated holds; a tier-1 hold lasts 3:20 ± 10 s; the composition distribution matches the tier table within 5 % over 1000 rolls; deterministic given `RNG_DIRECTOR`.
- **Verified by:** `simtest.hml --course director` running 100 holds and printing the distribution.

### W4-7 — Progression
- **Owns:** `nightshade/src/sim/progression.hml`
- **Deps:** W2-9
- **Do:** `xp_to_next(L) = 500 + 250L + 25L²`, the level 2–30 unlock ladder, Wickmarks past 30, the XP source table, and the three Ember Streaks (Flare 4 / Drone 7 / Dawnfall 11, reset on death, no carry between lives).
- **Acceptance:** the cumulative XP table matches the GDD §3.1 column exactly; a scripted "hour 1" script lands the player at level **6–7**; Dawnfall fires at exactly 11 and never carries across a death.
- **Verified by:** `simtest.hml --course progression` printing the table.

### W4-8 — Loot
- **Owns:** `nightshade/src/sim/loot.hml`
- **Deps:** W2-9
- **Do:** the five rarity tiers with per-shade-tier drop weights, the ten-affix pool rolled without replacement in value bands, and the six hand-authored Relics.
- **Acceptance:** drop weights reproduce the GDD §3.3 table within 2 % over 100 k rolls; no affix ever appears twice on one item; Relics never drop below shade tier 3; deterministic given `RNG_LOOT`.
- **Verified by:** a `loot --distribution` self-test.

### W4-9 — The sim step and snapshots
- **Owns:** `nightshade/src/sim/sim.hml`, `nightshade/src/sim/snapshot.hml`
- **Deps:** W4-1 … W4-8
- **Do:** `sim_step` executing the **exact** ten-stage order of `ARCHITECTURE.md` §4. `sim_effects` is stage 10 and is skipped when `world.replaying == 1`. `snapshot_write(world, viewer_slot, baseline)` always takes a viewer.
- **Acceptance:** sim ≤ **2.0 ms/frame** at the v1 entity count with headroom reported; setting `world.replaying = 1` and re-applying 8 commands produces **zero** sounds, particles or shake; `replay.hml` reproduces a 10 000-tick position hash bit-for-bit; the stage order is asserted by a test that reorders two stages and expects a different hash.
- **Verified by:** `simtest`, `replay`, `benchframe`.

### W4-10 — The viewmodel
- **Owns:** `nightshade/src/render/viewmodel.hml`
- **Deps:** W2-8, W3-7, W4-2
- **Do:** idle sway ±2 px at 0.4 Hz, 1-px footstep bob, fire kick (back 0.06 m, up 4° over 2 frames, return over 5), 3-stage reload with a falling magazine billboard, sprint tilt 35° and drop 0.1 m over 6 frames, ADS lerp. `depth = 0.05`, fog `f = 0`, never culled, never crosses the crosshair, ≤ 38 % of screen height.
- **Acceptance:** ≤ 260 triangles; visual kick provably never moves the bullet (CI grep + assertion); the weapon reads as metal at 320×240 (the baked `STEEL_HI` 1-texel specular line along the receiver is present); animation is frame-rate independent.
- **Verified by:** `shot.hml --scene viewmodel_all` (all six weapons) reviewed by the visual critic.

### W4-11 — The game loop, client and server
- **Owns:** `nightshade/src/game/main.hml`, `nightshade/src/game/client.hml`, `nightshade/src/game/server.hml`
- **Deps:** everything in Waves 2–4
- **Do:** the loop of `ARCHITECTURE.md` §3 verbatim in shape. `client.hml`: input → command → transport, snapshot → RenderSnapshot, the event log that drives HUD and audio. `server.hml`: the authoritative host, in-process behind `LoopbackTransport`.
- **Acceptance:** movement distance over 10 s is identical at 30 and 240 fps; a 500 ms stall advances the clamped tick count and does not spiral; `NS_FAKE_LATENCY_MS=120` is playable with no rubber-banding; `NS_FAKE_LATENCY_MS=250` still fires the weapon on frame 0 with full cosmetic feedback; **the renderer never reads `world.*`** (CI grep).
- **Verified by:** manual play + `benchframe` + the latency env-var runs.

### W4-12 — Save/load
- **Owns:** `nightshade/src/game/save.hml`
- **Deps:** W2-10, W3-2, W4-7
- **Do:** versioned binary save on entering town, sleeping, lighting a lantern, and quitting. Persists the seed, player state, progression, the chunk **edit overlay only** (never generated chunk data), lit lanterns, town layout, almanac.
- **Acceptance:** a save/load round-trip reproduces an identical world hash; a save file for a 200-chunk-visited world is ≤ 256 KB (proof that generated data is not persisted); a version mismatch is rejected cleanly rather than crashing.
- **Verified by:** round-trip hash assertion.

### W4-13 — Protocol dump and frame bench
- **Owns:** `nightshade/tools/packetdump.hml`, `nightshade/tools/benchframe.hml`
- **Deps:** W2-12, W3-7
- **Do:** `packetdump.hml` hexdumps and decodes one `S_SNAPSHOT`, asserting every field's byte offset. `benchframe.hml` drives the live renderer and prints the §4 stage table with per-stage deltas.
- **Acceptance:** the packet dump asserts every documented offset and fails on a one-byte layout change; `benchframe` reproduces the PERF.md-style table for the shipping renderer and is wired into CI as a budget regression gate (frame time, triangle count, draw calls, allocations).
- **Verified by:** the tools themselves + a deliberate one-byte protocol change that must fail the dump.

> **GATE 4 — THE FIRST 60 SECONDS.** The GDD §8 sequence is playable end to end: wake at dusk, walk
> to the lantern, kill Wisps with the Kestrel, light the lantern (2.5 s channel, the silence, the
> expanding ring, `+350 XP`, `LEVEL 2`, the unlock card), the dusk horn, survive a tier-1 wave-1 hold,
> the 0.4 s of silence, the ember rain, and see the path of lit lanterns. Plus: sim ≤ 2.0 ms, frame
> ≤ 16.67 ms at the worst measured moment, `replay` hash stable.

---

## Wave 5 — Content and systems breadth (11 tasks)

### W5-1 — Biomes
- **Owns:** `nightshade/src/art/biome.hml`
- **Deps:** W2-5, W3-1
- **Do:** the six biomes: per-biome palette shifts, texture cell selection, prop density, `FOG_FAR` override, signature enemy/weapon/resource, and — critically — the **triangle budget policy** (Ashwood affords 140 billboards because it fogs at 45 m; Chalk Downs affords almost no props because it sees to the cap).
- **Acceptance:** every biome stays under 2500 triangles in its worst frame; each is identifiable from a single screenshot without UI; `FOG_FAR` never exceeds 72 m in any biome; biome transitions blend over ≥ 3 s with no visible seam.
- **Verified by:** `shot.hml --scene biome_<n>` × 6, reviewed by the visual critic, with stats.

### W5-2 — Hub geometry
- **Owns:** `nightshade/src/art/hubgen.hml`
- **Deps:** W2-8
- **Do:** Ember Hollow's modular buildings (`ROOF_TILE` roofs, plaster walls, teal/ochre trim), the well, the obelisk, the bench, the museum, fences, garden plots, strung lanterns, awnings in the two saturated fabric accents.
- **Acceptance:** the whole town is ≤ **600 triangles**; every window is a 2-tri additive quad with a glow card; the town reads as warm and human-scaled at 320×240.
- **Verified by:** `shot.hml --scene hub_dawn` (money shot 12.3), reviewed by the visual critic.

### W5-3 — Hub systems
- **Owns:** `nightshade/src/game/hub.hml`
- **Deps:** W5-2, W4-7, W4-12
- **Do:** the nine hub actions: spend, bank, upgrade the Great Lantern (5 tiers), build on the 1 m grid, plant/harvest, donate, talk, sleep, take contracts. **The town is always safe. Forever.**
- **Acceptance:** every action is reachable in ≤ 2 inputs from spawn; the Great Lantern's tiers visibly grow the town's light radius; sleeping skips to dawn and forfeits the night's ember; **no enemy can ever spawn or path inside the town boundary** (assert over 10 000 simulated ticks).
- **Verified by:** `simtest.hml --course hub`.

### W5-4 — NPCs and dialogue
- **Owns:** `nightshade/src/game/npc.hml`, `nightshade/src/data/dialogue.hml`
- **Deps:** W5-3, W2-8
- **Do:** the five named NPCs (Mabel Thorn, Odo, Connie Vane, Pip, Grandfather Wick), one new line per in-game day each, head-turn as the player passes, interaction prompts, a 3-note "voice" motif per NPC.
- **Acceptance:** ≥ 30 lines per NPC (six in-game days of non-repetition); each NPC is identifiable by silhouette alone; NPC rim light is `SKY_HORIZON * 0.35` and never violet; every line is in `dialogue.hml` and nowhere else.
- **Verified by:** a line-count assertion + `shot.hml --scene hub_dawn`.

### W5-5 — Weather
- **Owns:** `nightshade/src/art/weather.hml`
- **Deps:** W2-4, W3-10
- **Do:** the state machine and the four variants: overcast, rain (200 screen-space 2-tri streaks, fixed cost, −3 dB ambience duck), storm (rain + lightning every 4–11 s), and the corrupted-zone bloom override that fades in over 3 s.
- **Acceptance:** rain is a **fixed** triangle cost regardless of density setting; the lightning sequence is exactly 2 frames at `AMBIENT (0.90,0.92,1.00)` + 1 frame at (0.55,0.57,0.66); thunder is delayed by distance; weather never pushes a frame over budget.
- **Verified by:** `shot.hml --scene storm_assault` (money shot 12.5) and `--scene ns_bloom` (12.4).

### W5-6 — Lanterns and Wick Lines
- **Owns:** `nightshade/src/sim/lantern.hml`
- **Deps:** W4-6, W4-12
- **Do:** lantern posts, the 2.5 s channel cancelled by damage, tiers 1–4 with radii 40/60/85/120 m forcing shade tier 0, respawn and ammo top-up, the 90 m Wick Line linking, and fast travel along lit lines.
- **Acceptance:** a lit lantern permanently forces tier 0 in its radius across a save/load; Wick Lines recompute correctly when a lantern is added anywhere in a 200-lantern graph in ≤ 1 ms; **the lantern-lit moment fires all of: the expanding ring, the bell, the live fog-tier drop, the map icon, and `+350 XP`** — the single biggest moment in the game.
- **Verified by:** `simtest.hml --course lantern` + `shot.hml --scene lantern_lit`.

### W5-7 — Points of interest
- **Owns:** `nightshade/src/sim/poi.hml`
- **Deps:** W3-1, W4-6
- **Do:** the seven POI types at their stated frequencies with their stated triangle budgets, placed from the per-chunk hash roll so they are stable.
- **Acceptance:** a Lantern Post is guaranteed within 120 m of anywhere; **a Grove appears once per 8 chunks and never spawns an enemy, ever, including at night** (Groves are the exhale; assert over 10 000 ticks); every POI stays inside its triangle budget; placement is identical across runs for the same seed.
- **Verified by:** a `poi --survey` self-test over a 40×40 chunk region.

### W5-8 — Building
- **Owns:** `nightshade/src/sim/build.hml`
- **Deps:** W5-3
- **Do:** 1 m grid placement of prefab structures in the town's 40×40 plot (and, from level 20, in the wild), validation, ghost preview, removal.
- **Acceptance:** placement is deterministic and persists across save/load; the ghost preview uses alpha and never leaves geometry behind on cancel; an invalid placement is rejected with a readable reason; **no digging** — this is placement only.
- **Verified by:** `simtest.hml --course build`.

### W5-9 — Almanac and contracts
- **Owns:** `nightshade/src/sim/almanac.hml`, `nightshade/src/sim/contracts.hml`
- **Deps:** W4-7
- **Do:** the 60 critters / 24 relics / 18 enemy entries with donation and museum wings that change the town skyline; two contracts per day from the board with 300–900 XP rewards.
- **Acceptance:** every entry is reachable in-game; each museum wing opening visibly changes the skyline; contracts are deterministic per day + seed and never generate an impossible objective.
- **Verified by:** an entry-reachability audit + `simtest.hml --course contracts`.

### W5-10 — World map
- **Owns:** `nightshade/src/render/map.hml`
- **Deps:** W5-6, W1-9
- **Do:** the map screen: lit lanterns as warm dots in a cold field, Wick Lines drawn between them, discovered chunks, the deepest-lantern record. **This is the retention object** — the player is drawing a constellation of their own competence across a dark map.
- **Acceptance:** ≤ 400 triangles at 200 lanterns (aggregate distant lanterns into single dots); opens in ≤ 1 frame; the growth from 1 to 20 lanterns is visually dramatic; readable at 320×240.
- **Verified by:** `shot.hml --scene map_20_lanterns` reviewed by the visual critic.

### W5-11 — Menus
- **Owns:** `nightshade/src/render/menu.hml`
- **Deps:** W1-9, W2-7
- **Do:** title card (used during asset boot), pause, the level-up card and unlock card (slide in from the right for 2.5 s), settings (scale 2/3/4, scanlines, interlace, volume — **no resolution option**).
- **Acceptance:** every menu is navigable by keyboard alone; the title card covers the whole 400 ms boot; the level-up sequence matches juice item 14 exactly (gold edge bloom 0.6 s, ascending 4-note motif, centred `LEVEL 12` for 1.4 s, unlock card).
- **Verified by:** `shot.hml --scene menu_*`.

> **GATE 5:** all five ART_BIBLE money shots reproduce from `shot.hml` and pass the visual critic.
> Every biome screenshot is under budget. A 30-minute play session hits no frame over 16.67 ms.

---

## Wave 6 — Juice, tuning and the readiness gates (6 tasks)

Cross-cutting by design. Each owns a distinct domain of files; they do not overlap.

### W6-1 — Juice items 1–12 (the tech-demo/game line)
- **Owns:** `nightshade/src/render/fx.hml`, `nightshade/src/render/viewmodel.hml`
- **Deps:** Wave 5
- **Do:** GDD §7 items 1–12 to spec: hitmarker (4-tick white cross, 12 px, 0.09 s, 1.0→1.35→1.0, red + 1.6× on kill), hit sound with the pitch chain, enemy hit flash (0.06 s), muzzle flash with random roll and a 1-frame 6 % screen brighten, weapon kick, tracer (1 in 3, 1 in 1 for Longshadow), impact spark + 6-particle material burst, damage numbers (max 8), **kill dissolve with 8 ember motes that home to the player's face**, ember pickup arpeggio, 3-stage reload with a falling magazine, dry-fire click.
- **Acceptance:** **every damaging hit produces all five feedback signals in the same frame** — hitmarker, enemy flash, damage number, impact billboard, audio blip. A missing one is a failed test, "regardless of how correct the math is." Total juice cost ≤ 1.0 ms and ≤ 200 triangles.
- **Verified by:** an automated frame-capture test that fires one shot and asserts all five signals present in one frame, plus `shot.hml --scene hit_moment`.

### W6-2 — Juice items 13–21
- **Owns:** `nightshade/src/render/hud.hml`, `nightshade/src/render/postfx_geo.hml`, `nightshade/src/game/audiobank.hml`
- **Deps:** W6-1
- **Do:** damage taken (4-segment arc, HP-scaled vignette, 0.25° punch away from the hit), level up, streak earned, **wave clear (music stops — 0.4 s of actual silence — then ember rain and the fog warms one step)**, lantern lit, footsteps, the dusk horn, weather, idle charm. Plus the audio mix rule: the gun is always loudest; music ducks −8 dB on fire and recovers over 1.2 s.
- **Acceptance:** every item matches its spec's timings within one frame; the wave-clear silence is exactly 0.4 s; the dusk horn is unmistakable; the mix rule is measurable (peak levels during fire).
- **Verified by:** an event-timing capture + an audio level assertion.

### W6-3 — The money shots
- **Owns:** `nightshade/tools/shot.hml` (scene registry), `nightshade/docs/shots/`
- **Deps:** Wave 5
- **Do:** register and tune all five ART_BIBLE §12 money shots as reproducible scenes, plus `hud_worst_case`, `budget_worst`, `readability_12px`, `readability_6px`.
- **Acceptance:** **all five reproduce, and if a build cannot produce all five it is not done.** Each is deterministic and committed to `docs/shots/` with its stats report.
- **Verified by:** the visual critic, against the ART_BIBLE §12 "why it works" paragraphs.

### W6-4 — Performance and budget enforcement
- **Owns:** `nightshade/tools/benchframe.hml`, `wobbleweed/src/stats.hml`, `nightshade/tools/ci_unbox.sh`
- **Deps:** Wave 5
- **Do:** the full ablation table on the shipping renderer; enforce every budget in `ARCHITECTURE.md` §8 as a CI regression gate; verify the 12 hottest locals are unboxed in the emitted C; a 10 000-frame RSS soak.
- **Acceptance:** every budget line has an automated check with a threshold; the ablation table is reproducible; RSS is flat over 10 000 frames; **the answer to "what is `FOG_FAR` at ship" is a measured number, not a guess**.
- **Verified by:** the CI gate itself, plus a deliberate 20 % regression that must fail it.

### W6-5 — Multiplayer readiness gate
- **Owns:** `nightshade/tools/simtest.hml`, `nightshade/tools/replay.hml`, `nightshade/tools/packetdump.hml`, `nightshade/tools/ci_imports.sh`
- **Deps:** Wave 5
- **Do:** implement all ten of NETWORKING §19's v1 exit criteria as automated checks.
- **Acceptance:** all ten pass — (1) 10 000 SDL-free ticks, (2) bit-exact replay hash, (3) `NS_LOOPBACK_SERIALIZE=1` clean, (4) 120 ms + 30 ms jitter playable, (5) 250 ms still fires on frame 0, (6) replay purity: zero sounds/particles/shake, (7) packet dump offsets match, (8) no forbidden import under `src/sim/`, (9) every entity reference is an i32 id, (10) sim ≤ 2.0 ms with headroom reported.
- **Verified by:** the ten checks, each independently failable.

### W6-6 — Balance pass
- **Owns:** `nightshade/src/sim/weapons.hml`, `nightshade/src/sim/progression.hml`, `nightshade/src/sim/loot.hml`, `nightshade/src/sim/director.hml`
- **Deps:** W6-1, W6-2
- **Do:** tune against the GDD's own targets: the TTK matrix, hour-1 at level 6–7, the three chases (survival → power → completion), hold duration 3:20, and the D2 `FOG_FAR` retune's knock-on effects on the long-range weapons.
- **Acceptance:** the TTK matrix is reproduced or a deliberate, documented deviation is recorded in the GDD; a scripted hour-1 lands level 6–7; a scripted hour-5 reaches shade tier 3 with 9 lanterns and 4 town buildings; **no weapon is strictly dominated and none is strictly dominant** across the six-biome sightline matrix.
- **Verified by:** `simtest.hml --course balance` printing all four tables.

> **GATE 6 — SHIP.** All five money shots pass. All ten multiplayer-readiness criteria pass. Every
> budget gate green. A 60-minute session with no frame over 16.67 ms and no RSS growth. The visual
> critic signs off.

---

## Task index

| Wave | Tasks | Theme | Gate |
|---|---:|---|---|
| 0 | 3 | Engine foundation: FFI, math, clock | probes pass 4 ways; legacy unbroken |
| 1 | 11 | Engine core: batch, emit, shade, clip, target, input, audio, atlas, font, mesh, lifecycle | all probes pass; whole engine builds |
| 2 | 13 | Engine integration + game foundations: art generators, sim core, net shapes, **the shot harness** | golden PNG; SDL-free simtest; CI live |
| 3 | 14 | World and render | **the art-direction gate** |
| 4 | 13 | Gameplay | **the first 60 seconds** |
| 5 | 11 | Content and breadth | five money shots + biomes under budget |
| 6 | 6 | Juice, tuning, readiness | ship |
| | **71** | | |
