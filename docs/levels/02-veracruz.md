# Level 2 -- Veracruz

**Status: fourth pass -- art redrawn so the scenery blows the same way as the wind. Awaiting playtest.**

## Why this level matters

Level 2 is where a player decides whether the game has more to show them. The
earlier level 2 (Isla Mujeres) differed from Cancun only in geometry, which you
barely notice in the first minute. Veracruz changes how you MOVE from the first
second, and says so on the intro card before play starts.

## Look

Overcast Gulf coast in a norte: slate grey and grey-green, a promenade of tiled
roofs, Mexican flags and papel picado streaming right, palms bent over, kites.
Deliberately the opposite of Cancun's sunny turquoise. Green seaweed reads
harder on the grey sand than it does on gold.

The beach shape is close to Cancun's (sand 198px vs 230, shallows 112px vs 110). That is on purpose: **the wind is the one new thing**, so the player learns
a rule rather than a new beach and a rule at once.

## The mechanic: the norte

A constant wind blowing left to right, with gusts. All numbers live in
`scripts/beaches.gd` (level 2's `wind` block) and `scripts/player.gd`.

| | Value | Effect |
|---|---|---|
| Base push | 48 px/s | Walking into it you move at 63% speed |
| Gusts | every ~13s (10-16), 4s long | Push rises to 2.7x -- 130 px/s -- at the peak |
| Peak gust, on foot | 130 px/s | **Exactly cancels walking speed: into it, you stand still** |
| Standing still | 30% of the push | You brace, so you creep rather than slide |
| On a tractor | 45% of the push | Still drives into a peak gust at 106 px/s |
| Wading | 130% of the push | Footing is worse in the water |
| Floating seaweed | 25% of the push | Rafts slide along the coast, wrapping at the edges |
| During a storm | x1.5 | A norte and a storm together is the worst of both |

**Tourists** are shoved by gusts only -- about 86px per gust (drunks 143px) --
and lean into them, a visible tell. Not by the steady wind: that would walk every
tourist into the downwind wall over their lifetime, which is where the bay is. On
a windy beach they also arrive a little upwind so gusts carry them across the
sand rather than into the corner.

### First pass vs second

The first pass (30 px/s base, 2.4x gusts, tourists unaffected) played as "a
minor inconvenience" -- a slope rather than a force. The retune is built around
one number: a peak gust exactly cancels walking speed on foot. That makes the
wind something you plan around rather than lean against: wait a gust out, or use
the warning to get where you are going first. A gust takes 2 seconds to peak and
opens with a whoosh, so the warning is real.

**Caught before shipping:** the first tourist shove (0.8) passed its one-frame
test, but integrated over a whole gust it carried a tourist 228px -- two-thirds
of the beach -- and pinned 39% of them against the bay wall. At 0.3 with upwind
spawning, 1.6% end up there. A test now integrates a full gust.

The first gust arrives early (about 6 seconds in), so a player meets it before
they have settled into Cancun habits.

**Music:** three tension tracks (Tropical Tension 1-3), replacing the brighter
Island Jump and Island Vibes -- a storm level should sound like weather, not a
holiday. Those two are currently unassigned.

**Seen and heard.** Sand streaks blow across the whole beach, multiplying during
a gust; a wind bed plays under the music and swells with each gust, and every
gust opens with a whoosh. The audio is synthesised placeholder
(`tools/make_wind_audio.py`) until real recordings are chosen.

**How it plays against the layout.** The service bay is on the right --
downwind. A loaded trip to the skip is quick; the empty walk back is into the
wind. That rhythm is the heart of the level.

## Storms wait for the tractor

On foot, a storm's seaweed surge on top of the wind was more than anyone could
clear. Veracruz sets `storms_need: "tractor"`, so storms are held back until it is
owned. The storm timer is held 25 seconds SHORT of firing rather than at the
threshold: at the threshold, buying the tractor set a storm off the very next
frame, which reads as a punishment for upgrading. Happy Hour is unaffected.

## The art has to agree with the wind

The first Veracruz art contradicted itself: the flags flew right, but every palm
leaned left and the kite tails trailed left -- against a wind that blows right.
The sway shader leans foliage downwind, so on those palms it was fighting the
painting. Flipping the image was not an option: it would have moved the plaza
and the skip upwind, killing the quick downwind run to the bay.

Regenerating with the old art as a reference failed four times over -- the
reference dominated and copied the left-leaning palms exactly. What worked was
dropping the reference and running the prompt both ways at once: everything
blowing right, and everything blowing LEFT with the plaza on the left (to be
mirrored). The model's habit is left-leaning palms, so asking for consistency
in either direction and mirroring if needed is the reliable approach.

## The palms sway

The palms, flags and kites are painted into the background, so they cannot be
animated as sprites. A shader (`shaders/sway.gdshader`) shifts only the pixels a
mask marks, leaving buildings and trunks still. It is driven by the wind system:
a steady downwind lean, plus a wobble, both of which grow with the current gust --
so the palms whip hardest exactly when a gust shoves the player. The intro card
runs its own slow swell, since the game's wind is paused behind it.

The mask (`assets/sprites/sway_level2.png`) is built by
`tools/make_sway_mask.py`. Its first version also caught the green pennants in
the bunting and bushes at the promenade, and the swing margin around them
dragged the building walls along -- the houses wobbled. It is now cut off above
the rooftops (`--below 62`).

## Deliberately NOT done yet (candidates for iteration)

- **Beached seaweed tumbles in gusts.** Small clumps skitter along the sand
  during a gust. Most visible form of the wind; risky because piles would drift
  into each other and merge.
- **Carnaval de Veracruz.** One of Mexico's biggest carnivals. Would replace
  Happy Hour on this level: a parade crowd crossing the beach in a line, confetti,
  a brass band sting. Gives the level its own event rather than a reskin.
- **The wind turns.** Mid-shift the norte could swing and blow right to left,
  forcing the player to re-learn their routes.
- **A wind vane in the HUD** so the strength is readable without watching the
  sand.

## Playtest -- what to feel for

1. Does the wind read as a new rule within the first 10 seconds, or only after
   you notice you are drifting?
2. Is walking into it satisfying resistance, or just tedious? (30 px/s is the
   knob.)
3. Do gusts feel like events you react to, or random annoyance?
4. Does the tractor's resistance to wind feel like a reward?
5. Does floating seaweed sliding along the coast help you read the wind, or
   just make it harder to predict where piles land?
