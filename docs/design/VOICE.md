# VOICE — every word a player reads, collected, judged, and a rule for the next ten waves

**Status:** the W7 anti-cringe audit, requested by the project owner by name. Owned by that task.
**Companion:** `LORE.md` §10 (REGISTER) is the *law*. This file is the *enforcement* — §10 has existed
for waves and nothing on screen obeyed it, because nobody had ever seen the strings as a set.

**Read §5 if you read nothing else.** It is four rules and it is the reason this file exists.

---

## 0. THE HEADLINE, AND IT IS NOT A TONE PROBLEM

I was sent to find purple prose. I found some. But the three worst things in this audit are not
taste, they are **defects that no probe could see and only a screenshot could**:

1. **`FONT_MICRO` HAS NO APOSTROPHE.** A 320×180 frame of Mabel's first line read
   **`MM. YOU RE ON THE ROTA.`** `hud_micro_cp` registers 50 glyphs — `A–Z 0–9 . , : / % + - [ ] < >`
   plus degree, heart and bolt — and U+0027 is not among them. `font.hml` advances the pen for an
   unmapped codepoint and draws nothing, so **every contraction in every line of dialogue in this
   game has rendered as a hole since the day it was written.**
   `IT'S GOING TO GET THEIR ATTENTION` — the sentence `LORE.md` §3 calls the central bargain of the
   whole game, on screen for the full 2.5 s lantern hold — has always read `IT S GOING TO GET THEIR
   ATTENTION`. This is the same class as *"FONT_BIG has no letters"*, which hid the death banner for
   the entire history of the project, and it was found the same way: **by looking at the picture.**
   Fixed and measured (§7); the diff is §8-C.

2. **YOU BUY A `PUMP` AND YOU ARE HANDED A `BELLOWS`.** All four village guns had two unrelated
   names — one in the trade panel, one on the ammo plate — with no string anywhere connecting them.
   Photographed at both ends. `BOLT`→`BLKTHRN`, `REVOLVER`→`KESTREL`, `PUMP`→`BELLOWS`,
   `PIPE SMG`→`NETTLE`. That is a comprehension bug wearing a writing problem's clothes.

3. **`"YOU CAME BACK."` IS SAID TO PEOPLE YOU HAVE NEVER MET.** `npc.hml` §18 step 1 fires
   `NPC_T_GREET` on `met[w] == 0` and on nothing else — it is the *first-meeting* topic. Walk up to
   Mabel for the first time in your life and she says *"You came back."* It also spends the sentence
   this entire game is about on hello.

And the biggest *writing* finding is not a line at all, it is arithmetic:

4. **`NPC_LINES = 6` HAS BEEN SELECTED, HASHED AND THROWN AWAY SINCE W6.** `client_talk_line`'s
   `NPC_T_DAILY` arm read `p_who` and ignored `p_arg`, so each villager had exactly **one** daily
   line, said every in-game day, forever. GAME_DESIGN §5.7's *"one new line per in-game day"* has
   never once happened. **Repetition is the single largest amplifier of a bad line, and it is also
   what turns a good one bad.** *"Soup's warm past midnight"* is the best sentence in this game
   exactly once.
   And the one it repeated was **truncating**: priced through the real font,
   `"TWO FINGERS SHORT, STILL STRAIGHT."` is **120 triangles against a 96-triangle clamp** and
   rendered as `TWO FINGERS SHORT, STILL STR`.

---

## 1. HOW THIS WAS DONE, AND WHAT TO DISTRUST

- Every string that reaches a human was grepped out of `src/game/main.hml`, `src/game/client.hml`,
  `src/render/hud.hml`, `src/game/server.hml` and `src/sim/npc.hml` and put in one list (§2). **A
  tone problem is invisible line by line and obvious in a list.**
- Every line was then **priced through the real font** — `font_tri_cost(hud_font_micro(), s) * 2`,
  the same call `probe_hud` uses — against the clamp its actual draw site passes. That is where the
  Mabel truncation and the `g_TB_PROMPT` overrun came from. Guessing glyph counts by eye would have
  found neither.
- Every verdict below that says *"photographed"* means I looked at a 320×180 PNG upscaled 4×, not at
  source. Four findings exist only in the frame and are invisible in a text editor: the apostrophe,
  `PUMP`/`BELLOWS`, `YOU CAME BACK` to a stranger, and the `TO`/`OUTSIDE` collision (§2.C4).
- **`npc.hml` contains no strings at all** and never has — the import wall forbids it and its own
  header says so (*"strings are the HUD's business"*). My task brief said I owned "villager dialogue
  + names" in that file; **they are not in it.** They live in `client.hml`, which I do not own, so
  everything for it is written out as a diff (§8) and measured in a scratch copy of the whole tree.
- **`main.hml`'s md5 changed four times while this ran** (three agents own it this wave). The diffs
  in §8 are therefore **exact string replacements, not line-number patches**, each asserting its old
  text appears exactly once. Snapshot they were verified against:
  `main.hml 8dcf8af0324ebfceeff99288557b5571`, `client.hml 6af8b5b297936d7c65bc60f48c8af38b`,
  `hudgen.hml 09187344955de437692aaae19fc93c74`.
- **What I did not do:** I did not photograph the character sheet or the trade panel at every tier,
  I did not audit `--help` output beyond reading it, and I did not review the *audio* surface at all.

---

## 2. THE INVENTORY

`t` = triangles through `FONT_MICRO` with its mandatory shadow (4 per ink glyph); `/N` = the clamp
its draw site passes. **KEEP / FIX / CUT**, with a reason on every one, including the keeps —
saying why something works is how §5 got written.

### A. Boot and CLI — `main.hml`

| # | String | t | Verdict | Why |
|---|---|---|---|---|
| A1 | `NIGHTSHADE W6 - the first minute, and the town you carry it home to` | — | **FIX** | The subtitle is the best one-sentence statement of this game anywhere in the repo. `W6` is an internal build tag, two waves stale, in a line a player reads at boot. → drop the tag. |
| A2 | `--help` body, ~30 lines | — | **KEEP** | Plain, specific, admits which flags are fixtures (`DEV/FIXTURE`) and why. A dev surface that tells the truth about itself. |
| A3 | `controls_print` key table | — | **KEEP** | Verb-per-key, no adjectives. `-- only the guns you OWN; buy them from a gunsmith` earns its aside. |
| A4 | *(the boot walkthrough, `THE FIRST SIXTY SECONDS`)* | — | **already CUT** | It carried the only semicolon in any player-facing text in the game, against `LORE.md` §10.4's *"if a line needs a semicolon it needs a rewrite"*. Another agent deleted the whole block this wave for a better reason ("a walkthrough in a terminal is not a teaching signal, it is an alibi for not having one"). Recorded so nobody re-adds it. |

### B. The first minute — the must-never-yield set

| # | String | t | Verdict | Why |
|---|---|---|---|---|
| B1 | `THE LAMPS WENT OUT ON A TUESDAY` | 100/128 | **KEEP — and protect it** | The best string in the game. `LORE.md` §2's own opening, verbatim. Concrete, no adjective, and *Tuesday* does all the work: **a catastrophe with a weekday on it is a maintenance failure**, which is the entire thesis of this fiction. It is also the only line that has *earned* its definite article — "the lamps" are a specific municipal thing a specific town had. |
| B2 | `AN UNLIT LANTERN` + `${d}M` | 56/64 | **KEEP** | Article, adjective, noun, distance. Nothing else. |
| B3 | `HOLD [E] - LIGHT THE LANTERN` | 92/112 | **KEEP** | Imperative, key, object. The shape every prompt in this game should copy. |
| B4 | `IT'S GOING TO GET THEIR ATTENTION` | 108→**112**/112 | **KEEP — and protect it** | Second only to B1. *"Their"* names an antagonist without naming it, in the register of somebody warning you about wasps. `LORE.md` §3 quotes it as the central bargain. **It was rendering without its apostrophe** (§0.1) and adding the glyph took it to 112 against a 108 clamp — `g_TB_PROMPT` raised to match (§8-B V17). `probe_hud` §H caught this on the first run. |
| B5 | `F1 CONTROLS`, and the 18 control rows | 20–36 | **KEEP** | One-word verbs. `F1 MORE` / `F1 CLOSE` teaches its own paging. |
| B6 | `RELOADING` | 36/40 | **KEEP** | Present participle, state readout. Correct. |
| B7 | `UNLOCKED` (card header) | 32/36 | **KEEP** | One word, true. |
| B8 | `WAVE 1  x0` (readout) | 24/44 | **FIX** | `x0` is a **count rendered as a multiplier** — "wave one, times zero" — and it sat on screen reading zero for the entire gap between waves, the one state in which it has nothing to say. → show nothing when the answer is none. **See §3 for the version of this fix I threw away and why.** |
| B9 | `WAVE ${n}` / `WAVE ${n} CLEARED` (banners) | 0† | **KEEP** | Flat, but clear and standard, and this audit does not get to spend the frame budget on making flat things interesting. †They draw through `FONT_BIG`, which has no letters, so a banner's letters cost nothing and only its digits draw. |
| B10 | `THE LAMPS ARE OUT` (horn banner) | 0† | **FIX** | Fires at the exact moment the player has just **lit** one — a banner contradicting the frame it is drawn over — and repeats B1 sixty seconds later meaning something different. → `THEY HEARD IT`: the payoff to B4, coming true. |
| B11 | `THE LIGHT HOLDS` (hold-done banner) | 0† | **KEEP** | The test for an abstraction is *can the player point at it*, and here they can: it is `CORE_LUX` held, and they have a number for it. Three words, declarative, names the win condition. |
| B12 | `A PATH OF LIGHT` (PATH beat toast) | 48/60 | **FIX** | A phrase, not a sentence. Names nothing the player can point at or act on — it is the game admiring itself. What the beat *does* is put more unlit lanterns in the world. → `MORE LANTERNS`, same 48 triangles, one fact. |
| B13 | `POST SET` | 28/60 | **KEEP — the model** | Two words, past tense, civic. If §5 needs an exemplar, it is this. |
| B14 | `TINKER SMG - AT THE BENCH` (card) | 80/80 | **CUT** | The only string in the game that makes a promise the game does not keep, and it makes two. (a) *The bench is Mabel's*, and at 0:30 there is no Village, no Mabel and no bench — the player is told where to collect a gun ~25 minutes before the place exists. (b) *The Tinker is a City gun*; `weapons.hml`'s village row is `{BLACKTHORN, KESTREL, BELLOWS, NETTLE}` and it is not on it. (c) The beat **already has a card** — lighting the lantern grants the FLARE and `cl_apply_w6` fires `cl_card(client_spell_name)` on the same tick. Two cards competed for one 80-triangle slot and the untrue one drew first. |

### C. The second verb

| # | String | t | Verdict | Why |
|---|---|---|---|---|
| C1 | `[E] PLANT A LANTERN POST` | 80/112 | **KEEP** | Photographed; reads perfectly at 320×180 over a dusk sky in its plate. |
| C2 | `${gap}M TO THE REACH` / `INSIDE THE REACH` | 56/112 | **KEEP — and protect it** | **`THE REACH` is the one Proper Concept in this game that has earned itself.** It is a circle you can see on the ground, it flips from grey to amber when you cross it, and three instruments say the same word. A naive player learned the 64 m rule *by walking*. This is what a capitalised abstraction looks like when it is working. |
| C3 | `THE GRID TAKES IT` | 56/68 | **FIX** — *the one the owner named* | Three faults, and the third decides it. **(i) `GRID` appears in no other string in this game.** It is in `LORE.md` §2 and in `npc.hml`'s comments and nowhere a player can read it — the most important confirmation in the second verb was phrased in a noun nothing had taught. **(ii) "Takes it" reads as *confiscates*** at least as easily as *accepts*; a player who plants a lantern and is told something took it has been told they lost something. **(iii) The failure line was better written than the success line** — the other arm is `25M OUTSIDE THE REACH`, concrete, numeric, in the taught vocabulary, and the *reward* was an abstraction. That is exactly backwards. → `THE TOWN GETS IT` (52 t): names the beneficiary, needs no new word, and is what the fantasy is actually about. |
| C4 | `${gap}M OUTSIDE THE REACH` | 72/84 | **FIX — visible only in the frame** | Photographed: at the moment this draws, the prompt 40 px below reads `25M TO THE REACH`. **Same number, same fact, two prepositions, one screen.** Both are true and they read as a contradiction at 320×180. → `${gap}M SHORT OF THE REACH` — a verdict rather than a second measurement, keeps the taught noun, same 72 t. |
| C5 | `THE LANTERN'S REACH` (crossing toast) | 64→68/72 | **KEEP** | A road sign, and this is the moment the word is introduced. Correct to be a label rather than a sentence. |
| C6 | `INSIDE ${n} M IT FEEDS US.` (Wick) | 76/96 | **KEEP, one space** | *"Us"* is the whole line — a person, not a system, telling you a number. → `${n}M`, because every other number on this HUD is `112M TO THE REACH` and three instruments in one shape is one lesson. Also **moved out of `main.hml`**, which had confessed the seam itself: *">>> THIS BELONGS IN `client_talk_line` AS `if (t == 10)`, one line, the next time that file is owned. <<<"* |

### D. Death — the most-read string in the game (478 dead frames in one 45 s run)

| # | String | t | Verdict | Why |
|---|---|---|---|---|
| D1 | `THE DARK TOOK YOU` | 56/56 | **KEEP** | I came to cut this and the fiction saved it. It *looks* like `LORE.md` §10.2's forbidden capital-letter Evil — an abstract noun as the subject of a transitive verb. But §1 says *"Light can be **stolen**, so there is something that steals it"*, and §4 says a drained creature *"is not dead, it is **empty**"*. In this cosmology **the dark taking your light is not a metaphor, it is the axiom.** The sentence is mechanically literal. It stays. |
| D2 | `YOU GET UP AGAIN` | 52/52 | **KEEP — see §3** | I marked this FIX, wrote `THE TOWN RELIGHTS YOU`, and then read the comment above the draw site, which killed it: respawn only uses the lantern `if (sv.lantern_lit == 1)` and otherwise returns you to spawn, so *any* line naming where you wake is a lie for the whole first minute. The existing line answers the question a player actually has on their first death — *"is that it?"* — truthfully, in four words. **My rewrite was prettier and false.** |

### E. The five villagers

| # | String | Verdict | Why |
|---|---|---|---|
| E1 | `MABEL` `ODO` `WICK` `CONNIE` `PIP` | **KEEP, all five** | **Fantasy-name syndrome does not apply here at all.** These are small English names of an unglamorous vintage — a 1930s parish register, not a generator — every one of them is a whole person in `LORE.md` §8, and every one fits a 250-triangle panel. Odo *"keeps soup warm past midnight"* is a character in six words. This is the good end of the roster and §5.3 points at it. |
| E2 | `BENCH` `INN` `LANTERN` `BOARD` `STALL` | **KEEP** | One concrete noun each. `BOARD` is Connie's notice board; the comment explaining why `PIP'S STALL`→`STALL` is model reasoning. |
| E3 | `YOU CAME BACK.` (`NPC_T_GREET`) | **FIX** | §0.3 — it is the **first-meeting** topic and it is said to strangers. → five first-meeting lines, one per person, straight out of `LORE.md` §8's voices. `"YOU CAME BACK."` wants a *returning* topic; `npc.hml` already tracks `talkday` per person so the data exists, but adding the topic needs an owner of **both** files, so it is §6.1 rather than half-done. |
| E4 | `THE LIGHTS ARE GUTTERING.` | **KEEP** | *Guttering* is a lamp word, a real symptom, and understated alarm. Mild collision with the GUTTERING spell; §6.5. |
| E5 | `THE ${DIR} ROAD IS DARK.` | **KEEP** | `DIRECTION.md` §6.3's own model line: tutorial, quest-giving and world-state readout in one sentence. |
| E6 | `THE FOUNDRY WANTS POWER.` | **KEEP** | *Power* is a utility word, and `LORE.md` §1 is explicit that light in this world is *plumbing, a municipal utility, people complained about the rates.* Exactly in register. |
| E7 | `${NAME} MOVED IN.` | **KEEP** | Two words. The whole settlement system's payoff, reported like a neighbour. |
| E8 | `WE'RE A ${TIER} NOW.` | **KEEP** | First person plural. Understated pride. The reason the town is worth coming back to. |
| E9 | `SOMETHING'S GOING UP.` | **KEEP** | Vague on purpose and vague *correctly* — the speaker genuinely does not know what the scaffold will be. |
| E10 | `I'VE GOT SOMETHING FOR YOU.` | **KEEP** | A person, not a menu row lighting up. `DIRECTION.md` §6.1 exactly. |
| E11 | `STAY IN THE LIGHT TONIGHT.` | **KEEP** | Advice, not instruction. Warm without being soft. |
| E12 | `TWO FINGERS SHORT, STILL STRAIGHT.` | **FIX (length), KEEP (line)** | 120 t against a 96 clamp — **it has been rendering as `TWO FINGERS SHORT, STILL STR` on every reading**, and nobody caught it because it takes two in-game days and a Village to reach. → `TWO SHORT. STILL STRAIGHT.` (92 t). And `LORE.md` §8 says of the fingers *"She tells you this exactly once… One scene. Then the weather."* — the shipping game told you every day. |
| E13 | `SOUP'S WARM PAST MIDNIGHT.` | **KEEP — the best line in the game** | `LORE.md` §10.3 nominates *"I kept a bowl"* and this is its sibling. Everything Odo says is about food and none of it is about food. **It is only this good once**, which is the whole argument for §0.4. |
| E14 | `MIND THE WICK, NOT THE FLAME.` | **KEEP** | An aphorism he refuses to explain. 96/96 — zero margin, draws whole. |
| E15 | `I'VE MAPPED WHAT I CAN SEE.` | **KEEP** | Connie's entire character: enormous enthusiasm, carefully bounded scope. |
| E16 | `I FOUND A THING. HONEST.` | **KEEP** | `HONEST.` is the joke and it does not need help. |
| E17 | *(25 daily lines that do not exist)* | **FIX** | §0.4. Thirty written, all priced under the 96 clamp (worst 96/96), in `LORE.md` §12.1's form. |

### F. Guns, spells, items, stats

| # | String | Verdict | Why |
|---|---|---|---|
| F1 | `SPARROW` `KESTREL` | **KEEP** | Birds. Small, fast, real, and a 1998 gun-namer would have shipped them without a second thought. |
| F2 | `BELLOWS` `TINKER` | **KEEP** | `LORE.md` §10.7: *"Guns in this world are agricultural equipment that got a promotion."* A pump shotgun called a Bellows is a workshop tool that moves air. Perfect. |
| F3 | `NETTLE` | **KEEP** | Crude, stinging, common, free. Exactly the pipe-SMG. |
| F4 | `LNGSHDW` `EMBRLNC` `BLKTHRN` | **FIX, all three** | Photographed: `BLKTHRN 5/64` beside `KESTREL 6/12` in the same 78 px slot, one a word and one a licence plate. **And I had the reason wrong at first, which is worth recording**: the slot is 78 px and `BLACKTHORN` is 41 px, so it was never a *pixel* limit — the clamp is `clampi(cap - used, 0, 28)`, **28 triangles = seven glyphs**, and three ten-letter names were mutilated to fit a *triangle* budget. Disemvowelling is the tell: a name chosen at ten letters for a seven-letter box was never chosen for the box. → `HERON` (20 t, joins the bird family; long, still, patient, strikes at range — that *is* a marksman rifle), `STOKER` (24 t; a stoker feeds a furnace continuously, which is what an LMG does, and it is a municipal job title in a world of lamplighters), `THORN` (20 t; **Mabel Thorn** forges it — guns are named after whoever made them, and in this world that is one woman with a shed). All three now have margin inside the clamp instead of sitting on it. |
| F5 | `EMBERLANCE` (spell) vs `EMBRLNC` (gun) vs `LANCE` (spell) | **FIX by renaming the gun** | A three-way collision, and a *fossil*: `spells.hml` §336 records that the fire blast **moved out of** `WPN_EMBERLANCE`'s slot into the spell, whose cooldown is still derived from the gun's RPM. The spell owns the name; the gun was left holding it. Renaming the gun (F4) resolves all three with one edit and leaves `MAGIC_KINETIC.md` intact. |
| F6 | `FLARE` `SHUTTER` `MEND` `KINDLING` `GUTTERING` `LANCE` | **KEEP** | Plain, verb-shaped, trade-skill register — `LORE.md` §4.2: *"You learn them the way you learn to solder."* `SHUTTER` is what you close over a lamp. |
| F7 | `CLUB` `SPEAR` `SWORD` | **KEEP** | Nouns. Nothing to add. |
| F8 | `BOLT` `REVOLVER` `PUMP` `PIPE SMG` (trade rows) | **FIX** | §0.2, photographed at both ends. → the gun's actual name. Measured: the dearest row goes **44 → 40 t** (`REVOLVER 120` → `KESTREL 120`), so the panel's worst window got *cheaper*. |
| F9 | `HND` `CAP` `LAN` `VIT` `ATT` | **FIX** | Photographed: five three-letter stubs in a panel with **250 px of empty room to the right of every one of them**. `LAN` is not a word. **The full table already existed in `client.hml` and nothing was calling it.** → `client_stat_name`. Measured: the panel goes 212 → 300 of a 360 cap, still clearing `probe_hud`'s 36-triangle headroom rule at 44. |
| F10 | `ATTUNEMENT` | **FIX — recommended, NOT diffed** | The only word in the five that a lamplighter would never say, and `LORE.md` §10.6 is absolute: *"Nobody explains the mechanics."* It governs spell slots, potency and cooldown; the register word is **`TENDING`** — one tends lamps, and `LORE.md` §2 has people *"tended in shifts for a very long time."* **I did not write this diff**, because `stats.hml` carries a second copy of the table and `MAGIC_KINETIC.md` §11 is written against the word. That is the owner's call, not an anti-cringe pass's. §6.4. |
| F11 | `HANDLING` `CAPACITY` `LANTERN` `VITALITY` | **KEEP** | Plain, physical, and `LANTERN` is a stat named after an object you are holding. |
| F12 | `CHARACTER` (panel header) | **FIX** | Not because it is bad but because the F1 card calls the same panel `SHEET`. **One thing, two names** — the same defect as `PUMP`/`BELLOWS`, smaller. → both say `STATS`, which is also what the five rows are. |
| F13 | `BRASS` `REPAIR` `BELT` `BED` `PACK` `SOUP` `LAMP KIT` `MAP` `ALMANAC` `CHARM` | **KEEP** | Ten concrete nouns. The `BANDOLIER → BELT` note in `client.hml` is the model for how to shorten one and should be read before anybody shortens another. |
| F14 | `REROLL` | **FIX** | A dice word in a world with no dice; `LORE.md` §10.6. A gunsmith **refits** a gun. → `REFIT`, 28 → 24 t. |
| F15 | `WICK` (offer row) | **FIX** | The row raises the Great Lantern's wick — but `WICK` **is the name of the man selling it**, and the panel header three rows up reads `WICK   LANTERN`. → `TRIM`. Trimming a wick is what a lamplighter does to make a lamp burn better, it is the correct trade verb, and it is not somebody's name. |
| F16 | `GUN` (offer row 0) | **dead — leave** | `cl_offer_name` intercepts kind 0 and returns `g_cl_vw_name[arg]`, so this entry has never been drawn. Named rather than quietly deleted; changing a table's length is not this task's call. |
| F17 | `TRAVEL` `WORK` | **FIX — recommended, not diffed** | Verbs used as nouns for contract rows; neither names a thing you receive. → `ROAD` and `JOB`. Both rows are `NPC_OC_UNBUILT` today, so this is worth zero until they exist. §6.6. |
| F18 | `SPENT` `NO POINTS` `AT MAXIMUM` `TAKEN` `NOT OFFERED` `NOT FORGED YET` `NOBODY HERE` `NO SALVAGE` `YOU HAVE ONE` `TAKEN - HEAVY` | **KEEP, all ten** | The best-written table in the game and nobody has praised it. Two words, factual, **never a scold**. `NOT FORGED YET` is the game admitting a design row has no system behind it, in the player's own words — a better failure than a button that does nothing. `TAKEN - HEAVY` reports a *success* in different words because overloading is a cost and never a refusal. Copy this table's manners. |
| F19 | `CAMP` `VILLAGE` `TOWN` `CITY` | **KEEP** | Four rungs, four ordinary words, no `Hamlet of the Ninth Lantern`. |
| F20 | `NORTH … NORTHWEST` | **KEEP** | Directions. |
| F21 | `X NEXT   C SPEND` / `X NEXT   C TAKE` | **KEEP** | Key, verb. The comment explaining why the close key is deliberately absent is correct. |
| F22 | The 16 site names | **FIX-when-shown** | `client_site_name` has **zero call sites** — not one of these has ever been on screen. As a set: `ASHFORD` `GREYFEN` `COLDSTILE` `OLD KEEL` `HEARTHWAY` `NINE ELMS` `SALTMIRE` `TALLOWDOWN` `WICKHOLLOW` `THE FOLD` `LANTERNMOOR` `EMBERCROSS` are **KEEP** — real English place-name morphology, real suffixes (`-ford -fen -mire -down -moor -cross`), no adjectives. `MARROWGATE` and `BRIARLIGHT` are generator compounds (bone-word + gate, thorn-word + light) → `MARROWGATE`→`MARLOW`, `BRIARLIGHT`→`BRIARFEN`. `SUNDER` is a verb doing duty as a place and it is Tolkien register → `SUNDERN`. `THE LAST LAMP` is portentous *and* spoils the endgame → `LOWWICK`. **And `EMBER HOLLOW` is missing** — `LORE.md` §7 is titled with it and it is the name of the town in every paragraph of that document. §6.3. |
| F23 | `WAKE STAND SEEK WISPS MOTE REACH CHANNEL LIT HORN WAVE CLEAR PATH` (beat names) | **KEEP** | Debug overlay only (`H`), never in a shipping frame. Correct as internal vocabulary. |

---

## 3. THE TWO FIXES I WROTE AND THREW AWAY

Both are here because a critique that cannot be wrong is not worth reading.

**`YOU GET UP AGAIN` → `THE TOWN RELIGHTS YOU`.** I liked it: it makes the respawn diegetic and
points at the fantasy. Then I read the comment above the draw site, which had already answered it —
*"The obvious line is 'you wake at the lantern', and it would be a LIE for the whole first minute:
`sv_tick`'s respawn only uses the lantern `if (sv.lantern_lit == 1)` and otherwise puts you back at
the spawn."* **My line names a place you do not wake in.** Priced afterwards it would also have
truncated: `YOUR LAMP WENT OUT` is 60 t against a 56 clamp. The existing line stays.

**`WAVE 1  x0` → `WAVE 1  3 LEFT`.** Better English. I built it, ran `--demo 80`, and it took the HUD
peak **332 → 354 of a 360 cap** — **sixteen of the twenty-eight triangles left in the entire HUD**,
spent turning `x3` into `3 LEFT` on a line nobody has ever complained about. CLAUDE.md §3 is a hard
rule and an anti-cringe pass does not get to spend the frame budget on taste. The shipped version
suppresses the count when it is zero and is **≤ the old cost in every state**.

---

## 4. WHY REPETITION IS THE REAL ENEMY

A bad line is read once and forgotten. **A good line said too often is retrospectively damaged** —
the fourth time Odo says *"Soup's warm past midnight"* it stops being a man keeping a bowl warm and
becomes a vending machine, and it takes the first three hearings down with it. `LORE.md` §8 already
knows this and says it about Mabel: *"She tells you this exactly once… One scene. Then the weather."*

So the selector matters as much as the words, and this pass fixed it in `src/sim/npc.hml`
(`npc_daily_index`, the one file I own):

- **was:** `hpick(day, who, seed, NPC_LINES)` — a flat hash. Measured over 8 seeds × 5 villagers ×
  600 days: **4003 consecutive-day repeats**, up to 4 of the 6 lines missing from a six-day window,
  and a mean of **3.978 distinct lines per six days** rather than 6.
- **is:** `(base + stride·day) mod n` with the stride drawn from `{1, n-1}`, which is coprime with
  `n` for every `n ≥ 2`. **Any** six consecutive days — aligned to nothing — contain all six lines
  exactly once, and two consecutive days can never collide. Measured: **0 repeats, 0 missing,
  6.0 distinct.**
- **and my first version of it was wrong, and `tools/probe_voice.hml` caught it before anything else
  did.** It cut the days into cycles and tried to rotate each cycle's base off the previous cycle's
  last index, but compared against the previous cycle's *unadjusted* base — a number the sequence
  never actually said. 238 repeats, and an unaligned window lost up to 3 of 6. The shipped version
  is duller, has no branch in it, and is correct for every window instead of for the ones that start
  on a multiple of six.
- **stated, not glossed:** the order is cyclic, so after six days it repeats in the same order. With
  six written lines there is no way to avoid saying one of them again on day seven. If that ever
  feels mechanical the fix is **more lines**, not more shuffling.

---

## 5. THE STYLE GUIDE — four rules, and this is the point of the file

Every wave adds strings and there has been no rule for them. `LORE.md` §10 is the register (civic
not epic, no capital-letter Evil, understatement carries the grief, short sentences and ordinary
words, warm is not soft, nobody explains the mechanics, no military vocabulary). **These four are
how you apply it to a HUD.**

> ### 1. NAME THE THING THAT CHANGED.
> A line that fires on an event must say what the event was, in a noun the player can point at.
> `POST SET`. `CONNIE MOVED IN`. `NOT FORGED YET`. Not `A PATH OF LIGHT`, which names nothing.
> **Test:** could the player draw what you just told them? If not, you wrote a mood.

> ### 2. IF THE PLAYER HAS NOT BEEN TAUGHT THE WORD, YOU MAY NOT USE THE WORD.
> `THE REACH` is legal because a circle on the ground flashes when you cross it and three
> instruments repeat the word. `THE GRID` was not, because it appears in no other string in the
> game. **Test:** grep your noun. If it has one call site, it is jargon, not vocabulary.
> Corollary: **one thing, one name.** `PUMP` and `BELLOWS` were the same gun. `SHEET` and
> `CHARACTER` were the same panel. Two names is not richness, it is a bug.

> ### 3. WRITE THE PERSON, NOT THE SYSTEM.
> Mabel repairs, Odo feeds, Wick refuses to explain, Connie is thrilled, Pip lies. A villager may
> say `THE FOUNDRY WANTS POWER` and may never say `INDUSTRY STAGE 2`. Names go on the parish
> register, not through a generator: **Mabel, Odo, Wick, Connie, Pip** are right; **Blackthorn,
> Longshadow, Emberlance** were three ten-letter compounds that had to have their vowels removed to
> fit a seven-glyph box, which is the tell. **Test:** if you shortened it to fit, you did not choose
> it to fit.

> ### 4. PRICE IT THROUGH THE FONT BEFORE YOU SHIP IT, AND THEN LOOK AT IT.
> `font_tri_cost(hud_font_micro(), s) * 2` against the clamp the draw site actually passes. Mabel's
> best line was 120 against 96 and rendered as `…STILL STR` for ten waves. `FONT_MICRO` has 51
> glyphs: `A–Z 0–9 . , : / % + - [ ] < > ' °♥⌁`. **There is no `!`, no `?`, no lower case**, and
> until this wave there was no apostrophe either — an unmapped character advances the pen and draws
> nothing, silently. **Test:** take the screenshot. Every finding in §0 was invisible in the source.

**Four things that are always wrong in this game**, derived from the above:
`[ABSTRACT NOUN] [VERB]S YOU/IT` as a sentence shape (the game used it four times and only one
survived audit) · a word capitalised into a Proper Concept that has one call site · an acronym
(`SMG`) or a game-system word (`REROLL`, `x0`) in anything a villager or a shop says · a second name
for something that already has one.

---

## 6. REPORTED, NOT FIXED — with the reason each was left

1. **`YOU CAME BACK.` has nowhere true to live.** It wants an `NPC_T_RETURN` topic firing on
   `day - talkday[w] >= 2`; `npc.hml` already stores `talkday`. Adding the topic id is a one-line
   `npc.hml` change **whose visible half is in `client.hml`**, and a sim change whose string is
   un-applied is a half-fix that would render as a stray daily line. Needs an owner of both files.
2. **`probe_hud` §H prices only the strings it happens to enumerate.** `client_talk_line`'s output is
   not among them, which is exactly why a 120-of-96 truncation on the game's best-known line
   survived ten waves behind a green probe. It also prices a toast literal — `THE DARK IS COMING
   BACK` — **that is not a string in this game.** The right fix is to drive the real
   `client_talk_line` over all `(who, topic, arg)` and price every result.
3. **`EMBER HOLLOW` is not in `client_site_name`'s sixteen**, while `LORE.md` §7 is titled with it.
   Also: `LORE.md` calls the currency **Ember**; `npc.hml` §7 calls it **Salvage** and gives the
   better reason (*"brass casings, wire, lamp glass… what a lamplighter brings home"*). **`LORE.md`
   should adopt Salvage**, not the other way round — see §9.
4. **`ATTUNEMENT` → `TENDING`** (F10). Two copies of the table (`stats.hml`, `client.hml`) and
   `MAGIC_KINETIC.md` §11 written against the word.
5. **`GUTTERING` is both a spell and the brownout line's verb** (`THE LIGHTS ARE GUTTERING.`). Mild
   and arguably a nice rhyme; renaming the spell would desync `MAGIC_KINETIC.md` §1.9.
6. **`TRAVEL` / `WORK` offer rows** (F17). Both `NPC_OC_UNBUILT`; worth zero until they exist.
7. **`g_TB_PROMPT` is not exported**, so `probe_hud` carries a hand-copied `108` — the stale-literal
   class CLAUDE.md records twice already. My diff bumps both by hand; the right fix is to export it.
8. **Three strings still draw with no contrast plate**, against CLAUDE.md §9.9: the wave readout at
   (4,16) *(another agent gave the F1 hint a plate this wave and left this one)*, `g_l_verdict`, and
   the crossing toast. Photographed: `25M OUTSIDE THE REACH` in grey over the moon is barely
   legible, and `WAVE 1 x0` over a noon sky is worse.
9. **`IT'S GOING TO GET THEIR ATTENTION` is 135 px wide inside a 124 px plate**, so it overhangs both
   ends. Pre-existing, photographed, and a plate-width fix rather than a writing one.
10. **`probe_hud`'s `g_PANEL_CHAR = 212` and `g_PANEL_TRADE = 208` go stale** under §8 (measured 300
    and 216). Both assertions still pass — the headroom rule clears at 44 — but they are now
    measuring numbers the game does not produce.

---

## 7. MEASUREMENTS

Compiler verified per RULE 0: `hemlockc` printed `107` then `5120738502741017561`.
All timings min-of-run on a permanently busy box; **loadavg stated with every number**.

**Paired A/B, one identical source snapshot, one `apply_voice.py` apart** (loadavg 4.11 / 3.74):

| | base | after | |
|---|---|---|---|
| `--selftest` | PASS 40/40 | **PASS 40/40** | |
| `replay --verify` | 10000/10000 `16594734899016964914` | **10000/10000 `16594734899016964914`** | cosmetics 0 |
| HUD peak, `--demo 80 --seed 1337` | 334 / 360 | **330 / 360** | net **−4**, and that is *with* the apostrophe glyph added |
| world triangles, same run | 1791 / 3000 | **1789 / 3000** | |
| fps / frames over 16.67 ms | 59.5 / 81 of 4765 | **59.5 / 81 of 4763** | |
| CHARACTER panel | 212 | **300** / 360 | the long stat names; headroom 60 ≥ 36 |
| TRADE panel | 208 | **216** / 360 | worst *row* got cheaper, 44 → 40 |
| `probe_hud` | 16/16 | **16/16**, 0 strings over budget | went **red at 112 > 108** first, see §0.1 |
| `probe_npc` | 269/269 | **269/269** | |
| `probe_teach` | 87/87 | **87/87** | |
| `ci_imports.sh` | 8/8 PASS | **8/8 PASS** | |
| `ci_unbox.sh` | PASS, 0 boxed | **PASS, 0 boxed** | |

**`tools/probe_voice.hml` — 17/17, and sabotaged before it was trusted.** Reverting
`npc_daily_index` to the flat hash in a scratch copy of the whole tree changed the binary
(`2cd057c0…` → `78659348…`) and took the probe to **13/17 with exit 1**, failing exactly P1, P1b, P1c
and P2 and leaving P3 (purity) and P4 (range) green — the correct shape, because purity and range
were never what was broken. The probe also runs that negative control **in-process on every run**
(§C) and asserts the flat hash *fails*, so a future refactor that makes it pass reports that this
probe is measuring nothing instead of going quietly green.

```
                         shipping selector      flat hash (control / sabotage)
consecutive repeats              0                      4003
worst lines missing / cycle      0                         4
distinct per 6 days            6.0                     3.978
unaligned 6-day window           0 missing                 5 missing
```

**Every rewrite priced through the real font**, worst case in each slot:
`THE TOWN GETS IT` 52/68 · `999M SHORT OF THE REACH` 76/84 · `THEY HEARD IT` 44/68 ·
`MORE LANTERNS` 48/60 · `THORN` 20/28 · `HERON` 20/28 · `STOKER` 24/28 ·
`KESTREL 120` 40/72 · `TRIM 240` 28/72 · `REFIT -` 24/72 · `ATTUNEMENT` 40/72 ·
30 daily lines, worst **96/96**, none over · 5 first-meeting lines, worst 92/96 ·
`IT'S GOING TO GET THEIR ATTENTION` **112/112** with the apostrophe.

**Frames looked at** (320×180, upscaled 4× to read): intro card · lantern prompt before/after the
apostrophe · death banner · plant prompt + reach line · `25M OUTSIDE THE REACH` over the moon ·
`[E] MABEL / [T] TRADE` · the talk line before (`MM. YOU RE ON THE ROTA.`) and after
(`MM. YOU'RE ON THE ROTA.`) · CHARACTER before (`HND CAP LAN VIT ATT`) and STATS after
(`HANDLING CAPACITY LANTERN VITALITY ATTUNEMENT`) · trade panel before (`PUMP 65`) and after
(`THORN 0 / KESTREL 40 / BELLOWS 65`) · the ammo plate before (`BLKTHRN 5/64`) and after.

---

## 8. THE DIFFS — everything in a file this task does not own

**They are in `docs/design/VOICE_DIFFS.patch`, and the file itself says not to run `patch` on it.**
`main.hml` moved four times while this ran, so its line numbers were stale before the patch was
written. The apply script reproduced at the end of that file performs the same 24 edits as **exact
string replacements**, asserting each old text appears exactly once — so it either lands correctly
on a moved file or refuses and names the anchor it could not find. Verified against
`main.hml 8dcf8af0…`, `client.hml 6af8b5b2…`, `hudgen.hml 09187344…`.

- **A — `src/game/client.hml`, 10 replacements.** Gun names → `HERON`/`STOKER`/`THORN`; village trade
  names → the gun's actual name; `REROLL`→`REFIT`, `WICK`→`TRIM`; `THE LAMPS ARE OUT`→`THEY HEARD
  IT`; `A PATH OF LIGHT`→`MORE LANTERNS`; the `TINKER SMG` card removed; five first-meeting lines;
  `NPC_T_KIT` moved in from `main.hml`; thirty daily lines + `NPC_LINES_MAX`.
- **B — `src/game/main.hml`, 10 replacements.** `THE GRID TAKES IT`→`THE TOWN GETS IT`;
  `OUTSIDE`→`SHORT OF`; the wave readout; `CHARACTER`→`STATS` in both places;
  `client_stat_short`→`client_stat_name`; `g_VERSION`; `g_TB_PROMPT` 108→112; and **the two
  `hud_worst_case` literals**, without which `--scene hud_worst_case` would be pricing strings the
  game no longer contains.
- **C — `src/art/hudgen.hml`, 3 replacements.** The apostrophe: `HUD_MICRO_N` 50→51, the codepoint,
  and one 6-row bitfield. **Appended, not inserted**, so glyph indices 0–49 and their `ATLAS_HUD`
  UVs do not move.
- **D — `tools/probe_hud.hml`, 1 replacement.** The two hand-copied `108`s → `112`. §6.7.

Applied and measured together in a scratch copy of the whole tree; the numbers are §7.

---

## 9. WHAT `LORE.md` GOT RIGHT, WHICH WAS THE SURPRISE

I was asked whether the lore writes cheques the game does not cash. **It does not, and the problem is
the opposite one.** `LORE.md` is the best-written document in this repo. §10 (REGISTER) and §13
(THINGS DELIBERATELY LEFT OUT) are exactly the discipline this task was sent to impose, §11 separates
eight fixed facts from fourteen open ones, and §9 refuses to answer its own central question in v1 —
*"If you find yourself writing the answer, stop and write another one of Odo's soup lines instead."*
That is a document that knows what restraint costs.

**The gap is enforcement, not authorship.** Every single FIX in §2 is a violation of a rule already
written down in `LORE.md` §10 by somebody who then had no way to make the HUD obey it. That is what
§5 is for, and it is why `LORE.md` §15 now points here.

One correction back the other way: **`LORE.md` should adopt `SALVAGE` for the currency.** It says
Ember; the code says Salvage; and `npc.hml` §7 gives the better reason — *"brass casings, wire, lamp
glass… what a lamplighter brings home… and it is weightless, because a purse is not a load."* Ember
stays the *substance* (§1, compressed light). Salvage is what you sell.
