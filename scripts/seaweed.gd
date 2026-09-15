class_name Seaweed
extends Area2D

# A clump holds `units`. Standing on it yields one unit every
# player.gather_interval seconds.
#
# Clumps that spawn in the water DRIFT slowly shoreward over minutes and then
# settle at the waterline, merging into piles. Clumps that spawn on the sand
# stay put. Deep kelp is rooted and never drifts -- otherwise late-game value
# would wash itself into the shallows for free.

const MAX_PILE := 8
const ROT_WARN := 8.0      # starts browning almost at once
const ROT_TIME := 30.0     # fully rotten: half value, full reputation damage

# A fully rotten pile speeds up rot on its neighbours. This is the whole point
# of the rework: with a flat timer the optimal play is to vacuum whatever is
# nearest, because order never matters. With spread, leaving one rotten pile in
# a cluster turns the cluster, so clearing THAT pile first is worth more than
# clearing a closer one -- a decision the player can see and act on.
const ROT_SPREAD_RADIUS := 44.0
const ROT_SPREAD_RATE := 1.6
const ROT_COLOR := Color(0.45, 0.33, 0.14)

var units := 1
var kelp := false
var drifting := false
var drift_speed := 2.4           # px/sec
var shore_y := 394.0
var game

# FLAT arrays of tier-major frames: [tier0 f0..fN, tier1 f0..fN, tier2 f0..fN].
# Frames-per-tier is derived from the length, so a variant with no animation
# (rot) just supplies one frame per tier. Leave a slot empty and that variant
# falls back to the placeholder rectangle, so art can land one at a time.
@export var tex_fresh: Array[Texture2D]
@export var tex_drift: Array[Texture2D]
@export var tex_kelp: Array[Texture2D]
@export var tex_rot: Array[Texture2D]

# How lively each variant is. Beached weed has washed up and settled; drifting
# weed is still afloat; kelp waves slowly in deep water; rot is dead and must
# NOT move, or it undercuts the "this is spoiled, go clear it" signal.
const SWAY_FPS := {"fresh": 2.5, "drift": 6.0, "kelp": 4.0}

var age := 0.0             # only ticks up once beached; kelp never ages

var _timer := 0.0
var _sway := 0.0
var _anim_t := 0.0
var _anim_frame := -1
var _popping := false
var _base_color := Color.WHITE
var _player: Player = null
var _size := 18.0

@onready var _rect: ColorRect = $Visual
@onready var _shape: CollisionShape2D = $Shape
@onready var _sprite: Sprite2D = $Sprite
@onready var _sprite_rot: Sprite2D = $SpriteRot


func setup(pos: Vector2, u: int, g, is_kelp: bool = false, drifts: bool = false) -> void:
	# Called before add_child so _ready() sees the final values.
	position = pos
	units = u
	kelp = is_kelp
	drifting = drifts and not is_kelp
	game = g
	drift_speed = randf_range(1.9, 3.1)
	_sway = randf() * TAU


func _ready() -> void:
	# Collision layers come from the scene (layer 0, mask 2): seaweed watches
	# the player's gather sensor, not the player body.
	_refresh()
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)


static func size_for_units(u: int) -> float:
	# Three snapped tiers rather than a 4px-per-unit ramp, so the art is three
	# sprites instead of eight. Pile growth still reads: 1-2 small, 3-5 medium,
	# 6-8 large.
	if u <= 2:
		return 16.0
	if u <= 5:
		return 32.0
	return 48.0


func _spread_factor() -> float:
	# Rot accelerates near an already-rotten pile. Checked only once the clump
	# has started browning, so a fresh drop is never instantly doomed.
	if game == null or age < ROT_WARN or is_rotten():
		return 1.0
	for c in game.world.get_children():
		if c == self or not (c is Seaweed):
			continue
		var o := c as Seaweed
		if o.drifting or o.kelp or not o.is_rotten():
			continue
		if position.distance_to(o.position) < ROT_SPREAD_RADIUS:
			return ROT_SPREAD_RATE
	return 1.0


func is_rotten() -> bool:
	return age >= ROT_TIME


func rot_progress() -> float:
	if kelp or drifting or age <= ROT_WARN:
		return 0.0
	return clampf((age - ROT_WARN) / (ROT_TIME - ROT_WARN), 0.0, 1.0)


func value_per_unit() -> int:
	if game == null:
		return 1
	# Explicit type: `game` is untyped, so := has nothing to infer from here.
	var v: int = game.price_per_unit * (3 if kelp else 1)
	if is_rotten():
		v = max(1, int(v / 2))
	return v


func absorb(n: int) -> void:
	# Fresh material coming in makes the pile as a whole a bit less far gone.
	var total := units + n
	age = age * float(units) / float(total)
	units = min(total, MAX_PILE)
	_refresh()


func _punch() -> void:
	if _popping:
		return
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.18, 0.86), 0.05)
	tw.tween_property(self, "scale", Vector2.ONE, 0.09).set_trans(Tween.TRANS_BACK)


func _pop_and_free() -> void:
	# Scale up and fade rather than blinking out. The pile is the thing the
	# player is aiming at, so its removal is the moment worth selling.
	if _popping:
		return
	_popping = true
	set_process(false)
	if _shape != null:
		_shape.set_deferred("disabled", true)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.5, 1.5), 0.16).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(self, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(queue_free)


func _refresh() -> void:
	_size = size_for_units(units)
	_rect.size = Vector2(_size, _size)
	_rect.position = -Vector2(_size, _size) / 2.0

	if kelp:
		_base_color = Color(0.10, 0.52, 0.46)
	elif drifting:
		_base_color = Color(0.30, 0.60, 0.42)     # paler: still afloat
	elif units <= 1:
		_base_color = Color(0.24, 0.58, 0.28)
	else:
		_base_color = Color(0.13, 0.36, 0.20)
	_apply_textures()
	_apply_rot_tint()

	if _shape != null:
		(_shape.shape as RectangleShape2D).size = Vector2(_size, _size)


func _tier() -> int:
	# Matches size_for_units(): 1-2 small, 3-5 medium, 6-8 large.
	if units <= 2:
		return 0
	if units <= 5:
		return 1
	return 2


func _frames_per_tier(arr: Array[Texture2D]) -> int:
	return max(1, arr.size() / 3)


func _pick(arr: Array[Texture2D], frame: int = 0) -> Texture2D:
	if arr.is_empty():
		return null
	var fpt := _frames_per_tier(arr)
	var i := _tier() * fpt + (frame % fpt)
	if arr.size() > i and arr[i] != null:
		return arr[i]
	return null


func _variant_key() -> String:
	if kelp:
		return "kelp"
	return "drift" if drifting else "fresh"


func _base_array() -> Array[Texture2D]:
	if kelp:
		return tex_kelp
	return tex_drift if drifting else tex_fresh


func _tick_sway(delta: float) -> void:
	var arr := _base_array()
	if _frames_per_tier(arr) < 2:
		return
	_anim_t += delta * float(SWAY_FPS.get(_variant_key(), 3.0))
	var f := int(_anim_t) % _frames_per_tier(arr)
	if f != _anim_frame:
		_anim_frame = f
		var tex := _pick(arr, f)
		if tex != null:
			_fit(_sprite, tex)


func _fit(sprite: Sprite2D, tex: Texture2D) -> void:
	sprite.texture = tex
	if tex == null:
		sprite.visible = false
		return
	var t := tex.get_size()
	if t.x > 0.0 and t.y > 0.0:
		sprite.scale = Vector2(_size / t.x, _size / t.y)


func _apply_textures() -> void:
	var base := _pick(_base_array(), max(0, _anim_frame))
	_fit(_sprite, base)
	_sprite.visible = base != null
	_rect.visible = base == null

	# Only beached, non-kelp clumps ever rot, so nothing else needs the layer.
	var rot: Texture2D = _pick(tex_rot) if (not kelp and not drifting) else null
	_fit(_sprite_rot, rot)


func _apply_rot_tint() -> void:
	var p := rot_progress()
	if _sprite.texture != null:
		# Cross-fade a real rotten sprite in on top. Tinting the fresh texture
		# with modulate would MULTIPLY green by brown and just look muddy.
		_sprite_rot.visible = _sprite_rot.texture != null and p > 0.0
		_sprite_rot.modulate = Color(1, 1, 1, p)

		# Fully rotten: hide the fresh sprite outright rather than trusting the
		# rotten one to cover it. Any gap in the silhouette would leak green
		# through at exactly the moment the pile must read as dead and urgent.
		_sprite.visible = not (p >= 0.999 and _sprite_rot.texture != null)
	else:
		_rect.color = _base_color.lerp(ROT_COLOR, p)


func _on_area_entered(area: Area2D) -> void:
	var owner_node := area.get_parent()
	if owner_node is Player:
		_player = owner_node
		_timer = 0.0


func _on_area_exited(area: Area2D) -> void:
	if area.get_parent() == _player:
		_player = null


func _process(delta: float) -> void:
	_tick_sway(delta)
	if drifting:
		_do_drift(delta)
	elif not kelp:
		# Beached seaweed rots where it sits. Kelp is alive and rooted, so it
		# never spoils -- that is part of why the deep is worth the trip.
		var was_rotten := is_rotten()
		# Rot speed scales with the shift: later shifts give you less grace before
		# a pile starts costing reputation at 6x.
		var rot_rate: float = float(game.rot_scale()) if game != null else 1.0
		age += delta * _spread_factor() / rot_rate
		if age > ROT_WARN:
			_apply_rot_tint()
			if is_rotten() and not was_rotten and game != null:
				game.popup("rotted", global_position, ROT_COLOR)
				game.sfx("rot", randf_range(0.9, 1.1), -4.0)
	_do_gather(delta)


func _do_drift(delta: float) -> void:
	# Storms shove the whole raft in much faster -- that surge is what makes a
	# storm read as an incoming wall of work rather than just a colour change.
	var mult: float = 2.5 if (game != null and game.storm_active) else 1.0
	_sway += delta * 0.9

	position.y -= drift_speed * mult * delta
	position.x += sin(_sway) * 5.0 * delta
	position.x = clampf(position.x, 22.0, 338.0)

	if position.y <= shore_y:
		_settle()


func _settle() -> void:
	drifting = false
	position.y = shore_y + randf_range(-10.0, 12.0)

	# Merge into a neighbouring beached pile if there is one. This is what
	# grows the shoreline into clumps too big to clear in a single pass.
	if game != null:
		var host = game.find_pile_near(global_position, self)
		if host != null:
			host.absorb(units)
			queue_free()
			return

	_refresh()


func _do_gather(delta: float) -> void:
	if _player == null:
		return
	if _player.is_full():
		return

	_timer += delta
	if _timer < _player.gather_interval:
		return

	_timer = 0.0
	units -= 1
	_player.add_seaweed(1, value_per_unit())

	if game != null:
		# Pitch climbs as the pile empties, so working a big clump builds. The
		# ramp is gentle because pickup is a two-note motif, not a blip --
		# stretch it far and it goes chipmunk.
		var pitch := 1.0 + 0.035 * float(MAX_PILE - units)
		if kelp:
			pitch += 0.12
			game.popup("+1 kelp", global_position, Color(0.4, 0.95, 0.85))
		elif is_rotten():
			pitch = 0.85
			game.popup("+1 rot", global_position, Color(0.70, 0.58, 0.36))
		else:
			game.popup("+1", global_position, Color(0.55, 0.95, 0.55))
		game.sfx("pickup", pitch, -1.0)
		if _player.is_full():
			game.sfx("full")

	if units <= 0:
		_pop_and_free()
	else:
		# A small punch each time a unit comes off, so a big pile visibly
		# reacts to every grab rather than only when it disappears.
		_refresh()
		_punch()
