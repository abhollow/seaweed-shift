# Level 10 -- Tulum (the finale)

**Status: first rough, with its final art and music. Awaiting playtest.**

## Concept -- the hurricane

The shift starts on a calm, sunny beach below the clifftop ruins, and a
hurricane rolls in over it (`scripts/systems/hurricane.gd`). Chosen over "The
Inspector" and "The King Tide" because it is the only one that feels like an
ending: a build to a climax, a breather in the eye, and a callback to what the
campaign has taught.

It conducts systems the game already has -- the Veracruz wind, the storm's rain
and darkening, the Bacalar surf -- rather than inventing new ones.

| Phase | Starts at | What happens |
|---|---|---|
| Calm | shift start | sunny, still |
| Gathering | 15% of the shift target | the wind picks up (24 px/s, gusts) |
| Front | 35% | the hurricane hits: gale (40 px/s), storm rain and darkness, surf sets |
| **Eye** | 60% | **everything stops for 30s**: sky clears to gold, no wind, no rain, no surf, seaweed at 30% |
| **Back wall** | after the eye | **the wind reverses** -- right to left, harder (46 px/s) -- storm and surf return |

Phases follow **progress** through the shift, not the clock, so the eye always
comes before the end and the storm peaks as the player finishes, however long the
shift takes. The eye alone is timed: once it arrives it gives a fixed 30s.

**The wind reversing is the twist.** Every habit from the front -- walk with it
to the skip, fight it on the way back -- is backwards after the eye. Real
hurricanes do exactly this as the back wall passes.

Every shift starts calm again. Random storms and Happy Hour are off on this
level, so nothing competes with the hurricane.

## Engine changes it needed

- **Wind direction** (`Wind.dir`) and **live wind changes** (`Wind.set_live`).
  Sand streaks, drifting seaweed (wrapping at whichever edge the wind blows
  toward) and the palm sway all follow the direction.
- **A held storm** (`Weather.force_storm`): on for as long as the hurricane says,
  never ended early by the ordinary storm timer.
- The hurricane's per-phase seaweed factor multiplies into `Game.spawn_scale()`,
  alongside adaptive difficulty.

## Art

El Castillo and smaller ruins on a grassy limestone clifftop, upright palms, a
plain limestone plaza on the right for the service bay, and a wide, smooth,
empty beach -- the two rocks at the cliff's foot belong to the cliff, not the
sand. Replaces the old boulder-strewn Tulum.

Zones: sand from 192 (the cliff foot) to the waterline at 390, deep water from
515. Bay at (311, 160), on the plaza's edge.

**The sway follows the storm.** A mask (`assets/sprites/sway_level10.png`,
`--below 46 --sky 0`) covers the palm crowns and the jungle treeline behind the
ruins -- the whole jungle thrashing in the hurricane sells it. Two traps avoided:
the lawn is green and darker than the sky, so the mask stops above it; and the
sky is saturated blue, so the saturated-colour rule is off (it would have
wobbled the temple's edges).

The sway scales with the wind: barely stirring in the calm, whipping in the
storm, and leaning whichever way the wind blows -- so the palms bend the other
way after the eye. The damping only applies below Veracruz-strength wind, so
Veracruz is unchanged.

**Music:** Tropical Storm Reggae 1 and 2.

## Not built

- **A distinct eye visual** beyond the golden tint and the calm.

## Playtest -- what to feel for

1. Does the hurricane feel like it builds, or like switches flipping?
2. Is the eye a satisfying breather -- is 20s the right length?
3. Does the reversed wind land as a twist you have to adapt to?
4. Is the back wall a climax, or just unfair?
