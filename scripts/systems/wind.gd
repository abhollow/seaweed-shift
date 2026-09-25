class_name Wind
extends Node

# Per-level wind, blowing left to right. Configured from the current beach's
# "wind" block; a level without one is CALM and every query returns zero, so no
# other system needs to know which level it is on.
#
# Level 2 (Veracruz) is the first to use it: the norte, a steady wind off the
# Gulf with periodic gusts. It pushes the player -- faster downwind, slower
# upwind -- and slides the drifting seaweed along the coast.

signal gust_started

var game

var strength := 0.0      # base push, px/sec
var gust_every := 0.0    # mean seconds between gusts
var gust_len := 0.0      # seconds a gust lasts
var gust_mult := 1.0     # peak push during a gust, as a multiple of strength

var gusting := false
var _gust_t := 0.0
var _next_gust := 0.0

var _bed: AudioStreamPlayer
const BED := preload("res://audio/wind_loop.ogg")
const BED_DB := -14.0
const BED_GUST_DB := -6.0


func _ready() -> void:
	# A continuous wind bed on the Ambience bus, swelling with each gust. It
	# pauses with the game, which is right: no wind while a panel is up.
	_bed = AudioStreamPlayer.new()
	_bed.stream = BED
	if "loop" in _bed.stream:
		_bed.stream.loop = true
	_bed.bus = "Ambience"
	_bed.volume_db = -80.0
	add_child(_bed)


func configure(beach: Dictionary) -> void:
	var w: Dictionary = beach.get("wind", {})
	strength = float(w.get("strength", 0.0))
	gust_every = float(w.get("gust_every", 0.0))
	gust_len = float(w.get("gust_len", 0.0))
	gust_mult = float(w.get("gust_mult", 1.0))
	gusting = false
	_gust_t = 0.0
	# The first gust comes early, so a new player meets it within seconds.
	_next_gust = gust_every * 0.4
	if _bed != null:
		if active():
			if not _bed.playing:
				_bed.play()
			_bed.volume_db = BED_DB
		else:
			_bed.stop()


func active() -> bool:
	return strength > 0.0


func tick(delta: float) -> void:
	if not active():
		return
	if gusting:
		_gust_t -= delta
		if _gust_t <= 0.0:
			gusting = false
	else:
		_next_gust -= delta
		if _next_gust <= 0.0 and gust_every > 0.0:
			gusting = true
			_gust_t = gust_len
			_next_gust = gust_every * randf_range(0.75, 1.25)
			gust_started.emit()
			if game != null:
				game.sfx("gust", randf_range(0.92, 1.08), -2.0)
	if _bed != null and _bed.playing:
		_bed.volume_db = lerpf(BED_DB, BED_GUST_DB, gust_shape())


func gust_shape() -> float:
	# 0 outside a gust, rising to 1 at its peak and back. Eased rather than
	# stepped, so a gust is felt as a shove building and fading, not a snap.
	if not gusting or gust_len <= 0.0:
		return 0.0
	return sin((1.0 - _gust_t / gust_len) * PI)


func force() -> float:
	# Current push in px/sec; positive means rightward.
	if not active():
		return 0.0
	var f := strength * (1.0 + (gust_mult - 1.0) * gust_shape())
	# A norte and a storm together is the worst of both.
	if game != null and game.storm_active:
		f *= 1.5
	return f
