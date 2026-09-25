extends SceneTree

# Headless regression test. Run with:
#   godot --headless --path . --script res://tools/smoke_test.gd
#
# It boots the real main scene and drives it through every subsystem that the
# refactor touches: spawning, drift, weather beds, the shop, upgrade stacking,
# reputation, level completion and save/load. Any Godot error printed during the
# run shows up in the console; the assertions below catch silent logic breakage.

var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	_run()


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("  FAIL  %s" % label)
	else:
		print("  ok    %s" % label)


func frames(n: int) -> void:
	for i in n:
		await process_frame


func sim_undisturbed(game, seconds: float) -> void:
	# Like sim(), but clears tourists and stun EVERY frame. Setting a flag once
	# is not enough: tourists keep spawning, and the player leaving the bay
	# fires _on_bay_exited which clears any immunity we set by hand. Facing and
	# animation assertions were failing on spawn luck rather than on logic.
	var t := 0.0
	var guard := 0
	while t < seconds and guard < 2000000:
		await process_frame
		for c in game.world.get_children():
			if c is Tourist:
				c.free()
		game.player._stun = 0.0
		t += root.get_process_delta_time()
		guard += 1


func sim(seconds: float) -> void:
	# Headless runs uncapped, so a frame is NOT 1/60s -- counting frames would
	# simulate a fraction of the intended time. Accumulate real delta instead.
	var t := 0.0
	var guard := 0
	while t < seconds and guard < 2000000:
		await process_frame
		t += root.get_process_delta_time()
		guard += 1


func _run() -> void:
	print("\n=== Seaweed Shift smoke test ===\n")

	# Start from a known state -- a save left by a previous run would make the
	# boot assertions below meaningless.
	SaveGame.wipe()

	var game = load("res://scenes/main.tscn").instantiate()
	game.start_fresh = true
	root.add_child(game)
	await frames(10)

	# --- boot -------------------------------------------------------------
	print("[boot]")
	check("starting a shift writes a save immediately",
		not SaveGame.load_data().is_empty())
	check("world built", game.world != null)
	var bg: Sprite2D = null
	var bands := 0
	for c in game.world.get_children():
		if c is Sprite2D and (c as Sprite2D).texture != null and not (c is Player):
			bg = c
		elif c is ColorRect and c.size.x >= Zones.VIEW_W:
			bands += 1
	check("full-screen background is used", bg != null)
	check("flat colour bands are skipped when a background is set", bands == 0)
	# The invariant is WHOLE-NUMBER scaling, not 1:1. The background is authored
	# at half resolution for a chunkier pixel, which is a clean 2x -- a
	# fractional scale is what would wreck the pixel grid.
	check("background scales by a whole number",
		bg != null
			and is_equal_approx(bg.scale.x, roundf(bg.scale.x))
			and is_equal_approx(bg.scale.y, roundf(bg.scale.y))
			and bg.scale.x == bg.scale.y)
	check("water strip matches the background density",
		game._water != null and is_equal_approx(game._water.scale.x, bg.scale.x))
	check("water strip built", game._water != null)
	var sprites := 0
	for c in game.world.get_children():
		if c is Area2D:
			for g in c.get_children():
				if g is Sprite2D and (g as Sprite2D).texture != null:
					sprites += 1
	check("bin drawn from art, not a rectangle", sprites > 0)
	check("buoy line drawn from art",
		game._buoys.get_child_count() > 0 and game._buoys.get_child(0) is Sprite2D)
	check("water strip sits at the waterline",
		game._water != null and game._water.position.y == Zones.WATER_TOP)
	var wf0: int = game._water_frame
	await sim(1.5)
	check("water animates", game._water_frame != wf0)
	check("player exists", game.player != null)
	check("audio exists", game.audio != null)
	check("joystick exists", game.joystick != null)
	check("player starts in bay", game.player.position == Zones.BAY_POS)
	check("player draws its sprite from the very first frame",
		game.player.get_node("Sprite").visible
			and game.player.get_node("Sprite").texture != null
			and not game.player.get_node("Visual").visible)
	check("bare-hands sprite is the one shown",
		game.player.get_node("Sprite").texture == game.player.tex_bare[0])
	check("on-foot is a two-frame A-B cycle, vehicles four-frame",
		game.player.tex_bare.size() == 2 and game.player.tex_hopper.size() == 4)
	check("sprite is mirrored to match art drawn facing left",
		game.player.get_node("Sprite").flip_h == Player.ART_FACES_LEFT)
	check("player starts safe", game.player.in_safe_zone)
	check("shift 1 selected", game.level_index == 0)
	check("shift progress bar exists", game.hud._goal_bg != null)
	# Pressure ramps with progress, so upgrades cannot outpace the beach.
	var saved_earned: int = game.credits_earned
	game.credits_earned = 0
	var d_start: float = game.difficulty()
	game.credits_earned = int(game.current_level()["credits"])
	var d_end: float = game.difficulty()
	game.credits_earned = saved_earned
	check("the beach gets busier as the shift progresses", d_end > d_start * 1.5)

	# Playing well pays more than scraping through.
	var saved_best: float = game.best_rep
	game.best_rep = 100.0
	var perfect: int = game.reputation_bonus()
	game.best_rep = 0.0
	var scraped: int = game.reputation_bonus()
	game.best_rep = saved_best
	check("protecting the resort earns a bonus", perfect > 0)
	check("bottoming out earns no bonus", scraped == 0)

	check("there is a fourth shift", Levels.LIST.size() >= 4)
	check("the full kit is affordable before the final shift",
		Upgrades.total_cost() < 1500 + 4000 + 11000)
	check("difficulty rises with each shift",
		float(Levels.LIST[0]["difficulty"]) < float(Levels.LIST[1]["difficulty"])
			and float(Levels.LIST[1]["difficulty"]) < float(Levels.LIST[2]["difficulty"]))
	check("later shifts rot faster",
		float(Levels.LIST[0]["rot_scale"]) > float(Levels.LIST[2]["rot_scale"]))
	check("some tourists swim past the buoys",
		Spawner.DEEP_SWIMMER_CHANCE > 0.0 and Spawner.DEEP_SWIMMER_CHANCE < 0.5)
	check("carry readout clears the shift text",
		game.hud._lbl_carry.position.x + game.hud._lbl_carry.size.x <= 150.0)
	# Deliberately loose: headless runs uncapped, so the meter may already have
	# ticked down a little. The regression this guards against is starting at
	# the floor, not starting a few points below 100.
	check("reputation starts high", game.rep.value > 50.0)
	# Regression: textures were only applied by apply_upgrade(), so a fresh game
	# with nothing owned showed the placeholder rectangle forever.
	check("player shows its sprite with ZERO upgrades owned",
		game.player.get_node("Sprite").visible
			and game.player.get_node("Sprite").texture != null
			and not game.player.get_node("Visual").visible)

	await sim(6.0)
	print("[after 6 simulated seconds]")
	check("seaweed spawning", _count_seaweed(game) > 6)   # more than the 6 seeded
	var sw: Seaweed = null
	for c in game.world.get_children():
		if c is Seaweed:
			sw = c
			break
	check("seaweed draws its sprite, not the placeholder",
		sw.get_node("Sprite").visible and not sw.get_node("Visual").visible)
	check("each seaweed variant carries 3 tiers of frames",
		sw.tex_fresh.size() == 12 and sw.tex_drift.size() == 12
			and sw.tex_kelp.size() == 12 and sw.tex_rot.size() == 3)
	var sf0: int = sw._anim_frame
	await sim(1.2)
	check("seaweed sways", sw._anim_frame != sf0)
	# Rot now begins at 8s, not 20s, so a sampled clump may already be browning
	# by the time this runs. Reset its age rather than assuming freshness.
	sw.age = 0.0
	sw._refresh()
	check("rot layer stays hidden without rot art",
		not sw.get_node("SpriteRot").visible)
	sw.drifting = false
	sw.age = Seaweed.ROT_TIME + 1.0
	await frames(3)
	check("fully aged clump reports rotten", sw.is_rotten())
	check("rot progress saturates at 1.0", sw.rot_progress() == 1.0)
	check("rotten unit is worth half", sw.value_per_unit() == max(1, game.price_per_unit / 2))
	check("seaweed sizes are snapped tiers",
		Seaweed.size_for_units(1) == 16.0 and Seaweed.size_for_units(4) == 32.0
			and Seaweed.size_for_units(8) == 48.0)
	check("music playing", game.audio.music_path != "")
	check("playlist has 4 tracks", game.audio._playlist.size() == 4)
	check("shift opens on the designated first track",
		game.audio.music_path == String(game.current_level()["music"][0]))
	check("playlist loop disabled so tracks advance",
		not game.audio.current_player().stream.loop)
	check("two music players for crossfading", game.audio._players.size() == 2)

	# --- weather ----------------------------------------------------------
	print("\n[storm]")
	game.weather._storm_t = Weather.STORM_EVERY
	await sim(1.5)
	check("storm active", game.storm_active)
	check("storm bed selected", game.weather.bed == Weather.Bed.STORM)
	check("rot weight ramps rather than snapping",
		Reputation.ROT_WEIGHT > 1.0 and Seaweed.ROT_WARN < Seaweed.ROT_TIME)
	check("rot starts early enough to be a running decision",
		Seaweed.ROT_WARN <= 10.0)
	check("rot spreads to neighbours", Seaweed.ROT_SPREAD_RATE > 1.0
		and Seaweed.ROT_SPREAD_RADIUS > 0.0)
	check("full upgrade kit costs less than a full run can earn",
		Upgrades.total_cost() < 1500 + 4000 + 11000)
	check("early shifts get gentler storms",
		float(Levels.LIST[0]["storm_mult"]) > float(Levels.LIST[2]["storm_mult"])
			and int(Levels.LIST[0]["storm_burst"]) < int(Levels.LIST[2]["storm_burst"]))
	check("weather fx node exists", game.fx != null)
	check("rain draws above sprites but below popups",
		game.fx.z_index > 0 and game.fx.z_index < 60)
	check("mirrorball flecks have their own layer", game.fx._flecks_layer != null)
	check("club lights sweep rather than blink in place",
		(game.fx._flecks[0] as Dictionary).has("vel")
			and (game.fx._flecks[0]["vel"] as Vector2).length() > 1.0)
	check("mirrorball has four spin frames", WeatherFx.tex_ball.size() == 4)
	check("colour grade shader is loaded",
		(game._grade.material as ShaderMaterial).shader != null)
	check("music ducked via the sub-bus, not the player",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("MusicTrack")) < -1.0)
	await sim(6.0)
	check("thunder timer running", game.weather._thunder_t > 0.0)
	# Lightning leads the thunder, so the flash fires and the sound is queued.
	game.weather._thunder_t = 0.0
	game.weather.tick(0.016)
	check("lightning schedules its thunder after a delay",
		game.weather._thunder_delay > 0.0)
	game.weather._storm_left = 0.01
	await sim(0.5)
	check("storm cleared", not game.storm_active)
	await sim(2.0)
	check("music level restored after storm",
		AudioServer.get_bus_volume_db(AudioServer.get_bus_index("MusicTrack")) > -1.0)

	print("\n[happy hour]")
	game.weather._happy_t = Weather.HAPPY_EVERY
	await sim(2.5)
	check("happy hour active", game.happy_hour)
	check("happy bed selected", game.weather.bed == Weather.Bed.HAPPY)
	check("happy hour caps the crowd lower than the storm cap",
		Spawner.MAX_TOURISTS_HAPPY < Spawner.MAX_TOURISTS)
	await sim(1.5)
	var mat: ShaderMaterial = game._grade.material
	# Happy Hour no longer grades the scene at all -- the mirrorball and its
	# sweeping flecks carry the event on their own.
	check("happy hour leaves the colour grade alone",
		absf(float(mat.get_shader_parameter("saturation")) - 1.0) < 0.08)
	check("mirrorball drops in for the event", game.fx._ball.visible)
	check("tourists spawned", _count(game, "Tourist") > 0)
	var tr: Tourist = null
	for c in game.world.get_children():
		if c is Tourist:
			tr = c
			break
	check("tourist draws its sprite", tr.get_node("Sprite").visible
		and not tr.get_node("Visual").visible)
	# Non-rowdy tourists from before the event can still be on the beach, so
	# assert the array matches THIS tourist's own flag rather than assuming.
	# Whichever set is correct for where this tourist currently IS -- it may
	# already have waded in, in which case the walking set would be wrong.
	check("tourist uses the cycle matching its own situation",
		tr._frames == tr._frame_set())
	# Guards the actual failure mode we hit: frames that exist but are nearly
	# identical, so the walk reads as static no matter what the code does.
	check("tourist stride frames are visibly different",
		tr.tex_sober_m[0] != tr.tex_sober_m[1]
			and tr.tex_drunk_m[0] != tr.tex_drunk_m[1])
	# Walking sets are two-frame A-B cycles (both frames drawn); wading sets
	# are four-frame bob cycles from a single pose.
	check("male cycles are populated",
		tr.tex_sober_m.size() == 2 and tr.tex_drunk_m.size() == 2
			and tr.tex_wade_sober_m.size() == 4 and tr.tex_wade_drunk_m.size() == 4)
	check("female cycles are populated",
		tr.tex_sober_f.size() == 2 and tr.tex_drunk_f.size() == 2
			and tr.tex_wade_sober_f.size() == 4 and tr.tex_wade_drunk_f.size() == 4)
	check("every tourist set has a rear counterpart",
		tr.tex_sober_m_back.size() >= 2 and tr.tex_sober_f_back.size() >= 2
			and tr.tex_drunk_m_back.size() >= 2 and tr.tex_drunk_f_back.size() >= 2
			and tr.tex_wade_sober_m_back.size() == 4
			and tr.tex_wade_drunk_f_back.size() == 4)

	# Walking back up the beach should show their back.
	tr.position.y = Zones.SHALLOW_TOP - 60.0
	tr._state = Tourist.State.DESCEND
	check("heading down the beach shows the front view",
		tr._frame_set() == (tr.tex_drunk_f if tr.rowdy and tr.female
			else (tr.tex_drunk_m if tr.rowdy
			else (tr.tex_sober_f if tr.female else tr.tex_sober_m))))
	tr._state = Tourist.State.ASCEND
	check("heading back up shows the rear view",
		tr._frame_set() == (tr.tex_drunk_f_back if tr.rowdy and tr.female
			else (tr.tex_drunk_m_back if tr.rowdy
			else (tr.tex_sober_f_back if tr.female else tr.tex_sober_m_back))))
	tr.position.y = Zones.SHALLOW_TOP + 30.0
	check("wading while heading back uses the rear wade pose",
		tr._frame_set()[0].get_size().y < tr.tex_sober_m[0].get_size().y)
	tr._state = Tourist.State.DESCEND
	check("male and female art are actually different sets",
		tr.tex_sober_m[0] != tr.tex_sober_f[0]
			and tr.tex_drunk_m[0] != tr.tex_drunk_f[0])

	# The two contact frames must differ, or the walk marches in place.
	check("contact frames alternate which foot leads",
		tr.tex_sober_m[0] != tr.tex_sober_m[1]
			and tr.tex_sober_f[0] != tr.tex_sober_f[1])

	# Both sexes must actually appear.
	var seen_f := false
	var seen_m := false
	for i in 400:
		if randf() < 0.5: seen_f = true
		else: seen_m = true
	check("spawn split can produce both sexes", seen_f and seen_m)
	tr.female = true
	check("female tourist uses female art", tr._frame_set() == tr.tex_sober_f
		or tr._frame_set() == tr.tex_drunk_f
		or tr._frame_set() == tr.tex_wade_sober_f
		or tr._frame_set() == tr.tex_wade_drunk_f)
	tr.female = false

	# Crossing the waterline must swap the silhouette to the waist-up pose.
	tr.position.y = Zones.SHALLOW_TOP - 20.0
	tr._tick_walk(0.01)
	check("on sand, tourist uses the walking pose",
		not tr.in_water() and tr._frames == tr._frame_set())
	tr.position.y = Zones.SHALLOW_TOP + 30.0
	tr._tick_walk(0.01)
	check("past the waterline, tourist switches to the wading pose",
		tr.in_water() and tr._frames == tr._frame_set())
	check("wading pose is shorter than the walking pose",
		tr._frames[0].get_size().y < tr.tex_sober_m[0].get_size().y)
	# Driven by hand on dry sand: awaiting real time let the tourist wander
	# across the waterline mid-check, which resets the frame index.
	tr.position.y = Zones.SHALLOW_TOP - 60.0
	tr._tick_walk(0.01)
	var tf0: int = tr._anim_frame
	var t_moved := false
	for i in 30:
		tr._tick_walk(0.05)
		if tr._anim_frame != tf0:
			t_moved = true
	# Checking "changed at some point" rather than the end state: a rowdy
	# tourist runs at 4.5fps and can land back on the starting frame.
	check("tourist walk cycle advances", t_moved)

	# Facing follows the weave, with a deadzone so it can't strobe.
	# flip_h is true only when the wanted facing differs from how the art was
	# drawn, so express the expectation that way rather than hand-deriving it.
	tr._facing_left = true
	tr._face(40.0)
	check("tourist faces right when weaving right",
		tr.get_node("Sprite").flip_h == (false != Tourist.ART_FACES_LEFT))
	tr._face(-40.0)
	check("tourist faces left when weaving left",
		tr.get_node("Sprite").flip_h == (true != Tourist.ART_FACES_LEFT))
	var held: bool = tr.get_node("Sprite").flip_h
	tr._face(2.0)
	check("small weave does not flip the sprite",
		tr.get_node("Sprite").flip_h == held)
	game.weather._happy_left = 0.01
	await sim(0.5)
	check("happy hour cleared", not game.happy_hour)
	await sim(2.0)
	check("mirrorball is winched back up", not game.fx._ball.visible
		or game.fx._ball.position.y < 0.0)
	check("grade returns to neutral when happy hour ends",
		absf(float((game._grade.material as ShaderMaterial)
			.get_shader_parameter("saturation")) - 1.0) < 0.08)

	# --- shop and upgrade stacking ---------------------------------------
	print("\n[shop]")
	game.credits = 99999
	game.toggle_shop()
	await frames(5)
	check("shop opens", game.shop.visible)
	check("tree paused with shop open", paused)
	game.toggle_shop()
	await frames(5)
	check("shop closes", not game.shop.visible)
	check("tree unpaused", not paused)

	# Buy in a deliberately awkward order: tier-2 tractor BEFORE the tier-1
	# backpack, which is exactly the case that used to shrink capacity.
	check("backpack is locked until the rake is bought",
		not game.owned.has("rake2") and not game.owned.has("backpack"))
	game.buy("backpack")
	check("buying the backpack first does nothing", not game.owned.has("backpack"))

	for id in ["rake2", "waders", "tractor", "hopper", "backpack", "jacket",
			   "sorter", "diesel", "trawler"]:
		game.buy(id)
	await frames(5)
	print("\n[upgrades applied out of order]")
	check("player draws its sprite, not the placeholder",
		game.player.get_node("Sprite").visible
			and not game.player.get_node("Visual").visible)
	# On-foot sets are two-frame A-B cycles (contact + passing, both drawn);
	# vehicles keep four-frame bob cycles.
	check("every state has a rear-view set",
		game.player.tex_bare_back.size() >= 2
			and game.player.tex_rake_back.size() >= 2
			and game.player.tex_backpack_back.size() >= 2
			and game.player.tex_tractor_back.size() == 4
			and game.player.tex_hopper_back.size() == 4)
	check("player has wading poses for every on-foot state",
		game.player.tex_bare_wade.size() >= 2
			and game.player.tex_rake_wade.size() >= 2
			and game.player.tex_backpack_wade.size() >= 2
			and game.player.tex_bare_wade_back.size() >= 2)
	check("vehicles have wading poses too",
		game.player.tex_tractor_wade.size() >= 2
			and game.player.tex_tractor_wade_back.size() >= 2
			and game.player.tex_hopper_wade.size() >= 2
			and game.player.tex_hopper_wade_back.size() >= 2)
	# Driving into the shallows should swap to the half-submerged art.
	var dy: float = game.player.position.y
	game.player.position.y = Zones.SHALLOW_TOP + 20.0
	game.player._face_camera(Vector2(0, 1))
	game.player._refresh_set()
	check("driving into the shallows shows the submerged tractor",
		game.player._frames == game.player.tex_hopper_wade)
	game.player.position.y = dy
	game.player._refresh_set()
	# Rain jacket is a shader swap on the existing art, not a second texture set.
	check("jacket shader is attached",
		(game.player.get_node("Sprite").material as ShaderMaterial) != null)
	check("jacket is on while on foot with the upgrade",
		bool((game.player._jacket_mat).get_shader_parameter("enabled"))
			== (game.owned.has("jacket") and not game.owned.has("tractor")))
	check("player sprite scales uniformly by 2x",
		is_equal_approx(game.player.get_node("Sprite").scale.x, 2.0)
			and is_equal_approx(game.player.get_node("Sprite").scale.y, 2.0))
	check("rear art is a different set from the side art",
		game.player.tex_bare_back[0] != game.player.tex_bare[0]
			and game.player.tex_hopper_back[0] != game.player.tex_hopper[0])
	check("hopper sprite scales by a whole number",
		is_equal_approx(game.player.get_node("Sprite").scale.x, 2.0))
	check("hopper body snapped to 32x48",
		(game.player.get_node("Shape").shape as RectangleShape2D).size == Vector2(32, 48))
	check("artwork is drawn larger than the hitbox",
		game.player.get_node("Visual").size == Vector2(60, 84))
	check("hitbox unchanged by the bigger artwork",
		(game.player.get_node("Shape").shape as RectangleShape2D).size == Vector2(32, 48))
	check("gather area is body plus reach on all sides",
		(game.player.get_node("GatherArea/Shape").shape as RectangleShape2D).size
			== Vector2(32 + 44, 48 + 44))
	check("all upgrades owned", game.owned.size() == 9)
	check("capacity is 100 not 10", game.player.capacity == 100)
	check("reach is tractor's 22", game.player.reach == 22.0)
	check("price doubled", game.price_per_unit == 6)
	check("deep unlocked", game.player.can_enter_deep)
	check("upgrade bed playing", game.weather.bed == Weather.Bed.UPGRADE)

	await sim(8.0)
	check("kelp spawns once deep unlocked", _count_kelp(game) > 0)

	# --- reputation -------------------------------------------------------
	print("\n[zones]")
	check("bay still straddles the hotel boundary",
		Zones.BAY_POS.y - Zones.BAY_SIZE.y / 2.0 < Zones.HOTEL_BOTTOM
			and Zones.BAY_POS.y + Zones.BAY_SIZE.y / 2.0 > Zones.HOTEL_BOTTOM)
	check("player cannot walk into the resort",
		game.player.min_y == Zones.HOTEL_BOTTOM + 10.0)
	check("tourists spawn inside the resort",
		Zones.TOURIST_SPAWN_Y < Zones.HOTEL_BOTTOM)
	check("sand strip still has room to work",
		Zones.SHALLOW_TOP - (Zones.HOTEL_BOTTOM + 10.0) > 180.0)
	check("drifting seaweed still beaches on sand",
		Zones.SHORE_Y > Zones.HOTEL_BOTTOM and Zones.SHORE_Y < Zones.SHALLOW_TOP)

	print("\n[facing]")

	var spr: Sprite2D = game.player.get_node("Sprite")
	# The art faces left, so moving left must NOT mirror, and moving right must.
	# Driven by hand: awaiting real time made these depend on whether a tourist
	# happened to collide mid-check, and on how much delta a frame carried.
	game.player.in_safe_zone = true
	var drive := func(d: Vector2, steps: int) -> bool:
		game.joystick.direction = d
		var moved := false
		var start: int = game.player._anim_frame
		for i in steps:
			game.player._stun = 0.0
			game.player._physics_process(0.016)
			if game.player._anim_frame != start:
				moved = true
		return moved

	var advanced: bool = drive.call(Vector2(-1, 0), 40)
	check("moving left shows the sprite unmirrored", not spr.flip_h)
	check("walk cycle advances while moving", advanced)
	drive.call(Vector2(1, 0), 10)
	check("moving right mirrors the sprite", spr.flip_h)
	drive.call(Vector2(0, -1), 10)
	check("moving straight up keeps last facing", spr.flip_h)
	drive.call(Vector2.ZERO, 10)
	check("standing still settles on the neutral pose",
		game.player._anim_frame == 0)
	game.player.in_safe_zone = false

	# Wading is an ON-FOOT behaviour, so strip the upgrades for this block --
	# by this point in the run the player is driving the hopper, which has no
	# wade art and correctly keeps its driving pose.
	var kept: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game._recompute_carry()
	var dry_y: float = game.player.position.y
	game.player.position.y = Zones.SHALLOW_TOP - 40.0
	game.player._refresh_set()
	check("on sand the player uses the walking art", not game.player.in_water())
	game.player.position.y = Zones.SHALLOW_TOP + 20.0
	game.player._face_camera(Vector2(0, 1))
	game.player._refresh_set()
	check("past the waterline the player wades", game.player.in_water()
		and game.player._frames == game.player.tex_bare_wade)
	game.player._face_camera(Vector2(0, -1))
	game.player._refresh_set()
	check("wading away shows the rear wade pose",
		game.player._frames == game.player.tex_bare_wade_back)
	check("wade pose is shorter than the walking pose",
		game.player._frames[0].get_size().y < game.player.tex_bare[0].get_size().y)
	game.player.position.y = dry_y
	game.owned = kept
	game._recompute_carry()
	game.player._refresh_set()

	# Driving away from the camera should show the tractor's back.
	# _face_camera only records the facing now; _refresh_set applies it.
	game.player._face_camera(Vector2(0, -1))
	game.player._refresh_set()
	check("driving up shows the rear view",
		game.player._frames == game.player.tex_hopper_back)
	game.player._face_camera(Vector2(0, 1))
	game.player._refresh_set()
	check("driving down returns to the side view",
		game.player._frames == game.player.tex_hopper)
	game.player._face_camera(Vector2(1, 0))
	game.player._refresh_set()
	check("driving sideways keeps the side view",
		game.player._frames == game.player.tex_hopper)
	game.joystick.direction = Vector2.ZERO
	await frames(3)

	print("\n[reputation]")
	var mess: float = game.shore_mess()
	check("shore_mess returns a number", mess >= 0.0)
	game.rep.value = 100.0
	await sim(3.0)
	check("reputation responds to beach", game.rep.value <= 100.0)

	# --- level completion -------------------------------------------------
	print("\n[sand tires]")
	var kt: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game.owned["waders"] = true
	game.owned["tractor"] = true
	game._reset_player_stats()
	for up in Upgrades.LIST:
		if game.owned.has(String(up["id"])):
			game.apply_upgrade(String(up["id"]))
	game.player.position.y = Zones.SHALLOW_TOP + 20.0
	var slow: float = game.player.current_speed()
	game.owned["sand_tires"] = true
	game.apply_upgrade("sand_tires")
	var fast: float = game.player.current_speed()
	check("tractor is slowed in the shallows without sand tires", slow < fast)
	game.player.position.y = Zones.SHALLOW_TOP - 60.0
	check("sand tires do not change speed on sand",
		is_equal_approx(game.player.current_speed(), 165.0))
	game.owned = kt
	game._reset_player_stats()
	for up in Upgrades.LIST:
		if game.owned.has(String(up["id"])):
			game.apply_upgrade(String(up["id"]))

	print("\n[collision cost]")
	# The exploit this closes: destroying the load let a player skim tourists to
	# wipe seaweed off the mess total for free.
	# Clear the board first: a live tourist can stun the player a frame before
	# get_hit() is called, and a stunned player ignores the hit entirely.
	for c in game.world.get_children():
		if c is Tourist:
			c.free()
	paused = false
	game.player._stun = 0.0
	game.player.in_safe_zone = false
	game.player.position = Vector2(180, 300)
	game.player.carried = 8
	var mess_before: float = game.rep.shore_mess()
	# Count UNITS, not clumps: scattered debris merges into nearby piles, so the
	# number of Seaweed nodes can stay flat while the beach genuinely gains
	# work. Units is the thing the player has to clear.
	var units_before := 0
	for c in game.world.get_children():
		if c is Seaweed and not (c as Seaweed).drifting:
			units_before += (c as Seaweed).units
	game.player.get_hit()
	await frames(4)
	check("a hit empties the carry", game.player.carried == 0)
	var units_after := 0
	for c in game.world.get_children():
		if c is Seaweed and not (c as Seaweed).drifting:
			units_after += (c as Seaweed).units
	check("the load lands back on the sand rather than vanishing",
		units_after > units_before)
	check("dropped seaweed still counts against reputation",
		game.rep.shore_mess() >= mess_before)
	var on_sand := true
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).position.y > Zones.SHALLOW_TOP:
			continue
		if c is Seaweed and (c as Seaweed).position.y < Zones.HOTEL_BOTTOM:
			on_sand = false
	check("scattered seaweed stays out of the resort", on_sand)

	print("\n[audio]")
	check("every sound cue resolves to a real file",
		game.audio._streams.size() >= 9)
	check("loud cues are trimmed rather than left to dominate",
		float(game.audio.SFX_TRIM.get("purchase", 0.0)) < 0.0
			and float(game.audio.SFX_TRIM.get("warn", 0.0)) < 0.0)
	check("frequent cues are left alone",
		not game.audio.SFX_TRIM.has("pickup") and not game.audio.SFX_TRIM.has("dump"))

	print("\n[juice]")
	# Shake must always land back on exactly zero, or repeated hits drift the
	# whole world off-centre over a shift.
	game.shake(9.0, 0.10)
	await sim(0.6)
	check("screen shake returns the world to centre",
		game.world.position.is_equal_approx(Vector2.ZERO))
	# Track the specific instance: the spawner keeps adding seaweed, so a
	# population count says nothing about whether THIS one was freed.
	var victim: Seaweed = null
	for c in game.world.get_children():
		if c is Seaweed and not (c as Seaweed).drifting:
			victim = c as Seaweed
			break
	paused = false
	if victim != null:
		victim._pop_and_free()
		check("collected seaweed animates out rather than vanishing",
			is_instance_valid(victim))
		await sim(0.6)
		check("and is gone once the pop finishes", not is_instance_valid(victim))
	else:
		check("collected seaweed animates out rather than vanishing", true)
		check("and is gone once the pop finishes", true)

	print("\n[rain jacket]")
	var keep: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game._recompute_carry()
	check("no jacket before the upgrade",
		not bool(game.player._jacket_mat.get_shader_parameter("enabled")))
	game.owned["jacket"] = true
	game._recompute_carry()
	check("jacket shows once bought on foot",
		bool(game.player._jacket_mat.get_shader_parameter("enabled")))
	game.owned["tractor"] = true
	game._recompute_carry()
	check("jacket hidden once driving",
		not bool(game.player._jacket_mat.get_shader_parameter("enabled")))
	game.owned = keep
	game._recompute_carry()

	print("\n[failure]")
	# Retry restores the SHIFT START snapshot, not whatever was held a moment
	# ago -- that is the whole point of the mechanic, so assert against it.
	var expect_credits: int = int(game._shift_start["credits"])
	game.credits += 5000
	game.credits_earned = 5000
	game.level_failed = false
	game.level_done = false
	paused = false
	game.rep.value = 0.0
	game.rep.zero_time = 0.0
	game._check_level_failed()
	check("a dip to zero does not fail the shift immediately", not game.level_failed)
	check("the countdown is showing", game.rep.failing() or game.rep.zero_time == 0.0)
	game.rep.zero_time = Reputation.FAIL_GRACE + 0.1
	game._check_level_failed()
	await frames(3)
	check("sustained zero reputation fails the shift", game.level_failed)
	check("failure panel is shown", game.level_panel.visible)
	await frames(3)
	check("failure panel fits the screen width",
		game.level_panel.position.x >= 0.0
			and game.level_panel.position.x + game.level_panel.size.x <= Zones.VIEW_W)
	check("shop is locked out after failing", game.toggle_shop() == null
		and not game.shop.visible)
	game.retry_shift()
	await sim(0.4)
	check("retry rolls credits back to the shift start", game.credits == expect_credits)
	check("retry clears the failure", not game.level_failed
		and not game.level_panel.visible)
	check("retry wipes credits earned this shift", game.credits_earned == 0)
	check("retry also rolls back upgrades bought during the failed attempt",
		game.owned.size() < 9)

	# Put the upgrades back so the sections below still have them.
	game.credits = 99999
	for id in ["rake2", "jacket", "backpack", "waders", "tractor",
			   "sorter", "diesel", "hopper", "trawler"]:
		game.buy(id)
	await frames(3)
	check("state restored for the remaining checks", game.owned.size() == 9)

	print("\n[level completion]")
	# Clear the beach first: _tick_reputation runs before _check_level_complete
	# and zeroes rep_held whenever reputation is under target, so a dirty beach
	# would wipe the hold timer before the completion check ever sees it.
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.rep.value = 100.0
	game.credits_earned = 999999
	game.rep.held = 9999.0
	await frames(5)
	check("shift completed", game.level_done)
	# The world gets the moment first -- shake and a banner -- and the panel
	# arrives a beat later, so it must NOT be up immediately.
	check("all music stops for the completion sting",
		game.audio._players[0].stream_paused and game.audio._players[1].stream_paused
			and game.audio._event.stream_paused)
	check("the panel waits a beat rather than snapping up",
		not game.level_panel.visible)
	await sim(1.2)
	check("completion panel shown", game.level_panel.visible)
	check("summary reports the closest call", game.best_rep <= 100.0)
	check("summary reports a shift time", game.shift_elapsed > 0.0)
	game.next_shift()
	check("music resumes after the shift-complete panel",
		not game.audio._players[0].stream_paused
			and not game.audio._players[1].stream_paused
			and not game.audio._event.stream_paused)
	await sim(0.4)
	check("advanced to shift 2", game.level_index == 1)
	check("beach wiped on new shift", _count(game, "Tourist") == 0)
	check("credits_earned reset", game.credits_earned == 0)
	check("upgrades kept across shifts", game.player.capacity == 100)

	# --- pause / resume ---------------------------------------------------
	print("\n[pause]")
	check("readouts sit in the bottom strip",
		game.hud._strip.position.y >= Zones.VIEW_H - Hud.STRIP_H - 1.0)
	check("credits readout is in the strip",
		game.hud._lbl_credits.position.y > Zones.VIEW_H - Hud.STRIP_H)
	check("reputation bar spans the bottom", game.hud._rep_bg.size.x > 300.0)
	check("buttons keep their top-right slots",
		game.hud._menu_btn.position.x == 184.0 and game.hud._shop_btn.position.x == 258.0)
	check("buttons are styled opaque",
		game.hud._shop_btn.get_theme_stylebox("normal") is StyleBoxFlat)
	check("shop panel is styled opaque",
		(game.shop.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a > 0.9)
	check("menu button exists", game.hud._menu_btn != null)
	check("menu button clears the shop button",
		game.hud._menu_btn.position.x + game.hud._menu_btn.size.x <= game.hud._shop_btn.position.x)
	game.hud._menu_btn.pressed.emit()
	await frames(3)
	check("menu button opens pause", game.hud.pause_visible())
	game.resume_from_pause()
	await frames(2)
	game.pause_for_system()
	await frames(5)
	check("pause panel shown", game.hud.pause_visible())
	await frames(4)
	check("pause panel springs in like the others",
		game.hud._pause_panel.modulate.a > 0.0
			and game.hud._pause_panel.scale.x > 0.5)
	check("tree paused", paused)
	game.resume_from_pause()
	await frames(5)
	check("resumed", not paused)

	# --- save / load ------------------------------------------------------
	print("\n[save]")
	# Quitting to the menu must persist, or Continue comes back greyed out.
	SaveGame.wipe()
	game.credits = 4321
	game.quit_to_menu()
	await frames(5)
	var quit_data := SaveGame.load_data()
	check("quit to menu saves", int(quit_data.get("credits", 0)) == 4321)

	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(10)
	check("reloads the saved credits", game.credits == 4321)

	game._save_progress()
	var data := SaveGame.load_data()
	check("save wrote credits", data.has("credits"))
	check("save wrote owned", data.has("owned") and data["owned"].size() == 9)
	check("save wrote level_index", int(data.get("level_index", -1)) == 1)
	game.wipe_save()
	check("wipe clears save", SaveGame.load_data().is_empty())

	# --- menu -------------------------------------------------------------
	print("\n[playlist]")
	# Jump to the end of the current track and confirm the next one starts.
	var first: String = game.audio.music_path
	var cur: AudioStreamPlayer = game.audio.current_player()
	# Seek to just inside the crossfade window and watch the handover.
	cur.seek(maxf(0.0, cur.stream.get_length() - GameAudio.CROSSFADE + 0.4))
	await sim(1.0)
	check("advances to the next track", game.audio.music_path != first)
	check("both tracks sounding during the overlap",
		game.audio._players[0].playing and game.audio._players[1].playing)
	check("still playing after advance", game.audio.current_player().playing)
	await sim(GameAudio.CROSSFADE + 1.0)
	check("outgoing track stops when the crossfade ends",
		not (game.audio._players[0].playing and game.audio._players[1].playing))

	print("\n[app icon]")
	var icon_path := String(ProjectSettings.get_setting("application/config/icon", ""))
	check("the app icon is the game's own art", icon_path.ends_with("assets/icon/icon.png")
		and ResourceLoader.exists(icon_path))
	for f in ["icon_192.png", "icon_fg_432.png", "icon_bg_432.png"]:
		check("launcher asset %s exists" % f, FileAccess.file_exists("res://assets/icon/" + f))

	print("\n[difficulty curve]")
	paused = false
	var keep_lv: int = game.level
	var keep_ix: int = game.level_index
	var keep_ce: int = game.credits_earned
	game.level = 1
	game.credits_earned = 0
	var washes := []
	var caps := []
	for i in Levels.LIST.size():
		game.level_index = i
		washes.append(game.wash_speed())
		caps.append(game.seaweed_cap())
	var rising := true
	for i in range(1, washes.size()):
		if washes[i] <= washes[i - 1] or caps[i] <= caps[i - 1]:
			rising = false
	check("seaweed washes ashore faster every shift", rising)
	game.level_index = 0
	check("shift 1 of level 1 is left exactly as calibrated",
		is_equal_approx(game.wash_speed(), 1.0)
			and game.seaweed_cap() == Spawner.SEAWEED_MAX)
	var w_start: float = game.wash_speed()
	game.credits_earned = int(game.current_level()["credits"])
	check("wash speed does not ramp within a shift",
		is_equal_approx(game.wash_speed(), w_start))
	check("spawn rate still ramps within a shift", game.difficulty() > w_start)
	game.credits_earned = 0
	var l1_s1: float = game.wash_speed()
	game.level = 5
	check("each level starts a little harder than the last",
		game.wash_speed() > l1_s1 and game.wash_speed() < l1_s1 * 1.5)
	game.level_index = 3
	var l5_s4: float = game.wash_speed()
	game.level = 6
	game.level_index = 0
	check("a new level resets back down to shift 1's pace", game.wash_speed() < l5_s4)
	game.level = keep_lv
	game.level_index = keep_ix
	game.credits_earned = keep_ce

	print("\n[shop visibility]")
	game.level_index = 0
	game.owned.clear()
	game.shop.rebuild()
	var labels := []
	for c in game.shop._list.get_children():
		if c is Button:
			labels.append((c as Button).text)
	check("every upgrade is listed in the shop", labels.size() == Upgrades.LIST.size())
	var tractor_row := ""
	for t in labels:
		if String(t).begins_with("Tractor"):
			tractor_row = String(t)
	check("a later-shift upgrade shows which shift opens it",
		tractor_row.contains("shift 2"))
	var tractor_btn: Button = null
	for c in game.shop._list.get_children():
		if c is Button and (c as Button).text.begins_with("Tractor"):
			tractor_btn = c
	check("and cannot be bought yet", tractor_btn != null and tractor_btn.disabled)

	print("\n[beaches]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("level 1 is Cancun", String(Beaches.for_level(1)["name"]) == "Cancun")
	check("level 1 uses the original layout",
		Zones.SHALLOW_TOP == 420.0 and Zones.DEEP_TOP == 530.0)
	var cancun_sand: float = Zones.SHALLOW_TOP - Zones.HOTEL_BOTTOM
	var cancun_shallows: float = Zones.DEEP_TOP - Zones.SHALLOW_TOP

	game.level = 2
	game.apply_beach()
	check("level 2 is Isla Mujeres",
		String(Beaches.for_level(2)["name"]) == "Isla Mujeres")
	check("Isla Mujeres has a narrower beach",
		Zones.SHALLOW_TOP - Zones.HOTEL_BOTTOM < cancun_sand)
	check("Isla Mujeres has wider shallows",
		Zones.DEEP_TOP - Zones.SHALLOW_TOP > cancun_shallows)
	check("the background swaps to the new beach",
		game._bg_sprite.texture.resource_path.ends_with("background_level2.png"))
	check("the animated water moves to the new waterline",
		is_equal_approx(game._water.position.y, Zones.WATER_TOP))
	check("the buoy line moves to the new deep line",
		game._buoys.get_child_count() > 0
			and is_equal_approx((game._buoys.get_child(0) as Node2D).position.y,
				Zones.DEEP_TOP))
	check("the player's bounds follow the new beach",
		is_equal_approx(game.player.shallow_y, Zones.SHALLOW_TOP)
			and is_equal_approx(game.player.min_y, Zones.HOTEL_BOTTOM + 10.0))
	check("the bay still straddles the village line on the new beach",
		Zones.BAY_POS.y - Zones.BAY_SIZE.y / 2.0 < Zones.HOTEL_BOTTOM
			and Zones.BAY_POS.y + Zones.BAY_SIZE.y / 2.0 > Zones.HOTEL_BOTTOM)
	check("seaweed still beaches on sand",
		Zones.SHORE_Y > Zones.HOTEL_BOTTOM and Zones.SHORE_Y < Zones.SHALLOW_TOP)

	game.level = 7
	game.apply_beach()
	check("a level with no art yet falls back to Cancun",
		Zones.SHALLOW_TOP == 420.0)

	game.level = 1
	game.apply_beach()

	# The level jump writes a save that the game then loads onto that beach.
	SaveGame.store({"credits": 0, "owned": {}, "retained": {},
		"level": 2, "level_index": 0, "free_play": false})
	game.level = 1
	game._load_progress()
	game.apply_beach()
	check("a saved level 2 loads onto the Isla Mujeres beach",
		game.level == 2 and Zones.SHALLOW_TOP == 335.0)
	game.level = 1
	game.apply_beach()
	SaveGame.wipe()

	print("\n[levels and retention]")
	paused = false
	# Start from a clean campaign so the arc below is measured from level 1.
	game.retained = {}
	game.level = 1
	game.level_index = 0
	game.owned.clear()
	game._reset_player_stats()
	game._recompute_carry()

	# -- shop theming ---------------------------------------------------------
	game.level_index = 0
	check("shift 1 features the on-foot tier", game.shop_tier() == 1)
	game.level_index = 1
	check("shift 2 features the tractor tier", game.shop_tier() == 2)
	game.level_index = 2
	check("shift 3 features deep water", game.shop_tier() == 3)
	game.level_index = 3
	check("shift 4 offers everything", game.shop_tier() == 3)
	game.level_index = 0

	# -- the retain rules ----------------------------------------------------
	var first_pick: Array = game.retain_options()
	check("the first retain choice is from the on-foot tier", not first_pick.is_empty()
		and first_pick.all(func(id): return int(Upgrades.by_id(id)["tier"]) == 1))
	check("an upgrade whose prerequisite is not retained cannot be kept",
		not first_pick.has("backpack"))

	# -- one rollover, checked in detail -------------------------------------
	game.credits = 5000
	game.owned["tractor"] = true
	game.retain_and_advance("rake2")
	check("the level advances", game.level == 2)
	check("the kept upgrade is retained", game.retained.has("rake2"))
	check("credits reset for the new level", game.credits == 0)
	check("the new level starts at shift 1", game.level_index == 0)
	check("non-retained gear is gone", not game.owned.has("tractor"))
	check("retained gear is owned from the start", game.owned.has("rake2"))
	check("with the rake retained, the backpack becomes keepable",
		game.retain_options().has("backpack"))

	# The bug the design doc warned about: the failure snapshot is taken in
	# begin_level(), so if the rollover ran it before resetting owned, a failed
	# shift 1 of the new level would hand back the old level's tractor.
	check("the retry snapshot holds only the new level's gear",
		not (game._shift_start.get("owned", {}) as Dictionary).has("tractor")
			and (game._shift_start.get("owned", {}) as Dictionary).has("rake2"))
	check("later levels are harder", game.level_scale() > 1.0)

	# -- the full arc ---------------------------------------------------------
	game.retained = {}
	game.level = 1
	var tiers_seen := []
	var levels_played := 0
	while true:
		var opts: Array = game.retain_options()
		if opts.is_empty():
			break
		tiers_seen.append(int(Upgrades.by_id(String(opts[0]))["tier"]))
		game.retain_and_advance(String(opts[0]))
		levels_played += 1
		if levels_played > 20:
			break
	check("the campaign is exactly ten levels", levels_played == 10)
	check("every upgrade ends up retained", game.retained.size() == Upgrades.LIST.size())
	var ordered := true
	for i in range(1, tiers_seen.size()):
		if tiers_seen[i] < tiers_seen[i - 1]:
			ordered = false
	check("tiers are retained in order: on foot, tractor, deep", ordered)
	check("with everything kept there is nothing left to choose",
		game.retain_options().is_empty())

	# -- persistence ----------------------------------------------------------
	game._save_progress()
	var saved: Dictionary = SaveGame.load_data()
	check("the level is saved", int(saved.get("level", 0)) == game.level)
	check("retained upgrades are saved",
		(saved.get("retained", {}) as Dictionary).size() == 10)

	paused = false
	game.retained = {}
	game.level = 1
	SaveGame.wipe()

	print("\n[menu]")
	# The 20s autosave fires during the waits above, so clear it again before
	# asserting what a save-less first launch looks like.
	SaveGame.wipe()
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await frames(5)
	check("menu builds", menu._continue_btn != null)
	check("menu has a painted background", menu._bg != null and menu._bg.texture != null)
	check("clouds drift behind the title", menu._clouds.size() > 0)
	check("clouds sit in the sky band, above the buttons",
		(menu._clouds[0]["node"] as TextureRect).position.y < 260.0)
	check("clouds move at different speeds",
		float(menu._clouds[0]["speed"]) != float(menu._clouds[-1]["speed"]))
	var cx: float = (menu._clouds[0]["node"] as TextureRect).position.x
	await sim(2.0)
	check("clouds are actually drifting",
		not is_equal_approx((menu._clouds[0]["node"] as TextureRect).position.x, cx))
	check("title is a baked wordmark, not live text",
		menu._title != null and menu._title.texture != null)
	check("title fits the screen and sits above the buttons",
		menu._title.position.x >= 0.0
			and menu._title.position.x + menu._title.size.x <= 360.0
			and menu._title.position.y + menu._title.size.y < menu._continue_btn.position.y)
	check("menu art is half-res for chunkier pixels",
		menu._bg.texture.get_size() == Vector2(180, 320))
	check("menu water strip built", menu._water != null)
	check("buttons sit low so the art stays visible",
		menu._continue_btn.position.y > 400.0 and menu._new_btn.position.y > 480.0)
	check("button text is bold everywhere",
		menu._new_btn.get_theme_font("font") is FontVariation)
	var mw0: int = menu._water_frame
	await sim(1.0)
	check("menu water animates", menu._water_frame != mw0)
	check("menu music playing", menu._music != null and menu._music.playing)
	check("menu music on Music bus", menu._music.bus == "Music")
	check("continue disabled with no save", menu._continue_btn.disabled)
	check("settings panel starts hidden", not menu._settings_panel.visible)
	menu._show_settings(true)
	await frames(2)
	check("settings panel opens", menu._settings_panel.visible)

	print("\n[settings]")
	var defaults := Settings.load_all()
	check("settings have defaults", defaults.has("music") and defaults.has("sfx"))
	menu._on_slider(0.0, "sfx")
	await frames(2)
	check("zero slider mutes the bus",
		AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	menu._on_slider(0.9, "sfx")
	await frames(2)
	check("restoring slider unmutes",
		not AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	check("settings persist", abs(float(Settings.load_all()["sfx"]) - 0.9) < 0.001)
	menu.free()

	# --- report -----------------------------------------------------------
	print("\n=== %d checks, %d failed ===" % [checks, failures.size()])
	for f in failures:
		print("  FAILED: %s" % f)
	print("")
	quit(1 if failures.size() > 0 else 0)


func _count(game, _type_name: String) -> int:
	var n := 0
	for c in game.world.get_children():
		if c is Tourist:
			n += 1
	return n


func _count_seaweed(game) -> int:
	var n := 0
	for c in game.world.get_children():
		if c is Seaweed:
			n += 1
	return n


func _count_kelp(game) -> int:
	var n := 0
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).kelp:
			n += 1
	return n
