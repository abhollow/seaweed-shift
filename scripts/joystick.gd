class_name Joystick
extends Control

# Floating joystick: touch anywhere below `top_margin`, that spot becomes the
# stick origin. Dragging past `max_radius` drags the origin along so the stick
# never feels "stuck" at the edge.

var max_radius := 85.0
var dead_zone := 10.0
var top_margin := 145.0

var direction := Vector2.ZERO
var active := true

var _index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _input(event: InputEvent) -> void:
	if not active:
		if _index != -1:
			_reset()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			if _index == -1 and event.position.y > top_margin:
				_index = event.index
				_origin = event.position
				_knob = event.position
				direction = Vector2.ZERO
				queue_redraw()
		elif event.index == _index:
			_reset()

	elif event is InputEventScreenDrag and event.index == _index:
		_knob = event.position
		var offset: Vector2 = _knob - _origin
		if offset.length() > max_radius:
			offset = offset.normalized() * max_radius
			_origin = _knob - offset
		if offset.length() < dead_zone:
			direction = Vector2.ZERO
		else:
			direction = offset / max_radius
		queue_redraw()


func _reset() -> void:
	_index = -1
	direction = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if _index == -1:
		return
	draw_circle(_origin, max_radius, Color(1, 1, 1, 0.10))
	draw_circle(_knob, 26.0, Color(1, 1, 1, 0.30))
