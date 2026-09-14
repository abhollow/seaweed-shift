class_name WeatherFx
extends Node2D

# Drawn weather, not particle nodes or art: rain streaks and mirrorball flecks
# are lines and circles, so there are no textures to author or keep in sync with
# the palette. The one exception is the mirrorball itself, which is a sprite.
#
# Sits above the sprites but below the floating popups, so a "+1" is never lost
# behind the storm.

const DROPS := 130
const DROP_SPEED_MIN := 420.0
const DROP_SPEED_MAX := 700.0
const DROP_SLANT := 0.30          # x drift per unit of fall; the wind
const DROP_LEN_MIN := 7.0
const DROP_LEN_MAX := 14.0
const RAIN_COLOR := Color(0.72, 0.85, 1.0, 0.55)

# --- mirrorball -------------------------------------------------------------
const BALL_REST_Y := 74.0         # hangs inside the hotel zone
const BALL_DROP_TIME := 1.1
const BALL_SPIN_FPS := 10.0
const BALL_SIZE := Vector2(48, 60)

# Flecks thrown by the ball. Deliberately black AND white: on a desaturated
# scene the white ones read as light and the dark ones as the gaps between
# mirrors, which is what makes it feel like a spinning ball rather than a
# flashing lamp.
# Flecks SWEEP across the beach rather than blinking in place -- movement is
# what reads as a ball spinning.
const FLECKS := 70
const FLECK_R_MIN := 4.0
const FLECK_R_MAX := 13.0
const FLECK_SPEED_MIN := 26.0
const FLECK_SPEED_MAX := 74.0
const FLECK_BLINK := 3.2

# Club beat, driving both the fleck throb and the exposure pulse.
const BEAT_HZ := 2.6
const BEAT_DEPTH := 0.05

# Preloaded rather than exported: WeatherFx is constructed in code, so there is
# no scene inspector to drop these into.
const tex_ball: Array[Texture2D] = [
	preload("res://assets/sprites/ball_00.png"),
	preload("res://assets/sprites/ball_01.png"),
	preload("res://assets/sprites/ball_02.png"),
	preload("res://assets/sprites/ball_03.png"),
]

var game

var _drops: Array = []
var _flecks: Array = []
var _t := 0.0
var _ball: Sprite2D
var _ball_frame := -1
var _flecks_layer: Node2D
var _was_active := false


class FleckLayer extends Node2D:
	var fx

	func _draw() -> void:
		if fx != null:
			fx.draw_flecks(self)


func _ready() -> void:
	z_index = 55   # above sprites (0), below popups (60)
	set_process(true)

	_flecks_layer = FleckLayer.new()
	_flecks_layer.fx = self
	_flecks_layer.z_index = -1
	add_child(_flecks_layer)

	_ball = Sprite2D.new()
	_ball.visible = false
	_ball.z_index = 1
	add_child(_ball)

	for i in DROPS:
		_drops.append({
			"pos": Vector2(randf() * Zones.VIEW_W, randf() * Zones.VIEW_H),
			"speed": randf_range(DROP_SPEED_MIN, DROP_SPEED_MAX),
			"len": randf_range(DROP_LEN_MIN, DROP_LEN_MAX),
		})

	for i in FLECKS:
		_flecks.append(_new_fleck(randf() * TAU))


func _new_fleck(phase: float) -> Dictionary:
	# Angle biased sideways so spots sweep ACROSS the beach rather than raining
	# down it: a ball on a ceiling throws light outward, not downward.
	var a := randf_range(-0.55, 0.55) + (PI if randf() < 0.5 else 0.0)
	var sp := randf_range(FLECK_SPEED_MIN, FLECK_SPEED_MAX)
	return {
		"pos": Vector2(randf_range(-20.0, Zones.VIEW_W + 20.0),
			randf_range(Zones.HOTEL_BOTTOM - 40.0, Zones.VIEW_H + 10.0)),
		"vel": Vector2(cos(a), sin(a) * 0.45) * sp,
		"r": randf_range(FLECK_R_MIN, FLECK_R_MAX),
		"white": randf() < 0.60,
		"phase": phase,
	}


# =============================================================================
# Ball
# =============================================================================

func set_ball_visible(v: bool) -> void:
	if _ball == null:
		return
	if v and not tex_ball.is_empty():
		_ball.visible = true
		_ball.position = Vector2(Zones.VIEW_W * 0.5, -BALL_SIZE.y)
		_show_ball_frame(0)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(_ball, "position:y", BALL_REST_Y, BALL_DROP_TIME)
	elif _ball.visible:
		# Winched back up rather than vanishing -- it arrived, it should leave.
		var tw := create_tween()
		tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_ball, "position:y", -BALL_SIZE.y, 0.8)
		tw.tween_callback(func(): _ball.visible = false)


func _show_ball_frame(i: int) -> void:
	if tex_ball.is_empty() or i == _ball_frame:
		return
	_ball_frame = i
	var tex: Texture2D = tex_ball[i % tex_ball.size()]
	_ball.texture = tex
	var t := tex.get_size()
	if t.x > 0.0 and t.y > 0.0:
		_ball.scale = Vector2(BALL_SIZE.x / t.x, BALL_SIZE.y / t.y)


# =============================================================================
# Loop
# =============================================================================

func _process(delta: float) -> void:
	var storm: bool = game != null and game.storm_active
	var disco: bool = game != null and game.happy_hour

	if storm:
		for d in _drops:
			d["pos"].y += d["speed"] * delta
			d["pos"].x += d["speed"] * DROP_SLANT * delta
			if d["pos"].y > Zones.VIEW_H:
				d["pos"].y = -d["len"]
				d["pos"].x = randf() * (Zones.VIEW_W + 120.0) - 60.0
			elif d["pos"].x > Zones.VIEW_W + 20.0:
				d["pos"].x = -20.0

	if disco:
		_t += delta
		_show_ball_frame(int(_t * BALL_SPIN_FPS) % max(1, tex_ball.size()))

		var span := Zones.VIEW_W + 60.0
		for f in _flecks:
			f["pos"] += f["vel"] * delta
			# Wrapped rather than respawned, so the sweep never stutters.
			if f["pos"].x < -30.0:
				f["pos"].x += span
			elif f["pos"].x > Zones.VIEW_W + 30.0:
				f["pos"].x -= span
			if f["pos"].y < Zones.HOTEL_BOTTOM - 50.0:
				f["pos"].y = Zones.VIEW_H + 10.0
			elif f["pos"].y > Zones.VIEW_H + 20.0:
				f["pos"].y = Zones.HOTEL_BOTTOM - 40.0

	var active := storm or disco
	if active or _was_active:
		# The trailing redraw matters: without it the last frame of rain and
		# flecks stays painted on screen after the event ends, because nothing
		# would ask the canvas to clear itself.
		queue_redraw()
		_flecks_layer.queue_redraw()
	_was_active = active


func _draw() -> void:
	if game != null and game.storm_active:
		for d in _drops:
			var p: Vector2 = d["pos"]
			draw_line(p, p + Vector2(-DROP_SLANT, -1.0) * d["len"], RAIN_COLOR, 1.0)


func draw_flecks(canvas: Node2D) -> void:
	if game == null or not game.happy_hour:
		return
	for f in _flecks:
		# Each spot breathes on its own offset, so they never flash as one
		# block -- that reads as a strobe rather than a mirrorball.
		var b: float = 0.5 + 0.5 * sin(_t * FLECK_BLINK + f["phase"])
		if b < 0.12:
			continue
		var c: Color
		if f["white"]:
			c = Color(1, 1, 1, 0.62 * b)
		else:
			c = Color(0, 0, 0, 0.48 * b)
		canvas.draw_circle(f["pos"], f["r"] * (0.7 + 0.3 * b), c)
