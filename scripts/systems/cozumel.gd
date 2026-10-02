class_name Cozumel
extends Node2D

# Cozumel's night, on top of the darkness and the moon:
#
#   CRUISE SHIP      Once a shift: a horn, then a lit-up ship crosses far out.
#                    When it is halfway over, its passengers pour onto the beach,
#                    phones glowing -- a crowd in the dark.
#   BIOLUMINESCENCE  Now and then the sea glows for a few seconds and every
#                    drifting clump lights up -- a moment to see what is coming.
#   NIGHT DIVERS     Pairs of divers surface in the shallows with torches and
#                    bob there a while. People: bump one and the load is dropped.
#
# Drawn above the night's darkness, so the lights read as lights.

var game
var active := false

var cruise_at := [40.0, 80.0]
var cruise_crowd := 8
var glow_first := 25.0
var glow_every := 60.0
var glow_len := 7.0
var divers_first := 30.0
var divers_every := 40.0
var divers_len := 12.0

const SHIP_ART := preload("res://assets/sprites/event_ship.png")
const DIVER_ART := preload("res://assets/sprites/event_diver.png")
const SHIP_SPEED := 28.0
const SHIP_LEN := 120.0
const DIVER_SIZE := Vector2(14, 12)
const DIVER_LIGHT := 26.0
const GLOW_LIGHT := 15.0

var _cruise_wait := 0.0
var _cruise_done := false
var _ship_x := -1.0e9
var _ship_dir := 1.0
var _crowd_left := 0
var _crowd_t := 0.0
var _glow_next := 0.0
var _glow_t := -1.0
var _divers_next := 0.0
var divers: Array = []            # {pos, t, phase}
var _anim := 0.0


func configure(beach: Dictionary) -> void:
	var c: Dictionary = beach.get("cozumel", {})
	active = not c.is_empty()
	visible = active
	cruise_at = c.get("cruise_at", [40.0, 80.0])
	cruise_crowd = int(c.get("cruise_crowd", 8))
	glow_first = float(c.get("glow_first", 25.0))
	glow_every = float(c.get("glow_every", 60.0))
	divers_first = float(c.get("divers_first", 30.0))
	divers_every = float(c.get("divers_every", 40.0))
	# Every shift: the ship comes again, the timers start over.
	_cruise_wait = randf_range(float(cruise_at[0]), float(cruise_at[1]))
	_cruise_done = false
	_ship_x = -1.0e9
	_crowd_left = 0
	_glow_next = glow_first
	_glow_t = -1.0
	_divers_next = divers_first
	divers.clear()
	queue_redraw()


func ship_on() -> bool:
	return _ship_x > -SHIP_LEN and _ship_x < Zones.VIEW_W + SHIP_LEN


func glowing() -> bool:
	return _glow_t >= 0.0


func status_text() -> String:
	if not active:
		return ""
	if _crowd_left > 0:
		return "CRUISE PASSENGERS COMING ASHORE"
	if ship_on():
		return "A CRUISE SHIP IS PASSING"
	if glowing():
		return "THE SEA IS GLOWING -- SEE WHAT'S DRIFTING IN"
	if not divers.is_empty():
		return "NIGHT DIVERS IN THE SHALLOWS"
	return ""


func tick(delta: float) -> void:
	if not active:
		return
	_anim += delta
	_tick_cruise(delta)
	_tick_glow(delta)
	_tick_divers(delta)
	queue_redraw()


func _tick_cruise(delta: float) -> void:
	if not _cruise_done:
		_cruise_wait -= delta
		if _cruise_wait <= 0.0:
			_cruise_done = true
			_ship_dir = 1.0 if randf() < 0.5 else -1.0
			_ship_x = -SHIP_LEN * 0.5 if _ship_dir > 0.0 else Zones.VIEW_W + SHIP_LEN * 0.5
			game.sfx("cruise_horn", 1.0, -3.0)
		return
	if ship_on():
		var was_before := (_ship_dir > 0.0 and _ship_x < Zones.VIEW_W * 0.5) or (_ship_dir < 0.0 and _ship_x > Zones.VIEW_W * 0.5)
		_ship_x += SHIP_SPEED * _ship_dir * delta
		var now_past := (_ship_dir > 0.0 and _ship_x >= Zones.VIEW_W * 0.5) or (_ship_dir < 0.0 and _ship_x <= Zones.VIEW_W * 0.5)
		if was_before and now_past:
			_crowd_left = cruise_crowd
			game.sfx("cruise_crowd", 1.0, -6.0)
			_crowd_t = 0.0
	if _crowd_left > 0:
		_crowd_t -= delta
		if _crowd_t <= 0.0:
			_crowd_t = 0.45
			_crowd_left -= 1
			var start := Vector2(randf_range(30.0, Zones.VIEW_W - 60.0), Zones.TOURIST_SPAWN_Y)
			game.spawner.make_tourist(start, randf_range(Zones.SHORE_Y - 10.0, Zones.DEEP_TOP - 20.0), false)


func _tick_glow(delta: float) -> void:
	if glowing():
		_glow_t += delta
		if _glow_t >= glow_len:
			_glow_t = -1.0
		return
	_glow_next -= delta
	if _glow_next <= 0.0:
		_glow_next = glow_every * randf_range(0.85, 1.15)
		_glow_t = 0.0
		game.sfx("bioluminescence", 1.0, -6.0)


func _tick_divers(delta: float) -> void:
	_divers_next -= delta
	if _divers_next <= 0.0 and divers.is_empty():
		_divers_next = divers_every * randf_range(0.85, 1.15)
		game.sfx("diver_surface", 1.0, -6.0)
		var x0 := randf_range(60.0, Zones.VIEW_W - 60.0)
		for i in 2:
			divers.append({
				"pos": Vector2(clampf(x0 + float(i) * 34.0 - 17.0, 20.0, Zones.VIEW_W - 20.0),
					randf_range(Zones.SHALLOW_TOP + 16.0, Zones.DEEP_TOP - 14.0)),
				"t": 0.0,
				"phase": randf() * TAU,
			})
	var keep := []
	for d in divers:
		d["t"] = float(d["t"]) + delta
		var p: Vector2 = d["pos"]
		p.x += sin(_anim * 0.6 + float(d["phase"])) * 6.0 * delta
		d["pos"] = p
		var up := _diver_up(d)
		if up > 0.6 and game.touches_player(p, DIVER_SIZE):
			game.player.get_hit()
		if float(d["t"]) < divers_len:
			keep.append(d)
	divers = keep


func _diver_up(d: Dictionary) -> float:
	# 0 under water, 1 surfaced: up over a second, down over a second.
	var t: float = d["t"]
	return clampf(minf(t, divers_len - t), 0.0, 1.0)


func lights() -> PackedVector3Array:
	# Extra holes in the darkness, for the Night system.
	var out := PackedVector3Array()
	if not active:
		return out
	for d in divers:
		if _diver_up(d) > 0.2:
			var p: Vector2 = d["pos"]
			out.append(Vector3(p.x, p.y - 4.0, DIVER_LIGHT * _diver_up(d)))
	if glowing():
		var k := _glow_shape()
		for c in game.world.get_children():
			if out.size() >= 10:
				break
			if c is Seaweed and (c as Seaweed).drifting:
				var sw := c as Seaweed
				out.append(Vector3(sw.position.x, sw.position.y, GLOW_LIGHT * k))
	return out


func _glow_shape() -> float:
	if not glowing():
		return 0.0
	return clampf(minf(_glow_t / 1.0, (glow_len - _glow_t) / 1.0), 0.0, 1.0)


# ---- drawing (above the darkness) --------------------------------------------

func _draw() -> void:
	if not active:
		return
	if ship_on():
		_draw_ship()
	if glowing():
		_draw_glow()
	for d in divers:
		_draw_diver(d)


func _draw_ship() -> void:
	# Far out but clear of the HUD strip at the foot of the screen.
	var y := Zones.DEEP_TOP + 46.0
	var x := _ship_x
	var half := SHIP_LEN * 0.5
	if SHIP_ART != null:
		# The art faces right; mirrored for a westbound crossing. The hull is
		# dimmed to night, the lit windows still read as warm light.
		var sz := SHIP_ART.get_size() * 2.0
		draw_set_transform(Vector2(x, y), 0.0, Vector2(_ship_dir, 1.0))
		draw_texture_rect(SHIP_ART, Rect2(Vector2(-sz.x * 0.5, -sz.y + 8.0), sz), false, Color(0.72, 0.74, 0.88))
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(x - half, y + 9, SHIP_LEN, 2), Color(1.0, 0.8, 0.4, 0.25))
		return
	var hull := PackedVector2Array([Vector2(x - half, y - 6), Vector2(x + half, y - 6),
		Vector2(x + half - 10.0 * _ship_dir, y + 8), Vector2(x - half + 6.0 * _ship_dir, y + 8)])
	draw_colored_polygon(hull, Color(0.10, 0.11, 0.16))
	draw_rect(Rect2(x - half * 0.7, y - 18, half * 1.4, 12), Color(0.14, 0.15, 0.20))
	draw_rect(Rect2(x - half * 0.4, y - 26, half * 0.8, 8), Color(0.16, 0.17, 0.22))
	draw_rect(Rect2(x - 4.0 * _ship_dir - 3.0, y - 34, 6, 8), Color(0.75, 0.2, 0.15))
	# rows of lit cabin windows -- the whole point of the ship at night
	for row in 3:
		var ry := y - 2.0 - float(row) * 8.0
		var w := half * (1.0 - 0.3 * float(row))
		var n := int(w / 5.0)
		for i in n:
			var wx := x - w + float(i) * 10.0 + 3.0
			if (i * 7 + row * 3) % 5 != 0:
				draw_rect(Rect2(wx, ry, 3, 2), Color(1.0, 0.85, 0.45, 0.95))
	# its light on the water
	draw_rect(Rect2(x - half, y + 9, SHIP_LEN, 2), Color(1.0, 0.8, 0.4, 0.25))


func _draw_glow() -> void:
	var k := _glow_shape()
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).drifting:
			var p := (c as Seaweed).position
			var pulse := 0.6 + 0.4 * sin(_anim * 4.0 + p.x * 0.1)
			draw_circle(p, 9.0, Color(0.3, 0.95, 1.0, 0.18 * k * pulse))
			draw_arc(p, 7.0, 0.0, TAU, 12, Color(0.5, 1.0, 1.0, 0.55 * k * pulse), 1.0)
	# sparkles on the water
	for i in 26:
		var sx := fmod(float(i) * 61.0 + _anim * 7.0, Zones.VIEW_W)
		var sy := Zones.SHALLOW_TOP + fmod(float(i) * 37.0, Zones.VIEW_H - Zones.SHALLOW_TOP)
		var tw := maxf(0.0, sin(_anim * 3.0 + float(i)))
		draw_circle(Vector2(sx, sy), 1.0, Color(0.5, 1.0, 1.0, 0.7 * k * tw))


func _draw_diver(d: Dictionary) -> void:
	var up := _diver_up(d)
	if up <= 0.0:
		return
	var p: Vector2 = d["pos"] + Vector2(0, (1.0 - up) * 6.0 + sin(_anim * 2.0 + float(d["phase"])) * 1.0)
	# bubbles as they come up and go down
	if up < 1.0:
		draw_arc(p + Vector2(0, 2), 6.0 + (1.0 - up) * 6.0, 0.0, TAU, 12, Color(1, 1, 1, 0.5 * (1.0 - up)), 1.0)
	if DIVER_ART != null:
		var sz := DIVER_ART.get_size() * 2.0
		draw_texture_rect(DIVER_ART, Rect2(p - sz * 0.5, sz), false, Color(1, 1, 1, up))
		return
	draw_circle(p, 5.0, Color(0.05, 0.06, 0.08, up))
	draw_rect(Rect2(p + Vector2(-4, -2), Vector2(8, 3)), Color(0.55, 0.85, 1.0, 0.9 * up))
	draw_line(p + Vector2(4, -1), p + Vector2(5, -8), Color(0.95, 0.75, 0.15, up), 1.5)
	# torch beam
	draw_line(p + Vector2(-4, 2), p + Vector2(-14, 8), Color(1.0, 0.95, 0.7, 0.55 * up), 2.0)
	draw_arc(p, 8.0, 0.0, TAU, 14, Color(1, 1, 1, 0.35 * up), 1.0)
