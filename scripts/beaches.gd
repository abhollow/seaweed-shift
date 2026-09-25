class_name Beaches
extends RefCounted

# One entry per level: where it is, what it looks like, and the shape of its
# beach. Anything a level does not set falls back to Zones.DEFAULTS (Cancun).
#
# Levels 3-10 are first-pass mockup art: zones are read off each image by eye,
# and the special mechanics their art shows (turtle nests, boulders, the stream,
# the round island) are not built yet -- the player walks straight over them.

const LIST := {
	1: {
		"name": "Cancun",
		"tagline": "Your first shift at the resort. Keep the beach clean and the guests happy.",
		"background": "res://assets/sprites/background_level1.png",
		"water": "res://assets/sprites/water_%02d.png",
	},
	2: {
		# The norte: a constant wind off the Gulf, blowing left to right, with
		# stronger gusts. Geometry deliberately matches Cancun almost exactly --
		# the wind is the ONE new thing, so the player learns a rule rather than
		# a new beach and a rule at once.
		"name": "Veracruz",
		# No storms on foot here: the wind already makes walking hard, and a
		# storm's seaweed surge on top of it was more than anyone could clear.
		"storms_need": "tractor",
		"tagline": "The norte is blowing. The wind pushes you -- and the seaweed.",
		"background": "res://assets/sprites/background_level2.png",
		"water": "res://assets/sprites/water2_%02d.png",
		# Tension tracks for the storm level: the norte should sound like
		# weather, not a holiday.
		"music": [
			"res://audio/Tropical_Tension_1.mp3",
			"res://audio/Tropical_Tension_2.mp3",
			"res://audio/Tropical_Tension_3.mp3",
		],
		"zones": {
			"hotel_bottom": 192.0,
			"shallow_top": 390.0,
			"deep_top": 502.0,
			"shore_y": 384.0,
			"water_top": 360.0,
			"tourist_spawn_y": 182.0,
			"tourist_despawn_y": 182.0,
			"bay_pos": Vector2(311, 162),
		},
		# Tuned so a peak gust (48 x 2.7 = 130 px/s) exactly cancels walking
		# speed on foot: walking INTO one you stand still. At the first
		# pass (30 px/s, 2.4x) the wind was a slope rather than a force --
		# a minor inconvenience, not something to plan around.
		# The painted palms, flags and kites sway, driven by the wind above.
		"sway": {
			"mask": "res://assets/sprites/sway_level2.png",
			"amp": 1.4,
			"lean": 1.0,
		},
		"wind": {
			"strength": 48.0,
			"gust_every": 13.0,
			"gust_len": 4.0,
			"gust_mult": 2.7,
		},
	},
	3: {
		"name": "Playa del Carmen",
		"tagline": "The bay is on the left. Keep the VIP frontage spotless -- and watch for the Cozumel ferry.",
		# The beach club's frontage, from its daybeds down to the water, on the
		# RIGHT -- the far side from the skip. Seaweed there costs triple.
		"vip": {
			"x0": 205.0,
			"x1": 348.0,
			"weight": 3.0,
		},
		# The Cozumel ferry: every ~55s its slanted wake sweeps along the beach,
		# carrying HALF of the drifting seaweed ashore as it goes.
		"ferry": {
			"first": 35.0,
			"every": 55.0,
			"speed": 90.0,
			"angle": 20.0,
			"lane_y": 565.0,
			# Share of the drifting seaweed each wake carries, by shift. Shift 1
			# is on foot, and a flat 50% was an instant loss there; the later
			# shifts have the tractor and deep-water gear to cope.
			"share": [0.2, 0.3, 0.6, 0.8],
		},
		"background": "res://assets/sprites/background_level3.png",
		"water": "res://assets/sprites/water3_%02d.png",
		"zones": {
			"hotel_bottom": 150.0,
			"shallow_top": 381.0,
			"deep_top": 490.0,
			"shore_y": 375.0,
			"water_top": 350.0,
			"tourist_spawn_y": 140.0,
			"tourist_despawn_y": 140.0,
			"bay_pos": Vector2(43, 120),
		},
	},
	4: {
		"name": "Cozumel",
		"tagline": "The night shift. Work by lantern light -- and watch for the moon.",
		# Fog of war: a lantern on foot, headlights on the tractor, phone glows
		# on the tourists, and the moon breaking through now and then.
		"night": {
			"darkness": 0.86,
			"lantern": 62.0,
			"headlights": 110.0,
			"phone": 20.0,
			"bay_light": 58.0,
			# torches found in the art, plus the glowing pool
			"lights": [[104, 93, 46], [176, 144, 46], [32, 142, 46], [125, 125, 40]],
			"moon_first": 45.0,
			"moon_every": 70.0,
			"moon_len": 9.0,
		},
		"background": "res://assets/sprites/background_level4.png",
		"water": "res://assets/sprites/water4_%02d.png",
		"zones": {
			"hotel_bottom": 179.0,
			"shallow_top": 390.0,
			"deep_top": 474.0,
			"shore_y": 384.0,
			"water_top": 360.0,
			"tourist_spawn_y": 169.0,
			"tourist_despawn_y": 169.0,
			"bay_pos": Vector2(311, 149),
		},
	},
	5: {
		"name": "Bacalar",
		"tagline": "Big surf rolls in on this stretch of coast.",
		"background": "res://assets/sprites/background_level5.png",
		"water": "res://assets/sprites/water5_%02d.png",
		"zones": {
			"hotel_bottom": 170.0,
			"shallow_top": 366.0,
			"deep_top": 499.0,
			"shore_y": 360.0,
			"water_top": 336.0,
			"tourist_spawn_y": 160.0,
			"tourist_despawn_y": 160.0,
			"bay_pos": Vector2(315, 140),
		},
	},
	6: {
		"name": "Isla Holbox",
		"tagline": "A tiny island, with sea on every side.",
		"background": "res://assets/sprites/background_level6.png",
		"water": "res://assets/sprites/water6_%02d.png",
		"zones": {
			"hotel_bottom": 339.0,
			"shallow_top": 448.0,
			"deep_top": 512.0,
			"shore_y": 442.0,
			"water_top": 418.0,
			"tourist_spawn_y": 329.0,
			"tourist_despawn_y": 329.0,
			"bay_pos": Vector2(106, 309),
		},
	},
	7: {
		"name": "Puerto Morelos",
		"tagline": "A fishing town, and a stream that runs across the beach.",
		"background": "res://assets/sprites/background_level7.png",
		"water": "res://assets/sprites/water7_%02d.png",
		"zones": {
			"hotel_bottom": 141.0,
			"shallow_top": 384.0,
			"deep_top": 490.0,
			"shore_y": 378.0,
			"water_top": 354.0,
			"tourist_spawn_y": 131.0,
			"tourist_despawn_y": 131.0,
			"bay_pos": Vector2(311, 111),
		},
	},
	8: {
		"name": "Mahahual",
		"tagline": "Sargassum season. The worst the coast has ever seen.",
		"background": "res://assets/sprites/background_level8.png",
		"water": "res://assets/sprites/water8_%02d.png",
		"zones": {
			"hotel_bottom": 118.0,
			"shallow_top": 323.0,
			"deep_top": 464.0,
			"shore_y": 317.0,
			"water_top": 292.0,
			"tourist_spawn_y": 108.0,
			"tourist_despawn_y": 108.0,
			"bay_pos": Vector2(311, 88),
		},
	},
	9: {
		"name": "Akumal",
		"tagline": "The bay of turtles. Mind the nests.",
		"background": "res://assets/sprites/background_level9.png",
		"water": "res://assets/sprites/water9_%02d.png",
		"zones": {
			"hotel_bottom": 211.0,
			"shallow_top": 400.0,
			"deep_top": 534.0,
			"shore_y": 394.0,
			"water_top": 370.0,
			"tourist_spawn_y": 201.0,
			"tourist_despawn_y": 201.0,
			"bay_pos": Vector2(311, 181),
		},
	},
	10: {
		"name": "Tulum",
		"tagline": "Beneath the ruins, the beach is strewn with boulders.",
		"background": "res://assets/sprites/background_level10.png",
		"water": "res://assets/sprites/water10_%02d.png",
		"zones": {
			"hotel_bottom": 198.0,
			"shallow_top": 400.0,
			"deep_top": 493.0,
			"shore_y": 394.0,
			"water_top": 370.0,
			"tourist_spawn_y": 188.0,
			"tourist_despawn_y": 188.0,
			"bay_pos": Vector2(318, 168),
		},
	},
}


# Every location in the campaign, including the ones whose art has not been
# wired in yet. Used by the dev level select; a level only gets a real beach once
# it has an entry in LIST.
const NAMES := {
	1: "Cancun",
	2: "Veracruz",
	3: "Playa del Carmen",
	4: "Cozumel",
	5: "Bacalar",
	6: "Isla Holbox",
	7: "Puerto Morelos",
	8: "Mahahual",
	9: "Akumal",
	10: "Tulum",
}


static func name_of(level: int) -> String:
	return String(NAMES.get(level, "Level %d" % level))


static func has_art(level: int) -> bool:
	return LIST.has(level)


static func for_level(level: int) -> Dictionary:
	return LIST.get(level, LIST[1])
