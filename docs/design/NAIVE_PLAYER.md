# NAIVE_PLAYER.md — one session, told nothing

**Who wrote this.** An agent forbidden to read `docs/design/`, `src/sim/settle.hml`, or grep for
`settle_cx`. I read `CLAUDE.md` §2 to learn how to build and run, and nothing else about what any of
it means. Everything below is what I saw on a real screen on `DISPLAY=:0`, in the order I saw it.

**RULE 0.** `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` printed `107` then `5120738502741017561`.
PASS. Build: `hemlockc -O1 src/game/main.hml -o /tmp/ns`, 92.8 s, one shadowing warning at
`main.hml:5081`. HEAD `4e73611`, tree dirty with four other agents' work in it; I edited nothing.

---

## 0. FOUR THINGS THAT COMPROMISE MY NUMBERS, STATED UP FRONT

1. **I have no hands.** I drive the game through XTEST: screenshot → look → decide → send keys. One
   "beat" of mine is 1–2 seconds of wall clock. A human at 85 fps reacts in 200 ms. **Every death
   count below is inflated by my latency and you should discount it.** What is *not* inflated is
   what was on the screen at the moment I died, and that is what I report.
2. **I played with `--no-audio`.** The sound channel is a real teaching channel and I could not
   evaluate one second of it. If a Wisp growls when it is behind you, that fixes about a third of
   §5. Nobody should read my "there is no feedback" claims as covering audio.
3. **My first 40 minutes were contaminated.** Another agent was running `/tmp/ns_gate --demo 1560
   --headless` and *it opened an X window on `:0` at the same geometry as mine*, on top of mine. For
   a while I was screenshotting and typing into their demo bot's game. I found it, moved my window,
   pinned my captures to `WM_CLASS ("ns" "ns")`, and re-ran everything. **Nothing below comes from a
   frame taken before that fix.** (It is also a real finding for whoever owns the shot rigs:
   `--headless` still creates a mapped window.)
4. **§2–§4 use dev flags.** Playing straight, I never reached the settlement with a kit in my pack,
   so I could not answer "did you work out where to plant it" honestly by playing. I therefore ran
   `--at-town --kits N` and `--town 2` and evaluated the teaching signals with naive eyes on the
   state the game handed me. Where I did that, I say so.

---

## 1. WHAT I THOUGHT THE GAME WANTED, MINUTE BY MINUTE

### T+0 — the terminal tells you the whole game. The screen tells you nothing.

Launching from a shell prints a 40-line banner: the full keymap, "THE FIRST SIXTY SECONDS", and
"AFTER THAT". It even says *"Every lantern you light inside its ring raises CORE_LUX."* That banner
is the best teaching artefact in the build **and it is not in the game.** It scrolls past in a
terminal the player may not even have open. It also lies by omission in the exact place my task
cares about: it says **light**, four times. It never once says you can **plant**.

The first frame on screen: purple sky, a compass strip, a gold diamond under it, a green bar reading
`100`, `KESTREL 6 / 12`, and a lantern held in the right hand. No title card. No "you wake on your
back". No prompt of any kind. I was looking straight up and nothing told me to look down. I guessed.

### T+0:10 — I looked down and read the diamond as "go here". That guess was right.

Pitching down put a horizon on screen and the gold diamond onto a fixed row just under the compass.
It tracks with yaw, so it is unmistakably a world-space objective marker. **This is the single best
navigational affordance in the build** and I trusted it within ten seconds without being told
anything. It later turned out to be correct: sprinting at it for ~50 s took me across the map to the
settlement. Good. Keep it.

### T+0:12 → T+0:30 — I thought the game wanted me to look at the view. It wanted me to run.

I stood still and turned in place to survey. Health went `100 · 100 · 100 · 100 · 100 · 100 · 100 ·
100 · 94 · 82 · 76` over about eleven seconds and then to zero. **In not one of those frames was
there anything on screen that had hit me.** No hit-direction indicator, no flinch, no red arc, no
number. Just the bar going down.

I ran a controlled test later: `--no-audio`, sprint held continuously with a heading correction every
~1.2 s. **39 consecutive beats, ~50 s, health pinned at 100, zero damage taken.** Standing still at
spawn kills you in 15 seconds; running is free. The game never says this and there is no readable
cue that would let you infer it.

### T+0:35 — I died. I did not know I had died.

The only three cues are:
- the number reaching `0`;
- **the whole frame washing pink-red** — which, at dusk, under an orange sky, is indistinguishable
  from "the sun set a bit more". I logged it as a lighting change for three deaths in a row;
- the camera dropping to ankle height, which reads as "I fell into a ditch".

There is no text, no fade, no "you died", no respawn beat. I only proved I was dying by cropping the
health bar out of ten sequential screenshots and reading `0 · 0 · 88 · 70 · 40 · 40 · 22 · 0 · 0 · 0`
off the strip. **A player will not do that.** Between T+0:35 and T+2:10 I died at least five times
believing I was merely having a bad time.

### T+1:20 — I finally found the thing killing me, by looking at my own feet.

I pitched the camera 100 % down. A Wisp was standing *inside* me — a purple body filling a third of
the screen — with two more behind it. **The Wisps sit below the pitch a player naturally holds.**
Looking at the horizon, which is what you do when you are trying to navigate, they are invisible at
melee range. They are also invisible at distance: in the 8-yaw survey they render as ~6-pixel dots.

### T+1:25 — I shot it point-blank and could not tell whether I hit it.

Crosshair on the body, three shots (`6/12 → 5/12 → 3/12`). No hitmarker. No crosshair colour change.
No flinch, no knockback, no particle, no damage number. It killed me. **I still do not know whether
those bullets connected.** The banner promises "they die to one shot each"; my screen refused to
confirm or deny. This is the single most damaging feedback gap in the combat loop: without a hit
signal, a new player cannot tell "I am missing" from "this thing is tanky" from "my gun is broken",
and all three lead to different (and in two cases wrong) conclusions.

Note the contrast: in frames I accidentally captured of another agent's demo bot, **the crosshair
turns red on target and prints `RELOADING`.** So a hit/target state exists somewhere. It did not fire
for me.

### T+2:10 — the promised beacon is not where the banner says it is.

The banner: *"Forty metres downhill there is an unlit lantern on a post — the brightest thing you can
see."*

I surveyed the spawn twice: **8 yaws at horizon pitch, then 8 yaws pitched ~15° down. Sixteen views.
Zero lantern posts.** The crest I wake on occludes it. It is a real object and it is a *good* one —
when I later crossed the ridge it appeared as a tall post with a warm glowing head against the
skyline and read instantly as "go there, that is the thing" — but **at T+0, from the pose the game
puts you in, the promised beacon does not exist on screen.** The one thing the design leans on to
teach the first verb is behind a hill.

### T+2:10 → T+3:00 — the death loop, and why it is not just my latency.

Dead → respawn at spawn → 15 s to be killed again → repeat. Because respawn puts you back at the
start, every metre I walked was erased. Over one 14-second window the frames are pixel-identical
across four samples while the wave counter climbed `0 → 2 → 4 → 6 → 7`. Net progress: zero.

My reaction time makes this worse than it is for a human. But two parts of it are mine to report and
not my harness's fault: **respawn puts you back at square one with no message**, and **the wave
counter keeps climbing while you are dead**, so the world gets harder while you are learning it.

### T+3:00 — night falls and the game is beautiful and I have no light.

I am carrying a lantern in my right hand. It illuminates nothing. The world goes to deep blue-green
with a fat pixel moon and it is genuinely, unironically lovely — I stopped to look at it, which is
the nicest thing I can say about any frame in this build. But the fantasy is *"you push the dark back
one lantern at a time"* and at minute three I am standing in the dark holding a lit lamp that pushes
nothing.

### Where I was wrong, and what misled me

| I believed | Because | Truth |
|---|---|---|
| The pink-red wash was dusk | It looks exactly like the dusk sky | It is the death screen |
| Standing still was safe | Nothing said otherwise | It is the only way to die |
| Nothing was attacking me | Nothing was on screen | Wisps sit below your pitch |
| My shots were connecting | Crosshair was on the body | Unknown — the game will not say |
| The lantern post would be visible | The banner said "brightest thing you can see" | Not from spawn, in 16 views |
| The diamond was the lantern | It is the only marker | It is the settlement, ~50 s away |

---

## 2. DID I WORK OUT THAT I CAN PLANT A LANTERN?

**Playing straight: no. Never. Not once did the game hint the verb exists.** In roughly 25 minutes of
live play across five clean runs I saw: a compass, a diamond, a health bar, an ammo counter, a
weapon name, and a wave counter. Nothing else. No kit icon (I had no kits), no prompt, no dialogue,
no world label. The word "plant" did not appear on my screen at any point.

**The moment a kit is in the pack: instantly, in under two seconds, with no ambiguity.** I booted
`--at-town --kits 2` and the very first frame after I pitched to the horizon said:

```
              [E] PLANT A LANTERN POST
                  2M TO THE REACH
```

plus **two small gold kit icons** in the corner above the weapon. That is a good prompt. It names
the key, names the verb, names the noun, and carries a live number. Whoever wrote it: this works.
I understood the verb faster than I understood how to look down.

**So the gap is not the verb. The gap moved.** It is now **kit acquisition**, and it is total:

- Pip, a named villager standing in a TOWN-tier settlement, says exactly one line — **"YOU CAME
  BACK."** — and `X` does not advance it. I pressed `X` four times and got the same line four times.
- Pip's stall (`T`) offers three rows: **`ALMANAC –`**, **`CHARM –`**, **`CHARM –`**, and a footer
  `X NEXT   C TAKE`. No prices, no descriptions, no quantities — the `–` is where a number should
  be. **No lantern kits.** A player who found this panel would learn nothing from it and leave.
- I never found a kit in the world, in a barrel, on a corpse, or as a drop.

`probe_lanfeed`'s complaint has been half-answered. It said a human with four kits cannot learn where
to put them. That is now largely fixed. What it did not say, and what is now the binding constraint,
is that **a human cannot get the first kit at all**, and the one NPC I reached has one line of
dialogue and a shop full of dashes.

---

## 3. DID I WORK OUT WHERE TO PLANT IT SO IT COUNTS?

**Yes — but only from the HUD, only while standing near the boundary, and only because the game
tells you the answer instead of letting you see it.**

What works, and works well:

| state | text | colour |
|---|---|---|
| outside, near | `2M TO THE REACH` | white/grey |
| inside | `INSIDE THE REACH` | **gold** |
| planted inside | `THE GRID TAKES IT` → `POST SET` | **gold** → grey |
| planted outside | `50M OUTSIDE THE REACH` | grey |

The binary is unmissable and the metres are honest. Colour does the valence work. I walked out, the
line went white and counted up; I walked back, it went gold. **I learned the rule by walking, which
is the correct way to learn a spatial rule.** That is real design and it deserves the credit.

Now the five things wrong with it, in order of how much they cost:

**3a. The ring is never drawn.** Not once. There is a gold world-space label reading
**`THE LANTERN'S REACH`** — I saw it **exactly once in about forty screenshots**, from one specific
vantage on the way back into the camp. Standing inside the reach and doing a full 8-yaw survey with a
kit in hand: **zero labels visible in any direction.** The exit telemetry says `reach PEAK 27 marks`
for that run, so twenty-seven of them were submitted; I could see one of them, once. A single floating
noun that appears at one spot does not read as "this is the edge of a circle" — it reads as "this
particular spot is called the lantern's reach", which is a completely different and wrong idea.

**3b. "Reach" and "grid" are never defined.** `THE GRID TAKES IT` is a lovely line and I have no idea
what the grid is. There is no grid on screen, no grid in the HUD, no grid in any panel. Same for
"the reach": I inferred it means "the circle inside which this counts" purely from the fact that the
message changed colour when I crossed it. That inference is available to a careful player and
unavailable to a distracted one.

**3c. The ring silently changes size.** At CAMP the ring is 64 m. At TOWN it is 200 m. **The HUD uses
the identical word in both cases** and nothing announces that the thing you learned last night is
three times bigger tonight. A player who internalised "about sixty paces" is now wrong and has no way
to find out except by wasting kits.

**3d. Planting outside costs you a kit with no warning and no verdict.** The message
`50M OUTSIDE THE REACH` is *information*, not *failure*: grey, factual, no "wasted", no "nothing
happened", no shake, no sound I could hear. Compare it to gold `THE GRID TAKES IT`. A player could
easily read the pair as "two kinds of success". The kit is gone either way.

**3e. Worst of the five: the prompt disappears but the action does not.** Far outside the reach the
entire `[E] PLANT A LANTERN POST` block vanishes from the HUD — I verified this on the cropped frame
immediately before I acted. **`E` still plants, and still consumes the kit.** So the game teaches
"no prompt means you cannot do this here", and then punishes you for believing it. Either keep the
prompt visible at all distances with a red/grey `50M OUTSIDE THE REACH`, or refuse the input.

**One more, from talking to Pip:** standing next to an NPC replaces the plant prompt with
`[E] PIP / [T] TRADE`. `E` is overloaded. If the ring's best spot happens to be where a villager is
standing, the verb quietly becomes unavailable and nothing says why.

---

## 4. WHAT I DID THAT THE GAME DID NOT REWARD, AND WHAT I NEVER THOUGHT TO TRY

**Did, unrewarded:**

- **Surveyed the spawn carefully, twice, at two pitches.** Cost me most of my health for zero
  information. The game's answer to "look around before you move" is "die".
- **Aimed and fired at an enemy.** No hit feedback of any kind. Silence is the reward.
- **Stood still to read the HUD.** Fatal.
- **Pressed `TAB` to open the character sheet** while dead — nothing happened, no "not now", no
  sound, no greyed panel. I could not tell whether `TAB` was the wrong key or the wrong moment.
- **Pressed `X` four times at Pip** expecting a topic ladder. Same line every time.
- **Walked into the "settlement"** via `--at-town` and found empty hills. At TOWN tier the telemetry
  says 17 buildings and 14 villagers; from the spawn `--at-town` gives you, **an 8-yaw survey shows
  zero buildings and zero villagers.** You have to sprint ~12 beats before the first longhouse
  crests. (When it does, it is good: dark timber, big roof, a stone wall, a path. And the villagers
  — teal robes, conical hats, standing about — are charming.)

**Never thought to try, and would not have:**

- **Planting a post at all**, until the game put a kit in my hand and told me.
- **Sprinting continuously as a survival strategy.** Nothing suggests movement is defence.
- **Melee (`V`) or the flare (`C`).** I never earned them and never learned they were on the table.
  The FLARE bar exists — I saw it on another instance's HUD — and I never saw it on mine.
- **Reloading (`R`).** I fired the Kestrel dry more than once and only ever saw the number drop.
  There is a `RELOADING` string in the build; it never appeared for me. I assumed the gun was
  auto-managing and it may well be — I still don't know.
- **Looking for the reach boundary by walking a circle.** It would not have occurred to me that a
  boundary existed until the HUD said `2M TO THE REACH`.

---

## 5. EVERY MOMENT I WAS CONFUSED, BORED, OR STUCK

Timestamps are elapsed within the run named. `R6`/`R8`/`R9`/`R11`/`R13` are the clean runs (post-fix).

| when | state | what happened |
|---|---|---|
| R6 T+0:00 | **confused** | Woke facing straight up. No prompt, no card, no instruction. Guessed to look down. |
| R6 T+0:12 | **confused** | Health falling with nothing on screen. No direction indicator. |
| R6 T+0:30 | **confused** | Screen went pink. Read it as sunset. It was death. |
| R6 T+0:35 | **stuck** | Respawn with no message; I did not know a respawn had occurred, so I could not reason about position. |
| R6 T+1:20 | **confused → relieved** | Pitched 100 % down and found a Wisp inside my own body. First time I understood what an enemy looked like at range zero. |
| R6 T+1:25 | **confused** | Three point-blank shots, no hit feedback, dead. Could not tell if the gun works. |
| R8 T+0:00–0:40 | **stuck** | 16-view survey of spawn, no lantern post found, health drained to 0 twice during the survey. |
| R8 T+0:40 | **bored** | Third identical death loop. Nothing was changing; I was learning nothing per attempt. This is the point a real player quits. |
| R9 T+0:00–0:50 | **good** | Sprinting at the diamond. Full health for 50 s, terrain and light changing, actually enjoyable. |
| R9 T+0:52 | **stuck** | Walked into a hillside I could not read as a wall. Sprinted into it for ~35 s while the heading readout sat frozen at the same pixel. Nothing on screen says "you are against geometry" — no bump, no camera shake, no speed cue. |
| R11 T+0:04 | **taught** | `[E] PLANT A LANTERN POST / 2M TO THE REACH`. Understood the whole verb in one frame. Best moment in the session. |
| R11 T+0:25 | **taught** | Walked until the line flipped to gold `INSIDE THE REACH`. Understood the rule by moving. Second best moment. |
| R11 T+0:50 | **confused** | Kept walking out; the prompt vanished entirely rather than counting up. Lost the thread of where the boundary was. |
| R11 T+1:30 | **confused** | Saw `THE LANTERN'S REACH` floating in the world exactly once. Assumed it named that spot, not a circle. Never saw a second one. |
| R11 T+2:00 | **taught, then confused** | `THE GRID TAKES IT` — I knew I had succeeded, and had no idea what a grid was. |
| R11 T+2:00 | **confused** | Planting rooted me for ~2.5 s; health went 100 → 34 during it. I never saw what did it. Good risk design, invisible attacker. |
| R11 T+3:10 | **confused** | Planted the second kit at 50 m out with **no prompt on screen at all**, and it consumed the kit and told me afterwards. |
| R13 T+0:00 | **confused** | `--town 2`: 17 buildings, 14 villagers, and an 8-yaw survey showing empty hills. |
| R13 T+0:35 | **delighted** | First longhouse cresting the hill under a fat moon. This looks like a game I would want to play. |
| R13 T+0:55 | **delighted** | Five villagers in teal robes and conical hats standing around a stall. |
| R13 T+1:05 | **bored** | Pip: `YOU CAME BACK.` `X` ×4, same line. |
| R13 T+1:10 | **confused** | Pip's stall: `ALMANAC –`, `CHARM –`, `CHARM –`. Three unexplained nouns and three dashes. No prices, no effects, no kits. Closed it having learned nothing. |

---

## 6. WHAT IS ACTUALLY GOOD — said plainly, because a critic who can't tell good from bad is useless

1. **The plant prompt is excellent.** `[E] PLANT A LANTERN POST` + live distance + a gold/white
   inside-outside flip is a complete, wordless teaching device. It taught me a verb and a spatial
   rule in about thirty seconds with no manual. It is the best-taught thing in the build by a
   distance.
2. **`THE GRID TAKES IT`** is the right *kind* of line — warm, short, a little proud, and it made
   planting feel like it mattered. Define the noun and keep the line.
3. **The compass diamond just works.** I trusted it in ten seconds and it was right. Fifty seconds
   of sprinting at it crossed the map.
4. **The kit icons in the corner** are unambiguous: two icons, plant, one icon. I never had to
   wonder how many I had.
5. **The night is beautiful.** Deep blue-green terrain, a fat pixel moon with visible maria, warm
   orange embers drifting. I stopped playing to look at it, twice.
6. **The settlement, once you reach it, reads as a place.** Dark timber longhouse, big overhanging
   roof, stone wall, a worn path, teal-robed villagers with conical hats. It looks like somewhere
   worth carrying things home to. The fantasy is *in there*.
7. **Sprinting outruns the Wisps.** There is a real, learnable movement rule underneath the combat —
   it is just never signalled.

---

## 7. THE FIVE FIXES I WOULD PUT ABOVE ALL OTHERS

Ordered by how much of my session each one would have saved.

1. **Tell the player they died.** Two words, one second, centre screen. Right now death is a colour
   grade that looks like weather. Everything I misread in minutes 0–3 cascades from this.
2. **Give the gun a hit signal.** A crosshair flick, a flash, anything. Without it a new player
   cannot distinguish "I missed" from "it's tanky" from "the gun is broken", and picks wrong.
3. **Make the kit reachable.** Right now the verb is beautifully taught and completely unobtainable.
   One NPC row, in a stall that shows a price and a sentence of what the thing does, would close the
   whole loop. `ALMANAC –` teaches nothing.
4. **Draw the ring, or keep the readout alive at every distance.** Pick one. Twenty-seven marks that
   are visible once out of forty frames is worse than either. And when the ring grows 64 m → 200 m,
   say so.
5. **Never let `E` spend a kit while the prompt is hidden.** Either show `50M OUTSIDE THE REACH` in
   red at all distances, or refuse the press. Teaching a rule and then breaking it is the one thing
   worse than not teaching it.

---

## 8. THE HONEST BOTTOM LINE

> The second verb is taught. The first minute is not, and the kit that the second verb needs cannot
> be obtained by a player at all.

`THE_HOUR_2` reports eight of eight seeds reaching VILLAGE at ~24:53 with four player-planted posts.
I believe it. Every one of those posts was planted by something that already had four kits in its
pack and already knew where the ring was.

**I played for about twenty-five minutes and never held a kit I was given by the game.** I never lit
the tutorial lantern, because from the pose the game puts me in it is behind a hill, and standing
still to look for it is fatal, and dying does not tell me I died. I reached the settlement exactly
once, by sprinting at a diamond for fifty seconds, and when I got there the one villager I could talk
to said `YOU CAME BACK.` and sold me `CHARM –`.

The discoverability work is real and it lands. It landed on me in under two seconds. It is simply
sitting on the far side of a first minute that has not been taught at all, and behind an acquisition
step that does not exist yet.
