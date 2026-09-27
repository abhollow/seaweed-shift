# Level 7 -- Puerto Morelos

**Status: second pass after playtest -- bridge removed, current stronger, tourists carried too.**

## Look

A small fishing town under its famous leaning lighthouse, mangroves on the left,
and a freshwater stream winding from the mangrove lagoon across the beach to the
sea. The skip is on the right, on the far side of the stream.

## Mechanic -- the stream

The stream's path is traced from the art (`scripts/beaches.gd`, level 7's
`stream.points`) and handled by `scripts/systems/stream.gd`.

- **The current.** Wading through the stream slows the worker to 55% and pushes
  them downstream toward the sea at 85 px/s (60 in the first pass -- playtest
  asked for stronger). A tractor is pushed half as hard. Flow flecks show which
  way the water runs.
- **Tourists are carried too**, at 80% of the worker's push, as they cross.
- **No bridge.** The first pass had a footbridge; playtest found it pointless,
  so the stream must always be waded. The code keeps it as an option
  (`bridge_frac`) for any level that wants one.
- **The mouth.** Seaweed lying in the stream floats down it and piles up at the
  mouth, merging into whatever is already there. Ignore it and the mouth grows
  into the biggest pile on the beach.

## Signature event -- the flash flood

First at ~40s, then every ~60s (+/-15%), for 12s: rain up in the mangroves
flushes five clumps of debris down from the top, one every 0.6s -- you watch
them float down to the mouth. The flow flecks run quicker while it lasts.

The first pass also swelled the stream, doubled the current and turned it
muddy brown; playtest found the debris was event enough. (A wider stream with
no visual to match would also have been a trap.) HUD: FLASH FLOOD -- DEBRIS
COMING DOWN THE STREAM.


## A bug this level found

Tracking down a test that failed one run in two turned up a real bug in how
seaweed piles merge. When two clumps reached the stream's mouth on the same
tick, the first merged into the second and was queued for deletion; the second
then searched for a pile to merge into, found the first -- already dying -- and
merged into it. Both vanished, and the seaweed with them.

The same search runs whenever drifting seaweed washes ashore, so it could delete
seaweed on any level. `find_pile_near` now skips piles already queued for
deletion, and a test checks that directly.

The first two attempts at the flaky test adjusted the test until it passed more
often; both would have hidden the bug. Printing exactly what was on the beach
when it failed is what found it.

## Tuning knobs

All in level 7's `stream` block in `scripts/beaches.gd`: `half_w`, `current`,
`slow`, `bridge_frac`, `float_speed`, `flood_first`, `flood_every`, `flood_len`,
`flood_debris`.

## Not built -- candidates for iteration

- **Music:** Island Jump and Island Vibes -- unassigned since level 2 changed
  from Isla Mujeres to Veracruz. (Tidal Rush was offered but is already
  Bacalar's soundtrack; the uploaded files were byte-identical.)

## Playtest -- what to feel for

1. Is the current strong enough to matter now?
3. Does the mouth pile-up change what you go for?
4. Is the flood readable, and does it feel like an event rather than noise?
