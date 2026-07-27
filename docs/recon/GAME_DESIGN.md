# NIGHTSHADE — Game Design Document (v1)

**Status:** source of truth for implementation. Every number here is a number a programmer
can type into a constants file. Where a number is a guess, it is still a *specific* guess —
change it in one place, not by argument.

**Target:** PS1/N64-look open-world FPS in Hemlock on Wobbleweed. 320×240 internal, ×3/×4
integer upscale. Compiled with `hemlockc`. **≤2500 triangles/frame at 60 fps.**

---

## 0. Engine reality check (constraints this design was written against)

Measured: 530 tris/frame → 283 fps compiled (≈3.53 ms). Cost is dominated by per-triangle CPU
projection, so treat it as linear: **~6.6 µs/triangle**. 16.6 ms/frame ÷ 6.6 µs ≈ **2500 tris**
with zero headroom. Design target is **2200 tris steady, 2500 spike**, leaving ~10% for game logic.

What the engine has today (`/home/nbeerbower/Projects/wobbleweed/src`):

| Have | Implication for design |
|---|---|
| `SDL_RenderGeometry` GPU path, affine UVs | Textured quads are cheap-ish; *wobble is free and on-aesthetic* |
| Painter's sort, **no z-buffer** on GPU path | No large interpenetrating geometry. Everything is a discrete sorted object. Viewmodel + HUD are separate late batches. |
| Near-plane clip + screen guard band | Safe to put the gun 0.25 m from the camera |
| Per-vertex Gouraud, per-face flat light | No dynamic lights. **Lighting is baked per-vertex + a global day/night tint multiplier.** |
| OBJ loader, computed smooth normals | Meshes authored offline, loaded once, instanced |
| Keyboard state + event poll | **Missing: relative mouse.** Must add `SDL_SetRelativeMouseMode` + `SDL_GetRelativeMouseState`. Non-negotiable for an FPS. |
| No audio | Must add SDL audio FFI (queue-audio + a tiny mixer). Also non-negotiable — see §7. |
| No text | HUD numerals = a 6×8 texture-atlas font drawn as screen-space quads (2 tris/glyph) |

Three engine additions are **required** before this design is playable: relative mouse,
audio, screen-space quad batch (HUD/font/billboards). Nothing else is required.

### Triangle budget (steady-state, worst realistic frame)

| Element | Count | Tris ea. | Tris |
|---|---|---|---|
| Sky panorama band | 16 quads | 2 | 32 |
| Terrain — near ring (9 chunks, LOD0 8×8) | 9 | 128 | 1152 → **use 5 chunks** 640 |
| Terrain — mid ring LOD1 (4×4) | 12 | 32 | 384 |
| Terrain — far ring LOD2 (2×2) | 16 | 8 | 128 |
| Enemies visible | 8 | ~48 | 384 |
| Props/foliage (billboard cross-quads) | 90 | 2 | 180 |
| Structures / POI geometry | — | — | 260 |
| Weapon viewmodel | 1 | 64 | 64 |
| Tracers, muzzle, impacts, pickups | ~30 | 2 | 60 |
| HUD (font + bars + reticle) | ~50 quads | 2 | 100 |
| **Total** | | | **2232** |

**Hard rules that fall out of this:**
- Foliage, pickups, particles, distant enemies are **billboards** (2 tris). Never meshes.
- Enemy meshes are ≤72 tris and use **rigid part hierarchies** (no skinning): torso, head,
  2 arms, 2 legs, animated by rotating parts. This is the PS1 way and it is cheap.
- Fog is not an effect, it is a **budget device**. Draw distance 140 m, fog full at 120 m.
  Ashwood biome fogs at 45 m so it can afford dense trees.
- Never more than **14 live enemies**, **8 on screen**.

---

## 1. The fantasy, and the core loop

> **You are the last lamplighter of a world eaten by night: you push the dark back one lantern
> at a time, with a gun in your hands, and you carry what you find home to a small warm town
> that grows because you came back.**

That sentence is the whole game. Combat is *how* you push. The town is *why*. The map getting
brighter is the *record* of both.

### The three influences, honestly assigned

- **Call of Duty owns the 30 seconds.** Gunfeel, TTK, hitmarkers, sprint-to-fire, streak
  dopamine, HUD legibility, audio punch. Nothing about the shooting is "indie-soft".
- **Minecraft owns the 30 minutes.** Chunked procedural world, "what's over that hill",
  gather → craft → place, a torch (lantern) that permanently changes the world state,
  player-placed structures.
- **Animal Crossing owns the 30 hours.** A named town with named people, a day rhythm you
  live inside, seasons and weather, an Almanac to complete, and the emotional job of being
  the warm place you return to. It is the counterweight; without it the game is a corridor.

### Minute-to-minute (the wild, day)

```
scan horizon → pick a heading (a POI silhouette, a shade-plume, a lantern icon)
  → traverse (sprint/slide/mantle; terrain is a movement toy, not a hallway)
  → arrive: gather 2-4 nodes, 3-6 skirmish enemies, 1 chest/cache
  → decide: push one ring further out, or turn for home before dusk
```
Loop length: **60–120 s per POI**. There is always a next silhouette in view.

### Minute-to-minute (the wild, night — the CoD engine)

```
dusk horn (2 min warning) → you are either at a Lantern Post or you are prey
  → light the lantern (2.5 s channel) → THE HOLD: 3 waves, ~3:20 total
  → wave clear = ember rain + XP toast + the lantern ignites and the fog recolors
  → sprint the lit corridor home, or bed down at the lantern
```

### The day cycle (the metronome)

A full day is **16 real minutes**:

| Phase | Length | What it is |
|---|---|---|
| Dawn | 2:00 | Safe. Shade enemies dissolve. Gather bonus ×1.5. |
| Day | 7:00 | Explore, gather, build, travel far. Only Motes and stragglers. |
| Dusk | 2:00 | Horn sounds. Shade tier +1 everywhere. Enemies begin spawning. Panic-traverse. |
| Night | 5:00 | Full combat. Lantern holds happen here. Shade tier +2. |

Sleeping in town or at a Tier-2+ lantern skips to Dawn. **Sleeping is a choice with a cost:**
you forfeit the night's ember. Most players will not sleep. That is the point — night is where
the game is best and skipping it should feel like leaving money on the table.

### Session-to-session

```
Session start (in town) → check board (2 contracts) → spend last night's ember at Mabel
  → one town action (build/plant/donate) → walk out at Dawn
  → 2-3 day-cycles of push-and-return, each ending with a lantern hold
  → session end: town is one visible notch better, map is one ring brighter
```

**The retention hook is the map.** Lit lanterns are permanent, visible on the world map as
warm dots in a cold field, and they *connect* — two lanterns within 90 m of each other form a
lit **Wick Line** you can fast-travel along and that is permanently safe. The player is
literally drawing a growing constellation of their own competence across a dark map. That is
the Minecraft "my base got bigger" feeling and the Animal Crossing "my town got nicer" feeling
fused into one readable object.

---

## 2. The 30-second combat loop

### 2.1 Player vitals

| Stat | Value |
|---|---|
| Health | 100 |
| Regen delay after last damage | 4.0 s |
| Regen rate | 25 HP/s (0→100 in 4 s) |
| Damage-direction indicator | yes, 4-segment, 1.2 s fade |
| Low-health threshold | ≤35 HP: red vignette, heartbeat loop, desaturate to 40% |
| Death | drop 40% carried ember; respawn at nearest lit lantern after 4 s |
| Wicks (revive charges) | start 1, max 3. Consuming one revives in place at 50 HP with 1.5 s i-frames. |

TTK **against** the player is deliberately slow-ish (2–4 hits) because the camera is 320×240
and the player deserves reaction time. TTK **by** the player is CoD-fast. Asymmetry is fine.

### 2.2 Enemies

All costs below are *spawn budget* costs used by the director (§2.6).

| Enemy | HP | Tris | Speed | Attack | Dmg | Range | Tell | Ember | XP | Cost |
|---|---|---|---|---|---|---|---|---|---|---|
| **Wisp** | 15 | 24 | 6.4 m/s erratic | contact | 6 | 0 | audible chime 0.5 s | 1 | 6 | 2 |
| **Mote** | 30 | 32 | 2.2 m/s drift | contact pop | 12 | 0 | slow, always visible | 2 | 12 | 3 |
| **Husk** | 90 | 56 | 5.2 m/s charge, 3.0 m/s walk | swipe | 18 | 1.8 m | 0.45 s wind-up, arm raise | 4 | 25 | 6 |
| **Spitter** | 70 | 48 | 2.6 m/s reposition | lobbed bolt (4.5 m/s arc) | 22 | 30 m | 1.4 s glow charge | 5 | 30 | 8 |
| **Warden** | 220 (+80 front plate, 75% DR while intact) | 72 | 3.4 m/s advance | shoulder ram | 30 | 2.2 m | plate glows before ram | 12 | 90 | 20 |
| **Bulwark** (miniboss) | 900 | 140 | 2.8 m/s | slam AoE 5 m / spawn 4 Wisps | 40 | 5 m | 1.1 s crouch before slam | 60 | 400 | 90 |

**Design intent per enemy:**
- **Wisp** — free dopamine. Dies to one bullet of anything. Exists so the hitmarker fires often.
- **Mote** — spatial pressure. Slow, so it teaches you to check your back without punishing.
- **Husk** — the bread and butter. Its 90 HP defines the whole weapon table (§2.4).
- **Spitter** — makes you move. Forces you out of the ADS-and-hold stance.
- **Warden** — the *flank prompt*. Front plate means "stop shooting the wall, go around."
  It is the only enemy that makes movement tech mandatory.
- **Bulwark** — the wave-3 punctuation. One per Tier-3+ lantern hold.

**AI:** steering only, no navmesh. Seek player position, sample terrain height, avoid other
agents with a 1.2 m separation force, stop at attack range. Husks path around obstacles by
"whisker" raycasts at ±35°. This is honest and adequate at this scale — do not build A*.

### 2.3 Movement (player)

| Action | Value |
|---|---|
| Walk | 4.4 m/s |
| Sprint | 7.0 m/s (forward cone ±40° only) |
| Crouch walk | 2.3 m/s |
| ADS walk | 2.9 m/s |
| Ground accel | 60 m/s² |
| Ground friction | 8.0 /s |
| Air control | 0.35 × ground accel |
| Gravity | 22.0 m/s² |
| Jump impulse | 6.6 m/s (apex 0.99 m, air time 0.60 s) |
| Stand height / eye | 1.75 m / 1.62 m |
| Crouch height / eye | 0.95 m / 0.82 m |
| Crouch transition | 0.15 s |
| Capsule radius | 0.40 m |
| Step-up | 0.35 m auto |
| **Slide** | from ≥6.0 m/s: burst to 9.2 m/s, decays to 3.0 m/s over 0.75 s, eye drops to 0.70 m, cooldown 0.90 s |
| **Slide-jump** | cancel slide into a jump at any time, keeps 85% of current horizontal speed — **this is the movement tech, protect it** |
| **Mantle** | ledges 0.6–1.4 m, 0.35 s, locks aim, no fall damage on landing |
| Fall damage | none below 6 m; then 8 HP per m over 6 m |
| Sprint→fire delay | per weapon, 0.18–0.34 s (see table) |
| FOV | 70° hip, 58° ADS, 78° during sprint (+8 kick, 0.15 s lerp) |
| Mouse sensitivity | 0.0022 rad/count at sens 1.0; ADS multiplier 0.65 |
| Look pitch clamp | ±85° |

### 2.4 Weapons — the starting arsenal

Loadout: **primary + secondary + Kestrel (always)**. The Kestrel occupies no slot; it is your
lamplighter's sidearm and you never lose it. That is a deliberate anti-frustration valve.

#### Core stats

| Weapon | Role | Dmg near | Dmg far | HS mult | RPM | Mag | Reserve | Reload / empty | Pellets |
|---|---|---|---|---|---|---|---|---|---|
| **Sparrow** AR | all-round | 26 | 18 | 1.50 | 690 | 30 | 210 | 1.85 / 2.40 s | 1 |
| **Tinker** SMG | close aggression | 19 | 11 | 1.40 | 900 | 32 | 256 | 1.55 / 2.05 s | 1 |
| **Bellows** pump shotgun | doorway king | 13/pellet | 5/pellet | 1.25 | 75 (0.80 s pump) | 6 | 42 | 0.55 s/shell (interruptible) | 9 |
| **Longshadow** marksman | range, Wardens | 78 | 68 | 2.10 | 75 | 8 | 56 | 2.30 / 2.85 s | 1 |
| **Kestrel** revolver | sidearm, always | 45 | 30 | 1.50 | 200 | 6 | 48 | 2.10 s (full cylinder) | 1 |
| **Emberlance** special | crowd / ignite | 60 impact + 12/s burn 5 s | same | 1.00 | 40 | 3 | 12 | 2.60 s | 1 (3.5 m AoE) |

#### Range falloff

`dmg(r) = lerp(dmg_near, dmg_far, clamp((r - r0) / (r1 - r0), 0, 1))`

| Weapon | r0 (m) | r1 (m) | Max useful (m) |
|---|---|---|---|
| Sparrow | 22 | 46 | 70 |
| Tinker | 9 | 22 | 35 |
| Bellows | 6 | 14 | 18 |
| Longshadow | 55 | 110 | 140 (draw distance) |
| Kestrel | 14 | 30 | 45 |
| Emberlance | — | — | 40 (arc, 6.0 m/s projectile) |

#### Handling

| Weapon | ADS time | Sprint→fire | Swap in/out | Hipfire spread base → cap | Bloom/shot | ADS spread |
|---|---|---|---|---|---|---|
| Sparrow | 0.24 s | 0.22 s | 0.55 / 0.40 s | 3.2° → 6.0° | 0.35° | 0.25° |
| Tinker | 0.19 s | 0.18 s | 0.45 / 0.32 s | 4.0° → 7.5° | 0.30° | 0.55° |
| Bellows | 0.30 s | 0.28 s | 0.62 / 0.48 s | 6.5° cone (fixed) | — | 4.5° cone |
| Longshadow | 0.38 s | 0.34 s | 0.75 / 0.55 s | 9.0° (unusable, intentional) | 1.20° | 0.05° |
| Kestrel | 0.22 s | 0.20 s | 0.35 / 0.25 s | 3.6° → 6.5° | 0.55° | 0.20° |
| Emberlance | 0.34 s | 0.30 s | 0.70 / 0.50 s | 2.5° | — | 1.0° |

#### Recoil patterns

Model: each shot adds `(kick_v, kick_h)` degrees to an *aim offset*. Offset decays toward zero
at `recover °/s` starting `0.16 s` after the last shot. **The pattern is deterministic** —
learnable, CoD-style — with a small random jitter added only to `kick_h`.

**Sparrow** (recover 7.0 °/s, jitter ±0.06°):
```
shot 1-3   : (0.62,  0.00) (0.60, -0.06) (0.58, +0.10)
shot 4-8   : (0.42, +0.22)   // drifts right
shot 9-15  : (0.30, -0.18)   // hooks left
shot 16-30 : (0.26, ±0.20 random)
```
**Tinker** (recover 9.0 °/s, jitter ±0.10°):
```
shot 1-5   : (0.38, +0.05)
shot 6-14  : (0.34, +0.26)   // hard right climb
shot 15-32 : (0.30, -0.30)   // whips left
```
**Bellows**: single (2.4, ±0.30), recover 5.0 °/s. Big visual kick, fully recentered by the pump.
**Longshadow**: single (2.9, ±0.15), recover 4.0 °/s, forced 0.35 s re-settle before ADS is true again.
**Kestrel**: single (1.35, ±0.25), recover 8.0 °/s.
**Emberlance**: single (1.8, 0.00), recover 6.0 °/s.

Visual kick is **separate** from aim kick: viewmodel translates back `0.02 m × mult`, pitches
up `1.6° × mult`, decays at 14/s. Camera shake on fire is `0.35° × mult`, 0.08 s. Never let
visual kick move the actual bullet.

#### TTK table (the numbers that matter) — shots to kill / time in ms

| Weapon | Wisp 15 | Mote 30 | Husk 90 (body) | Husk (head) | Spitter 70 | Warden 220+plate |
|---|---|---|---|---|---|---|
| Sparrow (near) | 1 / 0 | 2 / 87 | 4 / 261 | 3 / 174 | 3 / 174 | 9 body / 696 |
| Sparrow (far) | 1 / 0 | 2 / 87 | 5 / 348 | 4 / 261 | 4 / 261 | 13 / 1043 |
| Tinker (near) | 1 / 0 | 2 / 67 | 5 / 267 | 4 / 200 | 4 / 200 | 12 / 733 |
| Tinker (far) | 2 / 67 | 3 / 133 | 9 / 533 | 6 / 333 | 7 / 400 | 20 / 1267 |
| Bellows ≤6 m | 1 | 1 | **1 / 0** | 1 | 1 | 3 / 1600 |
| Bellows @12 m | 1 | 1 | 2 / 800 | 2 | 2 / 800 | 5 / 3200 |
| Longshadow | 1 | 1 | 2 / 800 | **1 / 0** | 1 / 0 | 3 body / 1600, 2 head |
| Kestrel (near) | 1 | 1 | 2 / 300 | 2 / 300 | 2 / 300 | 6 / 1500 |
| Emberlance | 1 | 1 | 1 + burn / ~1000 | — | 1 + burn | 3 / 4500 |

Read this table as the design: **Bellows one-shots a Husk inside 6 m** (the reason to play
Ashwood), **Longshadow one-shots a Husk in the head at any range** (the reason to play Chalk
Downs), **Sparrow is never wrong but never best**, **Tinker is a knife that dies past 22 m**.
Warden always wants a flank or a Longshadow.

**Ammo economy:** ammo does not drop from enemies. It drops from **caches** and is **crafted**
in town. Running dry mid-night and falling back to the Kestrel is a designed dramatic beat, not
a failure. Kestrel reserve refills free at any lit lantern.

### 2.5 Hit feedback contract (non-negotiable)

Every bullet that connects produces, within the same frame: hitmarker, enemy flash, damage
number, impact billboard, and a mixed audio blip. See §7. If any of these five is missing the
gun is broken, regardless of how correct the math is.

### 2.6 The wave director (night holds)

```
budget(tier, wave) = 60 + 45*tier + 18*wave        // wave in 0..2
alive_cap        = 14
onscreen_cap     = 8     // director defers spawns that would exceed this
spawn_ring       = 24-40 m from lantern, biased behind the player's view cone
spawn_cadence    = 1.2 s while under caps
wave_gap         = 8 s (the breather: ember rains, ammo cache drops, hitmarker silence)
```
Composition rolls from a tier table, always spending the full budget:

| Tier | Roll pool |
|---|---|
| 1 | Wisp 40%, Mote 35%, Husk 25% |
| 2 | Wisp 25%, Mote 20%, Husk 40%, Spitter 15% |
| 3 | Wisp 15%, Husk 40%, Spitter 25%, Warden 20% (+1 Bulwark on wave 3) |
| 4 | Husk 35%, Spitter 25%, Warden 35%, Wisp 5% (+1 Bulwark on wave 2 and 3) |
| 5 | Husk 25%, Spitter 25%, Warden 40%, Bulwark 10% |

Hold duration ≈ 3:20 (3 waves + gaps). That is exactly one good CoD match's worth of tension.

---

## 3. Progression

### 3.1 XP curve

```
xp_to_next(L) = 500 + 250*L + 25*L*L     // L = current level
```

| Level | XP to next | Cumulative | Typical arrival |
|---|---|---|---|
| 1 | 775 | 0 | 0:00 |
| 5 | 2,375 | 6,300 | ~0:45 |
| 10 | 5,500 | 24,050 | ~2:30 |
| 15 | 9,875 | 61,300 | ~6:00 |
| 20 | 15,500 | 124,050 | ~12:00 |
| 25 | 22,375 | 218,800 | ~22:00 |
| 30 | 30,500 | 352,050 | ~35:00 (soft cap) |

Past 30: **Wickmarks** — each 40,000 XP grants +1 Wickmark, a prestige-flavoured cosmetic
lantern flame colour + 1 permanent stat point. Infinite, cheap to implement, satisfies the
Minecraft-endless itch.

**XP sources:**

| Event | XP |
|---|---|
| Wisp / Mote / Husk / Spitter / Warden / Bulwark | 6 / 12 / 25 / 30 / 90 / 400 |
| Headshot bonus | +25% of base |
| Point-blank Bellows kill | +15% |
| Kill while sliding/airborne | +20% ("Lamplighter's Grace") |
| New chunk discovered | 40 |
| POI cleared | 250 |
| Lantern lit (first time) | 350 |
| Night wave survived | 150 × tier |
| Almanac entry filled | 120 |
| Contract completed | 300–900 |
| Donating a relic to the museum | 250 |

Hour 1 should land the player at **level 6–7**. This is calibrated: kills alone are slow;
lanterns and discovery carry the early curve, which teaches "go outward" not "farm here".

### 3.2 Unlock ladder

| Lv | Unlock |
|---|---|
| 2 | **Tinker** SMG · Slide |
| 3 | Lantern Tier 2 (larger safe radius, sleep-anywhere) |
| 4 | Attachment slot 1 · Charm slot 1 |
| 5 | **Bellows** shotgun · Ember Streak: **Flare** |
| 6 | Crafting: Ammo bench |
| 7 | Mantle-and-vault (chain mantle into slide) |
| 8 | **Longshadow** marksman |
| 9 | Attachment slot 2 · Ember Streak: **Lantern Drone** |
| 11 | Charm slot 2 · Wick capacity 2 |
| 12 | **Emberlance** |
| 13 | Wick Line fast travel |
| 14 | Lantern Tier 3 (spawns an ammo cache each wave gap) |
| 16 | Ember Streak: **Dawnfall** |
| 18 | Attachment slot 3 · Charm slot 3 |
| 20 | Building: player structures unlocked in the wild (not just town) |
| 22 | Wick capacity 3 |
| 25 | Lantern Tier 4 (permanently clears shade in a 120 m radius) |
| 28 | Second primary slot (drop the sidearm rule) |
| 30 | Deepshade key — the endgame biome opens |

**Ember Streaks** (killstreaks, reset on death, do *not* carry between lives):

| Kills | Streak | Effect |
|---|---|---|
| 4 | **Flare** | 12 s: all enemies within 60 m outlined + a 2× ember multiplier on kills |
| 7 | **Lantern Drone** | 20 s: hovering turret, 14 dmg / 0.35 s, 24 m range, ~40 tris |
| 11 | **Dawnfall** | 3 s scripted sunbeam: 250 dmg to everything within 30 m, screen whites out, the *only* moment in the game with no fog |

Dawnfall at 11 kills is the single biggest dopamine spike in the design. Guard its rarity.

### 3.3 Loot rarity

| Tier | Colour | Affixes | Drop weight (shade tier 1 / 3 / 5) |
|---|---|---|---|
| Common | Ash grey `#9a9a8e` | 0 | 62 / 30 / 8 |
| Uncommon | Moss `#6fa05a` | 1 | 28 / 34 / 20 |
| Rare | Dusk blue `#4f7bc4` | 2 | 8 / 24 / 30 |
| Epic | Nightshade violet `#8b5bd6` | 3 | 2 / 10 / 28 |
| Relic | Ember amber `#f0a23c` | 4 + unique | 0 / 2 / 14 |

**Affix pool** (roll without replacement, values roll in a band):

| Affix | Band |
|---|---|
| +% damage | 4–12% |
| +% RPM | 3–9% |
| −% reload time | 6–18% |
| +mag size | +15–40% |
| −% recoil | 8–22% |
| −% ADS time | 8–20% |
| +% ember from kills | 10–30% |
| Ignite on hit | 6/s for 3 s, 20% chance |
| +1 pellet (Bellows only) | +1 |
| Overpenetrate (hits 2 enemies at 70%) | — |

**Relic uniques** (one per weapon family, hand-authored, hour-20 chase):
- *Wick* (Sparrow): every 10th round is a tracer that ignites.
- *Ninepence* (Bellows): pellets that miss ricochet once toward the nearest enemy.
- *The Long Sunday* (Longshadow): headshots refund the round and add 1.5 s to your streak timer.
- *Sixpenny* (Kestrel): the 6th chamber does 3× damage.
- *Chatterbox* (Tinker): +2% RPM per consecutive hit, resets on miss, caps +40%.
- *Vesper* (Emberlance): the burn spreads between enemies within 4 m.

### 3.4 What the player is chasing

| Time | Chasing |
|---|---|
| **Hour 1** | "Can I survive a night?" → first lantern lit, first Husk killed with the Bellows, Mabel's first upgrade, Odo learning your name |
| **Hour 5** | Push to shade tier 3. First Bulwark. First Rare with a good affix pair. Town has 4 buildings. The map has 9 lanterns and 2 Wick Lines. |
| **Hour 20** | Relic hunt in tier 5. Almanac at 70%. Museum wing 2 open. A personal record: *deepest lantern* (distance from town), shown on the town square obelisk. Building the town you actually want. |

The three chases are structurally different — **survival**, then **power**, then **completion +
expression**. Do not let one crowd the others out.

---

## 4. The world

### 4.1 Structure

- Chunk = **32 m × 32 m**, heightfield on a **4 m grid** (8×8 quads = 128 tris at LOD0).
- LOD by ring: 0–48 m LOD0 (128 tris), 48–96 m LOD1 (32), 96–140 m LOD2 (8). Skirts hide seams.
- Generation: 3-octave value noise for height, 2 low-frequency noise fields (temperature,
  moisture) select biome, deterministic from `(world_seed, chunk_x, chunk_z)`. Chunks generate
  in <2 ms and cache; POIs are placed by a per-chunk hash roll so they are stable.
- World is **infinite** in the Minecraft sense. Town is at origin.

### 4.2 Shade tier (the danger gradient)

```
base_tier(d) = clamp(floor(d / 200), 0, 5)        // d = metres from town
tier = clamp(base_tier + noise_tier(chunk) + phase_bonus, 0, 5)
  noise_tier  ∈ {-1, 0, 0, +1}   // hashed per chunk — creates pockets of "too deep, too soon"
  phase_bonus = 0 (day) / +1 (dusk) / +2 (night)
lit lanterns force tier 0 within their radius (T1 40 m, T2 60 m, T3 85 m, T4 120 m)
```

Tier is **visible without a UI**: sky tint, fog colour, fog distance, and the density of black
"shade motes" drifting in the air. A player should be able to look at the horizon and say
"that's a tier 4 out there" without opening a map.

| Tier | Fog colour | Fog dist | Feel |
|---|---|---|---|
| 0 | warm `#e0c89a` | 140 m | safe, home |
| 1 | pale `#b6bcae` | 120 m | frontier |
| 2 | grey-green `#7d8a7a` | 95 m | contested |
| 3 | slate `#4e5866` | 75 m | hostile |
| 4 | ink `#2b2f42` | 55 m | expedition |
| 5 | near-black `#14121c` | 38 m | Deepshade |

### 4.3 Biomes

| Biome | Look | Terrain | Sightline | Signature enemy | Signature weapon | Resource |
|---|---|---|---|---|---|---|
| **Hollowfield** | warm gold grass, scattered stones | gentle, rolling | 100 m | Mote, Husk | Sparrow | Ash, Sap |
| **Ashwood** | dead white birch, thick grey fog | flat, dense billboard trees | 45 m | Husk packs | **Bellows** | Ironwood |
| **Chalk Downs** | pale open hills, standing stones | big smooth ridges | 140 m | Spitter, Warden | **Longshadow** | Glass, Chalk |
| **The Fen** | black water, reeds, mist | flat, water slows you to 2.8 m/s | 70 m | Spitter, Wisp swarms | Tinker | Sap, Bogiron |
| **Ironpine** | steep dark conifer slopes, cliffs | vertical, mantle-heavy | 80 m | Warden, Husk | Tinker/Sparrow | Coldiron |
| **Deepshade** | permanent night, violet geometry, no sky | alien plateaus | 38 m | everything, +1 tier | Emberlance | **Shadeglass** |

Biome is also a **triangle budget policy**: Ashwood affords 140 billboards because it fogs at
45 m; Chalk Downs affords almost no props because it sees 140 m.

### 4.4 Points of interest

| POI | Frequency | Content | Tris |
|---|---|---|---|
| **Lantern Post** | 1 per ~4 chunks, guaranteed 1 within 120 m of anywhere | unlit lantern + 3-wave hold + permanent light | 40 |
| **Ruin** | 1 per 6 chunks | 2–4 walls, 1 chest, 3–6 enemies | 90 |
| **Caravan wreck** | 1 per 10 chunks | ammo cache + a note (worldbuilding) + Motes | 60 |
| **Shrine** | 1 per 14 chunks | 15-min buff, choose 1 of 2 | 34 |
| **Burrow** | 1 per 20 chunks | one-room dungeon: 12 enemies, guaranteed Rare+ | 180 |
| **Standing Stones** | 1 per 24 chunks | fast-travel node once linked to a Wick Line | 48 |
| **Grove** | 1 per 8 chunks | **cozy**: critters to catch for the Almanac, no enemies, ever | 50 |

**Groves are load-bearing.** They are the Animal Crossing beat in the wild: a small bright
clearing with fireflies and a bench, guaranteed safe even at night. Players need somewhere to
exhale. One grove per 8 chunks means you can usually see the next exhale from the last fight.

### 4.5 Resources & crafting

Five materials, five tiers: **Ash** (t1) → **Sap** (t1) → **Ironwood** (t2) → **Glass/Coldiron**
(t3) → **Shadeglass** (t5). Currency is **Ember** (drops from every kill, decays 0 — it is safe
to carry, but you drop 40% on death).

Crafting is deliberately shallow: **ammo**, **lantern kits** (place your own lantern anywhere:
20 Ironwood + 10 Glass + 200 Ember), **structure blocks**, **charms**. There is no crafting
grid and no recipe discovery. Minecraft's *placement* is the fun part, not its inventory.

---

## 5. Ember Hollow (the hub)

A small walled town at world origin. ~600 tris total, always rendered at LOD0 because it is
the only place with no combat and therefore has budget to spare. Warm lighting, wood smoke
billboards, lanterns strung between roofs, a well in the middle, a big obelisk with your
records carved into it.

### What you do there

1. **Spend** — Mabel's bench: attachments, rerolls, weapon upgrade tiers.
2. **Bank** — ember and materials deposited in the well are safe from the death penalty.
3. **Upgrade the Great Lantern** — town tech tree (5 tiers). Each tier visibly grows the town's
   light radius and unlocks a building slot.
4. **Build** — place prefab structures on a 1 m grid in the town's 40×40 m plot: houses,
   fences, gardens, lamps, benches, a bridge. Purely expressive + a few small buffs.
5. **Plant & harvest** — Ashroot beds. Plant at dusk, harvest 2 days later. The Animal
   Crossing tick that makes you want to log in tomorrow.
6. **Donate** — the Almanac museum: 60 critters, 24 relics, 18 enemy entries. Completion is
   the hour-20 chase and each wing that opens changes the town skyline.
7. **Talk** — every NPC has one new line per in-game day. Cheap, enormously effective.
8. **Sleep** — skip to dawn, forfeit the night.
9. **Take contracts** — 2 per day from the board.

### The five people

- **Mabel Thorn** — gunsmith, ex-lamplighter, two fingers short on the left hand.
  *"Sweetheart, I've buried better guns than this. Give it here and I'll make it worse in a way you'll like."*
- **Odo** — the innkeeper, round and anxious and vaguely moth-shaped, keeps soup warm past
  midnight for someone who might not come back.
  *"I kept a bowl. I always keep a bowl. It's not — I'm not waiting up, it's just that soup keeps."*
- **Constance "Connie" Vane** — cartographer, runs the bounty board, is *thrilled* by danger she
  has personally never once attended.
  *"Tier four! Oh, that's marvellous. If my knee were better I'd be right behind you. Two hundred metres behind you."*
- **Pip** — a kid, collects your Almanac finds, trades charms, is a confident liar.
  *"I've seen a Bulwark. Up close. It looked at me and I said nothing, because I am brave."*
- **Grandfather Wick** — the old lantern-keeper, mostly asleep, upgrades the Great Lantern,
  speaks in aphorisms he refuses to explain.
  *"A lamp doesn't argue with the dark. It just declines to be part of it. Mm. Off you go."*

### How hub relates to wild

- The town is a **tier-0 island** and the only guaranteed one at world start.
- Every lantern you light is a *little Ember Hollow*: it is a save point, an ammo top-up, a
  respawn, a sleep spot (T2+), and a fast-travel node (T1 lantern once linked). The town is
  literally the first lantern, upgraded. **This is the whole economy of the game in one object.**
- Town growth is gated on *wild* progress (materials, relics, ember), and wild reach is gated
  on *town* progress (lantern kits, ammo, upgrades). Neither side can be skipped.

---

## 6. Player abilities — consolidated numbers

Already given in §2.3; restated here as the implementation checklist with acceptance criteria.

| Ability | Numbers | Acceptance criterion |
|---|---|---|
| **Sprint** | 7.0 m/s, forward cone ±40°, FOV +8° over 0.15 s, sprint→fire 0.18–0.34 s | Releasing sprint and firing must feel *instant* on the Tinker (0.18 s) and *heavy* on the Longshadow (0.34 s) |
| **Slide** | trigger ≥6.0 m/s, burst 9.2 m/s → 3.0 m/s over 0.75 s, eye 0.70 m, cd 0.90 s | A slide must clear a 4 m gap the player cannot walk across |
| **Slide-jump** | cancel anytime, keeps 85% horizontal | Chaining slide-jump downhill should reach ~11 m/s. Do not "fix" this. |
| **Mantle** | 0.6–1.4 m ledges, 0.35 s, aim locked | Every waist-high wall in the game must be mantleable, no exceptions, or players stop trying |
| **Crouch** | 0.95 m, 2.3 m/s, 0.15 s transition, −40% hip spread | Crouching under a Warden's ram must work |
| **Jump** | 6.6 m/s impulse, g = 22, apex 0.99 m, air 0.60 s | Reaches a 0.95 m ledge without mantling |
| **Melee** | 0.45 s, 3.0 m lunge, 55 dmg, 1.5× vs Wisp/Mote | Kills a Wisp reliably; never kills a Husk |
| **Lantern channel** | 2.5 s hold, cancelled by damage | The moment before the wave — the game's best silence |

---

## 7. The juice list (priority order)

Implement **top to bottom**. If you run out of time, stop — the list is ordered by how much
game-feel each item buys per hour of work. Items 1–12 are the difference between "a tech demo"
and "a game".

| # | Feedback | Spec |
|---|---|---|
| 1 | **Hitmarker** | 4-tick white cross, 12 px, 0.09 s, scales 1.0→1.35→1.0. Red-tinted + 1.6× on kill. 4 tris. |
| 2 | **Hit sound** | 40 ms click, pitch +2 semitones per consecutive hit up to +8, resets after 0.6 s. Distinct 2-note chime on kill. |
| 3 | **Enemy hit flash** | Vertex colour → white for 0.06 s. Free — it's a colour multiply on an existing batch. |
| 4 | **Muzzle flash** | 2-tri billboard, 0.05 s, random 90° roll per shot, scale by weapon (Bellows 1.8×). Screen brightens 6% for 1 frame. |
| 5 | **Weapon kick** | Viewmodel −0.02 m Z, +1.6° pitch, decay 14/s. Camera shake 0.35°, 0.08 s. |
| 6 | **Tracer** | 2-tri quad from muzzle to impact, 0.045 s, drawn 1 in 3 shots (1 in 1 for Longshadow). |
| 7 | **Impact** | 2-tri spark billboard + material-tinted 6-particle burst (each 2 tris, 0.25 s life, gravity 12 m/s²). |
| 8 | **Damage numbers** | Rising 3-digit numerals, 0.5 s, +0.9 m/s up + 0.3 m/s outward, white / amber (headshot) / grey (falloff). Max 8 on screen. |
| 9 | **Kill dissolve** | Enemy scales Y ×0.15 and alpha→0 over 0.22 s while emitting 8 ember motes that home to the player over 0.6 s. **Kills must produce a thing that flies at your face.** |
| 10 | **Ember pickup** | Ping per mote, pitch rises through the pickup chain (a 1-2-3-4-5 arpeggio for a 5-mote pickup). |
| 11 | **Reload** | 3-stage animated viewmodel (drop / insert / seat), magazine billboard falls with gravity + a floor clack. Ammo counter goes red at ≤25% and pulses. |
| 12 | **Low ammo / dry click** | Distinct dry-fire click, reticle turns red, 0.2 s. |
| 13 | **Damage taken** | 4-segment directional indicator, red vignette scaled by missing HP, 0.25° camera punch away from the hit. |
| 14 | **Level up** | Screen edge blooms warm gold 0.6 s, ascending 4-note motif, big centred `LEVEL 12` for 1.4 s, unlock card slides in from the right for 2.5 s. |
| 15 | **Streak earned** | Screen-wide amber wash 0.2 s, distinct horn per streak, streak icon docks in the HUD corner with a bounce. |
| 16 | **Wave clear** | Music stops. 0.4 s of *actual silence*. Then ember rain (30 motes over 1.5 s) + the fog visibly warms one step. |
| 17 | **Lantern lit** | The single biggest moment: 1.2 s of light expanding outward as a scaling billboard ring, fog tier drops live, a low bell, the world map icon lights, `+350 XP`. |
| 18 | **Footsteps** | 0.42 s interval walking / 0.28 s sprinting, 4 samples per surface, 6% pitch jitter. |
| 19 | **Dusk horn** | Two long notes at T-2:00. Every player must learn to feel their stomach drop at this sound. |
| 20 | **Weather** | Rain = 200 screen-space 2-tri streaks (fixed cost) + a 3 dB duck on ambience. Snow in winter. Fog banks roll. |
| 21 | **Idle charm** | Weapon inspect on idle >8 s, NPC head-turn as you pass, critters that scatter from your footsteps. |

**Audio mix rule:** the gun is the loudest thing in the game, always. Music ducks −8 dB on
fire, recovers over 1.2 s. Night music is sparse and percussive; day music is a warm 3-instrument
loop; town music is the only melody in the game and it should be the thing players hum.

---

## 8. The first 60 seconds

| t | Beat |
|---|---|
| 0:00 | Black. A bell. Text: *"The lamps went out on a Tuesday."* Fade in — you are lying on your back looking at a sky at dusk, tier-1 fog. |
| 0:03 | Camera stands up on its own (0.8 s). You have control. No tutorial text. A **Kestrel** is in your hands and the ammo counter reads `6 / 12`. |
| 0:06 | 40 m ahead, downhill, an **unlit lantern** on a post is the only vertical thing on the horizon, silhouetted. It is the brightest object on screen. You will walk toward it. Everyone does. |
| 0:10 | You crest the slope. Three **Wisps** drift up. They chime. They die to one shot each. First hitmarker, first kill chime, first ember motes flying into your face. `+18 XP`. |
| 0:18 | A **Mote** rises from behind a rock. Two shots. Ammo now `1 / 12`. You are learning the reload prompt because you have to. |
| 0:24 | You reach the lantern post. Prompt: `HOLD [E] — LIGHT THE LANTERN`. Below it, small: *"It's going to get their attention."* |
| 0:27 | You hold. 2.5 s channel. The music stops. |
| 0:30 | **Light.** The expanding ring, the bell, the fog warms one step, `+350 XP`, `LEVEL 2`, and an unlock card: **TINKER SMG — at the bench**. The gun is not given to you. You must go home for it. |
| 0:33 | Dusk horn, two notes. The fog goes grey-green. Four **Husks** come up the hill, silhouetted against the last light. This is the first time the game is frightening. |
| 0:36–0:55 | Wave 1, tier 1, budget 60: ~4 Husks and 6 Wisps. You have a revolver and 12 rounds. **You will run out.** You will melee something. You will win with 30 HP. |
| 0:56 | Silence. 0.4 s. Ember rain. `WAVE 1 CLEARED`. |
| 0:58 | A path of small lit lanterns fades in, leading downhill and to the left, into fog. |
| 1:00 | Through the fog: warm windows, chimney smoke, and a very small person on a bridge waving both arms at you. Odo. *"You're— oh, you're the one from the ridge. There's soup."* |

That is the whole game in 60 seconds: shoot, light, be frightened, be welcomed. Nothing after
this needs to be explained.

---

## 9. Explicitly OUT of scope for v1

Cut ruthlessly. These are not "later maybe" — they are **not in v1**, and no v1 code should be
shaped around them except where noted.

**Out — game features**
1. **Multiplayer.** gn.hml integration is v2. *But:* keep player state in one struct, keep
   simulation deterministic per-tick, and route all input through an input-frame struct.
   That's the only accommodation.
2. Vehicles, mounts, horses.
3. Swimming / underwater. Water is a slowing surface with a hard floor, nothing more.
4. Ragdoll physics. Enemies dissolve (§7.9). This is *better* for the aesthetic and free.
5. Skeletal animation / skinning. Rigid part hierarchies only.
6. Destructible terrain / block-breaking. You **place** structures on a grid; you do not dig.
   (This is the single biggest Minecraft feature we are cutting, and it's correct: digging
   demands a voxel renderer we cannot afford at 2500 tris.)
7. Inventory tetris, weight limits, encumbrance. Flat stacks, generous caps.
8. Base defense / raids on the town. The town is always safe. Forever. That promise is why
   the town works emotionally.
9. Dialogue trees, quests with branching, romance, marriage.
10. Voiced dialogue. Text + one 3-note "voice" motif per NPC.
11. Fishing, bug nets as a full minigame — critters are a 1-button catch with a 0.8 s timing bar.
12. Weapon ballistics: bullet drop, travel time, penetration. **Hitscan only** (Emberlance is
    the one projectile, and it is slow and arcing on purpose).
13. Prone.
14. Difficulty settings. The shade-tier gradient *is* the difficulty setting.
15. Crafting recipe discovery / a grid. Fixed recipe list, all visible from the start.

**Out — technical**
16. Z-buffered GPU path. Painter's sort. Design around it.
17. Dynamic lights. Baked vertex colour × a global time-of-day tint.
18. Shadows of any kind except a 2-tri blob under each entity.
19. Real-time global illumination, reflections, water reflections.
20. Post-process beyond the existing dither/5-bit and a fog lerp.
21. Save-anywhere. Save on: entering town, sleeping, lighting a lantern, quitting.
22. Controller support (v1.1 — but read input through the input-frame struct so it's a 40-line add).
23. Resolution options. 320×240, integer scale 2/3/4. That's the look; it is not negotiable.

---

## 10. Open questions for the architect

1. **Chunk streaming budget** — generation must fit in ≤2 ms amortised. Is a background
   generation queue possible in Hemlock, or does this need to be a fixed per-frame slice?
2. **Screen-space quad batch** — the HUD, font, billboards and viewmodel all want a
   projection-bypass path into `SDL_RenderGeometry`. One shared batch or three?
3. **Audio** — SDL2 `QueueAudio` with a hand-rolled 8-voice mixer, or bring in SDL_mixer via FFI?
   The pitch-shifted hit-click chain (§7.2) needs per-voice resampling.
4. **Painter's sort cost** — at 2200 tris, is the per-frame sort inside budget, or does it need
   bucketing by coarse depth?
5. **Determinism** — is Hemlock's `random` seedable and reproducible across compiled/interpreted?
   World generation depends on it.
