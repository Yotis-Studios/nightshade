# Nightshade — SDL2 FFI Reference (source of truth)

**Author:** sdl-ffi recon
**Date:** 2026-07-27
**Status:** All signatures, offsets and constants below are **verified**, not guessed.
Everything risky was executed from Hemlock — interpreted *and* compiled with `hemlockc`,
headless *and* on a real GPU.

---

## 0. TL;DR for the implementation team

| Question | Answer |
|---|---|
| Does mouse look work through Hemlock FFI? | **Yes.** `SDL_SetRelativeMouseMode` returns 0 on real X11 and live `xrel`/`yrel` arrive at event offsets **28/32**. Proven with real pointer motion. |
| Render targets? | **Yes.** `SDL_TEXTUREACCESS_TARGET` + `SDL_SetRenderTarget` works, *including* `SDL_RenderGeometry` drawing into the target. |
| Blending / alpha? | **Yes.** All of `SDL_BLENDMODE_*`, `SetTextureAlphaMod`, `SetTextureColorMod` verified numerically by pixel readback. |
| `SDL_RenderCopyEx` rotation? | **Yes** — but `angle` is C `double`, so the Hemlock type **must** be `f64` and you must pass `0.0`, never `0`. |
| Audio? | **Use `SDL_QueueAudio`.** No FFI callbacks needed. **SDL2_mixer is NOT installed on this machine** — do not depend on it. |
| 32-bit pixel format? | **`SDL_PIXELFORMAT_RGBA32` = 376840196.** On little-endian it is `ABGR8888`, whose *byte order in memory* is R,G,B,A. Verified by readback. |
| Extra runtime deps? | **None.** `libSDL2-2.0.so.0` only. |
| Biggest gotcha? | `extern fn` binds to the **most recently declared `import`**. See §8.1. |

Drop-in bindings module: **`docs/recon/sdl2_reference.hml`** (compiles, imports, and drives a
full frame loop — verified by `tools/probes/probe_module.hml`).

---

## 1. The environment, and how these numbers were obtained

### 1.1 What is actually installed

```
/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 -> libSDL2-2.0.so.0.18.2
```

> **The `.0.18.2` in the filename is libtool versioning, NOT the SDL release.**
> `SDL_GetVersion()` at runtime reports **2.0.20**. Confirmed by executing it.

**There are no SDL2 development headers on this machine** — `/usr/include/SDL2/` does not
exist, `sdl2-config` is absent, and `pkg-config sdl2` fails. So the headers were fetched:

```bash
apt-get download libsdl2-dev            # 2.0.20+dfsg-2ubuntu1.22.04.1
dpkg-deb -x libsdl2-dev_*.deb /tmp/sdl2dev/
# headers land in /tmp/sdl2dev/usr/include/SDL2/
# plus /tmp/sdl2dev/usr/include/x86_64-linux-gnu/SDL2/_real_SDL_config.h
```

The header version (2.0.20) **exactly matches** the runtime version reported by
`SDL_GetVersion()`, so every offset below describes the library we actually link against.

> Do **not** use the SDL headers under `~/Projects/emsdk/.../fakesdl/`. Those are
> emscripten's wasm32 port: pointers are 4 bytes there, so every struct offset past the
> first pointer field is wrong for x86-64.

### 1.2 Provenance of every number in this document

`tools/probes/sdl_abi_dump.c` includes the real `SDL.h`, prints `offsetof`/`sizeof` for
every struct and the value of every constant, and additionally calls `SDL_GetVersion()` to
assert the loaded library matches. Its full output is committed at
**`docs/recon/sdl_abi_dump.txt`** (351 lines). Regenerate with:

```bash
gcc -I/tmp/sdl2dev/usr/include/SDL2 -I/tmp/sdl2dev/usr/include \
    -I/tmp/sdl2dev/usr/include/x86_64-linux-gnu \
    -o sdl_abi_dump tools/probes/sdl_abi_dump.c -l:libSDL2-2.0.so.0
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ./sdl_abi_dump
```

Nothing in this document came from memory or from the internet.

### 1.3 Available libraries — the SDL2_mixer question, settled

```
/usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0        <- present (the only one)
/usr/lib/x86_64-linux-gnu/libSDL2_mixer*          <- DOES NOT EXIST
/usr/lib/x86_64-linux-gnu/libSDL2_image*          <- DOES NOT EXIST
/usr/lib/x86_64-linux-gnu/libSDL2_ttf*            <- DOES NOT EXIST
```

`ldconfig -p | grep -i sdl` lists **only** `libSDL2-2.0.so.0` (and ancient SDL 1.2).
SDL2_mixer copies exist *inside Steam's runtime sandboxes*
(`~/.local/share/Steam/.../libSDL2_mixer-2.0.so.0`) but those are not on the loader path
and must not be used — they are ABI-pinned to Steam's own runtime.

`apt-cache policy libsdl2-mixer-2.0-0` → installable (2.0.4), but that would add a
root-install step and a shipping dependency. **Recommendation: do not use SDL2_mixer.**
See §6.

---

## 2. Mouse look

### 2.1 Signatures

```hemlock
extern fn SDL_SetRelativeMouseMode(enabled: i32): i32;   // 0 on success, -1 on failure
extern fn SDL_GetRelativeMouseMode(): i32;               // SDL_bool: 1 = on
extern fn SDL_GetRelativeMouseState(x: ptr, y: ptr): u32; // returns button bitmask
extern fn SDL_GetMouseState(x: ptr, y: ptr): u32;
extern fn SDL_WarpMouseInWindow(win: ptr, x: i32, y: i32): void;
extern fn SDL_ShowCursor(toggle: i32): i32;              // 1 enable, 0 disable, -1 query
extern fn SDL_CaptureMouse(enabled: i32): i32;
```

`SDL_GetRelativeMouseState` takes **two `int*` out-params**; allocate 4 bytes each and read
with `ptr_deref_i32`. Verified that both are written.

### 2.2 `SDL_MOUSEMOTION` byte layout

`SDL_Event` is **56 bytes**. Over-allocating is harmless; under-allocating corrupts the stack.

| Field | Offset | Type |
|---|---|---|
| `type` | 0 | `u32` |
| `timestamp` | 4 | `u32` |
| `windowID` | 8 | `u32` |
| `which` | 12 | `u32` |
| `state` (button mask) | 16 | `u32` |
| `x` | 20 | `i32` |
| `y` | 24 | `i32` |
| **`xrel`** | **28** | **`i32`** |
| **`yrel`** | **32** | **`i32`** |

`sizeof(SDL_MouseMotionEvent)` = 36.

### 2.3 `SDL_MOUSEBUTTONDOWN` / `SDL_MOUSEBUTTONUP` layout

| Field | Offset | Type |
|---|---|---|
| `type` | 0 | `u32` |
| `windowID` | 8 | `u32` |
| `which` | 12 | `u32` |
| **`button`** | **16** | **`u8`** |
| `state` | 17 | `u8` (1 = `SDL_PRESSED`) |
| `clicks` | 18 | `u8` (2 = double-click) |
| `x` | 20 | `i32` |
| `y` | 24 | `i32` |

`sizeof(SDL_MouseButtonEvent)` = 28.

### 2.4 `SDL_MOUSEWHEEL` layout (scroll = weapon switching)

| Field | Offset | Type |
|---|---|---|
| `x` | 16 | `i32` |
| `y` | 20 | `i32` (positive = away from user) |
| `direction` | 24 | `u32` (1 = `FLIPPED`, multiply x/y by -1) |
| `preciseX` | 28 | `f32` (2.0.18+) |
| `preciseY` | 32 | `f32` |

### 2.5 Constants

```
SDL_MOUSEMOTION       1024   (0x400)
SDL_MOUSEBUTTONDOWN   1025   (0x401)
SDL_MOUSEBUTTONUP     1026   (0x402)
SDL_MOUSEWHEEL        1027   (0x403)

SDL_BUTTON_LEFT   1     SDL_BUTTON_LMASK   1
SDL_BUTTON_MIDDLE 2     SDL_BUTTON_MMASK   2
SDL_BUTTON_RIGHT  3     SDL_BUTTON_RMASK   4
SDL_BUTTON_X1     4     SDL_BUTTON_X1MASK  8
SDL_BUTTON_X2     5     SDL_BUTTON_X2MASK 16

SDL_PRESSED 1   SDL_RELEASED 0
SDL_ENABLE  1   SDL_DISABLE  0   SDL_QUERY -1
SDL_MOUSEWHEEL_NORMAL 0   SDL_MOUSEWHEEL_FLIPPED 1
```

Note `SDL_BUTTON_RIGHT` is **3** but its mask is **4** (`1 << (3-1)`). The mask is what
`SDL_GetRelativeMouseState`/`SDL_GetMouseState` return; the index is what
`event.button.button` holds. Do not mix them up — this is the single most common SDL bug.

### 2.6 VERIFIED — what actually happened when we ran it

**Real X11 display (`DISPLAY=:0`), interpreted and compiled:**

```
PASS  SDL_SetRelativeMouseMode(1)  rc=0 GetRelativeMouseMode=1  *** MOUSE LOOK WORKS ***
PASS  SDL_SetRelativeMouseMode(0) restores  cursor released
PASS  SDL_ShowCursor(QUERY/DISABLE/ENABLE)  initial=1 after_disable=0
```

**Live relative motion** (`tools/probes/probe_mouselook.hml`). Because
`SDL_WarpMouseInWindow` deliberately produces `xrel == 0` (SDL updates its own cached
pointer position as part of the warp, so warps never feed back into relative motion), the
probe moves the pointer **behind SDL's back** using `XTestFakeMotionEvent` from
`libXtst.so.6`. SDL then treats it as genuine hardware motion:

```
SDL_SetRelativeMouseMode(1) rc=0 mode=1 err=''
motion events=8  sum_xrel=3136  sum_yrel=2996  max_xrel=484
PASS  LIVE xrel/yrel delivered at offsets 28/32 in relative mode -- MOUSE LOOK IS REAL
SDL_GetRelativeMouseState after live move: dx=700 dy=500
```

Identical result from the `hemlockc`-compiled binary. **Mouse look is not a risk.**

Additionally, a byte-level cross-check (`scratchpad/bytecheck.c`) built a motion event
through SDL's *own* union and confirmed the raw bytes:

```
sizeof(SDL_Event)=56
bytes@20 = 130 (want 130)      bytes@28 = 1234567  (want 1234567)
bytes@24 = 145 (want 145)      bytes@32 = -7654321 (want -7654321)
button byte@16 = 3   state byte@17 = 1   clicks byte@18 = 2
```

### 2.7 ⚠ Headless limitation (report honestly)

Under `SDL_VIDEODRIVER=dummy`:

```
NOTE  SDL_SetRelativeMouseMode(1) under dummy driver
      rc=-1 err='No relative mode implementation available'
```

The `SDL_MOUSE_RELATIVE_MODE_WARP=1` hint **does not rescue it** (`rc=-1` as well). This is
an **environment** limitation of the dummy video driver, *not* an FFI or Hemlock problem —
the same code returns 0 on X11. Consequence: **mouse-look cannot be covered by headless CI.**
Gate it behind a real display, or stub the look-input source in tests.

### 2.8 Recommended usage pattern

```hemlock
// on entering gameplay
SDL_SetRelativeMouseMode(1);      // hides + grabs the cursor; deltas keep flowing
// on opening a menu / losing focus
SDL_SetRelativeMouseMode(0);
```

Prefer draining `SDL_MOUSEMOTION` events and **accumulating `xrel`/`yrel`** over calling
`SDL_GetRelativeMouseState` — the event path preserves sub-frame motion when multiple
motion events land in one frame, which matters for smooth aim at low frame rates.
`SDL_SetRelativeMouseMode` already hides the cursor, so a separate `SDL_ShowCursor(0)` is
redundant (harmless).

---

## 3. Alpha / blending

### 3.1 Signatures

```hemlock
extern fn SDL_SetTextureBlendMode(tex: ptr, mode: i32): i32;
extern fn SDL_SetTextureAlphaMod(tex: ptr, alpha: i32): i32;   // 0..255
extern fn SDL_SetTextureColorMod(tex: ptr, r: i32, g: i32, b: i32): i32;
extern fn SDL_SetRenderDrawBlendMode(ren: ptr, mode: i32): i32;
extern fn SDL_SetRenderDrawColor(ren: ptr, r: i32, g: i32, b: i32, a: i32): i32;
extern fn SDL_RenderFillRect(ren: ptr, rect: ptr): i32;
extern fn SDL_RenderFillRects(ren: ptr, rects: ptr, count: i32): i32;
extern fn SDL_RenderDrawRect(ren: ptr, rect: ptr): i32;
extern fn SDL_RenderDrawLine(ren: ptr, x1: i32, y1: i32, x2: i32, y2: i32): i32;
extern fn SDL_ComposeCustomBlendMode(srcColor: i32, dstColor: i32, colorOp: i32,
                                     srcAlpha: i32, dstAlpha: i32, alphaOp: i32): i32;
```

`SDL_BlendMode` is a 4-byte C enum → `i32`. Alpha/color mod arguments are `Uint8` but
promote fine as `i32` through libffi.

### 3.2 Blend mode constants

```
SDL_BLENDMODE_NONE     0    dst = src                    (opaque)
SDL_BLENDMODE_BLEND    1    dst = src*a + dst*(1-a)      (HUD, fades, decals)
SDL_BLENDMODE_ADD      2    dst = src*a + dst            (muzzle flash, tracers, fire)
SDL_BLENDMODE_MOD      4    dst = src * dst              (fog, shadow, tinting)
SDL_BLENDMODE_MUL      8    dst = src*dst + dst*(1-a)
SDL_BLENDMODE_INVALID  2147483647
```

Custom blend factors/ops (for `SDL_ComposeCustomBlendMode`, if an exotic post-fx is ever
needed):

```
SDL_BLENDFACTOR_ZERO 1  ONE 2  SRC_COLOR 3  ONE_MINUS_SRC_COLOR 4  SRC_ALPHA 5
SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA 6  DST_COLOR 7  ONE_MINUS_DST_COLOR 8
SDL_BLENDFACTOR_DST_ALPHA 9  ONE_MINUS_DST_ALPHA 10
SDL_BLENDOPERATION_ADD 1  SUBTRACT 2  REV_SUBTRACT 3  MINIMUM 4  MAXIMUM 5
```

### 3.3 `SDL_Rect` layout

**16 bytes**, four `i32` in order `x, y, w, h` (offsets 0, 4, 8, 12).
`SDL_FRect` is also 16 bytes (four `f32`). `SDL_Point` / `SDL_FPoint` are 8 bytes.
`SDL_Color` is 4 bytes, `r,g,b,a` at 0,1,2,3.

```hemlock
fn rect(x: i32, y: i32, w: i32, h: i32): ptr {
    let r = alloc(16);
    ptr_write_i32(r, x);
    ptr_write_i32(ptr_offset(r, 1, 4), y);
    ptr_write_i32(ptr_offset(r, 2, 4), w);
    ptr_write_i32(ptr_offset(r, 3, 4), h);
    return r;
}
```

> **Performance note:** do not `alloc()` a rect per draw call in the frame loop. Allocate
> the handful of rects you need once and mutate them with `rect_set()` (provided in
> `sdl2_reference.hml`). At a 2000–3000 tri/frame budget, per-call allocation is real cost.

### 3.4 VERIFIED — numeric pixel-readback results

Every blend test renders and then reads the framebuffer back with
`SDL_RenderReadPixels`. These are measured bytes, not "it didn't crash":

```
PASS  RenderFillRect                        inside=(10,200,30) outside=(0,0,0)
PASS  RenderDrawRect outline                border=255 interior=0
PASS  SetRenderDrawBlendMode(BLEND)         red@a=128 over black -> r=128   (exact)
PASS  SetRenderDrawBlendMode(ADD)           40 + 60 -> r=100                (exact)
PASS  SetTextureAlphaMod + BLEND            (255,128,0)@a=128 -> (128,64,0) (exact)
PASS  SetTextureColorMod                    colormod(0,255,255) -> (0,128,0)(exact)
```

Identical results interpreted, compiled, under the dummy/software renderer, and on the
real accelerated GPU renderer.

---

## 4. Render targets

### 4.1 Signatures

```hemlock
extern fn SDL_CreateTexture(ren: ptr, format: u32, access: i32, w: i32, h: i32): ptr;
extern fn SDL_SetRenderTarget(ren: ptr, tex: ptr): i32;   // pass null to restore backbuffer
extern fn SDL_GetRenderTarget(ren: ptr): ptr;
extern fn SDL_RenderCopyEx(ren: ptr, tex: ptr, src: ptr, dst: ptr,
                           angle: f64, center: ptr, flip: i32): i32;
```

```
SDL_TEXTUREACCESS_STATIC     0
SDL_TEXTUREACCESS_STREAMING  1
SDL_TEXTUREACCESS_TARGET     2     <- required for render targets
SDL_RENDERER_TARGETTEXTURE   8     <- renderer flag advertising support

SDL_FLIP_NONE 0   SDL_FLIP_HORIZONTAL 1   SDL_FLIP_VERTICAL 2
SDL_ScaleModeNearest 0   SDL_ScaleModeLinear 1   SDL_ScaleModeBest 2
```

### 4.2 ⚠ `SDL_RenderCopyEx` — the `angle` argument is `f64`

The C prototype is:

```c
int SDL_RenderCopyEx(SDL_Renderer*, SDL_Texture*, const SDL_Rect* src,
                     const SDL_Rect* dst, const double angle,
                     const SDL_Point* center, const SDL_RendererFlip flip);
```

`angle` is a **`double`**. Declare it `f64` and **always pass a float literal**:

```hemlock
SDL_RenderCopyEx(ren, tex, null, dst, 0.0, null, SDL_FLIP_NONE);   // correct
SDL_RenderCopyEx(ren, tex, null, dst, 0,   null, SDL_FLIP_NONE);   // WRONG — do not
```

`center` is an `SDL_Point*` (8 bytes, two `i32`); `null` means "rotate about the centre of
`dst`". Angle is **degrees, clockwise**.

### 4.3 VERIFIED — render targets work everywhere

```
PASS  CreateTexture(TARGET)                       non-null
PASS  SetRenderTarget + draw into it              green@(40,40)=255 blue@(5,5)=255
PASS  SetRenderTarget(null) + RenderCopy(target)  green@(40,40)=255 blue@(5,5)=255
PASS  target texture + AlphaMod (overlay path)    green expected ~64 got 64
PASS  RenderCopyEx FLIP_HORIZONTAL                unflipped_left_red=255 flipped_left_blue=255
PASS  RenderCopyEx rotation (f64 angle marshals)  top=(255,0,0) bottom=(0,0,255)
PASS  RenderCopyEx with explicit center SDL_Point rc=0
```

`SDL_RenderReadPixels` reads **the currently bound target**, which is how the probe
verified the off-screen contents directly.

### 4.4 VERIFIED — the full Nightshade frame pipeline

`tools/probes/probe_pipeline.hml` composes everything at once, because each feature passing
in isolation does not prove the *combination* works:

1. `SDL_RenderGeometry` → into a **320×180 TARGET** texture (the PS1 internal-res buffer)
2. `SDL_SetRenderTarget(ren, null)` → back to the backbuffer
3. `SDL_RenderCopyEx` the target upscaled to 640×360 with a **screen-shake offset**, nearest-neighbour
4. additive full-screen **muzzle flash**
5. alpha-blended **HUD bar**

```
PASS  create 320x180 TARGET (internal res buffer)
PASS  SDL_RenderGeometry INTO a render target      tri_center_green=220 sky_corner_blue=40
PASS  upscale target to window with screen-shake   left_gap_green=0 body_green=220
PASS  additive muzzle-flash over composited frame  r=60 g=250 (220+30, exact)
PASS  alpha-blended HUD bar over the frame         above=250 inside=24
PIPELINE PROBE: 5 passed, 0 failed
```

Passed identically: interpreted/dummy, compiled/dummy, **and compiled on the real GPU**.
**This is the recommended architecture and it is proven end to end.**

The 320×180 internal target is also what makes the triangle budget affordable: rasterization
cost scales with the low-res target, and the upscale is a single textured quad.

---

## 5. Pixel formats

### 5.1 Values (all little-endian x86-64; `SDL_BYTEORDER == SDL_LIL_ENDIAN` confirmed)

| Constant | Value | **Byte order in memory** |
|---|---:|---|
| `SDL_PIXELFORMAT_RGB24` | 386930691 | R, G, B (3 bytes/px) |
| `SDL_PIXELFORMAT_BGR24` | 390076419 | B, G, R |
| **`SDL_PIXELFORMAT_RGBA32`** | **376840196** | **R, G, B, A** ← use this |
| `SDL_PIXELFORMAT_ARGB32` | 377888772 | A, R, G, B |
| `SDL_PIXELFORMAT_ABGR32` | 373694468 | A, B, G, R |
| `SDL_PIXELFORMAT_BGRA32` | 372645892 | B, G, R, A |
| `SDL_PIXELFORMAT_ARGB8888` | 372645892 | B, G, R, A *(little-endian!)* |
| `SDL_PIXELFORMAT_RGBA8888` | 373694468 | A, B, G, R *(little-endian!)* |
| `SDL_PIXELFORMAT_ABGR8888` | 376840196 | R, G, B, A |
| `SDL_PIXELFORMAT_RGB888` / `XRGB8888` | 370546692 | B, G, R, X |
| `SDL_PIXELFORMAT_RGB565` | 353701890 | packed 16-bit |

### 5.2 ⚠ The `8888` names are packed-integer names, NOT byte order

This is the trap. `SDL_PIXELFORMAT_ARGB8888` describes a **32-bit integer** laid out
`0xAARRGGBB`. On little-endian that integer's *bytes* land in memory as **B, G, R, A**.

The `*32` aliases exist precisely to remove this ambiguity — they are defined per-endianness
so that the name always describes **byte order**:

```
SDL_PIXELFORMAT_RGBA32 == SDL_PIXELFORMAT_ABGR8888   (verified: "RGBA32 == ABGR8888 ? YES")
```

**Answer to "which one gives correct byte order on little-endian":**
use **`SDL_PIXELFORMAT_RGBA32` (376840196)** whenever you have an array of bytes ordered
R,G,B,A. It is endian-correct by construction and will still be right if this ever builds
on a big-endian target.

**Verified by readback**, not by reading the header:

```
PASS  PIXELFORMAT_RGBA32 byte order = R,G,B,A
      wrote bytes [255,128,0,255] -> rendered pixel (255,128,0)
```

Wobbleweed's existing 24-bit CPU framebuffer path should keep using
`SDL_PIXELFORMAT_RGB24` (386930691) — it maps 1:1 to `w*h*3` RGB bytes with no conversion,
which is why the current engine uses it.

---

## 6. Audio — **recommendation: `SDL_QueueAudio`**

### 6.1 The two options, evaluated

**(a) SDL2_mixer — REJECTED.**
Not installed (§1.3). Would require `apt install libsdl2-mixer-2.0-0` (root) and add a
shipping dependency. Its "play a sound, it just works" API is genuinely convenient, but it
buys nothing we cannot do in ~60 lines, and its channel model is less flexible than mixing
ourselves. Also note the packaged version here is 2.0.4 — old.

**(b) `SDL_OpenAudioDevice` + hand-written callback — REJECTED.**
It *would* work: Hemlock FFI supports libffi closures via `callback()`. But SDL invokes the
audio callback on **its own audio thread**, so every SFX would re-enter the Hemlock runtime
from a non-Hemlock thread, on a hard real-time deadline. The FFI docs explicitly warn that
callback invocations are serialized behind a mutex and that exceptions cannot propagate.
A missed deadline is an audible click. **Not worth the risk.**

**(c) ✅ `SDL_QueueAudio` — RECOMMENDED, and verified working.**
Set `desired.callback = NULL` and the device runs in *queue mode*. The game pushes mixed
PCM from the main thread once per frame. **Zero FFI callbacks, zero threading concerns,
zero extra dependencies.**

Because a queue is a single stream, overlapping sounds must be mixed by us — that is what
`SDL_MixAudioFormat` is for, and it is verified working (§6.4).

### 6.2 Signatures

```hemlock
extern fn SDL_OpenAudioDevice(device: ptr, iscapture: i32, desired: ptr,
                              obtained: ptr, allowed_changes: i32): u32;
extern fn SDL_CloseAudioDevice(dev: u32): void;
extern fn SDL_PauseAudioDevice(dev: u32, pause_on: i32): void;   // 0 = PLAY
extern fn SDL_QueueAudio(dev: u32, data: ptr, len: u32): i32;
extern fn SDL_GetQueuedAudioSize(dev: u32): u32;                 // bytes still pending
extern fn SDL_ClearQueuedAudio(dev: u32): void;
extern fn SDL_MixAudioFormat(dst: ptr, src: ptr, format: u16, len: u32, volume: i32): void;

extern fn SDL_RWFromFile(file: string, mode: string): ptr;
extern fn SDL_LoadWAV_RW(src: ptr, freesrc: i32, spec: ptr, buf: ptr, len: ptr): ptr;
extern fn SDL_FreeWAV(audio_buf: ptr): void;
extern fn SDL_BuildAudioCVT(cvt: ptr, src_format: u16, src_channels: u8, src_rate: i32,
                            dst_format: u16, dst_channels: u8, dst_rate: i32): i32;
extern fn SDL_ConvertAudio(cvt: ptr): i32;
```

> `device` is `const char*` and we must pass **NULL** for the default device. Declare it as
> **`ptr`** (not `string`) so `null` can be passed. Verified working.
> `SDL_AudioDeviceID` is `Uint32` → `u32`. `SDL_AudioFormat` is `Uint16` → **`u16`**.
> `SDL_LoadWAV` is a C *macro*; the real symbol is **`SDL_LoadWAV_RW`**.

### 6.3 `SDL_AudioSpec` — 32 bytes

| Field | Offset | Type | Notes |
|---|---:|---|---|
| `freq` | 0 | `i32` | 44100 |
| `format` | 4 | `u16` | `AUDIO_S16SYS` = 32784 |
| `channels` | 6 | `u8` | 2 |
| `silence` | 7 | `u8` | filled in by SDL |
| `samples` | 8 | `u16` | power of two, e.g. 1024 |
| `padding` | 10 | `u16` | — |
| `size` | 12 | `u32` | device buffer bytes (SDL fills) |
| **`callback`** | **16** | **`ptr`** | **MUST be NULL for queue mode** |
| `userdata` | 24 | `ptr` | NULL |

`SDL_AudioCVT` is **128 bytes**: `needed`@0 `i32`, `src_format`@4 `u16`, `dst_format`@6 `u16`,
`rate_incr`@8 `f64`, **`buf`@16 `ptr`**, **`len`@24 `i32`**, **`len_cvt`@28 `i32`**,
**`len_mult`@32 `i32`**, `len_ratio`@36 `f64`.

Format constants:
```
AUDIO_U8      8        AUDIO_S8      32776
AUDIO_S16SYS  32784 (0x8010)   <- use this
AUDIO_S32SYS  32800   AUDIO_F32SYS  33056 (0x8120)
SDL_MIX_MAXVOLUME 128
SDL_AUDIO_ALLOW_FREQUENCY_CHANGE 1  FORMAT 2  CHANNELS 4  ANY 15
SDL_INIT_AUDIO 16
```

### 6.4 VERIFIED — 11/11, interpreted, compiled, dummy **and real PulseAudio**

```
audio driver = pulseaudio  output_devices=2
PASS  SDL_OpenAudioDevice(callback=NULL) [queue mode]   dev=2
      obtained: freq=44100 format=0x8010 channels=2 samples=512 bufsize=2048
PASS  SDL_QueueAudio                          queued=35280 bytes
PASS  device drains queue (playback is live)  before=35280 after_120ms=8656 (drained 26624)
PASS  SDL_ClearQueuedAudio                    queued=0
PASS  SDL_MixAudioFormat                      one_voice=1000, +half-volume voice=1500
PASS  SDL_RWFromFile
PASS  SDL_LoadWAV_RW                          len=11024 freq=22050 fmt=0x8010 ch=1
PASS  SDL_BuildAudioCVT                       needed=1 len_mult=16
PASS  SDL_ConvertAudio (resample to device)   in=11024 out=44096 (22050 mono -> 44100 stereo = 4x)
PASS  QueueAudio(converted WAV)               44096 bytes accepted
AUDIO PROBE: 11 passed, 0 failed
```

The drain test is the important one: the queue really is being consumed in real time, so
this is a live playback path, not a no-op.

### 6.5 Recommended audio architecture

**Load time** — for each SFX: `SDL_RWFromFile` → `SDL_LoadWAV_RW` → `SDL_BuildAudioCVT` →
`SDL_ConvertAudio` → keep the converted buffer **in device format** and `SDL_FreeWAV` the
original. Never convert at play time.

**Per frame:**

```
1. zero a mix buffer of N bytes  (N ≈ 2–3 frames of audio)
2. for each active voice:
       SDL_MixAudioFormat(mix, voice.data + voice.pos, dev_format, n, voice.volume)
       voice.pos += n ; retire the voice when exhausted
3. if SDL_GetQueuedAudioSize(dev) < high_water:  SDL_QueueAudio(dev, mix, N)
```

Keep roughly **2–3 frames** of audio queued (~30–50 ms). Less risks underrun on a frame
spike; more adds latency you can hear on gunshots. `SDL_GetQueuedAudioSize` is the
feedback signal — queue only when the backlog is below the high-water mark, otherwise the
queue grows unboundedly and audio drifts behind the action.

`SDL_MixAudioFormat` saturates rather than wrapping, so loud overlaps distort instead of
producing horrible wraparound clicks. Keep per-voice volume ≤ ~96/128 with many voices.

For **music**, use the same queue: stream a decoded buffer in chunks and mix it as voice 0.

---

## 7. Timing

```hemlock
extern fn SDL_GetPerformanceCounter(): u64;
extern fn SDL_GetPerformanceFrequency(): u64;
extern fn SDL_GetTicks(): u32;        // ms, wraps after ~49 days
extern fn SDL_GetTicks64(): u64;      // ms, 2.0.18+ — prefer this over GetTicks
extern fn SDL_Delay(ms: u32): void;
```

**Measured on this machine:** `SDL_GetPerformanceFrequency()` = **1 000 000 000** (nanosecond
resolution). Two back-to-back `SDL_GetPerformanceCounter()` calls differed by 40–660 ticks
(40–660 ns), i.e. the FFI call overhead itself — resolution is far finer than a frame.

```
PASS  SDL_GetPerformanceCounter/Frequency delta-time   freq=1000000000 dt=0.033055006s (asked 0.033)
```

### 7.1 u64 precision — checked, and it is fine

`SDL_GetPerformanceCounter` currently returns ~`1.2e15`. Since Hemlock might have
represented FFI integers as doubles (2^53 ceiling), this was worth proving rather than
assuming. `tools/probes/probe_ffi_numerics.hml` round-trips exact u64 values through FFI:

```
EXACT  2^53 - 1 : 9007199254740991      EXACT  2^53 + 1 : 9007199254740993
EXACT  2^53     : 9007199254740992      EXACT  u64 max  : 18446744073709551615
above 2^53: big2 - big1 = 1  (want 1)
```

**Identical interpreted and compiled.** Hemlock carries true 64-bit integers across the
FFI; there is no 2^53 hazard. Use the counter directly.

### 7.2 Recommended delta-time loop

```hemlock
let freq = SDL_GetPerformanceFrequency();
let t_prev = SDL_GetPerformanceCounter();
while (running) {
    let t_now = SDL_GetPerformanceCounter();
    let dt = (t_now - t_prev) / freq;      // seconds, f64
    t_prev = t_now;
    if (dt > 0.25) { dt = 0.25; }          // clamp: never let a hitch teleport the player
    update(dt);
    render();
    SDL_RenderPresent(ren);
}
```

Always clamp `dt`. Without it, an alt-tab or a loading hitch integrates a single enormous
step and shoots the player through the world.

---

## 8. Window, vsync, fullscreen

```hemlock
extern fn SDL_CreateWindow(title: string, x: i32, y: i32, w: i32, h: i32, flags: u32): ptr;
extern fn SDL_SetWindowFullscreen(win: ptr, flags: u32): i32;
extern fn SDL_GetWindowSize(win: ptr, w: ptr, h: ptr): void;   // two int* out-params
extern fn SDL_GetWindowFlags(win: ptr): u32;
extern fn SDL_CreateRenderer(win: ptr, index: i32, flags: u32): ptr;
extern fn SDL_RenderSetVSync(ren: ptr, vsync: i32): i32;       // 2.0.18+
extern fn SDL_RenderSetLogicalSize(ren: ptr, w: i32, h: i32): i32;
extern fn SDL_GetRendererInfo(ren: ptr, info: ptr): i32;
```

Constants:
```
SDL_WINDOWPOS_CENTERED            805240832  (0x2FFF0000)
SDL_WINDOW_FULLSCREEN             1          (real mode switch — avoid)
SDL_WINDOW_FULLSCREEN_DESKTOP     4097       (0x1001 — USE THIS)
SDL_WINDOW_SHOWN 4   HIDDEN 8   BORDERLESS 16   RESIZABLE 32
SDL_RENDERER_SOFTWARE 1   ACCELERATED 2   PRESENTVSYNC 4   TARGETTEXTURE 8
SDL_WINDOWEVENT 512   FOCUS_GAINED 12   FOCUS_LOST 13   CLOSE 14
SDL_QUIT 256
```

**Fullscreen toggle** — verified `PASS  SDL_SetWindowFullscreen(DESKTOP -> 0)  enter_rc=0 flag_set=1 exit_rc=0`:

```hemlock
if (fullscreen) { SDL_SetWindowFullscreen(win, SDL_WINDOW_FULLSCREEN_DESKTOP); }
else            { SDL_SetWindowFullscreen(win, 0); }
```

Use `FULLSCREEN_DESKTOP`, not `FULLSCREEN`: it is borderless-window fullscreen, so alt-tab
is instant and no mode switch can strand the user at the wrong resolution.

**Window size** — `SDL_GetWindowSize` writes two `int*`. Verified `320x240`.
Note: for a HiDPI-correct drawable size use `SDL_GetRendererOutputSize` instead.

**VSync.** Two routes:
- at creation: `SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED + SDL_RENDERER_PRESENTVSYNC)`
- at runtime: `SDL_RenderSetVSync(ren, 1)` — **verified `rc=0` on the real X11 GPU renderer**,
  and `rc=-1 'That operation is not supported'` under the software/dummy renderer (expected).

Runtime toggling is preferable so vsync can be a settings-menu option without recreating
the renderer. Treat a non-zero return as "vsync unavailable", not as an error.

**Renderer creation.** Keep Wobbleweed's existing advice — pass **`flags = 0`** and let SDL
choose, then fall back to `SDL_RENDERER_SOFTWARE`. Observed renderer flags:

| Environment | `SDL_GetRendererInfo().flags` | Meaning |
|---|---|---|
| real X11 | 10 | ACCELERATED(2) + TARGETTEXTURE(8) |
| dummy driver | 13 | SOFTWARE(1) + PRESENTVSYNC(4) + TARGETTEXTURE(8) |

`max_texture_width` is 16384 on the GPU and 0 (unlimited) on software. Both advertise
`TARGETTEXTURE`, which is why the render-target pipeline works headlessly in CI.

`SDL_RendererInfo` is **88 bytes**: `name`@0 `ptr`, `flags`@8 `u32`,
`num_texture_formats`@12 `u32`, `texture_formats`@16 (16×`u32`),
`max_texture_width`@80 `i32`, `max_texture_height`@84 `i32`.

### 8.1 ⚠⚠ THE BIG HEMLOCK FFI GOTCHA: `import` is positional

`extern fn` declarations bind to the **most recently declared `import`** above them, not to
all imported libraries. This failed hard:

```hemlock
import "libSDL2-2.0.so.0";
import "libXtst.so.6";
import "libX11.so.6";
extern fn SDL_Init(flags: u32): i32;    // ERROR
// FFI function 'SDL_Init' not found in 'libX11.so.6':
//   /lib/x86_64-linux-gnu/libX11.so.6: undefined symbol: SDL_Init
```

The fix is to place each `import` immediately before the externs it provides:

```hemlock
import "libSDL2-2.0.so.0";
extern fn SDL_Init(flags: u32): i32;
// ... all SDL externs ...

import "libX11.so.6";
extern fn XOpenDisplay(name: ptr): ptr;
```

Verified working interpreted **and** compiled. Multi-library FFI is fine — just keep each
library's externs grouped under its own `import`.

### 8.2 Other Hemlock notes worth knowing

- `args` is an **array, not a function** — use `args`/`args.length`, not `args()`.
- Array/string length is the **`.length` property**; there is no `len()` builtin.
- There is no `int()` builtin.
- **`/` produces a float in the compiled backend** even when it divides evenly
  (`35280` interpreted vs `35280.0` compiled in string interpolation). Arithmetic and
  comparisons are still correct; this only bites when formatting numbers for the HUD.
  Round/format explicitly for display.
- FFI `u32` and `u64` returns are numerically exact in both backends (§7.1).

---

## 9. `SDL_Vertex` (already used by Wobbleweed — confirmed)

`SDL_RenderGeometry` takes a packed array of **20-byte** `SDL_Vertex`:

| Field | Offset | Type |
|---|---:|---|
| `position.x` | 0 | `f32` |
| `position.y` | 4 | `f32` |
| `color.r,g,b,a` | 8,9,10,11 | `u8` ×4 |
| `tex_coord.x` | 12 | `f32` |
| `tex_coord.y` | 16 | `f32` |

Wobbleweed's existing 20-byte assumption is **correct**. Verified that geometry renders
correctly into a render target (§4.4).

---

## 10. Scancodes and keycodes

**Scancodes** index `SDL_GetKeyboardState(null)` (physical key, layout-independent — the
right choice for WASD). Array length is **512** (`SDL_NUM_SCANCODES`), verified at runtime.

```
A 4   B 5   C 6   D 7   E 8   F 9   G 10
Q 20  R 21  S 22  T 23  V 25  W 26  X 27  Z 29
1 30  2 31  3 32  4 33  5 34  0 39
RETURN 40  ESCAPE 41  BACKSPACE 42  TAB 43  SPACE 44  GRAVE 53
F1 58  F5 62  F11 68
LCTRL 224  LSHIFT 225  LALT 226  RCTRL 228  RSHIFT 229
RIGHT 79  LEFT 80  DOWN 81  UP 82
```

**Keycodes** (`event.key.keysym.sym`, offset **20**) are layout-dependent — use for text and
menu accelerators, never for movement:

```
ESCAPE 27  SPACE 32  RETURN 13  TAB 9  BACKQUOTE 96
w 119  a 97  s 115  d 100  e 101  q 113  r 114  f 102  g 103  c 99  v 118
1 49  2 50  3 51
F1 1073741882  F5 1073741886  F11 1073741892
LSHIFT 1073742049  LCTRL 1073742048  LALT 1073742050
UP 1073741906  DOWN 1073741905  LEFT 1073741904  RIGHT 1073741903
```

`SDL_KeyboardEvent`: `state`@12 `u8`, `repeat`@13 `u8` (**filter this** — ignore
`repeat != 0` for gameplay actions), `keysym.scancode`@16 `i32`, `keysym.sym`@20 `i32`,
`keysym.mod`@24 `u16`.

Useful hints (exact strings, from the headers):
`SDL_HINT_RENDER_SCALE_QUALITY` = `"SDL_RENDER_SCALE_QUALITY"`,
`SDL_HINT_RENDER_VSYNC` = `"SDL_RENDER_VSYNC"`,
`SDL_HINT_MOUSE_RELATIVE_MODE_WARP` = `"SDL_MOUSE_RELATIVE_MODE_WARP"`,
`SDL_HINT_RENDER_DRIVER` = `"SDL_RENDER_DRIVER"`,
`SDL_HINT_GRAB_KEYBOARD` = `"SDL_GRAB_KEYBOARD"`.

---

## 11. Symbol availability audit

All **84** functions bound by `docs/recon/sdl2_reference.hml` were confirmed **present** in
the installed `libSDL2-2.0.so.0`. Zero missing. Re-run the audit any time with:

```bash
grep -oP "^export extern fn \K\w+" docs/recon/sdl2_reference.hml | sort -u > /tmp/want
nm -D --defined-only /usr/lib/x86_64-linux-gnu/libSDL2-2.0.so.0 | awk '{print $NF}' | sort -u > /tmp/have
comm -23 /tmp/want /tmp/have        # any output = a missing symbol
```

This includes the newer entry points that would fail against an older SDL2:

| Symbol | Requires | Present |
|---|---|---|
| `SDL_RenderGeometry` | 2.0.18 | ✅ |
| `SDL_RenderSetVSync` | 2.0.18 | ✅ |
| `SDL_GetTicks64` | 2.0.18 | ✅ |
| `SDL_SetTextureScaleMode` | 2.0.12 | ✅ |
| `SDL_ComposeCustomBlendMode` | 2.0.6 | ✅ |
| `SDL_QueueAudio` | 2.0.4 | ✅ |

> **Ship note:** `SDL_RenderGeometry` requires **SDL ≥ 2.0.18**. That is the real minimum
> version for Nightshade, and it is recent — a 2020-era distro will not have it. Check
> `SDL_GetVersion()` at startup and fail with a clear message rather than crashing on a
> missing symbol.

---

## 12. What did NOT work (truth over optimism)

Only one genuine limitation was found, and it is environmental, not an FFI defect:

1. **`SDL_SetRelativeMouseMode` fails under `SDL_VIDEODRIVER=dummy`** —
   `rc=-1, "No relative mode implementation available"`. The
   `SDL_MOUSE_RELATIVE_MODE_WARP=1` hint does not help. **Consequence: mouse-look cannot be
   tested in headless CI.** Works perfectly on X11 (§2.6). *Workaround:* route look input
   through an injectable source so tests can drive it synthetically, and keep the real
   relative-mode path behind a display check.

2. **`SDL_RenderSetVSync` returns -1 under the software renderer** —
   `"That operation is not supported"`. Expected and harmless; returns 0 on the real GPU.
   Treat non-zero as "unavailable", not fatal.

3. **`SDL_WarpMouseInWindow` produces `xrel == 0`.** This is *correct SDL behaviour*, not a
   bug — warps deliberately do not feed back into relative motion. It is documented here
   only because it makes warp useless as a mouse-look test; use real motion (§2.6).

Everything else in the assignment — render targets, blend modes, alpha/color mod,
`RenderCopyEx` rotation and flip, `RGBA32` byte order, the audio queue, `MixAudioFormat`,
WAV loading and resampling, the performance counter, fullscreen, window size, logical size —
**worked on the first honest attempt, interpreted and compiled.**

No workarounds are required for the shipping game.

---

## 13. Files produced

| Path | What |
|---|---|
| `docs/recon/SDL_FFI.md` | this document |
| `docs/recon/sdl_abi_dump.txt` | raw authoritative offset/constant dump (351 lines) |
| `docs/recon/sdl2_reference.hml` | **drop-in bindings module** — all externs, constants, helpers |
| `tools/probes/sdl_abi_dump.c` | the C offset/constant dumper |
| `tools/probes/probe_render.hml` | 14 blend/target/copyex/format tests via pixel readback |
| `tools/probes/probe_pipeline.hml` | the full frame pipeline (geometry→target→upscale→fx→HUD) |
| `tools/probes/probe_audio.hml` | 11 audio-queue / mixer / WAV / resample tests |
| `tools/probes/probe_input.hml` | mouse/event-layout/timing/window tests |
| `tools/probes/probe_mouselook.hml` | decisive live relative-motion test (needs X11) |
| `tools/probes/probe_ffi_numerics.hml` | u64 FFI precision audit |
| `tools/probes/probe_module.hml` | smoke test proving `sdl2_reference.hml` imports and runs |

### Reproducing everything

```bash
cd /home/nbeerbower/Projects/nightshade
H=/home/nbeerbower/Projects/hemlock

SDL_VIDEODRIVER=dummy $H/hemlock tools/probes/probe_render.hml     # 14 passed, 0 failed
SDL_VIDEODRIVER=dummy $H/hemlock tools/probes/probe_pipeline.hml   #  5 passed, 0 failed
SDL_AUDIODRIVER=dummy $H/hemlock tools/probes/probe_audio.hml <wav># 11 passed, 0 failed
SDL_VIDEODRIVER=dummy $H/hemlock tools/probes/probe_input.hml      #  9 passed, 0 failed
DISPLAY=:0            $H/hemlock tools/probes/probe_mouselook.hml  # live xrel/yrel

# and compiled — same results
$H/hemlockc -o /tmp/pr tools/probes/probe_render.hml && SDL_VIDEODRIVER=dummy /tmp/pr
```

**Total: 41 automated assertions, 0 failures**, across interpreted, `hemlockc`-compiled,
software/headless, and real accelerated GPU.
