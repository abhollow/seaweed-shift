class_name Hurricane
extends Node

# Tulum, the finale: a hurricane rolls in over the shift.
#
#   CALM       A sunny beach below the ruins.
#   GATHERING  The wind picks up -- the Veracruz norte, returning.
#   FRONT      The hurricane hits: storm-force wind with gusts, rain and dark
#              skies, and Bacalar's surf pounding in.
#   EYE        Everything stops. The sky clears to gold, the wind drops to
#              nothing, and seaweed barely arrives -- a fixed window to clear
#              the beach before...
#   BACK WALL  ...the other side of the storm arrives, and the wind blows from
#              the OTHER DIRECTION. Every habit from the front is backwards.
#              Real hurricanes do exactly this.
#
# It conducts systems the game already has -- the wind, the storm, the surf --
# rather than new ones. Phases follow PROGRESS through the shift, not the
# clock, so the eye always comes before the end and the storm peaks as the
# player finishes, however long the shift takes them. The eye alone is timed:
# once it arrives it gives a fixed window.

enum Phase { CALM, GATHERING, FRONT, EYE, BACKWALL }

var game
var active := false
var phase := Phase.CALM
var at_gathering := 0.15
var at_front := 0.35
var at_eye := 0.6
var eye_len := 20.0

var _eye_left := 0.0
var _eye_done := false

const EYE_TINT := Color(1.10, 1.00, 0.82)       # golden light in the eye

# Seaweed rate in each phase, on top of everything else. The storm adds its own
# pressure during the front and back wall; the eye is a true breather.
const SPAWN := {
	Phase.CALM: 0.9, Phase.GATHERING: 1.0, Phase.FRONT: 1.0, Phase.EYE: 0.3, Phase.BACKWALL: 1.0,
}


func configure(beach: Dictionary) -> void:
	var h: Dictionary = beach.get("hurricane", {})
	active = not h.is_empty()
	at_gathering = float(h.get("gathering", 0.15))
	at_front = float(h.get("front", 0.35))
	at_eye = float(h.get("eye", 0.6))
	eye_len = float(h.get("eye_len", 20.0))
	_eye_done = false
	_eye_left = 0.0
	phase = Phase.CALM
	if active:
		_enter(Phase.CALM)


func progress() -> float:
	if game == null:
		return 0.0
	var goal := maxf(1.0, float(game.current_level().get("credits", 1500)))
	return clampf(float(game.credits_earned) / goal, 0.0, 1.0)


func spawn_factor() -> float:
	return float(SPAWN[phase]) if active else 1.0


func eye_left() -> float:
	return _eye_left if phase == Phase.EYE else 0.0


func tick(delta: float) -> void:
	if not active:
		return
	var p := progress()
	match phase:
		Phase.CALM:
			if p >= at_gathering:
				_enter(Phase.GATHERING)
		Phase.GATHERING:
			if p >= at_front:
				_enter(Phase.FRONT)
		Phase.FRONT:
			if p >= at_eye:
				_enter(Phase.EYE)
		Phase.EYE:
			_eye_left -= delta
			if _eye_left <= 0.0:
				_enter(Phase.BACKWALL)


func _enter(next: int) -> void:
	phase = next
	if game == null:
		return
	match next:
		Phase.CALM:
			game.wind.set_live(0.0, 0.0, 0.0, 1.0, 1.0)
			game.weather.force_storm(false)
			game.tween_tint(Weather.TINT_CLEAR)
			game.surf.active = false
			game.surf.waves.clear()
		Phase.GATHERING:
			game.wind.set_live(24.0, 14.0, 3.5, 1.8, 1.0)
			game.popup("HURRICANE APPROACHING", Vector2(180, 300), Color(0.8, 0.9, 1.0))
		Phase.FRONT:
			game.wind.set_live(40.0, 10.0, 4.0, 2.3, 1.0)
			game.weather.force_storm(true)
			game.surf.active = true
			game.surf.visible = true
			game.shake(6.0, 0.4)
			game.popup("THE HURRICANE HITS", Vector2(180, 300), Color(1.0, 0.7, 0.6))
		Phase.EYE:
			_eye_left = eye_len
			_eye_done = true
			game.wind.set_live(0.0, 0.0, 0.0, 1.0, 1.0)
			game.weather.force_storm(false)
			game.surf.active = false
			game.surf.waves.clear()
			game.tween_tint(EYE_TINT)
			game.popup("THE EYE OF THE STORM", Vector2(180, 300), Color(1.0, 0.92, 0.55))
		Phase.BACKWALL:
			# The other side of the storm: the wind comes from the opposite
			# direction, harder than before.
			game.wind.set_live(46.0, 9.0, 4.0, 2.5, -1.0)
			game.weather.force_storm(true)
			game.surf.active = true
			game.shake(7.0, 0.45)
			game.popup("THE BACK WALL -- WIND REVERSED!", Vector2(180, 300), Color(1.0, 0.6, 0.5))


func status_text() -> String:
	if not active:
		return ""
	match phase:
		Phase.GATHERING:
			return "HURRICANE APPROACHING -- WIND RISING"
		Phase.FRONT:
			return "THE HURRICANE HITS"
		Phase.EYE:
			return "THE EYE -- CLEAR THE BEACH! %d" % ceili(_eye_left)
		Phase.BACKWALL:
			return "THE BACK WALL -- WIND FROM THE OTHER SIDE!"
	return ""
