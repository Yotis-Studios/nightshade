# NIGHTSHADE — DIRECTION NOTES

Design decisions from the project owner, captured verbatim-in-substance so they are not lost
between sessions. **These are directives, not proposals.** Where they contradict
`docs/recon/GAME_DESIGN.md`, these win and the GDD should be amended.

---

## 1. This is not strictly a Call of Duty game

The original brief leaned heavily CoD because that is what the owner had seen work well. **The FPS
element stays.** What was borrowed and is worth keeping is the *feel*: gunfeel, TTK, HUD legibility,
hit feedback, the 30-second loop. What was borrowed and is NOT wanted is the modern-military
*fiction*.

The measured weapon tables, recoil patterns and the §2.5 feedback contract are the expensive part and
they stay. The fiction around them changes freely.

## 2. Magic is a SPELL SCHOOL, not just a damage type

The owner wants the character to **learn** abilities: **healing, fire blasts, cloaking**, and more.
This is broader than the resistance system originally briefed.

The lantern stays and is always in hand. It is the anchor of the magic side — and note it is already
a genuine light source in every frame, rendered in view space with a constant bright core, so the
magic identity is already visually established.

**Consolidation opportunity:** the **Emberlance** is currently a *gun* that does 60 impact + 12/s
burn over 5 s with a 3.5 m AoE. That is a fire blast. It should probably move to the spell side,
which frees the kinetic arsenal to be purely primitive and merges two systems into one.

**OPEN QUESTION for the owner — this one changes the viewmodel build:** are spells and guns held
**simultaneously** (lantern-hand / gun-hand, no swap, very readable at 320x240, more distinctive) or
**swapped** like weapon slots (cheaper in viewmodel triangles, one hand on screen)?

## 3. Kinetic weapons lean PRIMITIVE — and manufactured ones need a lit city

The owner's constraint, and it is the keystone of the whole design:

> *"a sub machine gun and assault rifle are still cool potential weapons but youd have to have like a
> well lit city manufacturing them and the ammunition"*

### THE LOOP THIS CREATES — lighting the world IS the weapon tech tree

The player's core action, pushing the dark back one lantern at a time, is what keeps the city's lights
on, which is what lets it manufacture rifles and ammunition. The causal chain runs straight from the
moment-to-moment loop into progression:

| Tier | Source | Weapons | Character |
|---|---|---|---|
| **Village** | crafted, or traded with villagers | bolt-action rifle, revolver, pump shotgun, crude pipe-SMG | hand-made, forgiving on ammo, primitive |
| **City** | manufactured, only while the city has power | Sparrow AR, Tinker SMG, the LMG | precision-made, ammo-hungry, a privilege |

**Ammunition is the real currency, not the gun.** That solves "why would a player ever choose the
weaker weapon" without leaning entirely on a resistance table: sometimes you carry the bolt-action
because city ammo is precious. That is a choice, not a punishment.

The **Wick Lines and Lantern Posts** already in the GDD are the grid. Light more of it and the city's
output rises. This is world state the player permanently changes — the Minecraft pillar — and it is
now *visible in the shop inventory*, which is the Animal Crossing pillar.

### Specific weapons requested
- **Bolt-action rifle** — explicitly wanted. Note **Longshadow is NOT this**: at 75 RPM with an
  8-round magazine it is a semi-auto marksman rifle. A true bolt-action wants a manual cycle the
  player FEELS (~40-50 RPM), a 5-round internal magazine, stripper-clip reloads, and enough damage
  that one good shot matters. The rhythm is the point.
- **Machine gun** — the natural top of the crafting/manufacturing ladder. Rare, heavy, poor while
  moving, devastating while braced. Pairs with party composition: someone holds a lane while the
  caster does the clever thing.

## 4. Party composition matters, but v1 is single-player

The owner wants affinities where "good party composition helps you fight them and explore certain
areas". Multiplayer is **v2** — the architecture supports it already (deterministic headless sim,
authoritative-server shape, gn.hml behind an import wall) but v1 ships solo.

**Therefore every system here must be satisfying solo and BETTER in a party. Never solo-hostile.**

## 5. Constraints that do not move

2500 triangles, 60 fps, 2 dynamic lights, no z-buffer, procedural art only (no asset files), a
16-minute day, and the measured TTK/weapon/recoil tables. **A design that breaks the budget is not a
design.** Flag contradictions with the GDD rather than silently overriding it — two internal
inconsistencies (the XP cumulative column, the night-hold duration) were caught precisely because
implementers checked instead of assuming.

---

## 6. Villagers / NPCs — approved direction

The owner endorsed this shape. `GAME_DESIGN §5` already names five villagers with a personality line
each; this is how they should FUNCTION.

**They are where the Animal Crossing pillar actually lives.** Four principles:

1. **NPCs are the crafting and trading interface, not menus.** You get the bolt-action *from someone*,
   and that person remembers you. This matters doubly given `DIRECTION.md` §3 — village-tier weapons
   are crafted or traded, so the arsenal is literally delivered through relationships.
2. **They arrive as the settlement grows.** A new villager appearing is the most legible possible
   signal that your lantern work mattered — far better than a number going up. Ties settlement tier
   (see `SETTLEMENT.md`) directly to something you can greet.
3. **They react to the grid.** A villager who mentions the east road has gone dark again is doing
   tutorial, quest-giving and world-state readout in a single line of dialogue. With ENTROPY
   accepted, this is how a player learns their maintenance is slipping without a UI nag.
4. **Named, few and persistent** beats many and generic — especially under entropy, where the
   emotional hook is *"the town survived because you came back."*

### THE BUDGET PROBLEM, and it is the real constraint on settlements
Measured by `benchframe.hml`: **an NPC mesh is 220 triangles.** Ten villagers is 2200 — the entire
current budget, for people standing still. This, not building geometry, is what stands between us
and a town that feels inhabited.

**NPC LOD is the unlock** (approved): full mesh up close, a simplified silhouette mid-range, a
billboard beyond that. Target roughly **40 triangles at conversational distance**, at which point a
town of 30 becomes affordable. Silhouette must still read instantly at 320x240 per `ART_BIBLE` §6 —
a villager the player cannot tell from a Husk at 20 m is a bug, not a saving.
