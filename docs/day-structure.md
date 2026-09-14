# Planned: Days as the outer loop

**Status: agreed in principle, not scheduled. Nothing below is built.**

## The shape

The three shifts become **Day 1**. Finishing shift 3 rolls over to **Day 2** — a
fresh set of three shifts with a new background, music that did not play on Day 1,
and **all upgrades stripped**.

The stated intent matters more than the mechanic: it should read as *a new level
with new challenges*, not as losing everything you earned. That framing is the
design constraint, and it is the thing most likely to be got wrong.

## Why it needs compensating structure

Stripping upgrades is a strong move and it cuts both ways. On the good side it
resets the difficulty curve, makes tier-1 gear meaningful again, and gives each
day a clean arc. On the bad side, a player who has just spent three shifts
building a tractor will read a silent wipe as punishment however it is framed.

So a day rollover probably needs **at least one of**:

- Something carried forward that is visibly not gear — a title, a tally, a
  cosmetic, a permanent small bonus.
- A new mechanic introduced on Day 2 that the old gear could not have solved, so
  the reset reads as "different problem" rather than "same problem, worse tools".
- A narrative reason stated plainly on the rollover screen. The FIRED panel
  taught us that saying *why* defuses a lot: a wipe with a stated reason lands
  very differently from a wipe without one.

Day 2's unique challenges are undecided. That decision should come **before**
implementation, because it determines whether the reset feels earned.

## What the current code assumes, and would need changing

Worth knowing now so we stop hard-coding these:

- `Levels.LIST` is a **flat array of three**, and `level_index` walks it. Days
  would make this a list of lists, or add a `day` field and a lookup.
- `free_play` triggers after the last entry in that flat list. It would have to
  mean "after the last day", not "after shift 3".
- The save stores `level_index` and `owned`. It would need a `day` too, and the
  rollover would have to clear `owned` while preserving whatever carries forward.
- `_shift_start` (the failure-retry snapshot) is per shift. A day rollover must
  not let a failed shift 1 of Day 2 restore Day 1's gear.
- `Game.difficulty()` and `rot_scale()` read from the current level. Day 2's
  curve would presumably restart lower but sit above Day 1's — those numbers are
  a tuning question, not a structural one.
- Music is per level via `lv.get("music")`, so a per-day playlist already fits.
  The playlist-swap bug (new track starting over the old) is fixed, which this
  would have hit hard.
- Backgrounds are per level only in the sense that `main.tscn` holds one. A
  second day needs the background and its water frames swappable at runtime, not
  baked into the scene.

## Sequencing suggestion

Decide Day 2's distinct challenge first. Then the structural work (days, save,
rollover screen) is straightforward and testable; the art and music are a known
pipeline. Doing it in the other order risks building the plumbing around a
mechanic that turns out not to fit.
