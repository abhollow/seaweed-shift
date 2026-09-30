class_name Tutorial
extends Control

# A quick read-and-tap tutorial, played when a new game reaches the first level.
# Each step dims the screen except the one thing it explains, rings it in gold,
# and puts a tip card on the OPPOSITE side of the screen so the card never covers
# what it points at. NEXT moves on; SKIP TUTORIAL ends it; the last step's
# button is START SHIFT!, which hands over to the level 1 intro card.
#
# It covers the basics only. Each level's own twist is introduced by that
# level's intro card, so the tutorial doesn't front-load them.

const SHADER := preload("res://shaders/spotlight.gdshader")
const CARD_W := 316.0
const CARD_H := 152.0

var game
var step := 0
var steps: Array = []

var _dim: ColorRect
var _mat: ShaderMaterial
var _rings: Rings
var _card: Panel
var _count: Label
var _title: Label
var _body: Label
var _dots: Dots
var _next: Button
var _skip: Button


class Rings extends Control:
	# Gold rings round each hole, gently pulsing; and on the MOVE step, a
	# joystick being dragged.
	var holes: Array = []
	var joystick := false
	var t := 0.0

	func _process(delta: float) -> void:
		t = fposmod(t + delta, TAU * 10.0)
		queue_redraw()

	func _draw() -> void:
		var a := 0.75 + 0.25 * sin(t * 4.0)
		var gold := Color(0.98, 0.86, 0.52, a)
		for h in holes:
			var r: Rect2 = h["rect"]
			if h["circle"]:
				draw_arc(r.get_center(), minf(r.size.x, r.size.y) * 0.5 + 3.0, 0.0, TAU, 48, gold, 2.0)
			else:
				draw_rect(r.grow(3.0), gold, false, 2.0)
		if joystick and not holes.is_empty():
			var c: Vector2 = (holes[0]["rect"] as Rect2).get_center()
			draw_arc(c, 30.0, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 3.0)
			draw_circle(c + Vector2(cos(t * 1.6), sin(t * 1.6)) * 16.0, 10.0, Color(1, 1, 1, 0.9))


class Dots extends Control:
	var total := 8
	var at := 0

	func _draw() -> void:
		for i in total:
			var on := i <= at
			draw_circle(Vector2(4.0 + float(i) * 12.0, 4.0), 3.0,
				Color(0.98, 0.86, 0.52) if on else Color(0.24, 0.28, 0.34))


func build() -> void:
	position = Vector2.ZERO
	size = Vector2(Zones.VIEW_W, Zones.VIEW_H)
	mouse_filter = Control.MOUSE_FILTER_STOP     # the frozen game behind can't be touched
	visible = false

	_dim = ColorRect.new()
	_dim.size = size
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_dim.material = _mat
	add_child(_dim)

	_rings = Rings.new()
	_rings.size = size
	_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rings)

	# A plain Panel (children placed by hand) wearing the same style as the
	# game's other panels, borrowed from a throwaway PanelContainer.
	_card = Panel.new()
	_card.add_theme_stylebox_override("panel",
		UiTheme.panel(PanelContainer.new()).get_theme_stylebox("panel"))
	_card.size = Vector2(CARD_W, CARD_H)
	add_child(_card)

	_count = _label(Vector2(14, 10), 11, UiTheme.TEXT_DIM)
	_skip = Button.new()
	_skip.flat = true
	_skip.text = "SKIP TUTORIAL"
	_skip.add_theme_font_size_override("font_size", 11)
	_skip.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_skip.position = Vector2(CARD_W - 118, 2)
	_skip.size = Vector2(110, 26)
	_skip.pressed.connect(func(): finish())
	_card.add_child(_skip)

	_title = _label(Vector2(14, 28), 17, UiTheme.ACCENT)
	_title.add_theme_font_override("font", UiTheme.TITLE_FONT)
	_title.add_theme_constant_override("outline_size", 3)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0))

	_body = _label(Vector2(14, 56), 12, UiTheme.TEXT)
	_body.size = Vector2(CARD_W - 28, 44)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_dots = Dots.new()
	_dots.position = Vector2(16, CARD_H - 26)
	_dots.size = Vector2(100, 10)
	_card.add_child(_dots)

	_next = UiTheme.button(Button.new())
	_next.add_theme_font_override("font", UiTheme.TITLE_FONT)
	_next.add_theme_font_size_override("font_size", 15)
	_next.pressed.connect(_on_next)
	_card.add_child(_next)


func _label(pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(CARD_W - 28, 20)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(l)
	return l


func start(step_list: Array) -> void:
	steps = step_list
	step = 0
	visible = true
	_show()


func _on_next() -> void:
	if step >= steps.size() - 1:
		finish()
		return
	step += 1
	_show()


func finish() -> void:
	visible = false
	if game != null:
		game.finish_tutorial()


func _show() -> void:
	var s: Dictionary = steps[step]
	var holes: Array = s["holes"]
	for i in 2:
		var key := "a" if i == 0 else "b"
		if i < holes.size():
			var r: Rect2 = holes[i]["rect"]
			_mat.set_shader_parameter("hole_" + key, Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
			_mat.set_shader_parameter("circle_" + key, 1.0 if holes[i]["circle"] else 0.0)
		else:
			_mat.set_shader_parameter("hole_" + key, Vector4.ZERO)
	_rings.holes = holes
	_rings.joystick = bool(s.get("joystick", false))

	# The card goes on the opposite side from what it's pointing at.
	_card.position = Vector2((Zones.VIEW_W - CARD_W) * 0.5, 44.0 if s["top"] else 590.0 - CARD_H)
	_count.text = "%d / %d" % [step + 1, steps.size()]
	_title.text = String(s["title"])
	_body.text = String(s["body"])
	_dots.total = steps.size()
	_dots.at = step
	_dots.queue_redraw()
	var last := step == steps.size() - 1
	_next.text = "START SHIFT!" if last else "NEXT"
	var bw := 150.0 if last else 96.0
	_next.size = Vector2(bw, 32)
	_next.position = Vector2(CARD_W - bw - 12, CARD_H - 42)
