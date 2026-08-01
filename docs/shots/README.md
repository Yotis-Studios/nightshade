# `docs/shots/` — the visual evidence directory

Every PNG in here is produced by a **compiled, headless, deterministic** tool and every
screenshot ships with its budget report. A picture without triangle counts is not evidence.

Owned by task **W2-11**. `tools/shot.hml` is re-owned by **W3-7**, which rewires it onto the
game's real `frame_render` in `src/render/world_render.hml`.

---

## Every picture in here is 960×540. If one is not, it is stale.

The frame is **320×180** and the goldens are **×3 = 960×540**, exact. A 960×720 PNG in this
directory is a picture of the 4:3 build that was retired on 2026-07-31 — check the size before
you read anything into a shot.

```sh
# the one-line audit — every FRAME capture must be 960x540
for f in docs/shots/*.png; do python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read();\
print(*struct.unpack('>II',d[16:24]), sys.argv[1])" "$f"; done | grep -v '^960 540'
```

Legitimate non-frame images: the atlas magnifications (`tex_*.png`), the palette contact sheet,
the sky panorama, the meshgen inspector sheets and the heightmap. Everything else in that list
is a stale picture.

**Currently stale and not this task's to regenerate:** `w411_0000_wake.png`,
`w411_0010_the_lantern.png`, `w411_0030_lit.png`, `w411_0036_wave1.png` — four **320×240**
first-minute frames captured from the game before the 16:9 conversion. They are the record of
the opening beat and they show a frame shape the game no longer has.

---

## The four tools

```sh
# 1. the screenshot harness — the primary quality instrument
hemlockc -O1 tools/shot.hml -o /tmp/shot
SDL_VIDEODRIVER=dummy /tmp/shot --scene list
SDL_VIDEODRIVER=dummy /tmp/shot --scene ridge_golden --out docs/shots/ridge_golden.png
SDL_VIDEODRIVER=dummy /tmp/shot --scene muzzle_fog --cam 3,2.1,-8 --look 220,-4 \
                                --tod 22.0 --weather storm --seed 1337 --out /tmp/a.png
SDL_VIDEODRIVER=dummy /tmp/shot --selftest        # PASS 59/59, exit 0

# 2. the palette contact sheet — built BEFORE texgen, on purpose
hemlockc -O1 tools/palette_preview.hml -o /tmp/palprev
/tmp/palprev --out docs/shots/palette_preview.png

# 3. the atlas inspector — all four textures, magnified, gridded, labelled
hemlockc -O1 tools/texview.hml -o /tmp/texview
/tmp/texview --out docs/shots
/tmp/texview --tod 22.0 --weather storm --out /tmp     # TEX_SKY varies with ToD

# 4. the settlement harness — the town, driven to a tier through settle_step
hemlockc -O1 tools/settle_shot.hml -o /tmp/sshot
SDL_VIDEODRIVER=dummy /tmp/sshot --scene list
SDL_VIDEODRIVER=dummy /tmp/sshot --scene settle_city_dusk \
                                 --out docs/shots/settle_city_dusk.png
```

All four **refuse to run interpreted** and exit 2 with the build command in the message.
`hemlockc` is the shipping target; compiled is what is worth photographing (ARCHITECTURE §7).

---

## `settle_shot.hml` — the settlement, and the camera it was photographed through

The settlement is the emotional centre of the game and this is how anyone looks at it. It has
its own harness rather than a `shot.hml` scene because `shot.hml`'s terrain comes from
`world_render.terrain_h` and the town stands on `worldgen_height` — a settlement scene in
`shot.hml` would float. It drives the tier through the real `settle_step` ladder, so if the
ladder stops promoting, this tool stops producing a city.

### ⚠ Every settlement look-review before 2026-07-31 was made through a camera the game does not have

`settle_shot.hml` carried its own `g_RES_W = 320`, `g_RES_H = 240`, `alloc(320*240*4)` and
`g_fov = 70.0` — hand copies of three constants that moved to 320×180 / 58 in the 16:9
conversion. The consequences compounded:

* `frame_render` projects at `g_RES_W × g_RES_H` from `config.hml` (320×180) and
  `frame_present` reads back exactly that rectangle, so **the bottom 60 native rows of every
  render were a dead black band of unwritten memory** — a quarter of the picture. Reproduced
  on the tree at `f4644f7`.
* The seven checked-in goldens were **960×720 and did not show that band**, which proves they
  predate the conversion entirely. They were pictures of a build that no longer exists.
* Their `--fov` overrides (34 / 60 / 70 / 74 / 76) were all chosen against a 4:3 frame.

This is the same bug class as `probe_viewmodel`'s divisor of `2.4` (= 240/100), which turned a
viewmodel regression into an apparent improvement. **A stale constant in an instrument is worse
than one in the code, because the instrument is what you would have caught the code with.**

Fixed: resolution and FOV are now imported from `src/core/config.hml` and the file may not name
either. The seven goldens are regenerated at 960×540.

### The seven scenes, and why the FOV column is not uniform

`--scene <id>` sets every flag; the stats report prints them all back, so a golden can be
regenerated from its own `.stats.txt`. **That is new** — before this, `--ladder K`, `--rung R`
and `--dist` were never printed, and two of the seven were literally unreproducible.

| scene | what it is for | lens |
|---|---|---|
| `settle_city_dusk` | the money shot: a finished CITY down the High Road at dusk | `g_FOV_HIP` |
| `settle_village_dawn` | the same camera at tier 1 — city minus village *is* the growth read | `g_FOV_HIP` |
| `settle_dome_night` | the warm dome from 300 m out at 22:00 — the town as a glow you walk toward | `g_FOV_HIP` |
| `settle_nodome_night` | identical, dome off. The pair is the evidence; neither half alone is | `g_FOV_HIP` |
| `settle_facade_b1` | one building at 26 m, the B1 rung, orbited to 45° | 75.2° horizontal |
| `settle_block_b2` | the same building at 50 m, where the B2 rung takes over | 44.3° horizontal |
| `settle_ladder` | STAKED → FRAMED → CLAD → DONE of one archetype in a row | 92.3° horizontal |

**The four look shots take no `--fov`.** They are the settlement as the player sees it and the
player's lens is `g_FOV_HIP`. The three geometry instruments are diagnostics, not look-reviews,
and they state a **horizontal** angle — the intent is "does the whole ladder fit", "is one
facade big enough to judge" — which `fov_v_for_h()` solves against `g_RES_W/g_RES_H`. Those
three horizontal angles are exactly what the 4:3 originals covered, so the 16:9 frame *crops*
them vertically instead of zooming them out. Storing a vertical number would put them straight
back into the trap this section exists to describe.

`settle_block_b2` must keep its long lens: the LOD rung is chosen by **distance**, so 50 m is
what may not move, and at `g_FOV_HIP` a 50 m building is too small to judge.

### What the seven currently show — looked at, 2026-07-31

* **`settle_city_dusk`** — the dead band is gone and the wide frame suits the dusk sky. But this
  is meant to be a **28-building CITY** and the frame contains **one building and a hill**: at
  `--back 6` on the green, the terrain crest between the camera and the town eats it. The
  lantern viewmodel, the road and the sky read well. *The composition is a pre-existing defect,
  not a conversion artefact — the old golden showed the same single building.*
* **`settle_village_dawn`** — same camera, same problem, and the pair does not read as growth
  because both frames show one building. The dawn palette (cool violet sky, lit windows still
  on) is genuinely lovely and the two lit windows are the best thing in the set.
* **`settle_dome_night`** — **the best picture in the directory.** The dome is a soft warm bloom
  on the horizon under a starfield, the ridgelines stack in mist, and the lantern in hand is the
  only warm thing between you and it. This is the fantasy in one frame.
* **`settle_nodome_night`** — the control, and it earns the dome: identical frame, no glow, and
  the horizon is just dark hills. The A/B is unambiguous.
* **`settle_facade_b1`** — clean and legible: roof beams, plinth, window band, door reveal all
  readable at 26 m. The instrument works.
* **`settle_block_b2`** — the near building is solid and the far one is washed nearly white by
  fog and reads as glass. Worth a look by whoever owns `g_FOG_ALPHA_T`.
* **`settle_ladder`** — all four rungs are in frame (stake line → stone footing → grey clad box
  → finished roof), left to right, but the STAKED end is nearly lost in the grass and the DONE
  end touches the right edge. Usable; not well composed.

### What could not be reconstructed

`settle_ladder`'s original `--ladder K` and `--rung R` are **gone** — they were never printed.
Its recorded `tris.world = 1248` does not occur at any of K = 0..7 × rung 0..2 × dist 10..20 on
this tree (nearest 1229), so the checked-in picture also predates the current `hubgen`.
The new scene uses **K = 3, rung 0, dist 22, eye 4.0, pitch −6** and that is a fresh choice,
stated as one, not a reconstruction. The other six were solved back out of their stats files
exactly (camera positions match to the last printed digit).

---

## The contract `shot.hml` keeps

| | |
|---|---|
| **Real frame path** | `frame_render()` runs stages 6–28 of `ARCHITECTURE.md` §4 in that order on the real engine modules. There is no second renderer in the file. |
| **Deterministic** | No wall clock and no `@stdlib/random` touch geometry. The same command produces **byte-identical PNG bytes** — verified across separate processes for all 8 scenes. |
| **Never crashes headless** | `SDL_SetRelativeMouseMode` always fails under `SDL_VIDEODRIVER=dummy`; the status is printed into the stats report and rendering continues. |
| **PNG and stats are inseparable** | `--out foo.png` also writes `foo.stats.txt`. If either write fails the other is removed. The report also goes to stdout, always, even with no `--out`. |
| **`--scene list`** | enumerates every registered scene with its full camera / ToD / weather / seed / fog setup, so any shot in here is reproducible from the listing alone. |

## Scenes

| id | what it is for |
|---|---|
| `ridge_golden` | ART_BIBLE §12.1 — the ridge at golden hour. **The screenshot.** |
| `muzzle_fog` | ART_BIBLE §12.2 — muzzle flash in the fog. The identity shot. |
| `hub_dawn` | ART_BIBLE §12.3 — the cozy hub at dawn. |
| `ns_bloom` | ART_BIBLE §12.4 — nightshade bloom, violet fog, the monolith. |
| `storm_assault` | ART_BIBLE §12.5 — storm assault on the lightning frame. **Its shipping golden is TIME-OF-DAY INVARIANT and must not appear in a day/night table — see below.** |
| `hud_worst_case` | the HUD over noon sky, snow, a muzzle flash and `CONCRETE_HI`. |
| `budget_worst` | the densest legal frame: `FOG_FAR` 72 m, every prop class. |
| `flat_debug` | a quiet reference frame for regression diffs. |

Any of them can be overridden: `--cam x,y,z --look yaw,pitch --tod h --weather w --seed n
--fov deg --upscale n`.

---

## Two rules for anyone measuring darkness with this harness (2026-08-01)

### 1. `--headless` on the game binary now really is headless

`build/nightshade --headless` used to open a **mapped X window on `:0`** — `boot_window()` ran
unconditionally and the flag only skipped the mouse grab. Gate 9 counted seven of them on the
owner's desktop at once, and one agent screenshotted and typed into **another agent's game for
forty minutes** because the two windows landed at the same geometry.

It now forces `SDL_VIDEODRIVER=dummy` before `SDL_Init`, which is exactly what this directory's
tools have always been told to do by their caller. Measured, same binary, same box:

```
                                   NIGHTSHADE windows in `wmctrl -l`   no-DISPLAY boot
  74a6ec4  --headless --selftest    1                                   SDL_Init failed
  now      --headless --selftest    0                                   PASS, exit 0
  now      (no flag)                1   <- unchanged, a window is correct here
```

The `env -u DISPLAY` column is the stronger proof and it is new capability: the shipping
binary's `--selftest` can now run on a box with no X server at all.

Two things `--headless` still does **not** do, stated so nobody has to rediscover them:
it does not close the audio device (add `--no-audio`), and the dummy driver selects SDL's
**software** renderer, which collapses `BLEND_ADD` to `BLEND` — so glow and muzzle brightness in
a `--headless --shots` PNG is not what a display shows. That was always true of every headless
invocation here; it is now implied by a flag instead of typed by a caller.

### 2. `storm_assault`'s shipping golden cannot pass or fail a test about darkness

`--bolt 1` (its default, from `F_LIGHTNING`) renders the **flash frame**, and `tod.hml` §5.2
replaces the ambient, the key colour, the key *direction*, the fog tint and the fog alpha
ceiling with constants. After that override nothing in the frame depends on the hour. Measured
here, `--bolt 1 --nohud --novm --lantern 0 --pool 0 --upscale 1`, ground band rows 112..139,
Rec.709 mean: **`52.0287` at 02:00, noon, 18:15 and 22:00** — range `0.0000`, six significant
figures flat. **That is correct physics** (a bolt is the same bolt at any hour) and it must not
be "fixed".

> Gate 9 reported `53.9064` for this row and `5.54 / 6.88 / 5.83 / 5.34` for the `--bolt 0` row
> where this file measures `4.4747 / 6.1066 / 4.8534 / 4.3557`. The *finding* reproduces exactly;
> the absolute values do not, because gate 9 did not state its lantern/pool switches and this
> harness's `--lantern 0 --pool 0` is a different frame from the shipping default. **Quote the
> flags with the number or the number is not reproducible** — every table below states them.

**So the shipping `storm_assault` golden is excluded from every day/night comparison table.**
The row to use is `--bolt 0`, which renders the same storm between bolts, and `--scene list`,
the scene description and the `.stats.txt` all say so on every render.

The `--bolt 0` row was *also* flat until today, for a completely different and non-deliberate
reason. Measured on this tree, `--bolt 0 --nohud --novm --lantern 0 --upscale 1`, ground band
rows 112..139, Rec.709 mean, same camera, weather varied:

```
                02:00     noon    18:15    22:00     range
  clear        4.4693  76.9974  49.9303   5.8730    72.53
  overcast     4.5217  55.0026  43.4540   4.3802    50.62
  rain         3.7548  43.9591  35.9147   3.7197    40.24
  storm        4.4747   6.1066   4.8534   4.3557     1.75   <- no day at all
```

Storm noon is `6.11` against rain noon's `43.96`: **one step of weather costs 7× the daylight**,
and CLAUDE.md §8's "something above 220" is unreachable in a frame whose entire ground sits
under luminance 7. The cause is not the sun and not the storm — measured here, a storm returns a
key direction **identical to clear at 02:00 / noon / 18:15 / 22:00, to every printed digit**;
weather touches scalars and never `KF_DIR_*`. The cause is that both darkness gates in
`src/render/world_render.hml` (the carried lantern, and the night veil) read the **weathered**
fog tint's luminance, and `WX_STORM` multiplies that by `(0.26,0.32,0.46)`:

```
  WEATHERED fog tint luma    noon    02:00     lantern gate @ noon   veil @ noon
    WX_CLEAR                0.8576  0.4100           0.0000            0.0000
    WX_OVERCAST             0.7392  0.3536           0.0000            0.0000
    WX_RAIN                 0.6205  0.2970           0.4962            0.0000  <- half a lantern at midday
    WX_STORM                0.2775  0.1330           1.0000            1.0000  <- full night at midday
    WX_BLOOM                0.7934  0.4169           0.0000            0.0000
  the HOUR's own luma       0.8576  0.4100           (the gate band is 0.52 .. 0.72)
```

Every `.stats.txt` now prints that comparison on a `darkness` line — the weathered luma, the
hour's own luma (`tod_hour_tint_luma()`), both gates **as the frame actually ran them** (read
back out of the frame graph, not recomputed), and what they would be on the hour alone. When the
two disagree the line says so in words.

**LOOKED AT, `--bolt 0 --upscale 3`, shipping switches otherwise.** At 02:00 the storm is a
night: near-black sky, the carried lantern's pool covering roughly the near third of the ground
and everything past it falling away into the fog, the hostiles on the wall reading as
silhouettes with violet cores. At noon — on this tree — it is all but the same picture: the same
near-black sky, the same pool with the same edge in the same place, the same unlit mid-ground,
and the HUD reading `12H FOG 20M`. The two frames differ by `1.63` of 255 across the ground band.
It is midday and the game is showing you a night with rain in it.

With the fix below, the noon frame becomes a storm: the whole field is lit to the fog line at
`49.97`, the wall and its hostiles silhouette against the sky instead of dissolving, the
lantern's pool stops being the only light in a daylight scene — and the storm ceiling is
untouched, because the deck is the weather's and it is *supposed* to be dark. The 02:00 frame is
byte-identical to the one above.

### The fix, measured, and NOT APPLIED — it lands in files this task does not own

Darkness is the **hour**. Weather changes how much light gets through and what colour it is; it
does not move the sun. `src/art/tod.hml` now captures the hour's own authored fog tint before
the weather multiply and before the lightning re-key, and exports it:

```hemlock
export fn tod_hour_tint_luma(): f64
//  clock   05:30   11:54   12:00   18:15   19:30   22:00   02:00
//  luma   0.8450  0.8559  0.8576  0.7835  0.5998  0.4804  0.4100     measured, all weathers
```

`src/render/world_render.hml` may not import `src/art/**` (the import wall), so a `src/game/**`
caller has to hand it over. That is **one small function in `world_render.hml` and one line in
`main.hml`** — neither of which is this task's file — so they are written out here rather than
applied (CLAUDE.md §3: *found a bug in a file you do not own? Report it. Do not fix it*).
`tools/shot.hml` IS this task's file and its one line is written below too, but it is not in the
tree either: `frame_set_darkness` does not exist yet, so wiring the harness alone would not
compile. All three land together or none do.

```hemlock
// src/render/world_render.hml, beside gate_on_fog_tint:
let g_dark_lum: f64 = -1.0;                                   // -1 = nobody pushed one
export fn frame_set_darkness(p_lum: f64) { g_dark_lum = p_lum; }

fn gate_on_fog_tint(p_night: f64, p_day: f64): f64 {
    let lum: f64 = g_dark_lum;
    if (lum < 0.0) {                                          // unchanged fallback
        let env: array<f64> = g_env;
        lum = fog_tint_luma(env_field(env, ENV_FOG_R),
                            env_field(env, ENV_FOG_G),
                            env_field(env, ENV_FOG_B));
    }
    let out: f64 = gate_darkness(lum, p_night, p_day);
    return out;
}

// src/game/main.hml and tools/shot.hml, one line at stage 6, right after tod_eval:
frame_set_darkness(tod_hour_tint_luma());
```

Built in a scratch copy of the whole tree and measured against the table above:

```
                02:00     noon    18:15    22:00     range
  clear        4.4693  76.9974  49.9303   5.8730    72.53   <- IDENTICAL, every digit
  overcast     4.5217  55.0026  43.4540   6.2805    50.62
  rain         3.7548  43.9591  35.9147   5.1836    40.24
  storm        4.4747  49.9739  40.6674   6.1752    45.50   <- was 1.75
```

and lantern ON minus OFF, `--pool 0`, at **noon**:

```
                     before    after
  ridge_golden      +0.0000  +0.0000
  muzzle_fog        +0.0000  +0.0000
  hub_dawn          +0.0000  +0.0000
  ns_bloom          +0.0000  +0.0000
  storm_assault    +43.8574  +0.0000   <- the lantern burning at midday
```

and at **night**, which is the thing that may not move:

```
  ridge_golden @ 22:00   OFF  7.2094  ON 43.9221   +36.7127   before AND after
  ridge_golden @ 02:00   OFF  3.7167  ON 32.1349   +28.4182   before AND after
  ridge_golden @ 18:15 / 19:30                      +0.0000   before AND after
  storm_assault @ 02:00  the two PNGs are byte-identical (md5 a544e506…)
```

`WX_CLEAR`'s tint multiplier is `(1,1,1)`, so **clear weather is unchanged by construction** —
that is why the night does not move. Only three rows shift at 22:00 (overcast `4.38→6.28`, rain
`3.72→5.18`, ns_bloom `7.99→5.98`), because 22:00's hour-luma `0.4804` puts the veil at `0.9476`
rather than pinning it at `1.0`; night is still the darkest ground of the day in every row.

**The obvious wrong fix, so nobody spends an afternoon on it:** gate on the sun's elevation.
`ENV_SUN_Y` is already in the env and is already weather-invariant — and it is **0.8988 at
02:00**, higher than at dusk, because the night keyframes carry the *moon*. Sun elevation is not
a night signal in this table.

---

## Reading a `.stats.txt`

Three blocks: **provenance** (enough to reproduce the PNG from the text alone, including the
image's FNV-1a checksum), the **full §4 counter and stage-timer table** straight out of
`stats.hml`, and the **budget verdict** against `ARCHITECTURE.md` §8.

Two numbers in the timing block need reading correctly:

* **`sky.bake`** re-bakes the *whole* sky panorama, because a shot is one frame. The game
  re-bakes 20 rows/frame (≤ 0.6 ms) and never pays this. Judge the frame against
  `frame ms - sky`.
* Every stage time is inflated 60–100 %: this box permanently shares ~17 of 24 cores with a
  `llama-server` (`CLAUDE.md` §1.2). Compare shots to each other, not to an idle-box budget.

---

## What is a Wave-2 stand-in

All three tools carry a fenced block marked `WAVE-2 STAND-IN CONTENT`. It holds a local
palette, ToD keyframe table, texture/sky/font/mesh generators, transcribed from ART_BIBLE,
because `src/art/{palette,tod,texgen,skygen,fxgen,hudgen,meshgen}.hml` were being written **in
parallel** with these tools and could not be imported. The fences exist so W3-7 can delete
them and drop in the real imports mechanically.

**Everything outside the fences is permanent** — the CLI, the scene registry, determinism, the
PNG+stats pairing, the compiled-only guard, the §4 stage order, the stats plumbing, the
selftest. No colour and no game noun is named outside a fence.

---

## What the harness has already caught

The point of building this first is that it starts finding things immediately. As of W2-11:

1. **A ToD keyframe read literally drowns the world in mist.** ART_BIBLE §6.4 says
   `MIST_BOTTOM = terrain height, MIST_TOP = terrain + 1.6 m`. Applied per vertex that puts
   *every* ground vertex at `h = 1` and fogs the entire world uniformly. The band has to be an
   absolute world-Y band pinned just below the camera's ground, which is what actually makes
   valleys fill and hilltops stand clear. Worth fixing in `src/art/tod.hml` (W2-4).
2. **The sky's below-horizon band must start at exactly the horizon colour.** A step there is
   the visible seam at the skyline that ART_BIBLE §6.6 calls the classic amateur tell — it was
   plainly visible in the first `ridge_golden` render.
3. **A per-quad material swap on slope reads as cardboard patches** at 4 m quads. Most of the
   slope response belongs in vertex colour, with the hard swap kept rare.
4. **`hud_worst_case` immediately caught unplated HUD text** vanishing into a noon sky. It now
   has a plate. This is exactly the job that scene exists to do.
5. **Weather does not tint the sky.** `palette_preview.png`'s weather rows show identical sky
   bands for CLEAR / OVERCAST / STORM. Fog and lighting respond; the sky panorama does not.
   `src/art/skygen.hml` (W2-6) and `src/art/tod.hml` (W2-4) should take a weather term.
6. **The world tiles read as soft cloud rather than structure.** `tex_world.png` shows valid
   ramps, Bayer dithering and grain, but very little 4–10 texel *structure* (blades, cracks,
   plank ends). That is the bar `src/art/texgen.hml` (W2-5) has to clear.
7. **Headless additive blending is not representative.** SDL 2.0.18's software renderer
   collapses `BLEND_ADD` to `BLEND` inside `SDL_RenderGeometry` (characterised in
   `wobbleweed/examples/probe_target.hml`). Every headless shot prints a warning about it.
   Judge glow, muzzle and loot-beam brightness on `DISPLAY=:0`.

## Known gaps (W3-7 inherits these)

* **No near-plane clipping.** A triangle straddling the near plane is dropped whole, so the
  ground the camera stands on would leave a hole at the bottom of the frame. `shot.hml` covers
  it with a radial **near apron** whose triangles cannot span `w = 0`; the real fix is running
  `clip.hml`'s slow path from the frame orchestrator, and `clip.hml` currently carries a single
  scalar light term per vertex, not RGB, so it cannot yet carry baked terrain colour.
* **Dynamic point lights do not reach baked geometry.** `mesh_bake_light` folds ambient + sun +
  bounce only. Props pick lights up through their instance tint and the ground through a flat
  additive glow card — both correct-looking and both approximations.
* **`sort.world` / `sort.fx` are measured with an extra `batch_sort` call** because `batch.hml`
  fuses sort and flush; `flush.* - sort.*` is the pure gather+draw cost.
