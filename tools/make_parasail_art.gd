extends SceneTree

# Cuts the parasail sheet in raw/parasail/ into game art:
#   assets/sprites/parasail_boat.png    the speedboat, bow to the right
#   assets/sprites/parasail_canopy.png  the chute, with its lines
#
#   godot --headless --path . --script res://tools/make_parasail_art.gd
#
# The sheet is two objects on a magenta key, left to right; each is found by
# column projection, keyed and shrunk to its width in art pixels (drawn at 2x).

const SHEET := "res://raw/parasail/parasail_option_3.png"
const WIDTHS := {"boat": 30, "canopy": 34}


func _initialize() -> void:
	var src := Image.load_from_file(ProjectSettings.globalize_path(SHEET))
	src.convert(Image.FORMAT_RGBA8)
	var cols := _objects(src)
	var names := ["boat", "canopy"]
	for i in mini(cols.size(), names.size()):
		var f := src.get_region(cols[i])
		_key(f)
		f = f.get_region(f.get_used_rect())
		var w: int = WIDTHS[names[i]]
		var h := maxi(1, int(round(float(f.get_height()) * w / f.get_width())))
		f.resize(w, h, Image.INTERPOLATE_LANCZOS)
		for y in h:
			for x in w:
				var c := f.get_pixel(x, y)
				c.a = 1.0 if c.a > 0.5 else 0.0
				f.set_pixel(x, y, c)
		f.save_png(ProjectSettings.globalize_path("res://assets/sprites/parasail_%s.png" % names[i]))
		print("%s: %dx%d" % [names[i], w, h])
	quit()


func _is_key(c: Color) -> bool:
	return c.r > 0.55 and c.b > 0.55 and c.g < 0.4


func _key(f: Image) -> void:
	# Transparent BLACK, so the resize cannot blend a pink fringe in.
	for y in f.get_height():
		for x in f.get_width():
			if _is_key(f.get_pixel(x, y)):
				f.set_pixel(x, y, Color(0, 0, 0, 0))


func _objects(src: Image) -> Array:
	var w := src.get_width()
	var h := src.get_height()
	var occ := PackedByteArray()
	occ.resize(w)
	for x in w:
		for y in range(0, h, 2):
			if not _is_key(src.get_pixel(x, y)):
				occ[x] = 1
				break
	var out := []
	var start := -1
	var gap := 0
	for x in w:
		if occ[x] > 0:
			if start < 0:
				start = x
			gap = 0
		elif start >= 0:
			gap += 1
			if gap > 40:
				if x - gap - start > 60:
					out.append(Rect2i(start, 0, x - gap - start + 1, h))
				start = -1
				gap = 0
	if start >= 0 and w - start > 60:
		out.append(Rect2i(start, 0, w - start, h))
	return out
