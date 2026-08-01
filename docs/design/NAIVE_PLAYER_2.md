# NAIVE_PLAYER_2 — the first sixty seconds, played by someone who was told nothing

Wave 7 gate. Played 2026-08-01, 08:24–09:15, on `DISPLAY=:0`, seed 1337.
Compiler verified per RULE 0: `hemlockc 2.9.1 (built Jul 27 2026 21:11:41)` printed `107` then
`5120738502741017561`.

I did not read `docs/design/` or `src/sim/`. I read `CLAUDE.md` RULE 0 and §2 (build/run) and the last
seven commit messages, and nothing else about what the game means.

---

## 0. READ THIS BEFORE THE NUMBERS — how I drove it, and what it cost

The previous run led with three caveats and threw away its own first forty minutes, and that is why
it was believed. Here are mine. Two of them are bad.

**0.1 — I contaminated myself before I saw a single frame, twice.**

I ran `--help` to learn how to launch. It told me there is a death ("about 27 s later the dark takes
you"), a "reach ring", "lantern posts" you plant, and that towns go CAMP → VILLAGE → TOWN → CITY.

Worse: **the game prints a ~40-line tutorial to stdout at boot**, and I read it before I looked at
the screen. It gave me the entire first minute in prose — wake on your back at dusk, forty metres
downhill there is an unlit lantern, walk to it, three Wisps die to one shot each, hold E for two and
a half seconds, then the horn — plus every keybinding in the game.

So **I cannot honestly answer "how long until you understood what the game wanted."** I knew before I
started. Section 3 answers the falsifiable version instead: *what does the screen alone say, and
when.* Everything in this document that depends on my subjective discovery is marked CONTAMINATED.

That the tutorial lives in the terminal rather than on the screen is itself a finding, and it is
probably why Gate 9 said "the beacon **you are told** to walk to". You are told, in a place a player
who double-clicks never looks.

**0.2 — I discarded Run 1's first 54 seconds.** My input driver had not taken window focus, so the
game ran unattended on the desktop while I read the console. Health went 100 → 25 → 100 across a
gap I never observed. Nothing from before t=54 s of Run 1 appears in this report except as the
record of that mistake.

**0.3 — I play in bursts, and between bursts the player stands still.** There is no `xdotool` on this
box, so I drive with XTEST through python-Xlib. I queue a batch of inputs, they execute
continuously, then I stop and read frames — which takes minutes, during which the character is a
statue. **Standing still in this game is fatal.** Every death count below is inflated by my harness.
Do not read the totals as difficulty. The measurements that are *not* affected are the ones taken
inside a single continuous burst, and I say which those are.

**0.4 — Pinning, and no company this time.** Every capture is `import -window <my window id>`, and
every frame's filename records how many NIGHTSHADE windows existed on `:0` at capture time.
**3818 of 3818 recorded frames were captured with exactly one — mine.** No repeat of last wave's
forty minutes in another agent's window. (Three files in that tree match `grep -v _n1` — they are my
own `_crop.png` derivatives, not frames.)

**0.5 — Sampling rate.** The recorder runs at ~2.7 Hz. Every `t=` in this document is **±0.4 s**.

**0.6 — This is not the committed tree.** My binary is `hemlockc -O1 src/game/main.hml` at `74a6ec4`
**plus 13 modified files and 1 new file from four agents still in flight** (`tod.hml`, `config.hml`,
`client.hml`, `main.hml`, `server.hml`, `hud.hml`, `shot.hml`, five probes, `ci_imports.sh`,
`probe_feedback.hml`). Everything below describes that binary. Loadavg during play ranged 0.51–3.9,
which is quiet for this machine.

**0.7 — I got a measurement wrong and caught it, and it changes a headline number.** My first
alive/dead detector read the ammo readout's brightness. It scored *every frame where ammo was 0 and
therefore printed in red* as a death, because red has low luminance in greyscale. It reported a
28-second "death" in Run 9 that was actually me alive with `CLUB 0 / 12` on screen. I only noticed
because a 28 s death is impossible when the respawn timer is 4 s. The corrected detector reads the
minimum luminance of the compass plate, which separates cleanly (alive 7.72, dead 42–57, and it gets
the red-ammo frame right). **All death counts in this document are from the corrected detector.** The
first version would have told you I died 39 times in Run 10 when the true figure is 64.

---

## 1. Did I know when I was hit, and from where? Did I know when I died?

### Hit: yes, and I read it in one frame with no prior context.

A fat red bar with a dark keyline appears on a ring around the crosshair, offset toward the
attacker. It is large, saturated, and outlined, so it survives both the pale dusk sky and dark
terrain. Measured co-occurrence, Run 2, continuous burst:

| t | HP | on screen |
|---|---|---|
| 39.99 s | 100 | crosshair only |
| 41.49 s | 64 | **two red bars, left and right of the crosshair** |
| 44.51 s | 52 | bars persist |
| 47.53 s | 16 | bars persist |
| 48.28 s | 0 | death banner |

In Run 7 I took four at once — above, below, left and right — and it read instantly as *surrounded*.
There is also a **red glow along the whole screen edge** at low health, measured present at HP 34, 16
and 4 and absent at HP 70+. Between the bars, the numeric HP readout, the bar length and the screen
edge, being hurt is over-communicated rather than under-communicated. **This half of Gate 9's
complaint is fixed.**

### From where: the direction is right and the answer is still useless.

**In my entire naive run I was killed by things I never saw.** At Run 2 t=41.49 s the indicators said
left and right and there was nothing on screen but sky and a hillside. Same in Run 5, Run 8, Run 9.

The reason surfaced on my tenth run, by accident. **The things killing me are flying, and they sit
above my sightline.** They are visible at the very top edge of frames in Run 9 and unmistakable in
`rA_h10.png`, two purple bat-shaped enemies silhouetted against the sun on a ridge, well above the
horizon line the camera hands you.

The damage indicator is a 2D ring around the crosshair. It can say *right*. It cannot say *up*, which
was the only axis I ever needed. I did not look up once in fifty minutes, because nothing suggested
it, and the wake animation specifically leaves you looking at the horizon.

### Death: yes. Unmistakable. This is a clean fix.

Full-width black plate, dead centre, `THE DARK TOOK YOU` in white over `YOU GET UP AGAIN` in amber,
the entire HUD removed, and an amber bar underneath that **drains** as the respawn timer runs. I
understood it the first time I saw it, before I knew the game had a death state.

Respawn duration measured across 64 episodes in Run 10: **3.72–4.17 s**, tight.

### And the thing I would fix first: there is no way to lose, and idling is a death loop.

In Run 10 I stopped sending input and left the recorder running while I analysed frames. Over the
following **365 s** the game recorded **64 death episodes** totalling **252.75 s — 69 % of the
recording spent on the death screen**, in a metronome:

```
cycle 68: alive 0.75 s, then dead 4.14 s
cycle 69: alive 1.12 s, then dead 3.75 s
cycle 70: alive 1.12 s, then dead 4.14 s
cycle 71: alive 0.74 s, then dead 4.10 s
...
```

You respawn, you get less than a second and a half, you die, forever. The banner says YOU GET UP
AGAIN and it means it literally. A player who puts the pad down to answer the door comes back to an
unbroken chain of death banners and no information about what happened.

---

## 2. Did I know my shots were connecting?

### Firing: instantly, overwhelmingly obvious.

A muzzle flash that whites out roughly a third of the screen, plus an ammo counter that decrements,
**turns red at 1 round**, and swaps to `CLUB` at 0. I understood all three within two shots.

(One wart: the melee weapon inherits the gun's readout, so an empty club reads `CLUB 0 / 12`.)

### Connecting: yes — and it took me ten runs and fifty-one minutes to see it once.

When it finally happened it was excellent. `rA_h10.png` carries three simultaneous signals:

- an amber **`15`** floating just above the crosshair, dark-keylined so it reads on anything;
- the crosshair centre replaced by a **radiating starburst**;
- the top-left counter advancing.

**Control.** Firing at empty sky (`cA_sky4.png`) produced the muzzle flash and the ammo decrement and
**no number, no starburst, no counter change**. So the number confirms a *hit*, not a *shot*. This is
a single-frame A/B — the rest of my control burst was spent dead — so treat it as one sample, not a
table.

**Why it took fifty-one minutes.** I fired 6 shots in Run 8 and 14 in Run 9 and got nothing at all,
because not one of them had an enemy in front of it. I saw my first hit marker only after I
deliberately pitched the camera **up** in Run 10 to test a hypothesis. *The feedback is not missing.
The target is.* A player who never thinks to look up will fire into fog for as long as they can stand
it and conclude the gun does nothing.

**Honest gap.** From the screen alone I could not tell whether `15` is damage dealt or points scored.
The top-left counter read 12 before the shot and 15 after, and the floating number also read 15. As a
player I read it as "I did a thing worth 15" and did not care which, so this may not matter — but I
could not resolve it and I am not going to pretend I did.

---

## 3. How long until I understood what the game wanted?

CONTAMINATED (§0.1) — I knew before I started. So here is the falsifiable version.

### 3a. What the screen says with ZERO input. Measured three times, runs 3, 4 and 10.

| t | what is on screen |
|---|---|
| 0.0 – 0.7 s | black |
| 0.7 – 2.2 s | title card, `THE LAMPS WENT OUT ON A TUESDAY`, white on black |
| 1.4 – 4.1 s | **the sky, and nothing else.** Clouds fill the frame. |
| **4.1 s** | **the camera begins to pitch down by itself** |
| **4.45 s** | **it settles on the horizon and stops** |

No input was given at any point. It landed in 4.08–4.45 s on all three runs.

**Gate 9's "you wake facing the sky" is true but bounded: it is a 4.45-second get-up animation that
completes on its own.** That is a materially different complaint from the one in the brief, and it is
worth someone checking whether this changed this wave or whether the previous gate simply moved the
mouse before it finished.

**And on the frame it hands you control, both compass markers — the amber chevron on the bar and the
amber diamond below it — are dead centre.** The game is pointing at the objective at the exact moment
you get the controls.

### 3b. What happens if you then do the single most obvious thing (hold W). Run 4, continuous.

| t | on screen |
|---|---|
| 9.3 s | a pale post appears near the crosshair |
| 10.8 s | it is unmistakably a lantern on a post |
| **11.9 s** | **`HOLD [E] — LIGHT THE LANTERN` / `IT'S GOING TO GET THEIR ATTENTION`** |

That is a good first minute. On this seed the beacon is **not** behind a hill — it is straight ahead
and it announces itself in words.

### 3c. What misled me — and this is the real finding of this run.

**The guidance is an initial heading, not a persistent beacon.**

In Run 2 I did what any actual person does on waking somewhere unknown: I looked around. I panned
right during the wake. That spent the authored heading, and **nothing on screen ever gave it back**.

Same seed, same binary, both continuous bursts:

| | Run 2 — panned during the wake, then walked | Run 4 — never touched the mouse, held W |
|---|---|---|
| lantern found | **never**, in 112 s | prompt on screen at **11.9 s** |
| first death | 48.3 s | 62.7 s |
| deaths in first 60 s | 1 | **0** |

**The entire difference is whether the player moved the mouse in the first four seconds.**

The compass diamond was on screen the whole of Run 2. I could not tell what it meant, and when the
target went off-compass the marker **clamped to the edge of the bar** and sat there — which reads as
"the marker is stuck", not as "keep turning this way".

Two more things misled me:

- **At sprint speed the prompt is on screen for under 1.1 s.** Measured: absent at 11.56 s, present
  at 11.94 s, absent again at 12.68 s. I ran clean through the tutorial lantern and out the far side
  **twice**, and the game never mentioned it again.
- **In Run 7 I stood at the foot of a tall post with an amber lamp head, crosshair on it, and got no
  prompt at all** — because that post is a big distant landmark, not the interactive one. Two objects
  that read identically at a glance, one of which responds and one of which does not, with no way to
  tell them apart except walking at both.

---

## 4. Playing until the first lantern is lit

**Lit it on run 10.** Wall-clock from my first frame to the lantern lit: **51 minutes**.

The successful attempt took **14.2 s of game time from process start**: wait out the wake, sprint
6.0 s on the heading the game gave me, stop dead, hold E for ~2.7 s.

| t | on screen |
|---|---|
| 11.5 s | `HOLD [E] — LIGHT THE LANTERN`, HP 100 |
| 12.4 s | an amber progress bar begins filling under the prompt |
| 13.3 s | bar longer |
| **14.2 s** | **`UNLOCKED / FLARE` top right, and a pink FLARE bar appears above the health bar** |

**That reward moment is genuinely good.** A named thing you did not have, a bar that was not there
before, arriving on the beat, with no words wasted.

### Deaths

**50 recorded deaths before I lit it**, across 8 instrumented process launches, plus at least one
more in the un-instrumented Run 1.

**Do not read that as difficulty.** Corrected detector, per run:

| run | what I was doing | deaths | dead time | recording | first death |
|---|---|---|---|---|---|
| 2 | naive: panned at wake, then walked | 14 | 51.7 s | 218.5 s | **48.3 s** |
| 3 | wake control + 360° sweep | 1 | 4.1 s | 122.3 s | — |
| 4 | **held W on the given heading** | **1** | 4.1 s | 134.9 s | **62.7 s** |
| 5 | walked, bracketed approach | 7 | 28.2 s | 112.7 s | — |
| 6 | held E while closing | 1 | 4.0 s | 60.5 s | — |
| 7 | stood at the wrong post, probed it | 10 | 40.3 s | 121.3 s | — |
| 8 | fire test | 10 | 39.8 s | 130.9 s | — |
| 9 | sweep-and-fire | 6 | 24.3 s | 84.0 s | 20.5 s |
| 10 | **lit the lantern**, then idled | 64 | 252.8 s | 365.3 s | 14.9 s (after lighting) |

The honest number is the one inside continuous play: **Run 4, moving continuously on the game's own
heading, I survived 62.7 seconds and did not die in the first minute at all.** Runs 7, 8 and 10's
totals are my harness standing still while I read frames.

### Did I ever want to stop?

Yes, twice — around Run 7 and again in Run 8. Standing at a post that would not respond, health
draining to 4 from something I could not see, with no explanation on screen.

Not because it was hard. Because **nothing on screen distinguished "you are in the wrong place" from
"you are doing the wrong thing" from "this object is not interactive."** All three failure modes look
identical: no prompt, and you die.

### When did I next feel taught something?

**Immediately after lighting it, and twice over.**

The FLARE bar appearing above the health bar taught me with no words that there is a second resource
and it is mine now. And in the same breath the game taught me the other half of its own sentence: the
wave arrived and the counter started moving. **I learned "it's going to get their attention" by being
attacked** — the prompt's second line paying itself off about eight seconds later. That is the design
working the way the ~64 m ring worked for the last agent: taught by consequence, not by tooltip.

---

## 5. Every moment I was confused, bored or stuck

`t` is time within that run. Wall-clock in brackets.

| t | run | what happened |
|---|---|---|
| 1.4 – 4.1 s | all | **Confused.** Facing the sky with nothing in frame. It resolves itself at 4.45 s, but the first four seconds of the game are a cloud. |
| 6 – 12 s | 2 | **Confused.** I panned to look around — the natural thing — and by the time I stopped I had no idea which way I had woken up facing, and nothing on screen would tell me. |
| 12 – 48 s | 2 | **Lost.** Walking with no landmark. Small amber specks on the hillsides that I could not tell apart from the lantern I was looking for. |
| 41.5 s | 2 | **Confused.** Two red bars, health falling fast, nothing on screen to be hit by. First of six times this happened. |
| 48.3 s | 2 | Died. **Not confused** — the banner is completely clear. Best-communicated moment in the first minute. |
| 48 – 112 s | 2 | **Bored and stuck.** Two more deaths. Still no lantern. This is the run where a real player closes the game. |
| ~12.0 s | 4 | **Missed it.** Sprinted through the prompt inside 1.1 s. Did not realise until I reviewed frames. |
| 11 – 17 s | 7 | **Stuck, and this was the low point.** Standing at the base of a big lit-looking post, crosshair on it, holding E, nothing happening, health 100 → 46. Wrong object; no way to know. |
| 17 – 30 s | 7 | **Confused.** Four damage indicators at once. Surrounded by things I could not see. |
| 15 – 25 s | 8 | **Frustrated.** Six shots, no hit confirmation of any kind. Concluded the gun might not do anything. It does; nothing was in front of me. |
| 20 – 26 s | 9 | Ran out of ammo mid-sweep. `R` did not visibly reload; the counter went 6→0 and swapped to `CLUB 0 / 12`. **Confused** about whether I had reserve ammo at all. |
| 14.2 s | 10 | **Taught.** UNLOCKED / FLARE. The clearest moment in the game so far. |
| 15 s → 365 s | 10 | **The death loop.** 64 deaths, 69 % of the recording on the death screen, ~1 s of life per cycle, no game over. |

---

## 6. Scoreboard against Gate 9

> *"You wake facing the sky"* — **TRUE, BOUNDED.** 4.45 s, self-correcting, no input required.
> Measured 3×.

> *"the beacon you are told to walk to is behind a hill"* — **NOT TRUE ON SEED 1337.** It is dead
> ahead at the moment you get control, visible at 9.3 s, and the game names it in words at 11.9 s.
> **But it is only ahead if you do not move the mouse during the wake**, and that is the new bug.

> *"standing still to look for it kills you in ~15 seconds"* — **CLOSE.** Standing still from the
> wake, first death at 48.3 s (Run 2). Standing still after the wave starts, ~15 s. Moving
> continuously, 62.7 s and no death in the first minute.

> *"nothing on screen ever says an enemy hit you"* — **FIXED.** Directional bars, screen-edge glow,
> numeric HP. Over-communicated now. The residual problem is that the attacker is above your
> sightline and the indicator ring has no *up*.

> *"nothing says your shots connected"* — **FIXED, AND HARD TO EVER SEE.** Amber damage number,
> starburst crosshair, advancing counter, all three at once, verified absent when firing at sky. It
> took me ten runs to get an enemy in front of the gun.

> *"when you die the game does not tell you"* — **FIXED, EMPHATICALLY.** Best-communicated moment in
> the first minute. The new problem is the opposite one: it tells you 64 times in a row and never
> stops.

---

## 7. Artifacts (scratchpad, not in the repo)

`/tmp/claude-1000/-home-nbeerbower-Projects/6f56b098-a579-40ff-80df-fab693a3b2d6/scratchpad/naive2/`

- `run{2..10}.log` — timestamped input logs, one line per key/mouse/capture
- `run{2..10}.log.rec/` — 3818 window-pinned frames at ~2.7 Hz, window count in every filename
- `run1.log.stdout` — the boot tutorial that contaminated me
- `shots/` — the named captures referenced above (`r4_w01`, `rA_e03`, `rA_h10`, `cA_sky4`, …)
- `sheet*.png` — the contact sheets I actually read
- `driver.py`, `rec.sh` — the XTEST harness
- `deaths2.sh` — the corrected alive/dead detector (compass-plate minimum, threshold 20)

The only file I wrote in the repo is this one.
