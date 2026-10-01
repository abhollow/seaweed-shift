class_name Seagull
extends Node2D

# The Pet Seagull (tier 2). Perches on the skip; whenever a pile has started to
# rot, it flies out, takes a beakful, and drops it in the skip -- then goes
# for the next one, or settles back on the skip. It earns nothing: what it
# carries never pays. It only fixes reputation, by taking away the worst of
# the mess. Deliberately slow, so it is a help with rot, not a way to win.
# Storms do not slow it and tourists do not bother it -- it is in the air.

enum State { PERCHED, OUT, PICKING, BACK }

const SPEED := 60.0               # px/s -- the worker walks 130
const CARRY := 2                  # units per trip
const PICK_LEN := 0.6
const LOOK_EVERY := 0.4
const FLAP_FPS := 10.0
# Flap, then coast: two wingbeats, then a glide on the wings-level frame.
# Flapping nonstop was distracting.
const FLAP_LEN := 0.8             # two full beats at FLAP_FPS
const GLIDE_LEN := 1.0
const GLIDE_FRAME := 1            # wings spread level

var game
var enabled := false
var state := State.PERCHED
var pos := Vector2.ZERO
var carrying := 0
var _target: Seaweed = null
var _t := 0.0
var _look := 0.0
var _anim := 0.0
var _facing_left := false

# Art, when it exists: flying (side view, facing right) and perched.
var _fly: Array = []
var _perch: Array = []


func _ready() -> void:
	_fly = _load_frames("seagull_fly_f%d")
	_perch = _load_frames("seagull_perch_f%d")


func _load_frames(pattern: String) -> Array:
	var out := []
	for i in 8:
		var path := "res://assets/sprites/" + (pattern % i) + ".png"
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out


func set_enabled(on: bool) -> void:
	enabled = on
	visible = on
	reset()


func reset() -> void:
	# Back on the skip, beak empty -- a new shift, or just bought.
	state = State.PERCHED
	carrying = 0
	_target = null
	_t = 0.0
	pos = perch()
	queue_redraw()


func perch() -> Vector2:
	# On the rim of the skip, wherever this level draws it.
	if game == null:
		return Vector2.ZERO
	return Zones.BAY_POS + Vector2(game._bin_offset(), game._bin_y() - 14.0)


func tick(delta: float) -> void:
	if not enabled:
		return
	_anim += delta
	_t += delta
	match state:
		State.PERCHED:
			pos = perch()
			_look -= delta
			if _look <= 0.0:
				_look = LOOK_EVERY
				_target = _worst_rot()
				if _target != null:
					state = State.OUT
		State.OUT:
			if not _alive(_target):
				# Someone else got it -- the worker, or it was merged away.
				_target = _worst_rot()
				if _target == null:
					state = State.BACK
					return
			if _fly_to(_target.position, delta):
				state = State.PICKING
				_t = 0.0
		State.PICKING:
			if not _alive(_target):
				state = State.BACK if carrying > 0 else State.OUT
				if carrying == 0:
					_target = _worst_rot()
					if _target == null:
						state = State.BACK
				return
			if _t >= PICK_LEN:
				_take()
				state = State.BACK
		State.BACK:
			if _fly_to(perch(), delta):
				if carrying > 0 and game != null:
					game.sfx("pickup", 1.4, -8.0)
				carrying = 0
				_target = null
				state = State.PERCHED
				_look = 0.0      # straight back out if there is more
	queue_redraw()


func _fly_to(p: Vector2, delta: float) -> bool:
	var to := p - pos
	if absf(to.x) > 0.5:
		_facing_left = to.x < 0.0
	if to.length() <= SPEED * delta:
		pos = p
		return true
	pos += to.normalized() * SPEED * delta
	return false


func _alive(sw: Seaweed) -> bool:
	return sw != null and is_instance_valid(sw) and not sw.is_queued_for_deletion() \
		and not sw._popping and sw.units > 0


func _take() -> void:
	var n := mini(CARRY, _target.units)
	_target.units -= n
	carrying = n
	if _target.units <= 0:
		_target._pop_and_free()
	else:
		_target._refresh()


func _worst_rot() -> Seaweed:
	# Any pile that has started to rot -- browning or worse; fresh seaweed is
	# the worker's. The most rotten first, as that is what hurts reputation
	# most (it counts up to 6x), with distance only breaking near-ties.
	if game == null:
		return null
	var best: Seaweed = null
	var best_s := -INF
	for c in game.world.get_children():
		if not (c is Seaweed):
			continue
		var sw := c as Seaweed
		if sw.kelp or sw.drifting or sw.rot_progress() <= 0.0 or not _alive(sw):
			continue
		var s := sw.rot_progress() - pos.distance_to(sw.position) / 600.0
		if s > best_s:
			best_s = s
			best = sw
	return best


# ---- drawing ----------------------------------------------------------------

func _draw() -> void:
	if not enabled:
		return
	var flying := state != State.PERCHED
	var set_: Array = _fly if flying else _perch
	if not set_.is_empty():
		# Perched it mostly stands still, with a squawk every few seconds.
		var f := _flight_frame(set_.size()) if flying \
			else (1 if fmod(_anim, 3.0) > 2.6 and set_.size() > 1 else 0)
		var tex: Texture2D = set_[f]
		var sz := tex.get_size() * 2.0
		draw_set_transform(pos, 0.0, Vector2(-1.0 if _facing_left else 1.0, 1.0))
		draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false)
		draw_set_transform(Vector2.ZERO)
	else:
		_draw_placeholder(flying)
	if carrying > 0 or state == State.PICKING:
		# A beakful of brown weed dangling under it.
		var reach := 16.0 if not _fly.is_empty() else 5.0
		var beak := pos + Vector2(-reach if _facing_left else reach, 3.0)
		draw_circle(beak + Vector2(0, 2), 2.5, Color(0.40, 0.30, 0.13))
		draw_line(beak, beak + Vector2(0, 5), Color(0.35, 0.27, 0.12), 1.5)


func _draw_placeholder(flying: bool) -> void:
	var s := -1.0 if _facing_left else 1.0
	var white := Color(0.97, 0.97, 0.97)
	var grey := Color(0.62, 0.66, 0.72)
	if flying:
		var flap := sin(_anim * FLAP_FPS * 1.6) * 5.0
		draw_line(pos, pos + Vector2(-8, -3 - flap), grey, 2.5)
		draw_line(pos, pos + Vector2(8, -3 - flap), grey, 2.5)
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.7))
	draw_circle(Vector2.ZERO, 4.5, white)
	draw_set_transform(Vector2.ZERO)
	draw_circle(pos + Vector2(4.0 * s, -2.5), 2.5, white)
	draw_line(pos + Vector2(6.0 * s, -2.5), pos + Vector2(8.5 * s, -2.0), Color(1.0, 0.7, 0.15), 1.5)
	draw_circle(pos + Vector2(4.5 * s, -3.2), 0.7, Color(0.05, 0.05, 0.05))
	if not flying:
		draw_line(pos + Vector2(-5.0 * s, -1), pos + Vector2(-7.0 * s, 1), grey, 2.0)


func _flight_frame(n: int) -> int:
	var t := fmod(_anim, FLAP_LEN + GLIDE_LEN)
	if t >= FLAP_LEN:
		return mini(GLIDE_FRAME, n - 1)
	return int(t * FLAP_FPS) % n
