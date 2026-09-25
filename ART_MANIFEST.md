# Sprite manifest

Every sprite the game needs, at 360×640 viewport with nearest-neighbour
filtering. One art pixel = one unit in these tables.

**Sizes are snapped.** Everything is a multiple of 8, which matters most when
assets are AI-generated: downscaling 1024×1024 to 32×32 is an exact 32:1 box
average, while 30×36 is a fractional resample that softens edges on a sprite
that's only 30 pixels wide.

Rake reach was deliberately left alone (12 / 18 / 22) — it isn't a sprite
dimension and changing it would alter how the game feels.

**All world art is authored at HALF the game's coordinate space and drawn at 2x.**
The viewport is 360x640, but the background, the water frames and every sprite are
made at half that density and scaled up by a clean whole number. That doubled
pixel is the game's look.

So the table below lists **game units** (the size of the thing in the world) and
the **texture size** you actually draw. A 24x24 player is a **12x12 PNG**.

The HUD is deliberately exempt — it draws at full resolution, so text stays sharp
against chunky art.

Draw at the listed texture size. Do not draw large and scale down: the renderer
uses nearest-neighbour, so a downscaled sprite gets destroyed rather than
softened.

---

## Player — the highest-value assets

Four distinct states. The tractor is the emotional peak of the progression, so
it should read as a genuinely different machine, not a bigger person.

| State | Slot | Unlocked by | Texture | Drawn at | Hitbox | Notes |
|---|---|---|---|---|---|---|
| Bare hands | `tex_bare` | start | **24×24** | 48×48 | 24×24 | No tools; picking by hand |
| Rake | `tex_rake` | Rake (60 cr) | **24×24** | 48×48 | 24×24 | Hi-vis vest, wide hand rake |
| Backpack | `tex_backpack` | Backpack (220 cr) | **24×30** | 48×60 | 24×32 | Rake plus a visible pack |
| Tractor | `tex_tractor` | Tractor (800 cr) | **28×30** | 56×60 | 32×32 | Seated driver, small cab |
| Tractor + hopper | `tex_hopper` | Rear Hopper (2400 cr) | **34×31** | 68×62 | 32×48 | Hopper fills the rear half |
All four vehicle sprites come from **one generation** (`raw/tractor_all.jpg`),
which is what keeps the machine a constant size across loaded and unloaded, front
and rear. Boxes are normalised on the **machine**, not the bounding box — the
loaded hopper is wider, so it gets a wider box rather than a shrunken tractor.

Vehicles animate with a **1px bob only** (`--legs 0 --bob 1`). That is a pure
translate, so none of the mirroring or smearing failures that affect leg
manipulation can occur here.

### Rain jacket

The jacket upgrade is a **shader hue swap on the existing walking art**, not a
second set of textures: `shaders/hue_swap.gdshader` on the player's Sprite2D,
toggled by `Player.set_jacket()`. It covers every on-foot state including the
wading poses, and any walking art added later gets it for free — 36 sprites that
never had to be authored, sliced or kept in sync.

`Game._recompute_carry()` enables it only when the jacket is owned **and** no
vehicle is: driving is a different upgrade tier with its own art, so a driver
never wears it.

**The hue window is tight for a reason.** Measured from the sprites:

| Element | Hue |
|---|---|
| Skin | 21-33 deg |
| Tool handle | 30-47 deg |
| **Vest** | **50-58 deg** |
| Backpack | 60-73 deg |

A generous window (45-72) was tried first and turned the olive backpack and the
wooden handle red as well, which reads as a bug. Saturation gating above 0.6
additionally protects the pale reflective stripes, which are near-white and
should stay that way.

**Measure the sprite's actual palette before choosing a window.** Guessing "yellow
is about 60 degrees" is what produces the red backpack.

**Every state also has a rear view** — `tex_bare_back`, `tex_rake_back`,
`tex_backpack_back`, `tex_tractor_back`, `tex_hopper_back` — at the same texture
size as its front counterpart. Ten sets, forty textures.

The rear art is drawn **three-quarter and angled left**, exactly like the front
art, so the existing `ART_FACES_LEFT` flip covers both diagonals. A dead-on rear
view was tried first and abandoned: flipping it produces the same image, so it
could only ever show one direction.

`Player.BACK_THRESHOLD` is 0.45 on the joystick's Y — generous, so a mostly
sideways drift keeps the side view rather than flickering between the two. A
state with an empty rear set falls back to its side view.

**Leg depth is per-pose, not per-direction.** The bare stance stands with its feet
closer together than the raking stance, so the same `--legs` value gives it far
less to swap: 8.7% against 18-26% for the others. Bare uses `--legs 0.62`, the
rake and backpack states `0.42` side / `0.50` rear. Final leg swaps: bare 16.0/11.5,
rake 18.1/21.9, backpack 20.0/26.4 (side/rear).

Measure the **widest gap across the whole cycle**, not `f0` vs `f2`. The `step`
style puts its motion in frames 1 and 3, so an `f0`/`f2` comparison reads 0% and
looks like a failure when the animation is fine.

**The walk is a two-frame A-B cycle: striding, then passing.** Both frames are
drawn art — `make_walk_frames.py --pair` does no pixel manipulation whatsoever,
which is deliberate. Every animation bug in this project came from deriving a
frame instead of drawing it.

A three-pose cycle (left lead / passing / right lead) was attempted first. The
model will not draw the mirrored lead pose: asked five different ways, including
describing the legs by which one the torso occludes, it returned a copy of the
first pose every time. Two poses alternating is what 8-bit games shipped and it
reads correctly.

**Slice boxes are sized so the FIGURE stays constant, not the bounding box.** The
rake sprites are taller and wider in bbox because the tool extends past the body,
so a shared box would shrink the worker. Each column gets its own box scaled from
the bare sprite's height: bare 15x24, rake 21x28, backpack 24x27, and the rear
equivalents. Because those boxes no longer share one aspect ratio, the player
sprite scales at a **uniform 2x** (`Player.ART_SCALE`) rather than deriving scale
from an art size — otherwise a mismatched aspect stretches the sprite.

**Wading**: `tex_*_wade` and `tex_*_wade_back` for **all five states**. On foot
it is a chest-up pose with arms on the surface; on a vehicle the machine is cut
at the **axle line** with the wheels entirely below the surface and the driver
high and dry. Swapped at `Zones.SHALLOW_TOP` via `Player.in_water()`.

Twenty sets, 68 textures. Vehicle wade boxes are scaled to the same machine size
as the dry art (tractor side 28px wide in both), so entering the water changes
the silhouette without changing the apparent size of the tractor. The rake handle stays above the
waterline and the backpack above the shoulder, so the upgrade is still readable
when only the chest is visible.

**Generate every state of a character in ONE sheet.** Separate generations drift:
asking for "the rake version" later produces a different height, head size and
build, even with the approved sheet passed as a reference. The worker's six
on-foot states — bare, rake, rake+backpack, each side and rear — all come from a
single row, which is the only reliable way to get one character rather than six
cousins. Measured heights confirm it: 24px for every standing state.

If the model needs an object hidden in a view, **name the wrong answers**. Asking
for the rake handle to be "hidden behind him" produced a handle over the shoulder,
under the arm and across the back on successive attempts; listing those as
forbidden fixed it.

**Artwork is drawn larger than the hitbox on purpose.** At half density a 24-unit
player would only be a 12×12 PNG. 16×16 was tried and rejected — a human figure
downscaled from a 1024px render simply loses its structure at that size and reads
as a coloured blob. **24×24 is the floor** for a recognisable person here.

Drawing at 48 units gives that 24×24 texture while the collision shapes stay
exactly where they were tuned, so difficulty is unchanged. The sprite overhangs
its hitbox by ~12px a side, which reads as generous rather than broken — standard
practice, and it means a rake handle poking into a tourist is a miss.

If collisions start to feel *too* forgiving in play, grow the hitboxes rather
than shrinking the art; legibility was the harder problem to solve.

`Player.set_body(hitbox, artwork, colour, texture)` takes both; the rake's reach
is measured from the **hitbox**, not the drawing.

The player starts **bare-handed**. The rake is the first purchase, and the first
one that visibly changes anything — previously it was a 60-credit upgrade with no
sprite at all. The Backpack is gated behind the Rake in `upgrades.gd`, so the
chain is strictly ordered and the visual can never show gear out of sequence.

Consumed by `Game._recompute_carry()`. Each currently passes a size and a colour
to `Player.set_body()`; with sprites the colour argument becomes a texture swap.

### Walk cycles

Each player state is a **four-frame array**, not a single texture, generated by
`tools/make_walk_frames.py` from the one approved sprite:

```
python3 tools/make_walk_frames.py --src assets/sprites/player_01.png \
    --prefix player_s1 --legs 0.34      # on foot
python3 tools/make_walk_frames.py --src assets/sprites/player_03.png \
    --prefix player_s3 --legs 0          # vehicles: bob only, no feet
```

Asking the image model for animation frames does not work — separate generations
aren't frame-coherent, so proportions and palette drift and the result flickers.
Deriving frames from the approved sprite is coherent by construction and free.

**There is one style now: `step`.** It lifts one leg at a time, leaving the other
planted, operating on a band capped at the bottom 34% and splitting left from
right at the **content centroid** of that band.

Both of those constraints exist because of real breakage:

The old `mirror` style flipped the bottom `--legs` fraction horizontally. At any
depth deep enough to move the legs of a narrow-stanced pose it also flipped the
**torso** — vest and arms mirrored while the head stayed put. And on the rake
states it flipped the rake to the other side, producing a **ghost second rake**.
It has been removed entirely rather than tuned.

Splitting at the canvas midpoint was the other half of the bug: a worker carrying
a rake is not centred on his own body, so the midpoint cut the figure in the wrong
place and displaced the legs sideways.

**Sanity-check every cycle after generating.** Count opaque pixels per frame; any
frame differing from frame 0 by more than ~25% has ghosted or clipped something.
Motion percentage alone will not catch it — a mirrored torso scores *high* on
motion while looking utterly broken.

Both add a **bob** of the whole sprite on alternate frames. The bob is what sells
it; leg motion alone looks like a glitch and a bob alone looks like hovering.
Frame 0 is the standing pose, so the cycle settles there when you stop rather
than freezing mid-stride.

Every frame in a cycle must be the **same size** — scale is taken from frame 0.

**Facing is handled in code.** `Player._physics_process()` sets `flip_h` on the
sprite from the joystick's x direction, with a 0.25 deadzone so drifting straight
up or down doesn't flip it back and forth on tiny jitter. So **one sprite per
state covers left and right** — draw them all facing the same way.

`Player.ART_FACES_LEFT` records which way the artwork was drawn, and the mirror
is applied only when the wanted facing differs from it. If a future sheet comes
back facing the other way, flip that one constant rather than rewriting logic.

Up/down variants would multiply every state by the number of angles. Get one full
set of assets in-game at a single angle, watch it move, and only then decide
whether more directions earn their cost.

**Rain jacket** still has no visual. A recolour of the rake sprite would make a
140 cr purchase visible — the same problem the rake itself used to have.

---

## Seaweed — the most-seen sprite in the game

Three snapped tiers (`Seaweed.size_for_units()`) rather than a per-unit ramp, so
this is three sprites instead of eight. Pile growth still reads clearly.

| Units | Size | Where it comes from |
|---|---|---|
| 1–2 | **8×8** _(16×16 units)_ | Ordinary spawn |
| 3–5 | **16×16** _(32×32 units)_ | Storm clumps, deep kelp |
| 6–8 | **24×24** _(48×48 units)_ | Merged shoreline piles |

Every one of those is a whole number at half density, which is why 2x was chosen
over anything finer — 2.5x would have put the player at 9.6 pixels.

Four variants, each with three size tiers, in `seaweed.tscn`'s exported arrays
(ordered small / medium / large):

| Slot | Variant | Notes |
|---|---|---|
| `tex_fresh` | Fresh beach seaweed | Bright green |
| `tex_drift` | Drifting | Paler; still afloat, hasn't beached |
| `tex_kelp` | Deep kelp | Teal, deep water only, worth 3× per unit |
| `tex_rot` | Rotten | **Beached only** — 3 sprites, not 9 |

**Rot needs only three sprites.** Drifting clumps don't age until they beach, and
kelp never rots, so only the fresh row has rotten counterparts.

It's drawn as a **separate sprite cross-faded over the fresh one**, with alpha
driven by `rot_progress()` (20s → 32s). At full rot the fresh sprite is hidden
outright rather than trusted to be covered — any gap in the rotten silhouette
would leak green through at exactly the moment the pile must read as dead.

The fully rotten art carries **no green at all** — grey-brown, ochre, bleached
tan and blackened patches only. That contrast against fresh green is the urgency
signal: a rotten pile pays half at the bin and does six times the reputation
damage, so spotting one has to make you change course. Tinting the fresh texture with `modulate`
would MULTIPLY green by brown and just look muddy — a real rotten sprite fading in
keeps the gradual transition and actually looks spoiled.

Leave any slot empty and that variant falls back to the placeholder rectangle, so
art can land one variant at a time.

### Sway

Each variant is a **flat tier-major array** — `[tier0 f0..fN, tier1 f0..fN,
tier2 f0..fN]`. Frames-per-tier is derived from the array length, so a variant
with no animation just supplies one frame per tier.

Frames come from `tools/make_sway_frames.py`, the horizontal cousin of the water
tool: rows are displaced sideways by a travelling sine, weighted toward the top
so the base stays planted and only the fronds move.

```
python3 tools/make_sway_frames.py --src assets/sprites/sw_06.png \
    --prefix sea_kelp0 --amp 2 --anchor 0.15
```

How much each variant moves is a deliberate signal, set by `SWAY_FPS` in
`seaweed.gd`:

| Variant | Rate | Amp | Why |
|---|---|---|---|
| Fresh | 2.5 | 1px | Washed up and settled |
| Drifting | 6.0 | 2px | Still afloat |
| Kelp | 4.0 | 2px | Slow deep-water waver |
| **Rot** | **none** | — | Dead. Movement would undercut the "go clear it" signal |

---

## Hazards and pickups

| Sprite | Texture | Drawn at | Hitbox | Notes |
|---|---|---|---|---|
| Tourist | **18×24** | 36×48 | 16×24 | Beachwear, mid-stagger |
| Tourist (Happy Hour) | **24×24** | 48×48 | 24×24 | Warmer colour, drink in hand |
| Package | **12×8** | 24×16 | 24×16 | Wrapped brick, blinks as it expires |

Tourists get the same treatment as the player — drawn bigger than they collide,
so brushing past someone's elbow is a miss rather than a lost load.

Tourists carry **sixteen** frame sets on their root — sober/drunk x male/female x
walking/wading x **front/rear**, 64 textures:

| Slot | Character | State |
|---|---|---|
| `tex_sober_m` / `tex_sober_f` | sober | walking |
| `tex_drunk_m` / `tex_drunk_f` | drunk | walking |
| `tex_wade_sober_m` / `_f` | sober | past the waterline |
| `tex_wade_drunk_m` / `_f` | drunk | past the waterline |

Every one has a `_back` counterpart. The rear view is used when the tourist is in
the `ASCEND` state — the only one that travels away from the camera — so heading
back up the beach shows you their back, exactly as the player does. Wading has
front and rear poses too, since a tourist who wades in heading up-screen would
otherwise still face you.

Sex is a **straight 50/50 coin flip at spawn**, during Happy Hour as well as the
ordinary trickle. A female tourist falls back to the male set if hers is missing,
so a half-finished art drop looks wrong rather than invisible.

**Walking sets are four genuinely drawn frames** — contact, passing, opposite
contact, opposite passing. Four beats two: the passing frames (legs together,
body lifted) are what the eye reads as weight transfer, and without them a cycle
reads as a shuffle.

**Measure the frames before wiring them — the model repeats poses constantly.**
Across three separate tourist art passes, roughly half the "two drawn poses" came
back under 12% different, i.e. the same drawing twice. Asking for a *subtle*
stride made it worse, not better.

The reliable repair is to throw away the duplicate and **mirror the first pose**
instead: on the latest pass that took 5.9% -> 16.1%, 2.4% -> 20.6%, 6.3% -> 20.3%,
2.8% -> 23.1% and 0.5% -> 19.9%. Cycles that measured fine were left as drawn.

Do this check as a loop over every cycle rather than by eye; at 22 pixels a 3%
difference is invisible in a still and obvious in motion.

**Wading** swaps the silhouette at `Zones.SHALLOW_TOP` via `Tourist.in_water()`,
not on a state change — the player sees the change happen where it happens. The
waist-up pose has no legs at all and plays at 2.5fps: arms bobbing, not striding.

Sprite scale is a fixed **2x** rather than derived from an art size, because the
wading poses are shorter than the walking ones and one art size would squash
them.

They also **flip to face their direction of travel**, same `ART_FACES_LEFT`
convention as the player with an 8px deadzone so the weaving can't strobe them.
The drunk sets play at 4.5fps against 7 — a heavier lurch.

**Objects** (`obj_00..02`) are the skip, package and buoy. The skip and buoys are
built procedurally in `Game`, so they take `tex_bin` and `tex_buoy` on the Game
root; the package carries `tex_package` on its own scene. All three fall back to
coloured rectangles when unset.

Tourists have three states in `tourist.gd` — descending, splashing, ascending.
Two frames of walk cycle would carry all three.

---

## Static scenery

| Sprite | Size | Notes |
|---|---|---|
| Dump bin | **28×32** _(56×64 units)_ | Industrial skip |
| Loading bay apron | **48×56** _(96×112 units)_ | Concrete pad, tileable edge |
| Buoy | **4×4** _(8×8 units)_ | Repeats every 34px across the deep line |

---

## Backgrounds

**Preferred: one full-screen painted background** with the four zones baked in —
a single scene reads far better than four repeating tiles, and this game is one
fixed screen with nothing to scroll. Slot: `tex_background` on the Game root in
`main.tscn`. When it's set, the per-band tiles are skipped entirely.

**Size: 180×320.** That is half the 360×640 viewport, so it draws at a clean 2x
with nearest filtering and no resampling. Any size that does not divide the
viewport by a whole number loses the pixel grid.

**Band alignment is non-negotiable, and the image model will not hit it.** Asking
for "top 30%" reliably comes back at whatever proportion the model prefers. The
fix is to measure the generated art and remap the bands afterwards: crop each
band and resize it vertically to the share the game needs, then stack them.

Sand and open water are featureless enough that compressing or stretching them is
invisible, which gives plenty of slack to absorb the correction. A resort band
stretched ~1.4x just reads as a deeper terrace. The current background was built
this way — resort 1.41x, sand 0.81x, shallows 1.44x, deep 0.75x — and lands
exactly on y=190 / 420 / 530.

The zone boundaries are fixed in code, so the art must match these proportions:

| Band | Y range | Share | Content |
|---|---|---|---|
| Resort | 0–190 | **29.7%** | Hotel, pool, loungers, palms, tiki bar. Tourists spawn here; the player can never enter, so decorate freely. |
| Sand | 190–420 | **35.9%** | The play area. Keep it **empty and quiet.** |
| Shallows | 420–530 | **17.2%** | Foam line along the top edge, caustics, seabed showing through. |
| Deep water | 530–640 | **17.2%** | Darker, no seabed, darkest at the bottom. |

Two constraints that matter more than they sound:

**The sand band must stay visually quiet.** It's 44% of the screen and every
sprite in the game sits on top of it. Loungers, rocks, footprints and strong
speckle all fight the seaweed you're trying to spot — and spotting things fast is
the entire game. Boring sand is correct sand.

**Keep the far right of the resort strip plain.** The concrete loading bay sits at
x 262–360, y 100–212, straddling the resort and sand bands — the boundary at
y=190 runs through it, which is what makes it read as a service entrance rather
than a shed on the beach. Anything
detailed there gets covered by the apron sprite.

### Fonts

`assets/fonts/TitanOne-Regular.ttf` — the title screen heading, and nothing else.
A chunky playful display face, which is what makes the title read tropical rather
than corporate. Licensed **SIL OFL 1.1**; `TitanOne-OFL.txt` ships beside it
because the licence requires the text to travel with the font.

Every other piece of UI text uses Godot's default font **emboldened at runtime**
via `FontVariation` in `ui_theme.gd`. That fakes weight on the fallback font, so
buttons read heavier without bundling a bold cut of anything. Applied inside
`UiTheme.button()`, so it covers every button in the game automatically.

### Title wordmark

`title_logo.png` (164x104, drawn at 2x) is a **baked graphic**, not live text:
the seaweed drapes over and hangs off the letterforms, which no font can do.
The subtitle stays live text -- small enough that baking it would cost sharpness
for nothing, and easy to reword.

**Keyed by tight colour match, not connectivity.** The counters of A, D, O and C
are enclosed background and must drop out, and connectivity keying deliberately
keeps enclosed regions. Safe here only because the artwork contains no pink.
Sprites keep using connectivity keying; a logo is the exception, not a reason to
change the rule.

Do the colour maths in **float32**. Squared channel differences reach ~65000,
which overflows int16 and wraps to small values, so white reads as "close to
pink" and keys out -- the first attempt produced a logo full of holes.

### Title screen

`assets/sprites/menu_background.png` is authored at **90×160** _(180×320 units)_ — exactly half
the screen — so it upscales 2× with nearest filtering and no resampling. That
doubled pixel is deliberate: the title screen reads chunkier than the game
itself, which makes the gameplay screen feel sharper by contrast.

Its surf is animated too, from `menu_water_00..07.png` (180×124, strip top at
y=196 in art space / 392 on screen), preloaded in `menu.gd`.

Layout keeps the middle of the screen clear: title and subtitle at the top in
open sky, the three buttons pinned along the bottom over water. The resort and
beach between them are the reason to look at this screen, so nothing covers
them.

The source was a 1:1 generation, fitted to 9:16 by cropping x=180 width=760 and
stretching sky 1.50× and water 1.51× while leaving the resort band at 1.00×.

### Animated water

`tools/make_water_frames.py` builds a looping wave animation **from a static
background** — it does not need new art. It is parameterised, so the same script
serves both screens:

```
# in-game beach
python3 tools/make_water_frames.py --src raw/background_level1.png \
    --prefix water --width 360 --height 640 --water-top 390

# title screen, half resolution and gentler
python3 tools/make_water_frames.py --src raw/menu_fitted.png \
    --prefix menu_water --width 180 --height 320 --water-top 196 \
    --amp-shore 1.6 --amp-deep 0.8
```

Amplitudes are given in **output** pixels, so the motion looks the same whatever
resolution the source art came in at. The beach frames go in the
`tex_water_frames` array on the Game root; the menu frames are preloaded in
`menu.gd`.

**Why not generate wave frames with the image model?** Separate generations
aren't frame-coherent — the resort, palette and foam would all jitter between
frames. This displaces rows of the existing art with a travelling sine instead,
which is the technique old console games used and is coherent by construction.

- Only the strip below `Zones.WATER_TOP` (y=390) is exported, so frames stay
  small and the resort never moves.
- Amplitude **fades to zero at the top of the strip**, so it blends into static
  sand with no seam.
- Shoreline travel is about **4px** — deliberately subtle.
- Two sine components, so it doesn't read as one mechanical wave.
- Storms run the same loop **1.7× faster**, so the sea visibly churns.

Tuning knobs (`FRAMES`, `AMP_SHORE`, `AMP_DEEP`, `WATER_TOP`) are at the top of
the script; playback speed is `water_fps` on the Game root.

### Fallback: per-band tiles

Used only when `tex_background` is empty. Slots `tex_hotel`, `tex_sand`,
`tex_shallows`, `tex_deep`, all on the Game root. These use `STRETCH_TILE`, which
repeats rather than scales, so they must be **seamless** squares. Empty slots keep
their flat colour.

The loading bay apron (`tex_apron`, 96×112) is a separate sprite either way.

## Weather effects

Drawn in code, not art — `scripts/systems/weather_fx.gd`. Rain streaks and disco
spots are a handful of lines and circles, so there are no textures to author,
import or keep in sync with the palette.

**Storm.** 130 rain drops falling with a slight wind slant, plus lightning.
The flash fires **before** the thunder, with a randomised 0.15–1.3s gap standing
in for distance to the strike. That gap does more for atmosphere than the pitch
variation on the thunder samples ever did.

**Happy Hour.** A mirrorball drops from the top of the screen into the hotel
zone, spins through its four frames, and is winched back up when the event ends.
70 black-and-white flecks **sweep across** the scene beneath it.

**No colour grade.** Both a drained grey pass and an oversaturated one were tried
and removed. Oversaturating pushed the already-orange tourists hardest, so they
were the only thing that visibly changed -- which reads as a rendering bug rather
than a mood. The shader and `Game.grade()` remain for future use; Happy Hour
simply leaves them at neutral.

The flecks are deliberately **both** colours: the white ones read as thrown light
and the dark ones as the gaps between mirrors, which is what makes it feel like a
spinning ball rather than a flashing lamp. They travel with a sideways-biased
velocity and **wrap** at the edges rather than respawning, so the sweep never
stutters, and each breathes on its own phase offset -- if they all pulsed
together it would read as a strobe. An exposure throb runs on a 2.6Hz beat.

The mirrorball is four spin frames (`ball_00..03`, 24×30), **preloaded in
`weather_fx.gd` rather than exported** — WeatherFx is constructed in code, so
there is no scene inspector to drop them into. It drops in with a slight
overshoot, spins at 8fps, and is winched back up when the event ends.

The grade is `shaders/desaturate.gdshader` on a fullscreen ColorRect above the
world and below the HUD, so readouts stay legible while the beach goes grey. It
pushes each pixel away from its own Rec.601 luma. Below 1.0 drains toward grey;
**above 1.0 oversaturates**, which is what Happy Hour uses (1.95). A plain
overlay cannot do this — adding colour washes bright sand toward white and leaves
dark water untouched. `Game.grade(saturation, exposure, time)` tweens the
uniforms, and `pulse_grade()` adds the beat on top.

Grade values are tracked in script, not read back from the material: a uniform
that has never been written returns null, and `float(null)` is a hard error.

Coloured light spots were tried first and abandoned: additive blew out to white
on bright sand, and multiply read as coloured gels rather than a disco. A drained
grey scene was tried next. Oversaturating and letting the flecks sweep is what
actually reads as a club.

The fx node sits at **z_index 55**: above sprites, below the floating popups at
60, so a "+1" is never lost behind the storm.

## Not sprites

Worth knowing these exist but need no art:

- **Rake reach halo** — the translucent square around the player (12 / 18 / 22 px
  beyond the body). Currently a debug aid; delete it or restyle it once sprites
  land.
- **Floating popups** — `+1`, `LOAD LOST`, `+450 cr`. Text, not art. A pixel
  font would suit them better than the default.
- **Storm and Happy Hour tints** — fullscreen colour overlays.
- **HUD** — five text rows plus the reputation bar. Unaffected at 360 wide.

---

## Suggested order

1. **Player, all four states.** They tell you fastest whether the palette and
   density are working, and the tractor is the moment the whole economy builds
   toward.
2. **Seaweed, three sizes × three variants.** Most-seen sprite; everything else
   sits on top of it.
3. **Tourist.** The only thing that punishes you, so it must be instantly
   readable against the sand.
4. **Bin and bay.** A fixed landmark you navigate to by silhouette.
5. **Background bands.** Easy to iterate on once everything else is placed.
6. **Package, buoys.** Small and infrequent.

---

## Slicing a sheet

`tools/slice_sheet.py` cuts a generated sheet into game-ready PNGs. It **finds**
each sprite by looking for islands of non-background pixels rather than cutting a
fixed grid — generated sheets never space their subjects evenly, and a grid cut
clips limbs and centres things badly.

It also **preserves aspect ratio**: each sprite is scaled to fit inside its target
box and centred, not squashed to fill it. That matters because the five player
states are not all square.

```
python3 tools/slice_sheet.py --src raw/player_sheet.jpg --prefix player \
    --sizes 16x16,16x16,16x20,20x20,20x28

python3 tools/slice_sheet.py --src raw/seaweed.png --prefix seaweed \
    --sizes 16x16 --rows 3
```

**Keying is connectivity-based, not colour-based.** Only magenta *reachable from
the image border* is removed. A pure colour test cut holes through the tourists:
a hot pink hawaiian shirt is close enough to the key that pixels inside the
character keyed out, leaving them see-through in game. Since every subject is
enclosed by its own black outline, background reachable from the edge is the real
background and anything walled off inside a figure is not, whatever colour it is.

Alpha is then hard-thresholded — a faded generated edge reads as fringe at 16px —
and enclosed specks under 6px are refilled from surrounding colour, since
downscale-then-threshold can punch a stray hole through a solid area.

**Never widen the colour rule to fix a keying problem.** Every shirt, hat and
prop the game will ever add sits somewhere on the colour wheel; connectivity is
the property that actually distinguishes background from subject.

Sheets should be generated on **plain flat magenta**; that is why every prompt in
this file asks for it. Subjects may safely be any colour, including magenta-
adjacent pinks, because of the connectivity rule above.

## Working with generated art

Image models don't produce pixel art — they produce a high-resolution painting
*of* pixel art: soft anti-aliased edges, a drifting pixel grid, and hundreds of
near-duplicate colours. At 24×24 that reads as a smudge.

`tools/prep_sprite.py` fixes it in four steps: trim the empty margin, box-average
down to the target size, snap every colour to `tools/palette.txt`, then threshold
alpha so edges are on/off rather than feathered. That third step is the one
people skip, and it's why AI pixel art usually looks mushy in-engine.

```
python3 tools/prep_sprite.py raw/tractor.png -o assets/tractor.png -s 32x32
python3 tools/prep_sprite.py raw/player_sheet.png -o assets/player -s 24x24 --cols 4
```

Verified on a 1024×1024 source with 2,161 colours: output was 32×32, 13 colours,
all on-palette, alpha strictly 0 or 255.

**Generate square, crop after.** Models are most reliable on square canvases, so
produce at 1024×1024 with the subject centred and generous margin. The tool trims
and pads for you — don't ask the model for 24×32 directly.

**Generate sheets, not singles.** Four separate prompts give you four different
characters. One 4096×1024 image with all four player states side by side keeps
style, palette and proportion consistent; `--cols 4` slices it.

## Palette

`tools/palette.txt` — 31 colours for the whole game, each with a shadow tone. A
tight palette is most of what makes pixel art cohere, and it's what the quantize
step enforces. Edit that file to retune; every asset reprocessed afterwards will
follow it.


## Level backgrounds

Each level is a real Mexican location with **its own beach geometry**, not just
its own paint. Zone boundaries are static vars on `Zones`, set per level by
`Zones.apply()` from `scripts/beaches.gd`. `Game.apply_beach()` then refreshes
everything that was built once from them: background, animated water strip, buoy
line, and the player's bounds. Levels with no entry yet fall back to Cancun.

**Fit the zones to the art, not the art to the zones.** Level 1 remapped its art
onto a fixed layout. From level 2 on, each beach's layout is chosen to suit its
location, and the art is remapped onto *that*. Keep the village line at y=190 so
the service bay stays put across levels -- only the sand, shallows and deep
lines move.

| Level | Location | Sand | Shallows | Deep | Twist |
|---|---|---|---|---|---|
| 1 | Cancun | 230px | 110px | 110px | the baseline |
| 2 | Isla Mujeres | 145px | 210px | 95px | narrow beach, endless shallows |

**Level 2 -- Isla Mujeres** (`background_level2.png`, `water2_00..07.png`).
Colourful low-rise island village with palapas and hammocks. Source bands
village 0-41 / sand 41-56.5 / shallows 56.5-77.5 / deep 77.5-100, remapped to
0-190 / 190-335 / 335-545 / 545-640. The village compresses 0.72x and still
reads; the model happened to leave a plain concrete lot on the right exactly
where the bay goes.

Rebuild the water with:

    python3 tools/make_water_frames.py --src raw/bg_mujeres_fitted.png --prefix water2 \
        --width 180 --height 320 --water-top 152 --amp-shore 1.4 --amp-deep 0.65

**Testing a level**: debug builds show a TEST LEVEL row in Settings that jumps
straight to any level with its own beach. It overwrites the save and never
appears in a release build.


## App icon

`assets/icon/` -- generated as one framed image, then rebuilt into proper
launcher assets:

| File | Size | Use |
|---|---|---|
| `icon.png` | 512 | Project icon (`application/config/icon`) |
| `icon_192.png` | 192 | Legacy launcher icon |
| `icon_fg_432.png` | 432 | Adaptive foreground -- the worker alone |
| `icon_bg_432.png` | 432 | Adaptive background -- the beach behind him |

**The generated image had its own rounded frame baked in.** Android applies its
own mask -- circle, squircle or rounded square, depending on the phone -- so a
pre-drawn frame ends up as a square inside a circle with grey corners showing.
The frame was cropped off and its corners refilled by extending the edge colours
outward (sky at the top, sand at the bottom), sampled past the frame's inner
bevel so no pale fringe survives.

**Why split the layers.** Android shows only the middle 72 of 108dp and masks
inside that, so full-bleed art gets the cap and boots cropped off. The worker is
cut out and shrunk into a 62% safe zone; the backdrop is shrunk by the SAME
factor and edge-extended outward, so the visible window shows the original
composition -- sand under his feet, frond at the side. Shrinking only the worker
left him floating on sky.

**Cut out by keying the backdrop, not by tracing the outline.** Flood-filling
from the border through non-outline pixels leaked through small gaps where skin
meets sky and took both arms. The backdrop is far more distinctive -- bright
cyan, white sand, one green frond -- so it is keyed by colour and the worker is
whatever remains. Enclosed sky and sand patches are removed afterwards; nothing
on the worker is bright cyan, since his cap and shorts are dark teal.
