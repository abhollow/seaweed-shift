class_name Zones
extends RefCounted

# Beach geometry, in one dependency-free place.
#
# This exists to break a cycle: Game holds the systems, and the systems need the
# zone boundaries. If those constants lived on Game, every system would have to
# reference `Game`, and GDScript refuses to compile that cycle. Zones depends on
# nothing, so everyone can read it.
#
# Changing the layout is these numbers and nothing else -- player bounds, the
# bay driveway, all four spawn bands and the tourist routes derive from them.
#
# The beach geometry is PER LEVEL: each location has its own beach width, its own
# shallows, its own deep line. Those values are static vars, set by apply() when
# a level starts. VIEW_W, VIEW_H and BIN_SIZE never change and stay constants.

const VIEW_W := 360.0
const VIEW_H := 640.0

static var HOTEL_BOTTOM := 190.0
static var SHALLOW_TOP := 420.0
static var DEEP_TOP := 530.0

static var SHORE_Y := 414.0            # where drifting seaweed settles

# Top of the animated water strip. Sits slightly above the foam line so the
# animation's amplitude has room to fade in against static sand.
static var WATER_TOP := 390.0

# Tourists appear and vanish just inside the resort, so they always emerge from
# and retreat into the hotel grounds rather than popping in on open sand.
static var TOURIST_SPAWN_Y := 180.0
static var TOURIST_DESPAWN_Y := 180.0

# The loading bay straddles the hotel/beach boundary on the right edge. It is
# also the only safe square on the map.
static var BAY_POS := Vector2(311, 156)
# Tightened from 96x112. The old zone reached far enough left and down that a
# load could be banked from open sand near the palms, nowhere near the skip --
# the safe zone should be the bay, not its postcode.
static var BAY_SIZE := Vector2(62, 74)
# Half the original size. The background art already reads as a service bay, so
# the skip only needs to mark the exact drop point, not dominate the corner.
const BIN_SIZE := Vector2(28, 32)


# The layout every value above starts at -- level 1, Cancun. Kept so apply() can
# fall back to it for anything a beach does not override.
const DEFAULTS := {
	"hotel_bottom": 190.0,
	"shallow_top": 420.0,
	"deep_top": 530.0,
	"shore_y": 414.0,
	"water_top": 390.0,
	"tourist_spawn_y": 180.0,
	"tourist_despawn_y": 180.0,
	"bay_pos": Vector2(311, 156),
	"bay_size": Vector2(62, 74),
}


static func apply(beach: Dictionary) -> void:
	var z := DEFAULTS.duplicate()
	z.merge(beach.get("zones", {}), true)
	HOTEL_BOTTOM = float(z["hotel_bottom"])
	SHALLOW_TOP = float(z["shallow_top"])
	DEEP_TOP = float(z["deep_top"])
	SHORE_Y = float(z["shore_y"])
	WATER_TOP = float(z["water_top"])
	TOURIST_SPAWN_Y = float(z["tourist_spawn_y"])
	TOURIST_DESPAWN_Y = float(z["tourist_despawn_y"])
	BAY_POS = z["bay_pos"]
	BAY_SIZE = z["bay_size"]
