class_name Hatchlings
extends Node2D

# Akumal, the bay of turtles. The signature event: a nest HATCHES, and a line of
# baby turtles crawls from it down the beach to the sea.
#
# Any seaweed pile in their path stops them -- one of sargassum's real harms to
# nesting beaches. Clear the way and they reach the water, and each one that
# makes it pays out; leave them stuck when time runs out and reputation dips.
#
# It gives the player a positive goal for once: not just "keep the beach clean",
# but "clear the way HERE, now".

var game
var active := false
var first := 35.0
var every := 55.0
var count := 8
var speed := 16.0
var limit := 25.0
var reward_units := 3            # each hatchling that makes it pays this many units' worth
var lost_rep := 4.0              # reputation dip per hatchling left stranded

var turtles: Array = []          # {pos, stuck, done, wig}
var _t := -1.0                   # seconds into a hatching, < 0 when none
var _next := 0.0
var _saved := 0
var hatched := 0                 # hatchlings in the current hatching
var _warned := false             # the shoreline seaweed is planted
const PER_NEST_MIN := 1
const PER_NEST_MAX := 2
const PLANT_NESTS := 3           # nests that get seaweed in their way
const WARN_LEAD := 8.0           # seconds of warning before they hatch
var _result_t := 0.0
var _result := ""
var _anim := 0.0

# Two crawl frames, head pointing DOWN (toward the sea), drawn at 2x. Each
# hatchling alternates between them on its own offset, so the line doesn't
# paddle in unison.
const FRAMES := [preload("res://assets/sprites/hatchling_f0.png"), preload("res://assets/sprites/hatchling_f1.png")]
const CRAWL_FPS := 6.0


func configure(beach: Dictionary) -> void:
	var h: Dictionary = beach.get("hatch", {})
	active = not h.is_empty() and game != null and not game.nests.is_empty()
	visible = active
	first = float(h.get("first", 35.0))
	every = float(h.get("every", 55.0))
	count = int(h.get("count", 8))
	speed = float(h.get("speed", 16.0))
	limit = float(h.get("limit", 25.0))
	turtles.clear()
	_t = -1.0
	_result_t = 0.0
	_next = first
	_warned = false
	hatched = 0
	queue_redraw()


func hatching() -> bool:
	return active and _t >= 0.0


func status_text() -> String:
	if hatching():
		return "HATCHLINGS! CLEAR THEIR PATH TO THE SEA"
	if active and _warned and _next > 0.0:
		return "THE NESTS ARE STIRRING -- CLEAR THE SHORE"
	if _result_t > 0.0:
		return _result
	return ""


func start(nest_index: int = -1) -> void:
	# A hatching: one or two from EVERY nest -- or, given a nest, `count`
	# from that one alone (the tests use that to aim at a known path).
	if game == null or game.nests.is_empty():
		return
	turtles.clear()
	var which: Array = [nest_index] if nest_index >= 0 else range(game.nests.size())
	for i in which:
		var r: Rect2 = game.nests[i]
		var n: int = count if nest_index >= 0 else randi_range(PER_NEST_MIN, PER_NEST_MAX)
		for k in n:
			turtles.append({
				"pos": Vector2(r.position.x + r.size.x * (0.2 + 0.6 * float(k) / float(maxi(n - 1, 1))),
					r.end.y + randf_range(0.0, 4.0)),
				"done": false,
				"wig": randf() * TAU,
				# Each wanders its own way down: a slow sway of its own speed
				# and size, and a lean to one side.
				"weave": randf_range(0.7, 1.5),
				"sway": randf_range(10.0, 18.0),
				"drift": randf_range(-6.0, 6.0),
			})
	hatched = turtles.size()
	_t = 0.0
	_saved = 0
	_warned = false
	_next = every * randf_range(0.85, 1.15)


func _plant_seaweed() -> void:
	# Just before a hatching, a few clumps wash up on the shoreline right below
	# the nests -- in the way, on purpose. Left to chance, seaweed was rarely
	# in their path and the event asked nothing of the player. They drift in
	# from the shallows rather than appearing on the sand.
	var idx := range(game.nests.size())
	idx.shuffle()
	for i in idx.slice(0, mini(PLANT_NESTS, idx.size())):
		var r: Rect2 = game.nests[i]
		var p := Vector2(r.get_center().x + randf_range(-8.0, 8.0), Zones.SHALLOW_TOP + 6.0)
		game.spawner._add_seaweed(p, randi_range(2, 3), false, true)


func blocked(p: Vector2) -> bool:
	# Is a seaweed pile in the way of a hatchling at p?
	return _blocked_by(p, _piles())


func _piles() -> PackedVector3Array:
	# Every beached pile as (x, y, reach) -- gathered once a tick, not once per
	# hatchling per tick.
	var out := PackedVector3Array()
	for c in game.world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if not sw.drifting and not sw.is_queued_for_deletion() and sw.units > 0:
				out.append(Vector3(sw.position.x, sw.position.y, sw._size * 0.45 + 3.0))
	return out


static func _blocked_by(p: Vector2, piles: PackedVector3Array) -> bool:
	for q in piles:
		if p.distance_to(Vector2(q.x, q.y)) < q.z:
			return true
	return false


func tick(delta: float) -> void:
	if not active:
		return
	_anim = fposmod(_anim + delta, TAU * 20.0)
	_result_t = maxf(0.0, _result_t - delta)
	if not hatching():
		_next -= delta
		if _next <= WARN_LEAD and not _warned and game != null:
			_warned = true
			_plant_seaweed()
		if _next <= 0.0:
			start()
		return
	_t += delta
	# Every hatchling not yet in the sea -- INCLUDING any waiting behind a pile.
	# The first version counted only the ones actually moving, so a hatching
	# with every hatchling blocked ended on its first tick and wrote them all
	# off before the player could clear the way.
	var remaining := 0
	var piles := _piles()
	for h in turtles:
		if h["done"]:
			continue
		remaining += 1
		var p: Vector2 = h["pos"]
		# Wandering down the beach, not marching in a line.
		var wander := sin(_anim * float(h["weave"]) + float(h["wig"])) * float(h["sway"]) + float(h["drift"])
		var step := Vector2(wander, speed) * delta
		if _blocked_by(p + step * 4.0, piles):
			continue                      # waits, flippers going, until the way clears
		p += step
		# Round any other nest on the way down, never through it.
		if game != null:
			p = game.sidestep_nests(p, 0.0)
		p.x = clampf(p.x, 16.0, Zones.VIEW_W - 16.0)
		h["pos"] = p
		if p.y >= Zones.SHALLOW_TOP:
			h["done"] = true
			_saved += 1
			if game != null:
				game.add_credits(int(round(game.price_per_unit * reward_units)))
				game.popup("SAFE!", p + Vector2(0, -8), Color(0.55, 0.95, 0.85))
			remaining -= 1
	if remaining == 0 or _t >= limit:
		_finish()
	queue_redraw()


func _finish() -> void:
	var lost := hatched - _saved
	if lost > 0 and game != null:
		game.rep.value = maxf(0.0, game.rep.value - lost_rep * float(lost))
	if game != null:
		# The short package chime -- NOT "complete", which is the 15s shift sting.
		game.sfx("package" if lost == 0 else "warn", 1.0, -6.0)
	_result = "ALL %d HATCHLINGS MADE IT!" % hatched if lost == 0 \
		else "%d OF %d HATCHLINGS MADE IT" % [_saved, hatched]
	_result_t = 3.0
	_t = -1.0
	turtles.clear()
	queue_redraw()


func _draw() -> void:
	if not hatching():
		return
	# Tiny dark turtles, flippers paddling as they go.
	for h in turtles:
		if h["done"]:
			continue
		var p: Vector2 = h["pos"]
		var tex: Texture2D = FRAMES[int(_anim * CRAWL_FPS + float(h["wig"]) * 3.0) % FRAMES.size()]
		var sz := tex.get_size() * 2.0
		draw_texture_rect(tex, Rect2(p - sz * 0.5, sz), false)
