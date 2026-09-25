class_name Tourist
extends Area2D

# Normal tourists trot down, splash in the shallows, and stagger back up.
#
# HAPPY HOUR tourists (`rowdy`) are a different animal: much slower, headed all
# the way out to deep water, and they lurch sideways on a random timer instead
# of weaving on a clean sine. The lurch is the whole point -- a predictable
# weave can be walked around, an unpredictable one has to be watched.

enum State { DESCEND, SPLASH, ASCEND }

# Four-frame walk cycles from tools/make_walk_frames.py. The rowdy set is built
# with a bigger bob, so the drunk lurch reads even before you notice the drink.
# Sixteen sets: sober/drunk x male/female x walking/wading x front/rear.
# Walking sets are four-frame cycles; wading sets are the waist-up pose. The
# rear views mean a tourist heading back up the beach shows you their back,
# exactly as the player does.
@export var tex_sober_m: Array[Texture2D]
@export var tex_sober_m_back: Array[Texture2D]
@export var tex_sober_f: Array[Texture2D]
@export var tex_sober_f_back: Array[Texture2D]
@export var tex_drunk_m: Array[Texture2D]
@export var tex_drunk_m_back: Array[Texture2D]
@export var tex_drunk_f: Array[Texture2D]
@export var tex_drunk_f_back: Array[Texture2D]
@export var tex_wade_sober_m: Array[Texture2D]
@export var tex_wade_sober_m_back: Array[Texture2D]
@export var tex_wade_sober_f: Array[Texture2D]
@export var tex_wade_sober_f_back: Array[Texture2D]
@export var tex_wade_drunk_m: Array[Texture2D]
@export var tex_wade_drunk_m_back: Array[Texture2D]
@export var tex_wade_drunk_f: Array[Texture2D]
@export var tex_wade_drunk_f_back: Array[Texture2D]

const WALK_FPS := 7.0
const ROWDY_FPS := 4.5
const WADE_FPS := 2.5     # arms bobbing on the surface, not striding

# Rain slows the holidaymakers exactly as it slows an un-jacketed worker, so a
# storm reads as one weather system acting on everyone rather than a penalty
# aimed only at the player.
const STORM_SPEED := 0.55

# Tourists are shoved by GUSTS only, not the steady wind. A constant push would
# walk every one of them into the right-hand wall over their lifetime -- which
# on Veracruz is exactly where the loading bay is. Gust-only means they stagger
# sideways a few times and stay spread across the beach.
#
# Measured over a whole lifetime, not a frame: at 0.8 one gust carried a tourist
# 228px -- two-thirds of the beach -- and 39% ended pinned against the bay wall.
# At 0.3 a gust is an 86px stagger: enough to wreck a route you had planned.
const GUST_SHOVE := 0.3
const GUST_SHOVE_ROWDY := 0.5      # drunks have less footing
const GUST_LEAN := 0.22

# Which way the source art was drawn, same convention as Player. Flip this one
# constant if a future sheet comes back facing the other way.
const ART_FACES_LEFT := true

# Tourists weave constantly, so without a deadzone the sprite would strobe
# left-right every few frames as the sine crosses zero.
const FACE_DEADZONE := 8.0

var speed := 95.0
var weave := 55.0
var target_y := 450.0
var despawn_y := 150.0
var rowdy := false
var female := false

var _state: int = State.DESCEND
var _phase := 0.0
var _splash_left := 0.0
var _lurch_t := 0.0
var _lurch_vel := 0.0
var _pause_t := 0.0
var _frames: Array[Texture2D] = []
var _anim_t := 0.0
var _anim_frame := -1
var _facing_left := false
var game

@onready var _vis: ColorRect = $Visual
@onready var _shape: CollisionShape2D = $Shape
@onready var _sprite: Sprite2D = $Sprite


func setup(pos: Vector2, ty: float, is_rowdy: bool = false, dy: float = 150.0,
		is_female: bool = false) -> void:
	# Called before add_child, so _ready() sees the final values.
	position = pos
	target_y = ty
	despawn_y = dy
	rowdy = is_rowdy
	female = is_female
	_phase = randf() * TAU
	if is_rowdy:
		speed = randf_range(32.0, 52.0)
		weave = randf_range(45.0, 90.0)
	else:
		speed = randf_range(80.0, 130.0)
		weave = randf_range(30.0, 80.0)


func _ready() -> void:
	# Happy Hour tourists are a touch bigger and warmer coloured. As with the
	# player, the drawing is larger than the hitbox so the sprite has pixels to
	# spare at half density -- and so brushing past someone's elbow is a miss.
	var hit := Vector2(24, 24) if rowdy else Vector2(16, 24)
	var art := Vector2(48, 48) if rowdy else Vector2(36, 48)
	(_shape.shape as RectangleShape2D).size = hit
	_vis.size = art
	_vis.position = -art / 2.0
	_vis.color = Color(0.99, 0.58, 0.32) if rowdy else Color(0.92, 0.42, 0.45)

	_frames = _frame_set()
	var has_art: bool = not _frames.is_empty() and _frames[0] != null
	_sprite.visible = has_art
	_vis.visible = not has_art
	if has_art:
		_sprite.texture = _frames[0]
		_sprite.flip_h = ART_FACES_LEFT
		_anim_frame = 0
		# Fixed 2x: every sprite is authored at half density, and the boxes now
		# differ per character and per pose (a raised cocktail is wider than a
		# swinging arm), so deriving scale from one art size would squash them.
		_sprite.scale = Vector2(2, 2)

	body_entered.connect(_on_body_entered)


func _face(lateral: float) -> void:
	if _sprite == null or not _sprite.visible:
		return
	if absf(lateral) < FACE_DEADZONE:
		return
	var want_left := lateral < 0.0
	if want_left != _facing_left:
		_facing_left = want_left
		# Mirror only when the wanted facing differs from how it was drawn.
		_sprite.flip_h = (_facing_left != ART_FACES_LEFT)


func in_water() -> bool:
	return position.y >= Zones.SHALLOW_TOP


func _frame_set() -> Array[Texture2D]:
	# Heading back up the beach means we see their back. ASCEND is the only
	# state that travels away from the camera.
	var back := _state == State.ASCEND
	var wading := in_water()

	var f: Array[Texture2D]
	var m: Array[Texture2D]
	if wading:
		if rowdy:
			f = tex_wade_drunk_f_back if back else tex_wade_drunk_f
			m = tex_wade_drunk_m_back if back else tex_wade_drunk_m
		else:
			f = tex_wade_sober_f_back if back else tex_wade_sober_f
			m = tex_wade_sober_m_back if back else tex_wade_sober_m
	else:
		if rowdy:
			f = tex_drunk_f_back if back else tex_drunk_f
			m = tex_drunk_m_back if back else tex_drunk_m
		else:
			f = tex_sober_f_back if back else tex_sober_f
			m = tex_sober_m_back if back else tex_sober_m

	# Fall back to the male set if a female sheet is missing, so a half-finished
	# art drop leaves tourists looking wrong rather than invisible.
	if female and not f.is_empty():
		return f
	return m


func _tick_walk(delta: float) -> void:
	# Swap silhouette the moment the waterline is crossed, not on a state
	# change -- the player should see the change happen where it happens.
	var want := _frame_set()
	if want != _frames and not want.is_empty():
		_frames = want
		_anim_frame = -1
		_anim_t = 0.0

	if _frames.size() < 2:
		return
	var fps := WADE_FPS if in_water() else (ROWDY_FPS if rowdy else WALK_FPS)
	_anim_t += delta * fps
	var f := int(_anim_t) % _frames.size()
	if f != _anim_frame:
		_anim_frame = f
		_sprite.texture = _frames[f]


func _process(delta: float) -> void:
	_phase += delta * 3.5
	_tick_walk(delta)

	var fwd := 1.0
	if game != null and game.storm_active:
		fwd = STORM_SPEED
	var lateral := sin(_phase) * weave

	if rowdy:
		_lurch_t -= delta
		if _lurch_t <= 0.0:
			_lurch_t = randf_range(0.35, 0.95)
			_lurch_vel = randf_range(-110.0, 110.0)
			if randf() < 0.20:
				_pause_t = randf_range(0.3, 0.8)   # stops dead and sways
		if _pause_t > 0.0:
			_pause_t -= delta
			fwd = 0.0
		lateral = lateral * 0.5 + _lurch_vel
		rotation = sin(_phase * 0.7) * 0.28

	_face(lateral)

	match _state:
		State.DESCEND:
			position.y += speed * fwd * delta
			position.x += lateral * delta
			if position.y >= target_y:
				_state = State.SPLASH
				_splash_left = randf_range(1.5, 3.0) if rowdy else randf_range(2.5, 6.0)

		State.SPLASH:
			_splash_left -= delta
			position.x += lateral * 1.2 * delta
			position.y += sin(_phase * 0.9) * 18.0 * delta
			if _splash_left <= 0.0:
				_state = State.ASCEND

		State.ASCEND:
			position.y -= speed * (0.9 if rowdy else 1.15) * fwd * delta
			position.x += lateral * 0.8 * delta
			if position.y < despawn_y:
				queue_free()

	_tick_gust(delta)
	position.x = clampf(position.x, 12.0, 348.0)


func _tick_gust(delta: float) -> void:
	var g := 0.0
	if game != null and game.wind != null and game.wind.active():
		g = float(game.wind.gust_shape())
	if g > 0.0:
		var k := GUST_SHOVE_ROWDY if rowdy else GUST_SHOVE
		position.x += float(game.wind.force()) * g * k * delta
	# Lean INTO the wind (it comes from the left, so the top tips left) -- a
	# visible tell that the next few seconds belong to the weather.
	#
	# SET for sober tourists, ADDED for drunks. A drunk's sway rewrites rotation
	# every frame, so adding to it is safe; a sober tourist's rotation is never
	# reset anywhere else, and adding would accumulate until they spun.
	var lean := -GUST_LEAN * g
	if rowdy:
		rotation += lean
	else:
		rotation = lean


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		(body as Player).get_hit()
