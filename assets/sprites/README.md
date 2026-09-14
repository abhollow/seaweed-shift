# Sprites

Processed, game-ready PNGs go here. Raw generated art does not — keep that
outside the project so it never ships in a build.

Everything here should have come through `tools/prep_sprite.py`, which snaps
colours to `tools/palette.txt` and hardens the alpha edges.

Sizes are listed in `ART_MANIFEST.md`. A sprite must match its listed size
exactly, or it will be scaled to fit the collision box and lose its pixel grid.
