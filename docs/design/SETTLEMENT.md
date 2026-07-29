# NIGHTSHADE — SETTLEMENT GENERATION AND GROWTH

**Status:** design, from the owner's directive. No code written.

> Owner: *"one area to focus on next might be settlement gen. have some concept of how a seed starts a
> village and that grows into town then city"*

This document sits **on top of** `MULTIPLAYER.md`'s CIVIC LIGHT unification. It invents no new
currency, no new light system and no new render stage. It adds one sim module, one art module, one
save tag, and reuses the prop registry that already exists.

**The one-sentence version:** a seed picks a hollow, the hollow gets a green and three roads, the
roads get a fixed lattice of 72 plots, and plots fill outward in a fixed order as the grid points the
player has already been earning cross four thresholds — so the town is `f(seed)` in shape and
`f(light)` in extent, and every player on a shard sees the same town grow in the same order.

---

## CONTENTS

1. [Site selection from a seed](#1-site-selection-from-a-seed)
2. [CIVIC LIGHT, in numbers](#2-civic-light-in-numbers)
3. [The growth ladder: camp → village → town → city](#3-the-growth-ladder)
4. [The city and the Foundry](#4-the-city-and-the-foundry)
5. [Layout generation](#5-layout-generation--the-algorithm)
6. [Growth made visible](#6-growth-made-visible)
7. [The triangle budget](#7-the-triangle-budget--the-section-that-decides-it)
8. [Architecture](#8-architecture)
9. [Multiplayer](#9-multiplayer)
10. [Out of scope for v1](#10-out-of-scope-for-v1)
11. [Contradictions with existing docs](#11-contradictions-with-existing-docs-flagged-not-silently-overridden)

---

## 1. SITE SELECTION FROM A SEED

### 1.1 The settlement stays at world origin. The *site* does not.

`worldgen.hml` anchors the entire danger gradient at the origin: `worldgen_shade_tier` measures `d`
from `(0,0)`, `worldgen_biome_tmd` forces Hollowfield inside 96 m, and `WG_TOWN_TIER_R_M = 64` forces
tier 0 inside 64 m. Moving the settlement off origin means passing a settlement position into two pure
functions that every chunk load calls, and re-deriving `save.hml`'s `CHUNKRING` ordering. **Not worth
it for v1.**

So: **the settlement centre is chosen from the seed, inside the ±48 m square around the origin.** Same
guarantees, per-seed variation in centre, terrace height, road bearing and terrain fit. The scorer is
written position-parametric so v2 can hand it any anchor (see §10).

### 1.2 What the heightfield can actually answer

`worldgen.hml` is a heightfield with three noise fields and no hydrology. Every criterion below is
expressible in `worldgen_height`, `worldgen_temp`, `worldgen_moist`, `worldgen_biome_tmd` and
`worldgen_poi_roll`, and nothing else.

Measured context that constrains the criteria: over 20 808 chunks and 8 seeds, per-chunk height range
was **mean 10.3 m, minimum 3.58 m** (`worldgen.hml` header, re-measured by `probe_worldgen` §D). There
is no flat ground in this world. A settlement design that waits for a flat 40 m plot waits forever;
**the design must terrace.**

### 1.3 The scorer

Candidate lattice: **12 m spacing over ±48 m from origin → 9×9 = 81 candidates.** Each is scored from
21 height samples (centre, an 8-point ring at r = 20 m, an 8-point ring at r = 48 m, 4 diagonal probes
at r = 34 m) plus one `(t, m)` pair.

| # | Criterion | Measure | Weight | Target |
|---|---|---|---|---|
| **C1** | **Buildable** | `range20 = max−min` over the r = 20 m ring plus centre | **×3.0** | score `clamp(1 − (range20 − 2.0)/6.0, 0, 1)`; 2 m is perfect, 8 m is zero |
| **C2** | **Not dead flat** | `range20` again, lower bound | **×1.0** | score 0 if `range20 < 1.2 m`. A flat horizon is CLAUDE.md §9.5's anti-goal |
| **C3** | **The hollow** | count of the 8 bearings at r = 48 m whose height exceeds the centre by ≥ 2.5 m | **×2.5** | score `min(shoulders, 5) / 5`. **This is the defensibility term and it is why the place is called a Hollow.** |
| **C4** | **The view corridor** | the *lowest* bearing at r = 48 m | **×2.0** | score 1 if it is ≥ 3.0 m below centre. A full bowl kills the money shot; the town needs one direction it can see out of, and that is the gate |
| **C5** | **Water** | `worldgen_moist` at centre | **×1.5** | score `1 − |m − 0.545| / 0.10`, clamped. 0.545 is just under the Fen threshold (0.615) — a damp valley bottom with a spring, not a bog |
| **C6** | **Not the Fen** | `worldgen_biome_tmd(t, m, d)` | **hard veto** | reject `WG_BIOME_FEN`. You do not found a town in black water |
| **C7** | **Resources** | `worldgen_poi_roll` over the 5×5 chunk block centred on the candidate | **×1.0** | `min(ruins + caravans, 4) / 4`. Ruins are dressed stone, caravans are brass |
| **C8** | **Grid reach** | distance to the nearest `worldgen_lantern_x/z` anchor outside 64 m | **×1.5** | score `1 − (d − 64)/56`, clamped. Guaranteed ≤ 67.9 m by construction, so this is nearly always 1 — it exists to break ties toward a site that *has a first road to somewhere* |

`settle_site_score` is the weighted sum. Ties break on the lattice index, so the result is total and
deterministic.

**Cost:** 21 `worldgen_height` calls at 8.1–9.2 µs = ~180 µs per candidate, plus 25
`worldgen_poi_roll`. **81 candidates ≈ 16 ms.** This runs **once per world, at world creation, on the
server**, and its result is a delta-log record. It is not on any frame path and it is not in the
400 ms boot allowance for existing worlds — a loaded world reads the site from the log.

### 1.4 What the site produces

```
settle_site_x / _z        the centre C, on the 12 m lattice
settle_site_bearing       θ₀ = the bearing of C4's view corridor, radians
settle_site_deck_y        the green's terrace height = MEDIAN of the 9 samples inside r = 10 m
settle_site_name          index into the 128-name table (§5.7)
```

`settle_site_deck_y` is a **median, never a mean** — a mean is dragged by one boulder and puts the
green half a metre into the hill.

---

## 2. CIVIC LIGHT, IN NUMBERS

`MULTIPLAYER.md` names the field and assigns it five jobs. This is the arithmetic.

`MAGIC_KINETIC.md` §6.1a already ships a **grid points** system ("1 point per lit lantern; 2 if on a
Wick Line; −4 while a Pall stands"). **CIVIC LIGHT and grid points are the same number at two
resolutions.** Do not build a second one.

### 2.1 The unit

**LUX: an i32, in 1/256 of "one unlinked lit lantern at full wick, at its own post".**

```
grid_points = GRID_LUX / 256          (integer division; this IS MAGIC_KINETIC's number)
```

Integers, not floats — this goes into `sim_hash`, and `sim_hash` quantizes floats to 1/16 m, which
would make a float field look round-tripped when it had drifted.

### 2.2 The field

```
LUX(p) = min( CL_MAX,  Σ over lit lanterns L of  contrib(L) · max(0, 1 − dist(p,L)/R(L)) )
       − Σ over standing Palls P of  pall(P) · max(0, 1 − dist(p,P)/R(P))

contrib(L) = wick(L)          if L is not on a Wick Line          [wick ∈ 0..256]
           = wick(L) · 2      if L is on a Wick Line (a lit lantern within 90 m)
R(L)       = the GDD §4.2 tier radius: T1 40 m, T2 60 m, T3 85 m, T4 120 m
pall(P)    = 1024 standing / 512 shrunk below half radius / 0 extinguished
CL_MAX     = 4096             (16 lantern-equivalents)
```

**The cap is load-bearing.** A T4 lantern covers 45 239 m² and lantern anchors sit one per 4 096 m², so
a fully-upgraded grid overlaps ~11-deep and the field saturates without a ceiling — at which point the
ladder stops meaning anything and expansion stops costing anything. `CL_MAX = 4096` is a real design
constraint the GDD's radii create; see §11.4.

Two derived scalars drive everything:

| | Definition |
|---|---|
| **`CORE_LUX`** | `LUX(C)` at the settlement centre. The *quality* of home. |
| **`GRID_LUX`** | `Σ contrib(L)` over every lit lantern whose post is inside the tier's ring. The *extent* of the grid. Note this is a plain sum, **not** distance-weighted — extent should not care where in the ring a post is. |

### 2.3 Entropy — the decay rate

`MULTIPLAYER.md` accepts entropy with the owner's gradient ("cheaper closer, durability higher closer").
That gradient is `LUX` and nothing else:

```
wick_decay_per_real_hour = 16 − floor(14 · min(1, LUX(post) / 2048))         [0..16 of 256]
wick_decay = 0                                  inside the green (r ≤ 16 m from C)
```

| Where | LUX at post | Decay | Full → dark |
|---|---|---|---|
| The green | — | **0** | never |
| Town core, saturated | ≥ 2048 | 2/hr | **5.3 real days** |
| Maintained ring | ~1024 | 9/hr | **28 real hours** |
| Frontier, alone | ~256 | 15/hr | **17 real hours** |

**Durability:** a lantern at `wick ≥ 128` cannot be snuffed by an enemy. Below 128 a Snuffer or a Pall
can take it. So neglect is what makes a post *vulnerable*; the dark finishes what you started.

**Maintenance:** refuel is a **1.2 s hold, 1 Sap, restores wick to 256.** Fast on purpose. The content
is the *route*, not the interaction — a City's outer ring is ~20 posts over ~600 m, about eight
minutes of walking, which is the daily loop.

### 2.4 Cost, and where it runs

`settle_step` runs on **one tick in 60** (once per second) at frame-graph step (h), and re-integrates
**8 lanterns per call** on a rotating slice indexed by tick. A 200-lantern grid fully refreshes in 25 s
and never costs more than 8 distance evaluations per second. **Target: ≤ 0.05 ms per settle tick,
≤ 0.001 ms amortised per frame**, against a 2.0 ms sim budget. The slice index is `tick / 60 mod
ceil(n/8)`, so the lag is deterministic and hashes.

---

## 3. THE GROWTH LADDER

### 3.1 Thresholds — the numbers a programmer types in

| Tier | Ring | Grid points needed | `GRID_LUX` | `CORE_LUX` floor | Great Lantern | Anchors in ring | Coverage |
|---|---|---|---|---|---|---|---|
| **0 CAMP** | 64 m | 0 | 0 | 0 | unlit | 3 | — |
| **1 VILLAGE** | 120 m | **10** | 2 560 | 512 | ≥ T1 | 11 | ~50 % |
| **2 TOWN** | 200 m | **32** | 8 192 | 1 024 | ≥ T2 | 30 | ~55 % |
| **3 CITY** | 320 m | **72** | 18 432 | 2 048 | ≥ T4 | 78 | ~50 % |

"Anchors in ring" is `π·r² / 4096`, from `worldgen`'s structural one-lantern-per-2×2-chunk-block.
"Coverage" is the fraction of them you must light *and keep lit* — roughly constant per tier, which is
right: the tier gets harder because the ring grows, not because the rate changes.

A lantern on a Wick Line is worth 2 points, and at 64 m natural spacing against a 90 m link range,
**nearly every lit lantern is linked**. So the practical reading is: **5–6 posts for a village, 16–18
for a town, 36–40 for a city.** That is the sentence to put in the design pitch.

### 3.2 Promotion, demotion, and the promise

- **Promotion** requires all three of grid points, `CORE_LUX` and Great Lantern tier, held for **one
  continuous in-game day** (16 real minutes). The hold prevents a promotion firing off a transient
  spike during a night hold.
- **Demotion never deletes anything.** Below 80 % of the current tier's threshold, the settlement
  enters **BROWNOUT** at that tier: geometry unchanged, window glow cards off, vertex colour ×0.72,
  shops lose restock, the Foundry stops. No triangle spike, no pop, no "my town was deleted".
  Recovering is instant on crossing back over.
- **`settle_tier_ever` is a high-water mark and the settlement never drops below it.** Buildings, once
  DONE, are DONE forever.
- **The green never browns out.** `CORE_LUX` has a hard floor of 512 that decay cannot reach, because
  the Great Lantern has never gone out, because Grandfather Wick has never gone properly to bed
  (`LORE.md` §7). This is how `LORE.md` §11.1.4 — *"Ember Hollow is never attacked and never falls.
  Ever"* — survives contact with entropy: **brownout is an industrial failure, not a civic one.** The
  lights on the houses stay on. The lights over the machines go out. That is a better image than the
  alternative and it costs nothing to implement, because the green is already the `wick_decay = 0` zone.

### 3.3 Tier contents — what specifically exists

Archetypes are `sm_building`-shaped boxes (see §7.1 for the triangle formula).

#### Tier 0 — CAMP (what a fresh seed looks like)

Not an empty field. A *lapsed* one — the lamps went out because nobody tended them (`LORE.md` §2).

| Thing | Count | Authored | Notes |
|---|---|---|---|
| The Great Lantern, unlit, on a cracked dais | 1 | 48 + 8 | `MESH_LANTERN` + a 2×2-quad cobble dais |
| Roofless shells (Shack, `rows=1`, no roof deck, no fascia) | 2 | 24 each | Footings and one course. Reads as ruin at 40 m |
| A Wick Post at the head of the High Road, unlit | 1 | 48 | |
| Rubble, a collapsed cart | — | ~30 | existing `MESH_CRATE` / `MESH_BARREL` / `MESH_ROCK` |
| **Total** | | **~180 authored, ~95 drawn** | |

**Population:** none. **Services:** none. **Unlocks:** nothing.
**Player's arsenal here:** whatever they arrived with, plus the bench-free crafting the opening gives
them. This is the "before" the whole game is measured against.

#### Tier 1 — VILLAGE

| Building | Archetype | Authored | Service unlocked |
|---|---|---|---|
| Great Lantern (lit, T1) + dais | — | 56 | respawn, save, sleep, ammo top-up |
| **Mabel's Bench** | Hall | 112 | craft & repair **village weapons**: bolt-action, revolver, pump shotgun, pipe-SMG. Craft **their ammunition from world materials.** |
| **Odo's Inn** | House | 88 | sleep→dawn, bank (the well), soup |
| The Well | 6-sided lathe | 24 | deposit ember/materials, safe from the death penalty |
| Cottage ×4 | Cottage | 52 each | villager housing; each one is a lit window at night |
| **Total new** | | **488** | |

**Population:** 3 named (Mabel, Odo, Grandfather Wick) + 4 ambient villagers.
**Contracts:** 1/day. **Structure placement:** not yet.
**Weapons available:** exactly `DIRECTION.md` §3's village row. Hand-made, forgiving on ammo, primitive.

#### Tier 2 — TOWN

Everything from Village, unmoved, plus:

| Building | Archetype | Authored | Service unlocked |
|---|---|---|---|
| **Connie's Board** | Cottage + signboard | 58 | bounty board, **2 contracts/day**, the world map |
| **Pip's Stall** | awning (2 posts + canopy) | 14 | charm trading, Almanac hand-ins |
| **The Almanac** | Hall | 112 | museum donation; each wing that opens **changes the skyline** (a lantern on the ridge of its roof — 8 tris) |
| **The Watch Tower** | Tower (4 courses, 9 m) | 50 | fast-travel anchor; **see §7.5 — the most valuable 50 triangles in the settlement** |
| House ×5 | House | 88 each | housing; garden plots appear behind them |
| Palisade arc (outward bearings only) | 12 fence segments | 48 | reads as walled from the approach; *"the wall came later and it is not a very good wall"* (`LORE.md` §7) |
| The Back Lane | road | 24 | the town's second axis. **Its appearance IS the promotion**, visible from the green |
| **Total new** | | **746** | |

**Population:** 5 named (+Connie, +Pip) + 9 ambient.
**New services:** structure placement on the 1 m grid inside the green (GDD §5.4), garden plots
(plant at dusk, harvest in 2 days), museum, attachments and rerolls at Mabel's bench.
**Weapons:** still village-tier only. **No manufactured guns until the city.**

#### Tier 3 — CITY

| Building | Archetype | Authored | Service unlocked |
|---|---|---|---|
| **THE FOUNDRY** | Works (16×12 m) | 164 | **manufactures rifles and ammunition** |
| The Foundry stack | Tower, 5 courses, 12 m | 58 | the ember plume; the silhouette that says *city* |
| **The Arsenal** | Hall | 112 | sells the Sparrow AR, the Tinker SMG, the LMG, and manufactured ammunition. Stock is `f(ammo_rate)` |
| House ×8 | House | 88 each | 704 |
| Strung lantern lines over the green | FX layer | 0 world tris | 12 additive cards |
| **Total new** | | **1 038** | |

**Population:** 5 named + 18 ambient.
**Weapons:** manufactured tier unlocked, gated on city power **and** character level ≥ 12 (§9.4).

**Cumulative authored geometry: Camp 180 → Village 668 → Town 1 414 → City 2 452.**
That is authored, not drawn, and it is never all in frame at once. §7 is where that is proven.

---

## 4. THE CITY AND THE FOUNDRY

`DIRECTION.md` §3 is the keystone: *"you'd have to have like a well lit city manufacturing them and the
ammunition."* This is the mechanism.

### 4.1 What the city must sustain

Four conditions, checked once per in-game day:

| # | Condition | Value |
|---|---|---|
| **F1** | Settlement tier | **CITY** (grid points ≥ 72 in the 320 m ring) |
| **F2** | `CORE_LUX` | **≥ 2048** |
| **F3** | Great Lantern | **tier ≥ 4** |
| **F4** | **The feeder line** | **≥ 6 lit lanterns forming an unbroken Wick Line chain from the Great Lantern to the Foundry's own post** |

**F4 is the one that makes this a game rather than a number.** A global average is not a place; a
*specific chain of six posts you have to walk* is. It is the same 90 m Wick Line linking `lantern.hml`
already computes, evaluated as a graph path from node 0 to the Foundry node. It gives the player a
named route to maintain, it is the obvious thing to defend during a night hold, and it means the
Foundry's power has a geography the player can point at.

### 4.2 Output — the five tiers `MAGIC_KINETIC` §6.1a already promised

| Output tier | Grid points | Manufactured rounds / in-game day | City ammo price |
|---|---|---|---|
| **O0 COLD** | < 72, or F2/F3/F4 failing | **0** | — |
| **O1** | 72 – 89 | 60 | 1.00× |
| **O2** | 90 – 109 | 120 | 0.85× |
| **O3** | 110 – 133 | 200 | 0.72× |
| **O4** | 134 – 161 | 300 | 0.60× |
| **O5** | ≥ 162 | **420** | 0.50× |

An in-game day is 16 real minutes. O5 needs ~81 linked posts against ~78 natural anchors in the 320 m
ring, so the top tier requires **player-placed lantern kits** on top of every natural post. That is a
real endgame and it costs nothing to build — the kits already exist (GDD §4.5).

**The shop inventory is the readout.** `DIRECTION.md` §3: *"visible in the shop inventory, which is the
Animal Crossing pillar."* No UI for grid points is needed anywhere. The player learns the system by
noticing the Arsenal has more brass this week.

### 4.3 What happens when it fails — three stages, and none of them disarms the player

| Stage | Trigger | Effect |
|---|---|---|
| **FLICKER** | any of F1–F4 failing for < 1 in-game day | production **halves**. Shop sells stock on hand. Foundry windows flicker at 0.7 Hz. |
| **BROWNOUT** | ≥ 1 in-game day | production **stops**. Shop sells remaining stock only, at 1.4× price. The stack's plume goes out. Manufactured guns **still fire.** |
| **COLD** | 7 real days, **or** grid points < 58 (80 % of threshold) | the Foundry's fire is out. Restart costs **200 Ember + a fully lit feeder line + 1 in-game day of warm-up.** |

> **The player is never disarmed.** The bolt-action, the revolver, the pump shotgun and the pipe-SMG
> are crafted at Mabel's bench from world materials and have never depended on the city. Losing the
> city costs you *rate of fire and reach*, not your ability to play. This is `DIRECTION.md` §4's
> "never solo-hostile" applied to the harshest system in the design, and it is why the ladder can be
> punishing at all.

And it is the right feeling: *a man will lend you his rifle and not lend you six rounds for it*
(`LORE.md` §6a). A cold city is a world where you go back to counting brass.

---

## 5. LAYOUT GENERATION — THE ALGORITHM

Seven passes. All pure functions of `(seed)` except pass 6, which reads the delta log. No allocation
beyond fixed-size caller-owned arrays.

### 5.0 Why this shape

A procedural town reads as *noise* when buildings are scattered and *intentional* when they are
**subordinate to something**. Here everything is subordinate to three roads, and the roads are
subordinate to the terrain. That single hierarchy is the whole trick, and it means the layout has an
argument for every position: *this building is here because it fronts this road, and this road is here
because it is the only way out of this hollow.*

### 5.1 Pass 0 — the frame

`(C, θ₀)` from §1.4. Everything below is in the settlement frame. Two seeds with the same terrain
statistics produce recognisably different towns because θ₀ differs.

### 5.2 Pass 1 — the green

- A **20 m × 20 m terraced deck** at `settle_site_deck_y`, on the 4 m grid: 5×5 = 25 quads.
- Cobble in the central 8×8 m (the dais); `CELL_PATH` outside.
- **Kerb walls** on all four sides, `sm_wall` with `p_conform = 2` (both edges follow the height
  field) down to terrain. This is what makes a terrace legal on a 10 m/32 m slope: the deck is level,
  the kerb absorbs the difference, and nothing floats.
- The terrace is written as a **chunk edit overlay** (`chunk_set_edit`) — 8×8 = 64 samples ≈ 768 bytes,
  inside `chunk.hml`'s 4096-edit cap. Terrain edits already persist and already survive save/load; the
  green needs no new format. (This is where `worldgen.hml`'s *"levelling the town plot is hubgen's
  job"* comment resolves — see §11.5.)
- The Great Lantern stands on the dais. Radius 16 m around C is the **green keep-out**: no plot may
  intersect it, and it is the `wick_decay = 0` zone.

### 5.3 Pass 2 — three roads, and only three

Not a network. **Three radial spines, each with a reason to exist:**

| Road | Bearing | Appears at | Reason |
|---|---|---|---|
| **The High Road** | θ₀ | Camp | out through the view corridor. **This is where the player arrives from and it is the money-shot axis.** |
| **The Wick Road** | bearing of the nearest lantern anchor outside 64 m | Village | **connects the town to the grid.** The road network and the lantern network are the same network — which is not a mechanic dressed as fiction, it is what `LORE.md` §7 says the paving under a Wick Line literally is. |
| **The Back Lane** | θ₀ + 180° ± jitter(±25°, hashed) | Town | the second axis. **Its appearance is how a promotion reads from the green.** |

**Road generation — greedy least-grade stepping.** From C, 12 steps of 8 m. At each step, evaluate 3
candidate headings (`ψ − 20°`, `ψ`, `ψ + 20°`) and take the one with the smallest `|Δheight|` over the
8 m step; then pull `ψ` back toward the target bearing by 40 %.

```
ψ ← target
for step in 0..11:
    best ← argmin over δ ∈ {−20°, 0°, +20°} of  |h(p + 8·dir(ψ+δ)) − h(p)|
    p ← p + 8 · dir(ψ + best)
    ψ ← ψ + best
    ψ ← ψ + 0.40 · angle_diff(target, ψ)      // it always remembers where it is going
```

96 m of road, 16-point polyline, 25 `worldgen_height` calls per road. This produces a road that
**bends around a hill instead of climbing it** while never losing its destination — which is exactly
the "connect rather than wander" read. A wandering road has no argument; this one has two.

Roads are laid as 4 m × 4 m deck quads (2 quads per 8 m segment, to keep quads ≤ 4 m so the affine-UV
ground warp stays charming — CLAUDE.md §6).

### 5.4 Pass 3 — the plot lattice

**Along each road, on both sides, at 14 m pitch, mark 12 plots.** A plot is a **12 m × 10 m** rectangle
with:

- its **long edge flush with the road edge**, offset 2 m for a verge;
- **yaw = road segment bearing + 90°·side**. Every building faces the road *by construction*. This one
  line is the difference between a village and a scatter plot;
- `PLOT_ID = road·24 + side·12 + slot`, `road ∈ 0..2`, `side ∈ 0..1`, `slot ∈ 0..11`.

**72 plots.** A City uses 24. The lattice never runs out and therefore never needs re-planning, which
is what lets the accretion order be permanent.

### 5.5 Pass 4 — validity

A plot is buildable iff **all** of:

| Test | Threshold | Why |
|---|---|---|
| Corner height range | ≤ **2.4 m** over the 4 corners | `sm_building` runs its walls 1.4 m below the sill and its footing course conforms; 2.4 m is what that hides |
| Distance from C | ≥ **16 m** | the green keep-out |
| Biome at plot centre | ≠ `WG_BIOME_FEN` | |
| Overlap | guaranteed none | the lattice is disjoint by construction |

**Invalid plots are skipped, never moved.** A gap in a row of houses where the ground is bad reads as
*more* intentional than a shuffled building — the town visibly declined to build on the boggy bit. A
nudged building reads as a bug.

### 5.6 Pass 5 — the accretion order

> **A plot, once assigned a building, keeps that building forever. Growth only ever appends.**

Sort all valid plots by

```
key = ( floor(dist(plot, C) / 24) ,  road ,  side ,  |slot − 5.5| ,  sign(slot − 5.5) )
```

— i.e. **ring by ring outward from the green; within a ring, road by road; within a road, alternating
sides outward from the centre.** Computed once, cached, 72 entries.

Building number `n` of the settlement goes on `order[n]`. **Always.** Same seed, same order, forever,
regardless of the path any player took to get there.

This is what makes growth legible:

- the town **grows outward in rings**, so the centre is the oldest and the edge is the newest;
- the **frontier of construction is a visible ring**, which is `MULTIPLAYER.md`'s spatial gradient made
  architectural — safe core, maintained ring, work site, empty plot, dark;
- a returning player, or a player arriving on a shard for the first time, can **read the town's age off
  its geometry** with no UI at all.

### 5.7 Pass 6 — assignment, and one refinement

Each tier's manifest (§3.3) is an ordered list of kinds. Kind `i` goes to `order[i]`, so **services
land nearest the green** and houses fill outward.

One refinement, worth the complication: **the first plot on each road must be a service, not a
house.** Otherwise the Wick Road and Back Lane are streets of nothing and nobody walks down them. So
the manifest interleaves — `[Bench, Inn, Cottage, Board, Cottage, Cottage, Almanac, Cottage, …]` — with
the constraint enforced at assignment: if `order[i]` is `slot 0` of a road that has no service yet,
pull the next service forward.

**Naming.** `settle_site_name` indexes a 16 × 8 table:

```
[Ember, Grendle, Marrow, Thistle, Ashen, Bell, Corbie, Fallow,
 Harrow, Ladle, Mordent, Pallow, Quill, Saltby, Tarn, Withy]
   ×
[Hollow, Reach, Watch, Fold, Bell, Mill, Gate, Wick]
```

128 names. **Index 0 is Ember Hollow** and is the canonical/tutorial seed. `LORE.md` §11.2.2 already
leaves the room: *"Some of them founded towns you have not found."*

---

## 6. GROWTH MADE VISIBLE

The Animal Crossing pillar is *"the town grows because you came back."* A player must see change after
a session, and must be able to tell at 320×240 what state a building is in.

### 6.1 Four construction states, four silhouette heights

Each state is a **different mesh**, not a scaled one, and each is **cheaper than the next** — so
construction never spikes the budget.

| State | Geometry | Authored | Silhouette height | Reads at 320×240 as |
|---|---|---|---|---|
| **STAKED** | levelled dirt pad (1 deck quad) + 4 corner stakes (4 tris each) + a rope line (2) | **20** | **0.3 m** | a pale rectangle on the ground with four ticks. "Something is going here." |
| **FRAMED** | STAKED + the footing course (`sm_building`'s footing walls, rows = 1) + 4 corner posts | **~48** | **1.2 m** | a dark ring at ground level with posts. **Low and open** — unmistakably not a house. |
| **CLAD** | full walls, **no roof deck, no fascia** | archetype − (roof + fascia) | **eaves** | walls with sky above them. The roofline is missing and that is the read. |
| **DONE** | full archetype + chimney + door + window glow card | archetype | **eaves + 0.62 fascia + chimney** | a house. |

Four heights against the sky, resolvable at 40 m without a single new texture. The `g_EAVE = 0.62` m
fascia band was measured in `shot.hml` to give **four native pixels of hard dark value at 34 m**, so
its presence or absence is the CLAD→DONE tell at real distance.

**Plus 4 free triangles of scaffolding.** During FRAMED and CLAD, one lean-to scaffold on the
road-facing side. Four triangles that say "work in progress" from 40 m.

### 6.2 Pacing

- On promotion, **every new plot STAKES instantly.** The player immediately sees the *shape of the
  future town* — which is a strong Animal Crossing beat and costs 20 tris per plot.
- Then buildings advance **one state per in-game day (16 real minutes) per work site.**
- **Work sites = tier + 1.** Village 2, Town 3, City 4. Growth accelerates as the town grows, which is
  the correct feel.
- A work site is **visible**: scaffold + one ambient villager in a working pose.

| Transition | Buildings | Steps | Sites | In-game days | **Real time of maintained light** |
|---|---|---|---|---|---|
| Camp → Village | 7 (start at FRAMED — a camp's ruins have footings) | 14 | 2 | 7 | **1.9 h** |
| Village → Town | 8 | 24 | 3 | 8 | **2.1 h** |
| Town → City | 11 | 33 | 4 | 8.25 | **2.2 h** |

~2 hours of maintained light per tier build-out — **two sessions.** Every session shows several
buildings advancing a state. That is the requirement, met with a number.

**A construction step only fires while the tier's threshold is held.** If the grid falls, the work
stops where it stands, and a half-clad house on the green is the most legible possible reminder that
somebody has to do the rounds.

### 6.3 The notification

One HUD toast on entering the settlement: `ODO'S INN — CLAD`. Uses the existing toast; strings built
at ≤ 4 Hz (CLAUDE.md N3). No new HUD geometry.

### 6.4 And from 300 m away — the light dome, at zero triangles

Nothing at 300 m is drawn: `FOG_FAR` never exceeds 72 m. So "find home from the frontier" **cannot be
geometry.** It is the sky.

`skygen.hml` already re-bakes 20 rows per frame into `TEX_SKY` and already carries a horizon band
(`hub_dawn` ships `horizon 231,164,104`). **The settlement writes a warm dome into the horizon band on
its own bearing**, with angular radius and intensity proportional to `GRID_LUX`:

```
dome_half_angle = 6° + 14° · min(1, GRID_LUX / 18432)
dome_lift       = 0.10 + 0.22 · min(1, GRID_LUX / 18432)     // added to the horizon band, warm
```

**Zero triangles, zero draw calls, inside the existing 0.6 ms sky re-bake budget.** A village is a
faint smudge on the horizon; a city is an unmistakable glow you can navigate by at night from
anywhere on the shard. It is the best-value idea in this document and the engine already does the work.

---

## 7. THE TRIANGLE BUDGET — THE SECTION THAT DECIDES IT

**2500 drawn steady / 3500 hard clamp. Measured, not projected.**

### 7.1 What a building actually costs

From `tools/shot.hml`'s `sm_building`, counted from the code:

```
quads = 2·rows·(px + pz)     main walls, 4 faces
      + 4·(px + pz)          footing course, 4 faces, 1 row
      + px·pz                roof deck
      + 4·(px + pz)          fascia band, 4 faces, 1 row
tris  = 2 · quads
```

**Drawn** is what matters for the cap. From outside a closed box you see exactly **2 of 4** wall faces,
2 of 4 footing faces, 2 of 4 fascia faces, and **zero** of the roof deck (its normal is +Y and the
camera eye is at 2.4 m, below every eaves line in the project). Backface culling removes the rest for
free — measured at **62.9 % on a closed mesh** (`BUDGET_ACTUAL.md`).

| Archetype | px | pz | rows | Footprint | Eaves | **Authored** | **Drawn** | % |
|---|---|---|---|---|---|---|---|---|
| **Shack** | 1 | 1 | 2 | 4×4 m | 2.6 m | 34 | **16** | 47 |
| **Cottage** | 2 | 1 | 2 | 8×4 m | 2.8 m | 52 | **24** | 46 |
| **House** | 2 | 2 | 3 | 8×8 m | 3.4 m | 88 | **40** | 45 |
| **Hall** | 3 | 2 | 3 | 12×8 m | 4.2 m | 112 | **50** | 45 |
| **Works** (Foundry) | 4 | 3 | 3 | 16×12 m | 5.4 m | 164 | **70** | 43 |
| **Tower** | 1 | 1 | 4 | 4×4 m | 9.0 m | 50 | **24** | 48 |
| **Stack** | 1 | 1 | 5 | 4×4 m | 12.0 m | 58 | **28** | 48 |

Add-ons: cast shadow `sm_shadow` **+2 (always drawn**, faces up, mandatory per CLAUDE.md §9.6);
chimney **+10 authored / +6 drawn**; door quad **+2/+2**; window glow **+2 in the FX layer, not WORLD**.

Cross-check: `docs/shots/budget_worst.stats.txt` ships two of these buildings inside a frame that draws
**2459** of 2500 with `rej.backface = 1638`. The formula is not a projection.

### 7.2 The three building LOD rungs

A building is registered as an ordinary prop. `entity_prop_add(m0, m1, m2, d1, d2, …)` already takes
three LOD meshes and switches on distance. **No renderer change is required.**

| Rung | Distance | Geometry | Authored | Drawn |
|---|---|---|---|---|
| **B0 full** | **< 18 m** | the archetype: 4 walls, footing, roof deck, fascia, chimney, door | 34–222 | 16–100 |
| **B1 facade** | **18 – 40 m** | **only the 2 walls facing the camera hemisphere**, their footing and fascia, plus the cast shadow. No back walls, no roof deck. | ≈ B0 drawn | **= B0 drawn** |
| **B2 block** | **> 40 m** | a **6-triangle box** (three faces: two walls + top, `mg_vm_shell`'s delete-the-invisible-faces trick) at the archetype's AABB, at its mean albedo, **+ 1 fascia band quad (2)** so the roofline still reads dark against the sky, **+ cast shadow (2)** | **10** | **10** |

**B1 is free triangles and real milliseconds.** It authors *exactly* the faces that survive backface
culling, so the drawn count is identical and the **submitted** count halves. Submitted is what costs
time — `BUDGET_ACTUAL` measures emit + pack at 3.57 ms for 2500 submitted. B1 attacks the millisecond
budget without touching the triangle budget. B0 exists **only** for the downhill camera that can see a
roof deck; 18 m is where that stops mattering.

**How B1 picks its two walls without a per-frame mesh write.** Author **4 variants per archetype at
boot**, one per sector, and pick with `atan2`. Critically, **the sector boundaries sit on the face
normals, not on the corners:**

```
sector = floor( wrap2pi(atan2(camz − bz, camx − bx) − yaw) / (π/2) )
```

At a boundary the camera is square-on to one face: that face is in both neighbouring variants, and the
two faces that swap are both **exactly edge-on, at zero screen area.** The pop is provably invisible.
Put the boundaries on the corners instead and a fully-visible wall vanishes — that is the bug this
paragraph exists to prevent.

**Library cost:** 6 archetypes × 4 construction states × (1 B0 + 4 B1 sectors + 1 B2) ≈ 144 meshes,
~5 800 triangles of mesh library. `meshgen.hml` currently reports "34 meshes, 2500 triangles in the
library" and builds inside the 400 ms boot allowance; this roughly triples it. **Flagged as the one
real cost of this design** — see §7.6 for the mitigation if boot time misses.

**Why a box and not a billboard.** The brief offers "a skyline that is billboards beyond a radius". A
billboard must rotate to face the camera, which at 320×240 with pixel-snapped vertices reads as
*swimming*, and it cannot carry a corner — and a corner is the one thing that makes a building read as
solid. **6 triangles instead of 2 buys a real corner and a real silhouette.** Best four triangles in
the design.

### 7.3 Fog: the settlement runs at `FOG_FAR = 56 m`

`config.hml` sets `g_FOG_FAR_TIER0 = 72.0` — tier 0 sees furthest, because safety is legible as
distance. **The settlement overrides that to 56 m** and it is not a budget cheat:

- **The fog *colour* carries the tier, not the distance.** Warm ochre reads as safe at any distance.
  Cold slate reads as hostile at any distance. GDD §4.2 gives both; the colour is what the player
  actually reads off the horizon.
- **A town is where fog belongs.** Hearth smoke, lantern haze, a damp valley bottom. Warm *dense* air
  is the opposite read from cold thin air, and it is the difference between "I can't see" and
  "I'm inside something".
- **`hub_dawn` already ships at `FOG_FAR = 52` and it is the money shot** (`docs/shots/hub_dawn.stats.txt`).
  This is not a new idea; it is what the shipping hub frame already does.
- CLAUDE.md §6: *"when the budget breaks, turn `FOG_FAR` down first — it is the designed dial."*

**Ramped, never stepped:** linear from 56 m at the tier ring to the biome's value over the following
32 m. At 5 m/s that is 6.4 s of transition, against ART_BIBLE's ≥ 3 s requirement.

Ground cost, `(π/4)·d²/16·2`: **72 m → 509 tris. 56 m → 308 tris. 48 m → 226 tris.**

Proposed constant: **`g_FOG_FAR_SETTLEMENT = 56.0`**, a *place* override, not a *tier* override. A lit
lantern's tier-0 disc out in the wild keeps 72 m.

### 7.4 Humanoid caps — the real budget problem, and it is not the buildings

ART_BIBLE §8.3 budgets an NPC at **220 triangles** with the note *"more charm budget, they're static
and few."* In a City they are neither. Five named NPCs at LOD0 is 1 050 authored, which alone eats 40 %
of the frame.

**Two humanoid classes, not one:**

| Class | LOD0 | LOD1 | LOD2 | Switch | Cap |
|---|---|---|---|---|---|
| **Named NPC** (the five) | 210 | 90 | 28 | 12 / 28 m | **1 at LOD0** |
| **Ambient villager** | **48** | **28** | **12** | 10 / 22 m | **6 visible** |

- The named-NPC ladder costs **zero new code**: `build_humanoid(class, lod)` already produces 186/90/28
  for enemies. Point it at NPC colours.
- **`SET_MAX_NPC_LOD0 = 1`** is fine because you only ever talk to one person, and the one you're
  facing is the nearest. A second named NPC inside 12 m draws at LOD1 and nobody at 320×240 will tell.
- **A villager is not an enemy and does not have to satisfy RULE S1.** It needs to read as "a person,
  doing something", not "identify the class at 12 px". 48 triangles covers that at 37 px. This is the
  single biggest saving in the design and it is justified by what the asset has to *do*.
- **`SET_MAX_HUMANOID_VISIBLE = 8`**, shared across named NPCs, villagers and (in v2) other players.
  **Players take priority.** The 8 nearest in-frustum are emitted; the rest are not.

### 7.5 The worst realistic city frame

Camera on the green at the High Road junction, dusk, `FOG_FAR = 56`, looking down the High Road. This
is the densest legal settlement view and the proposed money shot (`--scene city_dusk`).

Visible wedge at 81° horizontal FOV: `0.225 · π · 56² = 2 217 m²`. At a 14 m plot pitch on three
radiating roads that is **~17 buildings in frustum**: 2 within 18 m, 6 in the B1 band, 9 in the B2 band.

| Line | Detail | **Drawn** |
|---|---|---|
| Ground | `(π/4)·56²/16·2` | 308 |
| Green: deck (25 quads, ~60 % in wedge) + kerb (2 of 4 sides) | | 50 |
| Roads in wedge | 12 segments × 2 quads | 48 |
| Buildings **B0** | 2 × avg 52 | 104 |
| Buildings **B1** | 6 × avg 45 | 270 |
| Buildings **B2** | 9 × 10 | 90 |
| Cast shadows | 17 × 2, all up-facing | 34 |
| Chimneys + doors on the 2 B0 | | 16 |
| Great Lantern + 4 Wick posts | 30 drawn each | 150 |
| Well, stall, board, palisade arc, crates, player-built fences | | 160 |
| **Humanoids** | 1 named LOD0 (105) + 2 named LOD1 (90) + 2 villagers LOD0 (48) + 4 villagers LOD1 (56) | **299** |
| Viewmodel (lantern) | 122 authored | 120 |
| **WORLD LAYER SUBTOTAL** | | **1 649** |
| Sky | measured, both shipped stats files | 80 |
| FX | 20 window glows + 8 stack plume + 6 smoke + 12 strung lights = 46 cards | 92 |
| HUD | measured `budget_worst` | 206 |
| Post-FX | ART_BIBLE §8.3 | 18 |
| **TOTAL DRAWN** | | **2 045** |

### **2 045 of 2 500. 455 triangles — 18 % — of headroom. The city fits.**

**Submitted**, which is what costs milliseconds: B0/B1/B2 author ~510 against 464 drawn; humanoids
author 598 against 299; the frustum-culled tail adds ~120. **≈ 2 510 submitted** — just under where
`budget_worst` already sits (**2 660 submitted / 2 459 drawn**, measured at **12.76 ms excluding the
one-shot sky bake**, on a box permanently sharing 17 of 24 cores). This frame is inside proven
territory, not extrapolated into it.

Against the **1 806 measured in play**, a City costs **+239 drawn** — it consumes a third of the
existing ~694 triangles of headroom and leaves 455. A Village costs **−477** and is *cheaper* than the
frame the game already renders.

**Why there is room at all:** *the settlement is the one place with no combat.* A wild combat frame
spends **5 enemies × 90 = 450** plus **~120 of muzzle/tracer/impact FX** — 570 triangles the settlement
never spends. The city is built out of the combat allocation. GDD §5 said exactly this
(*"always rendered at LOD0 because it is the only place with no combat and therefore has budget to
spare"*); this document is the arithmetic behind it.

**Village worst frame, for comparison:** 226 (ground @ 48 m — a village keeps a wider view because it
has less to hide) + 50 green + 30 roads + 162 buildings + 14 shadows + 90 lanterns + 60 props + 223
humanoids + 120 viewmodel + 80 sky + 50 FX + 206 HUD + 18 post = **1 329 drawn**. Settlement geometry
alone (excluding ground, viewmodel, humanoids, HUD) = **406 drawn**.

### 7.6 Hard caps, and what happens when one bites

Enforced in the emit walk, not hoped for:

```
SET_MAX_BLD_FULL       = 8      B0 + B1 combined, the nearest in-frustum
SET_MAX_BLD_BLOCK      = 16     B2
SET_MAX_HUMANOID_VIS   = 8      shared; players first, then named NPCs, then villagers
SET_MAX_NPC_LOD0       = 1
SET_PLAYER_BUILD_TRIS  = 120    drawn, for everything on the green's 1 m grid
```

**A building past the cap is demoted one rung, never dropped.** Dropping a building punches a hole in a
street and reads as a bug; demoting one is invisible. `SET_PLAYER_BUILD_TRIS` is enforced by
**refusing the placement**, not by dropping geometry — `shot.hml`'s own note on `structure_mesh_new`
records exactly how expensive a silent cap is (*"the frame simply comes back missing a thing nobody
mentioned"*).

**Escape hatches, in CLAUDE.md §6's priority order,** if the city ever needs more:

| # | Lever | Saving |
|---|---|---|
| 1 | `FOG_FAR` 56 → 48 in the core | **−128** (ground −82, 3 fewer B2, 4 fewer road quads) |
| 2 | `SET_MAX_BLD_FULL` 8 → 6 | **−90** |
| 3 | `SET_MAX_NPC_LOD0` 1 → 0 (all named at LOD1) | **−60** |
| 4 | B1 switch 18 m → 14 m | **0 drawn, −140 submitted** |
| 5 | B2 radius 40 m → 32 m | **−70** |
| | **Total available** | **≈ −348 drawn**, taking the worst city frame to **~1 697** |

**Never** cut the frame rate. A gorgeous 40 fps FPS is a bad FPS.

**If the mesh library's ~5 800 triangles miss the 400 ms boot allowance:** drop the four B1 sector
variants for **Shack, Cottage and Tower** (the small archetypes, where the difference between B1 and B0
is 8–16 triangles) and let them use B0 out to the B2 radius. That halves the library at a cost of
~40 submitted triangles per frame. Measure before deciding — the existing 34-mesh library builds today
and the boot budget has never been the binding constraint.

---

## 8. ARCHITECTURE

Signatures in `ARCHITECTURE.md` §5 style. **Settlement state is world state: it lives in `src/sim/**`,
it is deterministic, it takes no clock, and it is in the delta log.**

### 8.1 `src/sim/settle.hml` — NEW. Owns everything in §1, §2, §3, §5.

Imports `src/core/mathx.hml`, `src/sim/worldgen.hml`, `src/sim/lantern.hml`. No SDL, no wobbleweed, no
`@stdlib/random`, no wall clock. Site selection and the lattice are **pure `f(seed)` via `xhash2`** — no
RNG state at all, which is what makes them regenerable rather than persistable.

```hemlock
// ---- site selection: pure f(seed).  ~16 ms, ONCE per world, at creation.
settle_site_x(seed: i32): f64                        // world metres
settle_site_z(seed: i32): f64
settle_site_bearing(seed: i32): f64                  // radians; the High Road axis
settle_site_deck_y(seed: i32): f64                   // the green's terrace height
settle_site_name(seed: i32): i32                     // 0..127, index into the name table
settle_site_score(seed: i32, sx: f64, sz: f64): f64  // exposed for tools/probe_settle --survey

// ---- the plot lattice and the roads: pure f(seed).  72 plots, stable forever.
settle_plot_count(): i32                             // SET_PLOTS = 72
settle_plot_x(seed, pid: i32): f64                   // pid = road*24 + side*12 + slot
settle_plot_z(seed, pid: i32): f64
settle_plot_yaw(seed, pid: i32): f64                 // faces the road, by construction
settle_plot_valid(seed, pid: i32): i32               // 0/1: slope, biome, green keep-out
settle_plot_order(seed, n: i32): i32                 // accretion order -> pid, or -1
settle_road_point(seed, road: i32, step: i32, out: array<f64>): i32   // out[0]=x, out[1]=z
settle_road_count(tier: i32): i32                    // 1 / 2 / 3 / 3

// ---- the field.  LUX is an i32 in 1/256 of one unlinked lit lantern at its post.
settle_lux_at(st, wx: f64, wz: f64): i32             // capped at SET_CL_MAX = 4096
settle_core_lux(st): i32
settle_grid_lux(st): i32
settle_grid_points(st): i32                          // grid_lux / 256 — MAGIC_KINETIC's number
settle_wick_decay(st, wx: f64, wz: f64): i32         // per real hour, 0..16 of 256

// ---- the store: mutable settlement state, part of the shard
settle_new(seed: i32): object
settle_tier(st): i32                                 // SET_TIER_CAMP..SET_TIER_CITY
settle_tier_ever(st): i32                            // high-water mark; never demote past it
settle_brownout(st): i32                             // 0/1
settle_step(st, tick: i32): i32                      // -> SET_EV_* bitmask; runs 1 tick in 60
settle_promote_check(st): i32                        // the tier the field currently justifies
settle_hash(st): i32                                 // folded into sim_hash

// ---- buildings
settle_building_count(st): i32
settle_building_pid(st, i: i32): i32
settle_building_kind(st, i: i32): i32                // SET_B_SHACK..SET_B_WORKS
settle_building_state(st, i: i32): i32               // SET_CON_STAKED..SET_CON_DONE
settle_building_advance(st, i: i32): i32             // one construction step
settle_worksite_count(st): i32                       // = tier + 1
settle_solids_fill(st, cam_x, cam_z, out: array<f64>): i32   // AABBs for move_apply_ex

// ---- industry
settle_industry(st): i32                             // SET_IND_COLD/BROWNOUT/FLICKER/RUNNING
settle_output_tier(st): i32                          // O0..O5
settle_ammo_rate(st): i32                            // manufactured rounds per in-game day
settle_feeder_lit(st): i32                           // lanterns on the Foundry's Wick chain
settle_feeder_node(st, i: i32): i32                  // lantern id, for the HUD route marker
```

### 8.2 `src/art/hubgen.hml` — RE-SCOPED (was W5-2)

Builds the **archetype mesh library only**. Layout moves to `settle.hml`. See §11.2.

```hemlock
hubgen_build_all(): i32                              // boot; inside the 400 ms allowance
hubgen_mesh(kind: i32, con: i32, rung: i32, sector: i32)   // -> a mesh handle
hubgen_tris(kind, con, rung, sector): i32
hubgen_aabb(kind: i32, out: array<f64>): i32         // 6 f64, for move_solids_add
HG_B_SHACK..HG_B_WORKS · HG_CON_STAKED..HG_CON_DONE · HG_RUNG_B0/B1/B2 · HG_SECT_0..3
```

### 8.3 `src/game/` — the glue, and there is almost none

**The renderer needs zero changes.** A building is an ordinary prop:

```hemlock
entity_prop_add(hubgen_mesh(kind, con, HG_RUNG_B0, 0),
                hubgen_mesh(kind, con, HG_RUNG_B1, sector),
                hubgen_mesh(kind, con, HG_RUNG_B2, 0),
                18.0, 40.0, radius, x, y, z, yaw, 1.0, tr, tg, tb, 0.0, TAG_BUILDING)
```

`entity_prop_add` already takes three LOD meshes and switches on distance (`src/render/entity_render.hml`).
The **only** per-frame decision is the B1 sector, and the prop registry is refilled by the caller each
frame anyway (`entity_prop_clear` then re-add) — so the sector pick happens in `src/game/`, where it is
allowed to know about both art and sim. **The renderer reads and never writes; nothing in `src/render/`
learns what a settlement is.**

Optimisation: buildings are static within a construction state, so the game module caches the registry
fill and rebuilds it only when `settle_hash` changes (or the camera crosses a sector boundary for a
building inside the B1 band).

**Collision** is free: `hubgen_aabb` → `move_solids_add` → `move_apply_ex`, which already takes a
caller-owned flat `array<f64>` of 6-f64 AABBs. 8 buildings within 22 m = 48 f64.

### 8.4 The sim tick order

`ARCHITECTURE.md` §4.3's order **is API**. This is an addition at step **(h)** — *"day-cycle tick, chunk
streaming decisions"* — not a reorder:

```
  h  day-cycle tick, chunk streaming decisions, SETTLEMENT STEP (1 tick in 60)
```

### 8.5 The delta log — a whole city is 384 bytes

`save.hml`'s framing is a wire contract: append tags, never renumber; append columns, never insert.
**Two new tags, 29 and 30:**

```
SAVE_T_SETTLE        rows = building count
  cols_i32 = 4:  pid, kind, con_state, con_progress_ticks
SAVE_T_SETTLE_META   rows = 1
  cols_i32 = 8:  tier, tier_ever, industry, industry_cold_ticks,
                 ammo_stock, feeder_head_id, worksite_cursor, brownout
```

**24 buildings × 4 i32 = 384 bytes for a complete City.** Rows are emitted **sorted by `pid`**, never in
insertion order, so equal state produces equal bytes — the same canonicalisation `CHUNKRING` already
uses.

**Not persisted, because it is `f(seed)`:** the site, the terrace height, the name, the roads, all 72
plot positions and yaws, plot validity, and the entire accretion order. This is the identical argument
`save.hml` already makes for chunk heights, and it is what makes a shard `seed + deltas`.

**Also not persisted here:** lanterns and wick health are `lantern.hml`'s delta records.
`settle.hml` only ever *reads* the lantern set — it must never own a lantern, or the two modules will
disagree about what is lit.

**The green's terrace** rides in the existing `SAVE_T_CHUNKEDIT` record at 12 bytes per edited sample —
64 samples, 768 bytes, inside `chunk.hml`'s 4096-edit cap. No new format.

### 8.6 Acceptance criteria a task can be measured against

| # | Criterion | Number |
|---|---|---|
| A1 | `--scene city_dusk` worst frame | **≤ 2 200 drawn**, `batch.overflow = 0` |
| A2 | `--scene village_dawn` worst frame | **≤ 1 400 drawn** |
| A3 | Settlement WORLD geometry alone at Village | **≤ 600 drawn** (see §11.1) |
| A4 | Frame time in `city_dusk`, excluding the one-shot sky bake | **≤ 13.5 ms** |
| A5 | `settle_step` | **≤ 0.05 ms**; amortised **≤ 0.001 ms/frame** |
| A6 | Site selection at world creation | **≤ 25 ms**, once, off the frame path |
| A7 | Determinism | 8 seeds × 3 runs × interpreter and compiler produce identical `settle_hash`, identical plot order, identical site |
| A8 | Save round trip | a City survives encode→decode with an identical `settle_hash` and byte-identical re-encode |
| A9 | Growth is append-only | over 10 000 simulated ticks with the grid driven up and down randomly, **no building ever changes plot and no DONE building ever regresses** |
| A10 | Nothing floats | every building's footing course reaches terrain at all four corners (assert over all 72 plots × 8 seeds) |
| A11 | Boot | `hubgen_build_all` inside the remaining 400 ms allowance, measured |

---

## 9. MULTIPLAYER

`MULTIPLAYER.md`: the character travels, the world is collective.

### 9.1 Players do not place settlement buildings. Players enable them.

The layout is `f(seed)` and the accretion order is fixed, so **two players lighting lanterns in
different orders on different days produce the identical town.** That single decision:

- **kills the coordination problem** — nobody has to agree on anything;
- **kills griefing by ugly placement** — there is no placement to grief;
- **means a returning player recognises the town even if they weren't there when it grew**, which is
  the entire Animal Crossing pillar with other people in it.

### 9.2 What players *do* author

| Layer | Who | Where | Destructible by players? |
|---|---|---|---|
| **Lanterns** (kits, anywhere) | any player | the whole world | **No — only by the dark.** `MULTIPLAYER.md` §3, unchanged. |
| **Expressive structures** on the 1 m grid | any player | **inside the green only** (r ≤ 16 m) | Yes, by the placer |
| **Settlement buildings** | nobody | the 72-plot lattice | Never |

The green's 1 m grid is *inside* the plot keep-out radius, so player expression can **never** collide
with settlement growth. That is not a coincidence — it is why the keep-out radius exists.
`SET_PLAYER_BUILD_TRIS = 120` drawn, enforced by refusing the placement.

### 9.3 What a town reads like to someone arriving for the first time

Three cues, in the order you meet them, **none of them a menu**:

1. **The sky dome** (§6.4), from anywhere on the shard. Big glow = old world.
2. **The Watch Tower**, at 9 m, cresting the fog wall on the approach along the High Road.
3. **The construction states along the roads.** A ring of DONE, then a ring with scaffolds, then a ring
   of stakes, then empty plots. **You can read the town's age, its momentum, and where the frontier is,
   off its geometry.** A town mid-build reads as *somebody's project*, which is the social read this
   model needs.

Then exactly one HUD line on crossing the ring: `GRENDLE HOLLOW — TOWN — 22 / 32`.

**No plaques, no "built by".** Deliberate: a collective world where every contribution is signed
becomes a leaderboard. The town is the monument. (Opinionated. Flagging it as a choice, not a fact.)

### 9.4 Twinking — `MULTIPLAYER.md` §2's open question, answered: **GATE, both ways**

- **Manufactured weapons** require city power **and** character level ≥ 12.
- **Manufactured ammunition is bound to the world that made it.** It does not travel.

The gun travels; the brass does not. Thematically exact — *the city made these rounds* — and it means
a veteran world is worth **living in** rather than raiding. It also makes the ammo economy per-shard,
which is what stops one solved world from trivialising every fresh one.

**This is a deliberate exception** to "the character travels": one carried resource does not. Flagged
in §11.7.

### 9.5 Concurrency — `MULTIPLAYER.md` §1's open question, answered from the geometry

72 plots, ~24 built at City, 3 roads, an 80 m core. **Recommend a cap of 16.** That is "a small town",
it fills the green without a queue at the bench, and it falls out of §7.4's budget: **players and NPCs
share one 8-visible humanoid cap, and players take priority.** Above ~24 the settlement stops reading
as a place and starts reading as a lobby, and the humanoid cap starts hiding the NPCs the town is
supposed to be made of.

### 9.6 The shared night hold falls out for free

`MULTIPLAYER.md` §B wants one shared siege with the lit area shrinking as posts are overrun. **That is
`settle_lux_at` recomputed as wick drops.** The field this design already computes is the siege's
scoreboard, the fog radius, the enemy density and the visible lit ring, all at once. **No new systems —
only scope.** The green never falls (§3.2), so the siege has a floor and the promise holds.

---

## 10. OUT OF SCOPE FOR V1

Explicitly, so nobody builds them by accident:

1. **Interiors. Of any kind.** No building is enterable, no door opens. Every service is an
   **interaction prompt at 2.5 m from the door's AABB face**, and the shop / bench / museum is a HUD
   panel. The Inn's sleep is a fade. This is the PS1-era answer, it is how the budget in §7.5 closes,
   and it keeps every building a closed box that backface culling pays for.
2. **Off-origin settlements, and more than one per shard.**
3. **Player-authored settlement layout.** Only the green's 1 m grid.
4. **Demolition.** Brownout is the failure mode; nothing is ever removed.
5. **Roads between settlements.** Wick Lines are the travel layer; the road mesh stops at the ring.
6. **Reachable vertical architecture.** No second storeys, no stairs. The Tower is silhouette only.
7. **Named ambient villagers.** The five are named; villagers are a crowd with no dialogue and no
   persistence.
8. **A settlement map or minimap.**
9. **Economy simulation.** Villagers do not consume, trade, or produce anything. The Foundry's output is
   a table lookup on grid points.
10. **Farming beyond GDD §5.5's Ashroot beds.**

**v2, with multiplayer:**

- The **shared night hold** on the settlement grid (§9.6) — needs scope, not systems.
- **Travel between settlements** along Wick Lines.
- A **second settlement** at ~1 500 m, from the same scorer with the origin disc excluded. The scorer is
  already position-parametric; the only blocker is that `worldgen`'s danger gradient is origin-anchored
  (§1.1), which becomes a signature change to two pure functions.
- **Civic history / attribution**, if the owner overrules §9.3.
- **Interiors** for the Foundry and the Inn specifically, if the budget ever affords it. They are the
  only two that would earn one.

---

## 11. CONTRADICTIONS WITH EXISTING DOCS, FLAGGED NOT SILENTLY OVERRIDDEN

### 11.1 `BUILD_PLAN.md` W5-2: *"the whole town is ≤ 600 triangles"* — ambiguous, and the ambiguity is 2.2×

Authored and drawn differ by **2.2×** for a closed box (§7.1), and the criterion does not say which. A
Village authors **668** and draws **~406**. Read as authored it fails by 68; read as drawn it passes with
32 % to spare.

**Restate it as drawn, and give it three rungs:**

| Tier | Settlement WORLD geometry, drawn, worst in-town frame |
|---|---|
| Village | **≤ 600** |
| Town | **≤ 900** |
| City | **≤ 1 300** |

(Excluding ground, viewmodel, humanoids, HUD, FX — those have their own lines.) An unstated unit is
exactly the class of thing that costs a wave; the XP cumulative column and the night-hold duration were
both caught the same way.

### 11.2 `ARCHITECTURE.md` §5.3 gives `hubgen.hml` *"modular building meshes **and layout**"* — the layout half must move

**Layout belongs in `src/sim/settle.hml`.** Three hard reasons, not taste:

1. Layout is **world state** and must be in the delta log.
2. It must run on a **headless dedicated server** with no wobbleweed, which `src/art/**` requires.
3. `src/sim/**` **may not import `src/art/**`** (`ci_imports.sh` R1), so a sim module could never ask
   hubgen where a building goes.

`hubgen.hml` keeps the meshes (§8.2). `BUILD_PLAN.md` W5-2's acceptance criteria need re-pointing at
the mesh library, and a new task owns `src/sim/settle.hml`.

### 11.3 `LORE.md` §11.2.13: *"The city … nothing may depend on it being at a particular coordinate"* vs the settlement growing into one

`LORE.md` treats "the city" as a distant, unwritten place. `MULTIPLAYER.md`'s unification table already
says *"Settlement tier | Total integrated civic light drives village → town → city"*, and the owner's
directive is literally *"a seed starts a village and that grows into town then city."*

**Position: the settlement the player lights IS the city.** Argued, not assumed:

- The **owner asked for it in those words**, and `DIRECTION.md` §5 says directives win.
- A distant city **breaks the causal chain `DIRECTION.md` §3 exists to create.** The whole point is that
  the player's lighting raises the city's output; a city 1 500 m away that the player cannot see change
  is the Animal Crossing pillar with the pillar removed.
- `LORE.md` §11.2.13's own constraint is **satisfied**: nothing depends on a particular coordinate,
  because the coordinate is `f(seed)`.
- `LORE.md` §11.2.2 — *"Some of them founded towns you have not found"* — already provides the room.

**Consequence: `LORE.md` §6a's "there is exactly one place that makes those" needs one word changed** —
to "exactly one place *near you*", the one you build. The fiction is unharmed and arguably improved: a
factory still needs light, and now the light is yours. **`LORE.md` §11.1.8 is untouched.**

### 11.4 GDD §4.4's lantern radii saturate the field, and the cap is a consequence not a preference

T4 lanterns at 120 m radius against one anchor per 64 m block overlap ~11-deep. Without `CL_MAX` the
field saturates, the ladder stops meaning anything, and expansion stops costing anything.
**`SET_CL_MAX = 4096`** is a real design constraint the GDD's own radii create. Flagging it because it
looks like an arbitrary clamp and is not.

### 11.5 `worldgen.hml`'s header: *"Levelling the town plot is `hubgen.hml`'s job (Wave 4)"*

With layout moving to sim (§11.2), terracing moves to `settle.hml` and is expressed as a **chunk edit
overlay**, which is the correct home: a levelled green is a terrain *edit*, and edits are already the
only terrain thing that persists. `worldgen.hml`'s comment should be re-pointed. **Its decision not to
flatten anything itself was right and stands.**

### 11.6 `config.hml`'s `g_FOG_FAR_TIER0 = 72.0` vs the settlement at 56 m

Argued at length in §7.3. The proposal is a **new constant `g_FOG_FAR_SETTLEMENT = 56.0`**, a *place*
override, not a change to the tier ladder. A lit lantern's tier-0 disc in the wild keeps 72 m.
`hub_dawn` already ships at 52 m, so the shipping money shot is already on the other side of this line.

### 11.7 `MULTIPLAYER.md`'s *"the CHARACTER travels"* vs world-bound ammunition

§9.4 binds manufactured ammunition to its world. That is a **deliberate exception** to the persistence
split and it is the one lever that both answers the twinking question and gives a home world a reason
to exist. Flagged because it is the first exception to a rule that document calls "the key decision".

### 11.8 GDD §5's *"build prefab structures on a 1 m grid in the town's 40×40 m plot"*

A 40 × 40 m plot cannot hold a city. **Extension, not conflict:** the 1 m grid is kept exactly as
specified, scoped to the green (r ≤ 16 m ≈ a 32 × 32 m plot), and settlement growth uses the 72-plot
lattice out to an 80 m ring. The two are disjoint by construction (§9.2).

### 11.9 GDD §5's Great Lantern (5 purchase tiers) vs this document's 4 settlement tiers — **do not merge them**

They are different ladders. The Great Lantern is a **purchase** made with materials at Grandfather
Wick. The settlement tier is **earned by the field.** This design makes Great Lantern tier a
**prerequisite** for promotion (§3.1), which couples them without collapsing them. Merging them would
delete either the shop sink or the maintenance loop, and both are load-bearing.

### 11.10 ART_BIBLE §8.3's NPC at 220 triangles

Kept for the five named characters, with an LOD ladder added (210 / 90 / 28). **A new, cheaper
ambient-villager class at 48 / 28 / 12 is proposed** (§7.4) because ART_BIBLE's justification —
*"they're static and few"* — stops being true in a city, and because a villager does not have to satisfy
RULE S1's class-identification-at-12-px requirement. This is the largest single saving in the design
and the one most worth arguing with.
