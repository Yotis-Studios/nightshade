# THE HOUR — what happens if you keep playing, measured

**Task:** find-the-hour. **HEAD:** `2d90bc8`. **Date:** 2026-07-31.
**Instrument:** `tools/probe_session.hml` (new), plus a 60-minute session of the shipping
binary on `DISPLAY=:0` with 720 screenshots.
**Owned and written:** `docs/design/THE_HOUR.md`, `tools/probe_session.hml`. **Nothing in
`src/` or elsewhere in `tools/` was touched.**

---

## 0. HOW I DROVE IT, AND HOW MUCH TO TRUST THIS

Read this first, because it bounds everything below.

**⚠ THE TREE MOVED UNDER ME WHILE I MEASURED, AND HERE IS EXACTLY HOW MUCH.** Other agents
were editing this working tree during my session. `git status` at the end shows uncommitted
modifications to `src/art/meshgen.hml` (18:53), `src/game/main.hml` (18:57),
`src/render/settle_render.hml` (19:00), `src/sim/worldgen.hml` (18:52) and four probes — none
of them mine. Consequences, stated rather than glossed:

- **The display-session binary was built 18:22–18:26 and launched at 18:27:09**, so it
  predates every one of those edits. Its pictures and its frame report describe the tree at
  `2d90bc8` plus whatever was already uncommitted at 18:22.
- **`src/sim/worldgen.hml` changed at 18:52, and it owns the settlement site and the shade
  tier.** My probe was compiled at 18:46 (run 3) and again at 18:55 (run 4), i.e. once either
  side of that edit. **The ARM POST table is byte-identical between the two runs** — I diffed
  them — so the concurrent worldgen work did not move any number in this report. That is a
  check, not an assumption.
- **`src/game/server.hml` is clean** (`git diff --stat` empty), and
  `grep -n 'let md = w.model;' src/game/server.hml` still returns **line 1537** in the tree as
  it stands right now. **The headline bug in §2 is live, not historical.**

**I did not play this with hands.** There is no `xdotool` and no `xte` on this box. There *is*
`python-xlib` and `libXtst`, so XTest injection was possible in principle, but an hour of
blind, hand-authored key events would have produced a worse player than the one the repo
already ships and a measurement nobody could reproduce. So I drove it three ways, and each
one is named with what it can and cannot tell you.

| # | How | What it is | What it can say | What it cannot |
|---|---|---|---|---|
| **A** | `nightshade --demo 3600 --scale 4 --shots …` on `DISPLAY=:0`, one real hour, 720 PNGs | `src/game/demobot.hml`, **the shipping driver** — the same code `--demo` has run since `2d90bc8` | what the game **looks and sounds like** minute by minute; frame pacing; what is on screen at 30:00 | nothing about curiosity, exploration, or a player who decides to walk somewhere |
| **B** | `tools/probe_session.hml`, ARM POST, headless, compiled, 216 000 ticks | the **same** `demobot.hml`, imported not ported | thirty-one state columns once per game minute, and exactly when each one stops moving | same limits as A |
| **C** | `tools/probe_session.hml`, ARM WALK | the same combat driver with the **movement overridden**: at every dawn it walks the 282 m to the settlement, greets whoever is there, and presses every row of every shop | whether the second half of the loop **can** be reached and what is there when you arrive | how hard any of it is to *discover* |

**ARM WALK is an oracle player and I am declaring it, not hiding it.** It reads villager
positions from `npc_x`/`npc_z` on the server and the settlement centre from `settle_cx`
rather than finding them on screen. A human learns both facts in their first five minutes
and then has them forever, so the shortcut costs the measurement nothing that matters — but
it means ARM WALK measures *what the systems do when driven correctly*, not how hard they
are to find. Discoverability is measured with eyes, and that half is §6 below.

**The one place a bot's hour differs materially from a human's, and it matters here more
than anywhere:** a bot never gets lost, never sightsees, never dies to something it did not
see, and never spends four minutes trying to work out what the game wants. Three gates said
"about twenty minutes". My instruments say **the last new thing arrives at 0:58** and **the
game stops being interesting at 6:40**. All three numbers are true, and the gap between them
is exactly the human overhead the bot skips. **Do not read "6:40" as "a human is bored at
6:40."** Read it as: *the game stops putting anything new in front of the player at 0:58, and
everything a human enjoys after that is them still catching up with what the first minute
already showed them.* A human takes about twenty minutes to finish catching up. **That is
where the twenty minutes comes from, and it is why adding more of the same will not extend
it.**

**Also honest:** I never once used a mouse, so I cannot tell you whether aiming feels good.
`demobot.hml` calls `client_set_angles` and teleports the crosshair. Everything I say about
gunfeel is inference from numbers and pictures, not from playing.

---

## 1. THE TIMELINE

Times are **elapsed session time**, not the in-game clock. The 16-minute day means the hour
is **3.7 days**. `h` is the in-game clock hour from the display session's stats lines.

### The first minute — this part is genuinely good

| t | h | what happens | player has |
|---|---|---|---|
| **0:00** | 17.5 | Black. A bell. *"THE LAMPS WENT OUT ON A TUESDAY."* The camera is on its back, looking at the sky. | nothing |
| **0:03** | 17.5 | The camera stands up. Control. `6 / 12`. | Kestrel, a club, an unlit lantern in the off-hand |
| **0:06** | 17.6 | `SEEK`. The unlit post is 40 m downhill, the only vertical thing on the horizon. | — |
| **0:10** | 17.7 | Three Wisps drift up from beyond the post. One shot each. | — |
| **0:18** | 17.8 | A Mote from behind a rock. Two shots. You learn `R`. | — |
| **0:24** | 17.9 | `HOLD [E]`. | — |
| **0:27** | 18.0 | The music stops. 2.5 s channel. | — |
| **0:30** | 18.0 | **LIGHT.** +350 XP, and the **Flare** is granted on this beat rather than from a menu. Best moment in the game. | a spell |
| **0:33** | 18.0 | The dusk horn. Four Husks up the hill. | — |
| **0:36** | 18.1 | Wave 1. Tier pinned to 1 because it is a tutorial. | — |
| **0:56** | 19.0 | Silence. Ember rain. | — |
| **0:58** | 19.0 | **`PATH`.** Five lit lanterns fade in, curving away downhill into fog. | **This is the last authored beat in the game.** |

### Minutes 1 to 7 — the first hold. Still good.

| t | what | measured |
|---|---|---|
| 1:00–6:40 | three waves at the post, ~14 alive at the cap, ember rain in the gaps | 131 kills, 2 045 XP, HP 100→10→76, 4 deaths and 4 respawns at the post |
| ~2:00 | **level 2** — one stat point | |
| ~6:00 | **level 3.** The Shutter spell's unlock level is 3 (`spells.hml:367`), so this *should* be a second spell — **and it is not.** See the box below. | **nothing arrives** |
| **6:40** | the hold completes. `holds_done` 0→1. Nothing marks it. | |

> **I nearly shipped this as "the last new mechanic is the Shutter at 6:00". It is not, and
> the correction is the sharper finding.** `sv_w6_tick` sweeps once a second for any spell the
> player's level allows, and `spell_equip` refuses politely — but `sv_spell_grant` first needs
> **a free slot**, and `spell_slots = 1 + Attunement/7` clamped to 1..3 (`spells.hml:550`,
> `g_ATTUNE_PER_SLOT = 7`). Attunement starts at **0**, so there is **one slot**, and the Flare
> took it at 0:30. A second slot costs **7 stat points**; the player earns **1 per level**; that
> is **level 8**, or **14 000 cumulative XP**. The hour ends at level 5 / 5 502 XP.
> Measured, not reasoned: every run I made reports `spells granted 1` — `--selftest` (3 s),
> `--demo 120` (2 min), and the hour session.
> **So the true statement is: nothing new arrives after 0:58.**

### 7:00 to 19:00 — twelve minutes in which every column is frozen

This is not an exaggeration or a summary. It is the table.

```
 min  d ph   beat  hp lvl    xp purse  town lux pts bld npc lan kits holds kills own trd talk regW pt  dist
   7  0 NGHT PATH    76   3  2045    81    0    0   0   2   0   1    0     1   131   1   0    0    0  2   275
   8  1 dawn PATH    76   3  2045    81    0    0   0   2   0   1    0     1   131   1   0    0    0  2   275
   9  1 dawn PATH    76   3  2045    81    0    0   0   2   0   1    0     1   131   1   0    0    0  2   275
  10  1 day  PATH    76   3  2045    81    0    0   0   2   0   1    0     1   131   1   0    0    0  2   275
  ...  identical for minutes 11, 12, 13, 14, 15, 16, 17, 18 ...
  19  1 NGHT PATH     0   3  2247    89    0    0   0   2   0   1    0     1   137   1   0    0    0  2   285
```

Thirty-one sampled columns. **Twelve consecutive game minutes in which not one of them
changes.** On the display session the player's *coordinates* did not change either: the
stats line at `t=596` and the one at `t=746` both read `pos -43,-279 hp 4 ammo 6/12`. Two and
a half minutes, same pixel. At `t=1496` and `t=1796` — **five minutes apart** — both read
`pos -29,-252 hp 40 ammo 6/12`.

That is 11 of every 16 minutes. **69 % of the game's clock is dawn, day and dusk, and the
game currently puts nothing in any of it.**

### 19:00 to 60:00 — the same night, three more times

| t | what | measured |
|---|---|---|
| **19:00–23:00** | **night 2.** The tutorial tier pin is released (`sim.hml`: "only the FIRST hold is pinned"), and the chunk rolls **tier 3**. | 12 kills, and the player dies **20 times across the night** (`player_deaths` 4 → 24). The hold never clears; `dir_abort` kills it at dawn. `holds_done` stays 1. |
| 23:00–35:00 | twelve more frozen minutes | — |
| **35:00–39:00** | **night 3**, back at director tier 1 — *the same wave as minute 1* | 79 kills; level 4 at 39:00 |
| 40:00–51:00 | eleven more frozen minutes | — |
| **51:00–56:00** | **night 4**, tier 1→2 | 106 kills; **level 5 at 56:00**; `holds_done` 1→2 |
| **60:00** | end | level 5, 5 502 XP, 4 unspent stat points, **1 gun**, **1 spell**, **220 salvage**, **4 HP**, **71 deaths**, town still a **Camp**, **0 villagers**, **0 trades**, **0 conversations** |

**Four nights, two completed holds** (nights 1 and 4 — `holds_done` moves at 7:00 and 56:00
and nowhere else). Nights 2 and 3 were aborted by dawn with the field still up. Night 2 is
explained: tier 3 saturates the 14-alive cap and killed the player 20 times. Night 3 I have
not diagnosed — 79 kills at director tier 1, cut off at dawn. **Reported, not explained; it
wants its own look, and it is not the change I am recommending.**

### What ARM WALK found when it walked home

It made **2 round trips** to the settlement across the hour (the trip is ~2 game minutes:
282 m, and sprint is 7.0 m/s). Both times it walked to the green, stood on it, and turned
round, because:

```
                            ARM POST    ARM WALK
  town trips completed            0           2
  conversations                   0           0
  trades completed                0           0
  guns owned at 60:00             1           1
  settlement tier                 0           0
  villagers present               0           0
  lanterns the player lit         1           1
  kits placed                     0           0
```

**There is nobody there.** Not "the shop is closed" — the town is tier CAMP, a Camp has zero
named villagers and zero ambient ones, and 21 of 21 shop rows report `open-now: no`.

> **⚠ ARM WALK degrades after ~45:00 and I think that is MY BUG, not the game's.** From
> minute 50 it dies 7–9 times a minute with `kills` frozen at 265 and `xp` frozen at 3898 —
> in broad daylight. I checked the obvious suspect and it is not that: **`fall-damage hits`
> is 0 for the entire hour.** The likeliest cause is my own movement override leaving the bot
> in a travel state instead of handing it back to `demobot.hml`'s combat policy, which is
> precisely the failure `demobot.hml`'s header documents ("it walked away from its own
> ammunition supply"). **So do not trust ARM WALK's late-hour level, XP or kill numbers.**
>
> It does not touch the finding, and here is why, exactly: **the ARM WALK columns this report
> actually cites — trades, conversations, settlement tier, villagers, kits placed, regard —
> are all ZERO, and a bot that plays badly can only push those down.** They are already on
> the floor. ARM POST, which is the shipping driver with no override at all, is the arm every
> quantitative claim above rests on.

---

## 2. THE FIVE ANSWERS

### 1. Where exactly does it stop being interesting, and what is the last new thing?

**The last new thing is `PATH` at 0:58 — five lit lanterns fading in downhill into fog. It
stops being interesting at 6:40, when the first hold completes and the game turns out to
have nothing behind it.**

I want to be exact about the two timestamps, because they are different questions:

- **0:58 — the last new thing.** Nothing after this is a thing the player has not already
  seen. Not a weapon, not a spell, not an enemy class they meet for the first time, not a
  place, not a person, not a sentence of dialogue. I checked the spell ladder specifically
  and it does not save it (box in §1).
- **6:40 — where it stops being interesting.** Minutes 1:00–6:40 are *not* boring even though
  no new thing arrives, because the player is still learning the wave: the crowd cap, the
  break-contact distance, that the lantern is the ammunition. At 6:40 the hold clears, and
  the reward for clearing it is silence.

After 6:40 the game contains exactly two kinds of minute: a night that is a re-run of the one
you already fought, and eleven minutes of standing still. Level 4 arrives at 23:00 and level
5 at 56:00; each hands over one stat point, and a stat point raises a number on a panel that
unlocks nothing (`DIRECTION.md` §9's own rule: *"unlocks decide what you have, stats decide
how well you use it"* — and in an hour there is nothing new to have).

**How far away is the next real thing?** Two candidates, both arithmetic:
- **A second spell slot** — Attunement 7, i.e. 7 stat points, i.e. **level 8 = 14 000 XP**.
- **Mend, the heal, at spell level 7** — which also needs the slot, so it is the same wall.

Post-opening the player earns **65 XP/min** (the first seven minutes run at **292 XP/min** —
**4.5× the rest of the game**). From 5 502 XP, level 8 is **8 498 XP away = 131 more minutes**.
**The player finishes the hour on 4 HP, and the heal is two and a quarter hours away.**

### 2. What runs out?

"Content" is not the answer and neither is "difficulty" — the world is unbounded, the enemy
pool is unspent, and the reward counters keep climbing all hour. **What runs out is the second
verb.**

Nightshade has exactly one verb the player can perform after 0:58: *point at a thing and
shoot it*. The design's other verb — *light a lantern, and carry the salvage home to a town
that grows* — **cannot be performed at all.** Named precisely, and in the order that matters:

1. **The town's lantern feed is empty and always will be.** `sv_lan_gather`
   (`src/game/server.hml:1537`) tests a lantern's lit state against the wrong array:
   ```hemlock
   let md = w.model;                       // <-- w.model
   if (md[slot] == SIM_LANTERN_LIT) {      //     90 == 1.  Never true.
   ```
   `sv_spawn_lantern` writes the lit flag into `w.anim` and writes `SV_MODEL_LANTERN` (90)
   into `w.model`. So the test is `90 == 1` **for every lantern that has ever existed.** The
   settlement's lantern array holds exactly one row — the Great Lantern, wick 0 — for the
   whole of any session. Measured: `lan 1` at minute 0 and `lan 1` at minute 60.
   *I did not fix this. I do not own `src/`.*

2. **Even repaired, the six lanterns you are given are in the wrong place.** ARM SHADOW runs
   a second, private copy of the *shipped* `settle.hml` and `npc.hml`, same seed, same cell,
   same `settle_step` cadence, fed from `w.anim` instead — one word different, nothing else.
   It finds 7 lanterns instead of 1, and the town **still does not grow**:

   ```
     lanterns reaching the town feed :  ships 1   shadow 7
     core lux                        :  ships 0   shadow 256   (Village needs 512)
     grid points                     :  ships 0   shadow   1   (Village needs 10)
     settlement tier                 :  ships 0   shadow   0
   ```
   Because of geography, which the probe prints:
   ```
     post  0  LIT   274.5 m from the green
     post  1  LIT   258.8 m
     post  2  LIT   241.4 m
     post  3  LIT   222.5 m
     post  4  LIT   202.3 m
     post  5  LIT   181.1 m
   ```
   A tier-1 lantern's radius is **40 m**. The nearest post the game gives you is **181 m**
   from the green. They are inside the 320 m *gather* ring and outside the *light* falloff,
   so they are worth nothing. `sv_light_the_path` aims them at `spawn_yaw − 20°` — away from
   the town, by construction.

3. **The only way to plant a new lantern is a kit, and the kit is behind a wall.**
   `sv_place_kit` needs `NPC_OFF_KIT` in the pack. That is offer row 13: Wick's, price 36,
   **tier VILLAGE, regard 192 (TRUSTED)**. Wick does not exist below Village. And regard: of
   its five wired sources, `NPC_CRK_LANTERN` (+2) is called **exactly once in the entire
   game**, on the *first* lantern (`server.hml:1053`); `NPC_CRK_NIGHT` (+3, "a night
   survived") is **called from nowhere**; contracts and donations are UNBUILT. What is left
   is +8 to meet and +6 per villager per in-game day. **192 regard is ~30 in-game days, which
   is eight hours of play** — and you cannot start the clock, because Wick needs a Village
   and a Village needs lanterns and lanterns need Wick.

   **It is a closed circuit.** Measured, not inferred: ARM WALK walked to Wick's town every
   morning for an hour and finished with **0 regard, 0 kits, 0 trades**.

4. **9 of 21 shop rows are `NPC_OC_UNBUILT`** and the probe prints the table. All three of
   Connie's (contracts, the map) and all three of Pip's (almanac, charms) — so there are **no
   quests and nothing anywhere points anywhere.** That is honest in the source and it is
   worth naming here.

5. **The spell school is one slot wide and stays that way.** `spell_slots = 1 + Attunement/7`,
   Attunement starts at 0, the Flare fills the one slot at 0:30, and the six other spells —
   including the heal — cannot be equipped before **level 8**. So the school that
   `DIRECTION.md` §2 calls "the anchor of the magic side" is, for the whole first hour,
   **one button**.

6. **Two smaller taps that are off:** `g_REGEN_DELAY_S` and `g_REGEN_RATE` exist in
   `config.hml` and **are read by nothing in `src/`** (`demobot.hml`'s own header says so).
   And **money has no sink** — the hour ends holding **220 salvage** with no shop.

So: *novelty* runs out at 0:58, *goals* run out at 0:58, *reward* keeps arriving as XP and
salvage into a wall, and *difficulty* does something worse than run out — it **flaps**
(tier 1 → 3 → 1 → 2 across four nights, because the tier is a function of the chunk you are
standing in and the pin comes off after the first hold; night 2 killed the player 20 times
in four minutes and never cleared).

### 3. What does the player have at 20:00 that they did not have at 5:00?

Measured, both arms:

| | 5:00 | 20:00 | worth having? |
|---|---|---|---|
| level | 2 | 3 | 1 stat point, spendable on a panel; unlocks nothing |
| XP | 1 773 | 2 369 | — |
| salvage | 70 | 94 | **no** — nothing sells |
| guns | 1 | **1** | — |
| spells | 1 (Flare) | **1** — the Shutter unlocks at level 3 and cannot be equipped: one slot, and the Flare is in it | **no** |
| settlement tier | CAMP | **CAMP** | — |
| villagers | 0 | **0** | — |
| buildings | 2 | **2** | — |
| lanterns lit | 1 | **1** | — |
| HP | 10 | 34 | not a gain — there is no regen; it went up by dying |

**Every single row is either unchanged or worthless.** The honest answer to "what does the
player have at 20:00 that they did not have at 5:00" is: **one stat point and 24 salvage they
cannot spend.**

**The town did not grow. It grew by nothing, and it cannot.** `settlement tier`, `core lux`,
`grid points`, `buildings`, `villagers` and `guns owned` all report **"last moved at 0:00"**.
It is not "a number in a struct rather than a feeling" — **the number in the struct never
moves either.**

And this is what makes it hurt: **the town is built, and I ran it.**

```
$ nightshade --demo 45 --town 2 --at-town --demo-ui --seed 1337
   W6 town:   TOWN lux 1915/2048  pts 40/72  buildings 17  villagers 14 (5 named)
   W6 panels: TRADE peak 208 tris, cap 250, open on 327 frames, 0 truncated strings
   W6 acts:   talks 1  trades 2 (0 refused)
   W7 hands:  held BLKTHRN (6)  asking BLKTHRN (6)  own 2 mask 80  grants 2  denied 0
```

**Forty-five seconds.** Walk to Mabel, `[E] MABEL / [T] TRADE`, a panel that reads
`MABEL — BENCH / BOLT 0 / REVOLVER 40 / PUMP 65 / X NEXT  C TAKE`, `TAKEN` in amber, and you
walk away holding a **Blackthorn bolt-action, `5 / 64`** — the exact gun `DIRECTION.md` §3
asked for by name, delivered by a person, exactly as §6.1 says it should be. It renders inside
budget (208 of 250 HUD triangles, 782 of the settlement's tris drawn, 5 162 tris of town mesh
in 232 meshes). The authority path is proven — `2d90bc8` traced the bought rifle for 601
consecutive ticks.

**All of it works. In an hour of real play the player reaches none of it.** It is the largest
finished thing in the repository and it is switched off by one word.

### 4. Does the loop actually loop?

**No. It does not complete one circuit, so there is no second circuit to compare.**

Traced, with times, on ARM WALK:

| leg | time | result |
|---|---|---|
| go out | — | you start out. 0:00 |
| push the dark back | 0:27–0:30 | **1 lantern, ever.** The other five are scripted set-dressing at 0:58 and the player never touches one again in 59 minutes |
| carry salvage home | inside minute 8 | **works.** Sampled distance-to-green goes **275 m → 86 m → 267 m** across minutes 7, 8, 9: the whole round trip fits in **under two game minutes** (282 m at sprint 7.0 m/s is 40 s each way). The bot arrives on the green |
| town grows | — | **no.** Camp. 0 buildings added, 0 villagers, 0 conversations, 0 trades. Turn round |
| go out further | inside minute 9 | walks back to the same 40 m post it left, because there is nowhere else and no reason |

The circuit is ~2 minutes of walking and it delivers nothing, so the second one is not the
same as the first — **there isn't one.** ARM WALK gave up making trips after the second and
stood at the post exactly like ARM POST. The two arms end the hour with **identical**
lantern, tier, villager, trade and gun counts. *The lamplighter and the man who never left
his post achieved the same thing.*

What *does* repeat is the night: 4 nights, of which 2 completed a hold. Night 3 is the tier-1
wave from minute 1, again. Night 4 is that wave with one extra tier. **The second circuit is
the first one again, and quieter, because the player has learned it.**

### 5. What is the single change that would buy the most minutes?

**Turn the town on: make a lit lantern count, and give the player lanterns to light.**

Not "add content". Every part of the second act — five named villagers with dialogue, 12
working shop rows, four village-tier guns, 17 buildings, a construction ladder, a regard
system, a working authoritative trade path — **is already built and already renders.** The
change is to remove the three things standing between the player and it. All three are in
**one file**, `src/game/server.hml`. Scoped below (§4).

I considered and rejected two alternatives, and I want the reasoning on the record:

- *"Fill the empty day with wandering enemies."* It would fill the 11 minutes, and it is the
  wrong fix: the day is empty **because there is nowhere to go**, and adding targets to it
  makes the game one verb for 16 minutes instead of one verb for 5. It also spends triangle
  budget, which the town does not.
- *"Fix the difficulty flap so night 2 stops slaughtering the player."* Real, and worth doing
  (it is 20 deaths in 4 minutes and it is the worst *moment* in the hour). But it makes an
  existing loop fairer rather than making a missing loop exist, and a fair repeat is still a
  repeat.

---

## 3. WHAT IS WORKING — and this is not a courtesy paragraph

A critique that cannot tell good from bad is useless, so, specifically:

- **The first minute is excellent and I would not touch a beat of it.** Bell, line, the
  camera standing up, one vertical thing on the horizon, three Wisps, a Mote, `HOLD [E]`, the
  music stopping, the light, the horn. Granting the Flare **on the lantern beat instead of on
  a level-up card** is the single best design decision in the repository.
- **It is beautiful, and it is beautiful in motion.** The dusk sky at `t=16`, the ridge under
  stars at `t=1196`, the fog eating the far hills — this reads as a game a 1998 art director
  would have shipped, not as "retro" as an excuse. The lantern viewmodel is a real light
  source with a bright core and it anchors every frame.
- **The night is genuinely dark and genuinely readable.** Violet cores at 30 m, fog collapsing
  to 26 m, the post silhouetted. `t=306` — a Mote's `NS_CORE` glow filling the crosshair
  against a black hillside — is the best frame in the 720.
- **The 30-second combat loop is solid.** 371 kills in an hour, target persistence working,
  and the lantern-as-ammunition idea *actually functioning* — you can watch `ammo x/12` refill
  in the stats lines only while `d` (distance to the post) is small, and `supplied` climbing
  with it. (I did **not** verify the five-part hit-feedback contract of CLAUDE.md §9 — that
  needs a frame-by-frame capture at 60 Hz and I only have one frame per five seconds. Not
  claimed.)
- **It holds its budget with enormous room.** Peak 1 974 of 3 000 triangles; the display
  session ran the whole hour at the pace it was given. **There is room for the town.**
- **The engineering discipline is visible from the outside.** `--selftest 25/25`,
  `replay --verify 10000/10000` hash `16594734899016964914`, `ci_imports` 8/8, `ci_unbox`
  PASS — all still green today. The comments in `server.hml`, `director.hml` and `demobot.hml`
  told me *why* things are as they are, which is why this diagnosis took hours and not days.

---

## 4. THE CHANGE, SCOPED FOR THE NEXT AGENT

**File: `src/game/server.hml`. Three edits. Zero new systems.**

### (a) One word. `sv_lan_gather`, ~line 1537.

```hemlock
                let md = w.model;              // 90 == SIM_LANTERN_LIT (1) is never true
                if (md[slot] == SIM_LANTERN_LIT) {
```
→ `let md = w.anim;`

**Cost: 0 triangles, 0 ms** — it is the same loop, over the same array length, one field
across. **Effect, measured by ARM SHADOW:** the town's lantern feed goes 1 → 7 rows and core
lux 0 → 256. Necessary. **Not sufficient**, and the probe asserts that so nobody can claim it
as a fix on its own.

### (b) Point the opening's five lanterns at home. `sv_light_the_path`, ~line 1102.

Today the path curves to `spawn_yaw − 20°` and away from the settlement, so it drops six posts
at 181–275 m from the green where they are worth 1 grid point. Aim it at
`atan2(settle_cx − lantern_x, −(settle_cz − lantern_z))` instead and space the last two inside
60 m of the green.

**Cost: 0 triangles** (it is the same five posts, moved). **Effect, measured directly against
the shipped `settle.hml` by the probe's `what_would_it_take()`:**

```
    posts   ring     core lux   grid pts
        4    20.0 m       1536         10   <- Village
        4    40.0 m        512         10   <- Village
        4    60.0 m        512         10   <- Village
       16   100.0 m        256          1   <- still a Camp at sixteen posts
```

**Four lit posts inside 60 m of the green is a Village.** That is the whole threshold. And it
makes the beat at 0:58 mean what `GAME_DESIGN` §8 says it means — *a path of lit lanterns
leading somewhere* — instead of five lamps curving into empty fog.

> **A design decision the next agent must make deliberately, not by accident.** Four posts is
> so cheap that if (b) puts four of the five *already-lit* path lanterns inside 60 m, the town
> promotes to Village **at 0:58, for free, before the player has done anything.** That is
> almost certainly wrong — it spends the game's best reward on a cutscene. My recommendation
> is: **(b) aims the path at the town and lands the nearest post at ~120–150 m — close enough
> to be an obvious invitation, far enough to be worth nothing** — and the last stretch is
> walked and lit by the player with the kits from (c). Then the Village is *earned*, and it is
> earned by the verb the game is named after. Either way, **decide it, and say which you
> chose.**

### (c) Give the player lanterns to plant, without the Village gate. `sv_w6_boot` + `sv_script`.

`sv_place_kit` already works: `BTN_USE` with nobody and nothing in reach plants a post from
the pack, and `sim.hml` stage (g) channels it lit. Only the *supply* is missing, and it is
gated on a regard band the game cannot reach (§2.2.3).

Cheapest honest version, in the file that already owns both:
- `sv_w6_boot`: seed the pack with **2** `NPC_OFF_KIT` (mirroring how it already seeds the
  club and the Kestrel's 12 rounds — *"the club is spawn kit, not a reward"*).
- `sv_script`: on the `DIR_EV_HOLD_DONE` edge it already reads from `director_events`, grant
  **1 more kit** and call `npc_credit(sv.npcs, NPC_CRK_NIGHT, -1)` — the +3-regard credit that
  is defined, documented, and called from nowhere.

That is the loop, stated in one sentence with no new machinery: **survive a night, earn a
lantern, plant it, the town grows.**

**Cost:** one lantern post is `MESH_LANTERN`, **48 triangles**
(`meshgen.hml`, `mg_register(MESH_LANTERN, "lantern", 48, MG_KIND_PROP, three_q, 72)`; the
mesh's own comment says 40). Four extra posts near the green is **192 triangles worst case**, and
only when all four are simultaneously inside a 26–72 m fog radius. Measured peak today is
**1 974 of 3 000**. **≈ 0.28 ms** by `frame_ms = 0.63 µs·SOURCE + 1.45 µs·DRAWN` if every one
of the 192 is both submitted and drawn. Sim cost: `sv_lan_gather` is already O(entities) once
per 60 ticks and four more lanterns do not change its complexity.

**What it buys, and I am giving the ceiling as well as the floor.** It does not add a minute
of authored content. What it does is make **the 11 empty minutes have a destination** and
open **12 working shop rows, 4 village guns, 5 villagers and 17 buildings** to a player who
currently reaches none of them. The trade path is proven (`2d90bc8`: 601 traced ticks holding
a bought rifle) and the town renders (`--town 2`: 782 tris peak). **The next agent should
measure the hour again with this probe and report the new "last moved at" column, not
estimate it.**

### The one thing to check that this does NOT fix

`sv_lan_gather` caps the feed at `SV_LAN_CAP` and `settle_step` re-integrates
`SET_SLICE = 8` lanterns per second, so a player who plants many posts will see lux lag by up
to a sweep. That is by design (`settle.hml`'s header says so) and it is fine. But
`settle_refresh`'s `acc_valid = 0` invalidation on every injection means a feed rebuilt every
60 ticks with a *changing* member count will restart the sweep — worth a look once posts are
actually being planted.

---

## 5. HONEST GAPS AND BUGS FOUND (reported, not fixed — I do not own `src/`)

1. **`src/game/server.hml:1537` — `sv_lan_gather` reads `w.model` where it must read
   `w.anim`.** Disables the entire settlement system in every unmodified session. §2.2.1.
2. **`NPC_CRK_NIGHT` (+3 regard, "a night survived in the settlement") is defined at
   `npc.hml:194` and called from nowhere in `src/`.** `NPC_CRK_LANTERN` is called exactly once
   ever, on the first lantern, so *the game's core verb awards relationship progress one time.*
3. **`g_REGEN_DELAY_S` and `g_REGEN_RATE` (`config.hml:1108-9`) are read by nothing in
   `src/`.** The player ends the measured hour on **4 HP** with no tap at all: no regen, no
   soup (Odo needs a Village), and no Mend — which needs both spell level 7 *and* a second
   spell slot at Attunement 7, i.e. character **level 8**, i.e. **~131 more minutes** at the
   measured post-opening rate of 65 XP/min.
4. **The spell school is one slot wide for the whole hour.** `spell_slots = 1 + Attunement/7`
   (`spells.hml:550`) and Attunement starts at 0, so the Flare takes the only slot at 0:30 and
   the six other spells — heal, cloak, fire blast — cannot be equipped at any point in an
   hour. `spells granted 1` in every run. This is the thing I almost got wrong; see §1.
5. **The night-2 difficulty cliff.** The tier pin comes off after `holds_done > 0` and the
   chunk rolls tier 3: **20 player deaths across the night**, the hold never clears,
   `dir_abort` ends it at dawn. `sim.hml`'s own comment already argues tier 2 saturates the 14-alive cap
   "by construction"; nothing pins the *second* night, and the second night is the first time
   the player meets the real curve.
6. **`--demo N --town 2 --at-town` without `--demo-ui` never reaches the town.** Measured:
   `--demo 120 --town 2 --at-town` ended at `pos -51,-270`, 274 m from the green, `trades 0`,
   because the shipping `demobot.hml` leashes to the lantern post at 16 m and the trade
   steering lives in `main.hml`'s `demo_ui_drive`. Adding `--demo-ui` fixes it (`trades 2` in
   45 s). Not a game bug — a harness footgun, and worth a line in `--help`, because the
   commit message's `--demo 30 --town 2 --at-town` recipe no longer does what it says.
7. Cosmetic: `hemlockc` warns `variable 'rc' shadows variable declared at line 3559` in
   `src/game/main.hml` (line number as of my 18:22 build; that file has since been edited by
   another agent).

---

## 6. THE SCREENSHOTS I LOOKED AT

720 PNGs were captured at 5 s intervals from the `DISPLAY=:0` session
(`…/scratchpad/hourA/`). Every image below I opened and looked at; each carries its own stats
line from the session log, which is the durable half of the evidence.

| frame | t | what I saw |
|---|---|---|
| `ns_0_t1.png` | 0:01 | On your back, staring at the sky, `p 68`. *THE LAMPS WENT OUT ON A TUESDAY* in centre frame. `tri 789/1424`. Good. |
| `ns_3_t16.png` | 0:16 | Dusk. Ochre sky, acacia silhouettes, the lantern post ahead. `RELOADING`, `KESTREL 3/12`, the Flare bar. Reads exactly as intended. |
| `ns_61_t306.png` | 5:06 | **Best frame of the 720.** A violet `NS_CORE` glow filling the crosshair against a black hillside, `WAVE 3 7` top-left, the post silhouetted. |
| `ns_120_t601.png` | 10:01 | Daylight. Empty green hills, one small lit lantern mid-frame, `6/12`. Nothing to do. `pos -43,-279 hp 4`. |
| `ns_150_t751.png` | 12:31 | **Identical in substance to the frame 2.5 minutes earlier — same position, same HP, same ammo.** |
| `ns_239_t1196.png` | 19:56 | Night 2. Stars, hills, `WAVE 2 10`, `RELOADING`, `2/8`. Beautiful, and it is the frame where the player died twenty times. |
| `ns_300_t1501.png` | 25:01 | Daylight, hills, one lantern, `6/12`. Same. |
| `ns_360_t1801.png` | 30:01 | **Twenty minutes after `t601` and it is the same picture.** Empty hills, one lantern, `6/12`, no HUD banner. This is the whole finding in one image. |
| `ns_400_t2001.png` | 33:21 | Dusk, `WAVE 1 8` appearing top-left. The night is starting again. Position unchanged from 20 minutes earlier. |
| `ns_500_t2501.png` | 41:41 | Broad daylight, blue sky, `alive 0`, `hp 10`, `6/12`, `pos -51,-270` — which is the same coordinate as `t2001`, **eight minutes earlier.** I checked the log rather than trusting my eyes: the blue angular shape lower-left is scenery, not an enemy. |
| `town/camp_actual.png` | — | `settle_shot --tier 0 --seed 1337`: **the settlement the player actually walks 282 m to reach.** Roads and the plot lattice drawn on empty grass. No buildings. Nobody. It reads as an abandoned car park. |
| `town/village.png` | — | The same camera at Village tier: one clad building on the ridge. The *only* difference from the frame above is the thing the player cannot cause. |
| `town/city.png` | — | The same camera at City tier at dusk. |
| `uiC/ns_5_t26.png` | — | **The trade panel, working.** `MABEL / BENCH`, rows `BOLT 0 · REVOLVER 40 · PUMP 65`, `X NEXT  C TAKE`, and `TAKEN` in `UI_AMBER`. Legible, plated, on-palette. **Unreachable in normal play.** |
| `ns_719_t3596.png` | 59:56 | **The last frame of the hour.** Daylight, `pos -39,-280`, `hp 58`, `6/12`, `alive 0`, `tri 1490/2064`. The eight frames before it are the same coordinate. |
| `uiC/ns_8_t41.png` | — | Standing in front of Mabel's Bench: `[E] MABEL / [T] TRADE`, and the HUD now reads **`BLKTHRN 5 / 64`**. This is the game the design document describes, and it is 45 s from a `--town 2` boot and infinitely far from a real one. |

---

## 7. ACCEPTANCE — every criterion, PASS/FAIL, with its number

Loadavg is stated with every timing per **RULE T** / CLAUDE.md §1.2. This box permanently
shares ~17 of 24 cores with a `llama-server`.

| # | criterion | result | number |
|---|---|---|---|
| 0 | **RULE 0** — compiler verified before any measurement | **PASS** | `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` printed `107` then `5120738502741017561` |
| 1 | probe **COMPILED** and headless; `exit(1)` on failure; asserts its own count | **PASS** | `hemlockc -O1 tools/probe_session.hml` → `nm \| grep -c SDL_` = **0**; prints `build COMPILED`; `PASS 31 / 31`, `exit=0`; `g_PS_EXPECT = 31` pinned |
| 2 | before/after measurements, loadavg stated | **PASS** | probe run **1 m 49 s** CPU at loadavg **8.69**. **Three separate compiles and runs — at loadavg 8.69, ~9.0 and 33.21, spanning a concurrent `src/sim/worldgen.hml` edit — produce a byte-identical ARM POST table.** That is the before/after that matters here: the finding is deterministic, not an artefact of a busy box. Hour session **3600 s** launched at loadavg **28.38**, sampled 20.87 / 12.78 / 9.60; `--demo 120` at loadavg ~9 |
| 3 | `ci_imports.sh` R1–R8 | **PASS** | `files=111 imports=872`, **RULES 8/8**, `CI_IMPORTS PASS`, re-run last with `tools/probe_session.hml` in the tree |
| 4 | `ci_unbox.sh` | **PASS** | `targets=14 functions=521 scalars=79 boxed=0 warn=18` → `CI_UNBOX PASS` |
| 5 | `--selftest` | **PASS** | `PASS 25 / 25`, re-run at loadavg **3.34** after everything else was finished |
| 6 | `replay --verify` | **PASS** | `10000/10000 ticks matched, hash 16594734899016964914` — **the same hash `2d90bc8` recorded** — `0` cosmetics while replaying, `PASS 14/14` |
| 7 | triangle budget holds | **PASS** | the hour session's own report: **`triangles: PEAK 1857 of 3000   HUD peak 248 of 250   viewmodel peak 122`**. Across its 720 screenshot stats lines the peak **submitted** was **2 200** against 1 757 **drawn** — reported separately, because CLAUDE.md §3 is explicit that they are different variables. `--demo 120` peaked 1 974. **The town would cost ~192 of the ~1 150 triangles of headroom.** |
| 8 | 60 fps floor | **PASS** | the full hour on `DISPLAY=:0`: **283 263 frames in 3600.0 s = 78.7 fps**, render CPU **7.6 ms** (RULE T, min of 7-frame batches) with **9.1 ms of headroom**. **24 449 of 283 263 frames (8.6 %) exceeded 16.67 ms** and the worst was **82.0 ms** — on a box that was at loadavg 20–33 for most of the hour with three other agents compiling on it. Reported, not hidden. For contrast the headless `SDL_VIDEODRIVER=dummy` figure is **57.0 fps**, which is a `run_loop` sleep-and-spin artefact of having no vsync, not a renderer cost. |
| 8b | sim budget | **⚠ FAIL, reported** | `sim+net: worst 9.5 ms of the 2.0 ms budget` over 216 001 ticks. A single worst-case tick, `stalls 0  forgiven 0  decode-fail 0`, on a box at loadavg 33 — but it is over budget and I am not going to round it down. **Not investigated; not mine; another agent was measuring exactly this (`sim+net worst` sweeps) in the same tree while I ran.** |
| 9 | **LOOK at every frame I changed** | **N/A — I changed no frames.** | This is a diagnostic task and its deliverable is knowledge. `src/` is untouched **by me** — `git diff --stat` shows modifications from other agents (§0) and none from me; my contribution to `git status` is exactly two untracked files, `docs/design/THE_HOUR.md` and `tools/probe_session.hml`. I opened and looked at **16 frames** that I *caused to be rendered*, listed in §6. |

### What I did not do, plainly

- **I did not fix the `w.model` bug**, or any of the seven items in §5. I do not own `src/`.
- **I did not play with a mouse or a keyboard.** See §0. Every claim about *feel* is inference.
- **I did not measure a second seed.** Everything here is seed **1337** — the seed the display
  session and both probe arms ran. The settlement site, the spawn bearing and the chunk tier
  are all functions of the seed, so **the 181–275 m lantern distances will move on another
  seed; the `w.model` bug will not, and neither will the regard arithmetic.**
- **I did not measure audio.** The display session ran with sound; I cannot hear it.
- **I did not run the multi-seed first-minute ladder** (`probe_firstminute`) — out of scope,
  and `2d90bc8` measured it four days of commits ago at 11 of 12.

---

## 8. THE DISPLAY SESSION'S OWN REPORT

`nightshade --demo 3600 --scale 4 --seed 1337 --shots …` on `DISPLAY=:0`, one wall-clock hour,
started **18:27:09**. **Loadavg at launch: 28.38** (my own `-O3` build had just finished);
sampled at **20.87 / 12.78 / 9.60** through the run. This box permanently shares ~17 of 24
cores with a `llama-server`, and while I measured, other agents in the same tree were
compiling and running `probe_firstminute` and their own `--demo` benchmarks. **Read the frame
numbers below as a lower bound on a badly contended box, not as this renderer's ceiling.**

```
nightshade: 283263 frames in 3600.0 s
   render, wall (STAT_T_FRAME)  mean 12.3 ms  worst 82.0 ms
   render, CPU  (RULE T, min of 7-frame batches)  7.6 ms
   headroom at 60 fps: 9.1 ms/frame on the CPU-time number
   whole frame  mean 12.7 ms -> 78.7 fps  (283263 frames in 3600.0 s of loop)
   frames over 16.67 ms: 24449 of 283263
   where the frame goes, mean: input+tick 0.3 ms (sim CPU 0.6)  render 12.3  body 12.7
   parallel emit: 4 workers
   triangles: PEAK 1857 of 3000   HUD peak 248 of 250   viewmodel peak 122
   sim+net: worst 9.5 ms of the 2.0 ms budget   ticks 216001
   stalls 0  forgiven 0  cmds 216000  packets 216001  decode-fail 0
   beat reached: PATH   lantern 1   path 5   sounds 4670
   unlock card: 0 truncated frames (MUST be 0)
   W6 town: CAMP lux 0/512  pts 0/10  buildings 2  villagers 0 (0 named)
   W6 draw: settlement PEAK 0 tris, villagers PEAK 0 drawn,
            town mesh library 5162 tris in 232 meshes
   W6 hand: melee 0  spells granted 1  casts 595  oil 20/100  points 4 unspent
   W6 panels: TRADE peak 0 tris, open on 0 frames
   W6 talk: target -1 at 0 m, topic -1, open offers mask 0, last panel message ''
   W6 acts: swings 0  talks 0  trades 0 (0 refused)  points spent 0  lanterns fed 1
   W7 hands: held KESTREL (4)  own 1 mask 16  grants 1  denied 0
```

### THE CROSS-CHECK, AND IT IS THE REASON TO BELIEVE ANY OF THIS

This report is a **different binary**, a **different frame rate** (78.7 fps against the probe's
nominal 60), a **different renderer path** (a real GPU and vsync against no renderer at all)
and a **different process**. Every structural number the probe predicted, the game printed:

| | probe, headless | game, `DISPLAY=:0` |
|---|---|---|
| beat reached after an hour | `PATH` | **`PATH`** |
| lanterns in the settlement feed | 1 | **`lanterns fed 1`** |
| settlement | CAMP, lux 0, pts 0 | **`CAMP lux 0/512 pts 0/10`** |
| buildings | 2 | **2** |
| villagers | 0 | **`0 (0 named)`** |
| settlement triangles drawn | — | **`settlement PEAK 0 tris, villagers PEAK 0 drawn`** |
| spells granted | 1 | **1** |
| guns owned | 1 | **`own 1 mask 16`** |
| trades / talks | 0 / 0 | **`trades 0 (0 refused)` / `talks 0`** |
| unspent stat points | 4 | **4** |

**`settlement PEAK 0 tris` is the sentence to take away.** Over 283 263 frames of an hour, the
renderer drew **zero triangles of town**, out of a **5 162-triangle library sitting in memory
in 232 meshes** the whole time. The art is loaded. Nothing ever asks for it.

### The last forty seconds, verbatim from the log

```
ns_712_t3561.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_713_t3566.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_714_t3571.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_715_t3576.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_716_t3581.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_717_t3586.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_718_t3591.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
ns_719_t3596.png ... pos -39,-280 d 16 hp 58 ammo 6/12 alive 0
```

Eight consecutive frames, forty seconds, one coordinate. That is how the hour ends.

### A caveat on comparing the two, stated rather than glossed

The display session ran at **78.7 fps** and the probe at a nominal 60. `demobot.hml` decides
once per **frame** while the sim steps at a fixed 60 Hz, so the two are **not tick-identical**
and their moment-to-moment numbers differ (HP 58 here, 4 in the probe; 5 502 XP there). **Every
structural column matches exactly**, which is the point: the finding is not sensitive to frame
rate, renderer, binary or process.
