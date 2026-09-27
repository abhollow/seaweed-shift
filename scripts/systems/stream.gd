class_name Stream
extends Node2D

# Puerto Morelos: a freshwater stream winds from the mangroves across the beach
# to the sea, and the skip is on the far (right) side of it.
#
#   CURRENT   Wading through the stream slows the worker and pushes them
#             downstream toward the sea. A tractor is pushed half as hard.
#   TOURISTS  Tourists wading across are carried downstream too.
#   BRIDGE    Optional (bridge_frac). Puerto Morelos had one and it was removed
#             after playtest -- nobody needed it.
#   MOUTH     Seaweed lying in the stream floats down to its mouth and piles up
#             there, so the mouth becomes a hotspot that grows if ignored.
#   FLOOD     The signature event: rain up in the mangroves flushes a batch of
#             debris down the stream; the flow flecks run quicker while it lasts.
#
# The path is traced from the art (points in world px, upstream first).

var game
var active := false
var points := PackedVector2Array()
var half_w := 9.0
var current := 60.0
var slow := 0.6
var bridge_at := 0.0              # arc length along the stream
var bridge_half := 9.0
var float_speed := 28.0           # how fast seaweed floats downstream
var flood_first := 40.0
var flood_every := 60.0
var flood_len := 12.0
var flood_debris := 5

var _lengths := PackedFloat32Array()     # cumulative arc length at each point
var _total := 0.0
var _flood_t := -1.0
var _next_flood := 0.0
var _debris_left := 0
var _debris_t := 0.0
var _flecks: Array = []
var _anim := 0.0

const VEHICLE_PUSH := 0.5


func configure(beach: Dictionary) -> void:
	var st: Dictionary = beach.get("stream", {})
	active = not st.is_empty()
	visible = active
	if not active:
		return
	points = PackedVector2Array()
	for q in st.get("points", []):
		points.append(Vector2(float(q[0]), float(q[1])))
	half_w = float(st.get("half_w", 9.0))
	current = float(st.get("current", 60.0))
	slow = float(st.get("slow", 0.6))
	bridge_half = float(st.get("bridge_half", 9.0))
	float_speed = float(st.get("float_speed", 28.0))
	flood_first = float(st.get("flood_first", 40.0))
	flood_every = float(st.get("flood_every", 60.0))
	flood_len = float(st.get("flood_len", 12.0))
	flood_debris = int(st.get("flood_debris", 5))
	_lengths = PackedFloat32Array([0.0])
	for i in range(1, points.size()):
		_lengths.append(_lengths[i - 1] + points[i - 1].distance_to(points[i]))
	_total = _lengths[_lengths.size() - 1]
	# No bridge unless the level asks for one.
	bridge_at = _total * float(st["bridge_frac"]) if st.has("bridge_frac") else -1.0
	_flood_t = -1.0
	_next_flood = flood_first
	_flecks.clear()
	for i in 26:
		_flecks.append(randf() * _total)


# ---- geometry ---------------------------------------------------------------

func closest(p: Vector2) -> Dictionary:
	# The nearest point on the stream: its distance, arc length and the
	# downstream direction there.
	var best := {"d": INF, "s": 0.0, "dir": Vector2.DOWN, "pt": p}
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_to(q)
		if d < float(best["d"]):
			best = {"d": d, "s": _lengths[i] + ab.length() * t, "dir": ab.normalized(), "pt": q}
	return best


func point_at(s: float) -> Dictionary:
	s = clampf(s, 0.0, _total)
	for i in range(points.size() - 1):
		if s <= _lengths[i + 1] or i == points.size() - 2:
			var seg := _lengths[i + 1] - _lengths[i]
			var t := (s - _lengths[i]) / maxf(seg, 0.001)
			var ab := points[i + 1] - points[i]
			return {"pt": points[i] + ab * clampf(t, 0.0, 1.0), "dir": ab.normalized()}
	return {"pt": points[points.size() - 1], "dir": Vector2.DOWN}


func width() -> float:
	# The flood no longer swells the stream: playtest found the debris coming
	# down it was event enough, and a wider stream you cannot see is a trap.
	return half_w


func has_bridge() -> bool:
	return active and bridge_at >= 0.0


func on_bridge(p: Vector2) -> bool:
	if not has_bridge():
		return false
	var c := closest(p)
	return absf(float(c["s"]) - bridge_at) <= bridge_half and float(c["d"]) <= half_w + 8.0


func in_stream(p: Vector2) -> bool:
	if not active:
		return false
	return float(closest(p)["d"]) <= width() and not on_bridge(p)


# ---- effects on the worker ----------------------------------------------------

func slow_at(p: Vector2) -> float:
	return slow if in_stream(p) else 1.0


func push_at(p: Vector2, on_vehicle: bool) -> Vector2:
	if not in_stream(p):
		return Vector2.ZERO
	var c := closest(p)
	var f := current * (VEHICLE_PUSH if on_vehicle else 1.0)
	return (c["dir"] as Vector2) * f


# ---- the flood ----------------------------------------------------------------

func flooding() -> bool:
	return active and _flood_t >= 0.0


func start_flood() -> void:
	_flood_t = 0.0
	_debris_left = flood_debris
	_debris_t = 0.0
	_next_flood = flood_every * randf_range(0.85, 1.15)


func status_text() -> String:
	return "FLASH FLOOD -- DEBRIS COMING DOWN THE STREAM" if flooding() else ""


# ---- loop ---------------------------------------------------------------------

func tick(delta: float) -> void:
	if not active:
		return
	_anim = fposmod(_anim + delta, TAU * 20.0)
	if flooding():
		_flood_t += delta
		# Debris enters at the top of the stream, a clump at a time.
		if _debris_left > 0:
			_debris_t -= delta
			if _debris_t <= 0.0 and game != null:
				_debris_t = 0.6
				_debris_left -= 1
				var top: Vector2 = point_at(6.0)["pt"]
				game.spawner._add_seaweed(top, randi_range(1, 2), false, false)
		if _flood_t >= flood_len:
			_flood_t = -1.0
	else:
		_next_flood -= delta
		if _next_flood <= 0.0:
			start_flood()
	_float_seaweed(delta)
	var speed := (60.0 if flooding() else 32.0)
	for i in _flecks.size():
		_flecks[i] = fposmod(float(_flecks[i]) + speed * delta, _total)
	queue_redraw()


func _float_seaweed(delta: float) -> void:
	# Seaweed lying in the stream is carried down to the mouth and piles up
	# there -- merging into whatever is already at the mouth.
	if game == null:
		return
	var mouth: Vector2 = points[points.size() - 1] + Vector2(-16.0, -8.0)
	for c in game.world.get_children():
		if not (c is Seaweed):
			continue
		var sw := c as Seaweed
		if sw.drifting or sw.kelp or sw.is_queued_for_deletion():
			continue
		var cl := closest(sw.position)
		if float(cl["d"]) > width() + 2.0:
			continue
		var s: float = float(cl["s"]) + float_speed * (2.0 if flooding() else 1.0) * delta
		if s >= _total - 4.0:
			sw.position = mouth + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0))
			var host = game.find_pile_near(sw.global_position, sw)
			if host != null:
				host.absorb(sw.units)
				sw.queue_free()
		else:
			sw.position = point_at(s)["pt"]


# ---- drawing ------------------------------------------------------------------

func _draw() -> void:
	if not active:
		return
	# Flecks showing which way the water runs -- quicker during a flood, which
	# is the only sign of it besides the debris. (The first pass also turned
	# the stream brown; playtest found that unnecessary.)
	for s in _flecks:
		var q: Dictionary = point_at(float(s))
		var p: Vector2 = q["pt"]
		var d: Vector2 = q["dir"]
		var side := Vector2(-d.y, d.x) * sin(float(s) * 0.7) * width() * 0.5
		draw_line(p + side, p + side + d * 5.0, Color(1, 1, 1, 0.4), 1.5)
	if has_bridge():
		_draw_bridge()


func _draw_bridge() -> void:
	# Wooden planks across the stream, square to its flow.
	var q: Dictionary = point_at(bridge_at)
	var p: Vector2 = q["pt"]
	var d: Vector2 = q["dir"]
	var across := Vector2(-d.y, d.x)
	var reach := half_w + 8.0
	var wood := Color(0.55, 0.36, 0.20)
	var dark := Color(0.30, 0.18, 0.09)
	for k in range(-2, 3):
		var o := p + d * float(k) * 4.0
		draw_line(o - across * reach, o + across * reach, dark, 4.0)
		draw_line(o - across * reach, o + across * reach, wood, 3.0)
	for side in [-1.0, 1.0]:
		draw_line(p + across * reach * side - d * 10.0, p + across * reach * side + d * 10.0, dark, 2.0)
