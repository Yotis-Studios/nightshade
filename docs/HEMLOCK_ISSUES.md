# Hemlock / toolchain issues found while building Nightshade

Every issue below was reproduced by hand on this machine (hemlock + hemlockc from
`/usr/local/bin`, hemlock repo at `8bee0d58`). Repros are minimal and self-contained.
Copy any block into a `.hml` file and run it.

**Status key:** 🔴 blocks work · 🟠 costly workaround · 🟡 papercut / DX

---

> **Status update after pulling `main` (now at `7d45a37c`).** The user merged a
> batch of fixes including `ed12be28 codegen: fix 30+ interpreter/compiler
> divergences found by systematic audit`. Re-verified everything below against it:
> **H-3 is FIXED upstream. H-1 is NOT — still broken on latest main, and now
> fixed on branch `fix/inliner-param-name-collision`.**

---

## ✅ H-1 — `hemlockc` inliner captures caller locals: emits invalid C
### FIXED — branch `fix/inliner-param-name-collision`, commit `e2946c1c`

Verified still broken on clean upstream `7d45a37c`, then fixed. The patch extends
the pre-inline guard to decline inlining when a parameter name collides with a
caller local / main var / in-scope name. Conservative: it gives up the
optimization in the colliding case rather than emitting invalid C. **The complete
fix is alpha-renaming inlined bodies to fresh names, which would keep the
optimization — left as follow-up.**

Validation: **54/54 compiler tests, 321/321 parity (100%)**, including a new
regression test `tests/parity/language/inline_param_name_collision.hml`.

Original analysis follows.



**The bug.** When a caller has a local variable whose **name matches the callee's
parameter name**, `hemlockc` inlines the callee's body without renaming. The
inlined arithmetic then binds to the *caller's* boxed `HmlValue` local instead of
the unboxed parameter, and the generated C does native arithmetic on an
`HmlValue`. GCC rejects it.

**Two identical programs. The ONLY difference is a local variable's name.**

```hemlock
// FAILS TO COMPILE — caller's local is named `s`, same as the parameter
fn mix(s: i32): i32 { return s + 7; }
fn main() { let s: i32 = 100; let r: i32 = mix(s); print(`${r}`); }
main();
```
```hemlock
// COMPILES AND RUNS (prints 107) — caller's local renamed to `q`
fn mix(s: i32): i32 { return s + 7; }
fn main() { let q: i32 = 100; let r: i32 = mix(q); print(`${r}`); }
main();
```

**Error produced by the first:**
```
/tmp/hemlock_XXXX.c:83:42: error: invalid operands to binary + (have 'HmlValue' and 'int')
   HmlValue _tmp38 = hml_val_i32((s + 7));
C compilation failed with status 1
```

**The interpreter runs both correctly.** Only the compiler is affected — and the
game ships compiled.

### Scope (each line separately verified)
| Case | Result |
|---|---|
| Caller local name **==** parameter name | **FAIL** |
| Caller local name **!=** parameter name | ok |
| Types `i32`, `u32`, `u64`, `i64`, `f64` | **all FAIL** — not type-specific |
| Operator `+`, `*` | **both FAIL** — not operator-specific |
| Literal size (`7` vs `6364136223846793005`) | irrelevant — both FAIL |
| Argument is a **literal** (`mix(41)`) | ok (constant-folded, not inlined the same way) |
| Body routed through an intermediate local: `let t: u64 = s + 7; return t;` | **ok — this is the workaround** |
| Body uses two parameters, no literal: `return s + k;` | ok |
| Same arithmetic written inline with no helper fn | ok |

### Severity: loud, not silent
I specifically tried to make it miscompile silently (forcing the caller's
same-named local to be unboxed by hammering it in native arithmetic first). It
**always** produced a hard C compile error instead of a wrong answer. So this
blocks builds; it does not corrupt results. That is the good outcome.

### Why it matters here
`fn f(x: T): T { return x <op> <literal>; }` is the single most common helper
shape in a math/renderer codebase, and `s`, `x`, `i`, `n`, `v` are exactly the
names both the helper and its caller will use. We hit it writing an LCG for
terrain noise.

### Workarounds (both verified)
1. Route the arithmetic through an intermediate typed local in the callee:
   `fn mix(s: u64): u64 { let t: u64 = s * K; return t; }`
2. Give parameters names callers will not use (a `p_` prefix convention).

### Suggested real fix
Alpha-rename inlined callee bodies (standard inliner hygiene): rewrite parameter
and local names to fresh uniques at the inline site before substitution.

---

## 🔴 H-7 — `ptr == null` is FALSE in compiled code for a NULL pointer returned from FFI
### Live on `main` (`cb7fbfaa`). Silent wrong behaviour, not a crash. **Worst severity so far.**

An FFI function that returns a NULL `ptr` compares **false** against `null` when
compiled, and **true** when interpreted:

```hemlock
import "libSDL2-2.0.so.0";
extern fn SDL_Init(f: u32): i32;
extern fn SDL_GetWindowFromID(id: u32): ptr;   // returns NULL for a bogus id
fn main() {
    SDL_Init(32);
    let p = SDL_GetWindowFromID(999999);        // guaranteed NULL
    print(`p == null       -> ${p == null}`);
    print(`p == ptr_null() -> ${p == ptr_null()}`);
}
main();
```
```
compiled     : p == null -> false     p == ptr_null() -> true      <-- WRONG
interpreted  : p == null -> true      p == ptr_null() -> true
```

`typeof(p)` is `"ptr"` in both. So the value is a null pointer; only the `== null`
comparison disagrees.

### Why this is the most dangerous issue in this file
It silently disables error handling. Every guard of the form
`if (handle == null) { ...fail... }` is **dead code in a compiled build**, so a
failed allocation is carried forward as if it were a valid handle and the program
dies later, somewhere unrelated.

This was **not hypothetical**: `wobbleweed/src/sdl.hml` at `HEAD` had exactly this
shape at four sites — `if (win == null)`, `if (ren == null)`, `if (tex == null)` —
so a failed `SDL_CreateWindow` or `SDL_CreateRenderer` was never detected in the
shipping (compiled) configuration. Found by the Gate 0 auditor; independently
reproduced by the orchestrator on a freshly built compiler.

### Workaround (in force across this project)
**Never compare a `ptr` to `null`. Always use `ptr_null()`.** It is correct on both
backends. Every Wave-1 module that checks an SDL handle (`batch`, `atlas`,
`target`, `audio`, `mesh`, `engine`) must obey this.

### Suggested fix
Make the compiled `==`/`!=` path treat a null `ptr` as equal to `null`, matching
the interpreter. This is a parity bug — `make parity` should have a test for
`ptr`-vs-`null` comparison and currently does not.

---

## ⚪ H-8 — `extern fn` resolution is LAZY on both backends (probably by design — but document it)

A program that declares an extern for a symbol that **does not exist** builds and
runs cleanly, exit 0, on both backends, as long as the function is never called.

Consequence for testing: the acceptance criterion "every declared extern resolves
at runtime" **cannot** be discharged by a probe exiting 0. It needs either a real
`dlsym` check or a call-graph coverage argument. Worth one line in the FFI docs,
since the natural assumption is that binding happens at load.

---

## ❌ NOT A BUG — `u64 >>` divergence (retracted)

Gate 0 reported that `hemlockc` emitted an arithmetic (sign-propagating) right
shift for `u64` while the interpreter emitted a logical one:
```
let b: u64 = 10241477005482035122;  b >> 1
  compiled: 14344110539595793369    interpreted: 5120738502741017561
```
**This does not reproduce on current `main`.** Both backends now return the
correct `5120738502741017561`, and `(u64 all-ones) >> 60` gives `15` on both.

**Root cause: a stale compiler.** `/usr/local/bin/hemlockc` is dated **July 12**
and predates both the user's "30+ interpreter/compiler divergences" merge
(`ed12be28`) and the inliner fix (`e2946c1c`). Agents invoking `hemlockc` from
`PATH` were testing a two-week-old toolchain. See the toolchain warning at the
top of `CLAUDE.md`.

---

## 🟠 H-2 — `array.sort` is a different algorithm per backend, and the compiled one is O(n²) on sorted input

Reported by the engine recon agent, consistent with observed timings.

- **Compiled:** non-randomized **Lomuto quicksort** — O(n²) time *and* O(n)
  recursion depth when the input is already ordered.
- **Interpreted:** stable insertion sort — O(n²) always.

Measured in the renderer's painter's-sort path: **2.95 ms** for 2 000 triangles on
lucky input vs **107 ms** on depth-ordered input — a 36× cliff, and depth-ordered
is the *normal* case for a camera moving through a world. The O(n) recursion depth
is also a stack-overflow risk at larger n.

**Ask:** median-of-three or randomized pivot, plus an introsort depth cap.
Also worth documenting that sort is not stable in the compiled backend, since the
two backends disagree on stability.

**Our mitigation:** never call `sort` with a closure in a per-frame path — we
replaced it with an O(n) bucket sort over quantized depth (0.275 ms @ 2 000 tris,
and immune to input order).

---

## ✅ H-3 — Interpreter and compiler disagree on floating-point results
### FIXED UPSTREAM by `ed12be28` — re-verified, no action needed

Both backends now agree exactly:
```
interpreted: total=425 sky=4   y=2 -> 60,100,196  y=80 -> 124,155,216  y=200 -> 135,171,221
compiled:    total=425 sky=4   y=2 -> 60,100,196  y=80 -> 124,155,216  y=200 -> 135,171,221
```

### ⚠ IMPORTANT KNOCK-ON: a wobbleweed "bug" was a misdiagnosis
The engine recon agent filed §11.1 of `ENGINE_API.md` as *"`batch_flush` reuses one
vertex buffer across `SDL_RenderGeometry` calls → undefined behaviour → flat
cloudless sky in the interpreter"*, and proposed reworking `geom.hml` to pack each
texture run into a disjoint region of a frame-long buffer.

**That diagnosis was wrong.** The flat sky was this compiler divergence, not SDL
buffer aliasing. With `ed12be28` the *unmodified* `geom.hml` now produces the
correct gradient on both backends:
```
interpreted: top-left px = 60,100,196   mid px = 82,121,203
compiled:    top-left px = 60,100,196   mid px = 82,121,203
```
`SDL_RenderGeometry` copies vertex data into the render command queue, so reusing
the buffer between calls was always safe.

**Consequence:** do **not** treat the `geom.hml` disjoint-buffer rework as a
correctness fix. It may still be worth doing as a *performance* change (one
contiguous fill, no rewind, natural fit for a per-frame arena) — but it must be
justified by a benchmark, not by this bug. §11.3 (`batch_new(cap)` never enforced
→ heap corruption on overflow) is a **separate and still-real** bug.

Original analysis follows.



Rendering the identical scene with the identical camera:
```
interpreter: 404 triangles survive clipping
compiled:    425 triangles survive clipping
```
The two backends diverge somewhere in the near-clip / guard-band float arithmetic,
which then produces visibly different pixels. `wobbleweed/README.md` currently
claims "byte-identical output ... in the interpreter and compiled" — **that claim
is false today.**

This matters beyond cosmetics: it means the interpreter is not a valid preview of
the shipping renderer, and it would break any lockstep/deterministic multiplayer
that mixed backends.

**Ask:** determine whether this is intended (e.g. compiler contracting `a*b+c`
into FMA, or x87 excess precision) and either fix it or document it loudly.
Compiling with `-ffp-contract=off` on the C backend is the usual first check.

---

## 🟡 H-4 — Interpreter type errors do not say what was expected where

Returning a `buffer` from a function annotated `: object`:

- `hemlockc`: `error: return type mismatch: expected 'object', got 'buffer'` — with
  the file and line. Excellent.
- `hemlock`: `Runtime error: Expected object, got non-object`

"got non-object" names neither the actual type (`buffer`) nor the construct
(a return). Given the interpreter already knows the runtime type tag, echoing it
would cost nothing.

---

## 🟡 H-5 — `/` formats differently between backends in string interpolation

The same integer-valued division interpolates as `35280` in the interpreter and
`35280.0` compiled. Arithmetic and comparisons agree; only the rendered text
differs. Bites any HUD/score readout. (Arguably H-3's cousin — the backends should
agree on number formatting.)

---

## 🟡 H-6 — `import` for FFI is positional, and the failure is confusing

`extern fn` binds to the **most recently declared `import`**, not to all imported
libraries:

```hemlock
import "libSDL2-2.0.so.0";
import "libX11.so.6";
extern fn SDL_Init(flags: u32): i32;
// FFI function 'SDL_Init' not found in 'libX11.so.6':
//   undefined symbol: SDL_Init
```

This is defensible as a design, but nothing documents it and the error blames the
wrong library. **Fix:** either search all imported libraries, or say so in the
error ("`SDL_Init` not found in `libX11.so.6` (the most recent `import`); externs
bind to the nearest preceding import").

Workaround: group each library's externs directly under its own `import`.

---

## Notes that are NOT bugs (documented behaviour we hit anyway)

- **`i32`/`i64` `*` `+` `-` trap on overflow** rather than wrapping. Any hash or
  PRNG must use `u64` (unsigned wraps) or mask into `i64` explicitly. Writing a
  standard LCG with `i64` throws `Integer overflow: i64 multiplication`.
- **`/` always returns a float**; `divi()` is integer division. Opposite of C.
- **`define` structs are not value types** — measured no cheaper than object
  literals (223 ns vs 213 ns for 7 fields). They exist for FFI layout.
- **Type annotations are a performance feature.** `hemlockc` only unboxes
  arithmetic it can prove; untyped params/locals stay boxed `HmlValue`.

---

## Environment gotcha (not Hemlock's fault, but it will bite someone)

SDL2 **headers are 2.0.20** while the **runtime `.so` is 2.0.18**, and
`pkg-config --modversion sdl2` reports 2.0.20. A symbol can exist in the header
and still fail to resolve at runtime. Do not bind any SDL API newer than 2.0.18.
