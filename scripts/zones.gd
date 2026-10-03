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
const BIN_SIZE := Vector2(42, 48)


# ---- Radial layout (Isla Holbox) ------------------------------------------
#
# Every beach but one is a set of horizontal bands: resort at the top, sea at
# the bottom, so "how far out to sea" is simply y. Holbox is a round island --
# sea on every side -- where it is the distance from the island's centre.
#
# Systems ask depth() instead of reading y, and move along outward() instead of
# +y. On a banded beach these return exactly y and (0, 1), so every banded level
# behaves precisely as before. On a radial one, the zone values above
# (HOTEL_BOTTOM, SHORE_Y, SHALLOW_TOP, DEEP_TOP, TOURIST_*) are RADII.
static var RADIAL := false
static var CENTER := Vector2(180, 320)
static var DEPTH_MAX := 640.0     # furthest out anything goes: the screen, or a radius

# A village inside the island: streets radiating from a central plaza (where the
# skip is) out to the beach, with homes between them. The streets and plaza are
# walkable; the homes are not. STREETS = 0 means no village.
static var STREETS := 0
static var STREET_OFFSET := 0.0   # angle of street 0, radians
static var STREET_HALF_W := 12.0
static var PLAZA_R := 0.0


static func street_angle(k: int) -> float:
	return STREET_OFFSET + float(k) * TAU / float(maxi(STREETS, 1))


static func nearest_street(p: Vector2) -> int:
	if STREETS <= 0:
		return -1
	var step := TAU / float(STREETS)
	return posmod(int(round(((p - CENTER).angle() - STREET_OFFSET) / step)), STREETS)


static func street_axis(k: int) -> Vector2:
	var a := street_angle(k)
	return Vector2(cos(a), sin(a))


static func depth(p: Vector2) -> float:
	return p.distance_to(CENTER) if RADIAL else p.y


static func outward(p: Vector2) -> Vector2:
	# Unit vector pointing out to sea from p.
	if not RADIAL:
		return Vector2(0, 1)
	var v := p - CENTER
	return v / v.length() if v.length() > 0.001 else Vector2(0, 1)


static func at_depth(p: Vector2, d: float) -> Vector2:
	# p moved straight in or out to sea until it sits at depth d.
	if not RADIAL:
		return Vector2(p.x, d)
	return CENTER + outward(p) * d


static func random_point(d0: float, d1: float) -> Vector2:
	# A random on-screen point between depths d0 and d1.
	if not RADIAL:
		return Vector2(randf_range(24.0, VIEW_W - 24.0), randf_range(d0, d1))
	for i in 24:
		var a := randf() * TAU
		var q := CENTER + Vector2(cos(a), sin(a)) * randf_range(d0, d1)
		if q.x > 24.0 and q.x < VIEW_W - 24.0 and q.y > 22.0 and q.y < VIEW_H - 22.0:
			return q
	# Straight up is always on screen for a centred island.
	return CENTER + Vector2(0.0, -randf_range(d0, d1))


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
	"radial": false,
	"center": Vector2(180, 320),
	"depth_max": 640.0,
	"streets": 0,
	"street_offset": 0.0,
	"street_half_w": 12.0,
	"plaza_r": 0.0,
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
	RADIAL = bool(z["radial"])
	CENTER = z["center"]
	DEPTH_MAX = float(z["depth_max"])
	STREETS = int(z["streets"])
	STREET_OFFSET = float(z["street_offset"])
	STREET_HALF_W = float(z["street_half_w"])
	PLAZA_R = float(z["plaza_r"])
