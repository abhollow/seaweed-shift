extends "res://tools/make_crab_frames.gd"

# Cuts raw/seagull/seagull_option_4.png into game frames, with the crab cutter's
# slicing and keying:
#   assets/sprites/seagull_fly_f0..3    wing-flap cycle, facing right
#   assets/sprites/seagull_perch_f0..1  standing, and squawking
#
#   godot --headless --path . --script res://tools/make_seagull_frames.gd
#
# One scale for both sets, set by the perched bird's width, so it is the same
# size flying and standing. Flight frames share a centred canvas (the bird is
# drawn centred on its position); perched ones stand on the canvas bottom.

const SHEET := "res://raw/seagull/seagull_option_4.png"
const PERCH_W := 12.0         # art pixels, perched


func _initialize() -> void:
	var src := _load(SHEET)
	var rows := _frames(src)
	var perch_box: Rect2i = rows[1][0]
	var probe := src.get_region(perch_box)
	for y in probe.get_height():
		for x in probe.get_width():
			if _is_key(probe.get_pixel(x, y)):
				probe.set_pixel(x, y, Color(0, 0, 0, 0))
	var k := PERCH_W / float(probe.get_used_rect().size.x)
	_save_set(src, rows[0].slice(0, 4), k, "fly", true)
	_save_set(src, rows[1].slice(0, 2), k, "perch", false)
	quit()


func _save_set(src: Image, boxes: Array, k: float, name: String, centred: bool) -> void:
	var frames := []
	var cw := 0
	var ch := 0
	for b in boxes:
		var f := _shrink(src.get_region(b), k)
		frames.append(f)
		cw = maxi(cw, f.get_width())
		ch = maxi(ch, f.get_height())
	for i in frames.size():
		var f: Image = frames[i]
		var canvas := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		var y := (ch - f.get_height()) / 2 if centred else ch - f.get_height()
		canvas.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i((cw - f.get_width()) / 2, y))
		canvas.save_png(ProjectSettings.globalize_path("res://assets/sprites/seagull_%s_f%d.png" % [name, i]))
	print("%s: %d frames, %dx%d" % [name, frames.size(), cw, ch])
