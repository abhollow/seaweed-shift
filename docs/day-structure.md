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
