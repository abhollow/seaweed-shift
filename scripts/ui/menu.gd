class_name Menu
extends Control

# Placeholder title screen. Deliberately built in code and deliberately plain --
# it exists so the flow (new / continue / settings) is real and testable before
# any art decides what it should look like.

const MAIN_SCENE := "res://scenes/main.tscn"
# Authored at 180x320 -- exactly half the 360x640 screen -- so it upscales 2x
# with nearest filtering and no resampling. That doubled pixel is the point:
# the title screen reads chunkier than the game itself.
const BACKGROUND := preload("res://assets/sprites/menu_background.png")

# Baked wordmark rather than live text: the seaweed has to interact with the
# letterforms, which no font can do. Authored at half density like the rest of
# the art and drawn at 2x.
const TITLE := preload("res://assets/sprites/title_logo.png")

const WATER_FRAMES: Array[Texture2D] = [
	preload("res://assets/sprites/menu_water_00.png"),
	preload("res://assets/sprites/menu_water_01.png"),
	preload("res://assets/sprites/menu_water_02.png"),
	preload("res://assets/sprites/menu_water_03.png"),
	preload("res://assets/sprites/menu_water_04.png"),
	preload("res://assets/sprites/menu_water_05.png"),
	preload("res://assets/sprites/menu_water_06.png"),
	preload("res://assets/sprites/menu_water_07.png"),
]
const WATER_TOP := 392.0       # in 360x640 screen space (196 art px x2)
const WATER_FPS := 6.0

# Drifting clouds. The surf already moves; without these the sky was the one
# dead area of the screen, and it is the area the eye rests on while reading
# the title.
#
# Each cloud gets its own speed and scale, so they separate into layers as they
# travel -- a single shared speed reads as one sheet of wallpaper sliding past.
# Slow: the fastest crosses the screen in about a minute.
const CLOUD_BAND_TOP := 30.0
const CLOUD_BAND_BOTTOM := 250.0
const CLOUD_SPEED_MIN := 3.0
const CLOUD_SPEED_MAX := 9.0
const MENU_MUSIC := "res://audio/8-bit_Sunset.mp3"
const MENU_MUSIC_DB := -8.0
const FADE_OUT := 0.35

var _settings := {}
var _settings_panel: PanelContainer
var _continue_btn: Button
var _new_btn: Button
var _new_armed := false
var _reset_armed := false
var _music: AudioStreamPlayer
var _bg: TextureRect
var _title: TextureRect
var _water: TextureRect
var _water_t := 0.0
var _water_frame := -1
var _clouds: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings = Settings.load_all()
	Settings.apply(_settings)
	_build()
	_start_music()


# =============================================================================
# Layout
# =============================================================================

func _build() -> void:
	_bg = TextureRect.new()
	_bg.texture = BACKGROUND
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_build_clouds()

	# Same trick as the beach: a strip of pre-displaced frames laid over the
	# background's own water, so only the surf moves and the resort stays put.
	_water = TextureRect.new()
	_water.texture = WATER_FRAMES[0]
	_water.position = Vector2(0, WATER_TOP)
	_water.size = Vector2(360, 640 - WATER_TOP)
	_water.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_water.stretch_mode = TextureRect.STRETCH_SCALE
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_water)
	_water_frame = 0

	# The art is bright and busy. A scrim buys back enough contrast for the
	# title and the "no saved shift" line without dulling the resort itself.
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.02, 0.05, 0.09, 0.30)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# Title at the top, buttons at the bottom, so the resort and beach in the
	# middle stay unobstructed -- the art is the reason to look at this screen.
	_title = TextureRect.new()
	_title.texture = TITLE
	_title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_title.stretch_mode = TextureRect.STRETCH_SCALE
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := TITLE.get_width() * 2.0
	var th := TITLE.get_height() * 2.0
	_title.position = Vector2((360.0 - tw) / 2.0, 26)
	_title.size = Vector2(tw, th)
	add_child(_title)

	# No subtitle: the wordmark says enough, and a line of small text under a
	# heavy three-line logo just crowded it.

	var save := SaveGame.load_data()
	var has_save: bool = not save.is_empty()

	if not has_save:
		_text("No saved shift yet.", Vector2(0, 404), 12, Color(0.82, 0.88, 0.90))

	_continue_btn = _button(_continue_label(save), Vector2(40, 436), 280, 52)
	_continue_btn.disabled = not has_save
	_continue_btn.pressed.connect(_on_continue)

	_new_btn = _button("NEW GAME", Vector2(40, 496), 280, 52)
	_new_btn.pressed.connect(_on_new_game)

	var settings_btn := _button("SETTINGS", Vector2(40, 556), 280, 48)
	settings_btn.pressed.connect(func(): _show_settings(true))

	_build_settings_panel()


func _text(s: String, pos: Vector2, fsize: int, c: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.position = Vector2(0, pos.y)
	l.size = Vector2(360, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.outline(l)
	add_child(l)
	return l


func _button(text: String, pos: Vector2, w: float, h: float) -> Button:
	var b := UiTheme.button(Button.new())
	b.text = text
	b.position = pos
	b.size = Vector2(w, h)
	add_child(b)
	return b


func _continue_label(save: Dictionary) -> String:
	if save.is_empty():
		return "CONTINUE"
	var shift := int(save.get("level_index", 0)) + 1
	return "CONTINUE  --  Shift %d, %d cr" % [shift, int(save.get("credits", 0))]


func _build_clouds() -> void:
	# Loaded by scanning the sprites folder so adding or removing a cloud file
	# needs no code change.
	var frames: Array[Texture2D] = []
	for i in 8:
		var path := "res://assets/sprites/cloud_%02d.png" % i
		if ResourceLoader.exists(path):
			frames.append(load(path))
	if frames.is_empty():
		return

	for i in frames.size() * 2:
		var tex: Texture2D = frames[i % frames.size()]
		var spr := TextureRect.new()
		spr.texture = tex
		spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spr.stretch_mode = TextureRect.STRETCH_SCALE
		spr.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Bigger clouds drift faster, which is the wrong way round for real
		# parallax but reads better here: the big ones are the ones you notice
		# moving, and the small ones hang back as depth.
		var scale := randf_range(1.4, 2.6)
		var speed := lerpf(CLOUD_SPEED_MIN, CLOUD_SPEED_MAX,
			(scale - 1.4) / 1.2)
		spr.size = tex.get_size() * scale
		spr.position = Vector2(
			randf_range(-spr.size.x, 360.0),
			randf_range(CLOUD_BAND_TOP, CLOUD_BAND_BOTTOM - spr.size.y))
		spr.modulate.a = randf_range(0.55, 0.9)
		add_child(spr)
		_clouds.append({"node": spr, "speed": speed})


func _drift_clouds(delta: float) -> void:
	for c in _clouds:
		var n: TextureRect = c["node"]
		n.position.x += float(c["speed"]) * delta
		if n.position.x > 360.0:
			# Re-enters from the left at a fresh height, so the sky never
			# settles into a repeating pattern.
			n.position.x = -n.size.x
			n.position.y = randf_range(CLOUD_BAND_TOP, CLOUD_BAND_BOTTOM - n.size.y)


func _process(delta: float) -> void:
	_drift_clouds(delta)
	if _water == null:
		return
	_water_t += delta * WATER_FPS
	var i := int(_water_t) % WATER_FRAMES.size()
	if i != _water_frame:
		_water_frame = i
		_water.texture = WATER_FRAMES[i]


# =============================================================================
# Music
# =============================================================================

func _start_music() -> void:
	# On the Music bus, so the settings slider governs it exactly like in-game
	# music does.
	if not ResourceLoader.exists(MENU_MUSIC):
		push_warning("No menu music at %s" % MENU_MUSIC)
		return
	var stream = load(MENU_MUSIC)
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true

	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	_music.stream = stream
	_music.volume_db = MENU_MUSIC_DB
	add_child(_music)
	_music.play()


func _fade_out_music() -> void:
	# A hard cut into the shift's track clicks. A third of a second is enough to
	# hide the seam without making the button feel unresponsive.
	if _music == null or not _music.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MENU_MUSIC_DB - 40.0, FADE_OUT)
	await tw.finished


# =============================================================================
# Actions
# =============================================================================

func _on_continue() -> void:
	_start(false)


func _on_new_game() -> void:
	# Only ask twice if there's actually something to lose.
	if not SaveGame.load_data().is_empty() and not _new_armed:
		_new_armed = true
		_new_btn.text = "TAP AGAIN -- ERASES SAVE"
		return
	SaveGame.wipe()
	_start(true)


func _jump_to_level(n: int) -> void:
	# Writes a save that starts level n at shift 1 with nothing owned, then
	# continues it -- the same path a real rollover lands on. Overwrites the
	# current save, which is fine for a testing shortcut.
	SaveGame.store({
		"credits": 0,
		"owned": {},
		"retained": {},
		"level": n,
		"level_index": 0,
		"free_play": false,
	})
	_show_settings(false)
	_start(false)


func _start(fresh: bool) -> void:
	await _fade_out_music()
	# Instanced by hand rather than change_scene_to_packed(), because the fresh
	# flag has to be set BEFORE the game's _ready() decides whether to load.
	var packed: PackedScene = load(MAIN_SCENE)
	var game = packed.instantiate()
	game.start_fresh = fresh
	get_tree().root.add_child(game)
	var old := get_tree().current_scene
	get_tree().current_scene = game
	if old != null:
		old.queue_free()


# =============================================================================
# Settings
# =============================================================================

func _build_settings_panel() -> void:
	_settings_panel = UiTheme.panel(PanelContainer.new())
	_settings_panel.position = Vector2(24, 150)
	_settings_panel.size = Vector2(312, 384)
	_settings_panel.visible = false
	add_child(_settings_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_settings_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_slider(box, "Music", "music")
	_slider(box, "Sound effects", "sfx")
	_slider(box, "Ambience", "ambience")

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	box.add_child(gap)

	var reset := UiTheme.button(Button.new())
	reset.text = "Erase saved progress"
	reset.custom_minimum_size = Vector2(0, 38)
	reset.add_theme_color_override("font_color", Color(0.95, 0.55, 0.5))
	reset.pressed.connect(_on_reset.bind(reset))
	box.add_child(reset)

	# Playtesting shortcut: jump straight to any level that has its own beach.
	# Debug builds only -- a release build never shows it, so it cannot leak
	# into the shipped game. The Android APK you side-load IS a debug build.
	if OS.is_debug_build():
		var jump := HBoxContainer.new()
		jump.add_theme_constant_override("separation", 6)
		box.add_child(jump)
		var lbl := Label.new()
		lbl.text = "TEST LEVEL"
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
		jump.add_child(lbl)
		for lv in Beaches.LIST.keys():
			var jb := UiTheme.button(Button.new())
			jb.text = str(lv)
			jb.custom_minimum_size = Vector2(38, 34)
			jb.pressed.connect(_jump_to_level.bind(int(lv)))
			jump.add_child(jb)

	var back := UiTheme.button(Button.new())
	back.text = "BACK"
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(func(): _show_settings(false))
	box.add_child(back)


func _slider(box: VBoxContainer, label: String, key: String) -> void:
	var row := Label.new()
	row.text = label
	row.add_theme_font_size_override("font_size", 13)
	box.add_child(row)

	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(_settings.get(key, 0.8))
	s.custom_minimum_size = Vector2(0, 28)
	s.value_changed.connect(_on_slider.bind(key))
	box.add_child(s)


func _on_slider(value: float, key: String) -> void:
	_settings[key] = value
	Settings.apply(_settings)
	Settings.store(_settings)


func _on_reset(btn: Button) -> void:
	if not _reset_armed:
		_reset_armed = true
		btn.text = "TAP AGAIN TO ERASE"
		return
	_reset_armed = false
	btn.text = "Save erased"
	SaveGame.wipe()
	_continue_btn.disabled = true
	_continue_btn.text = "CONTINUE"


func _show_settings(v: bool) -> void:
	_settings_panel.visible = v
	_reset_armed = false
