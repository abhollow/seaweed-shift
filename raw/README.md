# Raw art

Drop generated PNGs here straight from the image model, at whatever size it gave
you. Run them through `tools/prep_sprite.py` and the processed result lands in
`assets/sprites/`.

The empty `.gdignore` file in this folder tells Godot to skip the directory
entirely — nothing in here is imported, and nothing in here ships in a build.
So it's safe to leave 1024x1024 originals lying around.
