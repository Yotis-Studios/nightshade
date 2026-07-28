# NIGHTSHADE — rules for every agent working in this repo

PS1/N64-aesthetic open-world FPS. Hemlock, on the Wobbleweed engine. **Ships compiled.**
**60 fps is the floor. 2500 triangles is the budget. 320×240 is the resolution.**

---

## 🛑 RULE 0 — VERIFY YOUR COMPILER BEFORE YOU TRUST A MEASUREMENT.

**Status: `PATH` is CURRENT as of 2026-07-27 20:37.** `/usr/local/bin/hemlockc` was refreshed by the
user and now carries both the inliner fix and the interpreter/compiler divergence fixes. Plain
`hemlockc` / `hemlock` are fine to use.

**Run this check once per session anyway.** It takes 15 seconds and it already caught one full wave
of bad data:
```sh
cat > /tmp/v.hml <<'EOF'
fn mix(s: i32): i32 { return s + 7; }
fn main() { let s: i32 = 100; let b: u64 = 10241477005482035122; print(mix(s)); print(b >> 1); }
main();
EOF
hemlockc /tmp/v.hml -o /tmp/v && /tmp/v      # MUST print 107 then 5120738502741017561
```
A stale compiler either fails to build line 1 (the inliner bug, H-1) or prints
`14344110539595793369` for the shift. If either happens, stop and say so.

> **Why this rule exists.** Through Wave 0, `/usr/local/bin` was dated **July 12** — two weeks behind
> `main` — and it silently produced *wrong answers rather than errors*. A Gate 0 auditor filed a
> "`u64 >>` is sign-propagating in the compiler" bug that was **entirely an artifact of that stale
> binary**, and every Wave 0 performance number had to be re-measured. Fresh source in the repo does
> not mean fresh binary on `PATH`.

**Corollary:** a toolchain bug is not real until you reproduce it on a compiler built from current
`main`. Check `docs/HEMLOCK_ISSUES.md` before filing — H-7 (`ptr == null`) is real; the `u64 >>`
entry is retracted.

If you ever need to bypass `PATH`, the repo build is at `/home/nbeerbower/Projects/hemlock/hemlockc`.

Read before you write code:
- `docs/ARCHITECTURE.md` — what exists, why, and the exact file list
- `docs/ENGINE_GAPS.md` — engine work items `G1`–`G22`
- `docs/BUILD_PLAN.md` — your task id, your owned files, your acceptance criteria
- `docs/HEMLOCK_ISSUES.md` — live toolchain bugs. **Check this before blaming your own code.**
- `docs/recon/` — the seven measured recon reports. Every number in this file came from one of them.

If this file disagrees with a recon document, **this file wins** — the recon documents conflict with
each other and `ARCHITECTURE.md` §0 settled them.

---

## 1. THE TEN THINGS THAT WILL KILL THIS PROJECT

Each is measured. Each has cost someone a day already.

| # | Never | Instead | Measured |
|---|---|---|---|
| 1 | `array.sort(cmp)` on per-frame data | bucket counting sort on quantized depth | 143 ms → 0.39 ms at 2000 tris; **and it segfaults** on a presorted 200 k array |
| 2 | Allocate an object per vertex / triangle / particle / tick | native `f64` locals, write straight to the buffer | 11.36 → 2.04 ms/frame; an 8-field literal is **260 ns** |
| 3 | A top-level variable without a `g_` prefix | `g_frame`, `g_world` — and never reuse those names as locals | 423 → 222 ms/50 M. Silent. No warning. |
| 4 | A hot function parameter without a `p_` prefix | `fn mix(p_s: i32)` | **1.19×, 8.4 ns/call** — it is what makes the copy-to-typed-local idiom (A1) expressible. See the corrected rationale below. |
| 5 | `return acc;` from a hot function | `let out: f64 = acc; return out;` | 430 → 241 ms/50 M. `return acc + 0.0;` does **not** dodge it — the folder eats it. |
| 6 | `defer` in anything called per frame | explicit cleanup | **+70 ns on every call** to the enclosing function, whether or not it fires |
| 7 | `throw` as control flow | sentinel return values | leaks **~192 B of heap locals per throw**, compiled only. 600 k throws = 112 MB. |
| 8 | A closure literal anywhere in a function with a hot loop | hoist it out, or delete it | de-optimizes the **entire enclosing block** — escape analysis is conservative |
| 9 | `x * 1.0` to make a float | `f64(x)` | folded to `x`, keeps `i32`, **throws** on `array<f64>.push` |
| 10 | `import * as ns` then `ns.f()` on a hot path | named import | 644 → 213 ms/20 M |

---

## 2. HOW TO BUILD, RUN, TEST, SCREENSHOT

```bash
# instant type/arity/borrow check — run this on every save
hemlockc --check src/game/main.hml

# dev build: within 3 % of -O3 at half the build time (1.70 s vs 3.26 s)
hemlockc -O1 src/game/main.hml -o /tmp/ns && /tmp/ns

# ship build
hemlockc -O3 src/game/main.hml -o build/nightshade

# verify unboxing actually happened on a hot local
hemlockc -c src/render/world_render.hml --emit-c /tmp/o.c
grep -E '^\s+double (mx|my|mz|vx|vy|vz|sx|sy|w|d|f|acc) ' /tmp/o.c
#   double acc = hml_to_f64(...)              -> UNBOXED, good
#   HmlValue acc = hml_convert_to_type(...)   -> BOXED, you lost 2x

# headless screenshot — the visual critic runs this every iteration
hemlockc -O1 tools/shot.hml -o /tmp/shot
SDL_VIDEODRIVER=dummy /tmp/shot --scene ridge_golden --out docs/shots/ridge_golden.png
SDL_VIDEODRIVER=dummy /tmp/shot --scene list

# headless sim — must build and run with NO SDL linked
hemlock tools/simtest.hml
nm /tmp/simtest | grep -c SDL_    # must be 0

# determinism, budget, and the walls
hemlockc -O1 tools/replay.hml -o /tmp/replay && /tmp/replay --verify
hemlockc -O1 tools/benchframe.hml -o /tmp/bf && SDL_VIDEODRIVER=dummy /tmp/bf
./tools/ci_imports.sh && ./tools/ci_unbox.sh
```

**`hemlockc` is the ground truth, always.** The interpreter accepts code the compiler rejects (a
function annotated `: object` that returns a `buffer` runs and dies mid-execution interpreted; the
compiler catches it at build time). The game ships compiled and compiled is 5–18× faster. Never do
visual or performance work in the interpreter just because it starts faster.

**Never build a screenshot without its stats report.** `shot.hml` writes both or neither. A picture
without triangle counts, cull rejections, draw calls and stage timings is not evidence.

---

## 3. FILE OWNERSHIP

- **Your task in `BUILD_PLAN.md` lists the files you own. Edit those and no others.**
  Ownership is exclusive *within a wave*. A later wave may re-own a file; the plan says so explicitly
  when it does (e.g. W3-7 re-owns `tools/shot.hml`).
- Need something from a file you do not own? **Code against the signature in `ARCHITECTURE.md` §5.**
  That is what it is for. It will link at the wave gate.
- Signature missing or wrong? **Add it to `ARCHITECTURE.md` §5 and say so in your task report.** Do
  not invent one silently and do not edit someone else's module to make yours compile.
- Found a bug in a file you do not own? Report it. Do not fix it.

### The import wall — enforced by `tools/ci_imports.sh`

| Directory | May import |
|---|---|
| `src/core/**` | `@stdlib/*` only |
| `src/sim/**` | `@stdlib/math`, other `src/sim/**`, `src/core/**`. **Nothing else.** No SDL, no wobbleweed, no gn.hml, no `@stdlib/random`. |
| `src/art/**` | wobbleweed, `src/core/**` |
| `src/render/**` | wobbleweed, `src/render/**`, `src/core/**`, read-only structs from `src/sim/**`. **Not `src/net/**`.** |
| `src/net/**` | `src/sim/**`, gn.hml, `@stdlib/*`. **gn.hml is imported from nowhere else, ever.** |
| `src/game/**` | everything |

Also banned everywhere under `nightshade/src/`: the seven frozen legacy wobbleweed modules
(`geom.hml`, `framebuffer.hml`, `raster.hml`, `sky.hml`, `postfx.hml`, `scene.hml`, `scene_gpu.hml`).

---

## 4. HEMLOCK PERFORMANCE RULES

"Hot" means executed more than ~1000 times per frame.

### The hot-function skeleton — write every one of them like this

```hemlock
fn project(p_x: f64, p_y: f64, p_z: f64, p_n: i32): f64 {
    let x: f64 = p_x;              // 1. copy params into typed locals (params are NEVER unboxed)
    let y: f64 = p_y;
    let n: i32 = p_n;
    let acc: f64 = 0.0;            // 2. i32 or f64 only — never u8/u16 (backends disagree)
    for (let i = 0; i < n; i++) {  // 3. no calls, no allocs, no closures inside
        acc = acc + x * y;
    }
    let out: f64 = acc;            // 4. copy-out — `return acc;` re-boxes it
    return out;
}
```

> ### ⚠ CORRECTED RATIONALE FOR `p_` — read this before applying rule 4 or A3
>
> The original rule said `p_` exists because *"`hemlockc`'s inliner emits invalid C when a caller
> local shares a parameter name (H-1)"*. **That is no longer true.** H-1 was fixed by the
> orchestrator, merged as hemlock PR #627 (`e2946c1c`, in `main` at `cb7fbfaa`), and re-verified on
> the merged build: the colliding program now compiles clean and prints the correct answer. The
> fix makes the compiler *decline to inline* on a collision rather than emit bad C.
>
> **So a name collision is no longer a build break. It is only a lost optimization — and a small
> one.** Measured on this box, 20 M calls, compiled:
> ```
> colliding param name : 422 ms      p_ prefixed : 404 ms      1.04x, 0.9 ns/call
> ```
> 0.9 ns/call is ~0.045 ms/frame at realistic call volumes — 0.3 % of the 16.67 ms budget. That
> alone would **not** justify a repo-wide convention.
>
> **The convention survives on A1, not on H-1.** Parameters are never unboxed, so a hot function
> must copy them into typed locals — and that idiom needs two distinct names, which is exactly what
> `p_` provides. That is worth real money. Measured, 5 M calls of a multi-use `f64` body:
> ```
> params used directly : 269 ms      copied to locals : 227 ms      1.19x, 8.4 ns/call
> ```
>
> **Consequences:** apply `p_` to **hot** functions (the A1 idiom), not to every parameter in the
> codebase. A cold function taking `(x, y, z)` is fine and clearer. Do not cite H-1 as a live bug.

### Always

| | |
|---|---|
| A1 | Copy every parameter you use more than once into a typed local — **this is the reason `p_` exists** (1.19×, 8.4 ns/call) |
| A2 | Return via a copy, never a bare identifier |
| A3 | `g_` on every top-level variable; `p_` on parameters of **hot** functions; neither on locals |
| A4 | Hoist the 16 matrix elements into 16 named `f64` locals once per frame |
| A5 | `array` / `array<f64>` for hot random-access float data — **faster than raw `ptr`** (240 vs 408 ms) |
| A6 | `buffer` / `ptr` of `u8`/`u16` for bulk data (heightmaps, light bakes) — 1.03 vs 16.03 B/element |
| A7 | Struct-of-arrays above ~1000 members (0.150 vs 0.265 ms/tick) |
| A8 | Allocate every buffer once at startup; reuse via `clear()` / overwrite |
| A9 | Hand-inline `clamp`/`min`/`max`/`abs` in the innermost loop (19.6 → 14.0 ns) |
| A10 | `x++` not `x = x + 1` for counters that cannot legitimately overflow (89 vs 209 ms — `+` emits the overflow check) |
| A11 | Cache `a.length` in a typed local before a loop |
| A12 | One `SDL_RenderGeometry` per texture run — never per triangle |
| A13 | All hash/PRNG mixing in `u64` or `i64` with an explicit `& 0xFFFFFFFF`. **`i32`/`i64` `* + -` throw on overflow.** A textbook LCG in `i64` throws. |

### Never

Everything in §1, plus:

| | |
|---|---|
| N1 | `try`/`catch` inside a per-element loop (+10.8 ns/entry) |
| N2 | `obj.method()` per element — 29.2 ns vs 9.6 ns for a free function |
| N3 | Template strings or `"a" + i` per frame (165 ns / 105 ns each) — build HUD strings at ≤ 4 Hz |
| N4 | `buffer_ptr(b)` inside a loop — hoist it (511 → 401 ms) |
| N5 | `u8` / `u16` annotated accumulators — the interpreter throws where the compiler wraps |
| N6 | `alloc()` / `buffer()` per frame |
| N7 | `a.push()` to rebuild a per-frame list from empty — `clear()` then push into retained capacity |
| N8 | `define` structs for hot data — measured **identical** to object literals (223 vs 213 ns). They are FFI layout descriptors, not value types. |
| N9 | `@inline` — a literal no-op. GCC refuses and you get a build warning. If you need it inlined, write it inline. |
| N10 | `spawn` anywhere in the frame path — it deep-copies objects |

### Things measured to NOT matter — don't bother

`for (v in a)` vs indexed loops · `a.reserve(n)` before pushing · `ptr_offset(p,i*4,1)` vs
`ptr_offset(p,i,4)` · `divi()` vs `/` vs reciprocal-multiply · `array<f64>` vs untyped `array` ·
draw-call batching (**2000 draw calls cost 0.3 ms more than 1** — do not architect around it).

### API corrections the official docs get wrong

- `ptr_offset(p, offset, element_size)` takes **three** arguments. The documented two-argument form
  does not exist. The first argument must be a **`ptr`**, never a `buffer` — convert with
  `buffer_ptr(b)` and hoist it out of the loop.
- `/` always yields `f64` — **except** `a / 1`, which the folder turns into `a` and keeps `i32`.
- `extern fn` binds to the **most recently declared `import`**, not to all libraries. Group each
  library's externs directly under its own `import` or you get "not found in <wrong library>".
- `alloc()` is never reclaimed for you. `buffer`/`array`/`object`/`string` are refcounted — do **not**
  `free()` one that is still reachable from a top-level `let`.

---

## 5. SDL RULES

- **The runtime is SDL 2.0.18. The headers and `pkg-config` say 2.0.20 and are lying.**
  Never bind a symbol added after 2.0.18. Check the `\version` line in the header doc-comment and
  smoke-test that the symbol resolves. `SDL_RenderGeometry` is exactly at the boundary.
- Prefer API calls to `SDL_Event` byte offsets. Use `SDL_GetRelativeMouseState`, `SDL_GetMouseState`,
  `SDL_GetKeyboardState`. The offsets are verified but an API call cannot silently break.
- `SDL_RenderCopyEx`'s `angle` is a C `double`. Pass `0.0`, never `0`. This is the easiest way to
  corrupt the call.
- **Never call `SDL_SetTextureScaleMode`.** It segfaults on SDL's internal format-conversion textures.
  `SDL_SetHint("SDL_RENDER_SCALE_QUALITY", "0")` at startup already covers every texture. This fix is
  merged upstream (wobbleweed PR #2) — do not regress it.
- Textures are `SDL_PIXELFORMAT_RGBA32` (**376840196**), whose *memory byte order is R, G, B, A*. The
  render target is `ARGB8888` (**372645892**). Both are renderer-native. Note the `*8888` names are
  packed-integer names, **not** byte order — `ARGB8888` is B,G,R,A in memory.
- `SDL_SetRelativeMouseMode` **fails under `SDL_VIDEODRIVER=dummy`** and the WARP hint does not rescue
  it. Mouse look cannot be headless-CI-tested. Handle the failure and keep rendering — `shot.hml` must
  never crash on it.
- `SDL_RenderSetVSync` returns -1 on software renderers. Treat non-zero as "unavailable", not fatal.
- SDL2_mixer: `Mix_PlayChannel` and `Mix_LoadWAV` are **C macros, not exported symbols**. Bind
  `Mix_PlayChannelTimed` and `Mix_LoadWAV_RW`. `Mix_QuickLoad_RAW` **does not copy** — every PCM
  buffer must live for the whole process, owned by `audio.hml`.

---

## 6. RENDERER RULES

- **`SDL_Vertex` is 2D. There is no z and there is no depth buffer.** Depth exists only as the painter
  sort key, and that key is **view-space `w`**, never NDC z. Larger = farther.
- **Four SDL textures. Not five.** `ATLAS_WORLD` (BLEND), `ATLAS_FX` (ADD), `ATLAS_HUD` (BLEND),
  `TEX_SKY` (none). Blend mode is per-texture, so **blend mode is the material model**.
- **Four layers, flushed in order:** SKY → WORLD (sorted) → FX (sorted) → HUD (insertion order).
- Sky at `depth = FAR`. Viewmodel at `depth = 0.05` with fog `f = 0`. No extra layer for either.
- **Screen x/y stay pixel-snapped (`floor(v + 0.5)`) and UVs stay affine.** The wobble and the warble
  are the signature. Do not "fix" them. Do keep quads ≤ 4 m so the ground warp stays charming.
- **Vertex colour multiplies the texture. You can only darken.** Every texture is authored at
  full-sun-noon albedo with minimum luminance 72, and `ambient + sun` sums to exactly (1,1,1).
- Nothing writes into a vertex buffer except through `batch_reserve`, which enforces the cap and
  returns -1 on overflow. Overflow drops a triangle and increments a counter. It never corrupts.
- **`FOG_FAR` never exceeds 72 m.** Camera far plane is `FOG_FAR * 1.06`, never a hardcoded 200.
  Fog is not an effect; it is the triangle budget. Ground tris ≈ `(π/4)·FOG_FAR²/16·2`.
- **When the budget breaks, turn `FOG_FAR` down first.** Then cut props, then LOD earlier, then cut
  overdraw. **Never cut the frame rate.**

---

## 7. SIMULATION RULES

- **`TICK_DT` is a compile-time constant (1/60).** No gameplay function ever sees a measured delta.
- **The sim loop runs 0, 1, or N times per frame.** Nothing may assume one step per frame.
- **All input reaches the sim through `InputCommand` and nowhere else.** Nine integers. No bools
  (gn.hml *throws* on a bool), no floats (truncated to f32 on the wire), no nulls (a null **silently
  truncates the rest of the packet**), no strings. Quantized **at construction**, so prediction uses
  the exact value the server will.
- **`sim_apply_command` is pure with respect to the world.** No sound, no particle, no shake, no
  `print`, no `ticks()`, no SDL. Cosmetic effects live in `sim_effects()`, which is skipped when
  `world.replaying == 1`. Replaying 8 commands must produce zero sounds.
- **Entity references are `i32` ids, never objects.** Ids are assigned by the authority, never reused
  within a session, and partitioned by kind. Client-only cosmetics use **negative** ids.
- **No entity state in a closure.** Closures cannot be snapshotted, serialized, rewound, or
  delta-compressed. It is the most tempting mistake in a scripting language and the most expensive.
- **Every movement variable lives in `PredictedState`** — coyote time, slide timer, bhop window, all
  of it. One outside means replay diverges only in one movement state, which is a brutal bug.
- **Seeded RNG with explicit streams.** `@stdlib/random` is banned under `src/sim/`.
- **The renderer reads `RenderSnapshot`, never `world.*`.**
- **The sim tick order is API.** Reordering it changes outcomes. It is written once, in
  `ARCHITECTURE.md` §4, and `sim.hml` implements exactly that.

---

## 8. THE PALETTE

Full table in `src/art/palette.hml` (from `docs/recon/ART_BIBLE.md` §3). **No colour is hardcoded
anywhere else.** CI greps for hex literals outside that file.

The rules that matter more than any individual value:

- **No pure hues.** No `(0,255,0)`, no `(128,128,128)`, no `(255,255,255)`. If a colour's channels are
  round numbers, or two channels are equal, it was typed rather than chosen.
- **Warm world, cool sky, violet threat.** Terrain, flora and architecture live in yellow-green →
  ochre → warm grey. Sky and shadows are cool.
- **`NS_CORE` `#C74FFF` is reserved.** Violet appears **only** on things that are hostile,
  collectable, or player progression. The moment it decorates a friendly building, long-range enemy
  readability dies with it. Guard this harder than any other rule in the art bible.
- **Every frame needs something below luminance 30 and something above 220.** No darks and no lights
  means no contrast anchor, and the image reads as a toy.
- **Ambient is always the complement of the sun.** Never grey ambient. This one rule is responsible
  for most of the beauty in retro 3D.
- **Minimum albedo luminance 72** in the world atlas — vertex colour can only darken.

Signature values you will type most often:

```
GRASS_MID   #7A9636   the most-seen colour in the game
DIRT_MID    #8A6840   BARK_HI  #96724A    LEAF_MID  #5A9A3C
STONE_MID   #867E6C   GUNMETAL_HI #7A8088  BRASS   #C89A3C
NS_CORE     #C74FFF   NS_MID   #8A2BD4    NS_HALO   #E8A6FF
UI_WHITE    #F4F4EC   UI_BLACK #0A0C10    UI_AMBER  #FFC444
UI_DANGER   #FF3B30   UI_GOOD  #6BE07A    UI_XP     #C74FFF
MUZZLE_CORE #FFF8DC   EMBER    #FF8A2A    TRACER    #FFDC6E
```

---

## 9. THE "NEVER DO THIS" LIST — art and design

Every one is an observed failure mode. Treat it as a code-review checklist.

1. **"Ugly on purpose."** PS1 games were not trying to look bad. If a decision's only justification is
   "it's retro," it is not justified. The test: *would a 1998 art director have shipped this, or would
   they have fixed it if they could?*
2. **Per-texel white noise as texture.** Structure at 4–10 texels or grain at ±6. Nothing in between,
   ever. The current `tex_grass` is green television static and it will shimmer in motion.
3. **No fog, or fog that doesn't match the sky.** The former makes a rug; the latter puts a visible
   seam at the skyline. Fog colour is *derived* from the horizon band, never authored separately.
4. **Flat-lit terrain.** If one `face_light()` result is applied to every ground quad, the ground is
   cardboard. Light per vertex, vary per vertex, and give the terrain real height variation.
5. **A flat horizon line.** ±1.5 m of undulation over 32 m destroys the ruler edge. Add mist and it
   becomes a landscape.
6. **Objects that float.** Every prop and every entity gets its 2-triangle contact blob. No
   exceptions, not even in a test scene. It is the highest value-per-triangle spend in the project.
7. **Debug textures in a shipping scene.** The checkerboard is a diagnostic. Ship the missing-texture
   tile as *magenta* so it is impossible to miss in a screenshot.
8. **Anti-aliased or scaled-up UI text.** Both fonts are hand-built bitfields. 1-px `UI_BLACK` shadow
   at (+1,+1), always. `FONT_BIG` is drawn separately, not scaled from `FONT_MICRO`.
9. **HUD without a contrast plate.** Test every element against noon sky, snow, a muzzle flash, and
   `CONCRETE_HI`. That is what `--scene hud_worst_case` is for.
10. **Symmetric, silhouette-identical enemies.** If two classes read the same at 12 px, one is wasted
    work. Every enemy needs one asymmetric feature and a distinct head:shoulder ratio.
11. **Attempting bloom, DOF, motion blur or real chromatic aberration.** Impossible on this renderer.
    Every hour spent is an hour not spent on fog and glow cards, which are possible and look better.
12. **Sky bands.** Bayer-dither every gradient row. The sky is 40 % of every outdoor frame.
13. **Inconsistent texel density.** 4 cm/texel on props, 12 cm/texel on ground. A mismatch is visible
    even at 320×240 and makes the world feel assembled from parts.
14. **Skipping the juice.** No hitmarker, no crosshair bloom, no screen kick, no XP popup. These cost
    almost nothing and they are the entire difference between a tech demo and a game.
15. **Overshooting the budget and dropping to 40 fps.** A gorgeous 40 fps FPS is a bad FPS.

**The hit-feedback contract, non-negotiable:** every bullet that connects produces, *within the same
frame*, all five of — hitmarker, enemy flash, damage number, impact billboard, audio blip. If any one
is missing, the gun is broken regardless of how correct the math is.

---

## 10. WHEN YOU FINISH A TASK

Report, in this order:

1. **Files written**, absolute paths.
2. **Acceptance criteria**, each with the measured number that satisfies it. Not "fast" — `2.83 ms`.
3. **Budget impact**: triangles, milliseconds, bytes. Every task has one.
4. **What you could not do** and why. An honest gap beats a quiet one — the recon phase was valuable
   precisely because it reported the two things that did not work.
5. **Anything you found that contradicts a doc.** Toolchain bugs go in `docs/HEMLOCK_ISSUES.md` with a
   minimal self-contained repro. Architecture disagreements go in `docs/ARCHITECTURE.md` §0 with a
   reason. **Do not silently work around a documented decision.**

Never claim a task is done because it compiles. `hemlockc --check` passing is criterion A of six.
