extends SceneTree

# Headless bot playtest: plays the four shifts of one level the way a decent
# player would, and reports how each one went. Run with:
#   godot --headless --path . --script res://tools/playtest_bot.gd ++ level=3 out=C:/tmp/l3.jsonl
#
# Args (after ++): level=N (1-10), out=path for JSON lines, ts=time scale
# (default 4), fails=retries per shift before skipping (default 3),
# limit=game seconds per attempt before calling it stuck (default 1500).
#
# The level starts the way a real campaign arrives there: with one upgrade
# retained per level already finished, in RETAIN_ORDER.
#
# The bot sees the whole beach (night darkness does not blind it) and reacts
# instantly, but it is not clever: greedy pile choice, simple tourist dodging.
# Treat its times as a lower bound on a human's and its failures as real.

const RETAIN_ORDER := ["rake2", "backpack", "waders", "jacket", "tractor", "sorter",
	"sand_tires", "hopper", "diesel", "trawler"]
const BUY_ORDER := ["rake2", "backpack", "jacket", "waders", "tractor", "sorter", "seagull",
	"sand_tires", "hopper", "diesel", "trawler"]

var game
var level := 1
var out_path := ""
var time_scale := 4.0
var max_fails := 3
var limit := 1500.0
var start_shift := 1         # >1: jump straight in, owning every earlier tier
var stop_after := false     # end after the first shift resolves

var _target = null            # Node2D or Vector2 (home)
var _blacklist := {}          # instance_id -> game time it expires
var _stuck_t := 0.0
var _stuck_from := Vector2.ZERO
var _jitter_t := 0.0
var _jitter := Vector2.ZERO
var _retarget_t := 0.0
var _last_stun := 0.0
var _prev_carried := 0
var _tourist_prev := {}

# per-attempt stats
var st := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := String(a).split("=", true, 1)
		if kv.size() != 2:
			continue
		match kv[0]:
			"level": level = int(kv[1])
			"out": out_path = kv[1]
			"ts": time_scale = float(kv[1])
			"fails": max_fails = int(kv[1])
			"limit": limit = float(kv[1])
			"debug": debug = kv[1] == "1"
			"shift": start_shift = int(kv[1])
			"stop": stop_after = kv[1] == "1"
	_run()


func _now() -> float:
	return game.shift_elapsed if game != null else 0.0


func _emit(d: Dictionary) -> void:
	var line := JSON.stringify(d)
	print("BOT|" + line)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()


func _run() -> void:
	Engine.time_scale = time_scale
	Engine.physics_ticks_per_second = int(60.0 * time_scale)
	Engine.max_physics_steps_per_frame = 64
	seed(1000 + level)

	game = load("res://scenes/main.tscn").instantiate()
	game.start_fresh = true
	game.tutorial_done = true
	root.add_child(game)
	for i in 5:
		await process_frame

	# Arrive at this level as the campaign would.
	var kept := {}
	for i in mini(level - 1, RETAIN_ORDER.size()):
		kept[RETAIN_ORDER[i]] = true
	game.retained = kept
	game.level = level
	game.credits = 0
	game.level_index = start_shift - 1
	game.owned = kept.duplicate()
	for up in Upgrades.LIST:
		if int(up["tier"]) < start_shift:
			game.owned[String(up["id"])] = true
	game._reset_player_stats()
	for up in Upgrades.LIST:
		if game.owned.has(String(up["id"])):
			game.apply_upgrade(String(up["id"]))
	game._recompute_carry()
	game.apply_beach()
	game.begin_level()
	game.level_intro.visible = false
	paused = false
	game.joystick.active = true

	var shift := start_shift - 1
	var attempt := 1
	_reset_stats(shift, attempt)
	while true:
		await process_frame
		if game.level_done and paused and game.level_panel.visible:
			_finish_attempt("complete")
			if stop_after:
				break
			if game.level_index + 1 >= Levels.LIST.size():
				break
			game.next_shift()
			shift = game.level_index
			attempt = 1
			_reset_stats(shift, attempt)
			continue
		if game.level_failed and paused:
			_finish_attempt("fail")
			if attempt < max_fails:
				game.retry_shift()
				attempt += 1
				_reset_stats(shift, attempt)
			else:
				if stop_after or not _skip_shift():
					break
				shift = game.level_index
				attempt = 1
				_reset_stats(shift, attempt)
			continue
		if paused:
			continue
		if _now() > limit:
			_finish_attempt("timeout")
			if stop_after or not _skip_shift():
				break
			shift = game.level_index
			attempt = 1
			_reset_stats(shift, attempt)
			continue
		_drive(root.get_process_delta_time())
		_sample(root.get_process_delta_time())

	_emit({"kind": "done", "level": level})
	quit()


func _skip_shift() -> bool:
	# Moves on as if the shift had been passed, without its credits.
	game.level_panel.visible = false
	game.level_failed = false
	game.level_done = false
	paused = false
	game.joystick.active = true
	if game.level_index + 1 >= Levels.LIST.size():
		return false
	game.level_index += 1
	game.shift_fails = 0
	game.begin_level()
	return true


func _reset_stats(shift: int, attempt: int) -> void:
	st = {
		"kind": "shift", "level": level, "shift": shift + 1, "attempt": attempt,
		"goal": game.shift_target(),
		"owned_start": game.owned.keys(),
		"credits_start": game.credits,
		"hits": 0, "loads_dropped": 0, "hit_log": [], "buys": [], "storm_s": 0.0, "happy_s": 0.0,
		"rep_min": 100.0, "rep_low_s": 0.0, "rep_zero_s": 0.0, "trips": 0,
		"rep_trace": [], "earned_trace": [], "max_beached": 0, "rotted_peak": 0,
		"adapt": game.adapt, "stuck_events": 0, "beached_trace": [], "tourist_trace": [],
	}
	_target = null
	_blacklist.clear()
	_trace_t = 0.0


var _trace_t := 0.0


func _sample(dt: float) -> void:
	var r: float = game.rep.value
	st["rep_min"] = minf(st["rep_min"], r)
	if r < 30.0:
		st["rep_low_s"] += dt
	if r <= 0.5:
		st["rep_zero_s"] += dt
	if game.storm_active:
		st["storm_s"] += dt
	if game.happy_hour:
		st["happy_s"] += dt
	st["rotted_peak"] = maxi(st["rotted_peak"], game.rep.rotten_piles)
	var stun: float = game.player._stun
	if stun > _last_stun + 0.5:
		st["hits"] += 1
		if _prev_carried > 0:
			st["loads_dropped"] += _prev_carried
			st["hit_log"].append([int(_now()), _prev_carried, int(game.player.position.x), int(game.player.position.y)])
	_last_stun = stun
	_prev_carried = game.player.carried
	_trace_t += dt
	if _trace_t >= 20.0:
		_trace_t = 0.0
		st["rep_trace"].append(int(r))
		st["earned_trace"].append(game.credits_earned)
		var beached := 0
		for c in game.world.get_children():
			if c is Seaweed and not c.drifting and not c.kelp:
				beached += c.units
		st["max_beached"] = maxi(st["max_beached"], beached)
		st["beached_trace"].append(beached)
		st["tourist_trace"].append(game.spawner.count_tourists())


func _finish_attempt(result: String) -> void:
	st["result"] = result
	st["time_s"] = snappedf(_now(), 0.1)
	st["earned"] = game.credits_earned
	st["bonus"] = game.shift_bonus if result == "complete" else 0
	st["credits_end"] = game.credits
	st["owned_end"] = game.owned.keys()
	st["storm_s"] = snappedf(st["storm_s"], 0.1)
	st["happy_s"] = snappedf(st["happy_s"], 0.1)
	st["rep_low_s"] = snappedf(st["rep_low_s"], 0.1)
	st["rep_zero_s"] = snappedf(st["rep_zero_s"], 0.1)
	st["rep_min"] = snappedf(st["rep_min"], 0.1)
	st["adapt_end"] = game.adapt
	_emit(st)


# =============================================================================
# The player
# =============================================================================

func _buy() -> void:
	for id in BUY_ORDER:
		if game.owned.has(id):
			continue
		var up := Upgrades.by_id(id)
		if int(up["tier"]) > game.shop_tier():
			continue
		var needs := String(up["needs"])
		if needs != "" and not game.owned.has(needs):
			continue
		if game.credits >= int(up["cost"]):
			game.buy(id)
			if game.owned.has(id):
				st["buys"].append("%s@%ds" % [id, int(_now())])
		return   # buy strictly in order: save up for the next one


func _reachable(p: Vector2) -> bool:
	var pl = game.player
	var d := Zones.depth(p)
	if d > pl.max_y + 6.0:
		return false
	if not Zones.RADIAL and p.y < pl.min_y - 20.0:
		return false
	if game.holbox != null and game.holbox.blocks(p):
		return false
	return true


func _pile_score(sw: Seaweed, from: Vector2, speed: float, room: int) -> float:
	var take := mini(sw.units, room / sw.weight())
	if take <= 0:
		return -1.0
	var dist := from.distance_to(sw.position)
	var t: float = dist / maxf(_speed_to(sw.position, speed), 1.0) + take * game.player.gather_interval + 0.5
	var v: float = take * sw.value_per_unit()
	if not sw.drifting and not sw.kelp:
		# Reputation pressure: rotting and VIP piles first, harder when the
		# meter is sliding.
		var w: float = 1.0 + 5.0 * sw.rot_progress()
		if game.in_vip(sw.position):
			w *= game.vip_weight
		var urgency: float = 1.0 + (100.0 - game.rep.value) / 25.0
		v += take * w * 6.0 * urgency
		if game.hatch != null and game.hatch.hatching():
			v += 30.0
	else:
		v *= 0.6
		# Kelp pays well but is out of the guests' sight: leave it while the
		# beach needs you.
		if sw.kelp and game.rep.value < 85.0:
			v *= 0.25
	return v / t


func _choose() -> void:
	var pl = game.player
	var room: int = pl.capacity - pl.carried
	if room <= 0 or (room < 2 and pl.carried > 0 and _sarg_only()):
		_target = Zones.BAY_POS
		return
	var speed: float = pl.current_speed()
	var best = null
	var best_s := 0.0
	var now := _now()
	for c in game.world.get_children():
		if c is Seaweed:
			var sw := c as Seaweed
			if sw.is_queued_for_deletion() or sw._popping or sw.units <= 0:
				continue
			if _blacklist.get(sw.get_instance_id(), -1.0) > now:
				continue
			if not _reachable(sw.position):
				continue
			var s := _pile_score(sw, pl.position, speed, room)
			if is_same(_target, sw):
				s *= 1.3
			if s > best_s:
				best_s = s
				best = sw
		elif c is Package and game.rep.value > 60.0:
			if _reachable(c.position) and _blacklist.get(c.get_instance_id(), -1.0) <= now:
				var tt: float = pl.position.distance_to(c.position) / maxf(speed, 1.0)
				if tt < c._life - 1.0:
					var s2: float = float(c.value) / (tt + 0.5)
					if s2 > best_s:
						best_s = s2
						best = c
	# Bank a decent load rather than wander far for little.
	if pl.carried > 0:
		var home_t: float = pl.position.distance_to(Zones.BAY_POS) / maxf(speed, 1.0)
		var bank: float = pl.carried_value / (home_t + 0.5)
		# A careful player banks big loads early: one tourist takes it all.
		var safe_load: float = minf(pl.capacity * 0.7, 30.0)
		if best == null or (pl.carried >= safe_load and bank > best_s * 0.5):
			_target = Zones.BAY_POS
			return
	_target = best if best != null else _idle_spot()


func _speed_to(p: Vector2, _speed: float) -> float:
	# Water drags: price the trip at the speed you will actually wade at.
	var pl = game.player
	var base: float = pl.base_speed * pl.speed_mult
	if game.storm_active and not pl.has_rain_jacket:
		base *= Player.STORM_SLOW
	var d := Zones.depth(p)
	if d >= Zones.SHALLOW_TOP:
		var k: float
		if pl.on_vehicle:
			k = 1.0 if pl.has_sand_tires else 0.45
		else:
			k = 1.0 if pl.has_waders else 0.30
		if d >= Zones.DEEP_TOP:
			k *= 0.72
		return base * (0.5 + 0.5 * k)
	return base


func _sarg_only() -> bool:
	return game.mat != null and game.mat.share > 0.0


func _idle_spot() -> Vector2:
	# Nothing to do: wait near the shoreline in the middle, ready.
	return Zones.at_depth(Vector2(180, 300), Zones.SHORE_Y - 20.0) if not Zones.RADIAL \
		else Zones.CENTER + Vector2(0, -1) * (Zones.SHORE_Y - 10.0)


func _goal_pos() -> Vector2:
	if typeof(_target) == TYPE_VECTOR2:
		return _target
	if _target != null and is_instance_valid(_target):
		if _target is Seaweed:
			return _aim_for(_target as Seaweed)
		return (_target as Node2D).position
	return game.player.position


func _aim_for(sw: Seaweed) -> Vector2:
	# Every pile inside the rake's reach is raked at once, so stand where the
	# reach covers the neighbours too -- keeping the target itself in reach.
	var pl = game.player
	var hs: Vector2 = (pl._shape.shape as RectangleShape2D).size
	var half: float = maxf(hs.x, hs.y) * 0.5 + pl.reach
	if sw.units <= 0:
		return sw.position
	var sum: Vector2 = sw.position * sw.units
	var w := float(sw.units)
	for c in game.world.get_children():
		if c is Seaweed and c != sw and not c.drifting and not c._popping:
			var d: float = (c as Seaweed).position.distance_to(sw.position)
			if d < half * 1.4:
				sum += (c as Seaweed).position * (c as Seaweed).units
				w += (c as Seaweed).units
	var aim := sum / w
	var off := aim - sw.position
	if off.length() > half * 0.6:
		aim = sw.position + off.normalized() * half * 0.6
	return aim


var _dt := 0.016
var debug := false
var _dbg_t := 0.0


func _drive(dt: float) -> void:
	_dt = dt
	var pl = game.player
	if debug:
		_dbg_t += dt
		if _dbg_t > 1.0:
			_dbg_t = 0.0
			var near := 999.0
			for c in game.world.get_children():
				if c is Tourist:
					near = minf(near, pl.position.distance_to(c.position))
			var bu := 0
			var du := 0
			for c in game.world.get_children():
				if c is Seaweed and not c.kelp:
					if c.drifting:
						du += c.units
					else:
						bu += c.units
			var tdesc := "home" if _is_home() else ("idle" if typeof(_target) == TYPE_VECTOR2 else ("pile u=%d d=%s k=%s" % [_target.units, _target.drifting, _target.kelp] if _target is Seaweed else str(_target)))
			print("%s pos=%s goal=%s | " % [tdesc, str(pl.position.round()), str(_goal_pos().round())], "t=%d carry=%d/%d rep=%d storm=%s beached=%d drifting=%d mess=%d/%d tour=%d earned=%d" % [int(_now()),
				pl.carried, pl.capacity, int(game.rep.value), game.storm_active, bu, du, int(game.rep.shore_mess()),
				int(game.mess_full()), int(near), game.credits_earned])
	if int(_now() * 2.0) != int((_now() - dt) * 2.0):
		_buy()
	_retarget_t -= dt
	var lost: bool = _target == null or (not (typeof(_target) == TYPE_VECTOR2) and not is_instance_valid(_target)) \
		or (_target is Seaweed and ((_target as Seaweed)._popping or (_target as Seaweed).is_queued_for_deletion()))
	if _is_home() and pl.carried == 0:
		lost = true
	if lost or _retarget_t <= 0.0:
		_retarget_t = 0.4
		if not (_is_home() and pl.carried > 0 and not lost):
			_choose()
		elif pl.carried < pl.capacity:
			# Heading home, but keep the option to grab something on the way.
			_choose()

	var goal := _goal_pos()
	var way := _waypoint(pl.position, goal)
	var to: Vector2 = way - pl.position
	var dir := Vector2.ZERO
	if to.length() > 3.0:
		dir = to.normalized()
		if to.length() < 12.0:
			dir *= 0.5
	# Into the bay: aim for its middle and keep pushing until the dump.
	dir = _steer(pl.position, dir)
	dir = _lean(pl, dir)
	if _jitter_t > 0.0:
		_jitter_t -= dt
		dir = _jitter
	if dir.length() > 1.0:
		dir = dir.normalized()
	game.joystick.direction = dir

	# Stuck: trying to move but going nowhere.
	if dir.length() > 0.3 and not pl.tumbling() and pl._stun <= 0.0:
		_stuck_t += dt
		if _stuck_t > 2.0:
			if pl.position.distance_to(_stuck_from) < 8.0:
				st["stuck_events"] += 1
				if typeof(_target) == TYPE_OBJECT and is_instance_valid(_target):
					_blacklist[(_target as Node2D).get_instance_id()] = _now() + 8.0
				_jitter = Vector2.from_angle(randf() * TAU)
				_jitter_t = 0.6
				_target = null
			_stuck_t = 0.0
			_stuck_from = pl.position
	else:
		_stuck_t = 0.0
		_stuck_from = pl.position


var _tvel := {}


func _steer(p: Vector2, want: Vector2) -> Vector2:
	# Sample 16 headings plus standing still; simulate each half a second ahead
	# against every tourist's current velocity and keep the one that makes the
	# most progress without coming within reach of anyone.
	var near := []
	var seen := {}
	for c in game.world.get_children():
		if not (c is Tourist):
			continue
		var t := c as Tourist
		var id := t.get_instance_id()
		var prev: Vector2 = _tourist_prev.get(id, t.position)
		seen[id] = t.position
		var v: Vector2 = (t.position - prev) / maxf(_dt, 0.0001)
		# Smoothed: the weave makes frame-to-frame velocity jumpy.
		var sv: Vector2 = _tvel.get(id, v).lerp(v, clampf(_dt * 6.0, 0.0, 1.0))
		_tvel[id] = sv
		if t.position.distance_to(p) < 160.0:
			near.append([t.position, sv, t.rowdy])
	_tourist_prev = seen
	# The level obstacles that are not Tourist nodes: divers (Cozumel), kayaks
	# (Bacalar), tumbling umbrellas (Veracruz). Treated as wide "rowdy" boxes.
	if game.cozumel != null and game.cozumel.active:
		for d in game.cozumel.divers:
			near.append([d["pos"], Vector2.ZERO, true])
	if game.kayaks != null and game.kayaks.active:
		for b in game.kayaks.boats:
			near.append([b["pos"], Vector2(Kayaks.SPEED * game.kayaks._dir, 0), true])
	if game.veracruz != null and game.veracruz.active:
		for u in game.veracruz.umbrellas:
			near.append([u["pos"], Vector2(float(u["v"]), 0), true])
	if near.is_empty() or game.player.in_safe_zone and want == Vector2.ZERO:
		return want

	var speed: float = game.player.current_speed()
	var hs: Vector2 = (game.player._shape.shape as RectangleShape2D).size
	var pad: float = 12.0 if game.player.carried > 0 else 7.0
	var best := want
	var best_s := -INF
	var opts := [Vector2.ZERO]
	if want.length() > 0.01:
		opts.append(want)
	for i in 16:
		opts.append(Vector2.from_angle(TAU * i / 16.0))
	for o in opts:
		var o2: Vector2 = o
		# Clearance to the nearest tourist over the horizon, box against box:
		# negative means the boxes overlap -- a hit.
		var clear := INF
		for k in range(0, 8):
			var tt := 0.08 * k
			var q := p + o2 * speed * tt
			for n in near:
				var tp: Vector2 = n[0] + n[1] * tt
				var th := Vector2(24, 24) if n[2] else Vector2(16, 24)
				var hx := (hs.x + th.x) * 0.5
				var hy := (hs.y + th.y) * 0.5
				# Drunks lurch: give them extra room sideways.
				if n[2]:
					hx += 10.0
				clear = minf(clear, maxf(absf(q.x - tp.x) - hx, absf(q.y - tp.y) - hy))
		var s := o2.dot(want) * 1.0
		if clear < pad:
			s -= (pad - clear) * 0.3 + 3.0
		if s > best_s:
			best_s = s
			best = o2
	return best


func _waypoint(p: Vector2, goal: Vector2) -> Vector2:
	if Zones.RADIAL and Zones.STREETS > 0:
		return _radial_waypoint(p, goal)
	if not game.nests.is_empty():
		return _nest_waypoint(p, goal)
	return goal


func _radial_waypoint(p: Vector2, goal: Vector2) -> Vector2:
	# Holbox: the beach is a ring round a village of radial streets. On the
	# ring, walk round it; into or out of the plaza, use a street.
	var c := Zones.CENTER
	var ring := Zones.HOTEL_BOTTOM + 1.0
	var rp := p.distance_to(c)
	var rg := goal.distance_to(c)
	var p_out := rp >= ring
	var g_out := rg >= ring
	if p_out and g_out:
		return _ring_step(p, goal)
	if not p_out and not g_out:
		return goal
	var k := _open_street(goal if g_out else p)
	var ax := Zones.street_axis(k)
	var v := p - c
	var along := v.dot(ax)
	var lat := absf(v.dot(Vector2(-ax.y, ax.x)))
	if p_out:
		# Heading in: round the ring to this street's mouth, then down it.
		if lat > Zones.STREET_HALF_W - 3.0:
			return _ring_step(p, c + ax * (Zones.HOTEL_BOTTOM + 12.0))
		return goal if along < Zones.PLAZA_R else c + ax * maxf(along - 40.0, 0.0)
	# Heading out: from the plaza or this street, straight out along it.
	if rp <= Zones.PLAZA_R - 2.0 or (lat <= Zones.STREET_HALF_W - 2.0 and along > 0.0):
		if lat > 3.0 and rp > Zones.PLAZA_R - 2.0:
			return c + ax * along      # recentre on the street
		return goal if along + 40.0 > rg else c + ax * (maxf(along, 0.0) + 40.0)
	# On some other street: back down it to the plaza first.
	var ax2 := Zones.street_axis(Zones.nearest_street(p))
	return c + ax2 * maxf(v.dot(ax2) - 40.0, 0.0)


func _ring_step(p: Vector2, goal: Vector2) -> Vector2:
	var c := Zones.CENTER
	var ap := (p - c).angle()
	var ag := (goal - c).angle()
	var diff := angle_difference(ap, ag)
	if absf(diff) < 0.3 and not _flamingo_between(ap, ag):
		return goal
	var r := clampf(p.distance_to(c), Zones.HOTEL_BOTTOM + 12.0, Zones.SHORE_Y)
	var step := c + Vector2.from_angle(ap + clampf(diff, -0.3, 0.3)) * r
	# The flamingos close their stretch of beach; wade round them instead.
	if game.holbox != null and game.holbox.blocks(step):
		step = c + Vector2.from_angle(ap + clampf(diff, -0.3, 0.3)) * (Zones.SHALLOW_TOP + 16.0)
	return step


func _flamingo_between(a0: float, a1: float) -> bool:
	if game.holbox == null:
		return false
	var c := Zones.CENTER
	for i in 5:
		var a := a0 + angle_difference(a0, a1) * float(i) / 4.0
		if game.holbox.blocks(c + Vector2.from_angle(a) * (Zones.HOTEL_BOTTOM + 14.0)):
			return true
	return false


func _nest_waypoint(p: Vector2, goal: Vector2) -> Vector2:
	for r in game.nests:
		var g := (r as Rect2).grow(16.0)
		if not _segment_hits(p, goal, (r as Rect2).grow(10.0)):
			continue
		var corners := [g.position, Vector2(g.end.x, g.position.y), g.end, Vector2(g.position.x, g.end.y)]
		var best: Vector2 = corners[0]
		var best_c := INF
		for q in corners:
			if p.distance_to(q) < 8.0 or _segment_hits(p, q, (r as Rect2).grow(8.0)):
				continue
			var cost: float = p.distance_to(q) + q.distance_to(goal)
			if cost < best_c:
				best_c = cost
				best = q
		return best if best_c < INF else goal
	return goal


func _segment_hits(a: Vector2, b: Vector2, r: Rect2) -> bool:
	for i in 13:
		if r.has_point(a.lerp(b, float(i) / 12.0)):
			return true
	return false


func _is_home() -> bool:
	return typeof(_target) == TYPE_VECTOR2 and _target == Zones.BAY_POS


func _lean(pl, dir: Vector2) -> Vector2:
	# Lean into the stream and the wind the way a player pushes the stick
	# against them: aim for the velocity you want, minus what pushes you.
	var sp: float = maxf(pl.current_speed(), 1.0)
	var push := Vector2.ZERO
	if game.stream != null and game.stream.active:
		sp *= game.stream.slow_at(pl.position)
		push += game.stream.push_at(pl.position, pl.on_vehicle)
	if game.wind != null and game.wind.active():
		push.x += pl.wind_push(true)
	if push.length() < 1.0:
		return dir
	var out: Vector2 = dir - push / sp
	return out.normalized() if out.length() > 1.0 else out


func _open_street(near: Vector2) -> int:
	# The nearest street whose mouth the flamingos are not standing in.
	var k0 := Zones.nearest_street(near)
	if game.holbox == null:
		return k0
	for d in [0, 1, -1, 2, -2, 3, -3, 4]:
		var k := posmod(k0 + d, Zones.STREETS)
		if not game.holbox.blocks(Zones.CENTER + Zones.street_axis(k) * (Zones.HOTEL_BOTTOM + 8.0)):
			return k
	return k0
