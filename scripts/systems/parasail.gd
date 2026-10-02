class_name Parasail
extends Node2D

# Purely for laughs -- no effect on play (Cancun, Puerto Morelos, Tulum). Once a
# level, in one chosen shift: a speedboat tows a parasailing tourist across the
# sea. Halfway over, the harness gives way and the tourist tumbles out of the
# sky into the water with a splash, and is gone. The boat and the empty chute
# carry on and leave.

enum State { WAITING, TOWING, GONE }

var game
var active := false
var state := State.GONE

var shift := 0
var at_min := 40.0
var at_max := 90.0

const BOAT_SPEED := 100.0         # px/s -- across in under four seconds
const HEIGHT := 150.0             # how far above the boat the chute flies
const ROPE_BACK := 70.0           # how far behind the boat it trails
const GRAVITY := 300.0
const SPIN := 9.0                 # rad/s, tumbling
const SPLASH_LEN := 0.9
const HANG := 34.0                # parasailer's centre, below the canopy's

var _wait := 0.0
var _dir := 1.0                   # +1 left to right, -1 right to left
var _boat := Vector2.ZERO
var _flying := true               # tourist still in the harness
var _flyer := Vector2.ZERO        # tourist position once they let go
var _flyer_v := Vector2.ZERO
var _flyer_rot := 0.0
var _sea_y := 0.0                 # where they hit the water
var _splash_t := -1.0             # seconds since the splash, < 0 none yet
var _splash_at := Vector2.ZERO
var _chute_lift := 0.0            # the chute bobs up when the weight goes
var _anim := 0.0

# Art, when it exists. The parasailer is an ordinary tourist sprite, tinted
# like the crowd, so they match the people on the beach.
const BOAT_ART := "res://assets/sprites/parasail_boat.png"
const CANOPY_ART := "res://assets/sprites/parasail_canopy.png"
var _boat_spr: Sprite2D
var _canopy_spr: Sprite2D
var _flyer_spr: Sprite2D


func _ready() -> void:
	_boat_spr = _sprite(BOAT_ART)
	_canopy_spr = _sprite(CANOPY_ART)
	var t: Tourist = load("res://scenes/tourist.tscn").instantiate()
	var frames: Array = t.tex_sober_m
	t.free()
	_flyer_spr = Sprite2D.new()
	_flyer_spr.texture = frames[0] if not frames.is_empty() else null
	# Half the size of the tourists on the beach: high up, and the canopy
	# reads as the big thing in the sky.
	_flyer_spr.scale = Vector2(1, 1)
	add_child(_flyer_spr)
	_hide_all()


func _sprite(path: String) -> Sprite2D:
	var s := Sprite2D.new()
	if ResourceLoader.exists(path):
		s.texture = load(path)
		s.scale = Vector2(2, 2)
	add_child(s)
	return s


func _hide_all() -> void:
	for s in [_boat_spr, _canopy_spr, _flyer_spr]:
		if s != null:
			s.visible = false


func configure(beach: Dictionary, shift_index: int) -> void:
	var c: Dictionary = beach.get("parasail", {})
	shift = int(c.get("shift", 0))
	at_min = float(c.get("at", [40.0, 90.0])[0])
	at_max = float(c.get("at", [40.0, 90.0])[1])
	active = not c.is_empty() and shift_index == shift and not Zones.RADIAL
	state = State.WAITING if active else State.GONE
	_wait = randf_range(at_min, at_max)
	_hide_all()
	queue_redraw()


func start() -> void:
	_dir = 1.0 if randf() < 0.5 else -1.0
	# Out in the deep water, entering from off-screen with the chute trailing.
	# Just past the buoys: lower and it runs under the HUD strip.
	var lane := Zones.DEEP_TOP + 14.0
	_boat = Vector2(-60.0 if _dir > 0.0 else Zones.VIEW_W + 60.0, lane)
	_flying = true
	_splash_t = -1.0
	_chute_lift = 0.0
	if _flyer_spr != null and game != null:
		_flyer_spr.material = Tourist._tint_for(game.spawner.clothes_hue())
	state = State.TOWING


# Rough going: the boat heaves on a choppy sea, and the chute rides gusty air --
# each a mix of two waves at odd frequencies, so the motion never settles into
# an obvious loop.
func boat_pos() -> Vector2:
	return _boat + Vector2(0, sin(_anim * 5.3) * 2.2 + sin(_anim * 8.9) * 1.2)


func chute_pos() -> Vector2:
	var gust := Vector2(sin(_anim * 1.9) * 1.5, sin(_anim * 2.4) * 6.0 + sin(_anim * 6.1) * 3.0)
	return _boat + Vector2(-_dir * ROPE_BACK, -HEIGHT - _chute_lift) + gust


func tick(delta: float) -> void:
	if not active:
		return
	_anim += delta
	match state:
		State.WAITING:
			_wait -= delta
			if _wait <= 0.0:
				start()
		State.TOWING:
			_tow(delta)
	_place_sprites()
	queue_redraw()


func _tow(delta: float) -> void:
	_boat.x += _dir * BOAT_SPEED * delta
	var chute := chute_pos()
	if _flying:
		# Halfway across, the harness gives way.
		if (_dir > 0.0 and chute.x >= Zones.VIEW_W * 0.5) or (_dir < 0.0 and chute.x <= Zones.VIEW_W * 0.5):
			_let_go(chute)
	elif _splash_t < 0.0:
		_flyer_v.y += GRAVITY * delta
		_flyer += _flyer_v * delta
		_flyer_rot += SPIN * delta * _dir
		if _flyer.y >= _sea_y:
			_splash_t = 0.0
			_splash_at = Vector2(_flyer.x, _sea_y)
			if game != null:
				game.sfx("big_splash", 1.0, -3.0)
	else:
		_splash_t += delta
	# The weight gone, the chute floats up a little.
	if not _flying:
		_chute_lift = minf(_chute_lift + 18.0 * delta, 22.0)
	# Gone once boat, chute and splash are all done with.
	var off := (_dir > 0.0 and chute.x > Zones.VIEW_W + 60.0) or (_dir < 0.0 and chute.x < -60.0)
	if off and (_splash_t > SPLASH_LEN or _flying):
		state = State.GONE
		_hide_all()


func _let_go(chute: Vector2) -> void:
	_flying = false
	_flyer = chute + Vector2(0, HANG)
	# Carried on by the tow for a moment, a little hop, then down.
	_flyer_v = Vector2(_dir * BOAT_SPEED * 0.9, -40.0)
	_flyer_rot = 0.0
	_sea_y = _flyer.y + 95.0
	if game != null:
		game.sfx("yell_%d" % (1 + randi() % 4), randf_range(1.1, 1.3), -2.0)


func _place_sprites() -> void:
	var towing := state == State.TOWING
	var chute := chute_pos()
	if _boat_spr.texture != null:
		_boat_spr.visible = towing
		_boat_spr.position = boat_pos()
		# Pitching over the chop: nose up, nose down.
		_boat_spr.rotation = sin(_anim * 4.3) * 0.09 * _dir
		_boat_spr.flip_h = _dir < 0.0
	if _canopy_spr.texture != null:
		_canopy_spr.visible = towing
		_canopy_spr.position = chute
		# Swings a little on the wind, more once it is empty.
		_canopy_spr.rotation = sin(_anim * (1.6 if _flying else 4.0)) * (0.05 if _flying else 0.14)
	_flyer_spr.visible = towing and (_flying or _splash_t < 0.0) and _flyer_spr.texture != null
	if _flying:
		_flyer_spr.position = chute + Vector2(0, HANG + sin(_anim * 2.0) * 1.5)
		_flyer_spr.rotation = sin(_anim * 1.6) * 0.12
	else:
		_flyer_spr.position = _flyer
		_flyer_spr.rotation = _flyer_rot


# ---- drawing: rope, harness, wake, splash -- and placeholders until art ----

func _draw() -> void:
	if state != State.TOWING:
		return
	var chute := chute_pos()
	# The tow line leaves from the top of the mast at the stern.
	var stern := boat_pos() + (Vector2(-_dir * 21.0, -20.0) if _boat_spr.texture != null else Vector2(-_dir * 18.0, -4.0))
	var harness := chute + Vector2(0, HANG - 10.0)
	var rope := Color(0.95, 0.95, 0.9, 0.85)
	# The tow line, sagging a little.
	var mid := (stern + harness) * 0.5 + Vector2(0, 10)
	draw_polyline(PackedVector2Array([stern, mid, harness]), rope, 1.0)
	# Rigging from the canopy down to the harness ring.
	for s in [-1.0, 1.0]:
		# From where the art's own lines end, or the placeholder dome's rim.
		var from := chute + (Vector2(s * 20.0, 20.0) if _canopy_spr.texture != null else Vector2(s * 28.0, -2.0))
		draw_line(from, harness, rope, 1.0)
	_draw_wake()
	if _canopy_spr.texture == null:
		_draw_canopy(chute)
	if _boat_spr.texture == null:
		_draw_boat()
	if _splash_t >= 0.0 and _splash_t <= SPLASH_LEN:
		_draw_splash(clampf(_splash_t / SPLASH_LEN, 0.0, 1.0))


func _draw_wake() -> void:
	var foam := Color(1, 1, 1, 0.7)
	for i in 6:
		var back := boat_pos() + Vector2(-_dir * (22.0 + i * 12.0), 4.0)
		var spread := 3.0 + i * 3.0
		draw_line(back + Vector2(0, -spread), back + Vector2(-_dir * 8.0, -spread - 2), Color(foam, 0.7 - i * 0.1), 2.0)
		draw_line(back + Vector2(0, spread), back + Vector2(-_dir * 8.0, spread + 2), Color(foam, 0.7 - i * 0.1), 2.0)


func _draw_boat() -> void:
	var b := boat_pos()
	var d := _dir
	var hull := PackedVector2Array([b + Vector2(-20 * d, -6), b + Vector2(16 * d, -6),
		b + Vector2(26 * d, 0), b + Vector2(16 * d, 6), b + Vector2(-20 * d, 6)])
	draw_colored_polygon(hull, Color(0.96, 0.96, 0.98))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.2, 0.3, 0.45), 1.0)
	draw_rect(Rect2(b + Vector2(-8, -5), Vector2(14, 10)), Color(0.15, 0.45, 0.85))


func _draw_canopy(c: Vector2) -> void:
	var cols := [Color(0.95, 0.25, 0.2), Color(1.0, 0.85, 0.2), Color(0.2, 0.55, 0.95), Color(0.3, 0.85, 0.4)]
	for i in 8:
		var a0 := PI + PI * float(i) / 8.0
		var a1 := PI + PI * float(i + 1) / 8.0
		var pts := PackedVector2Array([c])
		for k in 5:
			var a := lerpf(a0, a1, float(k) / 4.0)
			pts.append(c + Vector2(cos(a) * 30.0, sin(a) * 18.0))
		draw_colored_polygon(pts, cols[i % cols.size()])


func _draw_splash(p: float) -> void:
	# A ring opening on the water and a burst of drops thrown up and falling.
	var a := 1.0 - p
	var c := _splash_at
	draw_arc(c, 6.0 + p * 18.0, 0.0, TAU, 20, Color(1, 1, 1, 0.8 * a), 2.0)
	draw_arc(c, 3.0 + p * 10.0, 0.0, TAU, 14, Color(0.8, 0.95, 1.0, 0.7 * a), 1.5)
	for i in 8:
		var ang := -PI * (0.15 + 0.7 * float(i) / 7.0)
		var v := Vector2(cos(ang), sin(ang)) * (60.0 + 25.0 * float(i % 3))
		var t := p * SPLASH_LEN
		var q := c + v * t + Vector2(0, 0.5 * GRAVITY * t * t)
		if q.y <= c.y + 2.0:
			draw_circle(q, 1.6, Color(1, 1, 1, 0.9 * a))
