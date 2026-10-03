extends "res://tools/make_crab_frames.gd"

# Cuts raw/flamingo/fly_option_2.png into the flamingo's flight frames:
#   assets/sprites/flamingo_fly_f0..3   wings up, level, down, level -- facing right
#
#   godot --headless --path . --script res://tools/make_flamingo_frames.gd
#
# Generated on GREEN (a magenta key would eat a pink bird), so the key test is
# swapped. One scale for all frames, on a shared canvas: lined up on the beak
# (right edge) and on the sheet's rows, so the body holds still while the wings beat.

const SHEET := "res://raw/flamingo/fly_option_2.png"
const FLY_W := 30.0           # art pixels, beak to toes


func _is_key(c: Color) -> bool:
	return c.g > 0.55 and c.r < 0.45 and c.b < 0.45


func _initialize() -> void:
	var src := _load(SHEET)
	var boxes: Array = _frames(src)[0]
	var k := FLY_W / float((boxes[1] as Rect2i).size.x)
	# Every box spans the whole row; the bird's own top within it sets the offset.
	var tops := []
	for b in boxes.slice(0, 4):
		var probe := src.get_region(b)
		for y in probe.get_height():
			for x in probe.get_width():
				if _is_key(probe.get_pixel(x, y)):
					probe.set_pixel(x, y, Color(0, 0, 0, 0))
		tops.append(probe.get_used_rect().position.y)
	var top: int = tops.min()
	var frames := []
	var cw := 0
	var ch := 0
	for i in 4:
		var f := _shrink(src.get_region(boxes[i]), k)
		frames.append(f)
		cw = maxi(cw, f.get_width())
		ch = maxi(ch, int(round((tops[i] - top) * k)) + f.get_height())
	for i in frames.size():
		var f: Image = frames[i]
		var y := int(round((tops[i] - top) * k))
		var canvas := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
		canvas.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), Vector2i(cw - f.get_width(), y))
		canvas.save_png(ProjectSettings.globalize_path("res://assets/sprites/flamingo_fly_f%d.png" % i))
	print("fly: %d frames, %dx%d" % [frames.size(), cw, ch])
	quit()
