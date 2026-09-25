# Level 4 -- Cozumel

**Status: first rough. Awaiting playtest.**

## Look

The resort at night: silhouetted buildings with glowing amber windows, string
lights, tiki torches, an underlit pool. Moonlit silvery sand and a near-black
sea. After three daylight levels, the first real change of mood.

## Mechanic -- the night shift (fog of war)

The playable beach is dark. The resort band keeps its painted night look; the
darkness fades in below it (`shaders/night.gdshader`, driven by
`scripts/systems/night.gd`).

| Light | Radius | Why |
|---|---|---|
| Worker's lantern (on foot) | 62px | The level becomes a search |
| Tractor headlights | 110px | The upgrade transforms the level, not just its speed |
| Tourists' phones | 20px, plus a bright dot drawn above the dark | You can always see where people are |
| The service bay | 58px | The skip can always be found |
| Three torches + the pool | 40-46px | Fixed pools of light, found in the art |

Light falls off in four hard bands on a 2px grid rather than a smooth gradient,
so the darkness reads as part of the pixel art rather than a filter.

At darkness 0.86, seaweed in the dark is a faint dark shape: you can tell
something is there, but not how much or how rotten. Raising darkness toward 0.92
makes it close to invisible; lowering it makes the level easier.

**Tourists are never invisible.** Walking into people you had no way to see
would be unfair rather than hard, so each carries a phone glow.

## Signature event -- the clouds part

Every ~70s (+/-15%, first at ~45s) the moon comes out for ~9s: the darkness
lifts to 30% of normal, easing in and out over 1.5s. A window to spot every pile
and plan a route before the dark closes back in. The HUD reads THE CLOUDS PART
-- LOOK AROUND.

Calm and rewarding rather than punishing, in keeping with the tone.

## Interactions worth watching

- **Happy Hour at night.** The mirrorball's flecks are drawn above the darkness,
  so they sweep across the black beach as moving points of light. Untested in
  play, but potentially the best moment on the level.
- **Storms at night.** Rain is also drawn above the darkness.
- **Music.** Level 4 has no soundtrack of its own yet, so it plays the default
  shift playlist.

## Tuning knobs

All in level 4's `night` block in `scripts/beaches.gd`: `darkness`, `lantern`,
`headlights`, `phone`, `bay_light`, `lights`, `moon_first`, `moon_every`,
`moon_len`.

## Playtest -- what to feel for

1. Is the dark a search, or a guessing game? (darkness 0.86)
2. Is the lantern big enough on foot to be workable in shift 1?
3. Do the tractor's headlights feel like a real upgrade here?
4. Does the moon come often enough to plan by, or so often it removes the
   challenge?
5. Are tourists readable enough to avoid in the dark?
