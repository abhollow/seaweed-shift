class_name Surf
extends Node2D

# Big surf on Bacalar. Waves come in SETS you can count: two or three SMALL waves,
# then one BIG wave.
#
#   * Small waves are warnings. Thin swells that break into a little foam and
#     harm nothing -- they are there to be counted.
#   * The big wave is unmistakable: a tall dark swell with a heavy breaker and a
#     rising roar as it approaches. It is the only wave that knocks the worker
#     back to shore, and it carries a share of the drifting seaweed in with it,
#     at the same per-shift rates as the Playa del Carmen ferry.
#
# The first version had every wave in the set knock the worker back. Timing
# stopped mattering -- you were simply thrown out of the water three times --
# so it read as an annoyance rather than a rhythm to play around. Now: count,
# work, get out.
#
# Every few sets the big wave is a ROGUE that runs right up past the waterline,
# so the lower beach is not safe either.

var game
var active := false
var first := 18.0
var every := 26.0
var smalls := [2, 3]
var gap := 2.4
var speed := 60.0
var knock := 110.0
var rogue_every := 4
var runup := 55.0

var waves: Array = []            # {y, big, rogue, riders}
var _queue: Array = []           # waves still to arrive this set: "small" / "big"
var _next_set := 0.0
var _spawn_t := 0.0
var _sets := 0
var _set_rogue := false
var _big_launched := false
var _shares: Array = [0.2, 0.3, 0.6, 0.8]
var _spray: Array = []
var _churn := 0.0


func configure(beach: Dictionary) -> void:
	var f: Dictionary = beach.get("surf", {})
	active = not f.is_empty()
	visible = active
	first = float(f.get("first", 18.0))
	every = float(f.get("every", 26.0))
	smalls = f.get("smalls", [2, 3])
	gap = float(f.get("gap", 2.4))
	speed = float(f.get("speed", 60.0))
	knock = float(f.get("knock", 110.0))
	rogue_every = int(f.get("rogue_every", 4))
	runup = float(f.get("runup", 55.0))
	var sh = f.get("share", [0.2, 0.3, 0.6, 0.8])
	_shares = sh if typeof(sh) == TYPE_ARRAY else [float(sh)]
	waves.clear()
	_queue.clear()
	_spray.clear()
	_sets = 0
	_big_launched = false
	_next_set = first
	queue_redraw()


func share_for(shift_index: int) -> float:
	if _shares.is_empty():
		return 0.2
	return float(_shares[clampi(shift_index, 0, _shares.size() - 1)])


func set_rolling() -> bool:
	return active and (not waves.is_empty() or not _queue.is_empty())


func big_coming() -> bool:
	# The big wave is on its way -- the moment to get out of the water.
	return set_rolling() and _big_launched


func rogue() -> bool:
	return set_rolling() and _set_rogue


func limit_for(w: Dictionary) -> float:
	# Where a wave stops: the waterline, or -- for a rogue -- up the sand.
	return Zones.SHALLOW_TOP - (runup if bool(w["rogue"]) else 0.0)


func start_set() -> void:
	_sets += 1
	_set_rogue = rogue_every > 0 and _sets % rogue_every == 0
	_big_launched = false
	_queue.clear()
	var n := int(smalls[randi() % smalls.size()]) if smalls.size() > 0 else 2
	for i in n:
		_queue.append("small")
	_queue.append("big")
	_spawn_t = 0.0
	_next_set = every * randf_range(0.8, 1.2)


func tick(delta: float) -> void:
	if not active:
		return
	_churn = fposmod(_churn + delta * 6.0, TAU * 50.0)
	if not _queue.is_empty():
		_spawn_t -= delta
		if _spawn_t <= 0.0:
			_launch(String(_queue.pop_front()))
			_spawn_t = gap
	elif waves.is_empty():
		_next_set -= delta
		if _next_set <= 0.0:
			start_set()

	var keep := []
	for w in waves:
		var prev: float = w["y"]
		var lim := limit_for(w)
		w["y"] = maxf(lim, prev - speed * delta)
		if bool(w["big"]):
			_hit(prev, float(w["y"]))
			_carry(w)
		if float(w["y"]) <= lim:
			_break(w, lim)
		else:
			keep.append(w)
	waves = keep
	_tick_spray(delta)
	queue_redraw()


func _launch(kind: String) -> void:
	var big := kind == "big"
	var w := {"y": Zones.VIEW_H + 16.0, "big": big, "rogue": big and _set_rogue, "riders": []}
	if big:
		_big_launched = true
		w["riders"] = _pick_riders()
		if game != null:
			game.sfx("gust", 0.55, -2.0)        # the roar of the big one coming
	waves.append(w)


func _pick_riders() -> Array:
	# The same per-shift share of drifting seaweed as the ferry wake.
	var out := []
	if game == null:
		return out
	var pool := []
	for c in game.world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if sw.drifting and not sw.kelp:
				pool.append(sw)
	pool.shuffle()
	var n := int(round(float(pool.size()) * share_for(game.level_index)))
	for i in n:
		out.append(pool[i])
	return out


func _carry(w: Dictionary) -> void:
	# Seaweed the crest has reached is swept along just ahead of it.
	var y: float = w["y"]
	for sw in w["riders"]:
		if is_instance_valid(sw) and sw.drifting and sw.position.y > y - 3.0:
			sw.position.y = y - 3.0


func _hit(prev: float, now: float) -> void:
	# The big wave's crest swept past the worker: knocked back toward shore.
	if game == null or game.player == null:
		return
	var py: float = game.player.position.y
	if py <= prev and py > now:
		game.player.knock(knock)
		game.sfx("hit", 0.7, -8.0)


func _break(w: Dictionary, y: float) -> void:
	var big := bool(w["big"])
	for i in (70 if big else 14):
		_spray.append({
			"pos": Vector2(randf() * Zones.VIEW_W, y),
			"vel": Vector2(randf_range(-35.0, 35.0), randf_range(-130.0 if big else -60.0, -40.0)),
			"life": randf_range(0.4, 0.85 if big else 0.5),
		})
	if not big or game == null:
		return
	# The big wave throws its riders up onto the sand as it breaks.
	var landed := 0
	for sw in w["riders"]:
		if is_instance_valid(sw) and sw.drifting:
			sw.position.y = sw.shore_y - randf_range(1.0, 14.0)
			sw._settle()
			landed += 1
	game.shake(5.0 if bool(w["rogue"]) else 3.5, 0.25)
	game.sfx("dump", 0.6, -6.0)


func _tick_spray(delta: float) -> void:
	for w in waves:
		if float(w["y"]) < Zones.DEEP_TOP:          # only a breaking wave throws spray
			for i in (3 if bool(w["big"]) else 1):
				_spray.append({
					"pos": Vector2(randf() * Zones.VIEW_W, float(w["y"]) - 3.0),
					"vel": Vector2(randf_range(-25.0, 25.0), randf_range(-80.0, -30.0)),
					"life": randf_range(0.3, 0.6),
				})
	# Spray bursting around the worker while a wave carries them.
	if game != null and game.player != null and game.player.tumbling():
		var kp: float = game.player.knock_progress()
		if kp > 0.0 and kp < 1.0:
			for i in 3:
				_spray.append({
					"pos": game.player.position + Vector2(randf_range(-14.0, 14.0), randf_range(-4.0, 10.0)),
					"vel": Vector2(randf_range(-50.0, 50.0), randf_range(-90.0, -30.0)),
					"life": randf_range(0.3, 0.55),
				})
	var keep := []
	for p in _spray:
		p["life"] -= delta
		if p["life"] > 0.0:
			p["vel"].y += 170.0 * delta
			p["pos"] += p["vel"] * delta
			keep.append(p)
	_spray = keep


# ---- drawing ---------------------------------------------------------------

func _jag(x: float, k: float) -> float:
	return sin(x * 0.06 + _churn * 0.4 + k) * 3.0 + sin(x * 0.31 + _churn) * 1.6 \
		+ sin(x * 1.1 - _churn * 1.4 + k) * 1.1


func _hash(i: int, k: int) -> float:
	var h := (i * 73856093) ^ (k * 19349663) ^ (int(_churn * 2.0) * 83492791)
	return float(abs(h) % 1000) / 1000.0


func _draw() -> void:
	if not active:
		return
	for w in waves:
		_draw_wave(float(w["y"]), bool(w["big"]))
	for p in _spray:
		var a: float = clampf(float(p["life"]) / 0.6, 0.0, 1.0)
		draw_rect(Rect2(p["pos"], Vector2(3.0, 3.0)), Color(1, 1, 1, a))


func _draw_wave(y: float, big: bool) -> void:
	var W := Zones.VIEW_W
	# Small waves are thin and quiet; the big one is roughly twice the size with
	# a tall dark face, so there is never any doubt which wave is which.
	var size := 2.0 if big else 0.7
	var breaking := clampf((Zones.DEEP_TOP + 20.0 - y) / 40.0, 0.0, 1.0)
	var face := PackedVector2Array()
	var crest := PackedVector2Array()
	var x := 0.0
	while x <= W:
		var j := _jag(x, 0.0) * size
		crest.append(Vector2(x, y + j))
		face.append(Vector2(x, y + j + 7.0 * size))
		x += 5.0
	draw_polyline(face, Color(0.02, 0.10, 0.22, 0.6 if big else 0.35), 9.0 * size)
	draw_polyline(crest, Color(1, 1, 1, lerpf(0.5, 0.97, breaking)), lerpf(2.0, 5.0, breaking) * size)
	if breaking <= 0.0:
		return
	var rows := 6 if big else 2
	for k in range(1, rows + 1):
		var xi := 0
		while xi <= int(W):
			if _hash(xi, k) > (0.22 if big else 0.5):
				var p := Vector2(float(xi), y + float(k) * 6.0 * size + _jag(float(xi), float(k)))
				draw_line(p, p + Vector2(6.0 + _hash(xi + 5, k) * 10.0, 1.0),
					Color(1, 1, 1, (0.9 - float(k) * 0.12) * breaking), maxf(2.0, 4.0 - float(k) * 0.4) * size * 0.7)
			xi += 8
	for i in (90 if big else 18):
		var fx := _hash(i * 29, 7) * W
		var fy := y + 3.0 + _hash(i * 13, 5) * 34.0 * size
		draw_rect(Rect2(fx, fy, 3.0, 3.0), Color(1, 1, 1, 0.75 * breaking))
