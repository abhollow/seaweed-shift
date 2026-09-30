# Level 9 -- Akumal

**Status: first rough. Awaiting playtest.**

## Look

A turtle-nesting beach below a quiet eco-resort: thatched casitas, a stone-edged
cenote pool, palms, and four roped-off nest enclosures on wooden stakes across
the sand.

## Mechanic -- the nests are solid

The four enclosures are measured from the art (`scripts/beaches.gd`, level 9's
`nests`) and are obstacles:

- **The worker** can't walk into one; stepping in slides them to the nearest
  edge of the rope rather than across the beach (`Game.push_out_of_nests`).
- **Tourists** step round them sideways and keep heading for the water
  (`Game.sidestep_nests`).
- **Seaweed** never spawns inside one.

The beach becomes a maze to route through. No two nests sit in line, so each
nest's path down to the sea is clear of the others.

## Signature event -- hatchlings

First at ~35s, then every ~55s (+/-15%): a nest hatches and eight hatchlings
crawl from it straight down toward the sea at 16 px/s, wiggling as they go.

**Any seaweed pile in their path stops them** -- one of sargassum's real harms to
nesting beaches. Clear the way and they carry on.

- Each hatchling that reaches the water pays 3 units' worth of credits, which
  count toward the shift target. A "SAFE!" pops up as each arrives.
- After 25s any still stranded are lost: reputation dips by 4 each (a dip that
  recovers, like a hit).
- HUD: HATCHLINGS! CLEAR THEIR PATH TO THE SEA, then ALL 8 HATCHLINGS MADE IT! or
  N OF 8 HATCHLINGS MADE IT.

It gives the player a positive goal for once -- not just "keep the beach clean",
but "clear the way HERE, now".

## Hatchling art

Two crawl frames (`assets/sprites/hatchling_f0.png`, `_f1.png`, 9x12, drawn at
2x), head pointing down toward the sea: front flippers reaching forward, then
swept back. Each hatchling alternates at 6 fps on its own offset, so the line
doesn't paddle in unison. About a third of a tourist's height -- generous for
real hatchlings, but they have to be spotted on a phone mid-shift.

The forward flippers make the first frame taller than the second, so the usual
slicer -- which crops and scales each sprite on its own -- would have drawn the
shells at different sizes and set the crawl jittering. Both frames are cut with
one shared box, anchored on the shell's tip, and scaled by the same amount.

## A bug the tests caught

The event ended when no hatchlings were *moving*, and a hatchling waiting
behind a pile didn't count as still going. So a hatching whose every hatchling
was blocked -- exactly the situation the level is about -- ended on its first
tick and wrote them all off before the player could act. It now ends only when
every hatchling has reached the sea, or when time runs out.

## Tuning knobs

Level 9's `nests` and `hatch` blocks in `scripts/beaches.gd`, plus
`reward_units` and `lost_rep` in `scripts/systems/hatchlings.gd`.

## Not built

- **Music.** None of its own yet.

## Playtest -- what to feel for

1. Do the nests make routing interesting, or just awkward?
2. Are the hatchlings easy to spot on a phone?
3. Does clearing their path feel urgent and rewarding?
4. Is 25 seconds the right window?
