# Level 5 -- Bacalar

**Status: second pass after playtest ("fun"). Countable sets, smooth knockback, big wave carries seaweed.**

## Look

A surf town: rustic shacks, racked surfboards, a hammock bar, windswept palms,
coarse golden-brown sand. The shallows are painted as heavy breaking surf and the
deep as a dark Pacific swell.

## Mechanic -- sets you can count

Each set is **two or three SMALL waves, then one BIG wave**, 2.4s apart
(`scripts/systems/surf.gd`).

- **Small waves are warnings.** Thin swells that break into a little foam and
  harm nothing. They are there to be counted.
- **The big wave is unmistakable** -- about twice the size, a tall dark face, a
  heavy breaker, and a low roar as it sets off. It is the ONLY wave that knocks
  the worker back, and it carries a share of the drifting seaweed in with it at
  the same per-shift rates as the Playa del Carmen ferry: 20 / 30 / 60 / 80%.

The HUD reads SET ROLLING IN -- COUNT THE WAVES, then BIG WAVE -- GET OUT OF THE
WATER once the big one is on its way. The rhythm: count, work, get out.

**Why it changed.** In the first pass every wave in the set knocked the worker
back. Timing stopped mattering -- you were simply thrown out of the water three
times -- so it read as an annoyance rather than a rhythm to play around.

## The knockback

Carried ~110px shoreward (55px on the tractor) in one eased motion over 0.5s,
leaning back once as the wave takes you, then settling with a single slow sway
over 0.3s. Spray bursts around the worker while the wave carries them. Nothing
is lost -- only ground and time.

**Why it changed.** The first version moved at a constant speed and stopped
dead, all in 0.32s -- about ten frames on a phone -- with a +/-17 degree wobble
shaking five times a second. It read as a teleport. A test now pins it: no more
than 8px of movement in any one frame, spread over at least 25 frames.

## Signature event -- the rogue

Every fourth set's big wave is a ROGUE: it runs 55px up past the waterline onto
the sand, so the lower beach is not safe either. The HUD reads ROGUE WAVE -- GET
UP THE BEACH, and it breaks with a harder shake.

| | Value |
|---|---|
| First set / between sets | 18s / 26s (+/-20%) |
| Small waves per set | 2 or 3, then one big |
| Spacing / speed | 2.4s / 60 px/s |
| Knockback: foot / tractor | 110px / 55px |
| Big wave carries (by shift) | 20 / 30 / 60 / 80% |
| Rogue | every 4th set, 55px run-up |

**Music:** Tidal Rush 1 and 2.

## Not built -- candidates for iteration

- **Tourists get knocked too.** Wading tourists thrown up the beach alongside
  the worker.

## Known risk -- readability

The shallows are already painted as heavy white surf, and the animated breakers
are white foam too. Out in the deep the moving swell reads clearly; in the
shallows the moving waves can blend with the painted ones. Motion helps in play,
but if it is hard to track the answer is to tone down the painted surf rather
than make the animated waves louder.

## Playtest -- what to feel for

1. Can you see a set coming in time to get out of the water?
2. Can you track the moving waves against the painted surf?
3. Is the knockback a setback you plan around, or just annoying?
4. Is the big set's run-up a good surprise, or unfair?
5. Does the tractor's resistance make it feel like a reward here?
