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
var _result_t := 0.0
var _result := ""
var _anim := 0.0


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


func hatching() -> bool:
	return active and _t >= 0.0


func status_text() -> String:
	if hatching():
		return "HATCHLINGS! CLEAR THEIR PATH TO THE SEA"
	if _result_t > 0.0:
		return _result
	return ""


func start(nest_index: int = -1) -> void:
	if game == null or game.nests.is_empty():
		return
	var i: int = nest_index if nest_index >= 0 else randi() % game.nests.size()
	var r: Rect2 = game.nests[i]
	turtles.clear()
	for k in count:
		turtles.append({
			"pos": Vector2(r.position.x + r.size.x * (0.2 + 0.6 * float(k) / float(maxi(count - 1, 1))),
				r.end.y + randf_range(0.0, 4.0)),
			"done": false,
			"wig": randf() * TAU,
		})
	_t = 0.0
	_saved = 0
	_next = every * randf_range(0.85, 1.15)


func blocked(p: Vector2) -> bool:
	# Is a seaweed pile in the way of a hatchling at p?
	for c in game.world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if not sw.drifting and not sw.is_queued_for_deletion() and sw.units > 0 \
					and p.distance_to(sw.position) < sw._size * 0.45 + 3.0:
				return true
	return false


func tick(delta: float) -> void:
	if not active:
		return
	_anim = fposmod(_anim + delta, TAU * 20.0)
	_result_t = maxf(0.0, _result_t - delta)
	if not hatching():
		_next -= delta
		if _next <= 0.0:
			start()
		return
	_t += delta
	# Every hatchling not yet in the sea -- INCLUDING any waiting behind a pile.
	# The first version counted only the ones actually moving, so a hatching
	# with every hatchling blocked ended on its first tick and wrote them all
	# off before the player could clear the way.
	var remaining := 0
	for h in turtles:
		if h["done"]:
			continue
		remaining += 1
		var p: Vector2 = h["pos"]
		var step := Vector2(sin(_anim * 5.0 + float(h["wig"])) * 6.0, speed) * delta
		if blocked(p + step * 4.0):
			continue                      # waits, flippers going, until the way clears
		p += step
		h["pos"] = p
		if p.y >= Zones.SHALLOW_TOP:
			h["done"] = true
			_saved += 1
			if game != null:
				game.add_credits(game.price_per_unit * reward_units)
				game.popup("SAFE!", p + Vector2(0, -8), Color(0.55, 0.95, 0.85))
			remaining -= 1
	if remaining == 0 or _t >= limit:
		_finish()
	queue_redraw()


func _finish() -> void:
	var lost := count - _saved
	if lost > 0 and game != null:
		game.rep.value = maxf(0.0, game.rep.value - lost_rep * float(lost))
	if game != null:
		# The short package chime -- NOT "complete", which is the 15s shift sting.
		game.sfx("package" if lost == 0 else "warn", 1.0, -6.0)
	_result = "ALL %d HATCHLINGS MADE IT!" % count if lost == 0 \
		else "%d OF %d HATCHLINGS MADE IT" % [_saved, count]
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
		var flap := sin(_anim * 12.0 + float(h["wig"])) * 1.5
		var shell := Color(0.25, 0.22, 0.14)
		var skin := Color(0.38, 0.33, 0.22)
		draw_rect(Rect2(p + Vector2(-3, -4), Vector2(6, 7)), shell)
		draw_rect(Rect2(p + Vector2(-2, -3), Vector2(4, 5)), Color(0.33, 0.29, 0.18))
		draw_rect(Rect2(p + Vector2(-1, 3), Vector2(2, 2)), skin)           # head, toward the sea
		draw_line(p + Vector2(-3, -1), p + Vector2(-6, -1 + flap), skin, 1.5)
		draw_line(p + Vector2(3, -1), p + Vector2(6, -1 - flap), skin, 1.5)
		draw_line(p + Vector2(-3, 2), p + Vector2(-5, 3 - flap), skin, 1.5)
		draw_line(p + Vector2(3, 2), p + Vector2(5, 3 + flap), skin, 1.5)
