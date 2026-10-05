class_name Veracruz
extends Node2D

# Veracruz's moments, on top of its steady norte:
#
#   GUST FRONT  A wall of blown sand sweeps across the beach downwind. As it
#               passes it slides the beached piles along with it, staggers the
#               tourists, and sends beach umbrellas tumbling across -- objects,
#               so they knock the worker down but do not spill the load.
#   LOST CARGO  A freighter off the port sheds a few crates. They float in and
#               wash up on the shoreline: heavy (5 slots of the load), never
#               rot, worth a good bonus at the skip.

var game
var active := false

var front_first := 25.0
var front_every := 50.0
var cargo_first := 45.0
var cargo_every := 70.0

const WARN_LEN := 3.0             # sand haze at the upwind edge first
const FRONT_SPEED := 150.0        # px/s across the screen
const FRONT_W := 46.0             # the band's width
const PILE_SLIDE := 30.0          # how far a pile is pushed downwind
const UMBRELLAS := [2, 3]
const UMBRELLA_SPEED := [95.0, 130.0]
const UMBRELLA_SIZE := Vector2(22, 16)
const CRATES := [2, 3]
const CRATE_SLOTS := 5
const CRATE_PAY_UNITS := 25.0     # paid as this many units of seaweed
const CRATE_DRIFT := 7.0          # px/s shoreward
const PICK_LEN := 0.8

var _next_front := 0.0
var _next_cargo := 0.0
var _warn := -1.0                 # seconds of warning left, < 0 none
var _front_x := -1.0e9            # the front's leading edge; off-screen when idle
var _dir := 1.0
var _pushed := {}                 # piles the current front has already moved
var umbrellas: Array = []         # {pos, v, spin, rot, col}
var crates: Array = []            # {pos, beached, pick, bob}
var _horn_t := -1.0
var _anim := 0.0


func configure(beach: Dictionary) -> void:
	var v: Dictionary = beach.get("veracruz", {})
	active = not v.is_empty()
	visible = active
	front_first = float(v.get("front_first", 25.0))
	front_every = float(v.get("front_every", 50.0))
	cargo_first = float(v.get("cargo_first", 45.0))
	cargo_every = float(v.get("cargo_every", 70.0))
	_next_front = front_first
	_next_cargo = cargo_first
	_warn = -1.0
	_front_x = -1.0e9
	umbrellas.clear()
	crates.clear()
	queue_redraw()


func status_text() -> String:
	if not active:
		return ""
	if _warn >= 0.0 or front_on():
		return "GUST FRONT -- WATCH FOR FLYING UMBRELLAS"
	if _horn_t >= 0.0:
		return "CARGO OVERBOARD -- CRATES WASHING IN"
	return ""


func front_on() -> bool:
	return _front_x >= 0.0 and _front_x < Zones.VIEW_W + FRONT_W


func tick(delta: float) -> void:
	if not active:
		return
	_anim += delta
	_tick_front(delta)
	_tick_umbrellas(delta)
	_tick_cargo(delta)
	queue_redraw()


# ---- the gust front ----------------------------------------------------------

func _tick_front(delta: float) -> void:
	if _warn >= 0.0:
		_warn -= delta
		if _warn < 0.0:
			_launch_front()
		return
	if front_on():
		var prev := _front_x
		_front_x += FRONT_SPEED * delta
		_sweep(prev, _front_x)
		return
	_next_front -= delta
	if _next_front <= 0.0:
		_next_front = front_every * randf_range(0.85, 1.15)
		_dir = game.wind.dir if game.wind != null and game.wind.dir != 0.0 else 1.0
		_warn = WARN_LEN


func _launch_front() -> void:
	_front_x = 0.0           # in "distance travelled" -- see _screen_x
	_pushed.clear()
	game.sfx("gust_front", 1.0, -2.0)
	game.shake(3.0, 0.3)
	for i in randi_range(UMBRELLAS[0], UMBRELLAS[1]):
		var y := randf_range(Zones.HOTEL_BOTTOM + 30.0, Zones.SHORE_Y - 16.0)
		var x := -20.0 - float(i) * 30.0 if _dir > 0.0 else Zones.VIEW_W + 20.0 + float(i) * 30.0
		umbrellas.append({
			"pos": Vector2(x, y),
			"v": randf_range(UMBRELLA_SPEED[0], UMBRELLA_SPEED[1]) * _dir,
			"rot": randf() * TAU,
			"bounce": randf() * TAU,
		})


func _screen_x(travelled: float) -> float:
	# The front moves downwind: left to right, or right to left after a turn.
	return travelled if _dir > 0.0 else Zones.VIEW_W - travelled


func _sweep(prev: float, now: float) -> void:
	# Everything the front's edge passed this frame gets shoved downwind.
	var a := _screen_x(prev)
	var b := _screen_x(now)
	var lo := minf(a, b)
	var hi := maxf(a, b)
	for c in game.world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if sw.drifting or sw.kelp or _pushed.has(sw.get_instance_id()):
				continue
			if sw.position.x >= lo and sw.position.x <= hi:
				_pushed[sw.get_instance_id()] = true
				var to := clampf(sw.position.x + PILE_SLIDE * _dir, 16.0, Zones.VIEW_W - 16.0)
				var tw := sw.create_tween()
				tw.tween_property(sw, "position:x", to, 0.4).set_ease(Tween.EASE_OUT)
		elif c is Tourist:
			var t := c as Tourist
			if t.position.x >= lo and t.position.x <= hi:
				t.position.x = clampf(t.position.x + 14.0 * _dir, 12.0, Zones.VIEW_W - 12.0)


func _tick_umbrellas(delta: float) -> void:
	var keep := []
	for u in umbrellas:
		var p: Vector2 = u["pos"]
		p.x += float(u["v"]) * delta
		u["bounce"] = float(u["bounce"]) + delta * 9.0
		u["rot"] = float(u["rot"]) + delta * 7.0 * signf(float(u["v"]))
		u["pos"] = p
		var hop := absf(sin(float(u["bounce"]))) * 8.0
		if game.touches_player(p - Vector2(0, hop), UMBRELLA_SIZE):
			game.knock_down(p)
		if p.x > -60.0 and p.x < Zones.VIEW_W + 60.0:
			keep.append(u)
	umbrellas = keep


# ---- lost cargo ---------------------------------------------------------------

func _tick_cargo(delta: float) -> void:
	if _horn_t >= 0.0:
		_horn_t -= delta
	_next_cargo -= delta
	if _next_cargo <= 0.0:
		_next_cargo = cargo_every * randf_range(0.85, 1.15)
		_spill()
	var keep := []
	for k in crates:
		var p: Vector2 = k["pos"]
		k["bob"] = float(k["bob"]) + delta
		if not bool(k["beached"]):
			p.y -= CRATE_DRIFT * float(game.wash_speed()) * delta
			if game.wind != null:
				p.x = clampf(p.x + float(game.wind.force()) * 0.15 * delta, 20.0, Zones.VIEW_W - 20.0)
			if p.y <= Zones.SHORE_Y:
				p.y = Zones.SHORE_Y - randf_range(2.0, 10.0)
				k["beached"] = true
			k["pos"] = p
		if _pick(k, delta):
			continue
		keep.append(k)
	crates = keep


func _spill() -> void:
	game.sfx("cargo_horn", 1.0, -6.0)
	_horn_t = 6.0
	var x0 := randf_range(70.0, Zones.VIEW_W - 70.0)
	for i in randi_range(CRATES[0], CRATES[1]):
		crates.append({
			"pos": Vector2(clampf(x0 + randf_range(-60.0, 60.0), 24.0, Zones.VIEW_W - 24.0),
				Zones.DEEP_TOP + randf_range(20.0, 60.0)),
			"beached": false,
			"pick": 0.0,
			"bob": randf() * TAU,
		})


func _pick(k: Dictionary, delta: float) -> bool:
	# Stand on a crate to haul it into the load -- if there is room for it.
	var pl = game.player
	var p: Vector2 = k["pos"]
	if pl.position.distance_to(p) > 20.0 or pl._stun > 0.0 or not pl.can_carry(CRATE_SLOTS):
		k["pick"] = 0.0
		return false
	k["pick"] = float(k["pick"]) + delta
	if float(k["pick"]) < PICK_LEN:
		return false
	var value: float = float(game.price_per_unit) * CRATE_PAY_UNITS
	pl.add_seaweed(1, value, CRATE_SLOTS)
	game.popup("+CRATE", p, Color(1.0, 0.85, 0.45), true)
	game.sfx("crate_pickup", 1.0, -2.0)
	return true


# ---- drawing --------------------------------------------------------------

func _draw() -> void:
	if not active:
		return
	var band_top := Zones.HOTEL_BOTTOM
	var band_h := Zones.SHALLOW_TOP + 30.0 - band_top
	if _warn >= 0.0:
		# A haze of sand building at the upwind edge.
		var a := (1.0 - _warn / WARN_LEN) * 0.35
		var x := 0.0 if _dir > 0.0 else Zones.VIEW_W - 30.0
		draw_rect(Rect2(x, band_top, 30.0, band_h), Color(0.85, 0.72, 0.48, a))
	if front_on():
		var sx := _screen_x(_front_x)
		var back := sx - FRONT_W * _dir
		var r := Rect2(minf(sx, back), band_top, FRONT_W, band_h)
		# A wall of blown sand, thick at the leading edge and thinning behind.
		for j in 6:
			var f := float(j) / 6.0
			var sl := Rect2(r.position.x + (f if _dir < 0.0 else 1.0 - f - 1.0 / 6.0) * FRONT_W, band_top, FRONT_W / 6.0 + 0.5, band_h)
			draw_rect(sl, Color(0.88, 0.76, 0.52, 0.72 * (1.0 - f * 0.8)))
		# streaks of blown sand through it
		for i in 40:
			var y := band_top + fmod(float(i) * 37.0 + _anim * 13.0, band_h)
			var x0 := r.position.x + fmod(float(i) * 23.0, FRONT_W)
			draw_line(Vector2(x0, y), Vector2(x0 + 18.0 * _dir, y + 1.0), Color(1.0, 0.94, 0.78, 0.85), 1.5)
	for u in umbrellas:
		_draw_umbrella(u)
	for k in crates:
		_draw_crate(k)


const UMBRELLA_ART := preload("res://assets/sprites/event_umbrella.png")
const CRATE_ART := preload("res://assets/sprites/event_crate.png")


func _draw_art(tex: Texture2D, p: Vector2, rot: float = 0.0) -> void:
	var sz := tex.get_size() * 2.0
	draw_set_transform(p, rot)
	draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false)
	draw_set_transform(Vector2.ZERO)


func _draw_umbrella(u: Dictionary) -> void:
	var hop := absf(sin(float(u["bounce"]))) * 8.0
	_draw_art(UMBRELLA_ART, u["pos"] - Vector2(0, hop), float(u["rot"]))


func _draw_crate(k: Dictionary) -> void:
	var p: Vector2 = k["pos"]
	if not bool(k["beached"]):
		p.y += sin(float(k["bob"]) * 2.2) * 1.5
	_draw_art(CRATE_ART, p, sin(float(k["bob"]) * 1.7) * 0.08 if not bool(k["beached"]) else 0.0)
	if not bool(k["beached"]):
		draw_arc(p + Vector2(0, 9), 12.0, 0.15, PI - 0.15, 10, Color(1, 1, 1, 0.5), 1.0)
	elif float(k["pick"]) > 0.0:
		var fp := clampf(float(k["pick"]) / PICK_LEN, 0.0, 1.0)
		draw_rect(Rect2(p + Vector2(-10, -15), Vector2(20.0 * fp, 2)), Color(1.0, 0.85, 0.45))
