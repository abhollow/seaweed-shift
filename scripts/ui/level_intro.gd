class_name LevelIntro
extends Control

# Shown at the start of every level: the location's name over its own art, a
# line on what is different here, and a button the player must press to begin.
#
# Without it, finishing a level dropped you straight onto a new beach mid-play.
# The new location -- the main reward for finishing -- flashed past unnoticed,
# and a new rule (the wind) arrived with no warning at all.

var game

var _bg: TextureRect
var _count: Label
var _name: Label
var _tag: Label
var _button: Button
var _sway: ShaderMaterial
var _t := 0.0


func build() -> void:
	position = Vector2.ZERO
	size = Vector2(Zones.VIEW_W, Zones.VIEW_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_bg = TextureRect.new()
	_bg.size = size
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Dark enough for white type to read over any beach, light enough that the
	# art still shows -- the art IS the reward.
	var scrim := ColorRect.new()
	scrim.size = size
	scrim.color = Color(0.02, 0.05, 0.09, 0.52)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_count = _label(Vector2(0, 150), 15, UiTheme.ACCENT)
	_count.add_theme_constant_override("outline_size", 6)

	# Same face and treatment as the baked wordmark: heavy rounded white type,
	# a thick black outline and a hard drop shadow.
	_name = _label(Vector2(20, 176), 40, Color(1, 1, 1))
	_name.add_theme_font_override("font", UiTheme.TITLE_FONT)
	_name.add_theme_constant_override("outline_size", 14)
	_name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_name.add_theme_constant_override("shadow_offset_x", 4)
	_name.add_theme_constant_override("shadow_offset_y", 5)
	_name.size = Vector2(Zones.VIEW_W - 40, 120)
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_tag = _label(Vector2(34, 318), 15, Color(0.96, 0.97, 0.98))
	_tag.size = Vector2(Zones.VIEW_W - 68, 80)
	_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tag.add_theme_constant_override("outline_size", 5)

	_button = UiTheme.button(Button.new())
	_button.text = "START SHIFT!"
	_button.add_theme_font_override("font", UiTheme.TITLE_FONT)
	_button.add_theme_font_size_override("font_size", 22)
	_button.size = Vector2(240, 60)
	_button.position = Vector2((Zones.VIEW_W - 240) / 2.0, 470)
	_button.pressed.connect(_on_start)
	add_child(_button)


func _label(pos: Vector2, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = Vector2(Zones.VIEW_W - pos.x * 2.0, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func show_for(level: int) -> void:
	var beach := Beaches.for_level(level)
	var path := String(beach.get("background", ""))
	if path != "" and ResourceLoader.exists(path):
		_bg.texture = load(path)
	_sway = Game.make_sway_material(beach)
	_bg.material = _sway
	_count.text = "LEVEL %d OF %d" % [level, Beaches.NAMES.size()]
	_name.text = Beaches.name_of(level).to_upper()
	# Long names ("Playa del Carmen") wrap onto two lines; step the size down a
	# little so two lines still fit the slot.
	_name.add_theme_font_size_override("font_size", 40 if _name.text.length() <= 10 else 34)
	_tag.text = String(beach.get("tagline", ""))

	visible = true
	modulate.a = 0.0
	_name.scale = Vector2(0.7, 0.7)
	_name.pivot_offset = _name.size / 2.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(_name, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	# The game's wind is paused behind this card, so the card makes its own:
	# a slow swell in and out, enough to show the level is windy at a glance.
	if not visible or _sway == null:
		return
	_t += delta
	_sway.set_shader_parameter("t", _t)
	_sway.set_shader_parameter("gust", clampf(sin(_t * 0.9) * 0.8, 0.0, 1.0))


func _on_start() -> void:
	if game != null:
		game.start_from_intro()
