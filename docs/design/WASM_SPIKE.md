# WASM Spike — can Nightshade run in a browser?

**Date:** 2026-07-30 · **Compiler:** `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` · **Emscripten:** 5.0.1
**RULE 0:** verified — printed `107` then `5120738502741017561`.

All work was done in a scratch copy at `/tmp/wasm_spike/`. **No file in
`nightshade/`, `wobbleweed/` or `hemlock/` was modified** (this document is the
sole exception). Every change described below is a *proposal*, not an edit.

---

## Verdict: **FEASIBLE-WITH-WORK**

A Hemlock program using wobbleweed's SDL layer renders in Chrome today. I got
`SDL_RenderGeometry` — nightshade's actual render path — drawing 1000
Gouraud-shaded triangles per frame in a browser, driven from `.hml` source.

The compute cost is fine. **The blocker is the shape of the game loop, not the
language, the renderer, or the arithmetic.**

---

## 1. What Hemlock's WASM target actually is

There are **two independent things** in the repo, and the distinction decides
everything:

| | `make wasm-interpreter` → `hemlock/wasm/` | `hemlockc --target wasm` |
|---|---|---|
| What it is | the **tree-walking interpreter** compiled to WASM | **AOT**: your `.hml` → C → `emcc` → `.wasm` |
| Artifacts | `hemlock.wasm`, `hemlock.js`, `playground.html` | `<prog>.js` + `<prog>.wasm` (or `.html`) |
| Use | a web playground that evaluates Hemlock source | **this is the one for shipping a game** |
| CI job | `wasm-interpreter` | `wasm-compiler` |

The pre-built `hemlock/wasm/` directory is the *playground* — not a path to
shipping Nightshade. The relevant target is `hemlockc --target wasm`, which is
real, documented in `--help`, CI-tested, and worked first try.

`--emit-c` / `-c` also exist, which is what made this spike possible: the
built-in `emcc` line is a fixed `snprintf` in `src/backends/compiler/main.c`
(~line 716) with **no escape hatch for extra flags**, so `-sUSE_SDL=2` cannot be
passed. Emitting C and linking by hand routes around that.

## 2. Hello world — works

```
$ hemlockc --target wasm -o hello hello.hml && node hello.js
hello from wasm
45
```
34 KB `.wasm` + 14 KB `.js`. Clean.

## 3. The SDL2 FFI — the crux

**Hemlock's FFI is `dlopen`/`dlsym`-based even in the *compiled* target.** The
codegen emits, per `extern fn`, a lazy runtime resolve:

```c
_ffi_ptr_SDL_CreateWindow = hml_ffi_sym(_ffi_lib_libSDL2_2_0_so_0, "SDL_CreateWindow");
...
return hml_ffi_call(_ffi_ptr_SDL_CreateWindow, _args, 6, _types);
```

There is **no static/direct-C-call binding path** anywhere in the compiler.
Under Emscripten the whole of `runtime/src/builtins_ffi.c` is `#ifndef
__EMSCRIPTEN__`, so `hml_ffi_sym`/`hml_ffi_call` become panic stubs
(`runtime/src/wasm_shim.c`). Stock behaviour:

```
Warning: FFI import 'libSDL2-2.0.so.0' ignored in WASM build
before ffi
Uncaught exception: ffi_sym() is not available in WebAssembly
```

`import` only warns; the *call* panics (consistent with the known H-8 lazy-resolution note).

**This is solvable, and I solved it.** I wrote a ~150-line shim providing
`hml_ffi_load_import` / `hml_ffi_sym` / `hml_ffi_call` that resolves names from a
static table of Emscripten's linked-in SDL2 and dispatches through fixed C
function-pointer signatures. It works because in **wasm32 every argument in
`wobbleweed/src/sdl.hml` is a 32-bit scalar or a pointer (also 32-bit)** — all
69 `extern fn`s, no floats, no structs by value — so the signature space
collapses to (arity × return-kind), about two dozen cases.

Two things bit me and are worth recording:

- **WASM `call_indirect` is strictly type-checked.** A `void`-returning function
  *cannot* be called through an `i32`-returning pointer type — you get
  `RuntimeError: function signature mismatch`. libffi papers over this natively;
  in WASM the signature set must be enumerated statically. This is why a generic
  "any signature" FFI is fundamentally unavailable in the browser.
- Emscripten's SDL2 is a **32-bit** build. `sdl.hml`'s hardcoded `SDL_Event`
  offsets happen to be safe (the keyboard/mouse/wheel events contain no
  pointers), but any event or struct containing a pointer will differ from the
  x86-64 layout. Audit before trusting.

## 4. Two Hemlock bugs found (both cheap to fix)

### B-1 — `--target wasm` browser output is dead on arrival
Stock `hemlockc --target wasm -o foo.html` throws before `main` runs:

```
ReferenceError: FS is not defined      (and, with the FS shim, `IDBFS is not defined`)
```

`hml_runtime_init` mounts an IDBFS persistent filesystem via `EM_ASM`
(`runtime/src/builtins_core.c:245-252`), but the built-in `emcc` line passes
neither `-sFORCE_FILESYSTEM=1` nor `-lidbfs.js`. Node builds survive because
Emscripten links the FS for node targets by default; browser builds strip it.
**Every browser build from stock `hemlockc` is broken.**
*Fix:* add `-sFORCE_FILESYSTEM=1 -lidbfs.js` to the WASM branch in
`src/backends/compiler/main.c`, or guard the IDBFS `EM_ASM` on
`typeof FS !== 'undefined'`. **~1 line.**

### B-2 — four pointer builtins stubbed out for no reason
`ptr_offset`, `ptr_deref_i32`, `ptr_read_i32`, `ptr_write_i32` panic in WASM
("`ptr_offset() is not available in WebAssembly`"). They are **pure pointer
arithmetic with zero libffi dependency** — they got stubbed purely because they
happen to live in `runtime/src/builtins_ffi.c`, which is wholesale `#ifndef
__EMSCRIPTEN__`. Their 22 siblings in `builtins_memory.c` (`ptr_deref_u32`,
`ptr_write_f32`, …) work in WASM fine.

This blocks **all** of wobbleweed's vertex-writing code (`batch.hml`,
`sdl.hml:draw_tris_at`), i.e. the whole renderer. I reimplemented the four
verbatim in my shim and everything worked immediately.
*Fix:* move those four functions to `builtins_memory.c`, or narrow the
`#ifndef __EMSCRIPTEN__` in `builtins_ffi.c` to cover only the libffi-dependent
region. **~30 lines moved, no logic change.**

Also note: the other `ptr_read_*` variants in `builtins_ffi.c` have *no* WASM
stub at all, so using them would be a link error rather than a runtime panic.

## 5. What actually rendered

| Test | Result |
|---|---|
| `hello.hml` (node) | ✅ |
| `wobbleweed/examples/plasma.hml` (framebuffer → texture → present) | ✅ animating in Chrome |
| **`SDL_RenderGeometry` triangle** (nightshade's real path) | ✅ Gouraud-shaded, `rc == 0` |
| **1000 triangles / 3000 verts per frame** | ✅ |

## 6. Measurements

**Pure compute** — `mat_apply`/`mat_mul` from `wobbleweed/src/vec.hml`, 300k
vertex transforms, no SDL, no I/O:

| | µs/vertex | vs native |
|---|---|---|
| native `hemlockc -O3` | 0.50 | 1.00x |
| WASM in **Chrome** | 0.66 | **1.33x** |
| WASM in node | 0.77 | 1.55x |

**The vertex-transform bottleneck is only ~1.3x slower in WASM.** That is the
good news, and it is the number that matters most given the stated 82-88% frame
share.

**Full render path** — 300 frames × 1000 triangles (3000 verts) through
`SDL_RenderGeometry`:

| Build | total | ms/frame | vs native |
|---|---|---|---|
| native | 165 ms | 0.55 | 1.00x |
| WASM, **no** ASYNCIFY | 336 ms | 1.12 | **2.04x** |
| WASM, **with** ASYNCIFY | 78,370 ms | 261 | **475x** |

`plasma.hml`: 74 fps native vs ~45 fps in Chrome (≈1.65x).

## 7. The real blocker: the blocking game loop

Nightshade's loop is `while (running) { ...; delay(n); }`. A browser cannot have
its main thread held like that — the tab must return to the event loop.

The only way to keep that shape is Emscripten's **ASYNCIFY**, which rewrites the
program so the stack can unwind and resume. I used it to make `delay()` yield
(mapping `SDL_Delay` → `emscripten_sleep`), and plasma ran fine at ~1.65x.

But **ASYNCIFY taxes call-heavy code catastrophically**: the same triangle
benchmark went from 336 ms to 78,370 ms — a **233x** regression from that one
flag, 475x off native, 3 fps. Hemlock's generated C is exceptionally call-dense
(every builtin is a call, every FFI hop is an *indirect* call ASYNCIFY cannot
statically prove safe), so instrumentation covers essentially the whole program.
Binary size confirms it: 874 KB → 1183 KB (+35%).

Plasma survived because its inner loop is arithmetic on buffer indices; the
vertex path is dominated by `ptr_offset`/`ptr_write_f32` calls, which is exactly
what ASYNCIFY punishes. **The retro-FPS renderer is the worst case for it.**

### What would have to change

The loop must become **callback-driven**: hand one frame's work to
`emscripten_set_main_loop`, return, get called again next rAF. Then ASYNCIFY is
not needed at all and the honest cost is the measured **~2x**.

That needs, roughly in increasing order of cost:

1. **(cheap, in Hemlock)** a builtin to register a Hemlock function as the
   frame callback — e.g. `set_main_loop(fn, fps)` wrapping
   `emscripten_set_main_loop_arg`. Also requires the compiler to *not* tear down
   the runtime when `main` returns (`-sEXIT_RUNTIME=0` + skipping
   `hml_runtime_cleanup`).
2. **(moderate, in nightshade/wobbleweed)** refactor the loop body into a
   `fn frame()` with all per-frame state hoisted to module scope. The
   `src/sim/**` half is already deterministic and clock-free, so this is mostly
   mechanical on the client/render side.
3. **(alternative, fragile)** keep the blocking loop and tame ASYNCIFY with an
   `ASYNCIFY_ONLY` allowlist. I would not bet on this: the FFI indirection means
   the call graph cannot be pinned down statically, and it silently breaks
   whenever the hot path changes.

## 8. Other gaps worth knowing

- **Threading**: `spawn`/`join`/`channel_*` are panic stubs in the non-threaded
  WASM runtime. `--threads` exists (`libhemlock_runtime_wasm_threaded.a`,
  pthreads → Web Workers) but needs COOP/COEP headers, so "click a link and
  you're playing" gets a cross-origin-isolation requirement. Untested here.
- **Sockets, process, exec, websockets, zlib, ecdsa** are all stubbed — 81
  panic stubs total in `wasm_shim.c`. Multiplayer over the current socket layer
  will not port; it would need a WebSocket/WebRTC path.
- **No asset files** is a genuine advantage — nothing to preload, no virtual FS
  to populate, and the ~160 ms procedural boot happens in the browser too.
- Binary size is comfortable: ~875 KB `.wasm` + ~180 KB `.js` for the full
  runtime + SDL2, before compression.

## 9. Recommendation

Worth doing, but sequence it:

1. Fix **B-1** and **B-2** upstream in Hemlock (both trivial, both benefit every
   WASM user, neither is Nightshade-specific).
2. Decide on the FFI story. The shim approach works but lives outside
   `hemlockc`; the durable fix is either a `--target wasm` mode that emits
   direct C calls for `extern fn` against a linked library, or an
   `--emcc-flags` pass-through so projects can link ports themselves. The
   former is better and is what makes `-sUSE_SDL=2` viable in-tree.
3. **Prototype the callback-driven main loop before committing.** This is the
   only item with real design risk, and every performance number above depends
   on it.

**Biggest risk:** the main-loop refactor. Not because it is hard, but because
it touches the client/render structure that the rest of the project is built
around, and getting it wrong means paying ASYNCIFY's 233x tax — which is the
difference between 60 fps and 3 fps. Everything else measured here is
comfortably in budget.

---

### Reproducing

Scratch tree `/tmp/wasm_spike/` (`ffi_shim.c`, `shimdecl.h`, `tri.hml`,
`tri_bench.hml`, `bench_vt.hml`). Build shape:

```sh
hemlockc --target wasm -O3 --emit-c prog.c -o /dev/null prog.hml
sed -e 's/hml_ffi_load_import(/shim_ffi_load_import(/g' \
    -e 's/hml_ffi_sym(/shim_ffi_sym(/g'   -e 's/hml_ffi_call(/shim_ffi_call(/g' \
    -e 's/hml_builtin_ptr_offset(/shim_ptr_offset(/g' \
    -e 's/hml_builtin_ptr_deref_i32(/shim_ptr_deref_i32(/g' \
    -e 's/hml_builtin_ptr_read_i32(/shim_ptr_read_i32(/g' \
    -e 's/hml_builtin_ptr_write_i32(/shim_ptr_write_i32(/g' \
    -e 's|^#include <emscripten.h>|#include <emscripten.h>\n#include "shimdecl.h"|' \
    prog.c > prog_shim.c
emcc -O3 -o prog.html prog_shim.c ffi_shim.c -I. -I<hemlock>/runtime/include \
     <hemlock>/libhemlock_runtime_wasm.a \
     -sUSE_SDL=2 -sWASM=1 -sALLOW_MEMORY_GROWTH=1 -sSTACK_SIZE=1048576 \
     -sFORCE_FILESYSTEM=1 -lidbfs.js -D__HEMLOCK_WASM__=1
```
Add `-sASYNCIFY` only if the program calls `delay()` — and read §7 first.
