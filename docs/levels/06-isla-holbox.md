# Level 6 -- Isla Holbox

**Status: third pass. Streets and central skip confirmed good in playtest; seaweed slowed 25% on every shift.**

## Intent

A change of pace and picture, **not** a step up in difficulty. The skip is in
the middle of the island, so every trip is short and collecting is easy. What
changes is how the level moves and what happens on it.

## Look

A tiny round island seen from above: a village of colourful homes -- flat roofs
and thatched palapas -- with **eight sandy streets radiating from an open central
plaza** out to the beach, like the spokes of a wheel. A ring of white sand, a ring
of bright turquoise shallows, and deep water on every side.

## Why the skip moved to the centre

In the first pass the skip sat on the compound's left edge. With seaweed arriving
from every side, that made the far side of the island always the longest trip --
the round layout became a handicap rather than a twist. Now the skip is in the
central plaza and every side of the beach is the same short walk away, down
whichever street is nearest.

## The round island (a new layout model)

Every other level is horizontal bands -- resort at the top, sea at the bottom --
so "how far out to sea" was simply y. Holbox has sea on every side, so it is the
distance from the island's centre. Every system now asks `Zones.depth()` and
moves along `Zones.outward()`; on a banded beach these return exactly y and
straight down, so the other nine levels are untouched (the whole suite passed
unchanged through the rewrite). On Holbox the zone values are radii:

| Ring | Radius |
|---|---|
| Central plaza (the skip) | 34 |
| Edge of the village | 128 |
| Waterline | 155 |
| Deep line | 208 |
| Furthest anything goes | 270 |

- **The worker walks the whole way round** the beach ring, and **inward along any
  of the eight streets** (24px wide, at 45 degree steps) to the plaza. The homes
  between the streets are solid: stepping into one slides the worker to the
  nearest open ground -- the street alongside, the plaza or the beach -- rather
  than jumping them across the village.
- **The beach ring is narrow** -- about 27px, roughly one worker wide -- because
  the village takes most of the island. Wading just past it is part of walking
  round.
- **Seaweed arrives from every side** and washes up all round the ring.
- **Tourists walk out of the village along the streets** and back again, with
  their sideways weave cut to 30% so they stay in the street. No
  deep swimmers: most of the island's deep water is off the sides of the screen.
- **Buoys ring the island** at the deep line.
- The horizontal animated water strip is switched off -- it cannot follow a ring.

**25% less seaweed, on every shift** (`spawn_scale: 0.75`). It arrives from all
360 degrees, so covering the beach takes more walking than a straight one even
with the skip in the middle -- playtest found the standard rate too much.

**Storms and Happy Hour are switched off** on this level (`no_storms`,
`no_happy_hour`). Three signature events take their place.

## The three events

One at a time, rotating, never the same twice running: first at ~20s, then every
~32s (+/-15%). Each eases in and out over 1.5s.

**Whale shark (13s).** Surfaces off the top or bottom of the island -- where
deep water is on screen -- and five tourists stream out down the street facing
it, in a line. A crowd surge on one side. HUD: WHALE SHARK! TOURISTS RUSHING IN.

**Low-tide sandbar (16s).** The tide drops and a sandbar grows out of the beach
into the deep, above or below the island, with three kelp clumps (3x value) out
near its end. **You can walk out on it without the trawler**, dry underfoot. Step
sideways off it past the usual limit and you are held to its edge rather than
dropped in the deep. As the tide returns the bar shrinks back and eases you in
with it. HUD: LOW TIDE -- WALK THE SANDBAR, then TIDE'S COMING BACK IN.

**Flamingos (20s).** A flock of four lands on a stretch of beach **midway
between two street mouths**, and narrow enough to leave both clear -- so all
eight routes to the skip always stay open. You cannot walk into their
stretch (you are moved along the beach to its edge, never into the sea), and
nothing can be gathered from under them. HUD: FLAMINGOS! WAIT FOR THEM TO MOVE
ON.

**Art:** `assets/sprites/whale_shark.png` (52x22, seen from above, head right,
drawn rotated to its heading) and `assets/sprites/flamingo.png` (11x20, facing
right, drawn at 2x and randomly mirrored per bird). The sandbar is drawn in code.

The flamingo was generated on GREEN -- a magenta key would have removed a pink
bird -- and keyed by colour distance plus "strongly green". Its legs are thin
enough to vanish when shrunk, so the alpha is widened before the downscale; that
first pulled in the green background's colour and tinted the legs green, so the
background is now filled with the outline's dark plum before widening.

## History

- **Skip moved from the compound's edge to a central plaza** reached by eight
  streets; the old resort-compound art was replaced with a village.

- The flamingos were first drawn at the tourists' scale divided by three, and a
  flock read as a pink smudge; at 2x, eight packed into the arc merged into one
  pink mass. Now six, spaced at least 24px apart, drawn back-to-front.

## Tuning knobs

All in level 6's `holbox` block in `scripts/beaches.gd`.

## Playtest -- what to feel for

1. Does walking round the ring feel natural, or does it fight the controls?
2. Do the events feel like a change of pace, or interruptions?
3. Is the sandbar worth the walk out?
4. Do the flamingos create an interesting wait, or just an annoying one?
5. Is the island readable -- can you tell sand from shallows all the way round?
