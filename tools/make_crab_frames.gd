extends SceneTree

# Cuts the crab sprite sheets in raw/crab/ into game frames:
#   assets/sprites/crab_side_f0..3   scuttling sideways (moving right)
#   assets/sprites/crab_front_f0..3  walking toward the camera
#   assets/sprites/crab_back_f0..3   walking away
#   assets/sprites/crab_dig_f0..3    mound -> cracking -> half out -> out
#
#   godot --headless --path . --script res://tools/make_crab_frames.gd
#
# Frames are found by projection (rows, then frames within a row) on the
# magenta key. Every frame of every set is scaled by ONE factor, so the crab is
# the same size walking and digging, and each set shares one canvas with the
# art standing on its bottom edge -- cropping frames separately made them jitter.

const WALK := "res://raw/crab/walk_option_C.png"
const DIG := "res://raw/crab/dig_option_2.png"
const ART_W := 16.0           # the crab's shell-and-claws width, in art pixels
const OUT := "res://assets/sprites/crab_%s_f%d.png"


func _initialize() -> void:
	var walk := _load(WALK)
	var dig := _load(DIG)
	var wrows := _frames(walk)
	var drows := _frames(dig)
	# Scale from the crab's own orange, not the frame box: the dig frames carry
	# sand and a puff of dust that would shrink the crab if measured whole.
	var k_walk := ART_W / _orange_width(walk.get_region(wrows[1][0]))
	var k_dig := ART_W / _orange_width(dig.get_region(drows[0][3]))
	var sets := {"side": [walk, wrows[0], k_walk], "front": [walk, wrows[1], k_walk],
		"back": [walk, wrows[2], k_walk], "dig": [dig, drows[0], k_dig]}
	for name in sets:
		var src: Image = sets[name][0]
		var boxes: Array = sets[name][1]
		var k: float = sets[name][2]
		var frames := []
		var cw := 0
		var ch := 0
		for b in boxes.slice(0, 4):
			var f := _shrink(src.get_region(b), k)
			frames.append(f)
			cw = maxi(cw, f.get_width())
			ch = maxi(ch, f.get_height())
		for i in frames.size():
			var f: Image = frames[i]
			var canvas := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
			canvas.blit_rect(f, Rect2i(Vector2i.ZERO, f.get_size()),
				Vector2i((cw - f.get_width()) / 2, ch - f.get_height()))
			canvas.save_png(ProjectSettings.globalize_path(OUT % [name, i]))
		print("%s: %d frames, %dx%d" % [name, frames.size(), cw, ch])
	quit()


func _load(path: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	img.convert(Image.FORMAT_RGBA8)
	return img


func _is_key(c: Color) -> bool:
	return c.r > 0.55 and c.b > 0.55 and c.g < 0.4


func _spans(occ: PackedByteArray, min_gap: int) -> Array:
	var out := []
	var start := -1
	var gap := 0
	for i in occ.size():
		if occ[i] > 0:
			if start < 0:
				start = i
			gap = 0
		elif start >= 0:
			gap += 1
			if gap > min_gap:
				out.append(Vector2i(start, i - gap))
				start = -1
				gap = 0
	if start >= 0:
		out.append(Vector2i(start, occ.size() - 1))
	# Specks of noise are not frames.
	return out.filter(func(s): return s.y - s.x > 40)


func _frames(src: Image) -> Array:
	var w := src.get_width()
	var h := src.get_height()
	var rowocc := PackedByteArray()
	rowocc.resize(h)
	for y in h:
		for x in range(0, w, 2):
			if not _is_key(src.get_pixel(x, y)):
				rowocc[y] = 1
				break
	var rows := []
	for r in _spans(rowocc, 20):
		var colocc := PackedByteArray()
		colocc.resize(w)
		for x in w:
			for y in range(r.x, r.y + 1, 2):
				if not _is_key(src.get_pixel(x, y)):
					colocc[x] = 1
					break
		var row := []
		for c in _spans(colocc, 25):
			row.append(Rect2i(c.x, r.x, c.y - c.x + 1, r.y - r.x + 1))
		rows.append(row)
	return rows


func _orange_width(img: Image) -> float:
	var x0 := img.get_width()
	var x1 := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.7 and c.g < 0.5 and c.b < 0.3:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
	return float(maxi(1, x1 - x0 + 1))


func _shrink(f: Image, k: float) -> Image:
	# Key to transparent BLACK, not transparent magenta: the resize blends edge
	# pixels with their neighbours, and magenta would leave a pink fringe.
	for y in f.get_height():
		for x in f.get_width():
			if _is_key(f.get_pixel(x, y)):
				f.set_pixel(x, y, Color(0, 0, 0, 0))
	f = f.get_region(f.get_used_rect())
	var tw := maxi(1, int(round(f.get_width() * k)))
	var th := maxi(1, int(round(f.get_height() * k)))
	f.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	for y in th:
		for x in tw:
			var c := f.get_pixel(x, y)
			c.a = 1.0 if c.a > 0.5 else 0.0
			f.set_pixel(x, y, c)
	return f
