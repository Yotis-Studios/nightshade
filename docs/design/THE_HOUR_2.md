# THE HOUR, AGAIN — what the second verb bought, measured

**Task:** play-the-hour-again. **HEAD:** `b996b41` **plus eleven modified and two new files that are
not committed** (see §0.1 — this matters more than usual). **Date:** 2026-08-01.
**Instruments:** `tools/probe_session.hml` re-run **unchanged**, `tools/probe_lanfeed.hml` re-run,
one 60-minute session of the shipping binary on `DISPLAY=:0` with 720 screenshots, plus one scratch
driver of my own that lives outside the repo.
**Owned and written:** `docs/design/THE_HOUR_2.md`, and nothing else. **`src/` is untouched by me;
so is `tools/`.**

`THE_HOUR.md` ended with an instruction: *"The next agent should measure the hour again with this
probe and report the new 'last moved at' column, NOT ESTIMATE IT."* That is what this is.

---

## THE ONE-LINE ANSWER

**The second verb works, and it is worth twenty-four minutes.** The town a player builds themselves
promotes to VILLAGE at **24:53**, buys seven buildings and seven villagers, and does it with four
lantern posts and no fixture anywhere. THE_HOUR's last new thing was at **0:58**; it is now at
**24:53** — **25.7× further in** (1 493 s against 58 s).

**And then it stops dead, harder than before.** From 25:00 to 60:00 — **thirty-five consecutive
minutes, 58 % of the hour** — every single town, person, shop, regard and inventory column is
frozen. Not one of them moves again. The reason is exactly one thing and it is arithmetic, not
taste: **the second verb has an ammunition supply of four, and there is no fifth.**

---

## 0. HOW I DROVE IT, AND HOW MUCH TO TRUST THIS

Read this first, because it bounds everything below. THE_HOUR's §0 is the reason anyone believed
it; this is the same contract.

### 0.1 ⚠ I MEASURED A WORKING TREE, NOT A COMMIT — AND ONE PROBE DISAGREES WITH ITS OWN AUTHOR

`HEAD` is `b996b41`. The tree is not. `git status` at the time I started:

```
 M src/core/config.hml      M src/game/main.hml       M src/game/server.hml
 M src/sim/ai.hml           M src/sim/director.hml    M src/sim/npc.hml
 M tools/probe_director.hml M tools/probe_hudlayer.hml M tools/probe_nightanchor.hml
 M tools/probe_settle.hml   M tools/probe_simcost.hml
?? tools/probe_hud.hml      ?? tools/probe_lanfeed.hml
```

1 718 inserted lines from three agents, none of it committed. **Everything below describes that
tree.** The three agents were finished when I started — nothing moved under me, and I checked:
`git diff --stat` is byte-identical at the start and the end of my session.

**And that is how I found the first thing worth reporting.** `the-second-verb`'s headline was *"8 of
8 seeds reach VILLAGE ... at 24:45–25:08 elapsed"* and *"All green. Final verification complete."*
I re-ran its probe, unmodified, exactly as it sits in the tree:

```
$ hemlockc -O1 tools/probe_lanfeed.hml -o /tmp/plan2 && /tmp/plan2
   8 seeds x 24 game minutes, compiled
   -> 0 of 8 seeds promoted to VILLAGE in 24 game minutes
  FAIL [123] >>> A REAL SESSION, NO FIXTURE, REACHES VILLAGE <<< 0 of 8 seeds
  ASSERTIONS  ran 130  pass 125  fail 5      exit 1
```

**The finding is true and the probe is red, and both facts are the same fact.** `g_MINUTES` defaults
to **24** and the Village lands at **24:53**. Fifty-three seconds. Give it the window its own
headline needs and every number the author reported reproduces to the second:

```
$ /tmp/plan2 --seeds 3 --minutes 40
   seed   village at   posts then   end tier   core     pts     fed   bld
    1337       24:53            4          1    1042/512   10/10    11     9
       2       25:06            4          1    1041/512   10/10    10     9
       7       24:47            4          1    1043/512   10/10    11     9
   -> 3 of 3 seeds promoted to VILLAGE in 40 game minutes    PASS 39/39
```

24:53, 25:06, 24:47 — the same three numbers, in the same order, as the report. So this is not a
regression and it is not a false claim: it is a probe that **ships a default which cannot reach the
thing it asserts.** `g_MINUTES` must be at least 30. It is one integer and I do not own the file.

### 0.2 I did not play this with hands

There is still no `xdotool` and no `xte` on this box, and I did not write an XTest driver for the
same reason THE_HOUR did not: an hour of blind hand-authored key events makes a worse player than
the one the repo ships and a measurement nobody can reproduce. **I never used a mouse, so every
statement about how aiming feels is inference from numbers and pictures.** Five arms, each named
with what it can and cannot say:

| # | How | What it is | What it can say | What it cannot |
|---|---|---|---|---|
| **A** | `nightshade --demo 3600 --scale 4 --seed 1337 --shots …` on `DISPLAY=:0`, one real hour, 720 PNGs | `src/game/demobot.hml`, **the shipping driver**, unmodified | what the game looks like minute by minute; frame pacing; what is on screen at 30:00 | nothing about a player who decides to walk somewhere |
| **B** | `tools/probe_session.hml` **ARM POST**, re-run byte-unchanged | the same `demobot.hml`, imported not ported | the 31-column minute table THE_HOUR published, so the two hours diff column by column | same limits as A |
| **C** | `tools/probe_session.hml` **ARM WALK**, re-run byte-unchanged | the lamplighter that walks home at dawn | that walking home is still not enough | **it is still broken, and worse — see §0.4** |
| **D** | `tools/probe_lanfeed.hml` **ARM PLANT** | `the-second-verb`'s own probe: demobot first, movement overridden to plant four posts round the green | whether the loop closes when driven correctly, and when | whether a player would work out to do it |
| **E** | **ARM LAMP** — my own scratch driver, `…/scratchpad/hour2_lamp.hml`, outside the repo | ARM PLANT plus a minute sampler plus a post-Village town visit | the 60-minute "last moved at" table for a player who *does* close the loop | its town-visit half is defective — §0.4 |

**ARM PLANT and ARM LAMP are oracle players and I am declaring it, not hiding it**, exactly as
THE_HOUR declared ARM WALK. They read the settlement centre from `settle_cx` and they know a post is
worth more inside 64 m. The game teaches the first properly — `main.hml:2054` puts a **green `HUD_ICON_DIAMOND` on the
compass, bearing home, from the moment the first lantern is lit**, and turns it `UI_DANGER` on
brownout — and it **does not teach the second anywhere at all.** That is a finding, in §2.3, not a
probe defect — but it means these arms measure *what the systems do when driven correctly*, never
how hard any of it is to find.

### 0.3 The box, and what it did to the numbers

Loadavg is stated with every timing per **RULE T** / CLAUDE.md §1.2. This box permanently shares
~17 of 24 cores with a `llama-server`. Loadavg over my session ran **0.33 → 7.08**; it was **2.38**
when the display hour launched and I deliberately stopped compiling for the last third of it.
**RULE 0, run before any measurement:** `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` printed
`107` then `5120738502741017561`.

### 0.4 ⚠ MY TOWN-VISIT DRIVER BROKE, HERE IS WHEN, AND HERE IS THE CONTROL RUN THAT PROVES IT WAS MINE

THE_HOUR's ARM WALK degraded after ~45:00 and said so. **Mine broke at 25:00, and ARM WALK in this
tree now breaks at 26:00.** Both are the same class of defect and both are the instrument, not the
game. The evidence, because "I think it was my bug" is not good enough:

| run | town visits | deaths at 60:00 | kills | shots | XP | verdict |
|---|---|---|---|---|---|---|
| ARM LAMP `--notown` (never revisits) | 0 | **58** | 338 | 1 433 | 7 312 | clean hour |
| ARM LAMP `--retire 1` (visits once, then the override switches **off** for good) | 1 | **84** | 339 | 1 284 | 7 305 | clean hour |
| ARM LAMP, override left on | 3 | **350** | 197 frozen from 24:00 | 663 frozen | 4 735 frozen | **broken** |
| `probe_session` ARM WALK (not mine) | 3 | **223** | 183 frozen from 26:00 | — | 3 011 frozen | **broken the same way** |

`--retire 1` is the control that settles it: it walks to the town once and then **removes my
override entirely**, so from ~24:00 the frame path is byte-for-byte ARM POST. That hour is healthy
— 339 kills, level 5, 84 deaths. The moment the override is allowed to keep making trips, the
player stops firing (`shots` frozen), stops killing (`kills` frozen) and dies eleven times a minute
in broad daylight with `director_alive = 0`. **A state machine that steers a player it has disarmed
is my bug, and I could not finish fixing it inside this task.**

**What that costs this report, stated plainly:** I have **no unfixtured measurement of talking to or
trading with a villager in a town the player built.** Every `trades 0 / talks 0` below is my
driver's silence, not the game's, and I do not claim otherwise. What I *do* have for that question
is in §2.3: the earned Village's own open-offer table, and a separate fixtured run that proves the
shop path works at VILLAGE tier.

**Everything else in this document rests on ARM POST (no override at all), ARM PLANT (the shipped
probe), ARM LAMP `--notown` / `--retire 1`, and the display session.** None of those four is
affected.

---

## 1. THE TWO HOURS, COLUMN BY COLUMN

This is the table THE_HOUR asked for. Times are elapsed session time; the 16-minute day means the
hour is 3.7 days. Both columns are `--seed 1337`, the seed THE_HOUR ran.

### 1.1 ARM POST — the shipping driver, the same instrument, one wave apart

`probe_session.hml`, re-run with not one character changed.

| column | THE_HOUR (`2d90bc8`) | THIS HOUR | moved? |
|---|---|---|---|
| beat reached at 60:00 | `PATH` | `PATH` | — |
| lanterns in the settlement feed | **1** | **7** | ✅ the one-word fix, live |
| core lux | 0 / 512, *last moved 0:00* | **256 / 512, last moved 1:00** | ✅ |
| grid points | 0 / 10, *last moved 0:00* | **1 / 10, last moved 1:00** | ✅ |
| settlement tier | CAMP, last moved 0:00 | **CAMP, last moved 0:00** | ✗ |
| buildings | 2, last moved 0:00 | **2, last moved 0:00** | ✗ |
| villagers | 0, last moved 0:00 | **0, last moved 0:00** | ✗ |
| guns owned | 1, last moved 0:00 | **1, last moved 0:00** | ✗ |
| lanterns the player lit | 1 | **1** | ✗ |
| kits placed | 0 | **0** | ✗ |
| trades / talks | 0 / 0 | **0 / 0** | ✗ |
| regard (Wick) | 0, last moved 0:00 | **0, last moved 0:00** | ✗ |
| character level | 5, last moved 56:00 | **4, last moved 37:00** | ⚠ down one |
| XP at 60:00 | 5 502 | **5 082** | ⚠ |
| holds done | **2** (at 7:00 and 56:00) | **1**, last moved 6:00 | ⚠ **down one, and it is load-bearing** |
| player deaths | 71 | **112** | ⚠ |
| salvage, unspendable | 220 | **203** | ✗ |

**Read the ✗ column first.** For the player who does what the shipping bot does — hold the post —
**this wave changed nothing at all.** The lantern feed is repaired and the town gets 256 of the 512
lux it needs, which is real and is exactly what `b996b41` promised and no more. Tier, buildings,
villagers, guns, trades, talks, regard: every one still reports **"last moved at 0:00"**, in an
hour, with 296 kills.

**And the ⚠ row that matters is `holds done`, 2 → 1.** THE_HOUR measured the hold completing at 7:00
and again at 56:00. This tree completes exactly one hold, ever, in **every arm of every run I made**
— ARM POST, ARM WALK, ARM PLANT over eight seeds, ARM LAMP over four hours of variants. §2.2 is
about why that single number closes the loop.

### 1.2 The twelve frozen minutes are still there, unchanged

THE_HOUR printed minutes 7–19 of ARM POST and said "not one of thirty-one columns changes". Here is
the same window, this tree:

```
 min  d ph   beat  hp lvl    xp purse  town lux pts bld npc lan kits holds kills own trd talk regW pt  dist
   7  0 NGHT PATH    64   3  2051    82    0  256   1   2   0   7    0     1   131   1   0    0    0  2   275
   8  1 dawn PATH    64   3  2051    82    0  256   1   2   0   7    0     1   131   1   0    0    0  2   275
  ...  identical for minutes 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 ...
  19  1 NGHT PATH     0   3  2113    84    0  256   1   2   0   7    0     1   135   1   0    0    0  2   270
```

Twelve consecutive game minutes, thirty-one columns, nothing moves. The display session agrees to
the metre: `pos -52,-259` at `t1201`, at `t1501` and at `t1801` — **ten minutes, one coordinate.**
**11 of every 16 minutes — 69 % of the clock — is still empty for this player.**

### 1.3 ARM LAMP — the player who uses the four kits. This is the new hour.

`--notown`, the trustworthy variant (§0.4). One seed, 60 minutes, no fixture. Times corrected to
mm:ss.

```
 min ph   beat  hp lvl    xp purse tier lux pts bld npc nmd lan kit pack hold trd regW open dist deaths kills
   0 day  WAKE  100   1     0     0    0    0   0   2   0   0   1   0    0    0   0    0    0  282      0     0
   1 dusk PATH   64   1   634    25    0  256   1   2   0   0   7   0    2    0   0    0    0  289      0    20
   6 NGHT PATH   64   3  2051    82    0  256   1   2   0   0   7   0    4    1   0    0    0  275      4   131   <- hold 1: +2 kits
   9 dawn PATH   64   4  3451   138    0 1042  10   2   0   0  11   4    0    1   0    0    0   56      4   131   <- FOUR POSTS PLANTED
  24 dawn PATH   78   4  4748   189    0 1042  10   2   0   0  11   4    0    1   0    0    0  260     22   202
  25 dawn PATH   12   4  4854   194    1 1042  10   9   7   3  11   4    0    1   0   15    6  271     22   208   <- VILLAGE
  26 day  PATH   12   4  4854   194    1 1042  10   9   7   3  11   4    0    1   0   15    6  271     22   208
  ... 35 minutes in which tier, lux, pts, bld, npc, nmd, lan, kit, pack, hold, trd, talk, regW,
      regM and open-rows are ALL IDENTICAL to minute 25 ...
  60 day  PATH   12   5  7312   292    1 1042  10   9   7   3  11   4    0    1   0   15    6  273     58   338
```

```
  WHAT STOPPED MOVING, AND WHEN  (ARM LAMP, --notown)
    settlement tier                0 ->       1   last moved at  25:00
    core lux                       0 ->    1042   last moved at   9:00
    grid points                    0 ->      10   last moved at   9:00
    buildings                      2 ->       9   last moved at  25:00
    villagers                      0 ->       7   last moved at  25:00
    named villagers                0 ->       3   last moved at  25:00
    lanterns in the feed           1 ->      11   last moved at   9:00
    kits planted                   0 ->       4   last moved at   9:00
    kits in the pack               0 ->       0   last moved at   9:00
    holds done                     0 ->       1   last moved at   6:00
    guns owned                     1 ->       1   last moved at   0:00
    trades                         0 ->       0   last moved at   0:00     <- see §0.4
    conversations                  0 ->       0   last moved at   0:00     <- see §0.4
    regard (Wick)                  0 ->      15   last moved at  25:00
    regard (Mabel)                 0 ->      15   last moved at  25:00
    shop rows open now             0 ->       6   last moved at  25:00
    character level                1 ->       5   last moved at  37:00
    purse                          0 ->     292   last moved at  54:00
```

**That is the whole change this wave bought, in one column.** THE_HOUR's version of this table read
`0:00` on *every* town row. This one reads **9:00** and **25:00** on the rows that matter, and
**every one of them then stops for the remaining thirty-five minutes.**

---

## 2. THE FOUR ANSWERS

### 1. Where does it stop being interesting now, and what is the last new thing?

**The last new thing is the VILLAGE at 24:53, and it stops being interesting at 25:00 — the minute
after.** THE_HOUR's numbers were 0:58 and 6:40.

Precisely, because these are three different questions:

- **0:58 — the last *authored* beat is still `PATH`.** Unchanged, in every arm, in the display hour
  (`beat reached: PATH` at 60:00) and in the probe. Nothing scripted happens after it.
- **0:58 also now *hands you something*, and that is the wave's real win.** THE_HOUR's sharpest
  sentence was that the game's last beat gives the player nothing. It gives them **two lantern
  kits** now, on the beat, and `SV_HOLD_KITS` pays two more for surviving the first night at 5:52.
  The beat became a verb.
- **9:00 — the first thing the player *causes*.** Four posts down, core lux **256 → 1 042**, grid points
  **1 → 10**, the feed 7 → 11 rows, and a level (XP 2 051 → 3 451 in one minute, which is **1 400 XP for
  lighting four lanterns, with zero kills in that minute** — twenty-one minutes' worth of the
  65 XP/min post-opening rate THE_HOUR measured, and the largest single reward in the game).
- **24:53 — the town promotes.** `settle.hml` requires the thresholds be *held for one continuous
  in-game day*, so the sixteen minutes between 9:00 and 24:53 are a real, deliberate, designed wait.
- **25:00 — and that is the end.** Fifteen columns freeze in the same minute and none of them moves
  again in thirty-five minutes.

**How far away is the next real thing?** Three candidates, all arithmetic, none of them inside the
hour:

| the next thing | what it needs | measured position at 60:00 | reachable in an hour? |
|---|---|---|---|
| a fifth lantern kit (free) | a second completed hold | **holds done = 1**, in every arm | **no — §2.2** |
| a fifth lantern kit (bought) | Wick row 13, regard **192** TRUSTED | **regard 15** | no — ~28 in-game days |
| a second gun | Mabel row 1, regard **32** ACQUAINTED | **regard 15** | not without talking |
| a second spell | Attunement 7 = level 8 = 14 000 XP | level 5, 7 312 XP | no — unchanged from THE_HOUR |
| settlement TOWN | 32 grid points, 1 024 core lux | **10 pts**, 1 042 lux | **lux is already over. 22 points short.** |

The last row is the one to stare at. **The town's next promotion is already half-satisfied and has
been since minute nine.** Core lux 1 042 clears TOWN's 1 024 threshold outright. The only thing
missing is grid points, and grid points are bought with posts, and the player has no posts.

### 2. Does the loop loop? Trace both circuits.

**Circuit one completes. It is 24 minutes 53 seconds long and it is good.** Traced on ARM LAMP,
`--notown`, with times:

| leg | when | what actually happened |
|---|---|---|
| go out | 0:00–0:30 | the opening. Unchanged and still the best thirty seconds in the repo |
| push the dark back | **0:58** | `PATH`: five lit lamps fade in **pointing at the town** (the nearest lands at 134.9–135.0 m from the green on all 8 seeds, solved not typed) **and two kits appear in the pack** |
| survive a night | **5:52** | `DIR_EV_HOLD_DONE` → 2 more kits, +3 regard. The one achievement in the game finally pays |
| carry it home | 8:00–9:00 | 282 m at dawn, `dist` 275 → 143 → **56**. Four posts planted round the green, four channelled lit |
| the town takes it | **9:00** | core lux 256 → **1 042** of 512; grid points 1 → **10** of 10. Both thresholds cleared in one minute |
| the town grows | **24:53** | held for one continuous in-game day → **VILLAGE**. buildings 2 → 9, villagers 0 → 7 (3 named), shop rows open 0 → 6, regard 0 → 15 |
| go out further | — | **there is nowhere further and nothing to go with** |

**Circuit two does not exist, and it is not close.** It needs one lantern kit and there are exactly
two ways to get one:

1. **Survive another night.** `sv_script` pays `SV_HOLD_KITS` on `DIR_EV_HOLD_DONE`. **`holds done`
   reaches 1 and stops, in every arm of every run I made this session** — ARM POST, ARM WALK, ARM
   LAMP ×4 variants, and ARM PLANT across 8 seeds × 24 min and 3 seeds × 40 min, where the probe's
   own column prints `hold 2 done: -` eight times out of eight. THE_HOUR measured this number at
   **2**. Nights 2, 3 and 4 are all still aborted by dawn with the field up.
2. **Buy one from Wick.** Row 13, price 36, **tier VILLAGE — which the player now has — and regard
   192 TRUSTED**, which they do not. The measured regard after a full hour is **15**, and 15 is not
   the sum of an hour's relationship-building: it is `NPC_CR_PROMOTE`, the flat +15 that
   `npc.hml:2304` pays every villager the instant the town promotes. **It arrives at 25:00 and it
   never moves again.**

So the honest comparison THE_HOUR asked for — *is the second circuit better than the first, or the
same one again?* — has a new answer, and it is not "the same one again":

> **The first circuit is a real loop and it is the game the design document describes. The second
> circuit is not a repeat; it is a closed door.** THE_HOUR found a closed circuit with no entrance.
> This wave built the entrance, gave the player exactly enough to walk through it once, and left the
> room with no second door.

What still repeats is the night: four of them, of which **one** clears. THE_HOUR reported two.

### 3. Did the town grow, and did it FEEL like it grew?

**It grew. A number in a struct is not growth, so here is what is actually on screen.**

**The numbers, unfixtured, from `settle.hml` itself:**

| | 5:00 | 20:00 | 60:00 | worth having? |
|---|---|---|---|---|
| settlement tier | CAMP | CAMP | **VILLAGE** | **yes — this is the wave** |
| buildings | 2 (0 done) | 2 | **9 (7 DONE)** | yes |
| villagers | 0 | 0 | **7 (3 named)** | yes |
| lanterns in the feed | 7 | 11 | 11 | yes |
| core lux / grid points | 256 / 1 | 1 042 / 10 | 1 042 / 10 | yes |
| shop rows open now | 0 | 0 | **6 of 21** | **partly — see below** |
| regard | 0 | 0 | **15** | **no — 15 is below every band** |
| guns owned | 1 | 1 | **1** | no |
| kits in the pack | 2 | 0 | **0** | no |
| salvage | 70 | 149 | **292** | **no — still no sink** |

**And here is what a player sees.** `settle_shot --seed 1337`, the same camera, one flag apart —
the tier the player starts with against the tier they spend twenty-five minutes earning:

| | CAMP (`h2_camp.png`) | VILLAGE (`h2_village.png`) |
|---|---|---|
| buildings in the world | 2: **0 done**, 2 framed | 9: **7 DONE**, 2 framed |
| building triangles submitted | **8** | **112** |
| ground triangles (green + roads) | 138 over 2 meshes | 186 over 3 meshes |
| world triangles drawn | 829 | 948 |
| **what is different in the frame** | — | **one clad shed on the ridge** |

I rendered it at the tool's shipping standpoint at dusk and again at noon from 30 m out, and both
say the same thing: **the visible difference between the town you were given and the town you built
is one building.** 104 triangles of it. The other six DONE buildings are behind the ridge or beyond
the fog. That is not nothing — it is a real, clad, lit structure standing where there was grass —
but a player who walks 282 m at dawn to see what their four lanterns bought will see **one shed**.

**Two things I can prove do work, and one I could not.**

- **The town renders now.** THE_HOUR's display hour reported `settlement PEAK 0 tris, villagers
  PEAK 0 drawn` across 283 263 frames — the whole 5 162-triangle library sat in memory unasked-for.
  Standing in a Village, this tree reports **`settlement PEAK 576 tris, villagers PEAK 7 drawn`**.
  The art is finally on screen.
- **The shop works at VILLAGE tier.** `--demo 45 --town 1 --at-town --demo-ui --seed 1337`:
  `talks 1  trades 2 (0 refused)`, `own 2 mask 80`, held `BLKTHRN`. **This is a FIXTURE run and I am
  labelling it as one** (`--town N` boots the tier and the regard rather than earning them), so it
  proves the *path*, not the *reachability*.
- **I could not close that last link.** §0.4: my town-visit driver is broken and ARM WALK's is too,
  so I have no unfixtured trade. What I can put next to it is the earned Village's own offer table,
  read out of `npc_offer_open` on the real session at 60:00:

```
  row who    kind price tier regard  class     open-now
    0 MABEL     0     0    1      0  SERVICE   YES
    1 MABEL     0    40    1     32  SERVICE   no      <- a gun. regard 32. you have 15.
    2 MABEL     0    65    1     96  SERVICE   no      <- a gun. regard 96.
    4 MABEL     3     0    1      0  UNBUILT   YES     <- open, and UNBUILT
    5 MABEL     2    14    1      0  SERVICE   YES
    9 ODO       6     8    1      0  SERVICE   YES
   10 ODO       7    64    1      0  SERVICE   YES
   12 WICK      9    90    1      0  SERVICE   YES
   13 WICK     10    36    1    192  STOCK     no      <- THE LANTERN KIT. regard 192.
```

**Six of twenty-one rows open, one of the six is `NPC_OC_UNBUILT`, and neither gun and neither kit
is among them.** So: the town grew, seven people moved in, five of their doors opened — and the two
things the player actually wants, a second gun and a fifth lantern, are both behind a regard number
that the hour ends 17 and 177 short of.

**Did it FEEL like it grew? — and here I had a paragraph written that was wrong, so this is the
corrected one.** I was about to report that the promotion fires silently. **It does not.**
`client.hml:955-960` catches `set_tier_ever` rising and does exactly what the lantern beat does:
a `FONT_BIG` amber banner reading **`VILLAGE`** through `cl_banner`, and **`CSND_BELL` at full
volume** — the same bell that opens the game. There is a villager-arrival signal beside it, which
`DIRECTION.md` §6.2 calls *"the most legible possible signal that your lantern work mattered."*
**The best moment the game can now produce is announced, in words, once, with a bell, and I should
have read the code before writing the sentence.**

Two real gaps survive that correction, both small:

- **`client_promote_t` and `client_arrive_t` are exported, imported by `main.hml:355`, and read by
  nothing.** A 3-second `CL_PROMOTE_S` window exists to drive something the HUD never draws. Same
  shape as `g_REGEN_RATE` in THE_HOUR §5.3 — a tap that is plumbed and not connected.
- **The banner is three seconds of text over a landscape that gains one shed.** The signal is
  correct; what it points *at* is 104 triangles. That is the gap worth closing, and it closes by
  giving the player more posts to plant (§2.4), not by making the banner louder.

### 4. What is the single change that would buy the most minutes now?

> **Sell the lantern kit at ACQUAINTED instead of TRUSTED. One token, in one table, in one file —
> and it is simultaneously the second circuit, the salvage sink, and the reason to talk to anybody.**

**File:** `src/sim/npc.hml`, the `g_off_regard` table at lines 769–776. Row **13** — Wick, kind
`NPC_OFF_KIT`, price 36, tier VILLAGE — is the **second token of line 773**, which reads
`0, NPC_BAND_T_TRUSTED, 0,` (rows 12, 13, 14). **`NPC_BAND_T_TRUSTED` (192) → `NPC_BAND_T_ACQ` (32).**

**Why this one, argued from what I measured and not from the design document:**

1. **It is the only thing standing in 35 of the hour's 60 minutes.** Minutes 25–60 are frozen
   because the pack is empty. Both taps that could refill it are shut; this is the cheaper of the
   two to open, because the other one (`holds done` never reaching 2) is a difficulty question with
   a night-2 slaughter attached to it, and difficulty is a *tuning* problem where this is a *number*.
2. **32 is reachable, and I can show the arithmetic instead of guessing it.** The credits that
   actually fire in a session are `NPC_CR_PROMOTE` +15 (measured, at 25:00), `NPC_CR_MEET` +8 (one
   hello), `NPC_CR_TALK` +6 (one conversation per in-game day) and `NPC_CR_NIGHT` +3 (per completed
   hold — and this wave is what made it fire at all). **15 + 8 = 23 the day the Village appears;
   +6 the next morning = 29; +3 for the next night = 32.** So the door opens about **one in-game
   day (16 minutes) after the promotion — right where the hour currently goes flat**, and it opens
   because the player went and talked to somebody, which is the verb the whole settlement exists
   for. 192 is ~28 in-game days ≈ 7.5 hours and always was unreachable.
3. **It gives money its first sink, and the sink is thematically exact.** The hour ends holding
   **292 salvage** with nothing to buy — THE_HOUR said 220 and it is worse now because the player
   earns more. At 36 a post, 292 salvage is **eight lanterns**. *Carry the salvage home to a town
   that grows because you came back* stops being a sentence in a design document and becomes the
   transaction.
4. **There is somewhere for those posts to go, and it is already half-paid.** TOWN wants **32 grid
   points and 1 024 core lux**. The earned Village finishes on **10 points and 1 042 lux** — the lux
   threshold is *already cleared*. A wick-linked post inside the ring is worth 512 grid lux = 2
   points — measured: 4 posts + the Great Lantern = 5 rows = 10 points exactly. So **TOWN is ~11
   more posts ≈ 396 salvage ≈ 80 minutes of income** at the rate this hour measured (292 salvage in
   60 minutes). And the ring grows with the tier — `SET_RING_VILLAGE_M` is **120 m** against the
   Camp's 64 — so those eleven posts are spread over four times the ground. **That is a second
   circuit longer than the first, which cannot be rushed, and which the 16-minute promotion hold
   already paces.**

**Cost.** Zero triangles at rest. Eleven more `MESH_LANTERN` at 48 tris is **528 triangles worst
case**, and only if all eleven are simultaneously inside the fog radius. The display hour peaked at
**1 871 of 3 000** and `settle_shot` at VILLAGE draws 948. There
is room. Sim cost: none — `sv_lan_gather` is already O(entities) once per 60 ticks.

**What must be checked, and what would make this a lie if it were skipped.** `probe_lanfeed` must be
extended with a section that reaches **TOWN** in a real session with no fixture, or reports honestly
that it cannot — the same rule that file already imposes on itself. And it must be
sabotage-verified: put 192 back and confirm the new section goes red. **The `24 → 30` default in
`g_MINUTES` has to be fixed in the same change or the probe is red on arrival (§0.1).**

**Two alternatives I considered and rejected, with the reasoning on the record:**

- ***"Teach the player where the ring is."*** `probe_lanfeed`'s own §F nominates this, and it is
  real: nothing in the game ever mentions that a post is worth 512 grid lux inside 64 m and 0
  outside it. But the compass diamond already points home (`main.hml:2054`), the green is the
  obvious place to plant, and `SV_KIT_MIN_GAP_M` is only 12 m — so a player who walks home with four
  kits and puts them round the green **succeeds by accident**. It is the second thing to do, not the
  first, because it improves the odds of *reaching* the wall rather than moving it. When somebody
  does build it, it is cheap: **`client_settle_inside()` already exists** and `main.hml` already
  reads it to decide whether to draw the diamond, so "you are inside the ring" is a HUD state the
  client can already answer.
- ***"Fix `holds done` never reaching 2."*** It is a genuine regression against THE_HOUR (2 → 1) and
  somebody should look at it. But it is a difficulty-curve investigation with the night-2 cliff
  tangled into it, and its payoff is *two* kits an hour where the shop's payoff is *eight*.

---

## 3. WHAT IS WORKING — and this is not a courtesy paragraph

- **The four-kit design is genuinely elegant and I want to name it.** Two kits at the beat that says
  *there is a town over there*, two more for surviving a night, and four is exactly the number a
  Village costs. The player cannot be given the town at 0:58 and cannot be denied it after one
  night. `SV_OPEN_KITS + SV_HOLD_KITS >= 4` and `SV_OPEN_KITS < 4` are both asserted in
  `probe_lanfeed` §A so the arithmetic cannot drift. That is the second-best design decision in the
  repository after granting the Flare on the lantern beat.
- **The path points home now.** Six posts, nearest at **134.9–135.0 m from the green on all eight
  seeds**
  — solved from `SV_PATH_END_M` rather than typed — and the fallback branch is taken on
  **0 of 128** seeds. THE_HOUR's five lamps curving into empty fog are an arrow.
- **A probe that reaches its town through a real session finally exists**, and it says so on its
  first page in capitals. `probe_lanfeed`'s "NO FIXTURE. EVER. NOT ONCE." is the correct response to
  the `w.model` disaster, and it is why I could re-derive its headline in ninety seconds.
- **The town renders.** 576 settlement triangles and 7 villagers drawn, against THE_HOUR's `PEAK 0`.
- **The first minute is still excellent and still untouched.** Bell, line, camera standing up, three
  Wisps, `HOLD [E]`, the music stopping, the light, the horn.
- **It holds its budget with room to spare.** Display hour peak **1 871 of 3 000**; HUD now runs
  against the **334** cap `about-to-break` re-derived, where THE_HOUR ran at 248 of a 250 that was silently
  truncating text. **Every one of the eleven extra posts §2.4 asks for fits.**
- **The engineering walls are all green** on a tree with 1 718 uncommitted lines in it:
  `--selftest 25/25`, `ci_imports` **RULES 8/8**, `ci_unbox` `boxed=0` PASS.

---

## 4. HONEST GAPS AND BUGS FOUND (reported, not fixed — I own one markdown file)

1. **`tools/probe_lanfeed.hml` fails five of its own 130 assertions and exits 1 as it sits in the
   tree.** `g_MINUTES = 24`; the Village it asserts lands at 24:53. Not a false claim — a default
   that cannot reach it. **One integer.** §0.1.
2. **`holds done` reaches 2 in THE_HOUR and 1 here** — ARM POST, ARM WALK, ARM LAMP and ARM PLANT
   across 8 seeds all agree. Since `DIR_EV_HOLD_DONE` is now the *only* renewable source of the
   second verb's ammunition, a night that never clears is no longer just a difficulty problem.
3. **`probe_session.hml`'s ARM WALK is broken from 26:00** — 223 deaths, XP and kills frozen, in
   daylight. It is the same defect as mine (§0.4): a movement override that keeps steering a player
   it has disarmed. THE_HOUR flagged it at 45:00 and it has got worse. **Any future use of ARM WALK
   should be treated as unmeasured after minute 26.**
4. **`npc_offer_open` returns 1 for row 4, whose class is `NPC_OC_UNBUILT`.** One of the six doors
   the new Village opens leads nowhere. Cosmetic today; a player-visible dead end tomorrow.
5. **`client_promote_t` and `client_arrive_t` are imported by `main.hml:355` and read by nothing in
   `src/`.** The promotion's banner and bell do fire (`client.hml:955-960`); the 3-second
   `CL_PROMOTE_S` window they set up drives nothing. Same shape as `g_REGEN_RATE`, which THE_HOUR
   §5.3 found dead and which is **still dead** — I checked.
6. **Money still has no sink and it is worse**: 292 salvage at 60:00, up from THE_HOUR's 220,
   against six open rows priced 0/0/14/8/64/90 and no reason to buy any of them.
7. **The spell school is still one slot wide.** `spell_slots = 1 + Attunement/7`, Attunement 0,
   `spells granted 1` in every run including the display hour. Unchanged from THE_HOUR §5.4.
8. Cosmetic: `hemlockc` still warns `variable 'rc' shadows variable declared at line 4377` in
   `src/game/main.hml:4404`.

**And what I did not do, plainly.** I did not fix anything — I own `THE_HOUR_2.md`. I did not play
with a mouse or a keyboard. **I did not measure a talk or a trade in an unfixtured session, because
my driver broke (§0.4), and that is the biggest hole in this report.** I did not run
`replay --verify` (it wanted a compile I was not willing to spend against the display hour's frame
numbers). Everything here is **seed 1337** except `probe_lanfeed`, which is 8 seeds for the Village
timing and 128 for the path geometry.

---

## 5. THE SCREENSHOTS I LOOKED AT

720 PNGs at 5 s intervals from the `DISPLAY=:0` session, plus four `settle_shot` renders. Every
image below I opened and looked at; each carries its own stats line, which is the durable half.

| frame | t | what I saw |
|---|---|---|
| `ns_1_t6.png` | 0:06 | `SEEK`. Dusk, the unlit post downhill, `6/12`, `tri 1249/1808`. Unchanged and still good. |
| `ns_11_t56.png` | 0:56 | `WAVE 1`, five alive, `RELOADING`, acacias in silhouette against an ochre sky, the lantern viewmodel with its white core anchoring the bottom-right. This is the game at its best. |
| `ns_60_t301.png` | 5:01 | Night 1, `hp 10`, `alive 4`, `fog 26`. The hold, working. |
| `ns_120_t601.png` | 10:01 | Daylight, `alive 0`, `pos -51,-269`, `hp 10`, `fog 67`. Empty. |
| `ns_240_t1201.png` | 20:01 | `pos -52,-259`. |
| `ns_300_t1501.png` | 25:01 | `pos -52,-259`. **Same coordinate, five minutes later.** |
| `ns_360_t1801.png` | 30:01 | `pos -52,-259`. **Same coordinate, ten minutes after `t1201`.** A violet `NS_CORE` glow top-left is the only thing in the frame that is not terrain. This is THE_HOUR's finding, reproduced exactly, on the shipping driver. |
| `ns_600_t3001.png` | 50:01 | Night 4, `d 2` — the player is two metres from the lit post, and **it fills the centre of the frame with a white-hot core inside a warm halo.** This is `b996b41`'s lamp, in situ, and it reads as a light source rather than a decal. Best frame of the 720. |
| `ns_719_t3596.png` | 59:56 | **The last frame of the hour.** Noon, blue sky, acacias, the sun blown out behind the lantern post, `KESTREL 5/12`, `alive 0`, `hp 12`, `pos -45,-252`. Beautiful, and there is nothing to do in it. The seven previous frames are the same coordinate. |
| `town/h2_camp.png` | — | `settle_shot --tier 0 --seed 1337`: the town the player is given. Grass, a road, a dark framed sliver on the ridge. **8 building triangles.** |
| `town/h2_village.png` | — | The same camera at VILLAGE: **one clad building** on the ridge, upper left. **112 building triangles.** The entire visible reward for circuit one, in one frame pair. |
| `town/h2_camp_m.png` / `h2_village_m.png` | — | The same pair at noon from 30 m: the roads and plot lattice are visible on bare earth in both; the Village adds one grey clad shed with dark windows. Honest, and it reads as a building, not a box. |

---

## 6. ACCEPTANCE

Loadavg stated with every timing per **RULE T**.

| # | criterion | result | number |
|---|---|---|---|
| 0 | **RULE 0** before any measurement | **PASS** | `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` → `107`, `5120738502741017561` |
| 1 | THE_HOUR's own probe re-run **unchanged**, headless, compiled | **PASS (and RED, correctly)** | `nm \| grep -c SDL_` = 0; **`FAIL 26 / 31`**, exit 1, 1 m 50 s CPU at loadavg 3.25→5.12. **Five assertions failed and every one of them failed because the game got better** — see the box below |
| 2 | `probe_lanfeed` re-derived independently | **PASS** | 24:53 / 25:06 / 24:47 on seeds 1337/2/7 at `--minutes 40`, matching the author's report to the second; **red at its shipped 24-minute default** |
| 3 | a 60-minute display session | **PASS** | **305 852 frames in 3600.0 s**, 720 PNGs, launched at loadavg 2.38 |
| 4 | `--selftest` | **PASS** | `PASS 25 / 25` |
| 5 | `ci_imports.sh` R1–R8 | **PASS** | `RULES 8/8 checked`, `CI_IMPORTS PASS` |
| 6 | `ci_unbox.sh` | **PASS** | `targets=14 functions=521 scalars=79 boxed=0 warn=18` → `CI_UNBOX PASS` |
| 7 | `replay --verify` | **NOT RUN** | declared in §4. I would not spend a 1-minute compile against the display hour's frame numbers |
| 8 | triangle budget | **PASS** | display hour **PEAK 1 871 of 3 000**; HUD peak **294 of 334**; viewmodel 122; `settle_shot` at VILLAGE 948 |
| 9 | 60 fps floor | **PASS** | **85.0 fps**, render CPU **7.3 ms** (min of 7), **9.3 ms headroom**, **1.8 %** of frames over 16.67 ms, worst 43.7 ms |
| 9b | sim budget | **⚠ OVER, reported** | `sim+net: worst 3.1 ms of the 2.0 ms budget` over 216 001 ticks on a **quiet** box, `stalls 0 forgiven 0 decode-fail 0`. Better than THE_HOUR's 9.5 ms and still over. Not investigated; not mine |
| 10 | **LOOK at every frame I changed** | **N/A — I changed no frames** | I own one markdown file. `git status` gains exactly one entry from me: `docs/design/THE_HOUR_2.md`. My scratch driver lives in the session scratchpad and imports the repo by absolute path; nothing was added to `tools/`. I opened and looked at the 10 frames in §5 |

> ### THE FIVE RED ASSERTIONS, AND WHY A RED `probe_session` IS THE GOOD NEWS
>
> `probe_session.hml`'s header says its assertions are *"a STATEMENT OF WHAT IS, not of what ought to
> be. If a number here moves, the design moved, and this probe must go red rather than pass
> quietly."* It went red. Here is every failure and what it means:
>
> ```
>   FAIL [2]  ARM POST survived 1 nightly holds in the hour        <- REGRESSION (was 2). §4.2
>   FAIL [14] the settlement's lantern feed holds 7 rows           <- THE FIX. was 1.
>   FAIL [15] fed from `w.anim` instead, the SAME code finds 7     <- the shadow and the ship now
>                                                                     agree; the counterfactual is
>                                                                     retired
>   FAIL [24] the lamplighter lit exactly as many as the man who
>             never left                                           <- ARM WALK now places a kit
>   FAIL [28] and on 100 HP, with no regen                         <- it ended the hour on 100
> ```
>
> **Four of the five are the wave landing.** One is a real regression and it is the one that closes
> the loop. That is what a probe written as a statement of fact is *for*, and I am not going to
> "fix" someone else's file to make it green.

---

## 7. THE DISPLAY SESSION'S OWN REPORT

`nightshade --demo 3600 --scale 4 --seed 1337 --shots …` on `DISPLAY=:0`, one wall-clock hour.
**Loadavg at launch 2.38**, sampled 3.3 / 5.4 / 6.9 through the run — a far quieter box than
THE_HOUR's (28.38 at launch, 20–33 throughout), and the frame numbers should be read as *better
conditions*, not a renderer change. Demo time tracked wall time 1:1 (checked against file mtimes:
500 demo s in 500 wall s, 2 000 in 2 000).

```
nightshade: 305852 frames in 3600.0 s
   render, wall (STAT_T_FRAME)  mean 11.4 ms  worst 43.7 ms
   render, CPU  (RULE T, min of 7-frame batches)  7.3 ms
   headroom at 60 fps: 9.3 ms/frame on the CPU-time number
   whole frame  mean 11.8 ms -> 85.0 fps  (305852 frames in 3600.0 s of loop)
   frames over 16.67 ms: 5641 of 305852
   where the frame goes, mean: input+tick 0.3 ms (sim CPU 0.5)  render 11.4  body 11.8
   parallel emit: 4 workers
   triangles: PEAK 1871 of 3000   HUD peak 294 of 334   viewmodel peak 122
   sim+net: worst 3.1 ms of the 2.0 ms budget   ticks 216001
   stalls 0  forgiven 0  cmds 216000  packets 216001  decode-fail 0
   beat reached: PATH   lantern 1   path 5   sounds 4332
   unlock card: 0 truncated frames (MUST be 0)
   W6 town: CAMP lux 256/512  pts 1/10  buildings 2  villagers 0 (0 named)
   W6 draw: settlement PEAK 0 tris, villagers PEAK 0 drawn,
            town mesh library 5162 tris in 232 meshes
   W6 hand: melee 0  spells granted 1  casts 568  oil 30/100  points 3 unspent
   W6 panels: TRADE peak 0 tris, cap 334, open on 0 frames, 0 truncated strings
   W6 acts: swings 0  talks 0  trades 0 (0 refused)  points spent 0  lanterns fed 7
   W7 hands: held KESTREL (4)  own 1 mask 16  grants 1  adopted 1  denied 0
```

**Read `lanterns fed 7` and `W6 town: CAMP lux 256/512` together.** THE_HOUR's hour printed
`lanterns fed 1` and `lux 0/512`. The one-word fix in `b996b41` is live on a real display, in a real
hour, and it moved the town's feed from one row to seven and its lux from nothing to half of what a
Village costs. **And the town is still a Camp, still 2 buildings, still 0 villagers, and the
renderer still drew `settlement PEAK 0 tris` across 305 852 frames** — because the shipping demo bot
never walks the 282 m, and the four kits it is now given sit in its pack for fifty-nine minutes.

**Better than THE_HOUR on every frame number, and I will not take credit for it — the box was
quieter.** 85.0 fps against 78.7; **5 641 of 305 852 frames (1.8 %) over 16.67 ms against THE_HOUR's
24 449 of 283 263 (8.6 %)**; worst frame **43.7 ms against 82.0**; render CPU **7.3 ms** with
**9.3 ms of headroom** at the 60 fps floor. THE_HOUR ran at loadavg 20–33 with three other agents
compiling; this ran at 2.4–7.1 with one. **The 60 fps floor holds with room, and so does the
triangle budget: PEAK 1 871 of 3 000.**

**Two numbers I am not rounding down.**

- **`sim+net: worst 3.1 ms of the 2.0 ms budget`** over 216 001 ticks. THE_HOUR reported 9.5 ms on a
  loadavg-33 box and did not investigate; this is 3.1 ms on a quiet one, `stalls 0 forgiven 0
  decode-fail 0`. It is better and it is still over. `probe_simcost` §B2 (`about-to-break`) now
  measures the worst tick at the director's alive cap and should be the place this is settled.
- **`HUD peak 294 of 334`.** `about-to-break` raised that cap from 250 after finding the old one was
  silently truncating text every run. **This hour peaked at 294 — 44 triangles above the cap that
  shipped two days ago.** The raise was not cosmetic; without it this session would have been
  dropping HUD glyphs for an hour and reporting `0 truncated strings` while it did.

### The last forty seconds, verbatim from the log

```
ns_712_t3561.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 69
ns_713_t3566.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 70
ns_714_t3571.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 70
ns_715_t3576.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 70
ns_716_t3581.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 70
ns_717_t3586.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 71
ns_718_t3591.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 71
ns_719_t3596.png  pos -45,-252  d 15  hp 12  ammo 5/12  alive 0  fog 71
```

Eight consecutive frames, forty seconds, one coordinate — **the same ending THE_HOUR reported, at a
different coordinate.** The four lantern kits in the pack are what makes it different from last
time, and nothing in the game ever tells this player they are there.

### THE CROSS-CHECK

| | ARM POST, headless | game, `DISPLAY=:0` |
|---|---|---|
| beat reached after an hour | `PATH` | **`PATH`** |
| **lanterns in the settlement feed** | **7** | **`lanterns fed 7`** |
| settlement | CAMP, lux **256**, pts **1** | **`CAMP lux 256/512 pts 1/10`** |
| buildings | 2 | **2** |
| villagers | 0 | **`0 (0 named)`** |
| settlement triangles drawn | — | **`settlement PEAK 0 tris, villagers PEAK 0 drawn`** |
| spells granted | 1 | **1** |
| guns owned | 1 | **`own 1 mask 16`** |
| trades / talks | 0 / 0 | **`trades 0 (0 refused)` / `talks 0`** |
| unspent stat points | 3 | **3** |

Different binary, different frame rate (85.0 fps against a nominal 60), different renderer, different
process — **and every structural column matches exactly, including the two that changed this wave.**
That is the reason to believe the rest of this document.

---

## 8. WHAT THE NEXT AGENT SHOULD MEASURE

1. **The hour again, with a town-visit driver that works.** Mine and ARM WALK's are both broken in
   the same way (§0.4) and the consequence is that **nobody has yet measured a conversation or a
   trade in a town a player built.** That is the last unmeasured link in the fantasy sentence. The
   fix is small: a movement override must never suppress `BTN_FIRE`, must hand control back to
   `demobot.hml` on death, and must abandon a trip at dusk.
2. **`holds done` 2 → 1.** Why does night 2 never clear in this tree when it cleared at 56:00 in the
   last one, and is it the director ramp?
3. **And when §2.4 is built: report the new "last moved at" column for minutes 25–60, not estimate
   it.** That is the same instruction THE_HOUR left me, and it is the reason this document has
   numbers in it.
