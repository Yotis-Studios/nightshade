# Hemlock for Nightshade — Language & Performance Field Manual

**Audience:** engineers writing the Nightshade FPS in Hemlock on top of Wobbleweed.
**Toolchain measured:** `hemlockc 2.8.2` / `hemlock 2.8.2` (built Jul 25 2026), Linux x86-64, gcc.
**Every number in this document was produced by a benchmark in `/home/nbeerbower/Projects/nightshade/tools/bench/`, compiled with `hemlockc -O3` and run on this machine.** Re-run them with `tools/bench/run_all.sh`.

> **TL;DR for the impatient**
> 1. Ship compiled (`hemlockc -O3`). Interpreted is 10–60x slower.
> 2. **Never allocate an object per vertex/particle/tick.** Object literals cost ~120–240 ns each. That alone is the difference between 11 ms/frame and 2 ms/frame for 3000 triangles.
> 3. **Never call `array.sort(comparator)` per frame.** Hemlock's sort is a naive last-pivot quicksort: on a nearly-sorted array (i.e. every frame after the first) it degrades to O(n²) — **160 ms/frame** for 3000 triangles — and it **segfaults** on a presorted 200 000-element array. Use a bucket sort.
> 4. A `let x: f64` inside a function becomes a real C `double` **only** if it never escapes and its name doesn't collide with any top-level variable. Both traps are silent and cost ~2x.
> 5. `array` is the *fastest* random-access float container (faster than raw `ptr`). `buffer`/`ptr` is for **memory footprint** and **C/SDL interop**, not for speed.

---

## Table of contents

1. [Modules, imports, exports, and how `hemlockc` resolves them](#1-modules)
2. [The value model: what a Hemlock value actually costs](#2-value-model)
3. [Containers: object vs array vs buffer vs raw ptr](#3-containers)
4. [The fastest way to hold a large array of floats](#4-float-storage)
5. [Unboxing: the single biggest compiled-performance lever](#5-unboxing)
6. [Functions, closures, methods, struct-like patterns](#6-functions)
7. [Numeric semantics: overflow, division, casts, folding traps](#7-numerics)
8. [Error handling, `defer`, and manual memory](#8-errors-memory)
9. [`hemlockc`: invocation, flags, build times](#9-hemlockc)
10. [Interpreter vs compiler: verified differences](#10-parity)
11. [Landmines found in this recon (read this section twice)](#11-landmines)
12. [PERFORMANCE RULES (with the benchmark that justifies each)](#12-rules)
13. [A frame budget for Nightshade](#13-budget)
14. [Benchmark index](#14-bench-index)

---

<a name="1-modules"></a>
## 1. Modules, imports, exports, and how `hemlockc` resolves them

### Syntax that actually works

```hemlock
// --- exporting ---
export fn v3(x: f64, y: f64, z: f64): object { return { x: x, y: y, z: z }; }
export let SUN = v3(0.4, 1.0, 0.55);      // module-level state, singleton
export const MAX_TRIS = 4096;
export define Vec2 { x: f64, y: f64 }     // struct type
export extern fn SDL_GetTicks(): u32;     // re-export an FFI symbol

fn helper() { }
fn other() { }
export { helper, other };                 // export list form

export { add, sub } from "./math.hml";    // re-export (barrel module)
```

```hemlock
// --- importing ---
import { batch_tri, batch_flush } from "./geom.hml";   // named  (FAST)
import { v_add as vadd } from "./vec.hml";             // aliased
import * as sdl from "./sdl.hml";                      // namespace (SLOW - see below)
import { sin, cos, PI } from "@stdlib/math";           // stdlib
import "./register_weapons.hml";                       // side-effect only (.hml required)
import "libSDL2-2.0.so.0";                             // FFI shared library (NO .hml)
```

**Resolution rules (verified in `src/modules/modules.c`):**

| Form | Resolves to |
|---|---|
| `"./x.hml"`, `"../x.hml"`, `"./sub/x.hml"` | relative to the **importing file's** directory. `.hml` may be omitted. |
| `"/abs/path.hml"` | absolute |
| `"@stdlib/<name>"` | `<stdlib_dir>/<name>.hml`. `stdlib_dir` is found by probing, in order: `dirname(exe)/stdlib`, `dirname(exe)/../stdlib`, `dirname(exe)/../lib/hemlock/stdlib`, `$CWD/stdlib`, `/usr/local/lib/hemlock/stdlib`. Directory traversal out of stdlib is rejected. |
| `"owner/repo[/sub]"` | `hem_modules/` package (hpm), searched upward from the importer |
| bare string that is **not** `.hml` and does **not** start with `@` | **FFI shared library** (`dlopen`) |

**Semantics:**
- Modules are **singletons**, cached by canonical absolute path, executed in topological order.
- `export let` is **shared mutable state** across all importers.
- Imported bindings are **immutable** at the import site (`add = ...` is an error).
- Circular imports are detected and are a hard error.
- **`export define` types are registered globally.** After *any* import from a module, its `define`d types are usable by name. You **cannot** and **must not** name them in the import list — `import { Vec2 } from "./vec.hml"` fails with `Undefined variable 'Vec2'`.
- No dynamic `import()`. No conditional exports.

**`hemlockc` compiles the whole module graph into one C translation unit** (verified: `wobbleweed/examples/walk_gpu.hml` + its 8 imported modules → a single 14 200-line `.c`, one `gcc` invocation). Module-level symbols are mangled `_mod<N>_fn_<name>`. There is no separate compilation and no incremental build — **every build recompiles everything**.

### Import-style performance (`bench_module.hml`, 20 M calls)

| Call form | Time | Note |
|---|---|---|
| local `fn` call | 295 ms | |
| **named import** `add2(a,b)` | **213 ms** | same speed as (here, faster than) a local call |
| **namespace import** `lib.add2(a,b)` | **644 ms** | **~3x slower** — object-property lookup + indirect call |
| reading an imported `let` in a loop | 145 ms | |
| same value copied to a local first | **97 ms** | 1.5x |

> **Rule M1:** Use named imports (`import { x } from`). Never use `import * as ns` on a hot path.
> **Rule M2:** Copy imported constants into function-local `let`s before a loop.

### Recommended layout for Nightshade

```
nightshade/
  src/
    core/      math.hml  fixed.hml  rng.hml       // leaf modules, no imports
    world/     chunk.hml  gen.hml  mesh.hml
    render/    frame.hml  hud.hml
    game/      player.hml  weapon.hml  ai.hml
    main.hml                                       // entry
```
Keep the import graph a DAG and shallow — a cycle is a build error, and a single deep chain still recompiles wholesale on every build.

---

<a name="2-value-model"></a>
## 2. The value model: what a Hemlock value actually costs

Every runtime value is a **16-byte tagged union** (`HmlValue` in `runtime/include/hemlock_value.h`: a 4-byte type tag + padding + an 8-byte payload). This is the single most important fact for budgeting.

```c
typedef struct HmlValue {
    HmlValueType type;      // 4 bytes + 4 padding
    union { int32_t as_i32; double as_f64; HmlArray *as_array; ... } as;  // 8 bytes
} HmlValue;                 // => 16 bytes
```

Consequences you must design around:

- **A Hemlock `array` of N numbers costs 16·N bytes** plus header. Measured: `array<i32>` of 2 097 152 block ids = **16.03 bytes/block**; the same data in `buffer(u8)` = **1.03 bytes/block** (`bench_voxel`). That is a **15.5x** footprint difference.
- Strings ≤ 23 bytes are stored inline (SSO threshold `HML_SSO_THRESHOLD = 23`).
- The runtime keeps free-list pools: 1024 environments (≤16 vars), 512 objects (**≤8 fields**), 512 closures. An object gaining a 9th field migrates to the heap. Measured cost of that boundary: 8-field literal **240 ns**, 9-field literal **275 ns** (`bench_misc`).
- Refcounting is internal and automatic for `string`/`array`/`object`/`buffer`. `ptr` from `alloc()` is **never** reclaimed for you.

---

<a name="3-containers"></a>
## 3. Containers: object vs array vs buffer vs raw ptr

### Measured costs (bench_hotpath, 5 M iterations, compiled -O3)

| Operation | ns/op |
|---|---|
| 3 native `f64` locals, no container | ~2 ns/read |
| `v[i]` read from an `array` | **10.7 ns** |
| `v.x` read from an `object` | **14.3 ns** |
| `a[i] = v` write to an `array` | ~3.5 ns |
| `a.push(v)` | 17 ns (13.6 ns on a `clear()`ed reused array) |
| `ptr_write_f32(ptr_offset(p, i*4, 1), v)` | **~20 ns** (two out-of-line runtime calls) |
| `p[i]` byte read from a raw `ptr` | ~11 ns |
| `b[i]` byte read from a `buffer` (bounds checked) | ~12 ns |
| **allocate `{x,y,z}` object literal** | **~84 ns** (124 ns incl. 3 reads) |
| **allocate `[a,b,c]` array literal** | **~32 ns** (64 ns incl. 3 reads) |
| `alloc(64)` + `free` | 15 ns |
| `buffer(64)` + `free` | 50 ns |

### Why arrays beat raw pointers

`a[i]` is emitted **inline** by the code generator as a small type switch plus `hml_array_get_i32_fast()` (see `src/backends/compiler/codegen_expr.c:538`). `ptr_offset(...)` and `ptr_read_f32(...)` are each an **out-of-line call into the runtime that boxes an `HmlValue`** (`src/backends/compiler/codegen_call.c:372`). Two calls beat one inline switch only in your imagination.

### Decision table

| You need… | Use | Why |
|---|---|---|
| Hot per-frame math on ≤ a few hundred numbers | **native `f64`/`i32` locals** | 5–20x faster than any container |
| Random-access float/int array, speed-critical | **`array` / `array<f64>`** | fastest indexed access measured |
| Millions of small elements (voxel chunks, heightmaps, lightmaps) | **`buffer`** (or `ptr`) | 16x less memory; access only ~10 % slower |
| Memory handed to C / SDL (`SDL_Vertex`, texture pixels) | **`ptr` from `alloc()`** | `ptr_offset` needs a `ptr`; SDL needs a raw address |
| Bounds safety on a byte array | **`buffer`** + `b[i]` | bounds-checked, ~12 ns |
| Heterogeneous named record, created once | `object` | fine when not per-frame |
| Heterogeneous record created per frame | **flatten it into locals or parallel arrays** | 84–240 ns each is unaffordable |

### `ptr` / `buffer` API — corrections to the official docs

The published `docs/reference/builtins.md` is **wrong about `ptr_offset`**. Verified behaviour:

```hemlock
ptr_offset(p, offset, element_size)   // THREE arguments, required
```
- The docs' two-argument form `ptr_offset(ptr, bytes)` **does not exist** — you get
  `ptr_offset() expects 3 arguments (ptr, offset, element_size)`.
- Byte addressing is `ptr_offset(p, byteoff, 1)`; element addressing is `ptr_offset(p, i, 4)`. **Measured identical in speed** (408 vs 402 ms, `bench_float_storage`) — use whichever reads better.
- **The first argument must be a `ptr`, never a `buffer`**: `ptr_offset() first argument must be a ptr`. Convert with `buffer_ptr(b)` — and **hoist that call out of the loop** (511 ms → 401 ms, `bench_float_storage`).
- `ptr_read_*` / `ptr_write_*` / `ptr_deref_*` **do** accept a `buffer` directly, and then bounds-check the whole typed access (`ptr_write_f64` on a `buffer(4)` throws `access exceeds buffer length`). But since you cannot offset a buffer, this only ever addresses element 0. In practice: `let base: ptr = buffer_ptr(b);` once, then `ptr_offset(base, ...)`.
- Raw `ptr` has **no** bounds check: `ptr_write_f64(alloc(4), 1.0)` silently corrupts the heap.
- `talloc(f32, 4)` returns a `ptr` (typed allocation helper), `sizeof(f32)` = 4, `sizeof(ptr)` = 8, `ptr_to_buffer(p, n)` wraps a `ptr` in a bounds-checked `buffer`, `b.slice(a, b)` is a zero-copy buffer view.

---

<a name="4-float-storage"></a>
## 4. The fastest way to hold a large array of floats — **measured**

`bench_float_storage.hml` — 1 000 000 elements, 10 write passes + 10 read passes (20 M ops per row), `hemlockc -O3`:

```
dyn array           : 240 ms      <- FASTEST
typed array<f64>    : 273 ms      <- same, within noise across runs
buffer bounds-check : 258 ms      (single-element, shows the entry-point cost only)
raw ptr[i] u8 index : 267 ms
raw ptr f64         : 312 ms
buffer[i] u8 index  : 332 ms
buffer hoisted ptr  : 401 ms
raw ptr f32 (es=4)  : 402 ms
raw ptr f32         : 408 ms
buffer_ptr() in loop: 511 ms      <- SLOWEST (buffer_ptr() called per element)
```

**Answer:** for *speed*, a plain Hemlock **`array`** is the fastest large float container — about **1.7x faster than `ptr` + `ptr_read_f32`/`ptr_write_f32`**. Typed (`array<f64>`) and untyped arrays are indistinguishable; the type annotation buys you a runtime element-type check, not speed.

For *memory* (and for anything you must hand to C), use `buffer`/`ptr` and accept ~10–70 % slower element access:

| Container | bytes/element (f64 data) |
|---|---|
| `array` / `array<f64>` | **16** |
| `buffer` / `ptr` of f64 | 8 |
| `buffer` / `ptr` of f32 | **4** |
| `buffer` / `ptr` of u8 | **1** |

**Practical Nightshade policy**
- Per-frame vertex/transform scratch that stays inside Hemlock → `array<f64>`, preallocated once with `reserve()`, reused via `clear()`.
- The SDL vertex buffer → one `alloc(max_tris * 3 * 20)` allocated **once at startup**, written with `ptr_write_f32`/`ptr_write_u8`. There is no alternative; SDL needs the raw address.
- Voxel chunks, heightmaps, lightmaps, collision grids → `buffer`/`ptr` of `u8`/`u16`.

---

<a name="5-unboxing"></a>
## 5. Unboxing — the single biggest compiled-performance lever

The compiler can give a variable a **native C type** (`double`, `int32_t`, …) instead of a 16-byte `HmlValue`, which turns `acc = acc + x` from a runtime-dispatched `hml_binary_op()` into a machine instruction. This is worth **~2x** on arithmetic-heavy code. It is also **extremely fragile**, and there is no diagnostic when it fails.

### The exact rules (read from `src/backends/compiler/type_unboxing.c`, `type_escape_analysis.c`, `codegen_stmt.c`)

A `let` is unboxed **only if all** of these hold:

1. It is a **function-local** `let` (top-level/"main" variables are **never** unboxed — verified: `f64 top-level main : 201 ms` vs `169 ms` in a function, `bench_unboxing`).
2. It has a primitive annotation (`i8..u64`, `f32`, `f64`, `bool`) **or** an initializer whose type is inferable.
3. Its initializer is *structurally* unboxable: only number/bool/rune literals, identifiers, and `+ - * / % & | ^ << >>`, unary, `++`/`--`, ternary over those. **Any function call, array index, or property access in the initializer kills it.**
4. It never **escapes** in any later statement of the same block. All of these are escapes:
   - `return x;` — **a bare identifier return escapes.**
   - `[..., x, ...]` or `{ f: x }` — storing it into an array/object literal.
   - `x[i]` — using it as an array.
   - **Any `fn(...) {...}` literal anywhere later in the block** (escape analysis is conservative: `EXPR_FUNCTION => escapes`).
   - Passing it as a plain argument (`f(x)`) is **not** an escape — arguments are boxed copies.
5. **Its name does not collide with any top-level variable in the entry file.** (`codegen_stmt.c` checks `codegen_is_main_var(ctx, name)` **by name only**, with no scope awareness.)

Additionally: **function parameters are never unboxed** (`type_check.c:244 — "Function parameters cannot be unboxed"`), and closure-captured variables are never unboxed.

### The measurements

`bench_escape.hml`, 50 M iterations of `acc = acc + k`:

```
f64 'return acc;'            : 430 ms   <- boxed
f64 copy-out (native)        : 241 ms   <- native double     1.78x faster
i32 'return acc;'            : 369 ms   <- boxed
i32 copy-out (native)        : 248 ms   <- native int32_t    1.49x faster
f64 closure later in block   : 425 ms   <- boxed (a `let g = fn(z){...}` after the loop)
f64 param as operand         : 363 ms   <- boxed
f64 param copied to a local  : 250 ms   <- native           1.45x faster
```

`bench_globalname.hml`, 50 M iterations — **two byte-identical functions, only the variable name differs**:

```
local named 'acc'  (a top-level `let acc = 0;` exists) : 423 ms
local named 'g_sum' (no collision)                     : 222 ms   <- 1.9x faster
```

### The patterns you must write

```hemlock
// GOOD — every hot local is native
fn integrate(p0: f64, v0: f64, dt0: f64, n0: i32): f64 {
    let p: f64 = p0;          // copy params into locals  (params are never unboxed)
    let v: f64 = v0;
    let dt: f64 = dt0;
    let n: i32 = n0;
    for (let i = 0; i < n; i++) { p = p + v * dt; }
    let out: f64 = p;         // copy-out: `return p;` would escape and re-box p
    return out;
}
```

```hemlock
// BAD — all four mistakes
let p = 0.0;                  // top-level name `p` poisons EVERY local `p` in the program
fn integrate(p: f64, v: f64, dt: f64, n: i32): f64 {
    for (let i = 0; i < n; i++) { p = p + v * dt; }   // params: never unboxed
    let log = fn(m) { print(m); };                    // a closure literal in scope: escape
    return p;                                          // bare-ident return: escape
}
```

> **Do not try to dodge the escape with `return acc + 0.0;` or `return acc * 1.0;`.** The AST optimizer folds identity operations away, so both fold straight back to `return acc;`. Verified. Use a separate `let out: f64 = acc; return out;`.

### How to check whether it worked

```bash
hemlockc -c yourfile.hml --emit-c /tmp/out.c
grep -E '^\s+(double|int32_t|int64_t|float|uint8_t) <varname> ' /tmp/out.c
```
`double acc = hml_to_f64(...)` = unboxed. `HmlValue acc = hml_convert_to_type(...)` = boxed. **Add this grep to CI for the ~10 hottest variables in the renderer.**

### Once unboxing fires, the numeric type barely matters

`bench_numeric.hml`, 50 M iterations, **all accumulators verified unboxed** (native C locals in the emitted C):

```
i32  s = s + 1   (overflow-checked) : 209 ms
i32  s++         (wraps, no check)  :  89 ms     <- 2.3x faster
u32  s = s + 1   (wraps)            : 248 ms
i64  s = s + 1   (overflow-checked) : 258 ms
f64  s = s + 1.0                    : 215 ms
f64  s = s + 1.5 * 2.0              : 218 ms
```

All types are within ~25 % of each other. The **only** big lever here is `++` vs `+ 1` on a signed integer: `+` emits Hemlock's checked-add (which throws on overflow), `++` is defined to wrap and skips the check entirely. Use `x++` for counters that cannot legitimately overflow.

(If you ever measure a 2x gap between `i32` and `u32`/`i64` accumulators, you are looking at a *boxed* loop — go back to §5 and find the escape.)

### What is *not* unboxed even with perfect annotations

Boxed expressions have inline fast paths only for `i32`/`i64`
(`hml_both_i32(a,b) ? hml_i32_add(a,b) : ... : hml_binary_op(...)`); any boxed
`f64`/`u32`/`f32` operand falls all the way through to the runtime dispatcher.
So the penalty for *failing* to unbox is worst for float code — which is most of a renderer.

---

<a name="6-functions"></a>
## 6. Functions, closures, methods, struct-like patterns

### Call costs (bench_hotpath, 5 M calls, net of the 25 ms empty-loop baseline)

| Form | ns/call |
|---|---|
| no call (arithmetic inlined by hand) | 0 |
| `@inline` annotated `fn` | **9.4** (identical to plain — see below) |
| plain named `fn(a, b)` | **9.6** |
| closure held in a variable, `f(a, b)` | **13.8** |
| `obj.method(a, b)` | **29.2** — **3x a plain call** |
| FFI `extern fn` with 1 f64 arg | **25.8** (`bench_ffi`) |
| FFI `extern fn` with 2 f64 args | **33.2** |

**`@inline` is a no-op in practice.** It emits GCC `__attribute__((always_inline))` on a function that GCC then refuses to inline, and the build prints
`warning: 'always_inline' function might not be inlinable [-Wattributes]`.
Hemlock's own AST-level inliner only fires for very small bodies at depth ≤3 and is not driven by the annotation. **If you need it inlined, write it inline.**

### Object-method / "class" patterns

```hemlock
let counter = {
    n: 0,
    fn inc(): i32 { self.n = self.n + 1; return self.n; },
    fn get(): i32 => self.n,
};
```
Works identically in both backends. `self` binds implicitly. **But `obj.method()` is 3x a free function call and each `self.field` is a 14 ns hash lookup.** Use methods for cold/structural code (systems, managers, UI), never inside a per-vertex or per-entity loop.

### Struct-like patterns

```hemlock
export define Vertex { x: f64, y: f64, z: f64, u?: 0.0, v?: 0.0 }
let a: Vertex = { x: 1.0, y: 2.0, z: 3.0 };   // u/v auto-filled from the defaults
```
`define` gives you *shape checking and optional-field defaults*, **not** a packed struct. A `Vertex` is still a hash-backed object at ~84–240 ns to construct. `define` is for API clarity; it costs nothing extra and buys nothing at runtime.

### Entity storage — measured (bench_entities, 2000 entities × 200 ticks)

```
A array-of-objects   : 0.265 ms/tick
B SoA hemlock arrays : 0.150 ms/tick   <- FASTEST
C SoA raw f64 ptrs   : 0.370 ms/tick
D interleaved buffer : 0.320 ms/tick
```

Array-of-objects is *acceptable* for a couple of thousand entities **as long as you do not reallocate the objects each tick** — the win here comes from mutating existing objects in place. Struct-of-arrays with Hemlock `array`s is 1.8x faster still and is the recommended default for anything with >1000 members.

### Closures

- Creating a closure literal per iteration costs ~14 ns and, critically, **de-optimizes the entire enclosing block** (see §5 rule 4). Hoist closures out of loops; better, don't use them in hot code at all.
- Captured variables are stored as `HmlValue` in the closure environment and can never be native.
- Captures are live-shared with the enclosing scope (writes visible both ways) as of 2.6.0.

---

<a name="7-numerics"></a>
## 7. Numeric semantics: overflow, division, casts, folding traps

### Overflow policy

| Operation (promoted type) | Behaviour |
|---|---|
| `i32`, `i64` — `+ - *` and unary `-` | **throws** a catchable `"Integer overflow: ..."` |
| `i8`, `i16` same-type arithmetic | wraps |
| `u8`, `u16`, `u32`, `u64` | wraps |
| `++` / `--` (any integer type) | **always wraps**, preserving type |
| signed `MIN % -1` | defined as `0` |

Notes that bite:
- Promotion decides: `i8 + 1` promotes to `i32` (the literal's type) and **is** checked; `i8 + i8` stays `i8` and wraps.
- `x += 1` expands to `x = x + 1` and therefore throws on `i32` overflow.
- Constant expressions follow the same rules; `2147483647 + 1` throws at *runtime*, not compile time.
- **`++`/`--` are the explicit wrapping tool.** For per-frame counters that may wrap (frame index, RNG state), use `x++` or `u32`.
- Measured (`bench_numeric`, 50 M iterations, unboxed): `s++` **89 ms** vs `s = s + 1` **209 ms** on an `i32` — **2.3x**, because `++` skips the overflow check that `+` must perform.

### Division

`/` always produces `f64`… **except when the constant folder eats it.** Verified in *both* backends:

```hemlock
let a: i32 = 7; let b: i32 = 2; let one: i32 = 1;
typeof(a / b)    // "f64"  -> 3.5     correct
typeof(a / one)  // "f64"  -> prints 7   (value is exact, type is f64)
typeof(a / 1)    // "i32"  -> 7        <-- literal 1 divisor: folded to identity, STAYS i32
typeof(7 / 2)    // "f64"  -> 3.5
```

Use `divi(a, b)` from `@stdlib/math` for truncating integer division. Cost (5 M iterations, `bench_misc`): `a / b` **89 ms**, `divi(a,b)` **98 ms**, multiply-by-precomputed-reciprocal **78 ms**. Division is not specially expensive here — reciprocal-multiplication saves ~12 %, worth it only in the innermost projection loop.

### **Identity-folding trap — this one will cost you a day**

The AST optimizer folds `x * 1.0`, `x + 0.0`, `x - 0`, `x / 1`, `x * 1` to `x` **before type promotion is applied**. Two real consequences:

```hemlock
let a: array<f64> = [];
let i: i32 = 3;
a.push(i * 2.0);   // ok   -> f64
a.push(i * 1.0);   // THROWS "Type mismatch in typed array" — folded to `i`, still i32
```

```hemlock
return acc + 0.0;  // folds to `return acc;` -> acc escapes -> loses unboxing (see §5)
```

**Never use `* 1.0` / `+ 0.0` as an int→float conversion.** Use `f64(i)`. Same for `i32(x)` when you want truncation.

### Casts

- `i32(3.99)` truncates to `3`. `f64(i)` widens. `i32("42")` parses.
- `let n: i32 = "42";` is a **compile error** in `hemlockc` (`cannot initialize 'n' of type 'i32' with 'string'`) and a runtime error in the interpreter.
- `let s: string = 42;` is accepted by both (no error). Do not rely on annotations as a type wall.
- Promotion ladder: `i8 → u8 → i16 → u16 → i32 → u32 → i64 → u64 → f32 → f64`; `i64/u64 + f32 → f64`.
- Casting cost: `i32(x)` ≈ `floor(x)` ≈ **16 ns/call** (5 M iterations, net of baseline).

### Math library costs (5 M iterations, net of a 23 ms baseline, `bench_misc`)

| Call | ns/call |
|---|---|
| `sqrt(x)` | **14.4** |
| `floor(x)` | **14.2** |
| `i32(x)` | **16.4** |
| `sin(x)` + `cos(x)` (two calls) | **48.8** (≈24 each) |
| `clamp(v, lo, hi)` | **19.6** |
| hand-written `if (v<lo){v=lo;} if (v>hi){v=hi;}` | **14.0** |

`@stdlib/math`'s exports are thin aliases onto builtins (`export let sqrt = __sqrt;`), so a named import costs one ordinary call. Inline your own `clamp`/`min`/`max`/`abs` for the innermost loops; everything else is fine.

---

<a name="8-errors-memory"></a>
## 8. Error handling, `defer`, and manual memory

### Costs (5 M iterations unless noted, `bench_misc`)

| Construct | Time | Delta |
|---|---|---|
| plain loop | 20 ms | baseline |
| `try { ... } catch (e) { ... }` around the body | 74 ms | **+10.8 ns per entry** |
| calling a function (no `defer`) | 41 ms | baseline |
| **calling a function that contains `defer f();`** | **394 ms** | **+70 ns per call** |
| `throw` + `catch`, 200 k iterations | 7 ms | ~35 ns per throw |
| `"a" + i + "b"`, 200 k iterations | 21 ms | **105 ns per concat** |
| `` `template ${i}` ``, 200 k iterations | 33 ms | **165 ns per interpolation** |

> **Rule E1: `defer` is banned in per-frame code.** 70 ns per call, on *every* call to a function that merely mentions it. Use it in setup/teardown only.
> **Rule E2: no `try/catch` inside per-vertex loops.** Validate at the boundary.
> **Rule E3: build HUD strings once per second, not once per frame.** A template string is ~165 ns; a 20-line debug overlay rebuilt every frame is ~3–5 µs, which is fine, but rebuilding hundreds is not.

`defer` syntax note: `defer <expression>;` only. `defer { ... }` is a **parse error** (`Expect ';' after defer statement`). Wrap the block in a named function.

### Memory: what leaks and what does not

`bench_leaks.hml` runs 600 000 iterations of each construct and reads `/proc/self/statm`:

```
object literal        : delta 0 KB     <- no leak
array literal         : delta 0 KB     <- no leak
string concat         : delta 0 KB     <- no leak
closure literal       : delta 0 KB     <- no leak
alloc + free          : delta 0 KB     <- no leak
buffer, no explicit free : delta 0 KB  <- refcount reclaims it
for k in obj.keys()   : delta 0 KB     <- fixed in 2.5.0
obj.field = [..]      : delta 0 KB     <- fixed in 2.5.0
throw/catch w/ heap locals : delta 112 320 KB   <<< LEAKS ~187 B per throw
alloc WITHOUT free    : delta  84 480 KB        <<< leaks, as designed
```

Isolated further (500 k iterations each):

```
try + throw, no heap local in the frame   : +192 KB      (negligible)
try + heap local + throw                  : +93 696 KB   (~192 B/throw)
throw from a callee (indirect)            : +93 696 KB   (~192 B/throw)
try + heap local, NO throw                : +0 KB
```

**This is the known `throw_indirect` limitation documented in CHANGELOG 2.5.0 "Known limitations", and it is broader than the changelog implies — it also bites the directly-throwing frame.** `hml_throw` `longjmp`s past the C frames, so any array/object/string local in a skipped frame is never released.

> **Rule E4: exceptions are not a control-flow mechanism in Nightshade.** Any code path that can throw thousands of times per session must be rewritten to return sentinel values. Reserve `throw` for genuinely fatal, once-per-run conditions.

### Manual memory rules

- `alloc(n)` → **you must `free()`**. Nothing else will.
- `buffer(n)`, `array`, `object`, `string`: refcounted, released at scope exit / reassignment. `free()` is only for *early* release.
- **Do not `free()` a `buffer` that is still reachable from a top-level `let`** — historically a double-free (CHANGELOG 2.5.3); glibc tolerates it, macOS aborts. Let scope/refcount handle top-level buffers.
- `realloc(p, n)` may move; always reassign `p = realloc(p, n)` and check for `null`.
- Tasks share `ptr`s but copy primitives — `join()` before `free()`.
- Sanity check a build with `valgrind` or by watching `/proc/self/statm` over 10 000 frames; add that as a CI smoke test.

---

<a name="9-hemlockc"></a>
## 9. `hemlockc`: invocation, flags, build times

```
hemlockc [options] <input.hml>

 -o <file>         output executable (default a.out)
 -O<0..3>          optimization level, default 3  (passed to gcc as -O<n> -fwrapv)
 -c                emit C only, don't compile
 --emit-c <f>      write the generated C to <f>
 -k, --keep-c      keep the temp C file
 --cc <path>       C compiler (default gcc)
 --runtime <p>     path to libhemlock_runtime
 --check           static analysis only (type + borrow check), no build
 --no-type-check   disable type checking (also disables some optimizations)
 --strict-types    warn on implicit `any`
 --no-borrow-check / --borrow-strict / --borrow-error
 --no-lint / --lint-strict / --lint-error
 --no-stack-check  drop stack-overflow guards (faster, unsafe)
 --static          static-link volatile native libs (DEFAULT on Linux)
 --dynamic         dynamic link (default on macOS; needed for *runtime* ffi_open)
 --sandbox [DIR]
 --target wasm [--threads]
 -v, --verbose
```

### Build times (wobbleweed `examples/walk_gpu.hml`, 1493 lines across 9 modules → 14 200 lines of C)

| Flag | wall clock |
|---|---|
| `hemlockc --check` | **0.00 s** |
| `-O0` | **0.53 s** |
| `-O1` | 1.70 s |
| `-O2` | 3.17 s |
| `-O3` | 3.26 s |

Hemlock's own codegen is ~7 ms; **gcc dominates entirely.**

### Runtime cost of the optimization level (`bench_frame`, 3000 tris × 200 frames)

| | object style | flat locals |
|---|---|---|
| `-O0` | 15.43 ms/frame | 4.95 ms/frame |
| `-O1` | 11.46 ms/frame | 2.90 ms/frame |
| `-O3` | 11.25 ms/frame | 2.80 ms/frame |

> **Rule B1: build the dev loop with `-O1`** — within 3 % of `-O3` at half the build time.
> **Rule B2: ship with `-O3`.** Always. Interpreted Nightshade is not a product.
> **Rule B3: run `hemlockc --check` on save** — it is instantaneous and catches arity/annotation errors.

Note: `-O` also gates Hemlock-level unboxing (`ctx->optimize`), but the unboxing analysis still runs at `-O0`; the measured `-O0` penalty is mostly gcc's.

### Static checking: what it actually catches

`hemlockc` type checking is **shallow**. Verified: the following are compile errors —

- `let n: i32 = "42";` → `cannot initialize 'n' of type 'i32' with 'string'`
- `f(1)` where `fn f(a, b)` → `too few arguments to 'f': expected 2, got 1`
- single-argument `substr()` arity

…and the following **compile clean** and fail (or silently misbehave) at runtime:

- `f(3.7)` into `fn f(x: i32)` (silently truncates to 3)
- `a.push(4.5)` into `array<i32>` (runtime "Type mismatch in typed array")
- a function annotated `: i32` with no `return` (runtime "Cannot convert type to target type")
- `o.y` on an object without `y` (runtime "Object has no field")
- out-of-range `ptr` access (silent corruption)
- integer overflow (runtime throw)

> **Rule B4: annotations are optimization hints and runtime assertions, not a type system.** Do not rely on `hemlockc` to catch shape errors. Write tests.

---

<a name="10-parity"></a>
## 10. Interpreter vs compiler: verified differences

### Speed (`bench_interp_vs_compiled.hml`, N = 300 000, same file both ways)

| Kernel | `hemlock` | `hemlockc -O3` | speedup |
|---|---|---|---|
| native arithmetic | 64 ms | **1 ms** | **~60x** |
| object alloc + read | 101 ms | 38 ms | 2.7x |
| array push + index | 129 ms | 11 ms | 11.7x |
| ptr write + read | 197 ms | 15 ms | 13.1x |
| stdlib `sqrt()` calls | 91 ms | 7 ms | 13x |

The speedup is *very* uneven. Object-heavy code barely improves (2.7x) because the cost is runtime allocation, which both backends share. **The measured 52 → 283 fps for wobbleweed is entirely consistent with this.** If Nightshade is object-heavy, compiling will not save it.

### Behavioural differences found

1. **Narrow-unsigned overflow diverges.**
   ```hemlock
   fn wrap_u8(n: i32): u8 { let a: u8 = 250; for (let i=0;i<n;i++) { a = a + 1; } let o: u8 = a; return o; }
   wrap_u8(10)
   ```
   - interpreter: **throws** `Value 260 out of range for u8 [0, 255]`
   - `hemlockc -O3`: **silently wraps to 4**

   Root cause: the compiler stores the unboxed local as a native `uint8_t`; the interpreter range-checks each assignment against the annotation. `u32` agrees between the two. **Do not use `u8`/`u16` annotated accumulators.**

2. **`array.sort()` recursion depth is unbounded in the compiled runtime.** Sorting a presorted 200 000-element array **segfaults** (`hml_array_sort` → naive recursive quicksort, `runtime/src/builtins_array.c:829`).

3. **`throw` leaks heap locals when compiled** (§8). The interpreter does not.

4. From CHANGELOG 2.6.x, still worth knowing: interpreted `kill()` throws on failure while compiled returns `-1`; compiled method dispatch used to hijack `.read_u8()`/`.write_u8()`/`.close()` on user objects (fixed in 2.8.0 — **but avoid naming your own methods after buffer builtins anyway**).

### Behaviour verified **identical** (compiled == interpreted == expected)

Object method shorthand + `self`; nested closures; `define` with optional-field defaults; spread `{...a, b: 2}`; `match` with OR-patterns and guards; `enum`; default & named arguments; `ref` parameters; `array.sort()`/`map()`; bracket keys with coercion + `.keys()`; `defer`; `for-in`; `type` aliases for function types; `buffer.slice()`; identity constant folding (`i * 1.0` → `i32` in **both**); `a / 1` staying `i32` in both; `spawn()` rejecting non-`async` functions in both.

> The project maintains 259 parity tests and a `make parity` gate. Parity is genuinely good — the exceptions above are narrow but real.

---

<a name="11-landmines"></a>
## 11. Landmines found in this recon (read this section twice)

### 🔴 L1 — `array.sort(comparator)` is quadratic on nearly-sorted data, and it crashes

`hml_array_sort` (`runtime/src/builtins_array.c:837`) is a textbook Lomuto quicksort with a **last-element pivot, no median-of-three, no introsort fallback, no depth cap**, recursing on both halves.

`bench_sort.hml`, N = 3000:

```
array.sort(closure) on freshly-shuffled objects : 2.55 ms/frame
array.sort(closure) on an ALREADY-SORTED array  : 159.35 ms/frame   <<< 62x worse
array.sort() (no comparator) on random f64 keys : 0.20 ms/frame
array.sort() (no comparator) on presorted f64   : 5.25 ms/call
bucket sort, 1024 buckets, hand-written         : 0.35 ms/frame     <<< USE THIS
insertion sort, random input                    : 66.65 ms/frame
insertion sort, presorted input                 : 0.10 ms/frame
```
and:
```
array.sort() on a presorted 200 000-element array -> SIGSEGV (stack overflow)
```

**Why this is a Nightshade emergency:** a painter's-algorithm renderer sorts triangles by depth *every frame*, and between frames the camera barely moves, so **the input is always nearly sorted** — exactly quicksort's worst case. `wobbleweed/src/geom.hml:batch_flush()` does precisely this:

```hemlock
tris.sort(fn(p, q) { if (p.depth > q.depth) { return 0 - 1; } ... });
```

At 3000 triangles that is **160 ms/frame = 6 fps**. This is almost certainly the ceiling that will bite you the moment the scene stops being trivial.

**Fix:** replace it with a bucket/radix sort on a quantized depth key. Reference implementation in `tools/bench/bench_sort.hml:bucket_sort()` — O(n), no comparator calls, 0.35 ms/frame at 3000 triangles, and it is *stable-enough* for painter ordering. Preallocate the `counts` and `order` arrays once at startup.

### 🔴 L2 — object allocation dominates the frame

`bench_frame.hml`, 3000 triangles × 200 frames, three implementations of the *same* transform → project → pack-vertex pipeline:

```
A object style (v3()/mat_apply() returning fresh objects, wobbleweed today)
                                : 11.36 ms/frame   <- 68% of the 16.6 ms budget
B flat native locals + helper fn :  2.87 ms/frame   <- 4.0x faster
C flat native locals, fully inlined vertex writes : 2.04 ms/frame  <- 5.6x faster
```

An object literal costs **84 ns** (3 fields) to **240 ns** (8 fields). Wobbleweed's `mat_apply()` alone allocates one object per vertex; `to_screen()` allocates another; `cv()` another. That's 3 objects × 3 vertices × 3000 triangles = **27 000 allocations per frame ≈ 3.4 ms** in allocation alone.

**Fix:** the projection/packing inner loop must use native `f64` locals only. Keep the object-returning `vec.hml` API for setup, editor tooling and gameplay, and write a separate flat kernel for the per-frame path.

### 🔴 L3 — a top-level variable name silently de-optimizes every same-named local

See §5. A single `let acc = 0;` at file scope makes every function-local `acc` in the entire program boxed — **1.9x slower**, no warning.

**Fix (mandatory coding standard):** every top-level/module-level variable gets a `g_` prefix (`g_frame`, `g_world`, `g_input`). Locals never use `g_`. Enforce with a grep in CI.

### 🟠 L4 — `return <bare identifier>;` costs you unboxing

See §5. `return acc;` → boxed (1.8x slower). `let out: f64 = acc; return out;` → native. And `return acc + 0.0;` does **not** work as a dodge — it's constant-folded back.

### 🟠 L5 — `defer` costs ~70 ns on **every call** to the enclosing function

10x the cost of the call itself. Never in per-frame code.

### 🟠 L6 — `throw` leaks ~192 bytes of heap locals per throw (compiled only)

600 k throws = 112 MB. Don't use exceptions for flow control.

### 🟠 L7 — `ptr_offset` is documented wrong

Three arguments, first must be a `ptr` (not a `buffer`). The official `docs/reference/builtins.md` shows a two-argument form that does not exist.

### 🟠 L8 — `x * 1.0` / `x + 0.0` / `x / 1` are folded to `x` and keep the integer type

Breaks typed arrays, breaks the unboxing dodge, breaks any "convert to float" idiom. Use `f64(x)`.

### 🟡 L9 — `import * as ns` costs 3x on every call

### 🟡 L10 — `obj.method()` costs 3x a free function call

### 🟡 L11 — `u8`/`u16` annotated accumulators diverge between backends (throw vs wrap)

### 🟡 L12 — `@inline` does nothing (gcc refuses; you get a build warning)

### 🟡 L13 — `s = s + 1` is 2.3x `s++` on a signed integer (overflow check)

### 🟡 L14 — `read_file()` returns `""` for procfs and other zero-stat files; use `open()` + `.read()`

---

<a name="12-rules"></a>
## 12. PERFORMANCE RULES

Each rule cites the benchmark file and the measured numbers that justify it. **"Hot" means executed more than ~1000 times per frame.**

### Build

| # | Rule | Evidence |
|---|---|---|
| B1 | Ship compiled with `hemlockc -O3`. Never ship interpreted. | 1–60x, `bench_interp_vs_compiled` |
| B2 | Develop with `-O1`: 3 % slower than `-O3`, 2x faster to build. | 1.70 s vs 3.26 s; 2.90 vs 2.80 ms/frame, `bench_frame` |
| B3 | Run `hemlockc --check` on every save (0.00 s). | §9 |
| B4 | Grep the emitted C (`--emit-c`) in CI for `double`/`int32_t` on the ~10 hottest locals. | §5 |

### Per-frame loops — **never do this**

| # | Never | Instead | Evidence |
|---|---|---|---|
| N1 | **`array.sort(cmp)` on per-frame data** | bucket sort on a quantized key | 159.35 → 0.35 ms/frame, `bench_sort` |
| N2 | **Allocate an object per vertex/triangle/particle** | native `f64` locals; write straight to the vertex buffer | 11.36 → 2.04 ms/frame, `bench_frame`; 84–240 ns/object, `bench_hotpath` |
| N3 | `defer` in any function called per frame | explicit cleanup at the end | +70 ns/call, `bench_misc` |
| N4 | `try`/`catch` inside a per-element loop | validate at the boundary | +10.8 ns/entry, `bench_misc` |
| N5 | `throw` as control flow | sentinel return values | 192 B leaked per throw, `bench_leaks` |
| N6 | `import * as ns` + `ns.f()` on a hot path | named import | 644 → 213 ms/20 M, `bench_module` |
| N7 | `obj.method()` per element | free function taking explicit args | 29.2 vs 9.6 ns, `bench_hotpath` |
| N8 | Create a closure literal inside a loop | hoist it out (or delete it) | 14 ns + kills unboxing of the whole block, `bench_escape` |
| N9 | Build template strings per frame | build once per second, cache | 165 ns each, `bench_misc` |
| N10 | `buffer_ptr(b)` inside the loop | hoist to `let base: ptr = buffer_ptr(b);` | 511 → 401 ms, `bench_float_storage` |
| N11 | `u8`/`u16` annotated accumulators (backends diverge: throw vs wrap) | `i32`, `u32` or `f64` | §10.1 |
| N12 | `x * 1.0` to make a float | `f64(x)` | folded away; throws in typed arrays |
| N13 | `alloc()`/`buffer()` per frame | allocate once at startup, reuse | 15–50 ns each + fragmentation |
| N14 | `a.push()` to rebuild a per-frame list from empty | `a.clear()` then push into the retained capacity | 89 → 76 ms/5 M, `bench_hotpath` |

### Per-frame loops — **always do this**

| # | Always | Evidence |
|---|---|---|
| A1 | Copy every function parameter you use more than once into a typed local: `let n: i32 = n0;` | 363 → 250 ms/50 M, `bench_escape` |
| A2 | Return via a copy: `let out: f64 = acc; return out;` — never `return acc;` | 430 → 241 ms/50 M, `bench_escape` |
| A3 | Prefix every top-level variable with `g_`; never reuse those names as locals | 423 → 222 ms/50 M, `bench_globalname` |
| A4 | Hoist matrix elements into named locals once per frame (`let m0: f64 = m[0];` …) | part of the 4x in `bench_frame` |
| A5 | Use `array`/`array<f64>` for hot random-access float data | 240 vs 408 ms, `bench_float_storage` |
| A6 | Use `buffer`/`ptr` of `u8`/`u16` for voxel/heightmap/lightmap bulk data | 1.03 vs 16.03 bytes/block, `bench_voxel` |
| A7 | Use struct-of-arrays for >1000 entities | 0.150 vs 0.265 ms/tick, `bench_entities` |
| A8 | Preallocate the SDL vertex buffer once: `alloc(MAX_TRIS * 3 * 20)` | wobbleweed `geom.hml` already does this — keep it |
| A9 | Hand-inline `clamp`/`min`/`max`/`abs` in the innermost loop | 19.6 → 14.0 ns, `bench_misc` |
| A10 | Cache `a.length` in a typed local before the loop (harmless, and it enables unboxing of the bound) | 43 vs 44 ms/3 M — free, do it for the unboxing side-effect |
| A11 | Use `x++` instead of `x = x + 1` for counters that can't overflow-trap | 89 vs 209 ms/50 M, `bench_numeric` |
| A12 | Batch FFI: one `SDL_RenderGeometry` per texture run, not per triangle | 26–33 ns/FFI call, `bench_ffi` — 3000 individual calls would be 0.1 ms; per-vertex would not |

### Rules that are *not* worth obeying (measured, negligible)

- `for (v in a)` vs `for (let i = 0; i < len; i++)` — 49 vs 43 ms per 3 M. Use whichever is clearer.
- `a.reserve(n)` before a push loop — 87 vs 89 ms per 5 M. Reserve for memory predictability, not speed.
- `ptr_offset(p, i*4, 1)` vs `ptr_offset(p, i, 4)` — identical.
- `divi()` vs `/` vs reciprocal-multiply — within 20 % of each other.
- `array<f64>` vs untyped `array` — within noise.
- `@inline` — literally a no-op.

---

<a name="13-budget"></a>
## 13. A frame budget for Nightshade

Target: **60 fps = 16.6 ms/frame.** Baseline from the brief: ~530 triangles at 283 fps compiled. Budget 2000–3000 triangles.

Measured cost of a 3000-triangle vertex pipeline written correctly (`bench_frame`, variant C):

| Stage | Budget | Basis |
|---|---|---|
| Transform + project + pack 3000 triangles (flat locals) | **2.0 ms** | `bench_frame` C |
| Depth sort 3000 triangles (bucket sort) | **0.35 ms** | `bench_sort` |
| Entity/AI/physics tick, 2000 entities (SoA) | **0.15 ms** | `bench_entities` |
| Voxel chunk meshing amortized (1 chunk sweep of 32³) | **0.7 ms** | `bench_voxel`, 144 ms / 200 sweeps |
| SDL FFI (clear, ~20 draw calls, present) | **< 0.01 ms** + GPU | `bench_ffi` |
| HUD strings (rebuilt at 4 Hz) | **~0.00 ms** | `bench_misc` |
| **Total CPU** | **≈ 3.2 ms** | leaves ~13 ms for SDL/GPU/input/audio |

The same pipeline written in the naive object style:

| Stage | Cost |
|---|---|
| Transform + project + pack, object style | 11.4 ms |
| Depth sort with `array.sort(closure)` on nearly-sorted data | 160 ms |
| **Total** | **171 ms/frame = 5.8 fps** |

**The difference between a shipping game and an unshippable one is entirely in §11 L1 and L2.**

---

<a name="14-bench-index"></a>
## 14. Benchmark index

All in `/home/nbeerbower/Projects/nightshade/tools/bench/`. Build any with `hemlockc -O3 <file> -o /tmp/b && /tmp/b`, or run everything with `./run_all.sh`.

| File | Answers |
|---|---|
| `bench_float_storage.hml` | array vs typed array vs buffer vs raw ptr for 1 M floats |
| `bench_unboxing.hml` | do params / top-level vars / typed locals unbox? |
| `bench_escape.hml` | `return acc;`, closures-in-scope, param operands — the escape-analysis cliff |
| `bench_globalname.hml` | a top-level name collision de-optimizing a local |
| `bench_hotpath.hml` | allocation, field access, call kinds, iteration, array growth |
| `bench_frame.hml` | full 3000-triangle vertex pipeline: object style vs flat vs inlined; painter sort |
| `bench_sort.hml` | `array.sort` quadratic blowup vs bucket sort vs insertion sort |
| `bench_entities.hml` | AoS objects vs SoA arrays vs SoA ptrs vs interleaved buffer |
| `bench_voxel.hml` | chunk storage footprint (16 B vs 1 B per block) and sweep speed |
| `bench_misc.hml` | math calls, division, try/defer/throw, strings, allocation |
| `bench_numeric.hml` | cost of each numeric type when unboxed; `++` vs `+ 1` |
| `bench_module.hml` (+ `module_lib.hml`) | named vs namespace imports, imported constants |
| `bench_ffi.hml` | `extern fn` call overhead |
| `bench_leaks.hml` | RSS growth per construct (finds the `throw` leak) |
| `bench_interp_vs_compiled.hml` | the same file under `hemlock` and `hemlockc` |
| `run_all.sh` | build + run everything |

### Reproduction environment

- `hemlockc 2.8.2 (built Jul 25 2026)`, `hemlock 2.8.2`, gcc, Linux 6.8 x86-64.
- Timings via `@stdlib/time::time_ms()`, wall clock, single run each. Expect ±5 % run-to-run; every ratio quoted above is ≥1.4x and reproduced across at least two runs.
- Absolute ns/op figures include Hemlock's loop overhead (~4–5 ns/iteration for a boxed loop, ~0.5 ns unboxed); treat them as *relative* guidance.

---

## Appendix A — Nightshade coding standard (derived from the above)

1. Top-level variables are `g_`-prefixed. Always.
2. Every hot function starts by copying its parameters into typed locals.
3. Every hot function ends with `let out: <T> = <acc>; return out;`.
4. No `fn(...) {}` literal inside any function that contains a hot loop.
5. No object or array literal inside a per-frame loop.
6. No `defer`, `try`, `throw`, template string, or `.sort(cmp)` inside a per-frame loop.
7. Hot locals are `i32` or `f64`. Never `u8`/`u16` (backends disagree on overflow). Counters use `x++`, not `x = x + 1`.
8. `f64(x)`/`i32(x)` for conversion. Never `x * 1.0`.
9. Named imports only in hot modules.
10. Buffers, vertex buffers and scratch arrays are allocated once at startup and reused via `clear()`/overwrite.
11. Everything the GPU sees goes through one `alloc()`ed `ptr`, written with `ptr_write_*` on a hoisted base pointer.
12. Anything measured in millions of elements (voxels, lightmaps) lives in `buffer`/`ptr`, not `array`.

## Appendix B — Quick reference card

```hemlock
// module
import { thing } from "./mod.hml";     // named  (fast)
import { sin } from "@stdlib/math";    // stdlib
import "./side_effect.hml";            // side-effect (.hml required)
import "libSDL2-2.0.so.0";             // FFI library (no .hml)
export fn f() {}  export let g_x = 1;  export define T { a: f64 }

// memory
let p: ptr = alloc(n);  free(p);            // manual, unchecked
let b = buffer(n);                           // refcounted, bounds-checked, auto-freed
let base: ptr = buffer_ptr(b);               // hoist this
ptr_offset(base, byteoff, 1)                 // THREE args, first must be ptr
ptr_write_f32(q, v);  ptr_read_f32(q);  ptr_deref_u8(q);
talloc(f32, 4);  sizeof(f32);  ptr_to_buffer(p, n);  b.slice(0, k);
memset(p, 0, n);  memcpy(dst, src, n);

// hot-loop skeleton
fn hot(a0: f64, n0: i32): f64 {
    let a: f64 = a0;          // 1. params -> locals
    let n: i32 = n0;
    let acc: f64 = 0.0;       // 2. i32/f64 only
    for (let i = 0; i < n; i++) { acc = acc + a; }   // 3. no calls/allocs/closures
    let out: f64 = acc;       // 4. copy-out
    return out;
}

// build
hemlockc --check f.hml            // instant lint/type/borrow check
hemlockc -O1 f.hml -o dev         // dev loop
hemlockc -O3 f.hml -o nightshade  // ship
hemlockc -c f.hml --emit-c out.c  // inspect codegen / verify unboxing
```
