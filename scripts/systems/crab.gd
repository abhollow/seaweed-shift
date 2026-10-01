class_name Crab
extends Node2D

# The crab (Playa del Carmen, Puerto Morelos, Mahahual): once a level, in one
# chosen shift, a crab digs itself out of the sand and goes after the worker.
#
#   LURKING    a mound in the sand twitches -- the warning
#   EMERGING   it pops up
#   CHASING    it scuttles after the worker, slower than them, slower still in
#              a storm, and never off the sand. Reaching them is a hit: the
#              load is dropped, exactly as a tourist collision.
#              Lead it close to a tourist and it follows THEM for a while,
#              then turns back to the worker -- the way to shake it off.
#   BURROWING  time up, or it got you: it digs back in and is gone.

enum State { WAITING, LURKING, EMERGING, CHASING, BURROWING, GONE }

var game
var active := false               # this shift has the crab
var state := State.GONE
var pos := Vector2.ZERO

var shift := 1                    # which shift of the level (0-based) it appears in
var at_min := 35.0                # seconds into that shift it appears
var at_max := 80.0
var speed := 80.0                 # px/s -- the worker walks 130, drives 165+
var storm_slow := 0.5             # crabs hunker down in the rain
var chase_len := 24.0             # seconds it hunts before giving up
var lure_radius := 26.0           # this close to a tourist and it switches
var lure_len := 4.5               # seconds it follows a tourist
var lure_cooldown := 3.0          # before another tourist can catch its eye

const LURK_LEN := 2.2
const EMERGE_LEN := 0.6
const BURROW_LEN := 0.8
const BODY := Vector2(20, 14)     # hitbox
const WALK_FPS := 8.0

var _t := 0.0
var _wait := 0.0
var _hunt_left := 0.0
var _decoy: Node2D = null
var _decoy_left := 0.0
var _ignore_left := 0.0
var _facing_left := false
var _view := "front"          # "side", "front" (toward camera) or "back"
var _moving := false
var _anim := 0.0

# Art, when it exists: scuttling sideways (drawn moving right, mirrored for
# left), walking toward the camera, walking away, and digging
# (in or out). Missing files fall back to drawn shapes.
var _side: Array = []
var _front: Array = []
var _back: Array = []
var _dig: Array = []


func _ready() -> void:
	_side = _load_frames("crab_side_f%d")
	_front = _load_frames("crab_front_f%d")
	_back = _load_frames("crab_back_f%d")
	_dig = _load_frames("crab_dig_f%d")


func _load_frames(pattern: String) -> Array:
	var out := []
	for i in 8:
		var path := "res://assets/sprites/" + (pattern % i) + ".png"
		if ResourceLoader.exists(path):
			out.append(load(path))
	return out


func configure(beach: Dictionary, shift_index: int) -> void:
	var c: Dictionary = beach.get("crab", {})
	shift = int(c.get("shift", 1))
	at_min = float(c.get("at", [35.0, 80.0])[0])
	at_max = float(c.get("at", [35.0, 80.0])[1])
	speed = float(c.get("speed", 80.0))
	chase_len = float(c.get("chase", 24.0))
	active = not c.is_empty() and shift_index == shift and not Zones.RADIAL
	state = State.WAITING if active else State.GONE
	_wait = randf_range(at_min, at_max)
	_decoy = null
	visible = active
	queue_redraw()


func out() -> bool:
	return state in [State.LURKING, State.EMERGING, State.CHASING, State.BURROWING]


func chasing_tourist() -> bool:
	return state == State.CHASING and _decoy != null


func status_text() -> String:
	match state:
		State.LURKING:
			return "SOMETHING IS MOVING IN THE SAND"
		State.EMERGING, State.CHASING:
			return "THE CRAB IS AFTER A TOURIST" if chasing_tourist() \
				else "CRAB! LEAD IT INTO A TOURIST"
	return ""


func tick(delta: float) -> void:
	if not active:
		return
	_t += delta
	_ignore_left = maxf(0.0, _ignore_left - delta)
	_moving = false
	match state:
		State.WAITING:
			_wait -= delta
			if _wait <= 0.0:
				_surface()
		State.LURKING:
			if _t >= LURK_LEN:
				_enter(State.EMERGING)
				if game != null:
					game.sfx("rot", 1.6, -2.0)
		State.EMERGING:
			if _t >= EMERGE_LEN:
				_hunt_left = chase_len
				_enter(State.CHASING)
		State.CHASING:
			_chase(delta)
		State.BURROWING:
			if _t >= BURROW_LEN:
				_enter(State.GONE)
	_anim += delta
	queue_redraw()


func _enter(s: int) -> void:
	state = s
	_t = 0.0


func _surface() -> void:
	# Somewhere on open sand, a fair way from the worker -- the twitching mound
	# is a warning, so there has to be time to read it.
	var p := Vector2.ZERO
	for tries in 30:
		p = Vector2(randf_range(40.0, 320.0),
			randf_range(Zones.HOTEL_BOTTOM + 30.0, Zones.SHORE_Y - 12.0))
		if game == null:
			break
		var bay := Rect2(Zones.BAY_POS - Zones.BAY_SIZE / 2.0, Zones.BAY_SIZE).grow(20.0)
		if p.distance_to(game.player.position) > 120.0 and not bay.has_point(p) \
				and not game.in_nest(p, 12.0):
			break
	pos = p
	_enter(State.LURKING)


func _chase(delta: float) -> void:
	_hunt_left -= delta
	if _hunt_left <= 0.0:
		_enter(State.BURROWING)
		return

	# Following a tourist: until bored, or until they leave.
	if _decoy != null:
		_decoy_left -= delta
		if _decoy_left <= 0.0 or not is_instance_valid(_decoy) or _decoy.is_queued_for_deletion():
			_decoy = null
			_ignore_left = lure_cooldown
	elif _ignore_left <= 0.0:
		_decoy = _tourist_near(pos, lure_radius)
		if _decoy != null:
			_decoy_left = lure_len

	var target: Vector2 = _decoy.position if _decoy != null else game.player.position
	var s := speed * (storm_slow if game.storm_active else 1.0)
	var to := target - pos
	if to.length() > 1.0:
		var step := to.normalized() * minf(s * delta, to.length())
		pos += step
		_moving = true
		if absf(step.x) > 0.05:
			_facing_left = step.x < 0.0
		# Crabs go sideways: any real sideways component uses the scuttle;
		# only a mostly up-or-down move turns it toward or away from camera.
		if absf(step.x) >= absf(step.y) * 0.6:
			_view = "side"
		else:
			_view = "back" if step.y < 0.0 else "front"
	pos = _keep_on_sand(pos)

	if _decoy == null and _touching_player():
		game.player.get_hit()
		_enter(State.BURROWING)


func _keep_on_sand(p: Vector2) -> Vector2:
	# Beach only: never into the resort, never into the water, never into the
	# bay, and round any turtle nest.
	p.x = clampf(p.x, 16.0, 344.0)
	p.y = clampf(p.y, Zones.HOTEL_BOTTOM + 12.0, Zones.SHORE_Y - 4.0)
	var bay := Rect2(Zones.BAY_POS - Zones.BAY_SIZE / 2.0, Zones.BAY_SIZE).grow(6.0)
	if bay.has_point(p):
		p.y = bay.end.y + 0.5
	if game != null and not game.nests.is_empty():
		p = game.push_out_of_nests(p, 6.0)
	return p


func _touching_player() -> bool:
	var pl = game.player
	if pl.in_safe_zone or pl._stun > 0.0:
		return false
	var hs: Vector2 = (pl._shape.shape as RectangleShape2D).size
	return absf(pl.position.x - pos.x) < (hs.x + BODY.x) * 0.5 \
		and absf(pl.position.y - pos.y) < (hs.y + BODY.y) * 0.5


func _tourist_near(p: Vector2, r: float) -> Node2D:
	var best: Node2D = null
	var best_d := r
	for c in game.world.get_children():
		if c is Tourist and not c.is_queued_for_deletion():
			var d := p.distance_to((c as Node2D).position)
			if d < best_d:
				best_d = d
				best = c
	return best


# ---- drawing ----------------------------------------------------------------

func _draw() -> void:
	if not active:
		return
	match state:
		State.LURKING:
			_draw_mound(1.0)
		State.EMERGING:
			_draw_dig(clampf(_t / EMERGE_LEN, 0.0, 1.0))
		State.CHASING:
			_draw_crab()
		State.BURROWING:
			_draw_dig(1.0 - clampf(_t / BURROW_LEN, 0.0, 1.0))


func _draw_mound(k: float) -> void:
	# A low hump of sand that twitches, faster as it is about to break open.
	var shake := sin(_anim * (18.0 + 30.0 * _t / LURK_LEN)) * 1.5
	if not _dig.is_empty():
		_blit(_dig[0], false, Vector2(shake, 0))
		return
	var c := Color(0.80, 0.70, 0.48)
	draw_set_transform(pos + Vector2(shake, 0), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 9.0 * k, c)
	draw_circle(Vector2(-2, -3), 5.0 * k, c.lightened(0.15))
	draw_set_transform(Vector2.ZERO)


func _draw_dig(up: float) -> void:
	# 0 = under the sand, 1 = fully out.
	if not _dig.is_empty():
		var tex: Texture2D = _dig[mini(int(up * float(_dig.size())), _dig.size() - 1)]
		_blit(tex, false)
		return
	_draw_mound(1.0 - up * 0.6)
	if up > 0.3:
		_draw_body(pos + Vector2(0, (1.0 - up) * 6.0), up)


# Walking motion in code, on top of the frames: at this size the legs are a
# pixel or two, so a hop on every step, a squash as it lands and a little
# side-to-side waddle are what sell it -- toward and away from camera most.
const HOP := 2.0                  # px
const SQUASH := 0.10
const WADDLE := 1.0               # px


func _draw_crab() -> void:
	var set_: Array = _side if _view == "side" else (_back if _view == "back" else _front)
	if set_.is_empty():
		set_ = _front
	var step := _anim * WALK_FPS * PI     # one hop per frame of the cycle
	var hop := absf(sin(step)) if _moving else 0.0
	var off := Vector2(sin(step * 0.5) * WADDLE if _moving else 0.0, -hop * HOP)
	var sq := Vector2(1.0 + SQUASH * (1.0 - hop), 1.0 - SQUASH * (1.0 - hop)) if _moving else Vector2.ONE
	if not set_.is_empty():
		var f := int(_anim * WALK_FPS) % set_.size() if _moving else 0
		# The side art scuttles right; mirror it for left. Front and back are
		# symmetrical, so they only flip with the step for a bit of variety.
		_blit(set_[f], _facing_left if _view == "side" else false, off, sq)
		return
	_draw_body(pos + off, 1.0)


func _blit(tex: Texture2D, flip: bool, off: Vector2 = Vector2.ZERO, sq: Vector2 = Vector2.ONE) -> void:
	# Sprites are authored at half density and drawn at 2x, like everything
	# else -- anchored at the feet, so a squash sits it down onto the sand.
	var sz := tex.get_size() * 2.0
	var feet := pos + off + Vector2(0, BODY.y * 0.5)
	draw_set_transform(feet, 0.0, Vector2(-sq.x if flip else sq.x, sq.y))
	draw_texture_rect(tex, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false)
	draw_set_transform(Vector2.ZERO)


func _draw_body(p: Vector2, k: float) -> void:
	# Placeholder until the sprites land: shell, claws, eyes on stalks.
	var shell := Color(0.86, 0.30, 0.18, k)
	var dark := Color(0.55, 0.16, 0.10, k)
	var leg := sin(_anim * 24.0) * 1.5 if _moving else 0.0
	for side in [-1.0, 1.0]:
		for i in 3:
			var a := p + Vector2(side * 7.0, -2.0 + i * 3.0)
			draw_line(a, a + Vector2(side * 5.0, 2.0 + (leg if i % 2 == 0 else -leg)), dark, 1.5)
		draw_circle(p + Vector2(side * 10.0, -6.0), 3.2, shell)
		draw_circle(p + Vector2(side * 10.0, -6.0), 1.4, dark)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.7))
	draw_circle(Vector2.ZERO, 8.0, shell)
	draw_set_transform(Vector2.ZERO)
	for side in [-1.0, 1.0]:
		draw_line(p + Vector2(side * 2.5, -4.0), p + Vector2(side * 3.0, -8.0), dark, 1.0)
		draw_circle(p + Vector2(side * 3.0, -8.5), 1.3, Color(0.05, 0.05, 0.05, k))
