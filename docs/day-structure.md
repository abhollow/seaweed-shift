# Planned: Levels as the outer loop

**Status: the loop is BUILT.** Levels, shop theming, retention and the ten-level
arc all work and are tested. Still to do: each level's own backdrop, music and
signature event -- every level currently reuses the Cancun beach.

**The game is "Seaweed Shift: Mexico".** Each level is a real Mexican location;
Cancun is level 1, not the game's name.

## As built

| Shift | Shop features | |
|---|---|---|
| 1 | Tier 1 -- on foot | rake, jacket, backpack, waders |
| 2 | Tier 2 -- the tractor | tractor, sand tires, sorter |
| 3 | Tier 3 -- deep water | diesel, hopper, trawler |
| 4 | Everything | the payoff shift, fully equipped |

Anything from an earlier tier that was **not** bought stays in the shop, so the
player is never locked out -- skipping the waders in shift 1 does not cost them
the shallows forever. Owned upgrades are hidden rather than listed.

**Retention.** Tiers are retained in order -- all four on-foot upgrades first,
then the tractor tier, then deep water. 4 + 3 + 3 = **exactly ten levels**, after
which nothing is left to keep and the campaign is complete.

An upgrade can only be retained once its **prerequisite** is: keeping Sand Tires
without a tractor would be a permanent upgrade that does nothing. This makes a
few choices forced -- level 5 must take the tractor, since everything else in its
tier needs one -- which is thematically right: the tractor is the tier.

**Why 4 / 3 / 3.** The original file split the machinery 5 / 1, putting only the
trawler in deep water. That left shift 3's shop with a single item. Moving the
hopper and diesel to deep water gives every themed shift a real shop and keeps
the arc at ten levels.

**Each level is 7% harder** than the last (`Game.LEVEL_STEP`), on top of the
per-shift base and the within-shift ramp. Gentle, because by level 10 the player
starts with nine upgrades already owned.

## The loop

A **level** is a set of four shifts on one beach. Finishing shift 4 ends the
level:

1. The player **chooses one tier-1 upgrade to retain permanently.**
2. The next level begins on a **new beach** — new backdrop, new music, a new
   weather event, a new personality.
3. All other upgrades reset. Retained ones carry forward.
4. Every shift in the new level is harder than its counterpart in the last.

Repeat. Collecting retained skills across levels is the long-term goal.

## Why the retained skill matters

An earlier version of this plan flagged the real risk of a reset: a player who
spent four shifts building a tractor reads a silent wipe as punishment, however
it is framed. It proposed "something carried forward that is visibly not gear"
but never landed on what.

**The retained skill is that answer, and it is better than the options
considered.** It turns the reset into a choice the player *earned* rather than a
loss they suffered. And it compounds: by level 3 the player starts with two tier-1
upgrades already owned, so the early game of each new level gets faster to clear
— which gives room for that level's new challenge to be the focus.

**Limit it to tier 1.** Retaining a tractor or trawler would let a player skip
the entire tier-2 arc and flatten the difficulty curve every later level depends
on. Tier 1 (rake, jacket, backpack, waders) is exactly the grind worth removing.
Four tier-1 upgrades means four levels before the pool is exhausted — a natural
length for the campaign, after which the choice could widen or become cosmetic.

## Each level needs a personality

Per the playtest: a new level must feel different, not just harder. Minimum per
level:

- **Backdrop** — a different beach. The pipeline for this is proven: generate,
  measure the bands, remap onto the zone boundaries, rebuild the water frames.
- **Music** — tracks that did not play in earlier levels.
- **A signature weather event** — one new event introduced per level, joining
  storms and Happy Hour rather than replacing them. Candidates below.
- **A rule twist** — optional, but the strongest lever for "different". Examples:
  kelp worth more, tourists who throw litter, a tide that moves the waterline.

## Candidate events

Kept deliberately calm to match the relaxed-but-rewarding tone. The failure mode
to avoid is anything that tests reaction speed — frantic is the wrong direction.

- **Low tide.** The waterline recedes, exposing a wide band of stranded seaweed
  and briefly making deep water reachable without the trawler. Opportunity rather
  than threat: a burst of easy value if you get there in time.
- **Red tide.** An algae bloom tints the sea and speeds up rot everywhere. A
  pure prioritisation event — it rewards exactly the triage that rot spread was
  built to encourage.
- **Night shift.** Visibility narrows to a circle around the player. Quiet and
  atmospheric; changes how the beach is read rather than how fast it fills.
- **Cruise ship.** A wave of tourists disembarks in one direction, crossing the
  beach as a group. Readable and avoidable, unlike Happy Hour's scatter.

## What the code currently assumes

- `Levels.LIST` is a flat array (now four shifts). Levels need a list of lists,
  or a `level` field and a lookup.
- `free_play` triggers after the last entry. It should mean "after the last
  level", or disappear entirely if the campaign is open-ended.
- The save stores `level_index`, `owned` and `credits`. It needs a `level`, a
  `retained` set, and a rollover that clears `owned` except `retained`.
- **`_shift_start` (the failure snapshot) must never restore across a level
  boundary.** A failed shift 1 of level 2 must not bring back level 1's gear.
  This is the bug most likely to ship if nobody is looking for it.
- `Game.difficulty()` reads the current shift, ramped by progress. A level
  multiplier would sit on top of it.
- Backgrounds are baked into `main.tscn`; a second beach needs the background and
  its water frames swappable at runtime.

## Sequencing

1. Build the rollover and the retain-a-skill screen against the **existing**
   beach. It is the structural piece and it is testable without new art.
2. Then level 2's backdrop, music and first new event.
3. Tune the level multiplier by playing, not by estimate — shift 1 on foot is the
   calibration point the player has confirmed feels right.


## Level-by-level process (agreed)

Each level goes through the same loop before the next begins: brainstorm how it
looks and plays -- what is different, its events, its challenges -- build a
first playable version, playtest, revise, and approve. Mechanics are built per
level as each is reached, rather than all at once: every mechanic changes once
it is played, so building eight blind would mean building eight things twice.

Each level's rundown lives in `docs/levels/NN-name.md`.

Every level opens on an **intro card** -- the location in the wordmark's type
over its own art, a line on what is different here, and START SHIFT! -- so a new
location is a moment the player sees, and a new rule arrives with warning.


## Adaptive difficulty

Rather than hand-tuning each beach, the seaweed spawn rate follows the player
(`Game.adapt`, multiplied into `Game.spawn_scale()`):

| Outcome | Effect on the spawn rate |
|---|---|
| Fail a shift | the retry spawns **10% less** |
| Finish a shift first try | the next shift spawns **6% more** |
| Finish after one or more fails | no change -- that shift was about right |

The asymmetry is the point. The steps balance when roughly **two shifts in three
are finished first try** (ln(1/0.9) / (ln(1/0.9) + ln 1.06) = 0.64), so a player
settles where they mostly succeed but still fail now and then -- never breezing
through every shift, never failing the same one again and again.

Clamped between 60% and 150% of normal. Carried across levels -- it measures the
player, not the beach -- and saved with progress, so quitting mid-way does not
reset it. The failure panel says the beach will be quieter next time; the
summary after a first-try finish says the next beach will be busier.

Per-beach `spawn_scale` (Holbox 0.75) still applies underneath it.

## HUD safe area

The game keeps its 9:16 shape, so on tall phones it is letterboxed, and the
black bars already clear the notch and status bar. The HUD used to add the whole
notch height anyway, pushing MENU and SHOP (and the bottom strip) inward for
nothing. `Hud.inset_in_game()` now counts only the part of an inset that
reaches past the letterbox bar -- zero on most modern phones -- and the buttons
sit 4px from the top.


## Fixes worth remembering

**Music stayed ducked across a shift change.** Storms, Happy Hour and the
upgrade jingle duck the music by 10 dB and restore it when they end. Starting a
new shift cleared them without restoring the level, so a shift that began
mid-duck -- most often straight after buying upgrades, which plays the jingle --
ran its whole length quiet. It showed up on Mahahual, but could hit any level.
`Weather.reset()` now restores the music; a test ducks it, starts a shift, and
checks the level is back.

**The shop ran off the right of the screen.** Upgrade descriptions didn't wrap,
so one long sentence made its label -- and with it the list, the scroll area and
the panel -- as wide as the whole line: 448px on a 360px screen. Descriptions now
wrap, long button text trims with an ellipsis, and the contents are pinned to the
panel. A test opens the shop in its wordiest state and checks nothing reaches
past the screen edge (now 352px).

Both tests were checked to FAIL with their fix removed -- a test that cannot fail
guards nothing.


## Shift length -- pay doubled

Playtesting put shifts at about **10 minutes** -- double the ~5 minute session
mobile players settle into (GameAnalytics' 2025 benchmarks: median-tier games
5-6 minutes, top-tier 8-9), and long across ten levels of four shifts.

A shift ends when its credit target is earned, so shift length is target
divided by earning rate. Pay per unit was doubled -- base 3 -> **6**, Sorter
6 -> **12** (`Game.BASE_PAY`, `Game.SORTER_PAY`) -- which halves the units a shift
needs while earning **exactly the same credits per shift**. Upgrade prices, shop
pacing, the resort bonus and hatchling rewards all stay in balance.

Lowering the targets instead was rejected: it would have halved income per
shift and doubled the shifts needed to afford each upgrade.

Expect around 5 minutes; the summary panel's "Shift time" shows the real
figure. Every level's signature event runs on a timer of a minute or less, so
each still fires several times a shift; ordinary storms (every ~2 minutes) now
come about twice a shift rather than five times. The Tulum hurricane follows
progress rather than the clock, so its whole arc still fits one shift.


## The tutorial

A read-and-tap tutorial plays when a new game reaches level 1, before the
Cancun intro card (`scripts/ui/tutorial.gd`, `shaders/spotlight.gdshader`).

Eight steps -- keep the beach clean (the goal bar), move, rake it up, watch
your load, cash in at the skip, don't let it rot, mind the tourists, upgrade in
the shop. Each dims the screen except what it explains (up to two spotlights --
"don't let it rot" lights a rotting pile AND the reputation bar, so cause and
effect are on screen together), rings it in gold, and puts the tip card on the
opposite side so it never covers its subject. NEXT moves on; SKIP TUTORIAL ends
it; the last button is START SHIFT!.

It covers the basics only: each level's own twist is introduced by its intro
card.

**Staging.** The game is paused behind it with a small scene set up for the
steps to point at -- a big pile, a rotting pile, two small ones, a tourist, the
worker mid-beach -- all cleared away at the end, with the worker back in the bay.

**Music.** The menu hands its music player to the game instead of fading it.
(An AudioStreamPlayer stops when it leaves the scene tree, so it resumes from
the position the menu had reached.) The menu track plays on through the
tutorial -- set to keep running through the pause -- and level 1's music is held
back until START SHIFT!, when it takes over and the menu track fades out. With
no tutorial, the menu track fades out under the level's music as before.

**Once per new game.** `tutorial_done` is saved, so continuing a game never
replays it; a new game starts fresh and plays it again (SKIP is right there).


## Pay split to 4.5, storms made to matter

**Pay 4.5 per unit (9 with the Sorter).** Doubling to 6 got shifts to ~5 minutes
but the on-foot upgrades came too easily; 4.5 splits the difference -- a little
more work for the reward. Pay is carried as a float and rounded only when paid
out at the skip, so no half-credits ever show.

**Storms: every 75s (was 120), lasting 22s (was 14).** The worker drops to 40%
speed without the Rain Jacket (was 55%), tourists to 35% (was 55%). Before, a
player was slowed only ~12% of the time and barely noticed -- the jacket felt
optional. Now roughly a third of each shift is storm, and slow, lingering
tourists make storms crowded as well as slow. Tests pin these values.


## One goal per shift: credits earned

A shift ends the moment its credit target is reached, counting credits EARNED
this shift -- spending on upgrades never sets it back, and skipping upgrades is
no shortcut, since without them you earn more slowly. Upgrades are never
required.

It used to need a second condition as well: reputation held above a target
**continuously** for 90-150 seconds, drawn as a green bar laid over the yellow
credit bar. One dip reset it to zero, so a shift could sail past its credit
target and simply not end -- a playtest hit exactly that and read it as broken.
Removed, with the green bar and the per-shift `hold` times.

Reputation still carries the tension, more visibly: hit zero and the firing
countdown starts; a clean beach earns up to 30% more as the resort bonus. And
earning credits means raking seaweed, which cleans the beach anyway, so there is
no way to grind the target while the beach rots. As playtest put it: being on
the edge of getting fired is tenser, and more obvious, than a hold timer
resetting in its last few seconds.
