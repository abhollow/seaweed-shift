class_name Night
extends Node2D

# The night shift on Cozumel: fog of war. The playable beach is dark, and the
# only light is what you carry and what the resort provides.
#
#   * The worker carries a LANTERN -- a small pool of light. Seaweed washes up
#     where you cannot see it, so the level becomes a search.
#   * The tractor has HEADLIGHTS -- a much bigger pool -- so the upgrade
#     transforms this level rather than merely speeding it up.
#   * Tourists carry PHONES: a small glow that shows where they are. Without it
#     you would walk into people you had no way to see, which is unfair rather
#     than hard.
#   * The resort's torches and pool are fixed pools of light, and the bay is
#     always lit, so the skip can always be found.
#   * THE CLOUDS PART now and then: the moon comes out and the whole beach is
#     lit for a few seconds -- a window to spot every pile and plan a route
#     before the dark closes back in.

const SHADER := preload("res://shaders/night.gdshader")
const MAX_LIGHTS := 24

var game
var active := false
var base_darkness := 0.86
var lantern := 62.0
var headlights := 110.0
var phone := 20.0
var bay_light := 58.0
var fixed: Array = []            # [x, y, r]
var moon_first := 45.0
var moon_every := 70.0
var moon_len := 9.0

var _rect: ColorRect
var _mat: ShaderMaterial
var _dots: Node2D
var _next_moon := 0.0
var _moon_t := -1.0              # seconds into the current moonrise, <0 when none


class Dots extends Node2D:
	# Phone screens drawn ABOVE the darkness, so a tourist reads as a point of
	# light even in the black.
	var night

	func _draw() -> void:
		if night == null or not night.active or night.game == null:
			return
		for c in night.game.world.get_children():
			if c is Tourist:
				var p: Vector2 = (c as Tourist).position + Vector2(5.0, -8.0)
				draw_rect(Rect2(p, Vector2(2.0, 3.0)), Color(0.7, 0.95, 1.0, 0.95))


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.size = Vector2(Zones.VIEW_W, Zones.VIEW_H)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_rect.material = _mat
	add_child(_rect)
	_dots = Dots.new()
	_dots.night = self
	add_child(_dots)
	visible = false


func configure(beach: Dictionary) -> void:
	var n: Dictionary = beach.get("night", {})
	active = not n.is_empty()
	visible = active
	if not active:
		return
	base_darkness = float(n.get("darkness", 0.86))
	lantern = float(n.get("lantern", 62.0))
	headlights = float(n.get("headlights", 110.0))
	phone = float(n.get("phone", 20.0))
	bay_light = float(n.get("bay_light", 58.0))
	fixed = n.get("lights", [])
	moon_first = float(n.get("moon_first", 45.0))
	moon_every = float(n.get("moon_every", 70.0))
	moon_len = float(n.get("moon_len", 9.0))
	_next_moon = moon_first
	_moon_t = -1.0
	_mat.set_shader_parameter("top_y", Zones.HOTEL_BOTTOM)
	_push(0.0)


func moon_shape() -> float:
	# 0 in the dark; eases up to 1 over 1.5s, holds, and eases back down.
	if _moon_t < 0.0:
		return 0.0
	var ramp := 1.5
	var up := clampf(_moon_t / ramp, 0.0, 1.0)
	var down := clampf((moon_len - _moon_t) / ramp, 0.0, 1.0)
	return smoothstep(0.0, 1.0, minf(up, down))


func moonlit() -> bool:
	return active and moon_shape() > 0.05


func darkness() -> float:
	# The moon lifts most of the dark, not all of it -- it is still night.
	return base_darkness * (1.0 - 0.7 * moon_shape())


func player_radius() -> float:
	if game != null and game.player != null and game.player.on_vehicle:
		return headlights
	return lantern


func tick(delta: float) -> void:
	if not active:
		return
	if _moon_t >= 0.0:
		_moon_t += delta
		if _moon_t >= moon_len:
			_moon_t = -1.0
	else:
		_next_moon -= delta
		if _next_moon <= 0.0:
			start_moon()
	_push(delta)
	_dots.queue_redraw()


func start_moon() -> void:
	_moon_t = 0.0
	_next_moon = moon_every * randf_range(0.85, 1.15)


func lights() -> PackedVector3Array:
	var out := PackedVector3Array()
	if game == null:
		return out
	if game.player != null:
		out.append(Vector3(game.player.position.x, game.player.position.y, player_radius()))
	out.append(Vector3(Zones.BAY_POS.x, Zones.BAY_POS.y + 10.0, bay_light))
	for L in fixed:
		out.append(Vector3(float(L[0]), float(L[1]), float(L[2])))
	for c in game.world.get_children():
		if out.size() >= MAX_LIGHTS:
			break
		if c is Tourist:
			var t := c as Tourist
			out.append(Vector3(t.position.x, t.position.y - 6.0, phone))
	return out


func _push(_delta: float) -> void:
	var ls := lights()
	_mat.set_shader_parameter("lights", ls)
	_mat.set_shader_parameter("light_count", ls.size())
	_mat.set_shader_parameter("darkness", darkness())
