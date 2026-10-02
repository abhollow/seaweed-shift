extends "res://tools/make_parasail_art.gd"

# Cuts the level-moment art in raw/events/ into game sprites (drawn at 2x):
#   umbrella  Veracruz's tumbling beach umbrellas
#   crate     Veracruz's lost cargo
#   kayak     Bacalar's kayak tour (drawn on a diagonal; the game levels it)
#   ship      Cozumel's cruise ship
#   diver     Cozumel's night divers
#
#   godot --headless --path . --script res://tools/make_event_art.gd
#
# Each entry: [sheet, object index left to right, width in art pixels].

const PICKS := {
	"umbrella": ["res://raw/events/objects_option_2.png", 0, 12],
	"crate": ["res://raw/events/objects_option_1.png", 1, 10],
	"kayak": ["res://raw/events/objects_option_1.png", 2, 20],
	"ship": ["res://raw/events/ship_diver_option_2.png", 0, 60],
	"diver": ["res://raw/events/ship_diver_option_2.png", 1, 18],
}


func _initialize() -> void:
	var sheets := {}
	for name in PICKS:
		var path: String = PICKS[name][0]
		if not sheets.has(path):
			var img := Image.load_from_file(ProjectSettings.globalize_path(path))
			img.convert(Image.FORMAT_RGBA8)
			sheets[path] = [img, _objects(img)]
		var src: Image = sheets[path][0]
		var boxes: Array = sheets[path][1]
		var f := src.get_region(boxes[int(PICKS[name][1])])
		_key(f)
		f = f.get_region(f.get_used_rect())
		var w: int = PICKS[name][2]
		var h := maxi(1, int(round(float(f.get_height()) * w / f.get_width())))
		f.resize(w, h, Image.INTERPOLATE_LANCZOS)
		for y in h:
			for x in w:
				var c := f.get_pixel(x, y)
				c.a = 1.0 if c.a > 0.5 else 0.0
				f.set_pixel(x, y, c)
		f.save_png(ProjectSettings.globalize_path("res://assets/sprites/event_%s.png" % name))
		print("%s: %dx%d" % [name, w, h])
	quit()
