class_name Weather
extends Node

# Storms, Happy Hour, and everything they pull with them: screen tint, the music
# bed that plays over the top, the rain/crowd ambience layer, and the randomised
# thunder claps and shouts.
#
# `storm_active` and `happy_hour` still live on Game because half the game reads
# them; this node owns the scheduling and all the audio consequences.

# --- tuning -----------------------------------------------------------------
const STORM_EVERY := 120.0
const STORM_LENGTH := 14.0
const HAPPY_EVERY := 300.0
const HAPPY_LENGTH := 30.0

const THUNDER_MIN := 4.5
const THUNDER_MAX := 11.0
const THUNDER_COUNT := 3
const YELL_MIN := 1.4
const YELL_MAX := 4.2
const YELL_COUNT := 4
# ----------------------------------------------------------------------------

const TINT_CLEAR := Color(0.20, 0.25, 0.45, 0.0)
const TINT_STORM := Color(0.20, 0.25, 0.45, 0.35)
# Happy Hour no longer tints orange -- the scene is drained instead, so the
# mirrorball's white flecks are the only bright thing on screen.
const TINT_HAPPY := Color(0.20, 0.25, 0.45, 0.0)
# No colour grade during Happy Hour. Oversaturating pushed the orange tourists
# to the point where they were the only thing that changed, which read as a bug
# rather than a mood. The mirrorball and its sweeping flecks carry the event.
const HAPPY_SATURATION := 1.0
const HAPPY_EXPOSURE := 0.0

const STORM_TRACK := "res://audio/storm.mp3"
const HAPPY_TRACK := "res://audio/happy_hour.mp3"
const UPGRADE_TRACK := "res://audio/upgrade.mp3"
const RAIN_AMB := "res://audio/rain_loop.ogg"
const CROWD_AMB := "res://audio/crowd_loop.ogg"

# Relative attenuation on the MusicTrack bus, not an absolute level: with music
# sitting at -8 dB this lands the same -26 dB total as before, but it composes
# with the playlist's own per-track fades instead of overwriting them.
const MUSIC_DUCK_DB := -18.0
const EVENT_DB := -5.0
const UPGRADE_DB := -4.0
const AMBIENCE_DB := -7.0
const UPGRADE_LENGTH := 30.0

# Only one music bed plays at a time. Weather outranks the upgrade jingle:
# a storm rolling in is information the player needs, a victory lap is not.
enum Bed { NONE, STORM, HAPPY, UPGRADE }

var game
var bed: int = Bed.NONE

var _storm_t := 0.0
var _storm_left := 0.0
var _happy_t := 0.0
var _happy_left := 0.0
var _thunder_t := 0.0
var _thunder_delay := -1.0
var _thunder_pitch := 1.0
var _thunder_db := 0.0
var _yell_t := 0.0
var _upgrade_left := 0.0


func reset() -> void:
	game.storm_active = false
	game.happy_hour = false
	_storm_t = 0.0
	_storm_left = 0.0
	_happy_t = 0.0
	_happy_left = 0.0
	_upgrade_left = 0.0
	bed = Bed.NONE
	game.tween_tint(TINT_CLEAR)
	game.grade(1.0, 0.0, 0.3)
	if game.fx != null:
		game.fx.set_ball_visible(false)
	if game.audio != null:
		game.audio.stop_event(0.4)
		game.audio.stop_ambience(0.4)


func tick(delta: float) -> void:
	_tick_storm(delta)
	_tick_happy_hour(delta)
	_tick_upgrade_bed(delta)


# =============================================================================
# Events
# =============================================================================

func _tick_storm(delta: float) -> void:
	if game.storm_active:
		_storm_left -= delta

		_thunder_t -= delta
		if _thunder_t <= 0.0:
			_thunder_t = randf_range(THUNDER_MIN, THUNDER_MAX)
			# Flash first, thunder after. The gap is the "distance" to the
			# strike, and varying it does more for atmosphere than the pitch
			# variation alone ever did.
			_thunder_pitch = randf_range(0.82, 1.15)
			_thunder_db = randf_range(-9.0, -1.0)
			_thunder_delay = randf_range(0.15, 1.3)
			game.flash(randf_range(0.35, 0.7))

		if _thunder_delay > 0.0:
			_thunder_delay -= delta
			if _thunder_delay <= 0.0:
				_thunder_delay = -1.0
				game.sfx("thunder_%d" % (1 + randi() % THUNDER_COUNT),
					_thunder_pitch, _thunder_db)

		if _storm_left <= 0.0:
			game.storm_active = false
			game.tween_tint(TINT_CLEAR)
			resolve_bed()
			refresh_ambience()
		return

	_storm_t += delta
	# One event at a time. If Happy Hour is running the storm simply waits.
	if _storm_t >= STORM_EVERY and not game.happy_hour:
		_storm_t = 0.0
		game.storm_active = true
		_storm_left = STORM_LENGTH
		_thunder_t = randf_range(1.0, 3.0)
		_upgrade_left = 0.0
		game.tween_tint(TINT_STORM)
		set_bed(Bed.STORM)
		game.popup("STORM", Vector2(180, 300), Color(0.7, 0.85, 1.0))


func _tick_happy_hour(delta: float) -> void:
	if game.happy_hour:
		_happy_left -= delta

		_yell_t -= delta
		if _yell_t <= 0.0:
			_yell_t = randf_range(YELL_MIN, YELL_MAX)
			game.sfx("yell_%d" % (1 + randi() % YELL_COUNT),
				randf_range(0.85, 1.2), randf_range(-13.0, -5.0))

		if _happy_left <= 0.0:
			game.happy_hour = false
			game.grade(1.0, 0.0, 1.2)
			game.fx.set_ball_visible(false)
			resolve_bed()
			refresh_ambience()
		return

	_happy_t += delta
	if _happy_t >= HAPPY_EVERY and not game.storm_active:
		_happy_t = 0.0
		game.happy_hour = true
		_happy_left = HAPPY_LENGTH
		_yell_t = randf_range(0.8, 2.0)
		_upgrade_left = 0.0
		game.fx.set_ball_visible(true)
		set_bed(Bed.HAPPY)
		game.popup("HAPPY HOUR", Vector2(180, 300), Color(1.0, 0.72, 0.45))


# =============================================================================
# Music beds
# =============================================================================

func on_upgrade_bought() -> void:
	_upgrade_left = UPGRADE_LENGTH
	set_bed(Bed.UPGRADE)


func _tick_upgrade_bed(delta: float) -> void:
	# Ticks in _process, so the 30 seconds are gameplay time. Buying three
	# upgrades in one shop visit doesn't burn the jingle down while paused.
	if _upgrade_left <= 0.0:
		return
	_upgrade_left -= delta
	if _upgrade_left <= 0.0:
		_upgrade_left = 0.0
		resolve_bed()


func set_bed(b: int) -> void:
	if b == bed or game.audio == null:
		return
	bed = b
	match b:
		Bed.NONE:
			game.audio.stop_event()
			game.audio.restore_music()
		Bed.STORM:
			game.audio.duck_music(MUSIC_DUCK_DB, 1.2)
			game.audio.play_event(STORM_TRACK, EVENT_DB)
		Bed.HAPPY:
			game.audio.duck_music(MUSIC_DUCK_DB, 1.2)
			game.audio.play_event(HAPPY_TRACK, EVENT_DB)
		Bed.UPGRADE:
			game.audio.duck_music(MUSIC_DUCK_DB, 0.5)
			game.audio.play_event(UPGRADE_TRACK, UPGRADE_DB, 0.35)

	# Ambience tracks the actual weather, not the bed -- buying an upgrade mid
	# storm swaps the music but the rain keeps falling, because it should.
	refresh_ambience()


func resolve_bed() -> void:
	if game.storm_active:
		set_bed(Bed.STORM)
	elif game.happy_hour:
		set_bed(Bed.HAPPY)
	elif _upgrade_left > 0.0:
		set_bed(Bed.UPGRADE)
	else:
		set_bed(Bed.NONE)


func refresh_ambience() -> void:
	if game.audio == null:
		return
	if game.storm_active:
		game.audio.play_ambience(RAIN_AMB, AMBIENCE_DB)
	elif game.happy_hour:
		game.audio.play_ambience(CROWD_AMB, AMBIENCE_DB)
	else:
		game.audio.stop_ambience()
