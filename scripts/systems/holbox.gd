class_name Holbox
extends Node2D

# Isla Holbox: a round island with sea on every side, and three signature
# events drawn from what Holbox is famous for. One at a time, rotating, never the
# same twice running. Storms and Happy Hour are switched off on this level --
# with the skip in the middle of the island collecting is easy, so Holbox is a
# change of pace and picture rather than a step up in difficulty.
#
#   WHALE SHARK  A whale shark surfaces off one side of the island and a crowd of
#                tourists streams out into the water toward it.
#   SANDBAR      The tide drops and a sandbar emerges from the beach out into the
#                deep: for a while you can walk out to deep-water kelp without
#                the trawler. It sinks back gradually, easing you in with it.
#   FLAMINGOS    A flock lands on a stretch of beach. You cannot work that stretch
#                -- or reach the seaweed under them -- until they move on.
#
# The sandbar is drawn in code; the whale shark and flamingos are art.

var game
var active := false
var first := 20.0
var every := 32.0
var whale_len := 13.0
var whale_crowd := 5
var sandbar_len := 16.0
var bar_length := 60.0
var sandbar_width := 28.0
var sandbar_kelp := 3
var flamingo_len := 20.0
var flamingo_arc := 0.5
var flamingo_count := 8

const RAMP := 1.5                 # seconds to arrive and to leave
const WHALE_SCALE := 1.4          # it should feel huge next to the tourists
const WHALE := preload("res://assets/sprites/whale_shark.png")   # top view, head right, 2x

var event := ""                   # "", "whale", "sandbar", "flamingo"
var angle := 0.0                  # which side of the island it is happening on
var _t := 0.0
var _len := 0.0
var _next := 0.0
var _last := ""
var _anim := 0.0
var _birds: Array = []            # {home, phase}
var _arc := 0.5                   # the flock's half-width this time, radians
var _under: Node2D                # drawn beneath the sprites: sandbar, whale
var _over: Node2D                 # drawn with them: flamingos


class Layer extends Node2D:
	var draw_fn: Callable
	func _draw() -> void:
		if draw_fn.is_valid():
			draw_fn.call(self)


func _ready() -> void:
	_under = Layer.new()
	_under.z_index = -3
	_under.draw_fn = _draw_under
	add_child(_under)
	_over = Layer.new()
	_over.z_index = 1
	_over.draw_fn = _draw_over
	add_child(_over)


func configure(beach: Dictionary) -> void:
	var h: Dictionary = beach.get("holbox", {})
	active = not h.is_empty()
	visible = active
	first = float(h.get("first", 20.0))
	every = float(h.get("every", 32.0))
	whale_len = float(h.get("whale_len", 13.0))
	whale_crowd = int(h.get("whale_crowd", 5))
	sandbar_len = float(h.get("sandbar_len", 16.0))
	bar_length = float(h.get("sandbar_reach", 60.0))
	sandbar_width = float(h.get("sandbar_width", 28.0))
	sandbar_kelp = int(h.get("sandbar_kelp", 3))
	flamingo_len = float(h.get("flamingo_len", 20.0))
	flamingo_arc = float(h.get("flamingo_arc", 0.5))
	flamingo_count = int(h.get("flamingo_count", 8))
	event = ""
	_last = ""
	_next = first
	_birds.clear()


# ---- the rotation -----------------------------------------------------------

func tick(delta: float) -> void:
	if not active:
		return
	_anim = fposmod(_anim + delta, TAU * 20.0)
	if event == "":
		_next -= delta
		if _next <= 0.0:
			var kinds := ["whale", "sandbar", "flamingo"]
			kinds.erase(_last)
			start(kinds[randi() % kinds.size()])
	else:
		_t += delta
		if _t >= _len:
			event = ""
			_birds.clear()
			_next = every * randf_range(0.85, 1.15)
	_under.queue_redraw()
	_over.queue_redraw()


func presence() -> float:
	# 0 -> 1 as an event arrives, 1 while it lasts, back to 0 as it leaves.
	if event == "":
		return 0.0
	return clampf(minf(_t / RAMP, (_len - _t) / RAMP), 0.0, 1.0)


func _visible_side() -> float:
	# Most of the deep water is off the sides of the screen, so the whale and
	# the sandbar happen above or below the island, where they can be seen.
	return (-PI / 2.0 if randf() < 0.5 else PI / 2.0) + randf_range(-0.45, 0.45)


func start(kind: String) -> void:
	event = kind
	_last = kind
	_t = 0.0
	match kind:
		"whale":
			_len = whale_len
			angle = _visible_side()
			# A crowd rushes out toward it from the edge of town facing it.
			if game != null:
				for i in whale_crowd:
					var a := angle + randf_range(-0.35, 0.35)
					game.spawner.make_tourist(Zones.CENTER + Vector2(cos(a), sin(a)) * Zones.TOURIST_SPAWN_Y,
						randf_range(Zones.SHORE_Y + 8.0, Zones.DEEP_TOP - 10.0), false)
				game.sfx("package", 0.8, -4.0)
		"sandbar":
			_len = sandbar_len
			angle = _visible_side()
			# Kelp out near the end of the bar -- the reward for walking out.
			if game != null:
				var d := Vector2(cos(angle), sin(angle))
				var perp := Vector2(-d.y, d.x)
				for i in sandbar_kelp:
					var r := Zones.DEEP_TOP + bar_length * randf_range(0.45, 0.9)
					game.spawner._add_seaweed(Zones.CENTER + d * r + perp * randf_range(-22.0, 22.0), 5, true, false)
		"flamingo":
			_len = flamingo_len
			_arc = flamingo_arc
			if Zones.STREETS > 0:
				# Midway between two streets, and narrow enough to leave both
				# street mouths clear -- every route in always stays open.
				var k := randi() % Zones.STREETS
				angle = Zones.street_angle(k) + PI / float(Zones.STREETS)
				var r_beach := (Zones.HOTEL_BOTTOM + Zones.SHALLOW_TOP) * 0.5
				var mouth := (Zones.STREET_HALF_W + 6.0) / r_beach
				_arc = minf(flamingo_arc, PI / float(Zones.STREETS) - mouth)
			else:
				# Anywhere but in front of the bay -- the skip must stay reachable.
				var bay_a := (Zones.BAY_POS - Zones.CENTER).angle()
				for tries in 20:
					angle = randf() * TAU
					if absf(angle_difference(angle, bay_a)) > flamingo_arc + 0.5:
						break
			# Spaced out so each bird stands apart -- packed together at this
			# size they merged into a single pink mass.
			_birds.clear()
			for i in flamingo_count:
				var home := Vector2.ZERO
				for tries in 16:
					var a := angle + randf_range(-_arc * 0.85, _arc * 0.85)
					var r := randf_range(Zones.HOTEL_BOTTOM + 4.0, Zones.SHORE_Y - 2.0)
					home = Zones.CENTER + Vector2(cos(a), sin(a)) * r
					var clear := true
					for other in _birds:
						if home.distance_to(other["home"]) < 24.0:
							clear = false
							break
					if clear:
						break
				_birds.append({"home": home, "phase": randf() * TAU, "flip": randf() < 0.5})
			# draw back-to-front so nearer birds overlap farther ones
			_birds.sort_custom(func(p, q): return p["home"].y < q["home"].y)


func status_text() -> String:
	if not active or event == "":
		return ""
	match event:
		"whale":
			return "WHALE SHARK! TOURISTS RUSHING IN"
		"sandbar":
			return "LOW TIDE -- WALK THE SANDBAR" if _t < _len - 3.0 else "TIDE'S COMING BACK IN"
		"flamingo":
			return "FLAMINGOS! WAIT FOR THEM TO MOVE ON"
	return ""


# ---- the sandbar ------------------------------------------------------------

func _bar_axes() -> Array:
	var d := Vector2(cos(angle), sin(angle))
	return [d, Vector2(-d.y, d.x)]


# The bar surfaces in sections, from the beach outward, one after another, and
# sinks back the same way, tip first.
const BAR_CHUNKS := 7


func _bar_root() -> float:
	return Zones.SHORE_Y - 10.0


func _chunk_up(i: int) -> float:
	# 0..1: how far section i has surfaced. Overlapping ramps, so each section
	# starts rising a beat after the one before it.
	return clampf(presence() * float(BAR_CHUNKS + 1) - float(i), 0.0, 1.0)


func _bar_end() -> float:
	# Walkable out to the last section that is more than half up.
	var full := Zones.DEEP_TOP + bar_length
	var up := 0
	for i in BAR_CHUNKS:
		if _chunk_up(i) >= 0.5:
			up = i + 1
	return maxf(Zones.SHALLOW_TOP, lerpf(_bar_root(), full, float(up) / float(BAR_CHUNKS)))



func on_sandbar(p: Vector2) -> bool:
	if not active or event != "sandbar":
		return false
	var ax := _bar_axes()
	var v := p - Zones.CENTER
	var along := v.dot(ax[0])
	return along >= Zones.SHORE_Y - 10.0 and along <= _bar_end() \
		and absf(v.dot(ax[1])) <= sandbar_width * 0.5


func sandbar_reach(p: Vector2) -> float:
	# How far out the worker may go while standing on the bar.
	return _bar_end() - 6.0 if on_sandbar(p) else 0.0


func keep_on_sandbar(p: Vector2, normal_max: float) -> Vector2:
	# Past the normal limit, stepping sideways off the bar would drop the worker
	# into deep water -- instead, they are held to its edge.
	if not active or event != "sandbar":
		return p
	var ax := _bar_axes()
	var v := p - Zones.CENTER
	var along := v.dot(ax[0])
	if v.length() <= normal_max or along < Zones.SHORE_Y or along > _bar_end() + 20.0:
		return p
	var lat := clampf(v.dot(ax[1]), -sandbar_width * 0.5, sandbar_width * 0.5)
	return Zones.CENTER + ax[0] * minf(along, _bar_end() - 6.0) + ax[1] * lat


# ---- the flamingos ----------------------------------------------------------

func blocks(p: Vector2) -> bool:
	# Their stretch of beach: no walking in, and no gathering from it.
	if not active or event != "flamingo" or presence() < 0.5:
		return false
	var v := p - Zones.CENTER
	var r := v.length()
	return r >= Zones.HOTEL_BOTTOM - 6.0 and r <= Zones.SHALLOW_TOP + 8.0 \
		and absf(angle_difference(v.angle(), angle)) < _arc


func keep_off_flamingos(p: Vector2) -> Vector2:
	if not blocks(p):
		return p
	# Step out to whichever edge of the flock is nearer, at the same distance
	# from the centre -- sideways along the beach, never into the sea.
	var v := p - Zones.CENTER
	var off := angle_difference(angle, v.angle())
	# A hair past the edge: exactly on it, rounding can leave the worker inside.
	var edge := angle + (_arc + 0.03 if off > 0.0 else -_arc - 0.03)
	return Zones.CENTER + Vector2(cos(edge), sin(edge)) * v.length()


# ---- drawing ----------------------------------------------------------------

func _draw_under(c: CanvasItem) -> void:
	if not active:
		return
	if event == "sandbar":
		_draw_sandbar(c)
	elif event == "whale":
		_draw_whale(c)


func _draw_over(c: CanvasItem) -> void:
	if active and event == "flamingo":
		_draw_flamingos(c)


func _draw_sandbar(c: CanvasItem) -> void:
	var ax := _bar_axes()
	var d: Vector2 = ax[0]
	var perp: Vector2 = ax[1]
	var r0 := _bar_root()
	var full := Zones.DEEP_TOP + bar_length
	var step := (full - r0) / float(BAR_CHUNKS)
	var w := sandbar_width * 0.5
	for i in BAR_CHUNKS:
		var up := _chunk_up(i)
		if up <= 0.0:
			continue
		var ra := r0 + step * float(i)
		var rb := ra + step + 1.0          # a hair of overlap, no seams
		# Tapers toward the tip, and swells from narrow to full as it surfaces.
		var rise := up * up * (3.0 - 2.0 * up)
		var ka := (1.0 - 0.25 * float(i) / float(BAR_CHUNKS)) * w * (0.45 + 0.55 * rise)
		var kb := (1.0 - 0.25 * float(i + 1) / float(BAR_CHUNKS)) * w * (0.45 + 0.55 * rise)
		var pa := Zones.CENTER + d * ra
		var pb := Zones.CENTER + d * rb
		var poly := PackedVector2Array([pa + perp * ka, pb + perp * kb, pb - perp * kb, pa - perp * ka])
		if i == BAR_CHUNKS - 1:
			poly = PackedVector2Array([pa + perp * ka, pb + perp * kb * 0.75, pb + d * 8.0, pb - perp * kb * 0.75, pa - perp * ka])
		c.draw_colored_polygon(poly, Color(0.87, 0.80, 0.62, up))
		# a wet, darker band down the middle
		c.draw_line(pa, pb, Color(0.74, 0.66, 0.50, 0.6 * up), ka * 0.6)
		# foam along both edges
		for side in [-1.0, 1.0]:
			var pts := PackedVector2Array()
			var s := ra
			while s <= rb:
				var t := (s - ra) / maxf(rb - ra, 1.0)
				pts.append(Zones.CENTER + d * s + perp * (lerpf(ka, kb, t) + 2.0 + sin(s * 0.3 + _anim * 3.0) * 1.2) * side)
				s += 4.0
			c.draw_polyline(pts, Color(1, 1, 1, 0.75 * up), 2.0)
		# a burst of white water as each section breaks the surface
		if up < 1.0:
			var splash := sin(up * PI)
			c.draw_circle((pa + pb) * 0.5, (ka + 6.0) * (0.6 + 0.6 * up), Color(1, 1, 1, 0.45 * splash), false, 2.0)


func _draw_whale(c: CanvasItem) -> void:
	# A whale shark gliding along just under the surface, off one side.
	var a := presence()
	var sweep := angle + (_t / maxf(_len, 0.01) - 0.5) * 0.6
	var pos := Zones.CENTER + Vector2(cos(sweep), sin(sweep)) * (Zones.DEEP_TOP + 32.0)
	var fwd := Vector2(-sin(sweep), cos(sweep))
	var sz := WHALE.get_size() * 2.0 * WHALE_SCALE * 0.75
	c.draw_set_transform(pos, fwd.angle(), Vector2.ONE)
	c.draw_texture_rect(WHALE, Rect2(-sz * 0.5, sz), false, Color(1, 1, 1, 0.9 * a))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# a ring of ripples where it breaks the surface
	c.draw_arc(pos, sz.x * 0.62 + sin(_anim * 2.0) * 3.0, 0.0, TAU, 28, Color(1, 1, 1, 0.35 * a), 2.0)


func _draw_flamingos(c: CanvasItem) -> void:
	# Pink birds flying in from out at sea, standing about, then leaving.
	var a := presence()
	for b in _birds:
		var home: Vector2 = b["home"]
		var pos := home + Zones.outward(home) * (1.0 - a) * 140.0 + Vector2(0, -(1.0 - a) * 40.0)
		Flamingos.draw_bird(c, pos, a < 1.0, b["flip"], _anim, b["phase"])
