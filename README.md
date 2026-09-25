# Seaweed Shift: Mexico

A 2D pixel-art mobile game: clean sargassum seaweed off resort beaches along
Mexico's coast, earn credits, buy better gear, keep each resort's reputation up.
Ten levels, each a different real location, with one upgrade kept permanently at
the end of every level. Godot 4.3, portrait 360x640.

## Running it

Open the folder in Godot 4.3 and press F5.

**If sprites show as coloured rectangles**, delete the `.godot/` folder and
reopen — a stale import cache is almost always the cause.

## Tests

```bash
godot --headless --path . --import          # always import first
godot --headless --path . --script res://tools/smoke_test.gd
```

188 assertions covering zones, upgrades, save/load, failure and retry, animation
wiring and UI layout. Run after every change. CI runs them on push.

## Layout

```
scenes/      entity scenes, main, menu
scripts/     game spine, entities, systems/, ui/
tools/       smoke_test.gd, plus the Python art pipeline
assets/      game-ready sprites and fonts
audio/       music, ambience, sfx
shaders/     colour grade, jacket hue swap
raw/         SOURCE art -- generated sheets and fitted backgrounds
docs/        design decisions and plans
ART_MANIFEST.md   sizes, pipeline, and every failure mode we hit
```

**`raw/` is not disposable.** It holds the original generated sheets *and*
derived files that took real work — `background_level1.png` is the level art
after a four-band remap onto the zone boundaries, `menu_fitted.png` is the title
art after its crop-and-stretch fit. Regenerating assets without these means
redoing that work.

## Art pipeline

See `ART_MANIFEST.md`. Short version: generate on flat magenta, slice with
`tools/slice_sheet.py`, build cycles with `tools/make_walk_frames.py --pair`,
measure before wiring.
