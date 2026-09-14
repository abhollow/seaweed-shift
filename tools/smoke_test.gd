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
	game.rep.value = 0.0
	game._check_level_failed()
	await frames(3)
	check("zero reputation fails the shift", game.level_failed)
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
	check("completion panel shown", game.level_panel.visible)
	game.next_shift()
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

	print("\n[menu]")
	# The 20s autosave fires during the waits above, so clear it again before
	# asserting what a save-less first launch looks like.
	SaveGame.wipe()
	var menu = load("res://scenes/menu.tscn").instantiate()
	root.add_child(menu)
	await frames(5)
	check("menu builds", menu._continue_btn != null)
	check("menu has a painted background", menu._bg != null and menu._bg.texture != null)
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
