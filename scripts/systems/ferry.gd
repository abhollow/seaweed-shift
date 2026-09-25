class_name Ferry
extends Node2D

# The Cozumel ferry on Playa del Carmen.
#
# Its horn sounds from beyond the edge of the screen; a couple of seconds later
# it appears and crosses the deep water. Behind it trails a V-shaped wake, and
# the shoreward arm of that V IS the wave: it rises toward the beach at a slant,
# moves with the boat, and where it meets the shore it sweeps along the beach in
# the direction the boat travelled -- carrying HALF of the seaweed already
# drifting in the water up onto the sand as it goes.
#
# Geometry, and why the ferry is fast: at a ~20 degree slant, the arm only
# reaches the beach about 520px behind the stern -- wider than the screen. So
# the wave hits the beach AFTER the boat has passed, exactly as a real ferry
# wake does. At 90 px/s the first of it lands ~9s after the horn and sweeps the
# whole beach in ~4s; at 45 px/s it would have been nearly 19s.
#
# It carries existing seaweed rather than creating any: an earlier version
# dropped a fresh line along the whole waterline, which on foot was simply more
# than could be cleared. A wake over empty water does nothing.
#
# Uses assets/sprites/ferry.png if present (drawn at 2x, bow facing RIGHT);
# otherwise a placeholder boat drawn in code.

const TEXTURE_PATH := "res://assets/sprites/ferry.png"
const STERN := 50.0          # px from the ferry's centre to its stern
const LEAD := 270.0          # how far beyond the screen edge it starts (the horn comes first)

var game
var enabled := false
var first := 35.0
var every := 55.0
var speed := 90.0
var angle_deg := 20.0
var lane_y := 565.0
var share := 0.5                    # fraction carried THIS shift -- see share_for()
var _shares: Array = []

var running := false
var _x := 0.0
var _dir := -1.0
var _next := 0.0
var _bob := 0.0
var _churn := 0.0
var _tan := 0.364
var _tex: Texture2D
var _riders: Array = []
var _spray: Array = []
var _hit_once := false
var _sfx_cool := 0.0


func configure(beach: Dictionary) -> void:
	var f: Dictionary = beach.get("ferry", {})
	enabled = not f.is_empty()
	visible = enabled
	first = float(f.get("first", 35.0))
	every = float(f.get("every", 55.0))
	speed = float(f.get("speed", 90.0))
	angle_deg = float(f.get("angle", 20.0))
	lane_y = float(f.get("lane_y", 565.0))
	var sh = f.get("share", 0.5)
	_shares = sh if typeof(sh) == TYPE_ARRAY else [float(sh)]
	share = share_for(0)
	_tan = tan(deg_to_rad(angle_deg))
	running = false
	_riders.clear()
	_spray.clear()
	_next = first
	_tex = load(TEXTURE_PATH) if ResourceLoader.exists(TEXTURE_PATH) else null
	queue_redraw()


func share_for(shift_index: int) -> float:
	# Scales with the shift: light while the player is on foot, heavy once they
	# have the gear for it. The last entry covers anything beyond the list.
	if _shares.is_empty():
		return 0.5
	return float(_shares[clampi(shift_index, 0, _shares.size() - 1)])


func inbound() -> bool:
	# From the horn until the wave has finished sweeping the beach.
	return enabled and running


# ---- geometry --------------------------------------------------------------

func stern() -> Vector2:
	return Vector2(_x - _dir * STERN, lane_y + 6.0)


func crest_y(x: float) -> float:
	# Height of the shoreward wave at column x: it rises toward the beach the
	# further behind the boat you look. INF ahead of the boat -- no wave yet.
	var s := stern()
	var behind := (x - s.x) * -_dir
	if behind < 0.0:
		return INF
	return s.y - behind * _tan


func shore_contact_x() -> float:
	# Where the arm meets the waterline.
	var s := stern()
	return s.x - _dir * ((s.y - Zones.SHALLOW_TOP) / _tan)


# ---- loop ------------------------------------------------------------------

func tick(delta: float) -> void:
	if not enabled:
		return
	_bob = fposmod(_bob + delta * 2.4, TAU)
	_churn = fposmod(_churn + delta * 7.0, TAU * 50.0)
	_sfx_cool = maxf(0.0, _sfx_cool - delta)
	if running:
		_x += _dir * speed * delta
		_carry_riders()
		var cx := shore_contact_x()
		if cx >= 0.0 and cx <= Zones.VIEW_W:
			_break_at(cx, delta)
			if not _hit_once:
				_hit_once = true
				if game != null:
					game.shake(3.0, 0.25)
		# Done once the contact point has swept past the far edge of the beach.
		if (_dir < 0.0 and cx < -20.0) or (_dir > 0.0 and cx > Zones.VIEW_W + 20.0):
			running = false
			_riders.clear()
	else:
		_next -= delta
		if _next <= 0.0:
			depart()
	_tick_spray(delta)
	queue_redraw()


func depart() -> void:
	running = true
	_hit_once = false
	_dir = -1.0 if randf() < 0.5 else 1.0
	_x = Zones.VIEW_W + LEAD if _dir < 0.0 else -LEAD
	_next = every * randf_range(0.9, 1.1)
	_pick_riders()
	if game != null:
		game.sfx("horn", randf_range(0.95, 1.03), -3.0)


func _pick_riders() -> void:
	# A share of the seaweed drifting between the ferry's lane and the beach --
	# how much depends on the shift. Anything behind the lane is out of the path.
	_riders.clear()
	if game == null:
		return
	share = share_for(game.level_index)
	var pool := []
	for c in game.world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if sw.drifting and not sw.kelp and sw.position.y < lane_y:
				pool.append(sw)
	pool.shuffle()
	var n := int(round(float(pool.size()) * share))
	for i in n:
		_riders.append(pool[i])


func _carry_riders() -> void:
	# Once the wave reaches a rider it is pushed up the beach just ahead of the
	# crest -- far faster than it would drift -- and thrown onto the sand when
	# the crest reaches the waterline at that point.
	var keep := []
	for sw in _riders:
		if not is_instance_valid(sw) or not sw.drifting:
			continue
		var cy := crest_y(sw.position.x)
		if cy == INF:
			keep.append(sw)
			continue
		if cy <= Zones.SHALLOW_TOP:
			sw.position.y = sw.shore_y - randf_range(1.0, 14.0)
			sw._settle()
			if game != null and _sfx_cool <= 0.0:
				game.sfx("dump", 0.7, -9.0)
				_sfx_cool = 0.25
			continue
		if sw.position.y > cy - 3.0:
			sw.position.y = cy - 3.0
		keep.append(sw)
	_riders = keep


func _break_at(x: float, delta: float) -> void:
	# The wave breaking where it meets the beach: a steady plume of spray that
	# travels along the shore with the contact point.
	var n := int(60.0 * delta) + (1 if randf() < fposmod(60.0 * delta, 1.0) else 0)
	for i in n:
		_spray.append({
			"pos": Vector2(x + randf_range(-10.0, 10.0), Zones.SHALLOW_TOP - 2.0),
			"vel": Vector2(randf_range(-30.0, 30.0), randf_range(-110.0, -45.0)),
			"life": randf_range(0.4, 0.8),
		})


func _tick_spray(delta: float) -> void:
	# Spray is also thrown off the whole visible crest while the wave is running.
	if running:
		var n := int(90.0 * delta) + (1 if randf() < fposmod(90.0 * delta, 1.0) else 0)
		for i in n:
			var x := randf() * Zones.VIEW_W
			var cy := crest_y(x)
			if cy != INF and cy > Zones.SHALLOW_TOP and cy < Zones.VIEW_H:
				_spray.append({
					"pos": Vector2(x, cy - 2.0),
					"vel": Vector2(randf_range(-25.0, 25.0), randf_range(-70.0, -25.0)),
					"life": randf_range(0.3, 0.6),
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

func _jag(t: float, k: float) -> float:
	# Chop along the crest: a slow roll plus fast, uneven breakup.
	return sin(t * 0.09 + _bob * 3.0 + k) * 2.5 \
		+ sin(t * 0.37 + _churn) * 1.8 + sin(t * 1.3 - _churn * 1.7 + k) * 1.2


func _foam_hash(i: int, k: int) -> float:
	var h := (i * 73856093) ^ (k * 19349663) ^ (int(_churn * 2.0) * 83492791)
	return float(abs(h) % 1000) / 1000.0


func _draw() -> void:
	if not enabled or not running:
		_draw_spray()
		return
	var s := stern()
	var a := deg_to_rad(angle_deg)
	var back := -_dir
	# Shoreward arm: from the stern, back and up toward the beach, ending at
	# the waterline. Normal n points BEHIND the crest (away from the beach).
	var u := Vector2(back * cos(a), -sin(a))
	var n := Vector2(back * sin(a), cos(a))
	var shore_len := (s.y - Zones.SHALLOW_TOP) / sin(a)
	_draw_arm(s, u, n, shore_len, 1.0)
	# Seaward arm: the other half of the V, down toward the bottom edge.
	var u2 := Vector2(back * cos(a), sin(a))
	var n2 := Vector2(back * sin(a), -cos(a))
	var sea_len := (Zones.VIEW_H + 20.0 - s.y) / sin(a)
	_draw_arm(s, u2, n2, sea_len, 0.55)
	# Churned water right behind the hulls.
	for i in 10:
		var f := float(i) / 9.0
		var c := s + Vector2(back * (4.0 + f * 40.0), sin(f * 11.0 + _churn) * 3.0)
		draw_circle(c, 6.0 - f * 3.5, Color(1, 1, 1, 0.6 - f * 0.45))
	_draw_spray()
	_draw_boat(Vector2(_x, lane_y + sin(_bob) * 1.5))


func _draw_arm(origin: Vector2, u: Vector2, n: Vector2, length: float, strength: float) -> void:
	var crest := PackedVector2Array()
	var shadow := PackedVector2Array()
	var t := 0.0
	while t <= length:
		var j := _jag(t, 0.0)
		crest.append(origin + u * t + n * j)
		shadow.append(origin + u * t + n * (j + 5.0))
		t += 5.0
	if crest.size() < 2:
		return
	# A dark shadow behind the crest: on bright turquoise a white line alone
	# nearly disappears, so the shadow is what makes the wave readable.
	draw_polyline(shadow, Color(0.02, 0.16, 0.20, 0.5 * strength), 5.0)
	draw_polyline(crest, Color(1, 1, 1, 0.96 * strength), 4.0)
	# Broken foam trailing behind the crest, re-rolling several times a second.
	for k in range(1, 6):
		var ti := 0
		while float(ti) <= length:
			if _foam_hash(ti, k) > 0.3:
				var p := origin + u * float(ti) + n * (float(k) * 7.0 + _jag(float(ti), float(k)))
				var dash := 5.0 + _foam_hash(ti + 7, k) * 9.0
				draw_line(p, p + u * dash, Color(1, 1, 1, (0.9 - float(k) * 0.13) * strength),
					maxf(2.0, 4.0 - float(k) * 0.5))
			ti += 9
	for i in 50:
		var along := _foam_hash(i * 31, 9) * length
		var off := 4.0 + _foam_hash(i * 17, 11) * 38.0
		var p2 := origin + u * along + n * off
		draw_rect(Rect2(p2, Vector2(3.0, 3.0)), Color(1, 1, 1, 0.75 * strength))


func _draw_spray() -> void:
	for p in _spray:
		var al: float = clampf(float(p["life"]) / 0.6, 0.0, 1.0)
		draw_rect(Rect2(p["pos"], Vector2(3.0, 3.0)), Color(1, 1, 1, al))


func _draw_boat(p: Vector2) -> void:
	if _tex != null:
		var sz := _tex.get_size() * 2.0
		draw_set_transform(p, 0.0, Vector2(_dir, 1.0))
		draw_texture_rect(_tex, Rect2(-sz * 0.5, sz), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	# Placeholder: a blocky white ferry facing _dir.
	var d := _dir
	var hull := Color(0.96, 0.96, 0.95)
	var glass := Color(0.12, 0.18, 0.30)
	draw_rect(Rect2(p.x - 48.0, p.y - 6.0, 96.0, 16.0), hull)
	draw_rect(Rect2(p.x - 46.0, p.y - 1.0, 92.0, 3.0), Color(0.13, 0.43, 0.78))
	draw_rect(Rect2(p.x - 30.0, p.y - 18.0, 58.0, 12.0), hull)
	var wx := -26.0
	while wx < 24.0:
		draw_rect(Rect2(p.x + wx, p.y - 15.0, 4.0, 4.0), glass)
		wx += 7.0
	draw_rect(Rect2(p.x + d * 6.0 - 10.0, p.y - 26.0, 20.0, 8.0), hull)
