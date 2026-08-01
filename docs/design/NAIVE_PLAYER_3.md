# NAIVE PLAYER 3 — a player who was told nothing, for a full hour

One session, 3663.3 s of game loop, 311 223 frames, one seed (1337, the default). I read
`CLAUDE.md` RULE 0 and §2 and nothing else. I did not open `docs/design/`, I did not open `src/`,
I did not run `--help`, and I did not read a byte of the game's stdout until after I had killed the
process at t = 3663 s. Everything in sections 1–6 is what I could see on the screen. Section 7 is
what the game's own exit report said afterwards, and it is marked as such.

`hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` printed `107` then `5120738502741017561`.
Loadavg at session start `0.30 / 0.99 / 1.79`; at session end `5.83 / 5.55 / 5.15`.

---

## 0. HOW I DROVE IT, AND WHAT THAT COSTS THE MEASUREMENT

Read this first. Two of my findings are partly artefacts of the driver, and one number I nearly
reported was wrong.

**The rig.** `python-Xlib` + XTEST against `DISPLAY=:0`, a real 1280×720 window found by
`_NET_WM_PID` so I could never touch another agent's game. Stills are `import -window <id>`, which
is per-window. Video is `ffmpeg -f x11grab` of a *screen rectangle*, which is not — one frame in
`vid3/` has another agent's window composited into the corner. The dead/alive classification below
came from x11grab frames and I eyeballed every transition frame before trusting the count.

**Cost 1 — I was not always at the controls.** The game runs between my turns. Twice early on it
ran with no input at all: 50 s at t ≈ 16–76 and 44 s at t ≈ 104–148. Both gaps ended with me
badly hurt or dead. A human is never idle for fifty seconds. **The first two deaths in this report
are mine, not the game's**, and I say so where they appear. Everything from t = 1100 s onward is
continuous driven play in 20–100 s bursts.

**Cost 2 — the pointer is grabbed, and my turns were being eaten.** SDL confines the cursor to the
window, so XTEST *relative* motion silently stops the moment the pointer pins against a window
edge. I found this at t = 846 s when three consecutive `+100` turns produced three identical frames;
`query_pointer` returned `2359, 392`, which is exactly the top-right corner of my window. **For the
first fourteen minutes an unknown fraction of my mouse input did nothing**, which is why my early
navigation reads as flailing. It partly *was* flailing.

The fix, and it is clean: **the help modal swallows mouse deltas**, so I open F1, warp the pointer
back inside the window, and close F1. Verified rather than assumed — the compass ticks sit at
`x = 571` and `x = 741` before the reset and at `571` and `741` after it, unchanged
(`shots/cc0.png` vs `shots/cc1.png`).

**Calibration, so the angles below mean something.** 100 mouse units = 48 px of compass travel;
adjacent compass ticks are 181 px apart; **≈ 8.4 mouse units per degree**. Reversible: `+100, +100,
−200` returns the ticks to the pixel (`shots/cb0..cb3.png`).

**A detector of mine that lied, caught before I wrote it up.** At t = 1647 s I swept a full 360° in
twelve steps and cropped the top 50 px of every frame to read the compass. **No objective marker
appeared in any of the twelve** (`m_sc.png`), and I was about to report "the objective marker
disappears permanently". It does not. The marker is drawn *below* the bar, at y ≈ 36–80, when it is
out of range; my crop cut it off. Re-cropped at 95 px it is present in every single frame
(`m_se.png`, `m_sj.png`). The compass finding I *do* report in §5 is from the 95 px crops only.

**A number I read wrong and corrected against myself.** At t = 148 s the health bar read a green
`100` where it had read a red `10` forty-four seconds earlier, and I wrote down "health
regenerates". It does not follow: I was dead and respawned inside a gap I wasn't watching. I only
caught it when I later ran **90 continuous seconds at 4/100 with no recovery whatsoever**
(`m_l.png`, `m_n.png`). Then at t ≈ 2687 s I watched 82 → 100 inside 25 s with no death
(`m_tf.png`). **Both are real and I cannot reconcile them.** I never formed a working model of how
I heal, in an hour, and that is itself the finding.

**Discarded.** Two throwaway launches of ~30 s each before the real session, to prove the rig moved
the camera. From them I learned that WASD and the mouse work and that there is a compass with a
diamond on it — things every FPS player assumes before the window opens. The hour is a third,
fresh launch. Its first frame is `shots/b00.png` at window-map + 0.03 s.

---

## 1. WHAT DID DYING COST ME?

**Nothing I could see. Not once, in about seventy-eight deaths.**

I measured the death cycle instead of eyeballing it: 220 frames of x11grab at 10 fps through the
loop at t ≈ 1200 s, classified by mean(R) − mean(B) because the death screen is a flat sepia wash
(dead ≈ 32.2, alive ≈ 1.1–9.4, no overlap anywhere in 220 frames).

```
  dead   frames  36– 75   =  4.0 s
  alive  frames  76–118   =  4.3 s
  dead   frames 119–158   =  4.0 s
  alive  frames 159–201   =  4.3 s
  dead   frames 202–220   =  ...
```

On the respawn frame (`vid/f_076.png`, and the same again 8.3 s later):

| | before death | on respawn |
|---|---|---|
| health | 0 | **100** |
| ammo | 6 / 7 | **6 / 7** |
| weapon | KESTREL | KESTREL |
| wave readout | `WAVE 1  10` | `WAVE 1  10` |
| camera | that ridge, that tree | **the same ridge, the same tree** |

Respawn is *in place*. There is no banner naming a loss, no number that ticks down, no line about
what the dark kept. I did not go back for anything because nothing was taken from me.

Two consequences a designer should hear plainly:

**(a) The price only bites someone who is carrying something, and nothing in the first hour gave me
anything to carry.** The game's own exit report says `kits in pack 0`, `lanterns fed 1`,
`points spent 0`, `trades 0`. I finished the hour with exactly what I started it with, minus eight
rounds. If the ledger charges you for what is in your pack, then a player who never finds a pack
never learns there is a price. I never even learned there *was* one.

**(b) Dying is the best healing item in the game.** I spent minutes at 4/100 with no way to get it
back. Every death handed me 100/100 in four seconds, in place, with my gun still loaded. At
t = 1113 s I died at 4 HP and stood up at 100 HP three metres from a lantern
(`m_pb.png`) — the death was, straightforwardly, an upgrade. **That is the opposite of a price, and
it is the single loudest thing the death screen taught me.**

What the death screen *does* do, and does very well: it is unmistakable, and it takes the controls
away. I issued eight consecutive look commands across `e0`–`e7` and the view did not move by a
pixel. As a player I did not need to be told; the frame simply stopped answering. `THE DARK TOOK
YOU / YOU GET UP AGAIN` over a sepia wash with the HUD gone is legible in one glance at 1280×720,
and the amber progress bar under it told me, without a word, that waiting was the whole
interaction.

---

## 2. COULD I TELL WHERE DANGER WAS COMING FROM, INCLUDING ABOVE ME?

**Above: the question never arose. Nothing attacked me from above, ever, in one hour.**

**Below: yes — after twenty-one minutes and a deliberate experiment, not from the cue.**

The honest sequence:

- **t = 76 s.** First damage. Health 22, red vignette, and *two* dark-red rectangles floating near
  the crosshair — one above it, one well below it (`shots/c00.png`). I read that as "you are being
  hurt", not as a direction. Nothing was visible on screen to shoot.
- **t = 210–300 s.** In the death loop. Four red segments lit **simultaneously** — up, down, left,
  right (`shots/f7.png`, `shots/pd4.png`). Four arrows pointing four ways is not a direction, it is
  a shrug. I did not look down, because up-left-down-right does not say down.
- **t = 1304 s.** I finally pitched the camera down 180 units as an experiment. **Five or six blue
  creatures were standing on my feet**, filling the lower half of the frame
  (`shots/qa1.png`, `qa2.png`). From a level view, at the very same instant, they are *completely
  invisible* — not small, not dim, **not in the frame at all**.
- **t = 2687 s.** One attacker instead of six, and the cue works perfectly: a single red bar to the
  **left** of the crosshair, health 100 → 82 (`m_tf.png`). I turned left. It was there.

So: **the direction segments are correct and readable when one thing is hitting you, and say
nothing at all when four are.** That is not a bug in the segments; it is that the situation the
segments were built for (one attacker, off-screen bearing) is not the situation this game actually
puts you in at night.

**The one cue I missed, and I want to be precise about why.** There *is* a small T-shaped mark at
the bottom-centre of the frame on damage frames — about 20 × 14 px, dark red
(`shots/c00.png` at (640, 650); `shots/pd4.png`; `vid/f_080.png`). It is present when I am level and
absent when I am pitched down at the swarm, so it is doing exactly its job. **I read it as part of
the damage vignette for twenty-one minutes.** It is dark red, it sits in the bottom sixteen pixels
of the frame, and at that moment the bottom of the frame is already a solid red damage band. The
cue is drawn on top of the one colour that hides it.

---

## 3. HOW LONG UNTIL I UNDERSTOOD WHAT THE GAME WANTED, AND WHAT TAUGHT ME?

| when | what happened |
|---|---|
| **0.8 – 2.1 s** | `THE LAMPS WENT OUT ON A TUESDAY`, white on black, over a slow camera drift. Told me the *tone*, immediately and well. Told me no task. |
| **~5 s** | First person. A lantern in my hand, `100` health, `KESTREL 6 / 12`, `F1 CONTROLS` top-left, a compass with a diamond on it. |
| **84 s** | **`AN UNLIT LANTERN` / `5M`** on a post ahead of me (`shots/c02.png`). **This is the moment I understood the game.** Three words and a distance: the lamps went out, here is a lamp that is out, I am the one with the lamp. I had the entire premise in one glance and I never needed it explained again. |
| **88 s** | `AN UNLIT LANTERN / 12M`. I had walked straight past it. **The prompt names the noun and the range and not the verb.** There is no `[E]`, no `HOLD E`, no key of any kind on it. I did not know there was anything to press. |
| **674 s (11 min 14 s)** | Pressed F1 for the first time, after four deaths. Read `HOLD E — USE`. **Nine and a half minutes between understanding what the game wanted and being able to do it.** |
| **728 s** | `TAB` → the CHARACTER sheet. `0 PTS`, and `HND CAP LAN VIT ATT` all zero. |
| **1149 s** | Held E at `AN UNLIT LANTERN / 3M`. Died 0.6 s in, before the hold completed. Never got another one. |
| **end of hour** | Lanterns lit by me: **0**. Kits planted: **0**. Villagers met: **0**. Trades: **0**. |

**What taught me was the diegetic label on a real object in the world, at 84 seconds.** Not the
banner, not the controls card. The banner set the mood; `AN UNLIT LANTERN` set the *game*. That is
the design working exactly as intended and it is worth saying loudly.

**What failed was the eight-second gap between the noun and the verb.** A player who reads
`AN UNLIT LANTERN` and keeps walking has not failed to understand the fantasy — he has failed to
find a keystroke. Putting `HOLD E` on that same card is a two-word fix that would have moved my
whole hour.

**And the controls card is a keymap, not a purpose.** Both pages are beautifully legible — nine
rows, then eleven, gold key on white verb, no truncation at any width I saw. But `HOLD E — USE` and
`C — CAST` and `1-8 — GUNS` tell me the alphabet, not the sentence. I finished the hour knowing
every key and never once knowing what I was supposed to be *doing next*. Two of those rows are
advertising verbs I did not have: I pressed `1`, `2`, `3` and nothing happened and nothing said why
(I owned one gun); I pressed `C` and nothing happened and nothing said why (I had no spells); I
pressed `T` and nothing happened and nothing said why (no villager). **Three silent no-ops in a row
is how a player concludes the game is broken.**

---

## 4. THE FULL HOUR — WHEN DID I STOP WANTING TO CONTINUE?

**Twice, for two completely different reasons.**

**First, at t ≈ 290 s (4 min 50 s), inside the death loop.** Dying every 8.3 seconds, in place,
with no invulnerability on respawn and no way to break it. I could not turn, could not run, could
not find the thing killing me. That is the closest I came to closing the window. I got out at
t ≈ 474 s by holding shift+W through eleven consecutive respawns until I outran the cluster.
It worked, but I did not *learn* anything from it — I escaped by mashing.

**Second, and permanently, at t ≈ 2424 s (40 min).** I was sprinting toward a centred compass
diamond across the fifth identical green hill. Three consecutive 75-second sprints
(`m_tc.png`, `m_td.png`, `m_te.png`) produced the same ridge, the same acacia, the same brown
scar. **The last genuinely new thing the game showed me was the CHARACTER sheet at 12 minutes.**
From minute 12 to minute 61 I saw no new noun: no villager, no building, no lit lamp, no item on
the ground, no second weapon, no interior, no piece of text I had not already read.

The last twenty minutes were me testing hypotheses about the game rather than playing it, and I
want to be clear that I know the difference.

Two things about the hour that were genuinely good and that I kept noticing:

- **It is beautiful and it never stuttered.** Five day-night cycles. Dusk at t ≈ 1103 s
  (`m_pb.png`) and dawn at t ≈ 1436 s (`m_qd.png`) are both worth stopping for, and the moon at
  t = 2985 s is a real anchor in a real night sky (`shots/uj0.png`). It ran at what felt like a
  locked frame rate for sixty-one minutes without one hitch I could feel.
- **The carried lantern throws a real pool of light on the ground.** Looking down at night gives a
  soft white patch that moves with you (`shots/pa0.png`, `shots/qb0.png`). It is the single most
  convincing "you are the one carrying the light" moment in the game, and it is entirely non-verbal.

And one thing I only realised writing this up: **sprinting is total immunity.** 100 seconds of
continuous sprinting through night 4 with a live wave — **zero deaths, zero damage** (500
classified frames, `vid2/`). Standing still inside a spawned cluster is death every 8.3 s. There is
no middle. The optimal play I converged on by minute 8 was *hold shift+W forever and never stop*,
which is not a game about lighting lamps.

---

## 5. EVERY MOMENT I WAS CONFUSED, BORED OR STUCK

| t | what |
|---|---|
| 5 s | **I am holding a lantern and the HUD says `KESTREL 6 / 12`.** I assumed the ammo counter was decoration. |
| 5 s | `6 / 12` — six of twelve what? I only worked out it was magazine/reserve at t = 292 s when a reload turned `1 / 12` into `6 / 7`. |
| 5 s → end | **The gun is never in my hands.** I fired ~14 rounds over an hour. The viewmodel was a lantern in every single frame of the session. Clicking drains a counter attached to a weapon I never see. **This is the most disorienting thing in the game and it lasted the whole hour.** |
| 76 s | Health 22 and falling, screen edges red, nothing visible on screen. I never saw what hurt me. *(My fault — 50 s idle gap. Reported anyway because it is what the frames show.)* |
| 84 s | `AN UNLIT LANTERN / 5M` with **no key on it.** Stuck here for 9½ minutes. |
| 175 s | First death. Dead for 4 s, respawned into the same swarm, dead again. |
| 210–474 s | **The death loop.** ≈ 32 deaths in four minutes. Confused, then stuck, then bored, then angry. |
| 324 s | Pressed F1 while dead. **F1 does nothing on the death screen** and the `F1 CONTROLS` hint is hidden there too — so the one moment a new player most wants the manual is the one moment it is unavailable. |
| 551 s | Sky is blue. It is a new day. I have 4 HP and no idea how to get it back, and the game has never mentioned healing. |
| 674 s | F1. `HOLD E — USE`. Relief, and irritation that this was not on the lantern card. |
| 696 s | F1 from page 2 while I expected `F1 CLOSE`. It *does* close — but I had pressed F1 an extra time a moment earlier, so I got page 1 again and my `TAB` was eaten by the modal. Minor, but I lost 30 s to it. |
| 728 s | CHARACTER: `HND CAP LAN VIT ATT`, all `0`, `0 PTS`. **Five three-letter words with no expansion anywhere in the game.** I can guess LAN and VIT. I still do not know what HND or CAP or ATT are, and I had no points to spend to find out. |
| 846–1049 s | Rig fault (pointer pinned), declared in §0. ~3½ minutes lost. |
| 1149 s | Held E on a lantern at 3M. Killed 0.6 s into the hold. Never saw the prompt again. |
| 1304 s | Looked down. Six creatures on my feet. **Retroactively furious about the previous twenty minutes.** |
| 1647–2203 s | **The compass.** The diamond sat pinned at `◇>>` through **86° of continuous turning** (`m_sl.png`, six frames, ticks moving 565 → 610 px while the diamond does not move at all), and twice it snapped from `<<◇` to `◇>>` on a **7° turn** (`m_se.png`, se4 → se5). Both behaviours are consistent with "the target is behind you and the marker clamps to the nearer edge", and I worked that out eventually — but **I never learned to steer by it**, and I spent nine minutes trying. |
| 2227 s | Pressed `1`, `2`, `3`, `T`, `C` in sequence. **Five silent no-ops.** No "you don't have that", no dimmed row, nothing. |
| 2424 s | Bored. Fifth identical hill. Stayed bored. |
| 2960 s | Fired twice; ammo stayed `4 / 7` both times. Either the clicks were dropped or firing was blocked. **No feedback either way** — no click, no dry-fire, no message. |

---

## 6. DID ANYTHING THE GAME SAID MAKE ME WINCE?

The complete inventory of text I met in an hour. I am the only reader who met it cold, so here is
all of it, including the ones that worked.

### It landed

> **`THE LAMPS WENT OUT ON A TUESDAY`**

White, centred, over black, 0.8 s to 2.1 s. **This is a very good line and it is the best thing in
the game.** "Tuesday" is doing all the work: it makes an apocalypse into an inconvenience that
happened to a specific ordinary week, which is funnier and sadder and more *lived-in* than any
amount of "the darkness came". It is dry without being arch. It made me want to know what happened
next, which is the entire job of an opening card. Do not touch it.

> **`AN UNLIT LANTERN`** / `5M`

Four words that taught me the game (§3). "Unlit" rather than "broken" or "extinguished" is the
right register — plain, physical, slightly sad. It reads as a thing noticed rather than a quest
marker. **No wince. This is the model the rest of the game's nouns should copy.**

> **`THE DARK TOOK YOU`** / **`YOU GET UP AGAIN`**

I met this about seventy-eight times, which is the hardest possible test of a line, and it survived.
"The dark took you" is the right amount of mythic for a game called Nightshade — it names the
antagonist as a *condition* rather than a monster, which is what the fantasy needs. **"You get up
again" is the better half**: it is stubborn rather than heroic, and after the fortieth death it read
less like flavour text and more like a small, dry joke the game was making at my expense, which I
appreciated. Second person, present tense, no exclamation mark, no "respawning in 4…". It never
once made me wince and I am genuinely surprised by that.

> `F1 CONTROLS`

Correct. It also **disappears once you have used F1**, which I noticed and liked — the game stopped
telling me something I already knew.

### It didn't wince, it just said nothing

> `WAVE 1   10`

`WAVE 1` never became `WAVE 2` in an hour, across four nights. The number beside it went
`0 → 11 → 10 → 3 → 9 → 10`. **I do not know what either of them counts** and I watched them for
sixty-one minutes. It is the only permanent element on screen whose meaning I never recovered.

> `HND` `CAP` `LAN` `VIT` `ATT`

Not cringe — the opposite problem. This is the one screen in the game with no voice at all. Five
abbreviations and five zeroes. In a game whose lantern card says `AN UNLIT LANTERN`, a character
sheet that says `HND` is a different game leaking in.

> `X NEXT   C SPEND`

`C` is `CAST` on the controls page and `SPEND` here. Contextual keys are fine; a player who has
just read the controls page and then reads this one is briefly certain that one of them is wrong.

### One real wince, and it is structural rather than a line

> `NIGHTSHADE W6 - the first minute, and the town you carry it home to`

This is in the terminal, not on screen, and I only read it afterwards — so it did not affect my
play. But **`W6` is a build-wave number in the product's title line.** If a single screenshot of a
terminal ever escapes, that reads as unfinished in a way none of the on-screen text does. Every
string the *player* meets is in voice. The one string the *developer* meets is not.

**Nothing else made me wince.** After an hour with it I would say the writing is the most finished
thing in this game by a distance — the problem is not that the game says the wrong thing, it is
that at the four moments I most needed it (the lantern's key, what a wave is, what HND is, why my
keypress did nothing) **it says nothing at all.**

---

## 7. WHAT THE GAME'S OWN EXIT REPORT SAID — read only after the process was dead

Included because it corroborates, and in three places sharpens, what I saw. This is the game's
number, not mine.

- `FEEDBACK up/down: source BELOW the frame 14504, ABOVE it 29`. **99.8 % below.** §2 is not a
  seed artefact.
- `direction segments on 16520 (peak 4 of 4 lit at once)`. The four-at-once case in §2 is the
  measured peak, not my bad luck.
- `TEACH opening: compass KEEP-TURNING on 209587 frames` of 311 223 — **the compass was telling me
  to keep turning on 67.3 % of the hour.** My nine minutes of §5 were not incompetence; that is the
  steady state.
- `FEEDBACK death: dead frames 26625 (0 of them WITH control)`. 26 625 / 311 223 × 3663.3 s =
  **313 s dead, 8.6 % of the hour**; at the 4.0 s screen I measured, **≈ 78 deaths.** And `0 of them
  WITH control` independently confirms the frozen-view observation in §1.
- `TEACH: kits in pack 0  planted 0`. **I never had a lantern kit.** `[E] PLANT A LANTERN POST`
  cannot have appeared for me, which explains a hole I could not explain from the screen.
- `W6 town: CAMP lux 0/512  pts 0/10  buildings 2  villagers 0 (0 named)`;
  `W6 acts: talks 0  trades 0`. **There were no villagers in my world for me to fail to find.**
  Sixty-one minutes of walking toward a town that had nobody in it.
- `W6 hand: oil 100/100`. **There is an oil resource at full, and it is nowhere on the HUD.** I
  finished the hour not knowing I had oil.
- `W7 hands: held KESTREL (4) own 1 mask 16`; `spells granted 0, casts 0`. Confirms §3: `1-8 GUNS`
  and `C CAST` are advertised to a player who owns one gun and zero spells.
- `hitmarker on 14 frames`, `damage numbers on 101`, `swings 6`. **I connected with almost
  nothing all hour** — which matches how the combat felt, and is worth weighing against "the gun
  feels connected".
- Performance, for the record: `mean 11.8 ms → 85.0 fps`, `frames over 16.67 ms: 5690 of 311223`
  (1.8 %), `triangles PEAK 1958 of 3000`, `HUD peak 322 of 360`, `0 truncated frames`,
  `0 truncated strings`. It never stuttered and the HUD never lost a piece.
- **One line I would not have known to look for and am flagging rather than diagnosing:**
  `sim+net: worst 5.0 ms of the 2.0 ms budget`. The game's own report says it overran its tick
  budget by 2.5× at some point in my hour. I felt nothing, and I am not the right agent to chase it,
  but it should not be left in a log nobody reads.

---

## 8. THE THREE THINGS I WOULD CHANGE, IN ORDER

1. **Put the verb on the lantern card.** `AN UNLIT LANTERN` / `HOLD E` / `5M`. Four words taught me
   the whole game in eighty-four seconds and then stranded me for nine and a half minutes for want
   of two more.
2. **Give the player one second of grace on respawn, or move him ten metres.** Respawn-in-place
   inside a spawned cluster is a loop the player cannot act his way out of, and I hit it twice for a
   combined seven minutes. It is also what makes death read as free: four seconds and a free heal
   is not a price, it is a vending machine.
3. **Make the "it is below you" cue survive the frame it is drawn on.** It exists, it is correct, it
   is 20 px of dark red drawn into the bottom edge of a screen that is already flooded dark red when
   it matters. I looked at it for twenty-one minutes and never saw it.

And the one thing I would not touch: `THE LAMPS WENT OUT ON A TUESDAY`.

---

*Frames, montages and the classification data for every number above are in
`/tmp/claude-1000/-home-nbeerbower-Projects/6f56b098-a579-40ff-80df-fab693a3b2d6/scratchpad/np3/`
— `shots/` (per-window stills), `vid/` `vid2/` `vid3/` (x11grab sequences), `m_*.png` (montages),
`sess.py` (the driver), `session_stdout.log` (read after the process was killed, never before).*
