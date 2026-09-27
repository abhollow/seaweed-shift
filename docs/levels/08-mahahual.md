# Level 8 -- Mahahual

**Status: second pass -- mat lands as heaps, music added.**

## Look

A small fishing village on the Costa Maya: a long wooden boardwalk, weathered
beach bars, and a sea choked with brown-gold sargassum mats further out.

## Mechanic -- sargassum season

Half of everything that washes in is **sargassum** (`share: 0.5`):

| | Seaweed | Sargassum |
|---|---|---|
| Slots in your load, per unit | 1 | **2** |
| Value per unit | 1x | **2x** |
| Rot speed | 1x | **1.5x** |

A trip pays the same either way -- twice the value, half as much carried -- so
the pull is urgency: sargassum turns first. Sargassum only piles up with
sargassum, and seaweed with seaweed.

**Drawn deep amber, not brown.** It is the ordinary seaweed art recoloured by a
shader (`shaders/sargassum.gdshader`) that maps its greens onto an amber ramp by
brightness and leaves the outline alone. A colour-multiply tint would have looked
muddy -- and brown is how ROTTING seaweed already looks. The first ramp was straw
gold, too close to Mahahual's pale sand; amber stands off it as clearly as green
does.

**A guard this needed.** The gather step takes a unit off the pile before
handing it to the worker. Checking only "is the worker full?" would have lost a
heavy unit whenever exactly one slot was left. It now checks there is room for
that unit's weight first (`Player.can_carry`), and a test pins it.

## Signature event -- the mat

First at ~30s, then every ~65s (+/-15%): a huge raft of sargassum appears far out
and drifts slowly toward the beach at 12 px/s -- well over twenty seconds of
visible warning, heading straight for where it will land. When it reaches the
shallows it breaks up into sargassum piles (2 units each) across the stretch of
beach it came in on. HUD: SARGASSUM MAT DRIFTING IN, then THE MAT HAS COME
ASHORE.

It comes ashore as **heaps**: big grouped mounds of sargassum, up to 12 units
each (an ordinary pile tops out at 8), with any remainder as a normal pile. A
heap is three large piles composited into one mound
(`assets/sprites/sargassum_heap_f0-3.png` plus a rot overlay), drawn amber by
the same shader; raked down below 6 units it turns back into an ordinary pile.

Units per mat scale with the shift, like the ferry and the big wave: **8 / 12 /
16 / 20** -- one heap on shift 1, up to two heaps and a pile by shift 4.

## Tuning knobs

Level 8's `sargassum` block in `scripts/beaches.gd`: `share`, `mat_first`,
`mat_every`, `mat_speed`, `mat_width`, `mat_piles`.

## Not built

- **Mat art.** The drifting mat is drawn in code.

**Music:** Tense Beach Game 1 and 2.

## Playtest -- what to feel for

1. Does heavy, fast-rotting sargassum change what you pick up first?
2. Is amber easy to spot against the sand?
3. Does the mat's long warning let you plan, and does its landing feel like an
   event?
4. Is 4 piles on shift 1 manageable on foot?
