class_name Kayaks
extends Node2D

# Bacalar's kayak tour: every so often a line of kayaks paddles across the
# shallows, from one side to the other. People -- bump one and the load is
# dropped -- so the tour is a moving wall to time a wade around, alongside the
# surf sets. The paddlers are ordinary tourists in the crowd's colours.

var game
var active := false

var first := 30.0
var every := 55.0
var count := 4

const KAYAK_ART := preload("res://assets/sprites/event_kayak.png")
const ART_TILT := 0.44            # radians the art's diagonal is turned back by
const SPEED := 42.0
const GAP := 34.0                 # between kayaks in the line
const SIZE := Vector2(34, 12)
const PADDLE_FPS := 3.0

var _next := 0.0
var _dir := 1.0
var boats: Array = []             # {pos, hue}
var _frames: Array = []
var _anim := 0.0
var _sprites: Array = []          # one tinted paddler Sprite2D per kayak


func _ready() -> void:
	var t: Tourist = load("res://scenes/tourist.tscn").instantiate()
	_frames = t.tex_wade_sober_m if not t.tex_wade_sober_m.is_empty() else t.tex_sober_m
	t.free()


func configure(beach: Dictionary) -> void:
	var k: Dictionary = beach.get("kayaks", {})
	active = not k.is_empty()
	visible = active
	first = float(k.get("first", 30.0))
	every = float(k.get("every", 55.0))
	count = int(k.get("count", 4))
	_next = first
	_clear()


func _clear() -> void:
	boats.clear()
	for s in _sprites:
		s.queue_free()
	_sprites.clear()


func crossing() -> bool:
	return not boats.is_empty()


func status_text() -> String:
	return "KAYAK TOUR CROSSING THE SHALLOWS" if active and crossing() else ""


func tick(delta: float) -> void:
	if not active:
		return
	_anim += delta
	if boats.is_empty():
		_next -= delta
		if _next <= 0.0:
			_next = every * randf_range(0.85, 1.15)
			_launch()
		return
	var any_on := false
	for i in boats.size():
		var b: Dictionary = boats[i]
		var p: Vector2 = b["pos"]
		p.x += SPEED * _dir * delta
		p.y += sin(_anim * 1.3 + float(i)) * 3.0 * delta
		b["pos"] = p
		var s: Sprite2D = _sprites[i]
		s.position = p + Vector2(0, -10)
		s.flip_h = _dir < 0.0
		if not _frames.is_empty():
			s.texture = _frames[int(_anim * PADDLE_FPS + float(i)) % _frames.size()]
		if game.touches_player(p, SIZE):
			game.player.get_hit()
		if p.x > -40.0 and p.x < Zones.VIEW_W + 40.0:
			any_on = true
	# Gone once the last of the line has paddled off.
	if not any_on and _all_past():
		_clear()
	queue_redraw()


func _all_past() -> bool:
	for b in boats:
		var x: float = (b["pos"] as Vector2).x
		if (_dir > 0.0 and x < Zones.VIEW_W + 40.0) or (_dir < 0.0 and x > -40.0):
			return false
	return true


func _launch() -> void:
	_clear()
	game.sfx("kayak_paddles", 1.0, -6.0)
	_dir = 1.0 if randf() < 0.5 else -1.0
	var y := lerpf(Zones.SHALLOW_TOP, Zones.DEEP_TOP, 0.45)
	for i in count:
		var x := -30.0 - float(i) * GAP if _dir > 0.0 else Zones.VIEW_W + 30.0 + float(i) * GAP
		boats.append({"pos": Vector2(x, y + randf_range(-8.0, 8.0)),
			"hull": [Color(1.0, 0.75, 0.1), Color(0.95, 0.3, 0.2), Color(0.2, 0.75, 0.4), Color(0.25, 0.5, 0.95)][i % 4]})
		var s := Sprite2D.new()
		s.scale = Vector2(2, 2)
		s.material = Tourist._tint_for(game.spawner.clothes_hue())
		add_child(s)
		_sprites.append(s)


func _draw() -> void:
	if not active:
		return
	for i in boats.size():
		var b: Dictionary = boats[i]
		var p: Vector2 = b["pos"]
		var col: Color = b["hull"]
		if KAYAK_ART != null:
			# The art lies on a diagonal (bow up-right): level it, and mirror
			# it for a westbound tour. Each kayak tinted its own colour.
			var sz := KAYAK_ART.get_size() * 2.0
			draw_set_transform(p, ART_TILT * _dir, Vector2(_dir, 1.0))
			draw_texture_rect(KAYAK_ART, Rect2(-sz * 0.5, sz), false, col.lightened(0.35))
			draw_set_transform(Vector2.ZERO)
		else:
			var hull := PackedVector2Array([p + Vector2(-19, 0), p + Vector2(-11, -5), p + Vector2(11, -5),
				p + Vector2(19, 0), p + Vector2(11, 5), p + Vector2(-11, 5)])
			draw_colored_polygon(hull, col)
			draw_polyline(hull + PackedVector2Array([hull[0]]), col.darkened(0.5), 1.0)
		# the paddle, dipping side to side
		var a := sin(_anim * PADDLE_FPS * PI + float(i)) * 0.9
		var c := p + Vector2(0, -6)
		var d := Vector2(cos(a), sin(a) * 0.4) * 15.0
		draw_line(c - d, c + d, Color(0.35, 0.25, 0.15), 1.5)
		# a little wake
		draw_line(p + Vector2(-14.0 * _dir, 1), p + Vector2(-22.0 * _dir, 2), Color(1, 1, 1, 0.5), 1.0)
