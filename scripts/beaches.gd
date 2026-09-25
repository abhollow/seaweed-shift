class_name Beaches
extends RefCounted

# One entry per level: where it is, what it looks like, and the shape of its
# beach. Anything a level does not set falls back to Zones.DEFAULTS (Cancun).
#
# Levels without an entry yet reuse Cancun, so the ten-level loop always has a
# beach to stand on while the art arrives one location at a time.

const LIST := {
	1: {
		"name": "Cancun",
		"background": "res://assets/sprites/background_level1.png",
		"water": "res://assets/sprites/water_%02d.png",
	},
	2: {
		# A narrow beach and famously endless shallows: Playa Norte is
		# waist-deep a long way out. Sand shrinks from 230px to 145, shallows
		# grow from 110 to 210, so the waders matter more here than anywhere,
		# and kelp runs become long wades rather than a quick dash.
		"name": "Isla Mujeres",
		"background": "res://assets/sprites/background_level2.png",
		"water": "res://assets/sprites/water2_%02d.png",
		"zones": {
			"shallow_top": 335.0,
			"deep_top": 545.0,
			"shore_y": 329.0,
			"water_top": 304.0,
		},
	},
}


static func for_level(level: int) -> Dictionary:
	return LIST.get(level, LIST[1])
