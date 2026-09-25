class_name VipZone
extends Node2D

# The beach club's VIP frontage on Playa del Carmen: the club's whole beachfront,
# from its daybeds down to the water. Seaweed that washes up inside it costs
# TRIPLE reputation -- it is in the guests' eyeline.
#
# It runs to the waterline rather than sitting up by the club because that is
# where seaweed lands; a strip at the top of the sand would almost never see
# any. The service bay is on the far LEFT of this beach and the frontage on the
# right, so every VIP pile is the longest haul in the game.
#
# Drawn in code: a velvet rope on brass posts marking the boundary, and a faint
# warm tint on the sand. The rope pulses red while anything is lying inside, so
# the player can see at a glance that the frontage needs attention.

const ROPE := Color(0.62, 0.08, 0.14)
const ROPE_ALERT := Color(0.98, 0.22, 0.20)
const POST := Color(0.86, 0.68, 0.30)
const POST_DARK := Color(0.40, 0.28, 0.10)
const TINT := Color(1.0, 0.86, 0.45, 0.07)
const POST_GAP := 26.0

# Uses assets/sprites/vip_sign.png at the head of the rope if present (drawn at
# 2x); otherwise a plaque drawn in code.
const SIGN_PATH := "res://assets/sprites/vip_sign.png"

var game
var rect := Rect2()
var _sign: Texture2D
var _alert := 0.0
var _t := 0.0


func configure(r: Rect2) -> void:
	rect = r
	visible = r.size.x > 0.0
	_sign = load(SIGN_PATH) if ResourceLoader.exists(SIGN_PATH) else null
	queue_redraw()


func _process(delta: float) -> void:
	if not visible or game == null:
		return
	_t = fposmod(_t + delta * 5.0, TAU)
	var want := 1.0 if game.vip_units() > 0 else 0.0
	_alert = move_toward(_alert, want, delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if rect.size.x <= 0.0:
		return
	draw_rect(rect, TINT)
	var pulse := 0.5 + 0.5 * sin(_t)
	var rope := ROPE.lerp(ROPE_ALERT, _alert * pulse)
	var l := rect.position.x
	var r := rect.end.x
	var top := rect.position.y + 4.0
	var bottom := rect.end.y - 2.0
	# The rope runs down the inner (left) edge only -- the right edge is the
	# screen wall and the top is the club itself. It sags between posts.
	var y := top
	while y < bottom:
		var y2 := minf(y + POST_GAP, bottom)
		var pts := PackedVector2Array()
		for i in 7:
			var f := float(i) / 6.0
			pts.append(Vector2(l + sin(f * PI) * 3.0, lerpf(y, y2, f)))
		draw_polyline(pts, rope, 2.0)
		y = y2
	y = top
	while y <= bottom + 0.5:
		draw_rect(Rect2(l - 2.0, y - 5.0, 4.0, 7.0), POST_DARK)
		draw_rect(Rect2(l - 1.0, y - 5.0, 2.0, 6.0), POST)
		draw_circle(Vector2(l, y - 5.0), 2.2, POST)
		y += POST_GAP
	# The VIP sign at the head of the rope: the chosen art, or a coded plaque.
	if _sign != null:
		var sz := _sign.get_size() * 2.0
		draw_texture_rect(_sign, Rect2(Vector2(l + 4.0, top - sz.y * 0.35), sz), false)
		return
	var plaque := Rect2(l + 5.0, top - 2.0, 24.0, 11.0)
	draw_rect(plaque, POST_DARK)
	draw_rect(plaque.grow(-1.0), Color(0.12, 0.05, 0.06))
	draw_string(ThemeDB.fallback_font, Vector2(plaque.position.x + 3.0, plaque.end.y - 2.5),
		"VIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, POST)
