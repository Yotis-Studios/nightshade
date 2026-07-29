# NIGHTSHADE — MULTIPLAYER TOPOLOGY (v2)

**Status:** owner's direction, recorded. v1 ships single-player; **this shapes v1 decisions** — in
particular how world state, the lantern grid and building are stored, so it is worth settling early.

---

## The model: a world is a settlement, and worlds are seeded

> Owner: *"a world focuses around a settlement in some seed and you can teleport to other worlds?
> that way things feel infinite without connecting them and you can limit player concurrency"*

**This is what the architecture already is.** A shard is `sim(seed)`: deterministic, headless, zero
SDL, behind an enforced import wall. That was not designed toward this outcome — it fell out of the
sim/render split and the determinism requirement, and it means the server work is mostly *hosting*
rather than *rewriting*.

### Why it is the right model

| | Why it matters |
|---|---|
| **Worlds cost ~nothing to store** | The world is deterministic from a seed, so a shard is `seed + a delta log` (lanterns placed, buildings raised, POIs cleared). Terrain is never persisted. For F2P, where margins decide survival, this is the difference between viable and not. |
| **Bounded concurrency is a FEATURE** | 30 players across infinite terrain feels dead. 30 around one settlement feels like a town. Centring a world on a settlement concentrates players where the social loop lives. |
| **Worlds become meaningfully different** | With the lit-city tech tree (`DIRECTION.md` §3), a veteran world has a powered city manufacturing rifles; a fresh seed is dark and you are on a bolt-action. That is a real reason to travel and a real reason to invest in a home world. |
| **Cheap to scale horizontally** | Many small deterministic sims pack densely onto one host. No cross-shard consistency problem, because worlds are not connected. |

---

## THE KEY DECISION — the persistence split

Everything else follows from this:

- **The CHARACTER travels.** Level, spells, recipes, cosmetics. Yours, across all worlds.
- **The WORLD is collective.** The lantern grid, the town, how much of the night is pushed back.
  Shared and persistent per seed.

That split turns a world into a **community project** rather than a lobby. It is the Animal Crossing
pillar with other people in it — *the town grows because you all came back* — and it makes the first
player on a fresh seed the pioneer who lit it, which is a good story to be in.

## Travel should be diegetic

**Wick Lines already exist** in the GDD: the lit roads between Lantern Posts. Travel between
settlements **along the network**, not through a menu. Then fast travel is lore, and an unlit route is
a reason to go light it.

---

## PROBLEMS TO SOLVE BEFORE BUILDING, not after

### 1. Most worlds will be empty
Infinite seeds means infinite ghost towns. Matchmaking must **concentrate** players — featured
worlds, or new shards spun up only when population demands — rather than letting them scatter. A
settlement model that spreads players thin defeats its own purpose.

### 2. Twinking
If a powered city gates good weapons, a level-1 character hops to a veteran world and leaves with an
AR. Options: gate purchases on character progression **as well as** city power; make ammunition
non-transferable between worlds; or lean in and treat it as intended generosity between players.
**Decide deliberately rather than discover it.**

### 3. Griefing a collective world
If world state is shared and players can build, the grid is grief-able. Simplest robust answer:
**player-placed lanterns cannot be destroyed by players — only by the dark.** Let the antagonist be
the antagonist.

### 4. Do worlds become "solved"?
If light is permanent and free, every world trends toward fully lit and the game ends. See ENTROPY
below — this is the most important open question in this document.

---

## STRONG IDEAS ARISING (orchestrator's, for the owner to accept or reject)

### A. ENTROPY — the dark grows back
**Unmaintained lanterns dim over time.** This does an unusual amount of work at once:

- Returning to a world **matters** — the Animal Crossing daily-loop hook, mechanically grounded.
- Worlds never become trivially solved, so there is always something to do.
- Veterans get **maintenance** work that is not just combat.
- It **explains the premise**: the lamps went out on a Tuesday *because nobody tended them.* The
  player is not fixing a disaster, they are resuming a duty that lapsed.
- It gives lapsed worlds a reason to be re-lit rather than abandoned.

Tuning is delicate: too fast and it is a chore, too slow and it is decoration. Likely per-lantern
decay measured in real days, with the town core protected so nobody logs in to a dead home.

### B. THE SHARED NIGHT HOLD — the multiplayer setpiece
The night hold is already the game's CoD engine: dusk horn, three waves, ~2:40 (owner chose dense
over long). In a settlement world it should be **one shared siege**, not per-player instances.

Twelve lamplighters defending a town's grid against the dark, with the lit area shrinking as posts
are overrun, is the natural marriage of the night-hold design and the settlement model — and it is
the moment the three pillars fuse: CoD combat, a Minecraft world-state change at stake, and an
Animal Crossing town worth defending. It needs no new systems, only shared scope.

### C. A DANGER GRADIENT PER WORLD, not just per region
A young dark world is genuinely more dangerous than a lit one. So veterans have a reason to go
*back* into darkness on purpose — an endgame that costs nothing to build, because it is the same
content at a different grid state.

---

## OPEN QUESTIONS FOR THE OWNER
1. **Concurrency cap per world?** It decides the feel: ~8 reads as co-op, ~24 as a small town,
   ~60+ as an MMO hub. It also sets the server bill.
2. **Entropy: yes or no?** (§A). The single biggest lever on whether worlds stay alive.
3. **Shared night hold, or per-player?** (§B). Shared is far stronger and needs scope, not systems.
4. **Twinking: gate, block, or embrace?** (§2)
5. Is there a **home world** concept — one seed a character is bound to, with others visitable?

---

# ENTROPY: ACCEPTED, with the owner's gradient

> Owner: *"maybe the settlement as it grows can be safe and maintenance costs get cheaper closer and
> durability higher as you get closer to the settlement"*

That refinement is what makes entropy **humane instead of a chore**, and it solves the "nobody should
log in to a dead home" problem structurally rather than by special-casing the town.

It also creates the thing the world was missing: **a frontier.** A legible spatial structure of
safe core → maintained ring → frontier → dark. The frontier is where the game happens, and it MOVES
as the settlement grows.

## THE UNIFICATION — one field drives four systems

Call it **CIVIC LIGHT**: a scalar field over the world, highest at the settlement core, falling off
with distance and rising with the density of maintained lanterns around it.

| System | Driven by civic light how |
|---|---|
| **Entropy rate** | Lantern decay is inversely proportional. Near-zero at the core, fast at the frontier. |
| **Durability** | A lantern's resistance to the dark scales with the civic light around it. |
| **Danger** | Enemy tier and density scale inversely. Dark IS dangerous — no separate difficulty dial. |
| **Settlement tier** | Total integrated civic light drives village → town → city. |
| **Industry** | City tier plus core civic light gates manufactured weapons and ammunition (`DIRECTION.md` §3). |

**Why this is worth doing as one field rather than five systems:** the player has exactly one verb —
light and maintain lanterns — and that verb raises one number, and that number *is* progression,
safety, difficulty and the tech tree. Nothing needs to be explained to the player in a tutorial
because it is all spatially visible: you can see how far your influence reaches.

It also means **expansion has a real cost curve.** Pushing the frontier out is expensive to maintain
until the settlement grows enough to support it, which paces expansion naturally instead of with
artificial gates.

And it gives the danger gradient (§C) for free: a young world has a small bright core and a vast
dark everywhere, and a mature world has to be *sought out* for danger.
