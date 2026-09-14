class_name Spawner
extends Node

# Everything that puts entities on the beach: seaweed, deep kelp, tourists and
# washed-up packages, plus the pile-merge lookup that drifting clumps use when
# they beach themselves.
#
# Shared state (storm_active, happy_hour, player) still lives on Game -- this
# node owns the *timers and placement rules*, not the world.

const SEAWEED_SCENE := preload("res://scenes/seaweed.tscn")
const TOURIST_SCENE := preload("res://scenes/tourist.tscn")
const PACKAGE_SCENE := preload("res://scenes/package.tscn")

# --- tuning -----------------------------------------------------------------
const SEAWEED_INTERVAL := 1.05
const SEAWEED_MAX := 34
const KELP_INTERVAL := 3.0
const KELP_MAX := 7
const TOURIST_INTERVAL_MIN := 2.5
const TOURIST_INTERVAL_MAX := 5.5
const HAPPY_TOURIST_MIN := 1.0
const HAPPY_TOURIST_MAX := 1.9
const MAX_TOURISTS := 24
# Happy Hour gets its own, lower cap. At 24 the beach was impassable rather than
# difficult -- the event should force you to pick a route, not deny you one.
const MAX_TOURISTS_HAPPY := 13

# Share of ordinary tourists who swim right out past the buoys. The deep water
# was the only place the player could never be hit, which turned the most
# valuable zone into a rest stop. A minority out there keeps it tense without
# making deep kelp runs a coin flip.
const DEEP_SWIMMER_CHANCE := 0.28
const PACKAGE_EVERY_MIN := 25.0
const PACKAGE_EVERY_MAX := 45.0

# Where a new clump lands. The remainder after sand and shallow goes to deep
# water, so the bulk of the beach's supply starts a minute or more away and has
# to drift the whole way in.
const SPAWN_SAND := 0.08
const SPAWN_SHALLOW := 0.22
const SPAWN_SAND_STORM := 0.03
const SPAWN_SHALLOW_STORM := 0.12
# ----------------------------------------------------------------------------

var game

var _seaweed_t := 0.0
var _kelp_t := 0.0
var _tourist_t := 0.0
var _tourist_next := 3.0
var _package_t := 0.0
var _package_next := 30.0


func reset() -> void:
	_seaweed_t = 0.0
	_kelp_t = 0.0
	_tourist_t = 0.0
	_tourist_next = 3.0
	_package_t = 0.0
	_package_next = 30.0


func tick(delta: float) -> void:
	_tick_seaweed(delta)
	_tick_kelp(delta)
	_tick_tourists(delta)
	_tick_packages(delta)


# =============================================================================
# Seaweed
# =============================================================================

func _tick_seaweed(delta: float) -> void:
	_seaweed_t += delta
	# Typed explicitly: `game` is untyped to avoid a circular class dependency,
	# so dividing by game.difficulty() makes the whole expression untyped.
	var interval: float = SEAWEED_INTERVAL * (0.35 if game.storm_active else 1.0) \
		/ game.difficulty()
	if _seaweed_t < interval:
		return
	_seaweed_t = 0.0
	if count_seaweed(false) >= SEAWEED_MAX:
		return
	spawn_seaweed(3 if game.storm_active else 1)


func spawn_seaweed(units: int) -> void:
	# Most clumps start in deep water. Very little lands on the sand ready to
	# collect, so the shoreline is fed almost entirely by drift and stays thin.
	var sand_w := SPAWN_SAND_STORM if game.storm_active else SPAWN_SAND
	var shallow_w := SPAWN_SHALLOW_STORM if game.storm_active else SPAWN_SHALLOW

	var roll := randf()
	var pos: Vector2
	var drifts := true

	if roll < sand_w:
		pos = Vector2(randf_range(24.0, 336.0),
			randf_range(Zones.SHALLOW_TOP - 80.0, Zones.SHORE_Y - 6.0))
		drifts = false
	elif roll < sand_w + shallow_w:
		pos = Vector2(randf_range(24.0, 336.0),
			randf_range(Zones.SHALLOW_TOP + 14.0, Zones.DEEP_TOP - 12.0))
	else:
		pos = Vector2(randf_range(24.0, 336.0),
			randf_range(Zones.DEEP_TOP + 16.0, Zones.VIEW_H - 22.0))

	_add_seaweed(pos, units, false, drifts)


func _tick_kelp(delta: float) -> void:
	# Deep kelp only bothers to grow once you can actually reach it.
	if not game.player.can_enter_deep:
		return
	_kelp_t += delta
	if _kelp_t < KELP_INTERVAL:
		return
	_kelp_t = 0.0
	if count_seaweed(true) >= KELP_MAX:
		return
	var pos := Vector2(randf_range(28.0, 332.0),
		randf_range(Zones.DEEP_TOP + 22.0, Zones.VIEW_H - 24.0))
	_add_seaweed(pos, 5, true, false)


func _add_seaweed(pos: Vector2, units: int, kelp: bool, drifts: bool) -> Seaweed:
	var s: Seaweed = SEAWEED_SCENE.instantiate()
	s.setup(pos, units, game, kelp, drifts)
	s.shore_y = Zones.SHORE_Y
	game.world.add_child(s)
	return s


func count_seaweed(is_kelp: bool) -> int:
	var n := 0
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).kelp == is_kelp:
			n += 1
	return n


func find_pile_near(pos: Vector2, ignore) -> Seaweed:
	# Used by drifting clumps as they beach themselves, so the waterline grows
	# into a few fat piles instead of a hundred identical specks.
	var best: Seaweed = null
	var best_d := 26.0
	for c in game.world.get_children():
		if not (c is Seaweed) or c == ignore:
			continue
		var sw := c as Seaweed
		if sw.drifting or sw.kelp or sw.units >= Seaweed.MAX_PILE:
			continue
		var d := sw.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = sw
	return best


# =============================================================================
# Tourists and packages
# =============================================================================

func _tick_tourists(delta: float) -> void:
	_tourist_t += delta
	if _tourist_t < _tourist_next:
		return
	_tourist_t = 0.0

	var cap: int = MAX_TOURISTS_HAPPY if game.happy_hour \
		else int(MAX_TOURISTS * float(game.difficulty()))
	if count_tourists() >= cap:
		_tourist_next = 0.6
		return

	var target: float
	if game.happy_hour:
		# The whole bar empties onto the sand and heads for open water, which
		# means the crowd crosses every zone the player wants to work in.
		_tourist_next = randf_range(HAPPY_TOURIST_MIN, HAPPY_TOURIST_MAX)
		target = randf_range(Zones.DEEP_TOP + 30.0, Zones.VIEW_H - 30.0)
	else:
		# Splash target reaches up to the shoreline, so tourists park themselves
		# right on top of the pile you most want to be working.
		_tourist_next = float(randf_range(TOURIST_INTERVAL_MIN, TOURIST_INTERVAL_MAX)) \
			/ float(game.difficulty())
		if randf() < DEEP_SWIMMER_CHANCE:
			target = randf_range(Zones.DEEP_TOP + 24.0, Zones.VIEW_H - 34.0)
		else:
			target = randf_range(Zones.SHORE_Y - 10.0, Zones.DEEP_TOP - 20.0)

	var t: Tourist = TOURIST_SCENE.instantiate()
	t.game = game
	# Straight coin flip, during Happy Hour as well as ordinary trickle.
	t.setup(Vector2(randf_range(30.0, 330.0), Zones.TOURIST_SPAWN_Y),
		target, game.happy_hour, Zones.TOURIST_DESPAWN_Y, randf() < 0.5)
	game.world.add_child(t)


func count_tourists() -> int:
	var n := 0
	for c in game.world.get_children():
		if c is Tourist:
			n += 1
	return n


func _tick_packages(delta: float) -> void:
	_package_t += delta
	if _package_t < _package_next:
		return
	_package_t = 0.0

	# Packages only ever appear past the buoys, and they stay where they land.
	# Before you own the rig they show up at half rate: often enough to see what
	# you are missing, rare enough not to nag.
	var rate := 1.0 if game.player.can_enter_deep else 2.0
	_package_next = randf_range(PACKAGE_EVERY_MIN, PACKAGE_EVERY_MAX) * rate

	var pk: Package = PACKAGE_SCENE.instantiate()
	pk.setup(Vector2(randf_range(30.0, 330.0),
		randf_range(Zones.DEEP_TOP + 26.0, Zones.VIEW_H - 26.0)), game)
	game.world.add_child(pk)
