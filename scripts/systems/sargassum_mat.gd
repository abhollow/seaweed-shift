class_name SargassumMat
extends Node2D

# Mahahual, in sargassum season.
#
# A share of everything that washes in is SARGASSUM (see Seaweed.make_sargassum):
# heavy, worth double, quick to rot.
#
# THE MAT is the signature event: a huge raft of sargassum appears far out and
# drifts slowly toward the beach -- about twenty seconds of visible warning,
# straight toward where it will land. When it reaches the shallows it breaks up
# into a heap of sargassum piles along that stretch. How much it drops scales
# with the shift, like the ferry wake and Bacalar's big wave: light on foot,
# heavy once the player has the gear.

var game
var active := false
var share := 0.0                 # of ordinary spawns that come in as sargassum
var mat_first := 30.0
var mat_every := 65.0
var mat_speed := 12.0
var mat_width := 110.0
var _piles: Array = [4, 6, 8, 10]

var mat_x := -1.0                # < 0 when there is no mat
var mat_y := 0.0
var _next := 0.0
var _ashore_t := 0.0
var _seed := 0.0
var _anim := 0.0


func configure(beach: Dictionary) -> void:
	var m: Dictionary = beach.get("sargassum", {})
	active = not m.is_empty()
	visible = active
	share = float(m.get("share", 0.0)) if active else 0.0
	mat_first = float(m.get("mat_first", 30.0))
	mat_every = float(m.get("mat_every", 65.0))
	mat_speed = float(m.get("mat_speed", 12.0))
	mat_width = float(m.get("mat_width", 110.0))
	_piles = m.get("mat_piles", [4, 6, 8, 10])
	mat_x = -1.0
	_ashore_t = 0.0
	_next = mat_first


func piles_for(shift_index: int) -> int:
	return int(_piles[clampi(shift_index, 0, _piles.size() - 1)])


func drifting_in() -> bool:
	return active and mat_x >= 0.0


func status_text() -> String:
	if drifting_in():
		return "SARGASSUM MAT DRIFTING IN"
	if _ashore_t > 0.0:
		return "THE MAT HAS COME ASHORE"
	return ""


func launch() -> void:
	mat_x = randf_range(mat_width * 0.5 + 10.0, Zones.VIEW_W - mat_width * 0.5 - 10.0)
	mat_y = Zones.VIEW_H + 40.0
	_seed = randf() * 100.0
	_next = mat_every * randf_range(0.85, 1.15)


func tick(delta: float) -> void:
	if not active:
		return
	_anim = fposmod(_anim + delta, TAU * 20.0)
	_ashore_t = maxf(0.0, _ashore_t - delta)
	if drifting_in():
		mat_y -= mat_speed * delta
		if mat_y <= Zones.SHALLOW_TOP:
			_break_up()
	else:
		_next -= delta
		if _next <= 0.0:
			launch()
	queue_redraw()


func units_for(shift_index: int) -> int:
	# Two units per "pile" of the per-shift table: 8 / 12 / 16 / 20.
	return piles_for(shift_index) * 2


func _break_up() -> void:
	# The mat comes ashore as big HEAPS of sargassum -- grouped mounds of up to
	# twelve units -- across the stretch of beach it came in on, with any
	# remainder as an ordinary pile.
	if game != null:
		var left := units_for(game.level_index)
		var spots := int(ceil(float(left) / float(Seaweed.HEAP_MAX)))
		for i in spots:
			var u := mini(left, Seaweed.HEAP_MAX)
			left -= u
			var x := mat_x + (float(i) - float(spots - 1) * 0.5) * 72.0
			var y := Zones.SHORE_Y - 14.0
			var sw: Seaweed = game.spawner._add_seaweed(Vector2(clampf(x, 44.0, Zones.VIEW_W - 44.0), y), u, false, false)
			if u >= Seaweed.HEAP_SHOWS:
				sw.make_heap()
			else:
				sw.make_sargassum()
		game.shake(4.0, 0.25)
		game.sfx("dump", 0.55, -5.0)
	mat_x = -1.0
	_ashore_t = 2.5


func _draw() -> void:
	if not drifting_in():
		return
	# An irregular raft of brown-gold weed with a white fringe where it meets the
	# water, rolling gently as it comes.
	var c := Vector2(mat_x, mat_y)
	var rim := PackedVector2Array()
	var body := PackedVector2Array()
	for i in 28:
		var a := float(i) / 28.0 * TAU
		var wob := 1.0 + 0.18 * sin(a * 3.0 + _seed) + 0.1 * sin(a * 7.0 + _seed * 2.0 + _anim)
		var r := Vector2(cos(a) * mat_width * 0.5, sin(a) * mat_width * 0.22) * wob
		rim.append(c + r * 1.08)
		body.append(c + r)
	draw_colored_polygon(rim, Color(1, 1, 1, 0.45))
	draw_colored_polygon(body, Color(0.55, 0.36, 0.12, 0.92))
	for i in 46:
		var a := fposmod(float(i) * 2.399, TAU)
		var d := sqrt(fposmod(float(i) * 0.137, 1.0))
		var q := c + Vector2(cos(a) * mat_width * 0.45, sin(a) * mat_width * 0.19) * d
		var col := Color(0.86, 0.62, 0.22) if i % 3 else Color(0.38, 0.24, 0.07)
		draw_rect(Rect2(q, Vector2(3, 3)), col)
