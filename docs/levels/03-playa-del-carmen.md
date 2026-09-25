# Level 3 -- Playa del Carmen

**Status: third pass -- slanted wake that sweeps the beach, VIP sign art in. VIP frontage, left-hand bay and ~8s warning confirmed good in playtest.**

## Look

A sleek white beach club: curtained daybeds, palapas, a sunken lounge with bright
cushions. Sunny and polished after Veracruz's storm -- a deliberate swing back
from grey to glamour.

## Layout: the bay is on the LEFT

The reverse of both earlier levels, so muscle memory works against you. The
service bay sits on the far left; the beach club's frontage runs down the right.

## Mechanic 1 -- VIP frontage

The beach club's whole beachfront, from its daybeds down to the water on the
right-hand side (x 205-348), is VIP. **Seaweed there costs triple reputation.**

It runs to the waterline rather than sitting up by the club because that is
where seaweed lands -- a strip at the top of the sand would almost never see any.
With the skip on the far left, every VIP pile is the longest haul in the game:
the "prioritise WHAT you pick up" pressure, turned into geography.

Marked by a velvet rope on brass posts down the beach, a VIP sign at its head,
and a 7% warm tint. The sign uses `assets/sprites/vip_sign.png` if present,
otherwise a plaque drawn in code. The rope **pulses red** while anything lies inside, and the HUD reads
SEAWEED IN THE VIP AREA.

## Mechanic 2 -- the Cozumel ferry (signature event)

Every ~55s (+/-10%, first at ~35s) the ferry's horn sounds from beyond the edge
of the screen; ~2.4s later it appears and crosses the deep water, in either
direction, trailing a V-shaped wake.

**The shoreward arm of that V is the wave.** It rises from the stern toward the
beach at a 20 degree slant, moves with the boat, and where it meets the shore it
sweeps along the beach in the direction the boat went -- carrying HALF of the
seaweed already drifting in the water up onto the sand as it passes. The other
half drifts on as usual; anything behind the ferry's lane is out of the wave's
path; a wake over empty water does nothing.

### Why the ferry is fast

At a 20 degree slant, the arm reaches the beach ~520px behind the stern -- wider
than the screen. So the wave cannot touch the sand while the boat is in view; it
arrives after the boat has passed, exactly as a real ferry wake does. At the
original 45 px/s that meant waiting ~19s after the horn. At 90 px/s the first of
it lands ~9.4s after the horn (close to the ~8s that playtested well) and sweeps
the whole beach in ~4s. The horn sounding before the ferry appears is what makes
room for the warning.

### How the wave reads

The crest is jagged and choppy, with a dark shadow behind it -- on bright
turquoise a white line alone nearly vanishes. Broken foam and flecks churn
behind it, spray is thrown off the whole crest, and where it meets the beach a
steady plume of spray travels along the shore with the contact point. The
seaward arm of the V is drawn fainter. First contact shakes the screen.

### History

1. Dropped eight NEW clumps along the whole waterline -- too much on foot.
2. Carried half the existing drifting seaweed on a full-width crest -- right
   mechanic, but the crest spanned the whole screen and read as a line, not a
   ferry's wake.
3. The slanted V arm, emerging from the boat and sweeping the beach (current).

**Art:** `assets/sprites/ferry.png` (58x25 at 2x, bow facing right; mirrored for
crossings to the left) and `assets/sprites/vip_sign.png` (17x26 at 2x). The horn
is still synthesised (`tools/make_ferry_audio.py`).

## Tuning knobs

All in level 3's entry in `scripts/beaches.gd`:

| | Value |
|---|---|
| VIP weight | 3.0 |
| VIP span | x 205-348 |
| Ferry first / every | 35s / 55s |
| Ferry speed | 90 px/s |
| Wake angle | 20 degrees |
| Share of drifting seaweed per wake | 0.5 |

## Playtest -- what to feel for

1. Does the VIP frontage change which piles you go for, or do you just clear
   everything anyway?
2. Is triple the right weight? Too low and it is ignored; too high and the rest
   of the beach stops mattering.
3. Does the wake feel like a surge you can plan for, now that it carries
   seaweed in rather than creating it?
4. Is 55s the right rhythm, or does it crowd out the ordinary spawns?
5. Does the left-hand bay trip you up in a way that is fun, or just annoying?
