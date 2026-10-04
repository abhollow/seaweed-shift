class_name Game
extends Node2D

# =============================================================================
# SEAWEED SHIFT
#
# This file is the spine: it owns the world, the shared state everything reads
# (credits, weather flags, the player), and the shift lifecycle. The behaviour
# lives in child systems:
#
#   Spawner     seaweed, kelp, tourists, packages
#   Weather     storms, Happy Hour, music beds, ambience
#   Reputation  the 1-100 meter and what drags it down
#   Hud         readouts, safe area, pause panel
#   Shop        the supply shed
#   LevelPanel  the shift-complete summary
#
# Systems read shared state off `game` rather than owning it, which keeps the
# coupling one-directional and means no system needs to know about any other.
# =============================================================================

# Beach geometry lives in zones.gd -- see the note there on why.

const PLAYER_SCENE := preload("res://scenes/player.tscn")

# One full-screen painted background with the four zones baked in, at the exact
# band proportions below. This wins over the per-band tiles when set -- a single
# scene reads far better than four repeating textures, and this game is one fixed
# screen so there is nothing to scroll.
@export var tex_background: Texture2D

# Per-band tiles, used only when tex_background is empty. Drop a tile onto any of
# these in the Inspector (select the Game root in main.tscn) and that band tiles
# instead of drawing flat colour, so scenery can land one band at a time.
@export var tex_hotel: Texture2D
@export var tex_sand: Texture2D
@export var tex_shallows: Texture2D
@export var tex_deep: Texture2D
@export var tex_apron: Texture2D
@export var tex_bin: Texture2D
@export var tex_buoy: Texture2D

# Looping water frames from tools/make_water_frames.py. Two or more enables the
# animation; leave empty and the background's static water shows through.
@export var tex_water_frames: Array[Texture2D]
@export var water_fps := 7.0

# Per-shift music lives in levels.gd. This is only the fallback if a shift has
# no "music" key, or during free play after the last authored shift.
const DEFAULT_MUSIC := [
	"res://audio/Pixel_Paradise_2.mp3",
	"res://audio/Pixel_Paradise_3.mp3",
	"res://audio/Island_Bit_Reggae.mp3",
	"res://audio/Pixel_Paradise_4.mp3",
]
const MUSIC_DB := -8.0

# --- shared state -----------------------------------------------------------
var credits := 0
# Pay per unit of seaweed. A shift ends when its credit target is earned, so pay
# sets how LONG a shift runs -- without changing the credits a shift earns, so
# upgrade prices, shop pacing and the resort bonus stay in balance.
#   3 (6 with the Sorter): shifts ran ~10 minutes -- too long for mobile.
#   6 (12):  ~5 minutes, but the on-foot upgrades came too easily.
#   4.5 (9): split the difference -- a little more work for the reward.
# Fractional pay is carried as a float and rounded only when it is paid out at
# the skip, so no half-credits ever show.
const BASE_PAY := 4.5
const SORTER_PAY := 9.0
var price_per_unit := BASE_PAY
var storm_active := false
var happy_hour := false
var owned := {}

var level_index := 0
var credits_earned := 0        # this shift only; spending never sets it back
var shift_elapsed := 0.0       # seconds of play in the current shift
var best_rep := 100.0          # lowest the meter fell to -- how close it got
var shift_bonus := 0           # paid on completion, shown on the summary
var level_done := false

# The outer loop. A LEVEL is the four shifts; finishing shift 4 ends it and the
# player keeps one upgrade permanently. level_index (above) is the shift within
# the current level -- the naming predates levels and is kept to avoid churn.
var level := 1
var retained := {}
var level_failed := false
var free_play := false

# Taken at the start of each shift and restored on failure. Deliberately NOT the
# save file -- autosave overwrites that mid-shift, and the whole point is that
# losing sends you back to where the shift began, not to two minutes ago.
var _shift_start := {}

# Set by the menu BEFORE this node enters the tree: a new game skips the load.
var start_fresh := false

# Credits accrue continuously, so waiting for a purchase or a shift boundary to
# write meant a session could be killed by the OS and lose everything.
const AUTOSAVE_EVERY := 20.0
var _autosave_t := 0.0

var world: Node2D
var player: Player
var audio: GameAudio
var joystick: Joystick

var spawner: Spawner
var weather: Weather
var wind: Wind
var level_intro: LevelIntro

# The tutorial (new games only). The menu hands its music player over so the
# menu track keeps playing through it; the level's own music is held back until
# START SHIFT!.
var tutorial: Tutorial
var tutorial_done := false
var menu_music: AudioStreamPlayer = null
var menu_music_pos := 0.0
var _hold_music := false
var _staged: Array = []
var ferry: Ferry
var vip: VipZone
var vip_weight := 1.0
var night: Night

# ---- Adaptive difficulty ----------------------------------------------------
# Rather than hand-tuning each beach, the seaweed rate follows the player:
#   * FAIL a shift          -> the retry spawns 10% less.
#   * FINISH first try      -> the next shift spawns 6% more.
#   * FINISH after failing  -> no change: that shift was about right.
# The steps balance when roughly two shifts in three are finished first try,
# so a player settles where they mostly succeed but still fail now and then --
# never breezing through, never stuck failing again and again. Clamped, carried
# across levels (it measures the player, not the beach), and saved.
const ADAPT_FAIL := 0.90
const ADAPT_CLEAN := 1.06
const ADAPT_MIN := 0.6
const ADAPT_MAX := 1.5
var adapt := 1.0
var shift_fails := 0          # failed attempts at the current shift
var last_adapt := 0           # -1 eased after a fail, +1 raised after a clean run, 0 unchanged
var surf: Surf
var holbox: Holbox
var stream: Stream
var mat: SargassumMat
var hatch: Hatchlings
var crab: Crab
var parasail: Parasail
var gull: Seagull
var veracruz: Veracruz
var cozumel: Cozumel
var kayaks: Kayaks
var flamingos: Flamingos
var hurricane: Hurricane

# Turtle-nest enclosures (Akumal): solid obstacles on the sand, from the art.
var nests: Array = []         # of Rect2
var rep: Reputation
var hud: Hud
var shop: Shop
var level_panel: LevelPanel

var _tint: ColorRect
var _buoys: Node2D
var _water: Sprite2D
var _flash: ColorRect
var _grade: ColorRect
# Tracked in script rather than read back from the material: a uniform that has
# not been written yet returns null, and float(null) is a hard error.
var _grade_saturation := 1.0
var _grade_exposure := 0.0
var fx: WeatherFx
var _water_t := 0.0
var _water_frame := -1
var _shake_tw: Tween
var _bg_sprite: Sprite2D
var _bay: Area2D
var _bay_rect: RectangleShape2D
var _bay_bin: Sprite2D
var _sway_mat: ShaderMaterial
var _sway_phase := 0.0
var _sway_lean := 1.0
var _sway_amp := 1.4
const SWAY_SHADER := preload("res://shaders/sway.gdshader")


func _ready() -> void:
	randomize()
	# A 15-minute shift with no touch input during a long haul would otherwise
	# let the screen dim and sleep.
	DisplayServer.screen_set_keep_on(true)

	audio = GameAudio.new()
	add_child(audio)
	Settings.apply(Settings.load_all())

	_build_world()
	_build_ui()
	_build_systems()

	if not start_fresh:
		_load_progress()

	apply_beach()
	# A new game plays the tutorial before level 1's intro card, over the menu
	# music; the level's own music waits for START SHIFT!.
	var tut := level == 1 and level_index == 0 and not free_play and not tutorial_done
	_hold_music = tut
	begin_level()
	hud.refresh()
	_adopt_menu_music(tut)
	if tut:
		start_tutorial()
	elif level_index == 0 and not free_play:
		show_level_intro()


func _process(delta: float) -> void:
	spawner.tick(delta)
	weather.tick(delta)
	wind.tick(delta)
	ferry.tick(delta)
	night.tick(delta)
	surf.tick(delta)
	holbox.tick(delta)
	stream.tick(delta)
	mat.tick(delta)
	hatch.tick(delta)
	crab.tick(delta)
	parasail.tick(delta)
	gull.tick(delta)
	veracruz.tick(delta)
	cozumel.tick(delta)
	kayaks.tick(delta)
	flamingos.tick(delta)
	hurricane.tick(delta)
	if _sway_mat != null:
		var g: float = wind.gust_shape()
		_sway_phase = sway_step(_sway_phase, delta, g)
		_sway_mat.set_shader_parameter("phase", _sway_phase)
		_sway_mat.set_shader_parameter("gust", g)
		# The palms lean the way the wind blows -- including when it turns -- and
		# move with its strength: barely in a calm, fully from Veracruz-strength
		# wind upward. (Veracruz itself is always at full, so it is unchanged.)
		var calm := clampf(wind.strength / 30.0, 0.3, 1.0) if wind.active() else 0.3
		_sway_mat.set_shader_parameter("lean", _sway_lean * calm * (wind.dir if wind.active() else 1.0))
		_sway_mat.set_shader_parameter("amp", _sway_amp * calm)
	rep.tick(delta)
	_tick_water(delta)
	shift_elapsed += delta
	best_rep = minf(best_rep, rep.value)
	_check_level_failed()
	_check_level_complete()
	hud.refresh()

	_autosave_t += delta
	if _autosave_t >= AUTOSAVE_EVERY:
		_autosave_t = 0.0
		_save_progress()


# =============================================================================
# Construction
# =============================================================================

func _build_world() -> void:
	world = Node2D.new()
	add_child(world)

	if tex_background != null:
		_full_background()
	else:
		_band(0.0, Zones.HOTEL_BOTTOM, Color(0.36, 0.34, 0.40), tex_hotel)
		_band(Zones.HOTEL_BOTTOM, Zones.SHALLOW_TOP, Color(0.90, 0.82, 0.62), tex_sand)
		_band(Zones.SHALLOW_TOP, Zones.DEEP_TOP, Color(0.30, 0.62, 0.72), tex_shallows)
		_band(Zones.DEEP_TOP, Zones.VIEW_H, Color(0.10, 0.28, 0.48), tex_deep)

	_build_bay()
	_build_buoys()

	player = PLAYER_SCENE.instantiate()
	# Start the shift parked in the loading bay: it's the safe square, and it
	# means the first thing you do is drive out rather than hunt for the bin.
	player.position = Zones.BAY_POS
	player.in_safe_zone = true
	player.game = self
	player.shallow_y = Zones.SHALLOW_TOP
	player.deep_y = Zones.DEEP_TOP
	player.min_y = Zones.HOTEL_BOTTOM + 10.0
	player.max_y = Zones.DEEP_TOP - 12.0
	_apply_bay_bounds()
	world.add_child(player)


func _full_background() -> void:
	# Authored at the screen's own aspect, so this is a whole-number scale when
	# the art is 360x640 or an exact multiple of it. Anything else stretches and
	# loses the pixel grid -- see ART_MANIFEST.md for the required size.
	var bg := Sprite2D.new()
	_bg_sprite = bg
	bg.texture = tex_background
	bg.centered = false
	bg.z_index = -10
	var t := tex_background.get_size()
	if t.x > 0.0 and t.y > 0.0:
		bg.scale = Vector2(Zones.VIEW_W / t.x, Zones.VIEW_H / t.y)
	world.add_child(bg)
	_build_water()


func _build_water() -> void:
	# A strip of pre-displaced frames laid over the background's own water. Only
	# the strip is animated, so the frames stay small and the resort never moves.
	if tex_water_frames.size() < 2:
		return
	_water = Sprite2D.new()
	_water.centered = false
	_water.position = Vector2(0, Zones.WATER_TOP)
	_water.texture = tex_water_frames[0]
	_water.z_index = -9
	var t := tex_water_frames[0].get_size()
	if t.x > 0.0 and t.y > 0.0:
		_water.scale = Vector2(Zones.VIEW_W / t.x, (Zones.VIEW_H - Zones.WATER_TOP) / t.y)
	world.add_child(_water)
	_water_frame = 0


func _tick_water(delta: float) -> void:
	if _water == null:
		return
	# Storms churn the sea, so the same loop simply runs faster.
	var fps := water_fps * (1.7 if storm_active else 1.0)
	_water_t += delta * fps
	var i := int(_water_t) % tex_water_frames.size()
	if i != _water_frame:
		_water_frame = i
		_water.texture = tex_water_frames[i]


func _band(y0: float, y1: float, c: Color, tex: Texture2D = null) -> void:
	if tex != null:
		# STRETCH_TILE repeats the tile rather than scaling it, which is the
		# whole point -- a scaled tile loses its pixel grid immediately.
		var tr := TextureRect.new()
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_TILE
		tr.position = Vector2(0, y0)
		tr.size = Vector2(Zones.VIEW_W, y1 - y0)
		tr.z_index = -10
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		world.add_child(tr)
		return

	var r := ColorRect.new()
	r.position = Vector2(0, y0)
	r.size = Vector2(Zones.VIEW_W, y1 - y0)
	r.color = c
	r.z_index = -10
	world.add_child(r)


func _build_bay() -> void:
	var bay := Area2D.new()
	_bay = bay
	bay.position = Zones.BAY_POS

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Zones.BAY_SIZE
	shape.shape = rect
	_bay_rect = rect
	bay.add_child(shape)

	# The safe zone itself is invisible -- the background art already reads as a
	# service area, and a grey slab on top of it just looked like a placeholder.
	# Only draw an apron if real art is supplied for one.
	if tex_apron != null:
		var spr := Sprite2D.new()
		spr.texture = tex_apron
		spr.z_index = -5
		var t := tex_apron.get_size()
		if t.x > 0.0 and t.y > 0.0:
			spr.scale = Vector2(Zones.BAY_SIZE.x / t.x, Zones.BAY_SIZE.y / t.y)
		bay.add_child(spr)

	if tex_bin != null:
		var bin_spr := Sprite2D.new()
		bin_spr.texture = tex_bin
		_bay_bin = bin_spr
		bin_spr.position = Vector2(_bin_offset(), _bin_y())
		bin_spr.flip_h = _bin_flip()
		var bt := tex_bin.get_size()
		if bt.x > 0.0 and bt.y > 0.0:
			bin_spr.scale = Vector2(Zones.BIN_SIZE.x / bt.x, Zones.BIN_SIZE.y / bt.y)
		bay.add_child(bin_spr)
	else:
		var vis := ColorRect.new()
		vis.size = Zones.BIN_SIZE
		vis.position = Vector2(-Zones.BIN_SIZE.x / 2.0, -Zones.BIN_SIZE.y / 2.0 - 8.0)
		vis.color = Color(0.28, 0.26, 0.24)
		bay.add_child(vis)

	bay.body_entered.connect(_on_bay_entered)
	bay.body_exited.connect(_on_bay_exited)
	world.add_child(bay)


func _build_buoys() -> void:
	# A visible rope line marking where you are not allowed to go yet. Removing
	# it is most of what the Trawler Rig purchase should feel like.
	_buoys = Node2D.new()
	world.add_child(_buoys)

	var x := 14.0
	while x < Zones.VIEW_W:
		if tex_buoy != null:
			var spr := Sprite2D.new()
			spr.texture = tex_buoy
			spr.position = Vector2(x + 4.0, Zones.DEEP_TOP)
			var t := tex_buoy.get_size()
			if t.x > 0.0 and t.y > 0.0:
				spr.scale = Vector2(8.0 / t.x, 8.0 / t.y)
			_buoys.add_child(spr)
		else:
			var b := ColorRect.new()
			b.size = Vector2(8, 8)
			b.position = Vector2(x, Zones.DEEP_TOP - 4.0)
			b.color = Color(0.95, 0.85, 0.30)
			_buoys.add_child(b)
		x += 34.0


func _build_ui() -> void:
	# `base` holds things that must stay in raw viewport coordinates: the
	# fullscreen tint, and the joystick (whose drawing and touch handling both
	# work in screen space, so offsetting it would put the stick somewhere other
	# than your thumb). The Hud layer is the one that gets the safe-area offset.
	var base := CanvasLayer.new()
	base.layer = 0
	add_child(base)

	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.color = Weather.TINT_CLEAR
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(_tint)

	# Colour grade: drains the scene during Happy Hour. Must sit above the world
	# but below the HUD, so the readouts stay legible while the beach goes grey.
	_grade = ColorRect.new()
	_grade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grade_mat := ShaderMaterial.new()
	grade_mat.shader = load("res://shaders/desaturate.gdshader")
	grade_mat.set_shader_parameter("saturation", 1.0)
	grade_mat.set_shader_parameter("exposure", 0.0)
	_grade.material = grade_mat
	base.add_child(_grade)

	# Lightning flashes the whole screen, so it lives beside the tint rather than
	# in the world -- it must cover the HUD-free base layer edge to edge.
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(0.85, 0.92, 1.0, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_child(_flash)

	joystick = Joystick.new()
	base.add_child(joystick)
	player.joystick = joystick

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.build()

	# The level intro sits above everything, and keeps working while the game
	# is paused behind it.
	var intro_layer := CanvasLayer.new()
	intro_layer.layer = 40
	intro_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(intro_layer)
	level_intro = LevelIntro.new()
	level_intro.game = self
	intro_layer.add_child(level_intro)
	level_intro.build()

	var tut_layer := CanvasLayer.new()
	tut_layer.layer = 45
	tut_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(tut_layer)
	tutorial = Tutorial.new()
	tutorial.game = self
	tut_layer.add_child(tutorial)
	tutorial.build()

	shop = Shop.new()
	shop.game = self
	hud.add_child(shop)
	shop.build()

	level_panel = LevelPanel.new()
	level_panel.game = self
	hud.add_child(level_panel)
	level_panel.build()


func _build_systems() -> void:
	spawner = Spawner.new()
	spawner.game = self
	add_child(spawner)

	weather = Weather.new()
	weather.game = self
	add_child(weather)

	rep = Reputation.new()
	rep.game = self
	add_child(rep)

	fx = WeatherFx.new()
	fx.game = self
	world.add_child(fx)

	wind = Wind.new()
	wind.game = self
	add_child(wind)

	# Level props that live in the world: the VIP rope sits on the sand under
	# the sprites, the ferry out on the water.
	vip = VipZone.new()
	vip.game = self
	vip.z_index = -5
	world.add_child(vip)

	ferry = Ferry.new()
	ferry.game = self
	ferry.z_index = -2
	world.add_child(ferry)

	# Darkness sits above every sprite on the beach but below the weather, the
	# popups and the HUD -- so "+cr" and the strip at the bottom stay readable.
	night = Night.new()
	night.game = self
	night.z_index = 50
	world.add_child(night)

	# Surf sits on the water, under the sprites, so the worker stays readable
	# when a wave breaks over them.
	surf = Surf.new()
	surf.game = self
	surf.z_index = -1
	world.add_child(surf)

	holbox = Holbox.new()
	holbox.game = self
	world.add_child(holbox)

	# The stream's flow flecks and bridge sit on the sand, under the sprites.
	stream = Stream.new()
	stream.game = self
	stream.z_index = -2
	world.add_child(stream)

	# The sargassum mat floats on the water, under the sprites.
	mat = SargassumMat.new()
	mat.game = self
	mat.z_index = -2
	world.add_child(mat)

	# Hatchlings crawl over the sand, above the seaweed so they are never lost
	# under a pile.
	hatch = Hatchlings.new()
	hatch.game = self
	hatch.z_index = 2
	world.add_child(hatch)

	# The crab scuttles over the sand, above the seaweed, below the worker.
	crab = Crab.new()
	crab.game = self
	crab.z_index = 2
	world.add_child(crab)

	# The parasailer flies over everything on the beach.
	parasail = Parasail.new()
	parasail.game = self
	parasail.z_index = 55
	world.add_child(parasail)

	# The Pet Seagull: over the beach, under the night's darkness.
	gull = Seagull.new()
	gull.game = self
	gull.z_index = 45
	world.add_child(gull)

	# Level moments: Veracruz's gust fronts and cargo, Bacalar's kayak tour on
	# the water, and Cozumel's night events -- drawn ABOVE the darkness (z 50),
	# so its lights read as lights.
	veracruz = Veracruz.new()
	veracruz.game = self
	veracruz.z_index = 3
	world.add_child(veracruz)
	kayaks = Kayaks.new()
	kayaks.game = self
	kayaks.z_index = 1
	world.add_child(kayaks)
	flamingos = Flamingos.new()
	flamingos.game = self
	flamingos.z_index = 45
	world.add_child(flamingos)
	cozumel = Cozumel.new()
	cozumel.game = self
	cozumel.z_index = 52
	world.add_child(cozumel)

	hurricane = Hurricane.new()
	hurricane.game = self
	add_child(hurricane)


# =============================================================================
# Shift lifecycle
# =============================================================================

# How much busier the beach gets between the start of a shift and its end.
const SHIFT_RAMP := 1.75


func difficulty() -> float:
	# Spawn pressure for the current shift, RAMPED by how far through it you
	# are. A flat rate per shift was the problem: upgrades raise your throughput
	# but the beach stayed the same, so every shift got easier as it went on.
	#
	# Tying the ramp to credits earned means the pressure tracks the player's
	# own output -- buy a tractor and earn faster, and the beach fills faster to
	# match. It self-balances against whatever gear they have.
	var goal := maxf(1.0, float(shift_target()))
	var progress := clampf(float(credits_earned) / goal, 0.0, 1.0)
	return shift_difficulty() * lerpf(1.0, SHIFT_RAMP, progress)


func shift_difficulty() -> float:
	# The shift's own step on the curve, times the level: the value that rises
	# between shifts and between levels, but NOT during a shift. Wash speed and
	# the seaweed cap follow this rather than difficulty(), so shift 1 of level
	# 1 -- the balance the player has confirmed feels right -- is untouched.
	var base := maxf(0.1, float(current_level().get("difficulty", 1.0)))
	return base * level_scale()


# Share of the difficulty curve that goes into drift speed. Drift matters as much
# as spawn rate: with a population cap in place, faster drift is what puts more
# of that population on the SAND rather than floating harmlessly offshore.
const DRIFT_SHARE := 0.45
# Extra clumps allowed on screen per unit of difficulty above 1.
const CAP_PER_DIFFICULTY := 7.0


func wash_speed() -> float:
	return 1.0 + (shift_difficulty() - 1.0) * DRIFT_SHARE


func seaweed_cap() -> int:
	# The population cap has to rise with the curve. At a fixed 34, later
	# shifts filled it and every further increase in spawn rate did nothing --
	# which is why shifts 2 to 4 felt no harder than shift 1.
	return int(Spawner.SEAWEED_MAX + CAP_PER_DIFFICULTY * (shift_difficulty() - 1.0))


func mess_full() -> float:
	# How much shoreline mess drags reputation to zero. It grows with the
	# seaweed cap: at a fixed 28 units, later shifts allowed 45-65 clumps on the
	# beach while still firing you at 28 -- the beach's own capacity was past
	# the firing line before the player did anything wrong. Shift 1 of level 1
	# (cap 34) is unchanged.
	return Reputation.MESS_FULL * float(seaweed_cap()) / float(Spawner.SEAWEED_MAX)


func spawn_scale() -> float:
	# A level can arrive with less seaweed, across all its shifts. Holbox uses
	# it: collecting from all 360 degrees of an island is more walking than
	# working one straight beach, even with the skip in the middle. On top of
	# that sits the adaptive multiplier, which follows the player.
	var h := hurricane.spawn_factor() if hurricane != null else 1.0
	return maxf(0.1, float(Beaches.for_level(level).get("spawn_scale", 1.0))) * adapt * h


func cap_scale() -> float:
	# How far below seaweed_cap() the spawner stops: the beach's own scale and
	# the adaptive easing. Neither can RAISE the cap. Once a shift is busy the
	# beach sits at its cap, so a factor applied only to the spawn rate (as
	# both were) changed nothing exactly when it mattered.
	var beach := minf(1.0, float(Beaches.for_level(level).get("spawn_scale", 1.0)))
	return maxf(0.1, beach * minf(adapt, 1.0))


func in_nest(p: Vector2, pad: float = 0.0) -> bool:
	for r in nests:
		if (r as Rect2).grow(pad).has_point(p):
			return true
	return false


func push_out_of_nests(p: Vector2, pad: float) -> Vector2:
	# Out of any enclosure by the shortest way -- so the worker slides along
	# the rope instead of being thrown to the far side.
	for r in nests:
		var g := (r as Rect2).grow(pad)
		if not g.has_point(p):
			continue
		var outs := [Vector2(g.position.x - 0.5, p.y), Vector2(g.end.x + 0.5, p.y),
			Vector2(p.x, g.position.y - 0.5), Vector2(p.x, g.end.y + 0.5)]
		var best: Vector2 = outs[0]
		for q in outs:
			if p.distance_to(q) < p.distance_to(best):
				best = q
		p = best
	return p


func sidestep_nests(p: Vector2, pad: float) -> Vector2:
	# Tourists walk down the beach and step AROUND a nest rather than over it:
	# sideways only, so they keep heading for the water.
	for r in nests:
		var g := (r as Rect2).grow(pad)
		if g.has_point(p):
			p.x = g.position.x - 0.5 if p.x < g.get_center().x else g.end.x + 0.5
	return p


func adapt_after_fail() -> void:
	shift_fails += 1
	adapt = maxf(ADAPT_MIN, adapt * float(beginner().get("fail_ease", ADAPT_FAIL)))
	last_adapt = -1


func adapt_after_finish() -> void:
	if shift_fails == 0:
		adapt = minf(ADAPT_MAX, adapt * ADAPT_CLEAN)
		last_adapt = 1
	else:
		last_adapt = 0
	shift_fails = 0           # the next shift is a fresh start


# A hurricane's storm runs for most of the shift, not 22 seconds, so it uses
# shift 1's storm spawning (the mildest) on every shift. Its wind, rain, surf
# and darkness are the pressure. At each shift's own storm rate -- tuned for a
# short burst -- the bot lost every Tulum shift after the first.
const HURRICANE_STORM_MULT := 0.70
const HURRICANE_STORM_BURST := 1


# On foot with neither the Rain Jacket nor the Backpack, a storm is gentler:
# half the floating seaweed rides the surge in (the rest drifts at its normal
# pace) and half the extra storm seaweed arrives. Without either, the worker
# moves at 40% speed carrying 5 -- the first storm of level 1 was lost on 5 of
# 6 bot runs, and by players. Either upgrade restores full storms.
const GENTLE_STORM := 0.5


func gentle_storm() -> bool:
	if not beginner().is_empty():
		return true
	return not owned.has("jacket") and not owned.has("backpack")


func beginner() -> Dictionary:
	# The first level's forgiving settings (see Cancun in beaches.gd); empty
	# everywhere else.
	return Beaches.for_level(level).get("beginner", {})


func storm_every() -> float:
	return float(beginner().get("storm_every", Weather.STORM_EVERY))


func rep_fall() -> float:
	return Reputation.REP_FALL * float(beginner().get("rep_fall", 1.0))


func fail_grace() -> float:
	return float(beginner().get("fail_grace", Reputation.FAIL_GRACE))


func storm_mult() -> float:
	var m := maxf(0.2, float(current_level().get("storm_mult", 0.35)))
	if hurricane != null and hurricane.active:
		m = maxf(m, HURRICANE_STORM_MULT)
	return m


func storm_burst() -> int:
	var b := maxi(1, int(current_level().get("storm_burst", 3)))
	if hurricane != null and hurricane.active:
		b = mini(b, HURRICANE_STORM_BURST)
	return b


func rot_scale() -> float:
	# A beach can set a floor (Tulum): rot never faster than that there.
	var s := float(current_level().get("rot_scale", 1.0))
	return maxf(0.2, maxf(s, float(Beaches.for_level(level).get("rot_floor", 0.0))))


func shop_tier() -> int:
	return int(current_level().get("shop_tier", 3))


# Every level is harder than the last, applied on top of the per-shift base and
# the within-shift ramp. Gentle, because the player is also stronger: by level
# 10 they start with nine upgrades already owned.
const LEVEL_STEP := 0.07


func level_scale() -> float:
	return 1.0 + LEVEL_STEP * float(level - 1)


func retain_tier() -> int:
	# The lowest tier that still has something left to retain. Tier 1 goes
	# first, then the tractor tier, then deep water.
	for t in [1, 2, 3]:
		for up in Upgrades.LIST:
			if int(up["tier"]) == t and Upgrades.keepable(up) and not retained.has(String(up["id"])):
				return t
	return 0


func retain_options() -> Array:
	# Upgrades that can be kept at the end of this level. Restricted to the
	# current retain tier, and to ones whose prerequisite is already retained:
	# keeping Sand Tires without a tractor would be a permanent upgrade that
	# does literally nothing.
	var t := retain_tier()
	var out := []
	if t == 0:
		return out
	for up in Upgrades.LIST:
		var id := String(up["id"])
		if int(up["tier"]) != t or retained.has(id) or not Upgrades.keepable(up):
			continue
		var needs := String(up["needs"])
		if needs != "" and not retained.has(needs):
			continue
		out.append(id)
	return out


# Kept gear makes the early shifts of later levels go by fast: with the tractor
# and the Baling Sorter retained, shift 1 of levels 7-10 lasted ~2 minutes in
# the bot playtest against ~5 in levels 1-5. Each retained upgrade that the
# shift's own shop would not normally have given you yet raises the target, so
# shifts stay near five minutes. Factors per shift 1-4; shifts 3-4 are played
# with the full kit whatever you kept, so they are unaffected.
#   sorter:  doubles pay, so shift 1 needs double; in shift 2 it saves the
#            1200 it would have cost and pays double from the start.
#   tractor: capacity 20 and more speed on what is otherwise an on-foot shift.
const RETAINED_TARGET := {
	"tractor": [1.25, 1.0, 1.0, 1.0],
	"sorter": [2.0, 1.3, 1.0, 1.0],
}


func shift_target() -> int:
	var t := float(current_level().get("credits", 1500))
	var i: int = mini(level_index, Levels.LIST.size() - 1)
	for id in RETAINED_TARGET:
		if retained.has(id):
			t *= float(RETAINED_TARGET[id][i])
	# Round to 50 so the HUD target reads as a deliberate number.
	return int(round(t / 50.0)) * 50


func current_level() -> Dictionary:
	var idx: int = min(level_index, Levels.LIST.size() - 1)
	var lv: Dictionary = Levels.LIST[idx]
	return lv


func begin_level() -> void:
	var lv := current_level()

	_shift_start = {
		"credits": credits,
		"owned": owned.duplicate(),
		"level_index": level_index,
	}

	credits_earned = 0
	shift_elapsed = 0.0
	best_rep = 100.0
	level_done = false
	level_failed = false
	rep.reset(float(lv["rep"]))

	# Apply the player's appearance unconditionally. This used to run only from
	# apply_upgrade(), so a brand-new game -- which owns nothing and therefore
	# never calls it -- kept the placeholder rectangle instead of the sprite.
	_recompute_carry()

	# Wipe the beach so a new shift starts genuinely clean.
	for c in world.get_children():
		if c is Seaweed or c is Tourist or c is Package:
			c.queue_free()

	weather.reset()
	spawner.reset()
	# Every shift of the finale starts calm; the hurricane builds again.
	if hurricane != null:
		hurricane.configure(Beaches.for_level(level))
	# Once a level, in its chosen shift.
	if crab != null:
		crab.configure(Beaches.for_level(level), level_index)
	if parasail != null:
		parasail.configure(Beaches.for_level(level), level_index)
	# Level moments start over every shift.
	if veracruz != null:
		veracruz.configure(Beaches.for_level(level))
		cozumel.configure(Beaches.for_level(level))
		kayaks.configure(Beaches.for_level(level))
		flamingos.configure(Beaches.for_level(level), level_index)
	if gull != null and gull.enabled:
		gull.reset()

	if audio != null and not _hold_music:
		_play_level_music()

	player.position = Zones.BAY_POS
	player.in_safe_zone = true
	player.carried = 0
	player.carried_value = 0

	for i in 6:
		spawner.spawn_seaweed(1)

	# Write immediately: otherwise a player who starts a shift and quits before
	# buying anything leaves no save at all, and Continue stays greyed out.
	_save_progress()

	if not free_play:
		popup(String(lv["name"]), Vector2(180, 320), Color(1.0, 0.9, 0.5))


func _check_level_failed() -> void:
	if level_done or level_failed or free_play:
		return
	# A dip to zero starts a countdown rather than ending the run. One storm
	# surge should be survivable if the player reacts.
	if rep.zero_time < fail_grace():
		return
	fail_shift()


func fail_shift() -> void:
	level_failed = true
	adapt_after_fail()
	_save_progress()
	joystick.active = false
	shop.visible = false
	get_tree().paused = true
	level_panel.show_failure()
	sfx("hit", 0.7, -2.0)


func retry_shift() -> void:
	if audio != null:
		audio.pause_music(false)
	# Roll all the way back to how the shift started. Credits earned and any
	# upgrades bought during the failed attempt are gone.
	credits = int(_shift_start.get("credits", 0))
	owned = (_shift_start.get("owned", {}) as Dictionary).duplicate()
	level_index = int(_shift_start.get("level_index", level_index))

	_reset_player_stats()
	for up in Upgrades.LIST:
		if owned.has(String(up["id"])):
			apply_upgrade(String(up["id"]))
	_recompute_carry()

	level_panel.visible = false
	get_tree().paused = false
	joystick.active = true
	level_failed = false
	begin_level()
	_save_progress()


func _reset_player_stats() -> void:
	price_per_unit = BASE_PAY
	player.gather_interval = 0.7
	player.base_speed = 130.0
	player.speed_mult = 1.0
	player.reach = Player.BASE_REACH
	player.has_rain_jacket = false
	player.has_waders = false
	player.has_sand_tires = false
	player.on_vehicle = false
	player.can_enter_deep = false
	if gull != null:
		gull.set_enabled(false)
	player.max_y = Zones.DEEP_TOP - 12.0
	if _buoys != null:
		_buoys.modulate = Color(1, 1, 1, 1)


func _check_level_complete() -> void:
	if level_done or free_play:
		return
	# ONE goal: the shift's credit target, counting credits EARNED this shift --
	# spending on upgrades never sets it back, and skipping upgrades is no
	# shortcut, since without them you simply earn more slowly.
	#
	# There used to be a second condition: reputation held above a target
	# continuously for 90-150s, drawn as a green bar over the yellow one. A
	# single dip reset it to zero, so a shift could sail past its credit target
	# and not end, for reasons the player couldn't see. Reputation still
	# matters -- hit zero and you're fired, and a clean beach earns a bigger
	# resort bonus -- and the firing countdown is visible, tense and fair.
	if credits_earned < shift_target():
		return
	finish_level()


# Fraction of the shift's credit target paid as a bonus for a perfect shift.
const REP_BONUS_MAX := 0.30


func reputation_bonus() -> int:
	# Rewards HOW the shift went, not just that it ended. Scaled by the lowest
	# the meter fell: never slipping pays the full bonus, bottoming out pays
	# nothing. Framed as a reward on top rather than a cut to what you keep --
	# the goal is to make playing well feel good, not playing badly feel bad.
	var quality := clampf(best_rep / 100.0, 0.0, 1.0)
	return int(round(float(shift_target()) * REP_BONUS_MAX * quality))


func finish_level() -> void:
	level_done = true
	adapt_after_finish()
	shift_bonus = reputation_bonus()
	credits += shift_bonus
	joystick.active = false
	shop.visible = false
	_save_progress()
	sfx("complete")
	# The completion sting is a 15s celebration piece. Everything musical stops
	# for it -- the playlist AND any storm or Happy Hour bed.
	if audio != null:
		audio.pause_music(true)

	# Let the moment land in the WORLD before the UI covers it: a punch of
	# shake and a banner over the beach, then the panel a beat later. Showing
	# the panel instantly makes finishing a shift feel like a form submission.
	shake(6.0, 0.4)
	popup("SHIFT COMPLETE", Vector2(180, 300), Color(1.0, 0.92, 0.55))
	var t := get_tree().create_timer(0.85, true, false, true)
	t.timeout.connect(func():
		if not level_done:
			return
		get_tree().paused = true
		level_panel.show_summary(level_index + 1 >= Levels.LIST.size()))


func next_shift() -> void:
	if audio != null:
		audio.pause_music(false)
	level_panel.visible = false
	get_tree().paused = false
	joystick.active = true
	level_done = false

	if level_index + 1 < Levels.LIST.size():
		level_index += 1
		begin_level()
		_save_progress()
		return

	# End of the level. If there is anything left to retain, the player picks
	# one; otherwise every upgrade is permanent and the campaign is complete.
	var options := retain_options()
	if options.is_empty():
		free_play = true
		_save_progress()
		return
	get_tree().paused = true
	joystick.active = false
	level_done = true
	level_panel.show_retain(options)


static func sway_step(phase: float, delta: float, gust: float) -> float:
	# Advance the sway's phase at a speed that rises with the gust, wrapped to
	# 0..2pi so the shader never sees a large number. See sway.gdshader for why.
	return fposmod(phase + delta * (1.8 + 2.6 * gust), TAU)


static func make_sway_material(beach: Dictionary) -> ShaderMaterial:
	var sway: Dictionary = beach.get("sway", {})
	var path := String(sway.get("mask", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var mat := ShaderMaterial.new()
	mat.shader = SWAY_SHADER
	mat.set_shader_parameter("sway_mask", load(path))
	mat.set_shader_parameter("amp", float(sway.get("amp", 1.4)))
	mat.set_shader_parameter("lean", float(sway.get("lean", 1.0)))
	return mat


func _bay_on_left() -> bool:
	return Zones.BAY_POS.x < Zones.VIEW_W / 2.0


func _bin_offset() -> float:
	var over = Beaches.for_level(level).get("bin_offset", null)
	if over != null:
		return float(over)
	return 0.0


func _bin_y() -> float:
	# Where the skip is DRAWN, up or down from the bay centre. The drop-off zone
	# itself does not move; this only seats the sprite on the art.
	# The -8 keeps the bigger skip's base where the old, smaller one sat.
	return float(Beaches.for_level(level).get("bin_y", 0.0)) - 8.0


func _bin_flip() -> bool:
	# The art faces left; a level can turn it to face right.
	return bool(Beaches.for_level(level).get("bin_flip", false))


func _apply_bay_bounds() -> void:
	# The driveway: across the bay's width, the player may walk further up the
	# screen than anywhere else, into the hotel band where the skip sits. The
	# INNER edge (facing the rest of the beach) is inset slightly; the outer
	# edge runs to the wall, as the original right-hand bay always did.
	if player == null:
		return
	var left := Zones.BAY_POS.x - Zones.BAY_SIZE.x / 2.0
	var right := Zones.BAY_POS.x + Zones.BAY_SIZE.x / 2.0
	if _bay_on_left():
		player.bay_x0 = left - 10.0
		player.bay_x1 = right - 6.0
	else:
		player.bay_x0 = left + 6.0
		player.bay_x1 = right + 10.0
	player.bay_min_y = Zones.BAY_POS.y - Zones.BAY_SIZE.y / 2.0 + 18.0


func apply_beach() -> void:
	# Move the world onto this level's beach. Everything that was built ONCE
	# from the zone values has to be refreshed here: the background, the
	# animated water strip, the buoy line, the bay, and the player's bounds.
	# Anything read at the moment of use (spawn bands, tourist routes, where
	# seaweed beaches) picks the new values up on its own.
	var beach := Beaches.for_level(level)
	Zones.apply(beach)
	if wind != null:
		wind.configure(beach)
	if ferry != null:
		ferry.configure(beach)
	if night != null:
		night.configure(beach)
	if surf != null:
		surf.configure(beach)
	if holbox != null:
		holbox.configure(beach)
	if stream != null:
		stream.configure(beach)
	if mat != null:
		mat.configure(beach)
	nests.clear()
	for n in beach.get("nests", []):
		nests.append(Rect2(float(n[0]), float(n[1]), float(n[2]) - float(n[0]), float(n[3]) - float(n[1])))
	if hatch != null:
		hatch.configure(beach)
	# Last: the hurricane takes over the wind, storm and surf it was given.
	if hurricane != null:
		hurricane.configure(beach)
	# The VIP frontage runs from the club down to the waterline, so its height
	# comes from this beach's zones rather than being fixed.
	var v: Dictionary = beach.get("vip", {})
	vip_weight = float(v.get("weight", 1.0))
	if vip != null:
		if v.is_empty():
			vip.configure(Rect2())
		else:
			var x0 := float(v.get("x0", 0.0))
			var x1 := float(v.get("x1", 0.0))
			vip.configure(Rect2(x0, Zones.HOTEL_BOTTOM, x1 - x0, Zones.SHALLOW_TOP - Zones.HOTEL_BOTTOM))

	# Painted foliage that moves: a shader on the background, only on beaches
	# that ship a sway mask. Everywhere else the background has no material.
	_sway_mat = make_sway_material(beach)
	_sway_lean = float(beach.get("sway", {}).get("lean", 1.0))
	_sway_amp = float(beach.get("sway", {}).get("amp", 1.4))
	if _bg_sprite != null:
		_bg_sprite.material = _sway_mat

	var bg_path := String(beach.get("background", ""))
	if _bg_sprite != null and bg_path != "" and ResourceLoader.exists(bg_path):
		var tex: Texture2D = load(bg_path)
		_bg_sprite.texture = tex
		var t := tex.get_size()
		if t.x > 0.0 and t.y > 0.0:
			_bg_sprite.scale = Vector2(Zones.VIEW_W / t.x, Zones.VIEW_H / t.y)

	var pattern := String(beach.get("water", ""))
	if _water != null:
		_water.visible = pattern != ""
	if pattern != "":
		var frames: Array[Texture2D] = []
		for i in 8:
			var path := pattern % i
			if ResourceLoader.exists(path):
				frames.append(load(path))
		if frames.size() >= 2:
			tex_water_frames = frames
			_water_frame = -1
			if _water != null:
				_water.texture = frames[0]
				_water.position = Vector2(0, Zones.WATER_TOP)
				var ft := frames[0].get_size()
				_water.scale = Vector2(Zones.VIEW_W / ft.x,
					(Zones.VIEW_H - Zones.WATER_TOP) / ft.y)

	if _buoys != null:
		var kids := _buoys.get_children()
		for i in kids.size():
			var b: CanvasItem = kids[i]
			if not b.has_meta("home_x"):
				b.set_meta("home_x", b.position.x)
			b.visible = true
			if Zones.RADIAL:
				# A ring of buoys round the island, at the deep line.
				var a := float(i) / float(kids.size()) * TAU
				var at := Zones.CENTER + Vector2(cos(a), sin(a)) * Zones.DEEP_TOP
				b.position = at - (Vector2(4, 4) if b is ColorRect else Vector2.ZERO)
				b.visible = at.x > 4.0 and at.x < Zones.VIEW_W - 4.0 and at.y > 4.0 and at.y < Zones.VIEW_H - 4.0
			elif b is Sprite2D:
				b.position = Vector2(float(b.get_meta("home_x")), Zones.DEEP_TOP)
			elif b is ColorRect:
				b.position = Vector2(float(b.get_meta("home_x")), Zones.DEEP_TOP - 4.0)

	# The bay can move between levels -- Playa del Carmen puts it on the left.
	if _bay != null:
		_bay.position = Zones.BAY_POS
		if _bay_rect != null:
			_bay_rect.size = Zones.BAY_SIZE
		if _bay_bin != null:
			_bay_bin.position = Vector2(_bin_offset(), _bin_y())
			_bay_bin.flip_h = _bin_flip()
	_apply_bay_bounds()

	if player != null:
		player.shallow_y = Zones.SHALLOW_TOP
		player.deep_y = Zones.DEEP_TOP
		player.min_y = Zones.HOTEL_BOTTOM + 10.0
		player.max_y = (Zones.DEPTH_MAX - 14.0) if player.can_enter_deep \
			else (Zones.DEEP_TOP - 12.0)


func retain_and_advance(id: String) -> void:
	if audio != null:
		audio.pause_music(false)
	# Keep one upgrade for good, then start the next level from scratch apart
	# from everything retained so far.
	#
	# Order matters here. owned, credits and level_index are all reset BEFORE
	# begin_level(), because begin_level() is what takes the failure-retry
	# snapshot. If it ran first, a failed shift 1 of the new level would
	# restore the old level's full kit.
	retained[id] = true
	level += 1
	credits = 0
	level_index = 0
	owned = retained.duplicate()

	_reset_player_stats()
	for up in Upgrades.LIST:
		if owned.has(String(up["id"])):
			apply_upgrade(String(up["id"]))
	_recompute_carry()

	level_panel.visible = false
	get_tree().paused = false
	joystick.active = true
	level_done = false
	apply_beach()
	begin_level()
	_save_progress()
	show_level_intro()


func in_vip(pos: Vector2) -> bool:
	return vip != null and vip.visible and vip.rect.has_point(pos)


func vip_units() -> int:
	var n := 0
	for c in world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if not sw.kelp and not sw.drifting and in_vip(sw.position):
				n += sw.units
	return n


func _play_level_music() -> void:
	# A level's own soundtrack wins over the shift's. Each location should
	# sound like somewhere new -- tracks that did not play on earlier beaches.
	var beach := Beaches.for_level(level)
	var lv := current_level()
	audio.play_playlist(beach.get("music", lv.get("music", DEFAULT_MUSIC)), MUSIC_DB)


func _adopt_menu_music(keep: bool) -> void:
	# The menu's music player, handed over rather than faded. An AudioStreamPlayer
	# stops when it leaves the scene tree, so it resumes from where the menu had
	# it. Kept playing through the tutorial (and through the pause the tutorial
	# puts the game in); otherwise faded out under the level's music, as before.
	if menu_music == null:
		return
	add_child(menu_music)
	menu_music.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_music.play(menu_music_pos)
	if not keep:
		_fade_menu_music(0.5)


func _fade_menu_music(time: float) -> void:
	if menu_music == null or not is_instance_valid(menu_music):
		return
	var m := menu_music
	menu_music = null
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(m, "volume_db", m.volume_db - 40.0, time)
	tw.tween_callback(m.queue_free)


func start_tutorial() -> void:
	get_tree().paused = true
	joystick.active = false
	_stage_tutorial()
	tutorial.start(_tutorial_steps())


func finish_tutorial() -> void:
	# START SHIFT! (or SKIP): the level's music takes over from the menu's, and
	# level 1's intro card appears.
	tutorial_done = true
	tutorial.visible = false
	_unstage_tutorial()
	_hold_music = false
	if audio != null:
		_play_level_music()
	_fade_menu_music(0.9)
	_save_progress()
	show_level_intro()


func _stage_tutorial() -> void:
	# A frozen scene for the steps to point at: a big pile, a rotting pile, a
	# couple of small ones, a tourist, and the worker mid-beach.
	_staged.clear()
	var big: Seaweed = spawner._add_seaweed(Vector2(205, Zones.SHORE_Y - 14.0), 8, false, false)
	var rot: Seaweed = spawner._add_seaweed(Vector2(70, Zones.SHORE_Y - 12.0), 4, false, false)
	_staged.append(big)
	_staged.append(rot)
	_staged.append(spawner._add_seaweed(Vector2(300, Zones.SHORE_Y - 10.0), 1, false, false))
	_staged.append(spawner._add_seaweed(Vector2(140, Zones.HOTEL_BOTTOM + 90.0), 1, false, false))
	rot.age = 1.0e4
	rot._refresh()
	_staged.append(spawner.make_tourist(Vector2(262, Zones.HOTEL_BOTTOM + 90.0), Zones.SHALLOW_TOP + 40.0, false))
	player.position = Vector2(175, Zones.HOTEL_BOTTOM + 150.0)
	player.in_safe_zone = false


func _unstage_tutorial() -> void:
	for n in _staged:
		if is_instance_valid(n):
			n.queue_free()
	_staged.clear()
	player.position = Zones.BAY_POS
	player.in_safe_zone = true


func _tutorial_steps() -> Array:
	var ring := func(c: Vector2, r: float) -> Dictionary:
		return {"rect": Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), "circle": true}
	var box := func(ctl: Control, g: float) -> Dictionary:
		return {"rect": ctl.get_global_rect().grow(g), "circle": false}
	var big: Seaweed = _staged[0]
	var rot: Seaweed = _staged[1]
	var who: Node2D = _staged[4]
	return [
		{"title": "KEEP THE BEACH CLEAN", "top": true,
			"body": "Rake up seaweed and cash it in. Fill this bar to finish the shift.",
			"holes": [box.call(hud._goal_bg, 4.0)]},
		{"title": "MOVE", "top": true, "joystick": true,
			"body": "Touch anywhere and drag to walk. Let go to stop.",
			"holes": [ring.call(Vector2(90, 500), 58.0)]},
		{"title": "RAKE IT UP", "top": true,
			"body": "Stand on a pile to rake it in. Bigger piles take longer -- and are worth more.",
			"holes": [ring.call(big.position, 34.0)]},
		{"title": "WATCH YOUR LOAD", "top": false,
			"body": "You can only carry so much. When it's full, you can't pick up any more.",
			"holes": [box.call(hud._lbl_carry, 3.0)]},
		{"title": "CASH IN AT THE SKIP", "top": false,
			"body": "Walk into the bay to tip your load and get paid.",
			"holes": [ring.call(_bay_bin.global_position, 40.0)]},
		{"title": "DON'T LET IT ROT", "top": true,
			"body": "Seaweed left out rots, and your reputation drops. Hit zero and you're fired.",
			"holes": [ring.call(rot.position, 30.0), box.call(hud._rep_bg, 4.0)]},
		{"title": "MIND THE TOURISTS", "top": false,
			"body": "Bump into one and you'll drop your whole load on the sand.",
			"holes": [ring.call(who.position, 32.0)]},
		{"title": "UPGRADE IN THE SHOP", "top": false,
			"body": "Tap SHOP to spend credits: faster rakes, bigger loads -- and later, a tractor.",
			"holes": [box.call(hud._shop_btn, 3.0)]},
	]


func show_level_intro() -> void:
	# Holds the game until the player chooses to start. Not shown when a failed
	# shift is retried -- only when a level genuinely begins.
	if level_intro == null:
		return
	get_tree().paused = true
	joystick.active = false
	level_intro.show_for(level)


func start_from_intro() -> void:
	level_intro.visible = false
	get_tree().paused = false
	joystick.active = true


# =============================================================================
# Shop and upgrades
# =============================================================================

func toggle_shop() -> void:
	if level_done or level_failed:
		return
	var opening := not shop.visible
	shop.visible = opening
	if opening:
		UiTheme.present(shop)
	joystick.active = not opening
	get_tree().paused = opening
	if opening:
		shop.rebuild()


func buy(id: String) -> void:
	for up in Upgrades.LIST:
		if String(up["id"]) != id:
			continue
		var cost := int(up["cost"])
		if credits < cost or owned.has(id):
			return
		# Prerequisites were only ever enforced by the shop greying the button
		# out. Check them here too, so the rule holds wherever buy() is called.
		var needs: String = up["needs"]
		if needs != "" and not owned.has(needs):
			return
		credits -= cost
		owned[id] = true
		apply_upgrade(id)
		sfx("purchase")
		weather.on_upgrade_bought()
		_save_progress()
		return


func apply_upgrade(id: String) -> void:
	match id:
		"rake2":
			player.gather_interval = 0.35
			player.reach = 18.0
		"jacket":
			player.has_rain_jacket = true
		"waders":
			player.has_waders = true
		"tractor":
			# Only slightly quicker than on foot. The tractor's real value is
			# capacity and reach -- if it also doubled your speed, every tier-1
			# upgrade became pointless the moment you bought it.
			player.base_speed = 165.0
			player.reach = 22.0
		"sand_tires":
			player.has_sand_tires = true
		"seagull":
			if gull != null:
				gull.set_enabled(true)
		"sorter":
			price_per_unit = SORTER_PAY
		"diesel":
			player.speed_mult = 1.4
		"trawler":
			player.can_enter_deep = true
			player.max_y = Zones.DEPTH_MAX - 14.0
			if _buoys != null:
				_buoys.modulate = Color(1, 1, 1, 0.25)

	# Capacity and appearance are DERIVED from what you own rather than set by
	# each upgrade. Otherwise buying the tier-1 backpack after the tractor would
	# quietly shrink your capacity from 20 back down to 10.
	_recompute_carry()


func _recompute_carry() -> void:
	# A null slot means the PNG did not import -- usually a stale .godot folder
	# after unzipping over an existing project. Silently drawing the placeholder
	# rectangle made that look like a code bug, so say so out loud.
	if player.tex_bare.is_empty():
		push_warning("Player textures are not assigned. If you unzipped over an "
			+ "existing project, delete the .godot folder and reopen so Godot "
			+ "re-imports assets/sprites/.")

	# On-foot only: the jacket is a tier-1 upgrade and the vehicles have their
	# own art, so a driver never wears it.
	player.on_vehicle = owned.has("tractor")
	player.set_jacket(owned.has("jacket"))

	var cap := 5
	if owned.has("backpack"):
		cap = 10
	if owned.has("tractor"):
		cap = 20
	if owned.has("hopper"):
		cap = 100
	player.capacity = cap
	player.carried = min(player.carried, cap)

	# Five visual states, strictly ordered. The backpack is gated behind the rake
	# in upgrades.gd, so this chain can never show gear out of sequence.
	# set_body(hitbox, artwork, ...) -- the hitboxes are unchanged from the
	# tuning that already felt right; only the drawn size grew.
	if owned.has("hopper"):
		player.set_body(Vector2(32, 48), Vector2(60, 84),
			Color(0.80, 0.40, 0.22), player.tex_hopper, player.tex_hopper_back,
			player.tex_hopper_wade, player.tex_hopper_wade_back)
	elif owned.has("tractor"):
		player.set_body(Vector2(32, 32), Vector2(60, 60),
			Color(0.85, 0.45, 0.25), player.tex_tractor, player.tex_tractor_back,
			player.tex_tractor_wade, player.tex_tractor_wade_back)
	elif owned.has("backpack"):
		player.set_body(Vector2(24, 32), Vector2(48, 60),
			Color(0.92, 0.70, 0.30), player.tex_backpack, player.tex_backpack_back,
			player.tex_backpack_wade, player.tex_backpack_wade_back)
	elif owned.has("rake2"):
		player.set_body(Vector2(24, 24), Vector2(48, 48),
			Color(0.95, 0.78, 0.35), player.tex_rake, player.tex_rake_back,
			player.tex_rake_wade, player.tex_rake_wade_back)
	else:
		# Bare hands. Slow and short-reach -- which is what makes the 60-credit
		# rake the first purchase that visibly changes something.
		player.set_body(Vector2(24, 24), Vector2(48, 48),
			Color(0.88, 0.72, 0.42), player.tex_bare, player.tex_bare_back,
			player.tex_bare_wade, player.tex_bare_wade_back)


func reset_all_progress() -> void:
	SaveGame.wipe()
	credits = 0
	owned.clear()
	level_index = 0
	free_play = false
	_reset_player_stats()
	_recompute_carry()
	toggle_shop()
	begin_level()


# =============================================================================
# Save
# =============================================================================

func _load_progress() -> void:
	var data := SaveGame.load_data()
	if data.is_empty():
		return

	credits = int(data.get("credits", 0))
	level_index = int(data.get("level_index", 0))
	free_play = bool(data.get("free_play", false))
	level_index = clampi(level_index, 0, Levels.LIST.size() - 1)
	level = maxi(1, int(data.get("level", 1)))
	adapt = clampf(float(data.get("adapt", 1.0)), ADAPT_MIN, ADAPT_MAX)
	tutorial_done = bool(data.get("tutorial_done", false))
	shift_fails = maxi(0, int(data.get("shift_fails", 0)))
	var saved_retained = data.get("retained", {})
	if typeof(saved_retained) == TYPE_DICTIONARY:
		retained = saved_retained.duplicate()

	# Re-apply every owned upgrade so derived stats (capacity, reach, speed,
	# deep-water access) come back exactly as they were.
	var saved_owned = data.get("owned", {})
	if typeof(saved_owned) == TYPE_DICTIONARY:
		for up in Upgrades.LIST:
			var id := String(up["id"])
			if saved_owned.has(id):
				owned[id] = true
				apply_upgrade(id)


func _save_progress() -> void:
	SaveGame.store({
		"credits": credits,
		"owned": owned,
		"level_index": level_index,
		"free_play": free_play,
		"level": level,
		"retained": retained,
		"adapt": adapt,
		"shift_fails": shift_fails,
		"tutorial_done": tutorial_done,
	})


func wipe_save() -> void:
	SaveGame.wipe()


# =============================================================================
# Events
# =============================================================================

func _on_bay_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	var p := body as Player
	p.in_safe_zone = true
	if p.carried <= 0:
		return
	var earned := p.dump()
	add_credits(earned)
	popup("+%d cr" % earned, Zones.BAY_POS + Vector2(-16, -46), Color(1.0, 0.95, 0.5))
	shake(2.5, 0.16)
	sfx("skip_dump")


func _on_bay_exited(body: Node2D) -> void:
	if body is Player:
		(body as Player).in_safe_zone = false


func on_player_hit(lost_units: int, lost_value: int, at: Vector2) -> void:
	if lost_units <= 0:
		sfx("hit", 1.25, -6.0)
		shake(4.0, 0.22)
		return
	sfx("hit")
	# The load bursts back onto the sand instead of being destroyed. Destroying
	# it made a collision a FREE way to clear the beach: a player about to lose
	# on reputation could skim the shoreline, take a hit, and wipe their carry
	# off the mess total at no cost. Now the seaweed is still there and still
	# counts -- what a hit costs you is the work of picking it all up again.
	#
	# The WHOLE load comes back, however big. Held seaweed is off the beach --
	# it stops counting against reputation the moment it is raked -- but it is
	# not banked until the skip. Carrying a full hopper is a risk on purpose.
	# Deferred: a hit arrives inside a physics callback (the tourist's
	# body_entered), where adding new Area2D piles is refused by the physics
	# server -- the dropped seaweed came out with dead collision shapes.
	spawner.scatter.call_deferred(lost_units, at)
	shake(7.0, 0.34)


func touches_player(p: Vector2, size: Vector2) -> bool:
	# Box against the worker's hitbox, for level obstacles that are not bodies
	# (divers, kayaks, umbrellas). Never in the bay, never while stunned.
	if player == null or player.in_safe_zone or player._stun > 0.0:
		return false
	var hs: Vector2 = (player._shape.shape as RectangleShape2D).size
	return absf(player.position.x - p.x) < (hs.x + size.x) * 0.5 \
		and absf(player.position.y - p.y) < (hs.y + size.y) * 0.5


func knock_down(at: Vector2) -> void:
	# An OBJECT hit: a moment on the sand, but the load stays in your arms.
	# People (tourists, divers, kayakers) make you drop it; things don't.
	if player == null or player.in_safe_zone or player._stun > 0.0:
		return
	player._stun = 0.6
	sfx("umbrella_bonk", 1.0, -3.0)
	shake(3.0, 0.2)


func add_credits(n: int) -> void:
	credits += n
	credits_earned += n


# Convenience passthroughs so entities only ever need a reference to `game`.
func find_pile_near(pos: Vector2, ignore) -> Seaweed:
	return spawner.find_pile_near(pos, ignore)


func shore_mess() -> float:
	return rep.shore_mess()


# =============================================================================
# Pause
# =============================================================================

func pause_for_system() -> void:
	# Never resume automatically on the way back in: dropping someone straight
	# into a Happy Hour crowd after a phone call would be a cheap hit.
	if hud == null or hud.pause_visible():
		return
	if level_done or level_failed or shop.visible:
		return
	hud.show_pause(true)
	joystick.active = false
	get_tree().paused = true


func quit_to_menu() -> void:
	_save_progress()
	get_tree().paused = false
	var menu = load("res://scenes/menu.tscn").instantiate()
	get_tree().root.add_child(menu)
	var old := get_tree().current_scene
	get_tree().current_scene = menu
	if old != null:
		old.queue_free()


func resume_from_pause() -> void:
	hud.show_pause(false)
	joystick.active = true
	get_tree().paused = false


func _set_all_audio_muted(muted: bool) -> void:
	# _notification can fire before the bus layout is up, so check the index.
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			pause_for_system()
			_set_all_audio_muted(true)
			# Android may never resume this process, so this is the last
			# reliable chance to write.
			_save_progress()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save_progress()
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_set_all_audio_muted(false)
		NOTIFICATION_WM_GO_BACK_REQUEST:
			# Android back button pauses rather than killing the app.
			pause_for_system()


# =============================================================================
# Feel
# =============================================================================

func sfx(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if audio != null:
		audio.play(key, pitch, volume_db)


func shake(strength: float = 5.0, time: float = 0.28) -> void:
	# Offsets the world node rather than a camera -- there is no Camera2D, the
	# view is fixed. Always returns to exactly zero so repeated shakes cannot
	# drift the whole scene off-centre.
	if world == null:
		return
	if _shake_tw != null and _shake_tw.is_valid():
		_shake_tw.kill()
	_shake_tw = create_tween()
	var steps := 6
	for i in steps:
		var fall := strength * (1.0 - float(i) / float(steps))
		_shake_tw.tween_property(world, "position",
			Vector2(randf_range(-fall, fall), randf_range(-fall, fall)),
			time / float(steps))
	_shake_tw.tween_property(world, "position", Vector2.ZERO, time / float(steps))


func popup(text: String, pos: Vector2, color: Color, reward: bool = false) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos + Vector2(-40, -28)
	l.size = Vector2(80, 22)
	l.pivot_offset = l.size / 2.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	if reward:
		# Pickups: bold, a dark edge to lift it off the sand, and a soft glow
		# in its own colour -- the shadow drawn as a wide, faint outline.
		l.add_theme_font_override("font", UiTheme.bold())
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_constant_override("outline_size", 3)
		l.add_theme_color_override("font_outline_color", color.darkened(0.75))
		l.add_theme_color_override("font_shadow_color", Color(color, 0.45))
		l.add_theme_constant_override("shadow_outline_size", 7)
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
	l.z_index = 60
	world.add_child(l)

	var tw := create_tween()
	tw.set_parallel(true)
	if reward:
		l.scale = Vector2(1.35, 1.35)
		tw.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 28.0, 0.65)
	tw.tween_property(l, "modulate:a", 0.0, 0.65).set_delay(0.15 if reward else 0.0)
	tw.chain().tween_callback(l.queue_free)


func grade(saturation: float, exposure: float, time: float = 1.0) -> void:
	# Tween the shader uniforms rather than swapping materials, so the beach
	# ramps into the look instead of snapping.
	var mat := _grade.material as ShaderMaterial
	if mat == null:
		return
	var from_sat := _grade_saturation
	var from_exp := _grade_exposure
	_grade_saturation = saturation
	_grade_exposure = exposure

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(func(v: float): mat.set_shader_parameter("saturation", v),
		from_sat, saturation, time)
	tw.tween_method(func(v: float): mat.set_shader_parameter("exposure", v),
		from_exp, exposure, time)


func pulse_grade(extra: float) -> void:
	# Called every frame during Happy Hour to throb the exposure on top of
	# whatever grade() settled on. Kept separate so the tween and the throb
	# can't fight over the same uniform.
	var mat := _grade.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("exposure", _grade_exposure + extra)


func flash(peak: float = 0.6, up: float = 0.04, down: float = 0.34) -> void:
	# Fast up, slow down -- a slow rise reads as a light being switched on
	# rather than a strike.
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", peak, up)
	tw.tween_property(_flash, "color:a", 0.0, down)


func tween_tint(c: Color) -> void:
	var tw := create_tween()
	tw.tween_property(_tint, "color", c, 0.8)
