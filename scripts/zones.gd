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

const VIEW_W := 360.0
const VIEW_H := 640.0

const HOTEL_BOTTOM := 190.0
const SHALLOW_TOP := 420.0
const DEEP_TOP := 530.0

const SHORE_Y := 414.0            # where drifting seaweed settles

# Top of the animated water strip. Sits slightly above the foam line so the
# animation's amplitude has room to fade in against static sand.
const WATER_TOP := 390.0

# Tourists appear and vanish just inside the resort, so they always emerge from
# and retreat into the hotel grounds rather than popping in on open sand.
const TOURIST_SPAWN_Y := 180.0
const TOURIST_DESPAWN_Y := 180.0

# The loading bay straddles the hotel/beach boundary on the right edge. It is
# also the only safe square on the map.
const BAY_POS := Vector2(311, 156)
# Tightened from 96x112. The old zone reached far enough left and down that a
# load could be banked from open sand near the palms, nowhere near the skip --
# the safe zone should be the bay, not its postcode.
const BAY_SIZE := Vector2(62, 74)
# Half the original size. The background art already reads as a service bay, so
# the skip only needs to mark the exact drop point, not dominate the corner.
const BIN_SIZE := Vector2(28, 32)
