# Wobbleweed — Complete Engine API Map & Weakness Report

**Audience:** the Nightshade implementation team.
**Status of the engine as read:** commit `2972ef3` ("Merge pull request #1"), 14 source files,
1 383 lines of Hemlock in `src/`, 8 examples, 1 asset.
**Method:** every file in `src/`, `examples/`, `assets/`, `README.md` and `docs/` was read line by
line; every example was executed headless (`SDL_VIDEODRIVER=dummy`) in both the interpreter
(`hemlock`) and compiled (`hemlockc`); nine new benchmarks / repros were written and run to get
hard numbers rather than guesses. All numbers in this document were measured on this machine, in
this session. SDL is **2.0.18**.

> **Bottom line up front.** The GPU path is a real, working, correct-enough PS1-style renderer and
> it is the only viable basis for Nightshade. The CPU rasterizer is a screenshot tool, not a game
> renderer (8 fps compiled at 320×240). The GPU path as written costs **15.7 ms/frame at 2 000
> triangles** (61 fps) — but a rewritten, object-free emit path hits **1.8 ms/frame for the same
> 2 000 triangles** (422 fps). The engine is not slow because Hemlock is slow; it is slow because
> the emit path allocates ~12 heap objects per triangle and the painter's sort calls a Hemlock
> closure O(n log n) times. Both are fixable, and fixing them roughly **quadruples the triangle
> budget** from ~2 000 to ~8 000/frame.

---

## Table of contents

1. [How to build and run](#1-how-to-build-and-run)
2. [Module map](#2-module-map)
3. [Canonical data shapes](#3-canonical-data-shapes)
4. [Full API reference](#4-full-api-reference)
5. [Render path A — CPU rasterizer](#5-render-path-a--cpu-rasterizer)
6. [Render path B — GPU `SDL_RenderGeometry`](#6-render-path-b--gpu-sdl_rendergeometry)
7. [Clipping](#7-clipping)
8. [Post-processing](#8-post-processing)
9. [The OBJ loader](#9-the-obj-loader)
10. [Measured performance](#10-measured-performance)
11. [Confirmed bugs (with repros)](#11-confirmed-bugs-with-repros)
12. [Weakness list for shipping an FPS](#12-weakness-list-for-shipping-an-fps)
13. [Recommended work order](#13-recommended-work-order-for-nightshade)
14. [Appendix — Hemlock-level gotchas](#14-appendix--hemlock-level-gotchas-that-bite-the-renderer)

---

## 1. How to build and run

```bash
cd /home/nbeerbower/Projects/wobbleweed        # asset paths are relative to the repo root

# interpreted (dev only — see §11.2, the interpreter renders the GPU path WRONG)
SDL_VIDEODRIVER=dummy hemlock examples/scene_png.hml

# compiled (the only trustworthy target)
hemlockc examples/walk_gpu.hml -o /tmp/walk_gpu && SDL_VIDEODRIVER=dummy /tmp/walk_gpu
```

`hemlockc` on `walk_gpu.hml` (the whole engine + example) takes **3.3 s**. That is the iteration
cost per code change. It is fast enough to keep compiled-only as the default workflow, which is
what we must do anyway.

Runtime dependency is exactly one shared library: `libSDL2-2.0.so.0`, reached through Hemlock
`extern fn` FFI. No OpenGL, no SDL_image, no SDL_ttf, no SDL_mixer. Nothing else is linked.

### Benchmarks and repros added during this recon

All of these live in `/home/nbeerbower/Projects/wobbleweed/examples/` and all compile clean:

| File | What it measures / proves |
|---|---|
| `bench_gpu.hml` | Phase-timed GPU frame of the stock demo world |
| `bench_scale.hml` | GPU path fps vs triangle count (8×8 … 64×64 ground grid) |
| `bench_cpu.hml` | Phase-timed CPU raster frame at 160×120 … 640×480 |
| `bench_drawcalls.hml` | Draw calls per frame after the painter sort |
| `bench_flat.hml` | The same 2 000 triangles emitted with **zero** per-vertex objects |
| `probe_alpha.hml` | Proves alpha blending works through `SDL_RenderGeometry` |
| `repro_batchbuf_bug.hml` | Minimal repro of the shared-vertex-buffer bug (§11.1) |
| `repro_batchbuf_fix.hml` | The same case with per-run buffer offsets — correct on both backends |
| `repro_backend_divergence.hml` | Interpreter and compiler emit different geometry & pixels |

Sort-scaling and allocation-cost benchmarks live in the session scratchpad
(`bench_sort.hml`, `bench_bucket.hml`, `bench_alloc.hml`, `bench_struct.hml`); their results are
reproduced in §10 and they are trivially re-created from the numbers there.

---

## 2. Module map

```
                      ┌─▶ raster.hml ─▶ framebuffer.hml ─▶ sdl.present ──┐
scene.hml ────────────┤                       │                          │
  (CPU)               └─▶ sky.hml             └─▶ postfx.hml             ├─▶ window
                                              └─▶ png.hml (headless)     │
scene_gpu.hml ────────▶ geom.hml ─▶ sdl.draw_tris ─▶ SDL_RenderGeometry ─┘
  (GPU)

shared by both: vec.hml (math) · clip.hml (near + guard-band) · texture.hml · obj.hml
```

| File | LOC | Role | Depends on |
|---|---:|---|---|
| `src/vec.hml` | 108 | vec3 + row-major 4×4 matrices, projection, look-at | `@stdlib/math` |
| `src/sdl.hml` | 173 | the entire SDL2 FFI surface: window, present, input, GPU geometry | `libSDL2-2.0.so.0` |
| `src/framebuffer.hml` | 48 | CPU colour (RGB24 buffer) + depth (array\<f64\>) buffers | `png.hml` |
| `src/texture.hml` | 94 | texture struct + three procedural generators | — |
| `src/raster.hml` | 158 | CPU triangle rasterizer, 3 variants, z-tested | `@stdlib/math` |
| `src/clip.hml` | 111 | near-plane clip (clip space) + guard-band clip (screen space) | — |
| `src/geom.hml` | 71 | GPU triangle batch: painter sort + texture-run batching | `sdl.hml` |
| `src/sky.hml` | 57 | CPU procedural sky (per-pixel), resets depth | `framebuffer.hml` |
| `src/postfx.hml` | 38 | PS1 4×4 ordered dither → 5-bit (CPU only) | — |
| `src/png.hml` | 108 | PNG **writer** (stored-deflate only) | `@stdlib/hash`, `@stdlib/math` |
| `src/obj.hml` | 104 | Wavefront OBJ loader + material→colour palette | `vec.hml` |
| `src/scene.hml` | 149 | the hardcoded demo world, CPU renderer | most of the above |
| `src/scene_gpu.hml` | 194 | the same hardcoded world, GPU renderer | most of the above |

There is **no** engine entry point, no `engine.hml`, no init/shutdown lifecycle, no resource
manager, no game loop abstraction. Every example open-codes its own loop. That is fine for a demo
and a problem for a game — see §12.24.

---

## 3. Canonical data shapes

Everything in the engine is a plain Hemlock object or array. There are no classes and no
`define` structs. Field names below are exact.

### 3.1 vec3
```hemlock
{ x: f64, y: f64, z: f64 }
```
Produced by `v3()` and by every `v_*` operator. **Every operation allocates a new object.**

### 3.2 4×4 matrix
```hemlock
[f64; 16]        // row-major, flat Hemlock array
```
`m[row*4 + col]`. `mat_apply` uses `m[0..3]` for x, `m[4..7]` for y, `m[8..11]` for z,
`m[12..15]` for w.

### 3.3 Homogeneous point (`mat_apply` result)
```hemlock
{ x: f64, y: f64, z: f64, w: f64 }
```

### 3.4 Texture
```hemlock
{ width: i32, height: i32, data: buffer }   // data is width*height*3 bytes, RGB24, row-major
```
No alpha channel. No mip levels. No palette. Nearest sampling only. Used directly by
`raster.fill_tri_tex` (CPU) and uploaded to an `SDL_Texture*` by `sdl.upload_texture` (GPU).

### 3.5 Framebuffer (CPU path only)
```hemlock
{ width: i32, height: i32,
  color: buffer,        // width*height*3 bytes RGB24 row-major (maps 1:1 to SDL_PIXELFORMAT_RGB24)
  depth: array<f64> }   // width*height, smaller = nearer, cleared to DEPTH_FAR = 1.0e30
```
Note `depth` is a **Hemlock array of boxed f64**, not a buffer — at 320×240 that is 76 800 boxed
values (~1.2 MB) touched per covered pixel. See §12.2.

### 3.6 Clip vertex (input to `clip_tri_near`)
```hemlock
{ x, y, z, w,      // clip space, pre-divide
  u, v,            // texture coords
  l }              // scalar light 0..1
```
All f64. `clip.lerp_cv` interpolates all seven fields linearly (exact in clip space).

### 3.7 Screen / geom vertex (input to `batch_tri` and `clip_tri_rect`)
```hemlock
{ x: f64, y: f64,   // screen pixels, ALREADY snapped to whole pixels by to_screen()
  z: f64,           // NDC depth, larger = farther; used ONLY for the painter sort
  u: f64, v: f64,   // texture coords, affine
  r: i32, g: i32, b: i32 }   // 0..255 vertex colour; modulates the texture
```
There is **no alpha field.** `geom.put_vert` hardcodes `A = 255`.

### 3.8 Screen vertex, CPU flavour (output of `scene.to_screen`)
```hemlock
{ x, y, z, u, v, l }   // note: 'l' scalar light, NOT r/g/b — the two paths use different shapes
```

### 3.9 Batch (GPU)
```hemlock
{ tris: array<TriRecord>,   // rebuilt every frame
  buf: ptr,                 // alloc(max_tris * 3 * 20) — raw SDL_Vertex staging memory
  cap: i32 }                // max_tris — WRITTEN BUT NEVER CHECKED (see §11.3)

TriRecord = { tex: ptr|null, depth: f64, a: GeomVertex, b: GeomVertex, c: GeomVertex }
```

### 3.10 Packed `SDL_Vertex` (what actually reaches the GPU)
20 bytes, written by `geom.put_vert`:

| Offset | Type | Field |
|---:|---|---|
| 0 | f32 | position.x |
| 4 | f32 | position.y |
| 8 | u8 | colour.r |
| 9 | u8 | colour.g |
| 10 | u8 | colour.b |
| 11 | u8 | colour.a — **always 255** |
| 12 | f32 | tex_coord.u |
| 16 | f32 | tex_coord.v |

`SDL_Vertex` is 2D. There is no z, so there can be no hardware depth test. That is the single
structural fact that dictates the whole occlusion story.

### 3.11 Mesh (OBJ loader output)
```hemlock
{ pos:   array<vec3>,
  uv:    array<{u: f64, v: f64}>,     // v flipped to top-down; PARSED BUT NEVER USED BY EITHER RENDERER
  nrm:   array<vec3>,                 // computed smooth normals if the file has none
  faces: array<Face>,
  mats:  array<string> }              // usemtl names, first-use order

Face = { pa, pb, pc,   // position indices
         ta, tb, tc,   // uv indices (-1 = absent)
         na, nb, nc,   // normal indices
         m }           // index into mats / palette
```

### 3.12 Tree bundle (what `load_tree` returns)
```hemlock
{ mesh: Mesh, colors: array<{r: i32, g: i32, b: i32}> }   // colors indexed by face.m
```

### 3.13 Window handle
```hemlock
{ win: ptr, ren: ptr, tex: ptr, ev: ptr, width: i32, height: i32 }
```
`tex` is the streaming RGB24 texture used only by the CPU path's `present()`. `ev` is a 256-byte
`alloc` reused for every `SDL_PollEvent`.

---

## 4. Full API reference

Signatures are given as written. Parameters without a type annotation are dynamically typed
(which costs performance — see §14.1).

### 4.1 `src/vec.hml`

```hemlock
export fn v3(x: f64, y: f64, z: f64): object      // { x, y, z }
export fn v_add(a, b)                              // a + b
export fn v_sub(a, b)                              // a - b
export fn v_scale(a, s)                            // a * s
export fn v_dot(a, b): f64
export fn v_cross(a, b)
export fn v_len(a): f64
export fn v_norm(a)                                // returns {0,0,0} if |a| < 1e-9

export fn mat_identity()                           // [f64;16]
export fn mat_mul(a, b)                            // C = A·B, row-major; allocates a 16-array
export fn mat_apply(m, v)                          // point (w=1)  -> { x, y, z, w }
export fn mat_apply_dir(m, v)                      // direction (w=0) -> { x, y, z }
export fn mat_translate(x: f64, y: f64, z: f64)
export fn mat_scale(x: f64, y: f64, z: f64)
export fn mat_rot_y(a: f64)
export fn mat_rot_x(a: f64)
export fn mat_perspective(fov: f64, aspect: f64, near: f64, far: f64)   // RH, looks down -Z, fov in radians
export fn mat_look_at(eye, target, up)
```

**Missing:** `mat_rot_z`, matrix inverse, transpose, quaternions, `v_lerp`, `v_dist`,
`v_reflect`, AABB/ray/plane helpers. All of these are needed for an FPS (recoil, ragdolls,
hitscan, bullet reflection, frustum planes).

**Gotcha:** `mat_look_at` degenerates when the forward vector is parallel to `up`. The examples
avoid it by clamping pitch to ±1.4 rad (±80°). An FPS needs ±89° and a proper basis construction.

### 4.2 `src/sdl.hml`

Declared externs (the complete list — this is the engine's entire OS surface):

```
SDL_Init, SDL_CreateWindow, SDL_CreateRenderer, SDL_CreateTexture,
SDL_RenderSetLogicalSize, SDL_UpdateTexture, SDL_SetTextureScaleMode,
SDL_SetRenderDrawColor, SDL_RenderClear, SDL_RenderCopy, SDL_RenderGeometry,
SDL_RenderReadPixels, SDL_RenderPresent, SDL_PollEvent, SDL_GetKeyboardState,
SDL_Delay, SDL_GetTicks, SDL_GetError,
SDL_DestroyTexture, SDL_DestroyRenderer, SDL_DestroyWindow, SDL_Quit
```

Exports:

```hemlock
// keycodes (SDLK_*), for edge-triggered keys from poll().keys
export let KEY_ESCAPE = 27; KEY_SPACE = 32; KEY_LEFT/RIGHT/UP/DOWN; KEY_W/A/S/D

// scancodes (SDL_SCANCODE_*), for held-key polling
export let SC_A=4, SC_D=7, SC_E=8, SC_Q=20, SC_S=22, SC_W=26,
           SC_RIGHT=79, SC_LEFT=80, SC_DOWN=81, SC_UP=82,
           SC_LSHIFT=225, SC_SPACE=44

export fn window_open(title: string, width: i32, height: i32, scale: i32): object
    // creates window at width*scale x height*scale, RenderSetLogicalSize(width,height),
    // streaming RGB24 texture. Renderer created with flags=0 (SDL picks; do NOT force
    // ACCELERATED — under the dummy driver the compiler backend then fails RenderGeometry
    // with "Invalid renderer"). Returns null on failure.

export fn present(w: object, pixels: ptr)                 // CPU path: UpdateTexture + Clear + Copy + Present
export fn upload_texture(w: object, tex: object): ptr     // Wobbleweed texture -> static SDL_Texture, NEAREST
export fn clear(w: object, r: i32, g: i32, b: i32)        // GPU path frame start
export fn draw_tris(w: object, sdltex, vbuf: ptr, nverts: i32)   // SDL_RenderGeometry(ren, tex, vbuf, nverts, null, 0)
export fn present_geom(w: object)                          // GPU path frame end
export fn read_pixels(w: object, dst)                      // RenderReadPixels into an RGB24 buffer (headless PNG)
export fn poll(w: object): object                          // { quit: bool, keys: array<i32> } — QUIT + KEYDOWN only
export fn keystate(): ptr                                  // SDL_GetKeyboardState(null)
export fn held(state: ptr, scancode: i32): bool
export fn ticks(): i32                                     // SDL_GetTicks(), milliseconds
export fn delay(ms: i32)
export fn window_close(w: object)
```

Notes that matter:

* `poll()` handles **only** `SDL_QUIT` (0x100) and `SDL_KEYDOWN` (0x300). Mouse motion,
  mouse buttons, key-up, window resize, gamepad — all silently dropped.
* `held()` requires `poll()` to have run this frame (that is what pumps the event queue).
* `ticks()` returns `SDL_GetTicks()` (u32 ms) narrowed to i32 — 1 ms resolution and it wraps.
  `SDL_GetPerformanceCounter` exists in this SDL and should be used instead.
* `SDL_RenderSetLogicalSize(ren, width, height)` means **all GPU geometry is submitted in
  logical 320×240 coordinates and SDL scales the rasterization up to the window**. Textures are
  magnified with NEAREST so they stay chunky, but the *geometry* is rasterized at window
  resolution — the polygon edges are not actually 320×240-chunky. For a true PS1 look you want a
  320×240 render target upscaled NEAREST (see §12.20).
* No `SDL_RENDERER_PRESENTVSYNC`. Frame pacing is a hardcoded `delay(4)` in the examples.

### 4.3 `src/framebuffer.hml`

```hemlock
export const DEPTH_FAR = 1.0e30
export fn fb_new(width: i32, height: i32): object          // { width, height, color: buffer, depth: array<f64> }
export fn fb_clear(fb, r: i32, g: i32, b: i32)             // per-pixel loop + depth.fill
export fn fb_clear_sky(fb, tr,tg,tb, br,bg,bb: i32)        // vertical gradient + depth.fill
export fn fb_save(fb, path: string)                        // -> write_png
```

### 4.4 `src/texture.hml`

```hemlock
export fn tex_new(w: i32, h: i32): object                  // { width, height, data: buffer(w*h*3) }
export fn tex_grass(w: i32, h: i32): object                // noisy greens, hash2-based
export fn tex_sky(w: i32, h: i32): object                  // horizontally tileable sky panorama with cloud streaks
export fn tex_checker(w: i32, h: i32, cells: i32): object  // makes the affine warp visible
```
Private: `hash2(x, y): i32` (i64 math with 32-bit masking to dodge Hemlock's i32 overflow trap),
`fabs`.

There is **no texture loader.** `png.hml` writes PNG but cannot read it. All texture art today
must be procedural or hand-built in Hemlock code.

### 4.5 `src/raster.hml` (CPU only)

```hemlock
export fn fill_tri(fb, ax,ay,az, bx,by,bz, cx,cy,cz: f64, r,g,b: i32)
export fn fill_tri_shade(fb, ax,ay,az,la, bx,by,bz,lb, cx,cy,cz,lc: f64, r,g,b: i32)
export fn fill_tri_tex(fb, ax,ay,az,ua,va,la, bx,by,bz,ub,vb,lb, cx,cy,cz,uc,vc,lc: f64, tex)
```
All three: edge-function barycentric coverage over the triangle's screen bounding box, clamped
to the framebuffer, **affine** attribute interpolation (that's the PS1 texture swim), z-test
`z < depth[idx]` with write. Handles both windings (`pos = area > 0.0`) — i.e. **no backface
culling anywhere in the engine.** UV wrap is `i32(u*tw) % tw` with a negative fix-up. Light is
clamped to [0,1] in `fill_tri_shade` but **not** in `fill_tri_tex` (a sliver can extrapolate
light > 1 and wrap the `& 255`, producing a colour glitch).

### 4.6 `src/clip.hml`

```hemlock
export fn clip_tri_near(a, b, c)
    // Sutherland–Hodgman against clip-space z + w >= EPS (EPS = 1e-6).
    // Returns array of 0, 1 or 2 triangles, each an array of 3 clip vertices. Winding preserved.
    // Early-outs: all-in -> [[a,b,c]] (1 add + 3 compares); all-out -> [].

export fn clip_tri_rect(a, b, c, x0, y0, x1, y1: f64)
    // Screen-space guard-band clip. Returns 0..5 triangles. Early-outs when fully inside.
    // Needed because SDL's software rasterizer silently rejects triangles whose fixed-point
    // cross products overflow.
```
Private: `ndist`, `lerp_cv` (7-field clip vertex), `lerp_sv` (8-field geom vertex),
`clip_half(poly, dfn)` — which takes a **closure**, so each non-trivial clip allocates 4 closures.

There is **no far-plane clip, no side-plane clip in clip space, and no frustum culling.**
`scene_gpu` calls `clip_tri_rect` with a margin of `2*W` — i.e. the guard rect is
[-640, 960] × [-640, 880] for a 320×240 view. That is **31× the screen area**, so as an
incidental cull it removes almost nothing.

### 4.7 `src/geom.hml` (GPU batch)

```hemlock
export fn batch_new(max_tris: i32)      // { tris: [], buf: alloc(max_tris*3*20), cap: max_tris }
export fn batch_reset(b)                // b.tris = []  (exported, never used)
export fn batch_tri(b, tex, a, bb, c)   // depth = (a.z + bb.z + c.z)/3, push a TriRecord
export fn batch_flush(w, b)             // sort desc by depth, emit one SDL_RenderGeometry per
                                        // *consecutive* same-texture run, then b.tris = []
```
Private `put_vert(buf, vi, v)` packs the 20-byte `SDL_Vertex` described in §3.10.

The sort comparator is a Hemlock closure:
```hemlock
tris.sort(fn(p, q) {
    if (p.depth > q.depth) { return 0 - 1; }
    if (p.depth < q.depth) { return 1; }
    return 0;
});
```
This is the hot spot analysed in §10.3. `b.cap` is never enforced — see §11.3.

### 4.8 `src/sky.hml` (CPU only)

```hemlock
export fn draw_sky(fb, yaw: f64, pitch: f64)
    // per-pixel: vertical gradient + chunky value-noise cloud streaks panned by yaw/pitch
    // (xoff = yaw*110, yoff = pitch*80, CHUNK = 13), then fb.depth.fill(DEPTH_FAR)
```
`fb.depth.fill(DEPTH_FAR)` inside `draw_sky` means the sky **doubles as the depth clear.** If you
skip the sky you must clear depth yourself.

### 4.9 `src/postfx.hml` (CPU only)

```hemlock
export fn fb_retro(fb)   // PS1 GPU 4x4 ordered dither offsets, quantize to 5 bits/channel,
                         // re-expand as v | (v >> 5)
```
Runs over every pixel × 3 channels in Hemlock. Measured **11.3 ms at 320×240** — see §10.2.

### 4.10 `src/png.hml`

```hemlock
export fn write_png(path: string, color: buffer, width: i32, height: i32)
```
Truecolour RGB, bit depth 8, filter None, zlib with **stored (uncompressed) deflate blocks only**.
A 320×240 screenshot is 230 KB. No reader. Uses `crc32`/`adler32` from `@stdlib/hash`.

### 4.11 `src/obj.hml`

```hemlock
export fn load_obj(path: string)                 // -> Mesh (§3.11)
export fn palette(mesh, table, def)              // { name: {r,g,b} } + default -> array indexed by face.m
```
Handles `v`, `vt`, `vn`, `usemtl`, `f` with all index forms (`v`, `v/t`, `v/t/n`, `v//n`,
negative indices), polygons fan-triangulated, `#` comments, tabs. If the file has no `vn`, smooth
normals are computed as the sum of **area-weighted** face normals per vertex, then normalized,
and every corner is repointed at its position's normal.

Not handled: `.mtl` files, `o`/`g` groups (everything collapses into one mesh), smoothing groups
(`s`), line continuations, `\r\n` (the `\r` will end up inside the last token of every line on a
CRLF file — an OBJ exported on Windows will fail to parse).

### 4.12 `src/scene.hml` (CPU demo world)

```hemlock
export fn camera_mvp(eye, target, w: i32, h: i32)     // perspective(fov=1.15, aspect=w/h, 0.1, 200) * look_at(eye,target,+Y)
export fn load_tree(path: string)                      // { mesh, colors } with a hardcoded trunk/leaves palette
export fn render_mesh(fb, mvp, tree, model, W: f64, H: f64)
export fn render_world(fb, mvp, yaw, pitch, grass, crate, tree)
```
`render_world` is the hardcoded demo: `draw_sky`, then a 16×16 grid of ground quads over
±26 units, then a 5-face crate at the origin, then the tree at (−5, 0, −3). Sun direction and
ambient are module-level constants (`SUN = normalize(0.4, 1.0, 0.55)`, `AMBIENT = 0.45`).

### 4.13 `src/scene_gpu.hml` (GPU demo world)

```hemlock
export fn camera_mvp(eye, target, w: i32, h: i32)      // identical to scene.hml's
export fn load_tree(path: string)                       // identical to scene.hml's
export fn render_mesh_gpu(b, mvp, tree, model, W: f64, H: f64)
export fn render_world_gpu(b, mvp, yaw: f64, W: f64, H: f64, gtex, ctex, skytex, tree)
```
Private and worth knowing: `emit_sky(b, skytex, yaw, W, H)` draws the sky as a screen-space quad
at `z = 2.0` (past the far plane so the painter draws it first), sampling a **horizontal window of
width `HFOV/2π` = 0.226** of the panorama texture, offset by yaw, split into two quads when the
window crosses the wrap seam so UVs always stay in [0,1].

`recolor(v, col)` re-tints the grey Gouraud vertex colour per channel for untextured meshes.

**Note:** `scene.hml` and `scene_gpu.hml` are two independent ~150-line copies of the same world
with subtly different crate winding and UV assignment, so the two paths do **not** produce
identical images despite the README's claim.

---

## 5. Render path A — CPU rasterizer

Pipeline, exactly as coded in `scene.render_world`:

```
draw_sky(fb, yaw, pitch)            // per-pixel gradient + noise, also clears depth
for each quad / mesh face:
    cv(mvp, p, u, v, l)             // mat_apply -> clip-space vertex {x,y,z,w,u,v,l}
    clip_tri_near(a, b, c)          // 0..2 triangles
    to_screen(v, W, H)              // perspective divide, viewport, floor(+0.5) pixel snap
    fill_tri_tex / fill_tri_shade   // affine UV + light, z-tested per pixel
fb_retro(fb)                        // optional PS1 dither
present(win, buffer_ptr(fb.color))  // SDL_UpdateTexture + RenderCopy + Present
```

**Verdict: unusable for a shipping FPS.** Measured, compiled, headless, on the stock demo world
(~560 triangles):

| Resolution | fps | sky | world | postfx |
|---|---:|---:|---:|---:|
| 160×120 | 31 | 7.7 ms | 21.2 ms | 2.8 ms |
| 320×240 | **8** | 30.6 ms | 74.3 ms | 11.3 ms |
| 480×360 | 3 | 68.6 ms | 163.2 ms | 25.5 ms |
| 640×480 | 2 | 121.0 ms | 286.8 ms | 44.7 ms |

(The `world` column double-counts the sky because `render_world` calls `draw_sky` itself; even
correcting for that, 320×240 is ~86 ms/frame ≈ 11.7 fps.)

Fill rate works out to roughly **4.5 Mpixel/s**. A 320×240 frame at 60 fps with only 2× overdraw
needs 9.2 Mpixel/s. The CPU path is 2–3× short of viable at the *lowest* interesting resolution,
before any gameplay, HUD, particles or enemies.

**What it is still good for:** deterministic golden-image tests, offline asset previews, and
generating marketing screenshots with the dither pass. Keep it; do not ship on it.

---

## 6. Render path B — GPU `SDL_RenderGeometry`

Pipeline, exactly as coded in `scene_gpu.render_world_gpu` + `geom.batch_flush`:

```
clear(win, 0,0,0)
emit_sky(b, skytex, yaw, W, H)      // 2 or 4 screen-space triangles at z = 2.0
for each quad / mesh face:
    cv(mvp, p, u, v, l)             // clip-space vertex
    clip_tri_near(a, b, c)          // 0..2 triangles
    to_screen(v, W, H)              // divide, viewport, pixel snap, light -> grey vertex colour
    clip_tri_rect(p0,p1,p2, -2W, -2W, W+2W, H+2W)   // guard band, 0..5 triangles
    batch_tri(b, tex, ...)          // push { tex, depth=centroid ndc z, a, b, c }
batch_flush(win, b)
    tris.sort(closure)              // descending depth: farthest first
    for each consecutive same-texture run:
        pack SDL_Vertex into b.buf from offset 0
        SDL_RenderGeometry(ren, tex, b.buf, nverts, null, 0)
present_geom(win)
```

Occlusion is painter's algorithm on the **centroid NDC z**. There is no depth buffer because
`SDL_Vertex` has no z. Gouraud shading is free (vertex colour modulates the texture). Affine UVs
are automatic because `SDL_Vertex` is 2D — the wobble is a property of the API, not a choice.

Measured, compiled, headless (SDL software renderer under the dummy driver):

| Ground grid | tris/frame | fps | emit (CPU) | flush | of which sort |
|---|---:|---:|---:|---:|---:|
| 8×8 | 138 | 750 | 0.7 ms | 0.23 ms | 0.05 ms |
| 16×16 | 515 | 240 | 2.5 ms | 1.02 ms | 0.48 ms |
| 24×24 | 1 135 | 107 | 5.7 ms | 2.82 ms | 1.15 ms |
| **32×32** | **1 997** | **58–61** | **10.0 ms** | **5.9 ms** | **2.95 ms** |
| 40×40 | 3 101 | 38 | 15.0 ms | 9.4 ms | 5.02 ms |
| 48×48 | 4 447 | 25 | 21.5 ms | 15.6 ms | 9.03 ms |
| 64×64 | 7 865 | 12 | 38.0 ms | 36.4 ms | 21.9 ms |

The stock demo world runs at **267 fps / 376 triangles** with `emit = 2.6 ms`,
`flush = 0.64 ms`, `present = 0.44 ms`.

Two things jump out:

1. **`emit` dominates.** At 2 000 triangles the CPU spends 10 ms projecting and clipping — 60 %
   of a 16.6 ms frame — before SDL sees a single vertex. That is ~5 µs per triangle for what is
   arithmetically about 40 multiply-adds. The cost is allocation, not math (§10.4).
2. **Sort is 18 % of the frame at 2 000 tris and it is a landmine** (§10.3).

Note the flush/present numbers are with SDL's *software* renderer (no display). On a real
accelerated renderer, `flush`'s rasterization component and `present` drop toward zero;
`emit` and `sort` are pure CPU and do not change.

---

## 7. Clipping

* **Near plane, clip space** (`clip_tri_near`): correct Sutherland–Hodgman, winding preserved,
  attributes interpolate linearly in clip space (exact). Cheap early-outs. This is good code.
* **Guard band, screen space** (`clip_tri_rect`): correct, but it exists only to stop SDL's
  software rasterizer overflowing its fixed-point cross products. Its rect is ±2 screens, so it
  is not a cull.
* **Not present:** far-plane clip, left/right/top/bottom clip in clip space, frustum culling
  against the camera's six planes, occlusion culling, portal/PVS, backface culling.

Practical consequence for an open world: every chunk you hand the renderer is fully projected and
clipped even if it is entirely behind the player. At 2 000 emitted triangles you can afford maybe
600 visible ones.

---

## 8. Post-processing

`postfx.fb_retro(fb)` is the PS1 GPU's own 4×4 ordered dither table applied per channel, then a
5-bit truncate (`v & 248`) and re-expand (`v | v>>5`). It is **CPU-framebuffer only** and costs
11.3 ms at 320×240 (147 ns/pixel). The GPU path has no post-processing at all: no dither, no
colour grading, no vignette, no bloom, no motion blur, no screen flash, no damage vignette, no
scanlines.

Any GPU-path post-effect requires rendering into an `SDL_Texture` created with
`SDL_TEXTUREACCESS_TARGET` via `SDL_SetRenderTarget`, then compositing. Neither extern is
declared today.

---

## 9. The OBJ loader

Solid for what it is. `assets/tree.obj` is 24 vertices / 32 triangles / 2 materials (hex-prism
trunk + icosahedron canopy) and loads in the demo in well under a millisecond.

Real limitations for a game:

* **UVs are parsed and then ignored.** `render_mesh` and `render_mesh_gpu` both call
  `cv(mm, mesh.pos[...], 0.0, 0.0, l)` — hardcoded UV (0,0). **Meshes cannot be textured today.**
  Every OBJ renders as flat per-material colour with Gouraud light. For a game with guns, props,
  and characters this is the single biggest content limitation in the engine.
* No `.mtl`, so materials are a name→RGB table you write in Hemlock.
* No groups/objects: a multi-part model collapses into one draw.
* Normals are transformed by the **model matrix**, not its inverse-transpose, so non-uniform
  scaling breaks lighting.
* `render_mesh_gpu` re-transforms and re-normalizes **three normals per face, every frame**
  (`v_norm(mat_apply_dir(model, ...))` ×3). Shared vertices are recomputed once per incident
  face. For a 32-triangle tree that's 96 normalizes per instance per frame; 50 trees = 4 800
  normalizes + ~10 000 object allocations per frame just for lighting that never changes.
* Loading is text parsing with `split` per line and per corner; fine at 32 triangles, unusable as
  a level format. Nightshade needs a binary/precomputed mesh format.

---

## 10. Measured performance

All numbers: this machine, this session, `hemlockc`-compiled, `SDL_VIDEODRIVER=dummy`.

### 10.1 Reference points

| Configuration | Result |
|---|---|
| Stock demo world, GPU path, 376 tris | **267 fps** |
| GPU path @ 2 000 tris | **58–61 fps** |
| GPU path @ 4 447 tris | 25 fps |
| CPU path, 320×240, 560 tris | **8 fps** |
| Object-free emit, 2 000 tris, 1 draw call, no sort | **422 fps** |

### 10.2 CPU per-pixel cost

`fb_retro` at 320×240 = 11.3 ms for 76 800 pixels → **147 ns/pixel** for a 3-channel read-modify-
write. `draw_sky` = 30.6 ms → **397 ns/pixel** (it calls `hash2` twice per pixel).

**Rule for Nightshade: there is no budget for even one full-screen CPU per-pixel pass.** A single
320×240 sweep is ~10 ms. HUD, text, crosshair, muzzle flash, damage flash — all of it must be GPU
triangles.

### 10.3 The painter's sort — the landmine

`array.sort(comparator)` in the **compiled** runtime is `hml_array_sort` in
`runtime/src/builtins_array.c`: a **plain Lomuto quicksort, no randomization, no median-of-three,
fully recursive**. In the **interpreter** it is a **stable insertion sort** (O(n²) always).

Measured, compiled, with the exact `batch_flush` comparator, ms per sort:

| n | random depths | already ascending | descending | runs of equal depth |
|---:|---:|---:|---:|---:|
| 500 | 0.30 | 6.8 | 4.4 | 1.15 |
| 1 000 | 0.80 | 25.2 | 19.6 | 6.0 |
| **2 000** | **1.20** | **106.9** | **73.1** | **41.3** |
| 4 000 | 3.40 | 388.0 | 280.2 | 155.2 |

Read that table again. **On already-sorted input, sorting 2 000 triangles takes 107 ms — 9 fps
from the sort alone.** Quadratic confirmed at larger n: 8 000 → 1.4 s, 16 000 → 5.7 s,
32 000 → 22.6 s. (No stack overflow up to 32 000, but recursion depth is O(n) on sorted input, so
a large enough batch will smash the C stack.)

The stock demo world happens to emit triangles in a scrambled-enough depth order that it lands
near the "random" column (2.95 ms at 2 000). **That is luck.** The natural way to emit a chunked
open world — walk chunks in front-to-back or back-to-front order, emit each chunk's quads in grid
order — produces *exactly* the ascending/descending input that costs 107 ms. Nightshade would
have hit this on day one and it would have looked like "Hemlock is too slow for a game."

**Replacement, measured:** a 1024-bucket counting sort on quantized depth, written in plain
Hemlock over flat arrays:

| n | bucket sort, random | bucket sort, sorted input |
|---:|---:|---:|
| 2 000 | **0.275 ms** | **0.275 ms** |
| 4 000 | 0.45 ms | 0.55 ms |
| 8 000 | 0.90 ms | 0.95 ms |

Linear, input-order independent, **10× faster than the best case and 390× faster than the worst
case** of the current sort.

One caveat when implementing it: `batch_tri` uses centroid **NDC z**, which for a
`near=0.1 / far=200` projection is approximately `1 − 0.2/d`. Beyond ~10 m everything crushes into
the top few buckets. Bucket on **view-space depth (the clip-space `w`)** or on `1/z` linearized
against the actual play distance, not raw NDC z.

### 10.4 Allocation churn — why `emit` costs 10 ms

Measured allocation costs (compiled, 1 M iterations):

| Operation | Cost each |
|---|---:|
| 7-field object literal | **216 ns** |
| 3-field object literal | 102 ns |
| 3-element array | 46 ns |
| 7 writes into a preallocated flat array | 94 ns total (13 ns/write) |
| 7 `ptr_write_f32` into raw memory | 112 ns total (16 ns/write) |
| 7-field `define` **struct** | **223 ns** — *no better than a plain object* |

`define` structs are FFI layout descriptors, not value types; they allocate exactly like objects.
**Flat arrays and raw buffers are the only escape.**

Counting allocations in the current GPU emit path, per fully-visible textured triangle:

* `cv()` → `mat_apply` object + the clip-vertex object = **2 objects per corner**
* `clip_tri_near` all-in fast path → `[[a,b,c]]` = **2 arrays**
* `to_screen` ×3 = **3 objects**
* `clip_tri_rect` all-in fast path → `[[a,b,c]]` = **2 arrays**
* `batch_tri` push → **1 object**

≈ **8 objects + 4 arrays = 12 heap allocations per triangle**. At 2 000 triangles that is
**24 000 allocations per frame**, 1.44 M/s at 60 fps. Meshes are worse (~15/triangle, because of
the per-face normal transform + `recolor`).

`bench_flat.hml` proves the ceiling: the same 32×32 grid, same 2 004 triangles, projected with
scalars written straight into the `SDL_Vertex` buffer, no intermediate objects, no clip module,
one draw call, no sort → **emit = 1.8 ms, 422 fps**. That is a **5.5× reduction in emit cost** and
a **7× overall speedup**.

Add back a bucket sort (0.28 ms) and a cheap near-clip fallback for the rare crossing triangle,
and a realistic post-rewrite budget is **~8 000 triangles at 60 fps** instead of 2 000.

Good news on the runtime model: Hemlock is **reference counted** (`hml_retain`/`hml_release`),
not tracing-GC'd. Churn costs steady-state throughput but there are **no GC pause spikes**. Frame
times will be smooth once throughput is fixed.

### 10.5 Draw calls

`bench_drawcalls.hml` on the stock demo world: **389 triangles → 47.5 draw calls per frame
(max 63)**, with only four textures in the scene. `batch_flush` merges only *consecutive*
same-texture runs after the depth sort, and depth-sorting interleaves ground/crate/tree, so runs
average ~8 triangles. With a single texture atlas the same frame is **1–2 draw calls**.

---

## 11. Confirmed bugs (with repros)

### 11.1 `batch_flush` reuses one vertex buffer across draw calls → wrong pixels

`batch_flush` rewinds `vi = 0` for **every** texture run and re-packs into the same `b.buf`, then
calls `SDL_RenderGeometry`. SDL 2 queues render commands and processes them at flush/present time.
Handing SDL the same memory for several queued draws is undefined; in practice the earlier draws
end up reading the buffer's later contents.

**Repro:** `examples/repro_batchbuf_bug.hml` — a full-screen sky quad (texture A) plus a grass
quad (texture B), i.e. exactly two texture runs.

```
compiled:    top=60,100,196   mid(160,60)=82,121,203    <- correct gradient
interpreter: top=60,100,196   mid(160,60)=60,100,196    <- flat, whole sky is texel (0,0)
```

The visible symptom in the stock demo is that `SDL_VIDEODRIVER=dummy hemlock examples/geom_scene.hml`
renders a **completely cloudless flat blue sky**, while `docs/scene_gpu.png` (captured on an
accelerated renderer) and the compiled build both show the clouds. Every sky pixel in the
interpreted render is exactly `(60,100,196)` = texel (0,0) of the sky panorama.

**Fix (verified):** `examples/repro_batchbuf_fix.hml` — pack every run into a *disjoint* region of
one frame-long vertex buffer and pass `ptr_offset(buf, run_start * 20, 1)` to each
`SDL_RenderGeometry`. Both backends then produce identical, correct output. This is also faster
(one contiguous fill, no rewind) and it is the natural shape for a per-frame arena.
**File: `src/geom.hml`.**

### 11.2 The interpreter and the compiler produce different geometry *and* different pixels

`examples/repro_backend_divergence.hml` renders the identical scene both ways:

```
interpreter: total = 404 triangles
compiled:    total = 425 triangles
```

Same camera, same world, same code. The triangle counts differ, which means the two backends
disagree somewhere in the near-clip / guard-band float arithmetic. Combined with §11.1, the
README's claim of "byte-identical output ... in the interpreter and compiled" is **false today**.

**Consequence for Nightshade:** the interpreter is not a valid preview of the shipping renderer.
Treat `hemlockc` as the only ground truth, and make golden-image tests compile first. (We were
going to ship compiled anyway; the trap is doing visual work in the interpreter because it starts
faster.)

### 11.3 `batch_new(cap)` is not enforced → heap corruption on overflow

`b.cap` is stored and never read. `batch_tri` pushes without limit; `batch_flush` writes
`3 × 20` bytes per triangle into `b.buf`, which is only `cap × 3 × 20` bytes.

**Repro:** queue 4 000 triangles into `batch_new(16)`. The run dies with a nonsense error from
deep inside the runtime —
`Uncaught exception: Object has no field 'tex'` — i.e. the write ran off the end of `buf` and
corrupted adjacent heap objects. The same program with `batch_new(4096)` completes cleanly.

An open world with variable draw distance *will* exceed any fixed cap eventually. This must
become a hard clamp (drop the overflow triangles and count them) or a growable buffer.
**File: `src/geom.hml`.**

### 11.4 `fill_tri_tex` does not clamp interpolated light

`fill_tri_shade` clamps light to [0,1]; `fill_tri_tex` does not, then does
`i32(td[to] * light) & 255`. A sliver triangle whose barycentrics extrapolate slightly can wrap
the channel and produce a bright speckle. **File: `src/raster.hml`.** (CPU path only, low
priority.)

### 11.5 The two scene modules have drifted

`scene.hml` builds the crate's +X face from corner list `[1,5,6,2]`; `scene_gpu.hml` builds it
from `(x1,y1,z1),(x1,y1,z0),(x1,y0,z0),(x1,y0,z1)`. Different vertex order → different UV
orientation → the checker pattern is visibly stretched differently between the two paths. The sky
is also completely different code (per-pixel procedural vs. panorama texture). These are two
independent worlds that happen to look similar. **Nightshade should have exactly one scene
description and one renderer.**

### 11.6 `hemlockc` codegen bug worth knowing about

A small typed helper used in an inlined arithmetic context can emit invalid C:

```
error: invalid operands to binary * (have 'HmlValue' and 'long long int')
  HmlValue _tmp164 = hml_val_i64(((s * 6364136223846793005LL) + 1442695040888963407LL));
```

Triggered by `fn lcg(s: i64): i64 { return s * BIG + BIG2; }` called in a loop. Workaround: avoid
big integer literals in small inlinable functions, or annotate `@noinline`. Also note the
interpreter **traps i32 overflow at runtime** (`Integer overflow: i32 multiplication`) — which is
why `texture.hml`'s `hash2` does its mixing in i64 with an explicit 32-bit mask. Any hash function
Nightshade writes (terrain noise, chunk seeds) must do the same.

---

## 12. Weakness list for shipping an FPS

Ordered by how much they threaten the project. Each entry: **Impact** → **Fix** → **File**.

---

### 12.1 No z-buffer on the GPU path; painter's sort with a comparison closure

**Impact.** Two separate problems wearing one coat.

*Correctness.* Centroid sorting is wrong for the geometry an FPS is made of. Long thin triangles
(a wall, a floor, a corridor ceiling) that interpolate through each other cannot be ordered by a
single centroid. Interpenetrating geometry — the standard case where a crate sits partly inside a
wall, a corpse clips the floor, a gun model overlaps the world — will flicker and swap as the
camera moves. The demo already shows a mild version of this on the crate's side faces.
It also forbids the first-person weapon model being drawn "always on top" without a hack, and
makes any translucent-then-opaque ordering fragile.

*Performance.* §10.3. 2.95 ms at 2 000 tris on lucky input, **107 ms** on depth-ordered input,
with a non-randomized Lomuto quicksort whose recursion depth is O(n) in exactly that case.

**Fix.** Three parts, all in `src/geom.hml`:

1. Replace `tris.sort(closure)` with an **O(n) bucket/counting sort over quantized view-space
   depth**, using flat parallel arrays (`depth[]`, `slot[]`, `count[]`) — measured at 0.275 ms
   for 2 000 triangles and immune to input order. Bucket on clip-space `w`, not NDC z.
2. Emit in **layers** rather than one global sort: opaque world (sorted coarse, back-to-front),
   then transparent/particles (sorted fine), then first-person weapon (own layer, drawn last),
   then HUD (never sorted). Layers cut n per sort and remove whole classes of ordering bugs.
3. Sort at **object/chunk granularity** where possible (sort 200 chunks, not 8 000 triangles),
   and keep per-chunk triangles in a fixed, authored order.

If painter artifacts on interpenetrating geometry prove unacceptable, the fallback is to author
the world so that it doesn't interpenetrate (BSP-ish convex cells, which is what the PS1 games
actually did) — not to add a depth buffer, which `SDL_Vertex` cannot express.

---

### 12.2 The CPU rasterizer cannot render a game

**Impact.** 8 fps at 320×240, compiled, with 560 triangles and nothing else happening. ~4.5
Mpixel/s fill rate. It is 2–3× short at the lowest resolution anyone would ship.

**Fix.** Do not fix. Formally designate the CPU path as **offline/test-only** and build Nightshade
exclusively on the GPU path. If the CPU path is kept for golden-image tests, one cheap
improvement is worth doing: change `fb.depth` from `array<f64>` (76 800 boxed values, ~1.2 MB) to
a raw `buffer` of f32 accessed with `ptr_write_f32` — the current depth buffer is both large and
cache-hostile. **Files: `src/raster.hml`, `src/framebuffer.hml`.**

---

### 12.3 Per-vertex object allocation churn

**Impact.** ~12 heap allocations per triangle, 24 000 per frame at 2 000 triangles. Directly
responsible for `emit = 10 ms`, i.e. 60 % of the frame budget. Proven recoverable: the identical
workload with zero intermediate objects runs in **1.8 ms** (§10.4).

**Fix.** Restructure the emit path as **structure-of-arrays over preallocated flat storage**:

* One per-frame `alloc`'d vertex arena; project directly into it with `ptr_write_f32`.
* Keep triangle metadata (`tex`, `depth`) in flat parallel arrays, not in `{...}` records.
* Hoist the 16 matrix elements into 16 local `f64` before the loop (`bench_flat.hml` does this;
  it lets `hemlockc` unbox the whole expression — see §14.1).
* Type-annotate every hot-path local and parameter (`x: f64`, `i: i32`).
* Provide fast paths that skip `clip.hml` entirely when all four `w > near` and all screen
  coordinates are inside the viewport — which is the overwhelming majority of triangles.
* Do **not** reach for `define` structs; measured at 223 ns, no better than object literals.

**Files: `src/geom.hml`, `src/scene_gpu.hml` (to be replaced by Nightshade's own renderer),
`src/clip.hml`.**

---

### 12.4 No frustum culling

**Impact.** Every triangle handed to the renderer pays full projection + near-clip + guard-band
cost even when it is directly behind the player. The guard band is ±2 screens = 31× the screen
area, so it culls almost nothing. In `bench_scale` at 32×32, 4 096 emitted quads' worth of
geometry becomes 2 000 triangles — half of them off-screen. For an *open world* this is fatal:
you cannot stream chunks if every loaded chunk costs full emit.

**Fix.** Three tiers, cheapest first:

1. **Chunk-level sphere/AABB vs. frustum.** Extract the 6 frustum planes from the MVP (Gribb–
   Hartmann, ~30 lines) and reject whole chunks with 6 dot products. This alone should cut emitted
   geometry 3–5× for a 90° FOV.
2. **Distance ring / draw distance** with a hard cutoff, paired with fog (§12.6) to hide it.
3. **Per-triangle backface cull** in the emit loop: after projection, `cross(b-a, c-a).z` sign
   test — one subtract-multiply-subtract per triangle, kills ~half the triangles of any closed
   mesh before they enter the sort. (Note this changes the sort's n, which matters a lot.)

**File: new `src/frustum.hml` + the emit loop.**

---

### 12.5 No fog

**Impact.** Without fog you cannot hide the draw-distance cutoff, so an "infinite" open world
either pops visibly or must render far more geometry than the budget allows. Fog is also the
single cheapest mood/art-direction lever in a PS1-aesthetic game — Silent Hill's entire look is
fog. And on this engine it is nearly free.

**Fix.** Per-vertex distance fog folded into the existing Gouraud vertex colour. In `to_screen`
you already have clip-space `w` (view depth). Compute
`f = clamp((w - fog_start) / (fog_end - fog_start), 0, 1)` and
`rgb = lerp(rgb * light, fog_rgb, f)` before packing the vertex. Cost: three lerps per vertex, no
extra allocations, no extra draw calls. Set the renderer clear colour to the fog colour so the
horizon matches.

Height fog and coloured fog volumes follow the same pattern (fog factor from `w` **and** world y).

**Files: `src/scene_gpu.hml` `to_screen`/`recolor`, or the new emit path.**

---

### 12.6 No billboards / particles

**Impact.** No muzzle flash, no impact sparks, no blood, no smoke, no tracers, no explosions, no
pickup sparkle, no rain, no dust motes, no floating damage numbers, no distant-tree impostors.
"Juice" in a CoD-like is 70 % particles. Also no impostors means every distant tree costs its full
triangle count.

**Fix.** Straightforward on this architecture — a billboard is just two screen-space triangles:
project the particle's world centre once, then emit a screen-aligned quad of size
`world_size * projection_scale / w`, with UVs from an atlas cell and a vertex colour for
tint/fade. Needs §12.7 (alpha) to look right. A particle system is then a flat SoA pool
(`px[], py[], pz[], vx[], vy[], vz[], life[], kind[]`) updated with scalar loops — no objects.

Budget note: at 2 tris/particle, 300 live particles = 600 triangles = 30 % of the current budget.
This is a strong argument for landing §12.3 first.

**File: new `src/billboard.hml` / `src/particles.hml`.**

---

### 12.7 No alpha blending

**Impact.** `put_vert` hardcodes vertex alpha to 255 and no blend mode is ever set, so nothing can
be transparent. That blocks particles, muzzle flashes, glass, water, foliage cutouts, crosshair
overlays, HUD fades, damage vignettes, screen flashes, fade-to-black transitions, and ghost/
preview building placement.

**Fix — and this one is *verified working***. `examples/probe_alpha.hml` proves the whole chain:

```hemlock
extern fn SDL_SetTextureBlendMode(tex: ptr, mode: i32): i32;     // returns 0 = OK
extern fn SDL_SetRenderDrawBlendMode(ren: ptr, mode: i32): i32;
// SDL_BLENDMODE_BLEND = 1, SDL_BLENDMODE_ADD = 2, SDL_BLENDMODE_MOD = 4
```

Measured result: a 50 %-alpha white triangle over a pure-blue clear produced exactly
`(127, 127, 253)` — correct source-over blending, headless, through `SDL_RenderGeometry`, for both
textured and untextured triangles. Additive blending (`SDL_BLENDMODE_ADD`) is what muzzle flashes
and sparks want.

Work required: add an `a` field to the geom vertex, write it in `put_vert`, set the blend mode on
textures at upload and on the renderer at init, and make sure alpha-blended triangles sort **after**
all opaque geometry (a separate layer per §12.1).

**Files: `src/sdl.hml` (two externs + a setter), `src/geom.hml` (`put_vert`, vertex shape).**

---

### 12.8 No 2D / HUD layer

**Impact.** No crosshair, health bar, ammo counter, minimap, compass, hit markers, kill feed,
objective markers, damage direction indicator, weapon wheel, inventory, pause menu, or title
screen. This is not a nice-to-have; a CoD-like *is* its HUD.

**Fix.** Trivially cheap on this architecture, because screen-space quads are already the native
currency. A HUD layer is:

* its own batch, **never depth-sorted** (draw order = insertion order),
* flushed after `batch_flush` of the world,
* coordinates in the logical 320×240 space that `SDL_RenderSetLogicalSize` already establishes,
* one texture atlas → typically **1 draw call for the entire HUD**.

Budget: a crosshair + health + ammo + minimap frame is ~30 quads = 60 triangles = 3 % of budget.

**File: new `src/hud.hml`.**

---

### 12.9 No text rendering

**Impact.** No score, no ammo numerals, no subtitles, no NPC dialogue (which the Animal-Crossing
warmth pillar absolutely requires), no menus, no debug overlay, no player names for multiplayer.

**Fix.** Bitmap font atlas + quad batch. Because there is no PNG *reader* (§12.10), the fastest
path is a **procedurally generated font**: encode a 5×7 or 8×8 glyph set as an array of bitmasks
in Hemlock source, blit it once at startup into a `tex_new()` atlas, upload, and then
`draw_text(x, y, str, tint)` emits 2 triangles per glyph into the HUD batch.

Budget caution: text is triangle-hungry. A 200-character screen = 400 triangles = 20 % of the
current budget, 5 % of the post-rewrite budget. Another reason §12.3 comes first. Mitigate by
pre-baking static strings into single quads where possible.

**File: new `src/font.hml`, consumed by `src/hud.hml`.**

---

### 12.10 No texture loading — no art pipeline

**Impact.** `png.hml` writes PNG and cannot read it. There is no image decoder anywhere in the
engine or in `@stdlib`. Today, *every texture must be generated by Hemlock code at startup*
(`tex_grass`, `tex_sky`, `tex_checker`). An artist cannot contribute a single pixel. That is
incompatible with "visually stunning."

**Fix.** Two options, in order of preference:

1. **Write a PNG reader.** `@stdlib/compression` exposes `inflate_decompress`, so the missing
   piece is only the IHDR/IDAT chunk walk and the five PNG row filters (~150 lines). This gives
   the project a normal art pipeline (Aseprite → PNG → engine).
2. **Ship a trivial binary format** (`magic, w, h, RGB bytes`) plus a `tools/png2wwt.py`
   converter. Faster to write, but adds a build step and loses direct artist iteration.

Do (1). It is a day of work and it unblocks all art.

**File: `src/png.hml` (add `read_png`), or new `src/image.hml`.**

---

### 12.11 No texture atlas → 47 draw calls for 389 triangles

**Impact.** Measured (§10.5). `batch_flush` merges only *consecutive* same-texture runs, and the
depth sort deliberately interleaves objects, so runs average ~8 triangles. Draw-call overhead is
per-call state validation in SDL plus a command-queue entry; at 47/frame it is survivable, but a
world with 20 materials will produce 200–400 calls/frame and become the bottleneck.

**Fix.** One (or a very small number of) atlas texture(s). Bake all world textures into a single
1024×1024 RGB atlas at startup, store per-material UV rects, and offset/scale mesh UVs into the
atlas at emit time. The whole opaque world then becomes **one** `SDL_RenderGeometry` call, and the
texture-run loop in `batch_flush` collapses to a no-op.

Watch out: nearest sampling + atlas means you must inset UVs by half a texel and pad each atlas
cell, or you will bleed neighbouring cells at grazing angles. There is no mip-mapping, so no
bleeding from minification — only from the affine warp.

**Files: new `src/atlas.hml`; `src/geom.hml` simplifies.**

---

### 12.12 No mouse look

**Impact.** `poll()` handles `SDL_QUIT` and `SDL_KEYDOWN` only. The examples turn the camera with
the **arrow keys**. There is no FPS without mouse look; this is not negotiable and it is not
subtle.

**Fix.** All of the required SDL is present in 2.0.18 (verified by symbol dump):

```hemlock
extern fn SDL_SetRelativeMouseMode(enabled: i32): i32;   // hides cursor, gives unbounded deltas
extern fn SDL_GetRelativeMouseState(x: ptr, y: ptr): u32;
extern fn SDL_ShowCursor(toggle: i32): i32;
```

Per frame: `SDL_GetRelativeMouseState(dx_ptr, dy_ptr)` → `yaw += dx * sens`,
`pitch -= dy * sens`, clamp pitch to ±(π/2 − ε). Also extend `poll()` to surface
`SDL_MOUSEBUTTONDOWN` (0x401) / `SDL_MOUSEBUTTONUP` (0x402) for fire/ADS, and `SDL_KEYUP` (0x301)
so the input layer can track press/release edges rather than only "held".

While you are in there: `SDL_MOUSEWHEEL` (0x403) for weapon switching.

**File: `src/sdl.hml`, plus a new `src/input.hml` that owns the action-mapping layer.**

---

### 12.13 No audio

**Impact.** No gunshots, no footsteps, no reload clicks, no hit confirmation, no ambience, no
music, no NPC voice blips. Gunfeel is at least half audio — the CoD reference point is
unachievable without it, and it is the cheapest juice per byte in the entire project.

**Fix.** SDL 2.0.18 has `SDL_OpenAudioDevice` and `SDL_QueueAudio` (verified present). The
lowest-friction design for this engine:

* Open one device: 22 050 Hz, `AUDIO_S16LSB`, 1 channel (period-appropriate and cheap).
* Keep sounds as raw PCM in `buffer`s (procedurally synthesized at startup, or loaded from a
  trivial header-less `.raw` — WAV parsing is ~40 lines if you want it).
* Software-mix N active voices into a small ring buffer each frame (a few hundred samples ×
  8 voices is a trivial scalar loop) and `SDL_QueueAudio` it.
* Distance attenuation + stereo pan from the listener basis you already have.

Caution: mixing is a per-sample CPU loop. At 22 kHz mono, one frame is 367 samples; 8 voices =
~3 000 multiply-adds/frame — negligible next to the 24 000 allocations we are removing. Do **not**
mix at 48 kHz stereo with 32 voices without measuring first.

**File: new `src/audio.hml`.**

---

### 12.14 No animation

**Impact.** Meshes are static vertex soup. No weapon idle sway, no recoil kick, no reload
animation, no muzzle-flash timing, no enemy walk cycles, no death animations, no doors, no NPC
gestures. A shooter whose gun does not move when it fires feels broken in the first two seconds.

**Fix.** In priority order, cheapest first — you can get 80 % of the *feel* without skinning:

1. **Procedural transform animation.** Weapon sway/bob/recoil is a matrix, evaluated per frame
   from a spring or a curve. Zero engine changes required beyond a per-object model matrix.
   Do this first; it is the highest juice-per-hour in the project.
2. **Rigid-part hierarchy.** Model characters as a handful of separately-transformed parts
   (torso/head/arms/legs), each its own mesh with its own matrix — precisely how PS1 games did it,
   and it is on-aesthetic. Needs OBJ groups (§9) or one file per part.
3. **Vertex morph (keyframe lerp).** Two poses + a t. Cheap, PS1-authentic, and much simpler than
   skinning. Cost is one lerp per vertex per frame.

Skeletal skinning is not worth it here.

**File: new `src/anim.hml`; the mesh renderer needs to accept a per-part model matrix.**

---

### 12.15 No collision

**Impact.** Nothing stops the player walking through the crate, the tree, or the ground. No
bullets can hit anything. No gravity, no jumping, no stairs, no doors. Everything an FPS *does*
lives here.

**Fix.** This belongs in Nightshade, not Wobbleweed, but the engine must expose what it needs:

* **Player vs. world:** with a chunked/voxel world (the Minecraft pillar), swept-AABB against
  voxel cells is the right answer — cheap, robust, no mesh collision needed.
* **Hitscan:** DDA voxel raycast for the world; ray-vs-AABB for entities. Both are scalar loops
  over flat arrays.
* **Entities:** AABB or capsule-vs-AABB. No general mesh collision, ever.
* Engine-side, add `v_dist`, `v_lerp`, ray/AABB/plane helpers to `src/vec.hml` (§4.1) and make
  sure the world representation is queryable *without* going through the renderer.

**Files: `src/vec.hml` (math primitives); everything else in Nightshade's `src/`.**

---

### 12.16 Hardcoded scene, no scene graph, no entities

**Impact.** `render_world` / `render_world_gpu` literally contain a `for` loop over a 16×16 ground
grid, five hand-written crate faces, and one tree at `(-5, 0, -3)`. There is no notion of an
object, an instance, a transform hierarchy, a material, a chunk, or a visibility set. Nothing can
be added, moved, or removed at runtime.

**Fix.** Nightshade must own its own renderer module; treat `scene.hml` / `scene_gpu.hml` as
*reference implementations to be deleted*. The shape that fits both the triangle budget and the
Minecraft pillar:

```
World  = grid of Chunks
Chunk  = { cx, cz, voxels, mesh_verts: buffer, mesh_tri_count, dirty: bool, aabb }
Entity = flat SoA arrays (pos, vel, yaw, kind, health, mesh_id, ...)
Frame  = frustum-cull chunks -> emit cached chunk meshes -> emit entities -> particles -> HUD
```

The key idea: **chunk meshes are built once into a preallocated vertex buffer and re-uploaded only
when dirty.** Per frame you then transform and pack cached geometry rather than rebuilding it —
which is what makes an open world affordable at these budgets.

**Files: all of `src/scene*.hml` replaced by Nightshade's `src/world.hml`, `src/chunk.hml`,
`src/render.hml`.**

---

### 12.17 Meshes cannot be textured

**Impact.** See §9. `mesh.uv` is parsed and thrown away; both renderers pass hardcoded UV (0,0).
Every OBJ is flat-shaded per material. No textured guns, props, characters, or decorations.

**Fix.** Two lines of plumbing, really: use `f.ta/tb/tc` to index `mesh.uv` in `render_mesh_gpu`
(falling back to (0,0) when `ta < 0`), and pass the mesh's atlas texture instead of `null`.
Then handle the atlas UV remap (§12.11).

**Files: `src/scene_gpu.hml` `render_mesh_gpu` (and `scene.hml` `render_mesh` if the CPU path is
kept for tests).**

---

### 12.18 Lighting is one hardcoded directional sun

**Impact.** `SUN` and `AMBIENT` are module-level constants in *both* scene files. No day/night, no
point lights, no muzzle-flash illumination, no torches, no coloured light, no per-object tint, no
emissive materials, no baked ambient occlusion. Everything is lit identically forever — which
directly undercuts both the "visually stunning" goal and the cozy-hub warmth pillar.

**Fix.** Per-vertex lighting is already the model; extend it rather than replace it.

* Make sun direction/colour/ambient **runtime state** on a lighting struct, animated for
  day/night. Free.
* Add **up to N point lights** evaluated per vertex: for each vertex, accumulate
  `atten(dist) * max(0, dot(n, L)) * colour` over the few nearest lights. Cost is N dot products
  per vertex; keep N ≤ 4 and cull lights per chunk.
* **Bake static lighting into chunk vertex colours** at mesh-build time — free at runtime, and
  the natural fit for the cached-chunk design in §12.16. Dynamic lights then only need to touch
  entities and nearby chunks.
* Muzzle flash = a single bright point light with a 2-frame life, plus an additive billboard.

**Files: new `src/light.hml`; the emit path consumes it.**

---

### 12.19 No frame-rate-independent timing

**Impact.** `walk.hml` and `walk_gpu.hml` move the camera by `move_speed` **per frame** and turn
by `turn_speed` **per frame**, with a fixed `delay(4)`. Movement speed is therefore a function of
frame rate. On this engine, where frame rate swings from 267 fps (empty view) to 25 fps (dense
view), the player would physically move 10× faster when looking at the sky. For multiplayer
(gn.hml) this is also a desync generator.

**Fix.** A proper loop: measure `dt` with `SDL_GetPerformanceCounter`/`SDL_GetPerformanceFrequency`
(both present in 2.0.18), clamp it (e.g. ≤ 100 ms) to survive hitches, run gameplay on a **fixed
timestep accumulator** (60 Hz), and render with interpolation. Also consider
`SDL_RENDERER_PRESENTVSYNC` instead of `delay(4)`.

**Files: `src/sdl.hml` (two externs), new `src/loop.hml`.**

---

### 12.20 Nothing is chunky where it should be; no render target

**Impact.** `SDL_RenderSetLogicalSize(ren, 320, 240)` makes SDL scale the *rasterization*, so GPU
triangles are drawn at full window resolution with smooth edges — only the magnified nearest
textures look retro. The signature PS1 look (chunky polygon *edges*, low-res everything) is
therefore only present in the CPU path, which we are not shipping. It also means there is nowhere
to hang a full-screen post-effect.

**Fix.** Render into an offscreen 320×240 target, then blit it to the window with NEAREST scaling:

```hemlock
extern fn SDL_SetRenderTarget(ren: ptr, tex: ptr): i32;
// SDL_TEXTUREACCESS_TARGET = 2
```
Create a 320×240 TARGET texture with NEAREST scale mode; set it as the target; render all
geometry; set target back to null; `SDL_RenderCopy` the whole thing to the window. This gets you
authentic chunky edges *and* a place to apply GPU-side post-processing (dither via an additive
overlay quad, vignette, damage flash, fade-to-black — all as blended full-screen quads).

**File: `src/sdl.hml` + a new `src/target.hml`.**

---

### 12.21 The mesh renderer is O(faces) in normal transforms every frame

**Impact.** §9. `render_mesh_gpu` does three `v_norm(mat_apply_dir(model, ...))` per **face**, per
frame, plus `recolor` per vertex. Shared vertices are recomputed once per incident face — roughly
6× redundant on a closed mesh. 50 tree instances ≈ 4 800 normalizes and ~10 000 allocations per
frame for lighting that never changes.

**Fix.** Precompute per-vertex lit colours whenever the model matrix or the light changes (for
static props: once, at load) and cache them on the mesh. For an instance whose rotation is
yaw-only, transform the light *into model space* once per instance instead of transforming every
normal into world space — one matrix op per instance instead of 3N.

**File: `src/scene_gpu.hml` `render_mesh_gpu` → Nightshade's mesh renderer.**

---

### 12.22 No far-plane clip; no LOD; no impostors

**Impact.** `clip_tri_near` only clips near. Geometry beyond `far = 200` still projects (NDC
z > 1) and is still emitted and sorted on the GPU path. There is no LOD system and no impostor
system, so a distant tree costs exactly as much as a near one.

**Fix.** Distance-bucket the chunk emit: full mesh inside ring 0, decimated mesh in ring 1,
single billboard impostor in ring 2, nothing beyond. Pair with fog (§12.5) so the transitions are
invisible. The far-plane clip itself is cheap to add to `clip_tri_near` (test `w - far` as a second
plane) but a chunk-level distance cull makes it mostly unnecessary.

**Files: `src/clip.hml`, plus Nightshade's chunk emitter.**

---

### 12.23 No spatial audio / listener, no camera shake, no screen effects

**Impact.** Grouped because they are all "juice" systems that do not exist and that the CoD pillar
demands: recoil camera kick, hit-flash, low-health vignette, explosion screen shake, hitmarker
ping, slow-motion on the last kill.

**Fix.** All of these are trivial once §12.7 (alpha), §12.8 (HUD layer) and §12.20 (render target)
exist. Camera shake is an offset applied to the view matrix — no engine change at all. Budget an
explicit "juice" milestone after the renderer rewrite; do not let it slip, it is what makes the
difference between "a tech demo" and "addictive."

---

### 12.24 No engine lifecycle, no error handling, no asset manager

**Impact.** `window_open` returns `null` on failure and every example just prints and returns.
There is no shutdown ordering (the examples leak the uploaded `SDL_Texture`s — `window_close`
destroys only `w.tex`), no asset registry, no hot-reload, no config, no save/load. `alloc`'d
buffers (`b.buf`, `w.ev`) are never freed.

**Fix.** A thin `src/engine.hml` owning init → run(loop) → shutdown, a texture/mesh registry
keyed by name, and a `SDL_DestroyTexture` sweep on shutdown. Low urgency, high tidiness value once
more than one person is editing.

---

### 12.25 The README overstates the engine's guarantees

**Impact.** The README claims "byte-identical output ... in the interpreter and compiled" and
"feature-complete for v1." Both are misleading given §11.1 and §11.2, and a team member trusting
them will lose a day. Not a code bug, but a real project risk.

**Fix.** Update `README.md` when the fixes land; until then, treat this document as the source of
truth.

---

## 13. Recommended work order for Nightshade

The dependencies between the weaknesses matter more than their individual severity. This order
front-loads the things that change the *budget*, because every later decision depends on whether
the budget is 2 000 or 8 000 triangles.

**Phase 0 — correctness (half a day)**
1. Fix the shared vertex-buffer bug (§11.1) — one frame arena, per-run offsets. Verified fix
   already exists in `repro_batchbuf_fix.hml`.
2. Enforce `batch_new`'s cap (§11.3).
3. Adopt compiled-only as the workflow; add a golden-image test that compiles first (§11.2).

**Phase 1 — the budget rewrite (the highest-leverage work in the project)**
4. Replace the comparison sort with a bucket sort on view-space depth (§12.1). *2.95 ms → 0.28 ms,
   and removes a 107 ms cliff.*
5. Rewrite emit as SoA/flat with hoisted matrix scalars and typed locals (§12.3). *10 ms → 1.8 ms.*
6. Add frustum culling at chunk granularity + backface culling per triangle (§12.4).
7. **Re-measure.** Expect ~8 000 triangles at 60 fps. Every subsequent design decision keys off
   this number.

**Phase 2 — make it a game engine**
8. Mouse look + full input layer + fixed-timestep loop with real `dt` (§12.12, §12.19).
9. Alpha blending (§12.7) — already proven to work.
10. HUD layer + bitmap font (§12.8, §12.9).
11. Texture atlas (§12.11) and PNG reader (§12.10) — unblocks all art.
12. Fog (§12.5) — cheapest visual-quality win available, and it enables draw-distance culling.

**Phase 3 — make it fun**
13. Offscreen render target for true chunky pixels + full-screen effects (§12.20).
14. Billboards + particle pool (§12.6).
15. Audio (§12.13).
16. Procedural weapon animation, recoil, camera shake (§12.14, §12.23).
17. Collision + hitscan (§12.15).

**Phase 4 — the world**
18. Chunked world with cached chunk meshes and baked vertex lighting (§12.16, §12.18).
19. LOD rings + impostors (§12.22).
20. Textured meshes (§12.17), mesh normal caching (§12.21).

gn.hml multiplayer layers cleanly on top of this **provided** step 8 lands the fixed-timestep
simulation and the world is authoritative flat SoA state (§12.16) rather than the renderer's
private data. Design for that from Phase 1; retrofitting it later is expensive.

---

## 14. Appendix — Hemlock-level gotchas that bite the renderer

**14.1 Type annotations are a performance feature, not documentation.** `hemlockc` unboxes
arithmetic only when it can prove the types. Untyped parameters (`fn v_add(a, b)`) and untyped
locals fall back to boxed `HmlValue` dispatch. Annotate every hot-path local, parameter and return
(`x: f64`, `i: i32`). Hoisting `m[0]`…`m[15]` into 16 typed locals before a loop is worth several
milliseconds (this is a large part of why `bench_flat.hml` is 5.5× faster).

**14.2 `/` on two integers yields f64.** Verified: `5/2 == 2.5`. So `y / (h - 1)` is a true float
ratio, and `divi()` from `@stdlib/math` is the integer division. This is the opposite of C and it
is easy to misread.

**14.3 i32 overflow traps at runtime in the interpreter.** `Integer overflow: i32 multiplication`
is a thrown exception, not a wrap. Any hash/noise function must do its mixing in `i64` with an
explicit `& 0xFFFFFFFF` mask, exactly as `texture.hml`'s `hash2` does. Terrain/chunk seeding code
will hit this immediately if written naively.

**14.4 `array.sort` is a different algorithm in each backend.** Compiled: non-randomized Lomuto
quicksort (O(n²) and O(n) recursion depth on sorted input). Interpreted: stable insertion sort
(O(n²) always). Never put `sort` with a closure in a per-frame path — see §10.3.

**14.5 `define` structs are not value types.** Measured identical to object literals (223 ns vs
213 ns for 7 fields). They exist for FFI layout. If you want cheap aggregates, use flat arrays or
raw `alloc` memory.

**14.6 Reference counting, not tracing GC.** Steady-state throughput suffers from churn, but there
are no collection pauses. Frame times will be smooth and predictable once allocation volume drops.

**14.7 Allocation costs, for budgeting:** 7-field object 216 ns, 3-field object 102 ns,
3-element array 46 ns, flat-array write 13 ns, `ptr_write_f32` 16 ns. Roughly: **one object
allocation costs as much as 15 flat writes.**

**14.8 `hemlockc` can emit invalid C** for some typed helpers in inlined arithmetic contexts
(§11.6). If the C compiler errors with `invalid operands to binary * (have 'HmlValue' and ...)`,
restructure the helper or mark it `@noinline`.

**14.9 Compile time is 3.3 s** for the whole engine plus an example. Budget for it in the inner
loop; it is fast enough that compiled-only development is practical.

**14.10 SDL is 2.0.18 and has everything we need** — verified by symbol dump:
`SDL_SetRelativeMouseMode`, `SDL_GetRelativeMouseState`, `SDL_SetTextureBlendMode`,
`SDL_SetTextureAlphaMod`, `SDL_OpenAudioDevice`, `SDL_QueueAudio`, `SDL_GetPerformanceCounter`,
`SDL_RenderGeometryRaw`, `SDL_SetRenderTarget`, `SDL_SetHint`. Nothing in §12 is blocked by the
platform. `SDL_RenderGeometryRaw` in particular takes separate strided `xy` / `color` / `uv`
arrays and an index buffer — a perfect match for a structure-of-arrays emit path, and indexed
drawing would cut per-vertex packing work roughly threefold on shared-vertex meshes. Worth
evaluating in Phase 1.
