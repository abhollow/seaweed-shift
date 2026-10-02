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
		"tourists": "pink",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# Just for laughs, once a level in shift 1 (0-based below): a parasailer
		# drops out of the sky into the sea. See systems/parasail.gd.
		"parasail": {"shift": 0, "at": [40.0, 90.0]},
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
		"tourists": "blue",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# Gust fronts (sand wall, piles slide, umbrellas tumble) and lost cargo
		# (crates wash ashore, a bonus to haul). See systems/veracruz.gd.
		"veracruz": {"front_first": 25.0, "front_every": 50.0, "cargo_first": 45.0, "cargo_every": 70.0},
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
		"tourists": "purple",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# Once a level, in shift 2 (0-based below), 35-80s in: a crab digs out of
		# the sand and chases the worker. See systems/crab.gd.
		"crab": {"shift": 1, "at": [35.0, 80.0], "speed": 80.0, "chase": 24.0},
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
		"tourists": "aqua",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# A cruise ship once a shift (and its passengers), bioluminescence, and
		# night divers in the shallows. See systems/cozumel.gd.
		"cozumel": {"cruise_at": [40.0, 80.0], "cruise_crowd": 8, "glow_first": 25.0, "glow_every": 60.0,
			"divers_first": 30.0, "divers_every": 40.0},
		"tagline": "The night shift. Work by lantern light -- and watch for the moon.",
		"music": [
			"res://audio/Island_Night_Drive_1.mp3",
			"res://audio/Island_Night_Drive_2.mp3",
		],
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
		"tourists": "green",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# A kayak tour crossing the shallows. (Big waves also throw wading
		# tourists up the beach -- that lives in systems/surf.gd.)
		"kayaks": {"first": 30.0, "every": 55.0, "count": 4},
		"tagline": "Count the small waves -- then get out before the big one knocks you back to shore.",
		"music": [
			"res://audio/Tidal_Rush_1.mp3",
			"res://audio/Tidal_Rush_2.mp3",
		],
		# Surf in countable sets: 2-3 small waves, then one BIG wave that knocks
		# the worker back and carries seaweed in. Every fourth big wave is a
		# ROGUE that runs up past the waterline onto the sand.
		"surf": {
			"first": 18.0,
			"every": 26.0,
			"smalls": [2, 3],
			"gap": 2.4,
			"speed": 60.0,
			"knock": 110.0,
			"rogue_every": 4,
			"runup": 55.0,
			# share of drifting seaweed the big wave carries, by shift -- the
			# same as the Playa del Carmen ferry
			"share": [0.2, 0.3, 0.6, 0.8],
		},
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
		# A round island: the resort compound in the middle, a ring of sand, a
		# ring of shallows, and deep water on every side. The ONLY radial level,
		# so every zone value below is a RADIUS from the island's centre.
		#
		# Collecting is easy here -- the skip is in the middle, so every trip is
		# short. Holbox is a change of pace and picture, not a step up in
		# difficulty: storms and Happy Hour are switched off, and three
		# signature events take their place.
		"name": "Isla Holbox",
		"tourists": "red",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		"tagline": "A tiny round island. The skip is in the middle -- take any street in. Watch for whale sharks, low tide and flamingos.",
		"background": "res://assets/sprites/background_level6.png",
		"water": "",
		"no_storms": true,
		"no_happy_hour": true,
		# 25% less seaweed on every shift: it arrives from all 360 degrees, so
		# the beach takes more walking to cover than a straight one.
		"spawn_scale": 0.75,
		"bin_offset": 0.0,
		# The skip sits in the central plaza; eight streets run from it out to
		# the beach, with homes between them. Every side of the island is the
		# same short walk from the skip.
		"zones": {
			"radial": true,
			"center": Vector2(180, 320),
			"depth_max": 270.0,
			"hotel_bottom": 128.0,
			"shore_y": 149.0,
			"shallow_top": 155.0,
			"deep_top": 208.0,
			"water_top": 155.0,
			# Tourists appear on the edge of town and fade in there, rather than
			# walking out of the plaza: the streets are narrower than the tractor,
			# and they are the only way to the skip.
			"tourist_spawn_y": 126.0,
			"tourist_despawn_y": 126.0,
			"bay_pos": Vector2(180, 320),
			"bay_size": Vector2(52, 52),
			"streets": 8,
			"street_offset": 0.0,
			"street_half_w": 12.0,
			"plaza_r": 34.0,
		},
		"holbox": {
			"first": 20.0,
			"every": 32.0,
			"whale_len": 13.0,
			"whale_crowd": 5,
			"sandbar_len": 16.0,
			"sandbar_reach": 60.0,
			"sandbar_width": 28.0,
			"sandbar_kelp": 3,
			"flamingo_len": 20.0,
			"flamingo_arc": 0.5,
			"flamingo_count": 4,
		},
	},
	7: {
		"name": "Puerto Morelos",
		"tourists": "blue",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# Just for laughs, once a level in shift 2 (0-based below): a parasailer
		# drops out of the sky into the sea. See systems/parasail.gd.
		"parasail": {"shift": 1, "at": [40.0, 90.0]},
		# Once a level, in shift 3 (0-based below), 35-80s in: a crab digs out of
		# the sand and chases the worker. See systems/crab.gd.
		"crab": {"shift": 2, "at": [35.0, 80.0], "speed": 80.0, "chase": 24.0},
		"tagline": "A stream runs across the beach. Wade it and it carries you -- and the tourists -- out to sea.",
		# Unassigned since level 2 became Veracruz; a sunny fishing town suits them.
		"music": [
			"res://audio/Island_Jump.mp3",
			"res://audio/Island_Vibes.mp3",
		],
		# The stream, traced from the art, upstream first. Wading it slows the
		# worker and carries them -- and tourists -- downstream. Seaweed in it
		# floats down to the mouth. (A footbridge was tried and removed:
		# playtest found it pointless.)
		"stream": {
			"points": [[72, 166], [94, 180], [119, 190], [132, 204], [135, 222], [136, 240],
				[144, 251], [157, 261], [172, 270], [195, 280], [216, 290], [230, 300],
				[239, 310], [246, 320], [252, 330], [258, 340], [263, 351], [268, 363],
				[274, 374], [278, 383]],
			"half_w": 9.0,
			"current": 85.0,
			"slow": 0.55,
			"float_speed": 28.0,
			"flood_first": 40.0,
			"flood_every": 60.0,
			"flood_len": 12.0,
			"flood_debris": 5,
		},
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
		"tourists": "purple",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# Once a level, in shift 2 (0-based below), 35-80s in: a crab digs out of
		# the sand and chases the worker. See systems/crab.gd.
		"crab": {"shift": 1, "at": [35.0, 80.0], "speed": 80.0, "chase": 24.0},
		"tagline": "Sargassum season. Golden weed is heavy and rots fast -- and watch for the mat coming in.",
		"music": [
			"res://audio/Tense_Beach_Game_1.mp3",
			"res://audio/Tense_Beach_Game_2.mp3",
		],
		# Half of what washes in is sargassum: two slots per unit, worth double,
		# rots 1.5x as fast. The MAT drifts in slowly from far out and breaks up
		# into sargassum piles where it lands -- more of them each shift.
		"sargassum": {
			"share": 0.5,
			"mat_first": 30.0,
			"mat_every": 65.0,
			"mat_speed": 12.0,
			"mat_width": 110.0,
			"mat_piles": [4, 6, 8, 10],
		},
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
		"tourists": "aqua",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		"tagline": "The bay of turtles. Work around the nests -- and when they hatch, clear the way to the sea.",
		# Turtle-nest enclosures, measured from the art: solid for the worker
		# and tourists, and seaweed never lands inside. [x0, y0, x1, y1]
		"nests": [[38, 266, 78, 294], [201, 277, 244, 305], [107, 327, 150, 355], [282, 325, 325, 352]],
		# A nest hatches every ~55s: hatchlings crawl to the sea, stopped by any
		# seaweed pile in their way.
		"hatch": {
			"first": 35.0,
			"every": 55.0,
			"count": 8,
			"speed": 16.0,
			"limit": 25.0,
		},
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
		"tourists": "pink",  # most of the crowd wears this; see Spawner.TOURIST_COLOURS
		# Just for laughs, once a level in shift 2 (0-based below): a parasailer
		# drops out of the sky into the sea. See systems/parasail.gd.
		"parasail": {"shift": 1, "at": [40.0, 90.0]},
		# Once a level, in shift 1 -- before the hurricane builds; Tulum's later
		# shifts are the hardest in the game already. See systems/crab.gd.
		"crab": {"shift": 0, "at": [35.0, 80.0], "speed": 80.0, "chase": 24.0},
		"tagline": "The finale. A hurricane is coming -- and when the eye passes, the wind turns.",
		# The hurricane conducts the wind, the storm and the surf through the
		# shift; random storms and Happy Hour are off so nothing competes.
		"no_storms": true,
		"no_happy_hour": true,
		# Rot no faster than 0.8x on any shift (shifts 3-4 are 0.62 / 0.58 elsewhere):
		# the gale slows every trip, so piles rotted while the worker fought the
		# wind to reach them. See Game.rot_scale().
		"rot_floor": 0.8,
		"hurricane": {
			"gathering": 0.15,
			"front": 0.35,
			"eye": 0.6,
			# 30s (was 20): the only breather, and the bot arrived at it already
			# failing on every late Tulum shift.
			"eye_len": 30.0,
		},
		# Wind and surf parameters; the hurricane switches them on and off.
		"wind": {"strength": 0.0},
		# The palms and jungle treeline sway -- barely in the calm, whipping in
		# the storm, and leaning whichever way the wind blows.
		"sway": {
			"mask": "res://assets/sprites/sway_level10.png",
			"amp": 1.6,
			"lean": 1.2,
		},
		"surf": {
			"first": 6.0,
			"every": 20.0,
			"smalls": [2, 3],
			"gap": 2.4,
			"speed": 60.0,
			"knock": 110.0,
			"rogue_every": 3,
			"runup": 55.0,
			# Lower than Bacalar's from shift 3: here the surf runs through a held
			# storm and a gale, and at 60/80% the bot lost every late Tulum shift
			# within 30s of the front arriving.
			"share": [0.2, 0.3, 0.4, 0.5],
		},
		"background": "res://assets/sprites/background_level10.png",
		"water": "res://assets/sprites/water10_%02d.png",
		"zones": {
			"hotel_bottom": 192.0,
			"shore_y": 384.0,
			"shallow_top": 390.0,
			"deep_top": 515.0,
			"water_top": 360.0,
			"tourist_spawn_y": 182.0,
			"tourist_despawn_y": 182.0,
			"bay_pos": Vector2(311, 160),
		},
		# The skip sprite sits up on the plaza; at the bay centre it was drawn on
		# the cliff face. Only the drawing moves -- the drop-off zone is unchanged.
		"bin_y": -34.0,
		"music": [
			"res://audio/Tropical_Storm_Reggae_1.mp3",
			"res://audio/Tropical_Storm_Reggae_2.mp3",
		],
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
