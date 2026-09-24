class_name Upgrades
extends RefCounted

# One place to tune the whole economy. Add a row here, then handle its id in
# Game.apply_upgrade(). Nothing else needs to change.
#
# Tier 1 is everything you can carry or wear. It is cheap and it all stacks --
# the four of them together still cost less than the tractor.
# Tier 2 is machinery. The tractor is the wall between them, and buying it is
# meant to be the biggest single moment in the run.
# Tier 3 is deep water. Only the Trawler Rig lives there so far.
#
# The tiers map onto the map itself: tier 1 works the narrow beach strip, tier 2
# opens the shallows, tier 3 opens the deep.

# Tier drives two things: which shift's shop features the upgrade, and the
# order upgrades become RETAINABLE across levels. Split 4 / 3 / 3 so that every
# themed shift has a real shop and the retain arc runs exactly ten levels. The
# hopper and diesel sit with deep water because they are the late-game kit for
# long kelp runs, not tractor basics.
const TIER_NAMES := {
	1: "TIER 1  --  ON FOOT",
	2: "TIER 2  --  THE TRACTOR",
	3: "TIER 3  --  DEEP WATER",
}

static func by_id(id: String) -> Dictionary:
	for up in LIST:
		if String(up["id"]) == id:
			return up
	return {}


static func total_cost() -> int:
	# Used by the smoke test to keep the economy solvable: the full kit must
	# cost less than a complete run can earn, or the last upgrades are
	# unreachable in normal play.
	var t := 0
	for up in LIST:
		t += int(up["cost"])
	return t


const LIST := [
	{
		"id": "rake2",
		"tier": 1,
		"name": "Rake",
		"cost": 60,
		"desc": "Stop picking by hand. Twice as fast, wider sweep.",
		"needs": "",
	},
	{
		"id": "jacket",
		"tier": 1,
		"name": "Rain Jacket",
		"cost": 140,
		"desc": "Work at full speed during storms.",
		"needs": "",
	},
	{
		"id": "backpack",
		"tier": 1,
		"name": "Backpack",
		"cost": 220,
		"desc": "Carry 10 instead of 5. Half the trips.",
		"needs": "rake2",
	},
	{
		"id": "waders",
		"tier": 1,
		"name": "Wetsuit Waders",
		"cost": 320,
		"desc": "No more slog in the shallows.",
		"needs": "",
	},
	{
		"id": "tractor",
		"tier": 2,
		"name": "Tractor",
		"cost": 800,
		"desc": "Faster, and carries 20. Bogs down in the shallows.",
		"needs": "waders",
	},
	{
		"id": "sand_tires",
		"tier": 2,
		"name": "Sand Tires",
		"cost": 1000,
		"desc": "Full tractor speed in the shallows.",
		"needs": "tractor",
	},
	{
		"id": "sorter",
		"tier": 2,
		"name": "Baling Sorter",
		"cost": 1200,
		"desc": "Everything sells for double.",
		"needs": "tractor",
	},
	{
		"id": "diesel",
		"tier": 3,
		"name": "Illicit Diesel",
		"cost": 1700,
		"desc": "Tractor runs 40% faster.",
		"needs": "tractor",
	},
	{
		"id": "hopper",
		"tier": 3,
		"name": "Rear Hopper",
		"cost": 1900,
		"desc": "Carry 100. Far fewer trips.",
		"needs": "tractor",
	},
	{
		"id": "trawler",
		"tier": 3,
		"name": "Trawler Rig",
		"cost": 3100,
		"desc": "Past the buoys. Deep kelp is worth 3x.",
		"needs": "hopper",
	},
]
