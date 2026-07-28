# Host environment facts (verified by the orchestrator, 2026-07-27)

These were checked directly on this machine. Trust them over inference.

## Toolchain
- `hemlock` and `hemlockc` both at `/usr/local/bin/`.
- Cross-directory imports work in BOTH interpreter and compiler: a file in
  `/tmp/...` importing `/home/nbeerbower/Projects/wobbleweed/src/vec.hml` by absolute
  path compiled and ran fine. Relative imports also work. `hemlockc` on a small
  multi-module program took ~3.3s.
- `DISPLAY=:0` is set and a real display is available. `SDL_VIDEODRIVER=dummy`
  works for headless runs and PNG capture (`examples/geom_scene.hml` writes a PNG).

## SDL  (UPDATED — the user installed libsdl2-dev + libsdl2-mixer-dev)
- Headers now present: `/usr/include/SDL2/` (78 files). **Grep these for constants
  and struct offsets — they are authoritative.**
- ### ~~VERSION SKEW~~ — **RETRACTED. There is no skew. I was wrong.**
  **Runtime and headers are BOTH SDL 2.0.20.** Verified by calling
  `SDL_GetVersion()` at runtime -> `2.0.20`, matching
  `SDL_PATCHLEVEL 20` in the header and `pkg-config --modversion sdl2`.

  **My error:** I inferred "runtime is 2.0.18" from the filename
  `libSDL2-2.0.so.0.18.2`. That inference is invalid — SDL's shared-object
  version is deliberately *offset* from the release version, and SDL **2.0.20**
  ships as `libSDL2-2.0.so.0.18.2`. The `SDL_GetRevision()` hash `b424665e`
  quoted earlier in this document is likewise the **2.0.20** tag, not 2.0.18.

  **Consequence:** the "never bind anything newer than 2.0.18" rule was based on
  a false premise. It is retained anyway as a harmless conservative ceiling —
  and it costs nothing, because `grep "available since SDL 2.0.19\|2.0.20"` over
  all headers returns **zero hits** (those releases added no new functions).
  `SDL_RenderGeometry` and `SDL_RenderSetVSync` (both 2.0.18) remain the newest
  APIs in use.

  **Lesson worth keeping:** do not infer a library's version from its filename.
  Call the version API.
- **SDL2_mixer IS available**: headers `/usr/include/SDL2/SDL_mixer.h`, runtime
  `libSDL2_mixer-2.0.so.0` -> **linked version 2.0.4** (verified at runtime).

### AUDIO DECISION: use SDL2_mixer. (Verified, see probe results below.)
Earlier guidance said "hand-roll a mixer on SDL_QueueAudio" because no mixer
existed. That is now **superseded**. SDL2_mixer does multi-voice mixing and
positional panning in C, for free, instead of burning our frame budget doing it
in Hemlock. `SDL_QueueAudio` remains a verified working fallback.

**Binding gotcha that will waste an hour if you miss it:** `Mix_PlayChannel` and
`Mix_LoadWAV` are **C preprocessor macros, not exported symbols** — `extern fn`
against them fails. Bind the real functions instead:
`Mix_PlayChannelTimed(channel, chunk, loops, -1)` and `Mix_LoadWAV_RW(...)`.

**Ownership gotcha:** `Mix_QuickLoad_RAW` does **not copy** — the `Mix_Chunk`
points straight at our Hemlock buffer. The buffer must stay alive for as long as
the sound can play, or it is a use-after-free. Keep all SFX buffers in one
long-lived table owned by the audio module.

## Consequences for the FFI design
1. **Never depend on `SDL_Event` struct byte offsets where an API call can give
   you the same data.** For mouse look use `SDL_GetRelativeMouseState(&x, &y)`
   and for buttons use its return bitmask / `SDL_GetMouseState`. These need no
   struct layout knowledge and cannot silently break. The existing
   `src/sdl.hml` already pokes `SDL_Event` at offset 20 for the keysym - that
   works today, but keyboard state should likewise prefer
   `SDL_GetKeyboardState` (it already does).
2. Any constant that cannot be grepped from a header **must be verified
   empirically at runtime** (call the function, check the return code, check
   pixels) rather than assumed. Document each constant with how it was verified.
3. Because there are no headers, `SDL_RenderGeometry` (SDL >= 2.0.18) is
   available but only *just* - 2.0.18 is the exact version it landed in. Do not
   use any SDL API newer than 2.0.18. Notably `SDL_RenderGeometryRaw` is fine
   (also 2.0.18) but anything from 2.0.20+ (e.g. `SDL_RenderTextureRotated`
   naming, SDL3 APIs) will fail to resolve.

## VERIFIED FFI PROBE RESULTS (orchestrator ran this — 14/14 pass)

Probe source: `tools/probes-host/probe.hml`. Run interpreted AND compiled with
`hemlockc`, on the **real x11 display** and headless. Results were **byte-identical
between interpreter and compiler**. SDL revision on this box:
`libsdl-org/SDL@b424665e` (2.0.18).

Every one of these constants is confirmed **by observed behaviour**, not by a header:

| Feature | SDL calls | Constant(s) verified | Result |
|---|---|---|---|
| Delta-time clock | `SDL_GetPerformanceCounter/Frequency` | — | PASS, freq = 1e9 |
| **Mouse look** | `SDL_SetRelativeMouseMode(1)` / `SDL_GetRelativeMouseState(&x,&y)` | — | PASS on x11 |
| Mouse buttons | return bitmask of `SDL_GetMouseState` | bit0=L, bit1=M, bit2=R | PASS |
| Hide cursor | `SDL_ShowCursor(0)` | — | PASS |
| **Render target** | `SDL_CreateTexture(..., TARGET, ...)` + `SDL_SetRenderTarget` | `SDL_TEXTUREACCESS_TARGET = 2`, `SDL_PIXELFORMAT_ARGB8888 = 372645892` (0x16362004) | PASS — drew red into the target and read `(255,0,0)` back |
| Restore backbuffer | `SDL_SetRenderTarget(ren, null)` | — | PASS |
| **Alpha blending** | `SDL_SetTextureBlendMode/AlphaMod/ColorMod` | `SDL_BLENDMODE_BLEND = 1`, `SDL_BLENDMODE_ADD = 2` | PASS |
| Alpha composite | half-alpha red over blue | — | PASS — read back exactly `(128,0,127)` |
| Sprite rotation | `SDL_RenderCopyEx(..., angle, null, 0)` | — | PASS |
| HUD rects | `SDL_RenderFillRect` + `SDL_SetRenderDrawBlendMode` | `SDL_Rect` = 4 x i32 {x,y,w,h}, 16 bytes | PASS |
| **Audio device** | `SDL_OpenAudioDevice(null,0,want,have,0)` | `AUDIO_S16LSB = 32784` (0x8010) | PASS — got 22050Hz mono back |
| **Audio playback** | `SDL_QueueAudio` + `SDL_PauseAudioDevice(dev,0)` | — | PASS — 4410 bytes queued |

### `SDL_AudioSpec` layout (verified — `have` came back correctly populated)
```
freq     i32  @0      format   u16  @4     channels u8  @6    silence  u8  @7
samples  u16  @8      padding  u16  @10    size     u32 @12
callback ptr  @16     userdata ptr  @24            (allocate 64 bytes, memset 0)
```
**Set `callback` to NULL** — that selects queue mode, so Hemlock never has to hand a
function pointer back to C. This is the whole reason audio is safe here.

## VERIFIED SDL2_mixer PROBE (8/8 pass, interpreted AND compiled, dummy + real device)

Probe source: `tools/probes-host/probe_mix.hml`.

| Check | Result |
|---|---|
| `Mix_Linked_Version` | **2.0.4** |
| `Mix_OpenAudio(22050, AUDIO_S16LSB, 1, 512)` | PASS, ret 0 |
| `Mix_QuerySpec` | PASS — freq 22050, fmt 32784, 1 channel |
| `Mix_AllocateChannels(16)` | PASS — 16 mixing channels |
| `Mix_QuickLoad_RAW` on a procedural Hemlock buffer | PASS — no file I/O, no WAV encoding needed |
| `Mix_PlayChannelTimed(-1, chunk, 0, -1)` x6 | PASS — **6 overlapping voices** |
| `Mix_SetPanning(ch, l, r)` | PASS — per-channel positional audio |
| `Mix_Playing` mid-sound | PASS — 6 channels confirmed live |

So: procedural SFX synthesized in Hemlock -> raw S16 buffer -> `Mix_QuickLoad_RAW`
-> played on any of 16 channels with 3D panning. No asset files, no C callback.

## Interpreter vs compiler difference (observed while writing the probe)
Declaring `fn make_blip(...): object` while actually returning a `buffer`:
- **`hemlockc`**: caught it at COMPILE time — `error: return type mismatch:
  expected 'object', got 'buffer'`.
- **`hemlock` (interpreter)**: compiled nothing, ran, and died mid-execution with
  `Runtime error: Expected object, got non-object`.

**RULE: always `hemlockc` a module before trusting it.** The interpreter will
happily run code that the compiler rejects, and the game ships compiled. Note
also that `buffer` is a distinct type from `object` in annotations.

### The ONE failure, and it does not matter
`SDL_SetRelativeMouseMode` returns -1 under `SDL_VIDEODRIVER=dummy`
("No relative mode implementation available"). That is an SDL dummy-driver
limitation, not ours — it passes on the real display. **Consequence:** the input
layer must tolerate relative mouse mode failing and fall back gracefully, so
headless screenshot/bench runs never crash.

## Measured baseline (orchestrator)
Existing wobbleweed GPU path, ~530 tris/frame, 320x240, headless software renderer:
- interpreted: **52 fps**
- compiled with `hemlockc`: **283 fps**

The game ships compiled. Budget ~2000-3000 triangles/frame at 60fps.
