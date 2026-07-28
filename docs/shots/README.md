# `docs/shots/` — the visual evidence directory

Every PNG in here is produced by a **compiled, headless, deterministic** tool and every
screenshot ships with its budget report. A picture without triangle counts is not evidence.

Owned by task **W2-11**. `tools/shot.hml` is re-owned by **W3-7**, which rewires it onto the
game's real `frame_render` in `src/render/world_render.hml`.

---

## The three tools

```sh
# 1. the screenshot harness — the primary quality instrument
hemlockc -O1 tools/shot.hml -o /tmp/shot
SDL_VIDEODRIVER=dummy /tmp/shot --scene list
SDL_VIDEODRIVER=dummy /tmp/shot --scene ridge_golden --out docs/shots/ridge_golden.png
SDL_VIDEODRIVER=dummy /tmp/shot --scene muzzle_fog --cam 3,2.1,-8 --look 220,-4 \
                                --tod 22.0 --weather storm --seed 1337 --out /tmp/a.png
SDL_VIDEODRIVER=dummy /tmp/shot --selftest        # PASS 29/29, exit 0

# 2. the palette contact sheet — built BEFORE texgen, on purpose
hemlockc -O1 tools/palette_preview.hml -o /tmp/palprev
/tmp/palprev --out docs/shots/palette_preview.png

# 3. the atlas inspector — all four textures, magnified, gridded, labelled
hemlockc -O1 tools/texview.hml -o /tmp/texview
/tmp/texview --out docs/shots
/tmp/texview --tod 22.0 --weather storm --out /tmp     # TEX_SKY varies with ToD
```

All three **refuse to run interpreted** and exit 2 with the build command in the message.
`hemlockc` is the shipping target; compiled is what is worth photographing (ARCHITECTURE §7).

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
| `storm_assault` | ART_BIBLE §12.5 — storm assault on the lightning frame. |
| `hud_worst_case` | the HUD over noon sky, snow, a muzzle flash and `CONCRETE_HI`. |
| `budget_worst` | the densest legal frame: `FOG_FAR` 72 m, every prop class. |
| `flat_debug` | a quiet reference frame for regression diffs. |

Any of them can be overridden: `--cam x,y,z --look yaw,pitch --tod h --weather w --seed n
--fov deg --upscale n`.

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
