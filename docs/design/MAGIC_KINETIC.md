# NIGHTSHADE — THE TWO DAMAGE TYPES

**Status:** design specification. Every number in this file is a number a programmer can type into
`config.hml`, `combat.hml`, `director.hml`, `progression.hml` or a new `src/sim/lamp.hml`. Where a
number is a guess it is still a *specific* guess — change it in one place, not by argument.

**Owns:** the KINETIC / RADIANT split, enemy affinities, the two new enemy classes, party roles,
exploration gating, and the progression rows that carry them.

**Does not own:** any `.hml` file. This task wrote no code. Section 12 is the implementation ledger —
the exact files, tables and literals a later wave must touch, with the traps named.

**Reads:** `CLAUDE.md`, `docs/recon/GAME_DESIGN.md` (the GDD), `docs/recon/ART_BIBLE.md`,
`docs/ARCHITECTURE.md`, `docs/BUDGET_ACTUAL.md`, and the shipping sim: `src/sim/combat.hml`,
`ai.hml`, `director.hml`, `progression.hml`, `command.hml`, `src/art/meshgen.hml`.

**Companion:** `docs/design/LORE.md`. Every mechanic here has a fictional reason there, and the two
files are meant to be edited together. A rule with no reason in `LORE.md` is a rule the player will
experience as an arbitrary damage drop.

---

## 0. THE ONE-PARAGRAPH VERSION

The player already holds both damage types and has since the first frame of the game. The **lantern**
is in the left hand of every frame that has ever been rendered — a constant 156-px bright anchor, a
genuine light source, one of the two dynamic lights the budget allows. The **gun** is in the right.
The pitch already says it: *"you push the dark back one lantern at a time, with a gun in your hands."*
So the two damage types are **LIGHT** and **LEAD**, they are the two objects on screen, and nothing
new has to be introduced to the player at all — only *revealed*. The enemy roster already splits
along the same seam: **Wisps and Motes** are made of light the dark stole, and light takes it back;
**Husks, Wardens and Bulwarks** are matter with a tenant, and matter needs lead. You may only work one
hand at a time. That is the whole system. Everything below is arithmetic.

---

## 1. THE TWO TYPES

### 1.1 The axis is new; the delivery kinds are not

`combat.hml` already has six **delivery kinds** — `DMG_BULLET`, `DMG_MELEE`, `DMG_BURN`,
`DMG_EXPLOSION`, `DMG_FALL`, `DMG_CONTACT`. Those answer *"what shape did the damage arrive in"*.
Damage **type** is a second, orthogonal axis answering *"what is it made of"*. Do not overload the
existing enum; add the axis and a lookup.

```
DTYPE_KINETIC = 0
DTYPE_RADIANT = 1
DTYPE_COUNT   = 2

DMG_RADIANT_BURST = 6      // the flare
DMG_RADIANT_BEAM  = 7      // the shutter
DMG_RADIANT_LANCE = 8      // the lance (Lv 15)
DMG_KIND_COUNT    = 9      // was 6

// indexed by DMG_*, yields DTYPE_*
g_dtype: array<i32> = [0, 0, 0, 0, 0, 0, 1, 1, 1];
```

Everything that exists today is KINETIC, including `DMG_BURN`. **The Emberlance is a gun.** It looks
like fire and it is thematically warm, but mechanically it is lead that keeps burning; it has a
magazine, a reserve, a reload and a range table. Making it radiant would give the player a radiant
*primary* at Lv 12 and collapse the whole hand-switching tension. See §11 for the v2 note.

`sub_hit = DMG_SUB_BASE + p_dmg_kind` already exists in `combat_apply_damage`. With
`DMG_SUB_BASE = 64` the three new kinds ride at 70, 71, 72 — clear of weapon ids 0..15, clear of
everything. **The wire format does not change.**

### 1.2 KINETIC — lead

Fiction: metal, thrown fast. It does not care what a thing is made of; it cares whether the thing is
*there*. See `LORE.md` §4.

| Property | Value |
|---|---|
| Sources | every weapon in GDD §2.4, melee, the Lantern Drone streak, fall damage, enemy contact |
| Resource | ammunition — **does not drop from enemies**, comes from caches and the town bench (GDD §2.4) |
| Range | **up to 72 m** (`g_FOG_FAR_CAP`) with the per-weapon falloff table |
| Precision | headshot multipliers 1.25–2.10; the head volume is the top 0.22 of the body |
| Delivery | hitscan, instant, per-shot |
| Affinity | **×1.00 against every enemy in GDD §2.2, always** |
| Scales on | weapon tier, attachments, the 10-row affix pool (GDD §3.3), Relic uniques |

**KINETIC is 1.00 against every one of the six existing classes and that is a deliberate, load-bearing
decision.** GDD §2.4's TTK table has been measured, implemented and playtested. If light-fragile
enemies also became bullet-resistant, "a Wisp dies to one bullet of anything" would stop being true,
six weapons would need retuning, and the Wisp would stop being free dopamine. **The entire affinity
system lives in the RADIANT column.** The GDD's TTK table *is* the kinetic table, unamended.

The pressure toward light therefore cannot come from making bullets worse against existing enemies. It
comes from **two new classes** (§3) that resist lead, and from what light buys that lead cannot (§1.3).

### 1.3 RADIANT — light

Fiction: stored light, spent. It cannot break a body. It can call back what the dark swallowed, and
it can hurt the dark itself. See `LORE.md` §4.

| Property | Value |
|---|---|
| Source | **the lantern in your left hand.** The only radiant source in v1. |
| Resource | **OIL**, 0–100 (tank grows to 150 / 200 — §7) |
| Range | **≤ 14 m** for the two baseline verbs; 24 m for the Lv-15 lance. Nothing radiant reaches past 24 m, ever. |
| Precision | **none, and that is the point.** Cones and radii. No headshots, no crits. |
| Delivery | instantaneous volume test (hitscan-shaped — no projectile, GDD §9.12 holds) |
| Affinity | 0.25 → 2.50 by class, ×2.0 on a bodied enemy's tell, ×5.0 on the Spitter's sac |
| Scales on | **charms** (slots at Lv 4 / 11 / 18, currently carrying nothing), tank tier, day phase |

**What light buys besides damage — the four things that make a player choose the weaker hand:**

1. **You do not have to hit.** At 320×240 a 1.8 m enemy is 12 px at 30 m and 6 px at 60 m
   (ART_BIBLE §8.1). Inside 6 m, three Wisps moving 6.4 m/s erratically are a genuinely hard target
   with a 3.2° hipfire cone. A 6 m radius that does not miss is a mechanical *gift*, and it is the
   only answer in the game to "something is on my face".
2. **It is a light.** Discharging the lamp raises the actual light level: the lantern's dynamic light
   slot is boosted for the duration, the local shade tier is suppressed while it burns, and it is the
   only thing that lights a **sconce** (§6.2) or completes the 2.5 s lantern channel.
3. **It refills where you fight.** Ammo comes from caches and the town. Oil comes from **the lantern
   you are standing at** (+3.0/s inside a lit radius). The night hold is a place where one of your two
   resources regenerates and the other does not. Running dry on lead and falling back is already a
   designed dramatic beat (GDD §2.4); now the thing you fall back to is *stronger at night*.
4. **It punishes tells.** Radiant does **×2.0 against a bodied enemy in `AI_ST_WINDUP`** — the 0.45 s
   Husk arm-raise, the 1.1 s Bulwark crouch, and (at ×5.0) the 1.4 s Spitter glow charge. Those tells
   already exist in `ai.hml`. Lead is the *proactive* hand: you aim it where a thing will be. Light is
   the *reactive* hand: you spend it the instant a thing commits. That asymmetry is why an expert uses
   both in the same fight instead of picking a favourite.

**And the cost, stated plainly:** light is 14 m, imprecise, cannot kill anything with a body, and
using it means your gun is down.

### 1.4 The stance rule — the mechanical root of everything below

> **You may only work one hand at a time.** Raising the lamp lowers the gun and vice versa.

| Property | Value |
|---|---|
| Input | a new bit in the existing button mask: `BTN_LAMP = 4096` |
| Transition into lamp stance | 0.30 s, gun cannot fire during it |
| Transition out | 0.22 s, lamp cannot discharge during it |
| Movement while in lamp stance | 2.9 m/s (`g_SPEED_ADS`) — you may not sprint |
| Lantern light while in lamp stance | radius ×2.2, intensity ×1.6 — **still one light slot** |
| Viewmodel | the existing lantern rises from `g_VM_DOWN` 0.34 → 0.14 m and centres; the gun tucks |
| ADS | mutually exclusive with lamp stance; whichever button was pressed last wins |

This single rule does four jobs at once:

- It makes the two types feel like two objects rather than two buttons on one object.
- It puts a real cost on the imprecise-but-unmissable option: 0.52 s of round trip and no sprint.
- It stops the degenerate "hold the beam while shooting" that would otherwise be strictly optimal.
- **It is the entire party-composition answer.** One player is sequential. Two players are parallel.
  Nothing else in the design needs to exist for co-op to feel different (§5).

### 1.5 The three lamp verbs

All three are instantaneous volume tests against live entities — no projectile, no travel time. Falloff
is **linear**, not smoothstepped: `mult = 1 - clamp((r - r0) / (r1 - r0), 0, 1)`. Linear because the
player must be able to feel the edge of the cone; the smoothstep the fog uses would make the boundary
mushy and unlearnable.

| | **FLARE** (baseline) | **SHUTTER / beam** (Lv 3) | **LANCE** (Lv 15) |
|---|---|---|---|
| Input | tap `BTN_FIRE` in lamp stance | hold `BTN_FIRE` in lamp stance | tap `BTN_ADS` in lamp stance |
| Shape | sphere, 360°, centred on the player | cone, 22° half-angle | cone, 5° half-angle |
| Reach `r0 / r1` | 2.0 / 6.0 m | 8.0 / 14.0 m | 18.0 / 24.0 m |
| Damage | 28 at `r0`, 14 at `r1` | **3.0 per tick at 10 Hz** = 30 DPS at `r0`, 15 at `r1` | 55 at `r0`, 27 at `r1` |
| Oil | 18 per use | 22 per second | 40 per use |
| Cooldown | 0.60 s | — (drains while held) | 1.5 s |
| Wind-up | none — this is the panic button | 0.18 s shutter open | **1.2 s**, aim locked, cancelled by damage |
| Max targets | unlimited inside the sphere | unlimited inside the cone | unlimited inside the cone |
| FX | 1 expanding additive ring card + 8 ember billboards, 0.25 s | 3 stacked additive cone cards + 4 dust motes while held | 1 tapered additive card, 0.30 s |
| Tris | 18 for 0.25 s | 14 while held | 8 for 0.30 s |

The **flare** is the get-off-me verb and it is baseline because §8's first minute demands it (§7.1).
The **shutter** is the sustained verb: the shell-stripper, the plate-scourer, the Pall-pusher, the
sconce-lighter. The **lance** arrives at Lv 15, long after the player has internalised "light is a
14 m weapon", and its 1.2 s locked wind-up is priced exactly so it never becomes a sniper.

### 1.6 Oil — the economy

| Property | Value |
|---|---|
| Tank | **100**, → 150 at Lv 10, → 200 at Lv 21 |
| Regen inside a lit lantern radius, or in town | **+3.0 / s** |
| Regen outside a radius during `PHASE_DAY` | **+0.8 / s** |
| Regen outside a radius at dawn / dusk / night | **0.0 / s** |
| Oil flask | **+35**, stacks 6, consumed in 0.4 s, cannot be used while a wave is spawning |
| Flask recipe | 1 Sap + 2 Ash → 1 flask, at the **Oil Still** (Lv 6 town building, §7) |
| Ashroot bed yield | 3 Sap per harvest (GDD §5.5, planted at dusk, harvested 2 days later) |
| On death | oil resets to 0; the tank refills from the respawn lantern at +3.0/s |

**This closes a loop the GDD left open.** Ashroot beds are currently a pure Animal-Crossing tick with
no mechanical output. Now the thing you plant at dusk in your warm town is the ammunition for your
other hand. Farming feeds the shooter. That is the single best connection between the game's three
influences in the whole design and it cost one recipe.

**Sanity check, derived not guessed.** A tier-1 hold spawns ≈110 bodies over ≈3:20 (`director.hml`
header). Under the tier-1 composition in §3.4 that is ≈38 Wisps + 33 Motes + 11 Gloams (the unbodied
half) and ≈28 Husks. Oil available over a 200 s hold standing inside the lantern radius:
`100 + 200 × 3.0 = 700`, i.e. **38 flares**. At a 6 m radius sweeping a spawn ring, a flare kills
~3 unbodied. 38 × 3 = 114 ≥ 82. **The lamp can carry the unbodied half of a tier-1 hold and nothing
else.** The 28 Husks are the gun's problem, which is exactly GDD §8's *"you have a revolver and 12
rounds. You will run out."*

### 1.7 The day-phase multiplier

Radiant damage is a *contrast* effect — light against dark. `daycycle.hml` already gives the sim a
phase; this is a four-row table indexed by it, pure integer-safe f64 constants, no art import.

| Phase | `RADIANT_PHASE_MULT` |
|---|---|
| `PHASE_DAWN` | 0.85 |
| `PHASE_DAY` | **0.70** |
| `PHASE_DUSK` | 1.00 |
| `PHASE_NIGHT` | **1.30** |

The lamp is strongest exactly when the game is hardest, and the metronome the whole game already runs
on becomes a damage-type metronome: **day is a lead game, night is a two-handed game.** It never
becomes a *light* game, because night is also when the tier tables push Husks, Wardens and Bulwarks —
all radiant-resistant. The two curves cross instead of one dominating.

Inside a lit lantern radius the phase multiplier is forced to `PHASE_DAY`'s 0.70, for the same reason
the tier is forced to 0: there is no dark there to contrast against. This is not a nerf the player will
resent — it is why you leave.

### 1.8 The full damage equation

```
raw   = base_damage_for_verb_or_weapon
mult  = affinity[class][dtype]                     // §3.3, the only new table
        * (windup_bonus  if dtype == RADIANT and target is in AI_ST_WINDUP)
        * (RADIANT_PHASE_MULT[phase] if dtype == RADIANT)
        * falloff(r)                               // per-weapon (kinetic) or linear (radiant)
        * (hs_mult if dtype == KINETIC and head)
applied = raw * mult
```

Then the existing `combat_apply_damage` body runs unchanged: the plate branch, the
`i32(applied + 0.5)` round, the `dmg_i < 1 → 1` floor ("a damage number of 0 reads as *my gun is
broken*"), the HP write, `EF_HIT_FLASH`, `EV_HIT`, `EV_KILL`.

**One insertion point, one multiply.** `combat_apply_damage` is not a hot function — the worst case is
9 Bellows pellets in a single shot at 75 RPM, plus at most 14 AI contact events per tick. Two array
lookups and a multiply per call is unmeasurable at 60 Hz. *That is a prediction, not a measurement —
see §13.*

---

## 2. WHAT THE PLAYER SEES — the one-second test

> **ART_BIBLE RULE S1**: every enemy identifiable by class at 12 px (30 m), detectable as a threat at
> 6 px (60 m). **A resistance you cannot perceive is just an unexplained damage drop.**

*(Note: the task brief cites "ART_BIBLE §6" for this. §6 is FOG. The readability rules are §8.1
(S1/S2/S3) and §8.2. Flagged in §14.)*

Affinity must be readable from **silhouette, colour and motion** — the only three channels that
survive at 6 px — and it must never require a UI element, a scan, or a health bar.

### 2.1 The three rules that carry it

**RULE A — matter has a shadow and a footfall.** Everything in the game has a mandatory 2-triangle
contact blob (CLAUDE.md §9.6). The **bodied** classes keep the dark blob and they *step* — a footfall
cadence, a weight shift. The **unbodied** get a blob that is **inverted**: a 2-tri card in `ATLAS_FX`,
additive, tinted `NS_HALO`, i.e. a faint *pool of light* under the thing instead of a shadow. Same
triangle count, same layer discipline, opposite meaning. At 6 px you cannot see the creature, but you
can see whether the ground under it is darker or brighter, and that tells you which hand to raise.

This preserves CLAUDE.md §9.6 exactly ("no exceptions") while inverting its *meaning* for three
classes. It does move those cards from `ATLAS_WORLD` (BLEND) to `ATLAS_FX` (ADD) — a real technical
consequence, flagged in §14.

**RULE B — violet says "enemy", warm says "vulnerable".** ART_BIBLE §3.8's usage law reserves violet
for hostile / collectable / progression, and RULE S2 requires a persistent `NS_CORE` emissive marker
≥2 px at 60 m on every hostile. **That marker stays on every hostile at all times, unchanged.** The
new signal is a *second, smaller, warm* additive card — `MUZZLE_MID` / `EXPLO_HOT` — that appears only
during a radiant vulnerability window. Violet is identity. Warm is a window. The two never substitute
for each other, so long-range readability is untouched. This is an amendment to §3.8's usage law and
must be ratified, not assumed (§14).

**RULE C — the resisted hit looks resisted, in the same frame.** Two new bits in the existing
hitmarker mask (`HM_HEAD=1`, `HM_KILL=2`, `HM_FALLOFF=4`, `HM_ARMOR=8`):

| Bit | Name | What the player gets |
|---|---|---|
| 16 | `HM_RADIANT` | hitmarker is a **4-petal bloom**, not a cross; damage number in `UI_AMBER` |
| 32 | `HM_RESISTED` | number renders in `UI_DIM` at **half size** with a small ▼ glyph; enemy flash goes to dim amber instead of white and `HIT_FLASH_CS` halves 6 → 3; a 4-tri `FX_SCALD` puff instead of a spark |

Both ride in the `sub` field of the existing `EV_HITMARKER` / `EV_DAMAGE_NUMBER` / `EV_HIT_FLASH`
events. **Zero new events, zero new packet fields.** The hit-feedback contract (CLAUDE.md §9) still
fires all five channels — they just fire *differently*, which is the whole point. A resisted hit is
still a hit; it is a hit that says "wrong hand".

### 2.2 The cue table — per affinity, per screen size

| Affinity | 60 px (≤10 m) | 12 px (30 m) | 6 px (60 m) |
|---|---|---|---|
| **Unbodied** — light-weak | bright pool under it, no feet, sine-bob, violet halo card whose **alpha is its health** | pool of light instead of shadow; drift with no footfall cadence | a violet dot over a *bright* smudge on the ground |
| **Bodied** — light-resistant | dark contact blob, footfalls, earth palette (`MUD`, `GRANITE_LO`, `STONE_MID`) | dark blob, walk cycle, wide head:shoulder | a violet dot over a *dark* smudge |
| **Sacked** (Spitter) | sac emissive switches `NS_CORE` → `EXPLO_HOT` and grows **2.2×** for the 1.4 s charge | the warm dot appears and swells — visible at 12 px because it is a *brightness change*, not a shape change | the violet dot briefly turns amber |
| **Shelled** (Snuffer) | featureless `NS_DEEP` lozenge with one violet seam; **no class silhouette at all** | an unreadable black blob among readable enemies — "I can't tell what that is" **means** "strip it" | a dark lozenge with no limbs |
| **Light-eating** (Gloam) | **the world closes in** — fog draws to 35 % of its distance, your lantern radius halves | same; the fog is a screen-wide cue, so distance does not degrade it | same. **This is the only cue in the game that is more visible the further away you are.** |

### 2.3 The Gloam's fog effect — numbers, and why it is free

| Property | Value |
|---|---|
| Radius of influence | 12.0 m from a live Gloam |
| `FOG_FAR` multiplier | **×0.35**, never below `FOG_FAR_MIN = 10.0 m` |
| Lantern radius multiplier | ×0.50 |
| Ramp in / out | 0.8 s / 1.5 s |
| Stacking | **none.** Take the nearest Gloam only. Two are not darker than one. |

At `FOG_FAR = 72 m` (the shipping cap) the ART_BIBLE §2.6 formula `(π/4)·d²/16·2` gives **509 ground
triangles**. Pulled to 25.2 m it gives **62**. A Gloam therefore *returns* ~447 triangles to the
budget while it is alive. The scariest enemy in the design is the cheapest one to render. Do not
"optimise" this away by faking the fog with a screen overlay — the real fog parameter is both free and
correct.

### 2.4 Audio — two kill sounds for the same enemy

The Wisp's chime already exists (GDD §2.2: *"audible chime 0.5 s"*). `LORE.md` §4 says the chime is
the stolen light ringing.

- Killed by **lead**: the chime **stops mid-note.** Cut, not faded. 1 sample, gated.
- Killed by **light**: the chime **resolves** — it completes its interval upward and lands. 1 extra
  sample, ~0.35 s.

Two samples, one existing event, and it is the whole system in a sound. Same treatment on the Mote and
the Gloam. `SFX_KILL_CHIME` already exists; add `SFX_KILL_RESOLVE`. The resisted hit gets a dull
*thock* instead of the pitched blip, and the pitch chain (`chain_step`, +2 semitones per consecutive
hit) **does not advance on a resisted hit** — the rising pitch is a reward for using the right hand.

### 2.5 The acceptance criterion

> Show a naive playtester **8 stills at 320×240 for 1.0 s each** — one per affinity case, two
> distractors. They must name the correct hand (**"gun" / "lamp"**) on **≥ 7 of 8**. Not the class
> name. Not the multiplier. The hand.

If it fails, the fix is silhouette or fog, never a UI element. A tooltip is an admission that the art
did not work.

---

## 3. ENEMY AFFINITIES

### 3.1 The existing six, extended — GDD §2.2 is not replaced

Every row of GDD §2.2 survives intact. HP, tris, speed, attack, damage, range, tell, ember, XP and
cost are unchanged for all six. **One column is added.**

| Enemy | HP | Body | **KINETIC** | **RADIANT** | Radiant window | Why |
|---|---|---|---|---|---|---|
| **Wisp** | 15 | unbodied | 1.00 | **2.50** | — | Pure stolen light in a shape. One flare deletes a swarm. |
| **Mote** | 30 | unbodied | 1.00 | **2.00** | — | Slow, drifting, always visible — the AoE target the game is teaching you to notice behind you. |
| **Husk** | 90 | bodied | 1.00 | **0.35** | ×2.0 on the 0.45 s arm-raise | Matter with a tenant. The bread-and-butter enemy stays a bread-and-butter *gun* fight. |
| **Spitter** | 70 | bodied + sac | 1.00 | **0.60** | **×5.0** on the 1.4 s glow charge | Its existing tell *is* a light-filled sac. Hit it while it charges and it pops. |
| **Warden** | 220 + 80 plate | bodied + plate | 1.00, plate arc + 75 % DR unchanged | **0.25** body | radiant into the **plate pool at ×2.50, facing-independent** | Light goes round a shield. Scour the plate with the lamp, then kill with lead — a fast option, never the only one. |
| **Bulwark** | 900 | bodied | 1.00 | **0.30** | ×2.0 on the 1.1 s slam crouch | The wave-3 punctuation stays a lead fight. 900 HP at 11.7 radiant DPS is 77 s: the lamp is *irrelevant* here and should be. |

### 3.2 The two new classes

Two, not five. Every new class costs 3 LOD meshes, 6 table rows across 5 modules, and a re-normalised
director table. Two is what the design needs; a third would be decoration.

#### GLOAM — the light-eater. *Teaches "lead is not always the answer."*

| | |
|---|---|
| HP | **40** |
| Tris (LOD0 / 1 / 2) | 34 / 34 / 12 — unbodied, so a lozenge at every LOD, never a humanoid |
| Speed | 3.0 m/s drift, lunges to 5.5 m/s inside 4 m |
| Attack / dmg / range | contact chill / **10** / 0 |
| Tell | none on the body. **The world closes in** (§2.3) — the cue arrives before the creature does. |
| KINETIC | **0.15** |
| RADIANT | **2.00** |
| Ember / XP / cost | 3 / 20 / 4 |
| Palette | `NS_DEEP` body, `NS_CORE` marker, `NS_HALO` glow card, inverted light-pool contact card |
| Silhouette | horizontal lozenge with a **trailing tear on the −Y axis** — no limbs, no head, so it can never be confused with a bodied class at 12 px |
| First seen | **shade tier 1, 10 % of the roll** — on the player's first trip to the frontier |

Design intent: this is the teacher, and it is deliberately **not lethal**. 10 damage at contact against
100 HP with 25 HP/s regen means a solo player at level 1 with no beam can simply *walk away* and
survive to understand what happened. What they will do first is shoot it, and get grey half-size
damage numbers and a dull thock — the `HM_RESISTED` channel — and that is the lesson. Then they raise
the lamp and it dies in half a second. **13:1** in favour of the right hand:

| Approach | Maths | Time |
|---|---|---|
| Kestrel near, kinetic | 45 × 0.15 = 6.75 → 6 shots at 200 RPM | **1500 ms** (one full cylinder) |
| Shutter at 8 m, night | 30 DPS × 2.00 × 1.30 = 78 DPS → 40 HP | **510 ms** |

Note the worst case is 1.5 s and one cylinder, **not a wall.** See §5.3.

#### SNUFFER — the two-layer enemy. *Teaches "light opens, lead kills."*

| | |
|---|---|
| Shell | **60**, stored in the existing `world.armor` column |
| Body HP | **110** |
| Tris | **shell 14** (the shell *replaces* the body mesh while intact) / body 90 at LOD1 / 28 at LOD2 |
| Speed | 3.6 m/s |
| Attack / dmg / range / tell | overhand / **22** / 2.0 m / 0.55 s wind-up |
| KINETIC | **0.20 while shelled**, **1.00 once the shell is gone** |
| RADIANT | **2.20 into the shell pool** (never into HP), **0.30 against the body** once open |
| Ember / XP / cost | 8 / 45 / 12 |
| Palette | shelled: `NS_DEEP` lozenge, one `NS_MID` seam, the mandatory `NS_CORE` marker. Open: `STONE_MID` humanoid with an `EMBER` core. |
| Silhouette | **total change on break.** Shelled it has no class silhouette at all; open it is an ordinary humanoid. The strongest 320×240 signal available. |
| First seen | shade tier 2, 5 % of the roll |

Mechanics, using machinery that already exists:

- The shell is `world.armor`, spawned via `combat_plate_hp(class)` — the same field and the same
  function as the Warden plate.
- Radiant damage against a shelled Snuffer is applied **entirely to the shell pool** and never to HP.
- Kinetic damage against a shelled Snuffer is `×0.20` **into HP** and does not touch the shell. So
  lead *can* kill it through the shell — 110 / (26 × 0.20) = 22 Sparrow rounds — it is simply the slow
  and expensive road.
- The shell does not regenerate.

| Approach | Maths | Time | Cost |
|---|---|---|---|
| **Light then lead** (intended) | shutter 30 × 2.20 × 1.30 = 85.8 DPS → 60 shell = 0.70 s; then Sparrow near 26 → 110 HP = 5 rounds | **0.70 s + 0.35 s ≈ 1.05 s** | 15 oil + 5 rounds |
| **Lead only** | 26 × 0.20 = 5.2 per round → 110 HP = 22 rounds | **1.91 s** | 22 rounds (73 % of a Sparrow mag) |
| **In a party** (one lamp, one gun, simultaneous) | strip and shoot in parallel | **0.70 s** | same total |

Solo 1.05 s, party 0.70 s, lead-only 1.91 s. **Solo is 1.5× slower than a party and lead-only is 2.7×
slower than the intended play — and neither is blocked.** That is the shape every affinity in this
document must have.

### 3.3 The affinity table, as a programmer types it

```
// [class][dtype], DTYPE_KINETIC = 0, DTYPE_RADIANT = 1
// Classes in g_ENEMY_* order: Wisp Mote Husk Spitter Warden Bulwark Gloam Snuffer
// Flat, row-major, indexed [cls * DTYPE_COUNT + dtype].
g_affinity: array<f64> = [
//  KIN   RAD
    1.00, 2.50,      // Wisp
    1.00, 2.00,      // Mote
    1.00, 0.35,      // Husk
    1.00, 0.60,      // Spitter
    1.00, 0.25,      // Warden   (radiant vs the PLATE POOL is 2.50, facing-independent)
    1.00, 0.30,      // Bulwark
    0.15, 2.00,      // Gloam
    0.20, 2.20       // Snuffer  (SHELLED: radiant hits the shell only.
                     //           OPEN: kinetic 1.00, radiant 0.30)
];

RADIANT_WINDUP_MULT   = 2.00;    // bodied enemy in AI_ST_WINDUP
SPITTER_SAC_MULT      = 5.00;    // replaces WINDUP_MULT for the Spitter
WARDEN_PLATE_RADIANT  = 2.50;    // radiant into the plate pool
SNUFFER_SHELL_HP      = 60;
SNUFFER_OPEN_RADIANT  = 0.30;
SNUFFER_OPEN_KINETIC  = 1.00;
FLOOR_MULT            = 0.15;    // §5.3: the law. No multiplier below this, ever.
```

### 3.4 The re-normalised director composition table

`g_dir_w` in `director.hml` is `[tier * 6 + kind]` and **every row must sum to exactly 100**
(`director_table_ok` asserts it, so a typo is a test failure). Two new classes means two new columns
and **all five live rows must be re-normalised.** This is the largest ripple in the design and it is
owned here, with a concrete replacement rather than a note.

```
//                     Wisp Mote Husk Spit Ward Bulw Gloam Snuf     sum
g_dir_w: array<i32> = [
       0,   0,   0,   0,   0,   0,    0,    0,   //   0   tier 0 — inside a lit lantern
      35,  30,  25,   0,   0,   0,   10,    0,   // 100   tier 1
      20,  15,  35,  12,   0,   0,   13,    5,   // 100   tier 2
      12,   0,  33,  22,  16,   0,   10,    7,   // 100   tier 3
       4,   0,  28,  20,  28,   0,   10,   10,   // 100   tier 4
       0,   0,  20,  20,  32,   8,    8,   12    // 100   tier 5
];
g_dir_cost: array<i32> = [2, 3, 6, 8, 20, 90, 4, 12];
g_dir_bulwark unchanged: [0, 0, 0, 4, 6, 0];     // indexed by TIER, still 6 rows
```

Deliberate properties of that table, each checkable:

- **Husk stays at 25 % in tier 1.** GDD §8's first-night beat — *"Four Husks come up the hill,
  silhouetted against the last light"* — survives byte for byte.
- **Gloam appears at tier 1 (10 %)** so the player meets the light-teacher on their first frontier trip,
  with a revolver, when it cannot kill them.
- **Snuffer appears only at tier 2+ (5 %)** so the one-beat lesson lands before the two-beat one.
- **Wisp + Mote falls 75 → 65 % in tier 1** and Wisp falls 25 → 20 % in tier 2. The unbodied share
  drops slightly because Gloam is also unbodied; total "lamp food" in tier 1 goes 75 % → 75 %.
- Warden and Bulwark shares are within 1–4 points of the GDD's, so the high-tier feel is preserved.
- The new classes never exceed 22 % of a roll combined, so no hold becomes "the Gloam hold".

### 3.5 The affinity spread, and why it is only 4.5× wide

Radiant multipliers span 0.25 → 2.50 — a factor of 10 across the roster but never more than a
**4.5× swing** from the mean for any single class. That is deliberate. A ×0.05 resistance is
indistinguishable from immunity and reads as a broken gun; a ×6.0 vulnerability makes the other hand
pointless. 0.25–2.50 is wide enough that the player *feels* it in the TTK on the first try, and narrow
enough that the wrong hand is always still a hand.

---

## 4. HOW THE PLAYER LEARNS IT — the teaching order

Nothing here is a tutorial. Every step is a fight the player will have anyway.

| When | The lesson | How it is taught |
|---|---|---|
| 0:10, GDD §8 | there are things that die to one bullet | three Wisps, one Kestrel round each. **Unchanged.** |
| 0:30, GDD §8 | **the lantern is a weapon** | the lantern lights → `+350 XP`, `LEVEL 2`, and *the flare is granted by the act of lighting it*, not by a card (§7.1). One line under the unlock card: *"Some of it came back with you."* |
| 0:33–0:55 | **the lamp will not save you from a body** | four Husks. Flare them: 12 damage each, grey numbers, a dull thock. The revolver is the answer. This is the first time the game is frightening and now it is also the first time the system speaks. |
| first frontier trip (tier 1) | **lead is not always the answer** | a Gloam. The fog closes in before you see it. You shoot it, get grey half-size numbers, then raise the lamp and it dies in half a second. |
| tier 2 | **light opens, lead kills** | a Snuffer. An unreadable black lozenge that ignores bullets. The beam peels it and a normal humanoid steps out. |
| any Spitter | **windows** | you happen to flare a Spitter mid-charge and it pops for 5×. Nobody told you. You will tell a friend. |
| Lv 14 lantern T3 / any Warden | **light goes round a shield** | you lamp the plate off in 0.82 s instead of dumping 3 Longshadow rounds into it. |

**The rule this table obeys:** every lesson is taught by an enemy the player was going to fight,
inside a fight they were going to have, with feedback that arrives in the same frame as the mistake.
No pop-up ever explains an affinity. If a lesson needs text, the enemy is designed wrong.

---

## 5. PARTY COMPOSITION

Multiplayer is **v2** (GDD §9.1). The architecture supports it — deterministic headless sim,
authoritative-server shape, `InputCommand` on the wire, save as a wire contract — but v1 is
single-player. **So the system must be satisfying solo and better in a party, and it must never be
solo-hostile.** That is a hard constraint, not a preference.

### 5.1 Roles are verbs, not classes

There is no class select, no loadout lock, no "healer". **Every player carries a gun and a lantern.**
A role is what your hands are doing this minute.

| Role | What it does | Exists solo? |
|---|---|---|
| **LAMP** | holds the shutter: strips shells, scours plates, sweeps the unbodied, pushes a Pall back, lights sconces | yes — you switch to it |
| **GUN** | kills what the lamp opened, holds the long lane, deletes Spitters at 30 m, ends Wardens and Bulwarks | yes — you switch to it |
| **WICK** | runs the Wick Line, revives, carries spare flasks and Lantern Kits, lights the *second* sconce | **no. This is the v2 role.** |

The Wick role does not exist solo, and **no mainline content requires it.** That is how a party feels
categorically different without solo being a lesser version of the same thing.

### 5.2 What a party actually gains — precisely

Because of §1.4's stance rule, a solo player is **sequential** and a party is **parallel**.

| Situation | Solo | Two players | Gain |
|---|---|---|---|
| One Snuffer | 0.70 s strip + 0.35 s kill = **1.05 s** | strip and shoot at once = **0.70 s** | 1.5× |
| One Warden | 0.82 s plate scour + 1.60 s Longshadow = **2.42 s** | **1.60 s** | 1.5× |
| Wisp swarm + 2 Husks | flare, switch (0.52 s), shoot | one flares while the other shoots | ~1.4× |
| N=3 sconce door | needs a placed Lantern Kit (200 Ember + mats) | free | a cost, not a lock |
| Standing in a Pall | your own 14 m of light | two overlapping cones = a corridor | qualitative |

**A party is worth ~1.5× on the hard targets, not 3×.** Deliberate. Co-op that trivialises content
makes solo the "wrong" way to play, and this game's Animal-Crossing pillar means a lot of people will
play it alone forever.

### 5.3 The solo answer to a resistant mob — the ladder, and the law

> **THE LAW.** No enemy in Nightshade is immune to either type. **No multiplier is ever below
> `FLOOR_MULT = 0.15`.** The worst case in the entire game is a **6.7× longer TTK**, never an
> infinite one. Every "wall" in this design is a soft wall with a stated price.

When a player meets something their current hand is bad against, in order of what they will actually
reach for:

1. **Switch hands.** 0.30 s in, 0.22 s out. Always available, from minute one, with no unlock.
2. **Use distance.** Radiant is 14 m. If the lamp is failing, the answer is usually *back off* — and
   backing off is a movement-tech opportunity (slide-jump), which is the part of the game that is
   already good.
3. **Spend oil.** A flare has no aim requirement and no wind-up. 18 oil, 5 uses on a full tank.
4. **Grind the wrong hand.** 22 Sparrow rounds kills a shelled Snuffer. 6 Kestrel rounds kills a
   Gloam. Slow and expensive, never impossible.
5. **Walk away.** The world is infinite, the shade tier is a gradient, and there is always another
   silhouette in view (GDD §1). **No mainline content is mandatory.**
6. **Come back with a bigger tank.** Lv 10 → 150 oil, Lv 21 → 200.

### 5.4 What v1 must build so v2 costs nothing later

- Oil, stance, cooldowns and tank tier live in **one serializable state array per player**
  (`src/sim/lamp.hml`, shaped exactly like `progression.hml`'s `array` of i32/f64 slots) with
  `lamp_serialize` / `lamp_deserialize` / `lamp_hash`. No closures, no objects-per-entity — CLAUDE.md
  §7 ("no entity state in a closure") is the reason this is not a struct with methods.
- The lamp stance is a **bit in `InputCommand.buttons`**, so it predicts and reconciles for free
  through the machinery that already exists.
- Radiant damage goes through **`combat_apply_damage`**, so it is authoritative, event-mirrored, and
  in the state hash on day one.
- Sconce state is **world state**, not player state (a lit sconce is lit for everyone).

Nothing above is v2-only work. It is the v1 shape, done right once.

---

## 6. EXPLORATION GATING — "explore certain areas"

This is the Minecraft pillar: the pull of what is over that hill. **A lock is only good if the key is
legible.** So every gate below is visible from outside, states its own arity, and has a stated price
rather than a requirement.

> **THE ANTI-GATE LAW.** No area is ever gated on a damage type the player does not possess. The
> player has both types from the moment the first lantern lights, ~30 seconds in. Every gate is gated
> on **capacity** (tank size, beam reach), **simultaneity** (two sconces at once), or **skill**, and
> never on possession. A gate the player cannot see the key for is a bug.

### 6.1 THE PALL — a region gate you can see from 200 m

A **Pall** is a standing volume of dark: a dome of near-black fog with a hard edge, 40–70 m radius,
rolled per chunk at shade tier 3+ (1 per ~30 chunks). Implementation is a **local fog override**, not
new geometry.

| Property | Value |
|---|---|
| Radius | 40–70 m, hashed per chunk |
| Inside: `FOG_FAR` | **12 m**, and the sky is not drawn |
| Inside: `FOG_TINT_MUL` | `NS_DEEP`-ward, the tier-5 `#14121c` end of the ART_BIBLE §4.2 table |
| Inside: shade tier | forced to **5** |
| Inside: Gloam spawn weight | **×3** |
| Inside: `RADIANT_PHASE_MULT` | forced to **1.30**, day or night |
| Loot | tier-5 drop weights (Relic 14 %) — reachable long before the Lv 30 Deepshade key |
| Resource | Shadeglass nodes, 2–4 |
| Tris | **0 new.** It is a fog parameter. At 12 m, ground triangles are ~14. |

**Why it is legible.** From 200 m away it is a black bruise on the horizon with a hard edge — the one
silhouette in the game that is *not* a shape but an absence. Walk to its edge and you watch your own
lantern radius halve and your draw distance collapse; step back out and it returns. Nothing stops you
entering at level 1. You will die, visibly, for a reason you can name in one sent: *"I couldn't see."*

**What it gates on.** Oil tank and the shutter — both early and cheap. Inside a Pall your gun's range
falloff is irrelevant because you cannot see 12 m, so the Pall is the one region in the game where the
**lamp is the primary weapon** and the gun is the sidearm. That inversion is the reward: a place where
the thing you have been treating as support becomes the point.

**Map legibility.** A discovered Pall draws on the world map as a black blot among the warm lantern
dots. Lighting a T3+ lantern within 85 m of a Pall shrinks it by that lantern's radius, permanently and
visibly, on the map. **The map becomes a record of dark you personally deleted.** That is the retention
hook the GDD already identified, given a second thing to draw.

### 6.2 THE SCONCE DOOR — a lock that displays its own arity

Ruins (1 per 6 chunks) and Burrows (1 per 20 chunks) may carry a sealed **sconce door**: stone, with
**N empty sconces carved above it**, N ∈ {1, 2, 3}. You can count them from 30 m.

| | |
|---|---|
| Lighting one sconce | 0.8 s of shutter contact, ≤ 8 m |
| A lit sconce stays lit | **12.0 s** |
| Door opens | when all N are lit simultaneously |
| N=1 | anyone, always. ~60 % of doors. |
| N=2 | sconces 12–18 m apart. Solo is a **movement-tech puzzle**: light one, slide-jump, light the second inside 12 s. ~30 % of doors. |
| N=3 | sconces **25–40 m apart.** 12 s is not enough solo on foot. ~10 % of doors. |
| Tris | 12 for the door, 4 per sconce, +2 emissive per lit sconce. ≤ 24. |

**The solo key to an N=3 door, and why it is not a wall.** A **Lantern Kit** placed within 8 m of a
sconce lights it *permanently*. Lantern Kits already exist in GDD §4.5 at 20 Ironwood + 10 Glass +
200 Ember. So an N=3 door is **free in a party and expensive solo** — a cost, never a lock. And the
solo player who pays it gets a permanent T1 lantern next to a Burrow, which is a genuinely good place
to have one. The consolation prize is better than the shortcut.

This is the **only** genuinely party-favouring content in the design, it is ~10 % of one POI type, and
it is entirely optional side content. That is the correct v1 dose.

**Why the key is legible.** The door literally displays its own arity as three dark holes. The player
has lit a hundred things by the time they meet one. There is no vocabulary to learn.

### 6.3 GARRISONS — a skill gate, not a lock

Certain POIs — Warden camps in Ironpine, Burrows in Ashwood — are garrisoned by **Snuffers**. Nothing
is locked. Solo you must alternate hands under pressure; in a party you do not. This is where the
two-beat rhythm becomes a *skill*, and it is the difficulty gradient doing its job (GDD §9.14: the
shade-tier gradient *is* the difficulty setting).

### 6.4 What is deliberately NOT gated

- **No biome is gated.** Deepshade already has its Lv 30 key; nothing else gets one.
- **No Lantern Post is gated.** Every lantern must be lightable by any player at any level, forever.
  The lantern is the save point, the respawn, the refuel and the fast-travel node — gating one would
  gate the game.
- **No Grove is gated, ever.** Groves are the exhale (GDD §4.4). A gated Grove is a contradiction in
  terms.
- **The town is never gated and never threatened.** GDD §9.8's promise stands.

---

## 7. PROGRESSION

### 7.1 The flare is not an unlock

The flare is **granted by lighting the first lantern**, keyed on `sim.lanterns_lit == 1`, which is
already in the world state and already saved.

Three reasons: (a) GDD §8 shows exactly **one** unlock card at 0:30 — "TINKER SMG — at the bench" — and
a second card would dilute the best moment in the game; (b) the fiction is better as an event than as
a menu row (*"Some of it came back with you."*); (c) it makes lighting the first lantern the moment the
game hands you your second hand, which is the thesis of this document delivered as a beat rather than
as a stat.

### 7.2 Five new rows on the unlock ladder

`progression.hml` says **"Ids are API — append at the end, never renumber."** So these are ids 25–29,
appended, and `UNLOCK_COUNT` goes 25 → 30. Note that this **breaks the file's stated
`g_unlock_level`-is-sorted invariant** — flagged and resolved in §14.

| Id | Name | Level | Effect |
|---|---|---|---|
| 25 | `UNLOCK_LAMP_SHUTTER` | **3** | the sustained beam (§1.5) |
| 26 | `UNLOCK_OIL_STILL` | **6** | town building: 1 Sap + 2 Ash → 1 oil flask |
| 27 | `UNLOCK_LAMP_TANK_2` | **10** | oil tank 100 → **150** |
| 28 | `UNLOCK_LAMP_LANCE` | **15** | the 24 m lance (§1.5) |
| 29 | `UNLOCK_LAMP_TANK_3` | **21** | oil tank 150 → **200** |

**These rows fill holes rather than crowding the ladder.** `g_unlock_level` is
`[2,2,3,4,4,5,5,6,7,8,9,9,11,11,12,13,14,16,18,18,20,22,25,28,30]`. Levels 2..30 that currently grant
**nothing**: 10, 15, 17, 19, 21, 23, 24, 26, 27, 29. Three of the five new rows land on empty levels
(**10, 15, 21**); the other two join levels that currently have a single row each (3, 6). No level goes
above 2 unlocks. Checkable claim, checked.

Deliberate pairing at Lv 6: the **Ammo bench** (lead) and the **Oil Still** (light) arrive together.
The game says "you now maintain both hands" in one level-up.

### 7.3 Charms carry the lamp

Charm slots unlock at Lv 4 / 11 / 18 and currently carry nothing specified. **Charms are the lamp's
affix system**, keeping the 10-row weapon affix pool (GDD §3.3) purely kinetic and untouched.

| Charm | Band |
|---|---|
| +% radiant damage | 5–15 % |
| +% oil capacity | 8–20 % |
| −% oil cost | 6–18 % |
| +% shutter reach | 5–15 % (14 m → 16.1 m at the top) |
| +% radiant vs unbodied | 8–24 % |
| −% stance transition | 10–30 % (0.30 s → 0.21 s) |
| +oil regen inside a lantern | +0.5–1.5 / s |
| Flare leaves a 2 s light pool (3 m, 6 radiant/s) | — |

Rarity and affix count follow the existing GDD §3.3 tiers exactly. Charms drop from the same table as
everything else; no new loot system.

### 7.4 New XP sources

| Event | XP | Why |
|---|---|---|
| Gloam / Snuffer kill | **20 / 45** | slots between Mote (12) and Warden (90), matching their cost (4 / 12) |
| Sconce door opened | **200** | below "POI cleared" (250), above "new chunk" (40) |
| Pall shrunk by lighting a lantern in range | **400** | the largest non-Bulwark award in the game. It should be. |
| First kill of a class with the correct hand | **60**, once per class per save | the Almanac paying you for understanding |

`g_xp_kill` becomes `[6, 12, 25, 30, 90, 400, 20, 45]`.

### 7.5 Almanac and the Wickmark cosmetic

The Almanac's 18 enemy entries become 20. Each entry records **which hand you have killed that class
with** — a 2-bit field per class, 16 bits total, one i32. Filling both bits on all 8 classes is a
small completion goal that *teaches the system as its reward*. Wickmarks (each 40 000 XP past Lv 30)
already grant "a cosmetic lantern flame colour"; that colour is now visible on the flare ring and the
shutter cone, so prestige is visible in the thing you hold. **Zero new systems.**

### 7.6 What does not change

The XP curve (`500 + 250L + 25L²`), the level soft cap (30), the Wickmark rate (40 000), the three
Ember Streaks and their kill thresholds (4 / 7 / 11), the loot rarity table, the affix bands, and all
six Relic uniques. **Radiant kills feed streaks normally** — a flare that kills five Wisps advances
the streak by five and can fire Dawnfall. Do not special-case it; the streak is a reward for killing,
not for aiming.

---

## 8. BUDGET

Every task has a budget impact. Here is this one's, itemised, with the arithmetic shown.

### 8.1 Triangles

| Line | Tris | Note |
|---|---|---|
| HUD: oil bar (plate + fill + 3 numerals) | **+10** | HUD is ≤250 (ART_BIBLE §8.3); GDD §0 estimates ~100 in use |
| HUD: stance crosshair (4 arcs replacing the cross) | **+8** | at screen centre, `UI_AMBER` |
| Flare FX, 0.25 s | +18 | 1 ring card + 8 embers |
| Shutter FX, while held | +14 | 3 cone cards + 4 dust motes |
| Lance FX, 0.30 s | +8 | 1 tapered card |
| Sconce door + 3 sconces | +24 | POI geometry, inside the GDD §4.4 Ruin budget of 90 |
| Unbodied inverted contact card | **±0** | 2 tris either way; moves `ATLAS_WORLD` → `ATLAS_FX` |
| Snuffer while shelled | **−76** | a 14-tri lozenge replaces the 90-tri LOD1 humanoid |
| Gloam vs a humanoid of the same tier | **−56** | 34-tri lozenge vs 90-tri LOD1 |
| A live Gloam's fog pull (72 m → 25.2 m) | **−447** | `(π/4)·d²/16·2`: 509 → 62 ground tris |
| Inside a Pall (`FOG_FAR` 12 m) | **−495** | 509 → 14 ground tris |

**Steady-state worst case: +18 (HUD, permanent) + 32 (flare and shutter overlapping) = +50 tris.**
Against 2500 steady / 3500 hard clamp, and against a measured playing frame of 1806. The two new enemy
classes and the one new region type are all **net triangle negatives.** The scariest content in this
design is the cheapest to render, which is the correct relationship on this engine.

### 8.2 Dynamic lights — the 2-cap holds

`g_MAX_DYNAMIC_LIGHTS = 2` is **RATIFIED** (BUDGET_ACTUAL: 4 lights cost 8.47 ms of emit, 93 % of the
render budget). This design adds **zero** light slots:

- The flare, the shutter and the lance all **modulate the lantern's existing slot** — radius ×2.2,
  intensity ×1.6 for the duration. No new slot.
- The muzzle flash keeps slot 2.
- A lit sconce is an **emissive card**, not a light (ART_BIBLE §4.4: emissives are additive geometry).
- A Pall *removes* light: it halves the lantern radius.

**If an implementer finds themselves adding a third light for the beam, the design is being
implemented wrong.** The beam is additive geometry plus a boosted lantern.

### 8.3 Frame time

| Line | Estimate | Confidence |
|---|---|---|
| `combat_apply_damage` affinity lookup | 2 array reads + 1 multiply per call, ≤ 9 calls/shot + ≤14 AI events/tick | prediction |
| Radiant volume test (flare) | one distance test per live entity, ≤ 14 entities, at ≤ 1.67 Hz | prediction |
| Radiant volume test (shutter) | ≤ 14 dot products at **10 Hz**, not 60 | prediction |
| Gloam fog ramp | 1 lerp per frame on a single scalar | prediction |
| `lamp_step` | ~20 f64 ops per player per tick | prediction |

**All five are predictions, not measurements. No code was written and nothing here was benchmarked.**
See §13.

### 8.4 Memory, atlas, save, wire

| Line | Cost |
|---|---|
| New meshes | 2 classes × 3 LODs = **6**; `MESH_COUNT` 34 → 40 |
| New FX atlas cells | **5** (`FX_LAMP_CONE`, `FX_LAMP_RING`, `FX_SCALD`, `FX_SHELL_SEAM`, `FX_LIGHT_POOL`) of **36 free** — `FX_CELL_COUNT` is 28 in an 8×8 = 64-cell atlas. 33 free after. |
| New audio samples | 2 (`SFX_KILL_RESOLVE`, the resisted *thock*) |
| Boot time | +6 meshes against a 400 ms boot budget building 34. **Must be measured, not assumed.** |
| Save | one new block for `lamp` state (oil, stance, tank tier, cooldowns) → **`SAVE_VERSION` 1 → 2**. `save.hml` is a wire contract; this is a version bump, not a free change. |
| Wire — input | `BTN_LAMP = 4096` in a field that is already **u32** on the wire. **0 extra bytes.** |
| Wire — events | new `sub` values 70/71/72 and `HM_*` bits 16/32, all in existing fields. **0 extra bytes.** |
| Wire — snapshot | **none.** Oil is local-player predicted state, like ammo. It is not replicated. |

---

## 9. THE FIRST 33 SECONDS ARE UNTOUCHED

GDD §8's opening is implemented, playtested and verified to happen exactly as written. This design
does not modify a single beat of it:

| t | Beat | Change |
|---|---|---|
| 0:00 | the bell, *"The lamps went out on a Tuesday."* | none |
| 0:03 | camera stands up, Kestrel in hand, `6 / 12` | none |
| 0:06 | the unlit lantern 40 m downhill, the brightest object on screen | none |
| 0:10 | three Wisps, one shot each, `+18 XP` | none — kinetic is 1.00 |
| 0:18 | a Mote, two shots, ammo `1 / 12` | none |
| 0:24 | `HOLD [E] — LIGHT THE LANTERN` | none |
| 0:27 | the 2.5 s channel, the music stops | none |
| 0:30 | the ring, the bell, `+350 XP`, `LEVEL 2`, the Tinker card | **+ one line:** *"Some of it came back with you."* The oil bar fades in under the ammo counter. |
| 0:33 | the horn, four Husks silhouetted | none — and now the lamp visibly fails against them, which is the lesson |

**One line of text and one HUD element fading in. That is the entire footprint of this design on the
game's best 33 seconds**, and the footprint is *additive*: the moment that already works now also
means something.

---

## 10. NAMES

The existing roster is short, plain, faintly archaic English: Wisp, Mote, Husk, Spitter, Warden,
Bulwark. Both new names sit in that register and both are ordinary words doing double duty.

- **Gloam** — twilight, the dark itself. A thing that *is* the dusk.
- **Snuffer** — the little bell-shaped cap on a stick that puts a candle out. A tool for ending light,
  walking around wearing one. Mabel Thorn would have owned three.

Rejected: Shroud (too generic), Vessel (too portentous), Reliquary (too many syllables at 320×240),
Pall — **kept, but for the region**, where "a pall" meaning a cloth thrown over a thing is exactly
right. Wickless (too cute).

---

## 11. OUT OF SCOPE FOR V1 — explicitly

Cut ruthlessly. These are **not in v1**, and no v1 code should be shaped around them except where
noted.

**Out — mechanics**

1. **A third damage type.** Two. Forever, in v1. `DMG_BURN` stays kinetic and the Emberlance stays a gun.
2. **Player resistances.** The player has HP. There is no "you take 30 % less radiant". Enemy attacks
   are all kinetic for damage purposes and the player's damage-direction indicator does not change.
3. **An enemy immune to both types.** Forbidden by the §5.3 law.
4. **A radiant primary weapon.** The lamp is the only radiant source in v1. *(v2 note below.)*
5. **Radiant headshots, radiant crits, radiant overpenetration.** No precision on the light hand, ever.
6. **A radiant affix pool on weapons.** GDD §3.3's 10 affixes stay kinetic. Charms carry the lamp.
7. **Radiant projectiles.** All three verbs are instantaneous volume tests. GDD §9.12 ("hitscan only")
   holds; the Emberlance stays the one projectile in the game.
8. **A third dynamic light.** §8.2.
9. **Oil as a tradeable/bankable resource.** It is a tank, not an inventory item. Flasks are items;
   oil is not.
10. **Affinity on props, terrain, or structures.** Lighting a sconce is a *verb*, not damage.
11. **Enemies that change affinity mid-fight** — except the Snuffer's shell, which is the one designed
    instance and uses an existing armour pool.
12. **A bestiary UI that shows multipliers.** §2.5: if the player needs a table, the art failed.

**Out — content**

13. **More than two new enemy classes.**
14. **A Pall boss.** A Pall is a place, not an encounter.
15. **N>3 sconce doors.** Three is the readable maximum at 320×240.
16. **Palls in the Deepshade.** The Deepshade is already permanent night; a Pall there is redundant.

**v2, with multiplayer**

17. The **WICK** role (§5.1) and the party utilities that make it real: throwing an oil flask to a
    teammate, reviving with a Wick charge, running the Wick Line ahead of the group.
18. **N=3 sconce doors designed for parties** rather than merely openable by them — sconces at 60 m+,
    with the Lantern Kit route removed. Only correct once a party is guaranteed.
19. **The Sconce** — a radiant *primary* weapon. Only interesting when a party can build around one
    player giving up their gun slot. In v1 it would just delete the stance rule.
20. **The Pall as a co-op space** — 4 players, overlapping cones, a real light-corridor discipline.
21. **Shared oil / a party lantern** whose radius covers the group.

Every one of 17–21 is additive. None requires a change to the v1 shapes in §5.4.

---

## 12. IMPLEMENTATION LEDGER

What a later wave must touch. Ownership per `BUILD_PLAN.md` rules; **this task owns none of it.**

| File | Change | Trap |
|---|---|---|
| `src/core/config.hml` | `g_ENEMY_GLOAM = 6`, `g_ENEMY_SNUFFER = 7`, `g_ENEMY_KIND_COUNT` 6 → **8**; oil, stance, phase-mult and verb constants | `g_ENEMY_KIND_COUNT` is asserted against table widths in ≥4 modules. Widen the tables in the same commit or the probes fail loudly — **which is correct behaviour, not a bug.** |
| `src/sim/combat.hml` | `DTYPE_*`, 3 new `DMG_*`, `DMG_KIND_COUNT` 6→9, `g_dtype`, `g_affinity`, `HM_RADIANT`/`HM_RESISTED`, the multiply in `combat_apply_damage`; widen `HB_R`/`HB_H` to 8; `combat_plate_hp` returns `SNUFFER_SHELL_HP` for the Snuffer | `combat_hb_ok()` asserts both hitbox arrays are exactly `g_ENEMY_KIND_COUNT` wide. `class_of` clamps unknown classes to Husk — **do not let a Gloam fall through to Husk affinity**, that would silently make it bullet-vulnerable. |
| `src/sim/ai.hml` | 2 class rows in `ai_kind_params`; `AI_GLOAM = 6`, `AI_SNUFFER = 7`, `AI_CLASS_COUNT` → 8; the Gloam's 12 m fog aura as an AI-owned scalar the snapshot exposes | The Gloam's aura is **not** a light and **not** a render decision. The sim owns the number; the renderer reads it from the snapshot. |
| `src/sim/director.hml` | `g_dir_w` re-normalised to 8 columns (§3.4), `g_dir_cost` → 8 entries | **Every tier row must still sum to exactly 100** — `director_table_ok` asserts it. Use §3.4's table verbatim; it is checked. |
| `src/sim/progression.hml` | 5 new `UNLOCK_*` ids 25–29, `UNLOCK_COUNT` 25→30, 5 new `g_unlock_level` / `g_unlock_name` entries, `g_xp_kill` → 8 entries, 3 new XP sources | The header's *"keep `g_unlock_level` sorted"* invariant breaks. See §14 #5 — both enumerators already do a full linear scan, so nothing functional depends on it; **the comment must be corrected, not the code bent.** Unlocks are derived from level and never stored, so this costs **zero save bytes.** |
| `src/sim/command.hml` | `BTN_LAMP = 4096`, `BTN_ALL` 4095 → **8191** | **Two more literals hide here:** `c.buttons = p_buttons & 4095` (line ~177) and `if (c.buttons < 0 \|\| c.buttons > 4095)` (line ~260). Miss either and the lamp button is silently dropped on every command — a bug that only shows up as "the lamp doesn't work sometimes". |
| `src/sim/lamp.hml` | **NEW.** Oil, stance, cooldowns, tank tier, the three verbs, `lamp_step`, `lamp_serialize` / `lamp_deserialize` / `lamp_hash` | Shape it like `progression.hml`: a flat state array, no closures, no per-entity objects (CLAUDE.md §7). Add its signatures to `ARCHITECTURE.md` §5.4. |
| `src/sim/sim.hml` | call `lamp_step` in the tick order; radiant verbs resolve in the existing damage stage | **The tick order is API** (CLAUDE.md §7). Adding a stage means amending `ARCHITECTURE.md` §4, in that file, deliberately. |
| `src/art/meshgen.hml` | 6 new meshes; widen the 6 per-class arrays to 8; `MESH_COUNT` 34 → 40; the shell lozenge as a separate mesh | Every class needs a **distinct protrusion axis** and there are only 6 axes in `g_hu_axis` (0..5) for 8 classes. The unbodied are exempt from the humanoid rule — a lozenge has no shoulders — so measure them against a different criterion and **say so in the probe**, rather than forcing a fake head:shoulder ratio. |
| `src/art/fxgen.hml` | 5 new atlas cells | 28 of 64 used; 33 free after. No atlas resize. |
| `src/art/palette.hml` | none | **No new colour is needed.** Every cue in §2 uses an existing entry. |
| `src/render/viewmodel.hml` | the lamp-stance pose: `g_VM_DOWN` 0.34 → 0.14 m and centre | The 156-px bright anchor at every pitch is a *verified, playtested* property. Do not break it to make room for a raised pose — add a pose, keep the anchor. |
| `src/game/save.hml` | one `lamp` block; `SAVE_VERSION` 1 → 2, `SAVE_MIN_VERSION` stays 1 | The save is a wire contract. Old saves must load with oil = full and tank tier derived from level. |
| HUD | oil bar + stance crosshair (§8.1) | Must pass `--scene hud_worst_case` against noon sky, snow, a muzzle flash and `CONCRETE_HI`. 1-px `UI_BLACK` shadow at (+1,+1), always. |

---

## 13. WHAT THIS TASK DID NOT DO — stated plainly

1. **No code was written.** No `.hml` file was created or modified. This was a design task and the
   brief says so: *"DESIGN ONLY — write no game code."*
2. **No probe was written and none was run.** There is nothing compiled to probe. The universal
   acceptance criteria in `BUILD_PLAN.md` §21 (compiled, headless, `exit(1)` on failure, asserting its
   own assertion count) are **not satisfied and cannot be** by a document.
3. **Every frame-time and boot-time figure in §8.3 and §8.4 is a prediction, not a measurement.**
   Specifically unmeasured: the cost of the affinity multiply in `combat_apply_damage`; the radiant
   volume tests; the `lamp_step` tick cost; the boot cost of 6 new meshes; and whether the Snuffer
   shell actually saves 76 triangles in a real frame (it depends on LOD selection at the distance the
   shell is visible, which I did not simulate).
4. **The triangle figures in §8.1 are arithmetic, not renders.** The −447 and −495 fog savings come
   from applying ART_BIBLE §2.6's own formula. No screenshot was taken and `tools/shot.hml` was not run
   — CLAUDE.md §2 requires stats with every screenshot, and I produced neither.
5. **The one-second readability criterion in §2.5 is unrun.** It requires a human playtester and 8
   stills that do not exist yet. It is written as a testable criterion for whoever builds the art.
6. **The oil economy in §1.6 is derived from `director.hml`'s own header** (≈110 bodies, ≈3:20) and
   from §3.4's composition table. It has not been simulated. The first playtest will move these
   numbers and that is expected — the point is that they are *specific* and in one place.
7. **`hemlockc --check` was not run on anything**, because nothing was written to check. RULE 0 *was*
   run: v2.9.1, prints 107 then 5120738502741017561. `./tools/ci_imports.sh` and `./tools/ci_unbox.sh`
   were run and pass (§15).
8. **I did not amend any existing doc.** Every contradiction in §14 is *reported*, per CLAUDE.md §10.5
   and the brief's explicit instruction to flag rather than silently override. Three of them
   (#1, #3, #5) require a deliberate ratification in `ARCHITECTURE.md` §0 before implementation
   starts. **I did not make those decisions.**

---

## 14. CONTRADICTIONS WITH EXISTING DOCS — flagged, not silently overridden

Two internal inconsistencies in the GDD were found by implementers precisely because they checked. In
that spirit:

**#1 — CLAUDE.md §9.6 / ART_BIBLE: the mandatory contact blob.** *"Every prop and every entity gets
its 2-triangle contact blob. No exceptions, not even in a test scene."* The unbodied classes need to
read as *not touching the ground*. **My resolution keeps the rule and inverts the card**: 2 triangles,
`ATLAS_FX`, additive, `NS_HALO` — a pool of light instead of a shadow. Same count, opposite meaning.
**But it moves those cards from `ATLAS_WORLD` (BLEND) to `ATLAS_FX` (ADD)**, which is a layer and
material change, and ART_BIBLE §2.3 says blend mode *is* the material model. **Needs ratification.** If
rejected, the fallback is to drop the card for three classes, which is a real exception to a rule
written as absolute — I do not recommend it, and I did not take it unilaterally.

**#2 — the task brief cites "ART_BIBLE §6" for the 320×240 readability rule.** §6 is FOG. The
readability rules are **§8.1** (RULE S1: identifiable at 12 px, detectable at 6 px; S2: persistent
emissive marker; S3: violet rim light) and **§8.2** (silhouette design). A documentation reference
error in the brief, not in the repo. I designed against §8.1/§8.2.

**#3 — ART_BIBLE §3.8's usage law vs. warm emissives on hostiles.** The law: violet and green *"appear
ONLY on things that are hostile, collectable, or player progression"*, and RULE S2 requires a
persistent `NS_CORE` marker on every hostile. My vulnerability windows put a **warm** (`EXPLO_HOT`,
`MUZZLE_MID`, `EMBER`) emissive on a hostile, and elsewhere the game's colour language is *warm =
yours, violet = theirs*. **My resolution: the violet marker is never replaced, only joined.** Violet is
identity; warm is a window; a hostile always carries its violet marker. That is an **amendment to
§3.8's usage law** — "warm emissive on a hostile is legal only as a vulnerability-window marker" —
and it must be ratified rather than assumed. If rejected, the windows must be signalled by *scale*
(the sac grows 2.2×) rather than hue, which is weaker at 12 px but still legible.

**#4 — GDD §2.2's Warden: "220 (+80 front plate, 75 % DR while intact)".** I add a second path into
that same 80-point pool: radiant, at ×2.50, **facing-independent** (light has no arc). **GDD §2.2's
sentence remains literally true for kinetic** — the arc, the 75 % DR and the 80-point pool are
untouched. But the Warden's *design intent* is "stop shooting the wall, go around" (GDD §2.2), and the
lamp offers a third answer: "or scour it off in 0.82 s". I believe that strengthens the Warden by
giving it two counters instead of one. **It is still a change to a shipped enemy's rules and the owner
should say yes or no on purpose.**

**#5 — `progression.hml`'s two invariants conflict.** The header says both *"Ids are API — append at
the end, never renumber"* **and** *"keep `g_unlock_level` sorted"*. Those cannot both hold when a new
unlock lands at level 3. **Resolution: keep id stability, drop sortedness.** `prog_unlock_count_at`
and `prog_unlock_at` already do a full linear scan over all `UNLOCK_COUNT` entries, so nothing
functional depends on sortedness; the only casualty is the header's claim that *"the run of unlocks at
any level is contiguous"*, which becomes false. The unlock card would list a level's unlocks in id
order rather than insertion order — cosmetic. **The comment must be corrected in the same commit.**
The alternative (parking all new unlocks at level ≥ 30) would put the shutter behind 30 levels and is
much worse.

**#6 — `g_ENEMY_KIND_COUNT` is load-bearing in more places than the GDD suggests.** Going 6 → 8
requires widening: `HB_R`, `HB_H` (`combat.hml`), `g_dir_cost` and `g_dir_w` (`director.hml`),
`g_xp_kill` (`progression.hml`), `ai_kind_params`' rows (`ai.hml`), and 6 arrays plus `MESH_COUNT` in
`meshgen.hml`. Three modules assert their own table widths against it, which means a partial change
**fails loudly** — that is good design working, not an obstacle. Not a contradiction; a cost, itemised
so nobody is surprised by it.

**#7 — `g_dir_w` rows must sum to 100 and two new columns force a re-normalisation of all five live
rows.** This changes the composition of every night hold in the game. It is the largest behavioural
ripple in this design and I have owned it with a concrete table (§3.4) whose rows I have summed by
hand rather than leaving it as "adjust to taste".

**#8 — `command.hml` masks `buttons` to `& 4095` in two places.** The wire field is already u32
(NETWORKING §11.2, `+14 u32 buttons`), so no bytes are added — but `command_set` masks and
`command_validate` rejects `> 4095`. A new bit needs **three** literals changed, not one. Not a
contradiction; a trap, named in §12 because it would present as an intermittent input bug.

**#9 — ART_BIBLE §2.7 says "affordable for up to 4 simultaneous dynamic lights"; BUDGET_ACTUAL
ratifies 2.** `config.hml` correctly implements 2. This design needs **0 new lights**, so it does not
depend on the resolution — but the stale "4" in ART_BIBLE §2.7 is exactly the kind of number that will
tempt a future implementer to add a light for the beam. Worth striking.

---

## 15. VERIFICATION

| Criterion | Result | Measured |
|---|---|---|
| RULE 0 — compiler verified | **PASS** | `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)`, prints `107` then `5120738502741017561` |
| `./tools/ci_imports.sh` (R1–R8) | **PASS** | `files=75 imports=541`, `RULES 8/8 checked`, `CI_IMPORTS PASS` |
| `./tools/ci_unbox.sh` | **PASS** | `targets=11 functions=367 scalars=69 boxed=0`, `CI_UNBOX PASS` |
| Compiled probe, headless, asserts its own count | **N/A — NOT DONE** | design task; no code written (§13.2) |
| Before/after measurement for every claim | **PARTIAL** | triangle and wire figures are arithmetic from documented formulas; **every timing figure is a prediction** (§13.3) |
| Triangle budget respected | **PASS (by arithmetic)** | +18 permanent HUD, +50 worst-case transient, against 2500 steady / 3500 clamp / 1806 measured-in-play |
| 2 dynamic lights respected | **PASS** | 0 new slots (§8.2) |
| `FOG_FAR` ≤ 72 m respected | **PASS** | the design only ever pulls it *down* |
| Procedural art only | **PASS** | 6 meshes and 5 FX cells, all generated; no PNG, no OBJ |
| 16-minute day respected | **PASS** | §1.7 indexes `daycycle.hml`'s existing 4 phases; ARCHITECTURE D6 stands |
| Measured TTK / weapon tables respected | **PASS** | kinetic is ×1.00 on all six existing classes; GDD §2.4 is unamended (§1.2) |
| Design anchors pinned with literals | **PASS** | 8×2 affinity table, 6×8 director table summed by hand, 5 unlock rows with levels, oil economy derived from `director.hml`'s own header |
| Contradictions flagged, not overridden | **PASS** | 9 in §14; 3 need ratification and I did not grant it |
