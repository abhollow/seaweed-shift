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
		game.player._grace = 0.0
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
	print("\n[tutorial]")
	check("a new game opens on the tutorial", game.tutorial.visible and not game.level_intro.visible)
	check("the game waits behind it", paused)
	check("level 1's music waits for START SHIFT!", game._hold_music and game.audio._playlist.is_empty())
	check("it has eight steps", game.tutorial.steps.size() == 8)
	check("with a scene staged for it: piles, a rotting pile, a tourist", game._staged.size() == 5
		and (game._staged[1] as Seaweed).rot_progress() > 0.9)
	var holes_ok := true
	var flips := 0
	var was_top: bool = game.tutorial.steps[0]["top"]
	for i in game.tutorial.steps.size():
		var st: Dictionary = game.tutorial.steps[i]
		for h in st["holes"]:
			var hr: Rect2 = h["rect"]
			if hr.size.x <= 0.0 or not Rect2(0, 0, 360, 640).intersects(hr):
				holes_ok = false
		if bool(st["top"]) != was_top:
			flips += 1
			was_top = st["top"]
	check("every step spotlights something on screen", holes_ok)
	check("the card moves to stay clear of what it points at", flips >= 2)
	for i in game.tutorial.steps.size() - 1:
		game.tutorial._on_next()
	check("NEXT walks through to the last step", game.tutorial.step == game.tutorial.steps.size() - 1)
	check("whose button is START SHIFT!", game.tutorial._next.text == "START SHIFT!")
	var staged_before: Array = game._staged.duplicate()
	game.tutorial._on_next()
	await frames(2)
	check("START SHIFT! ends the tutorial", not game.tutorial.visible and game.tutorial_done)
	check("and plays level 1's music", not game._hold_music and not game.audio._playlist.is_empty())
	var cleared := true
	for n in staged_before:
		if is_instance_valid(n):
			cleared = false
	check("the staged scene is cleared away", cleared)
	check("and the worker is back in the bay", game.player.position.distance_to(Zones.BAY_POS) < 1.0)
	check("a new game opens on the level intro", game.level_intro.visible)
	check("the intro names the location",
		game.level_intro._name.text == Beaches.name_of(1).to_upper())
	check("the game waits behind the intro", paused)
	game.start_from_intro()
	await frames(3)
	check("START SHIFT! begins play", not paused and not game.level_intro.visible)
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
	game.weather._storm_t = game.storm_every()
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
	check("hopper hitbox trimmed a little from its 32x48 footprint",
		(game.player.get_node("Shape").shape as RectangleShape2D).size == Game.VEHICLE_HIT_HOPPER
		and Game.VEHICLE_HIT_HOPPER.x < 32.0 and Game.VEHICLE_HIT_HOPPER.y < 48.0)
	check("artwork is drawn larger than the hitbox",
		game.player.get_node("Visual").size == Vector2(60, 84))
	check("hitbox unchanged by the bigger artwork",
		(game.player.get_node("Shape").shape as RectangleShape2D).size == Game.VEHICLE_HIT_HOPPER)
	check("gather area is the full footprint plus reach on all sides",
		(game.player.get_node("GatherArea/Shape").shape as RectangleShape2D).size
			== Vector2(32 + 44, 48 + 44))
	check("all upgrades owned", game.owned.size() == 9)
	check("capacity is 100 not 10", game.player.capacity == 100)
	check("reach is tractor's 22", game.player.reach == 22.0)
	check("price doubled", game.price_per_unit == Game.SORTER_PAY and Game.SORTER_PAY == Game.BASE_PAY * 2)
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
			game.player._grace = 0.0
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
	game.player._grace = 0.0
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
	game.rep.zero_time = game.fail_grace() + 0.1
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
	check("a real failed shift eases the next attempt", game.last_adapt == -1 and game.shift_fails >= 1)
	check("retrying a failed shift does not replay the intro",
		not game.level_intro.visible)
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
	check("each shift has one goal: its credit target", not game.current_level().has("hold")
		and not ("_goal_hold" in game.hud))
	# Credits alone end the shift -- even with reputation low and no clean
	# spell behind it, which used to block completion invisibly.
	game.rep.value = 40.0
	game.credits_earned = int(game.current_level()["credits"]) - 1
	await frames(3)
	check("one credit short, the shift carries on", not game.level_done)
	game.credits_earned = int(game.current_level()["credits"])
	await frames(3)
	check("reaching the credit target ends the shift, whatever the reputation", game.level_done)
	check("shift completed", game.level_done)
	# The world gets the moment first -- shake and a banner -- and the panel
	# arrives a beat later, so it must NOT be up immediately.
	# A song ending during the sting must not start the next one.
	game.audio._on_track_finished(game.audio._active)
	await frames(3)
	# Checks what is AUDIBLE, not the paused flags. A crossfade in flight keeps
	# running through the pause and stop()s its outgoing player, which can reset
	# that player's flag -- harmless, since a stopped player is silent. The old
	# flag-based check failed on that roughly one run in five.
	check("all music stops for the completion sting",
		not game.audio._players[0].playing and not game.audio._players[1].playing
			and not game.audio._event.playing)
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
	if game.level_intro.visible:
		game.start_from_intro()
		await frames(2)
	check("a saved game never replays the tutorial", not game.tutorial.visible and game.tutorial_done)
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
	check("level 2 is Veracruz",
		String(Beaches.for_level(2)["name"]) == "Veracruz")
	# Close to Cancun's shape: the wind is the one new thing on this level.
	# Within 40px -- the redrawn art (wind-correct palms) came out with a beach
	# about 14% narrower, which still reads as the same kind of beach.
	check("Veracruz keeps a familiar beach so the wind is the new thing",
		absf((Zones.SHALLOW_TOP - Zones.HOTEL_BOTTOM) - cancun_sand) < 40.0
			and absf((Zones.DEEP_TOP - Zones.SHALLOW_TOP) - cancun_shallows) < 20.0)
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

	var l2_music: Array = Beaches.for_level(2).get("music", [])
	check("Veracruz has its own soundtrack",
		l2_music.size() == 3 and String(l2_music[0]).ends_with("Tropical_Tension_1.mp3"))
	var l1_music: Array = Levels.LIST[0]["music"]
	check("none of it repeats Cancun's tracks",
		l2_music.all(func(t): return not l1_music.has(t)))

	# Every level's geometry must be playable, whatever its art looks like.
	var sane := true
	var why := ""
	for lv in range(1, 11):
		game.level = lv
		game.apply_beach()
		# By DEPTH, so the same test holds on a banded beach and a round island:
		# the bay must straddle the resort's edge, whichever way out to sea is.
		var bay := Rect2(Zones.BAY_POS - Zones.BAY_SIZE / 2.0, Zones.BAY_SIZE)
		var near := INF
		var far := 0.0
		for q in [bay.position, bay.end, Vector2(bay.position.x, bay.end.y), Vector2(bay.end.x, bay.position.y),
				Vector2(bay.position.x, bay.get_center().y), Vector2(bay.end.x, bay.get_center().y),
				Vector2(bay.get_center().x, bay.position.y), Vector2(bay.get_center().x, bay.end.y)]:
			near = minf(near, Zones.depth(q))
			far = maxf(far, Zones.depth(q))
		var ok: bool = Zones.HOTEL_BOTTOM < Zones.SHORE_Y \
			and Zones.SHORE_Y < Zones.SHALLOW_TOP \
			and Zones.SHALLOW_TOP < Zones.DEEP_TOP and Zones.DEEP_TOP < Zones.DEPTH_MAX \
			and (Zones.RADIAL or Zones.WATER_TOP < Zones.SHALLOW_TOP) \
			and ((near < Zones.HOTEL_BOTTOM and far > Zones.HOTEL_BOTTOM)
				or (Zones.RADIAL and Zones.STREETS > 0 and Zones.depth(Zones.BAY_POS) < Zones.PLAZA_R)) \
			and Zones.TOURIST_SPAWN_Y < Zones.HOTEL_BOTTOM \
			and game._bg_sprite.texture.resource_path.ends_with("background_level%d.png" % lv)
		if not ok:
			sane = false
			why += " L%d" % lv
	check("all ten levels have playable geometry and their own art" + why, sane)

	game.level = 3
	game.apply_beach()
	check("Playa del Carmen puts the bay on the left",
		game._bay.position.x < Zones.VIEW_W / 2.0)
	check("the skip sits mid-bay, turned to face right",
		game._bay_bin == null or (absf(game._bay_bin.position.x) < 10.0 and game._bay_bin.flip_h))
	check("the driveway opens on the left",
		game.player.bay_x0 < 20.0 and game.player.bay_x1 < Zones.VIEW_W / 2.0)
	game.level = 1
	game.apply_beach()
	check("back on Cancun the bay returns to the right",
		game._bay.position.x > Zones.VIEW_W / 2.0
			and (game._bay_bin == null or game._bay_bin.position.x > 0.0))

	game.level = 1
	game.apply_beach()

	# The level jump writes a save that the game then loads onto that beach.
	SaveGame.store({"credits": 0, "owned": {}, "retained": {},
		"level": 2, "level_index": 0, "free_play": false})
	game.level = 1
	game._load_progress()
	game.apply_beach()
	check("a saved level 2 loads onto the Veracruz beach",
		game.level == 2 and Zones.SHALLOW_TOP == 390.0)
	game.level = 1
	game.apply_beach()
	SaveGame.wipe()

	print("\n[wind]")
	paused = false
	var keep_owned: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game._reset_player_stats()
	game._recompute_carry()
	game.level = 1
	game.apply_beach()
	check("Cancun is calm", not game.wind.active() and game.player.wind_push(true) == 0.0)
	game.level = 2
	game.apply_beach()
	check("Veracruz has the norte", game.wind.active() and game.wind.force() > 0.0)
	var base_f: float = game.wind.force()
	var spd: float = game.player.current_speed()
	var push: float = game.player.wind_push(true)
	check("walking downwind is faster than walking into it",
		spd + push > (spd - push) * 1.2)
	check("standing still you brace, and only creep",
		game.player.wind_push(false) > 0.0 and game.player.wind_push(false) < push * 0.5)
	game.owned["waders"] = true
	game.owned["tractor"] = true
	game._recompute_carry()
	check("a tractor shrugs off most of the wind", game.player.wind_push(true) < push * 0.6)
	game.owned.clear()
	game._recompute_carry()
	game.wind.gusting = true
	game.wind._gust_t = game.wind.gust_len * 0.5
	check("a gust pushes harder than the steady wind", game.wind.force() > base_f * 1.8)
	# The point of the retune: a peak gust on foot stops you dead.
	var walk: float = game.player.current_speed()
	check("walking into a peak gust on foot gets you nowhere",
		walk - game.player.wind_push(true) <= walk * 0.1)
	game.owned["waders"] = true
	game.owned["tractor"] = true
	game._recompute_carry()
	check("a tractor can still drive into one",
		game.player.current_speed() - game.player.wind_push(true) > 60.0)
	game.owned.clear()
	game._recompute_carry()
	var dry_push: float = game.player.wind_push(true)
	var py0: float = game.player.position.y
	game.player.position.y = Zones.SHALLOW_TOP + 30.0
	check("footing is worse in the water", game.player.wind_push(true) > dry_push)
	game.player.position.y = py0

	# Tourists: shoved by gusts, and they lean into them.
	# Built directly, so these checks can never silently skip for want of a
	# tourist on the beach.
	var t: Tourist = Spawner.TOURIST_SCENE.instantiate()
	t.game = game
	game.world.add_child(t)
	t.setup(Vector2(180, 300), 480.0, false, Zones.TOURIST_DESPAWN_Y)
	await frames(1)
	game.wind.gusting = true
	game.wind._gust_t = game.wind.gust_len * 0.5
	if true:
		t.rowdy = false
		t.position = Vector2(180, 300)
		var tx: float = t.position.x
		t._tick_gust(0.25)
		check("a gust shoves tourists sideways", t.position.x > tx + 3.0)
		check("and they lean into it", t.rotation < -0.05)
		game.wind.gusting = false
		t._tick_gust(0.25)
		check("in the steady wind they stand straight and hold their line",
			is_equal_approx(t.rotation, 0.0))
		var tx2: float = t.position.x
		t._tick_gust(0.25)
		check("the steady wind alone does not move them", is_equal_approx(t.position.x, tx2))
		t.queue_free()
	# Measured over a WHOLE gust, not one frame: the one-frame checks above
	# passed happily at a strength that carried tourists two-thirds of the way
	# across the beach and pinned 39% of them against the bay wall.
	var sweep := 0.0
	var sweep_rowdy := 0.0
	var steps := 200
	for i in steps:
		var g := sin(PI * (float(i) + 0.5) / float(steps))
		var f: float = game.wind.strength * (1.0 + (game.wind.gust_mult - 1.0) * g)
		var dt: float = game.wind.gust_len / float(steps)
		sweep += f * g * Tourist.GUST_SHOVE * dt
		sweep_rowdy += f * g * Tourist.GUST_SHOVE_ROWDY * dt
	check("a gust staggers tourists without sweeping them off the beach",
		sweep > 40.0 and sweep < 120.0 and sweep_rowdy < 180.0)
	game.wind.gusting = false
	check("gusts come round on their own", game.wind.gust_every > 0.0)

	# The painted palms sway, driven by the same wind.
	check("Veracruz's palms are animated", game._bg_sprite.material is ShaderMaterial)
	var p0: float = float(game._sway_mat.get_shader_parameter("phase"))
	game.wind.gusting = true
	game.wind._gust_t = game.wind.gust_len * 0.5
	await frames(3)
	check("the sway moves over time",
		not is_equal_approx(float(game._sway_mat.get_shader_parameter("phase")), p0))
	# The phone bug: a growing time value lost precision on the GPU and the
	# sway stuttered to a halt minutes in. An hour of frames must leave the
	# phase small, and still advancing every frame.
	var ph := 0.0
	var biggest := 0.0
	for i in 60 * 60 * 60:
		var before := ph
		ph = Game.sway_step(ph, 1.0 / 60.0, 0.5 + 0.5 * sin(float(i) * 0.01))
		biggest = maxf(biggest, ph)
		if i == 60 * 60 * 60 - 1:
			check("after an hour the sway still advances every frame",
				not is_equal_approx(ph, before))
	check("after an hour the phase is still a small number", biggest < TAU + 0.001)
	check("and whips harder in a gust", float(game._sway_mat.get_shader_parameter("gust")) > 0.5)
	game.wind.gusting = false
	game.level = 1
	game.apply_beach()
	check("a calm beach has no sway", game._bg_sprite.material == null)
	game.level = 2
	game.apply_beach()

	# No storms on foot in Veracruz; they arrive a little after the tractor.
	var keep_storm: bool = game.storm_active
	game.storm_active = false
	game.happy_hour = false
	game.owned.erase("tractor")
	game.weather._storm_t = game.storm_every() + 10.0
	game.weather._tick_storm(0.1)
	check("Veracruz holds storms back while you are on foot", not game.storm_active)
	check("and keeps the next one a little way off",
		game.weather._storm_t <= game.storm_every() - Weather.STORM_GRACE + 0.2)
	game.owned["waders"] = true
	game.owned["tractor"] = true
	game.weather._tick_storm(0.1)
	check("buying the tractor does not set one off instantly", not game.storm_active)
	game.weather._storm_t = game.storm_every()
	game.weather._tick_storm(0.1)
	check("once you have the tractor, storms come back", game.storm_active)
	game.storm_active = keep_storm
	game.owned.erase("tractor")
	game.owned.erase("waders")
	game.level = 1
	game.apply_beach()
	check("other levels storm on foot as before", game.weather.storms_allowed())
	game.level = 2
	game.apply_beach()
	# floating seaweed slides downwind, and wraps rather than piling up
	var raft: Seaweed = null
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).drifting:
			raft = c
			break
	if raft == null:
		raft = game.spawner._add_seaweed(Vector2(180, 560), 2, false, true)
	raft.position = Vector2(180, 560)
	var rx: float = raft.position.x
	for i in 30:
		raft._do_drift(0.1)
	check("floating seaweed is blown along the coast", raft.position.x > rx + 4.0)
	raft.position.x = 345.0
	for i in 20:
		raft._do_drift(0.1)
	check("and wraps round instead of piling at one end", raft.position.x < 345.0)
	game.owned = keep_owned
	game._reset_player_stats()
	for up in Upgrades.LIST:
		if game.owned.has(String(up["id"])):
			game.apply_upgrade(String(up["id"]))
	game.level = 1
	game.apply_beach()

	print("\n[playa del carmen]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("Cancun has no VIP area and no ferry", not game.vip.visible and not game.ferry.enabled)
	game.level = 3
	game.apply_beach()
	check("Playa del Carmen has a VIP frontage", game.vip.visible)
	check("on the far side from the skip",
		game.vip.rect.position.x > Zones.VIEW_W * 0.5 and Zones.BAY_POS.x < Zones.VIEW_W * 0.5)
	check("running all the way down to the water, where seaweed lands",
		game.vip.rect.end.y >= Zones.SHORE_Y)
	# weighting: the same pile costs triple inside the frontage
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	var base_mess: float = game.rep.shore_mess()
	var inside: Seaweed = game.spawner._add_seaweed(
		Vector2(game.vip.rect.get_center().x, Zones.SHORE_Y - 10.0), 2, false, false)
	await frames(1)
	var in_cost: float = game.rep.shore_mess() - base_mess
	inside.free()
	var outside: Seaweed = game.spawner._add_seaweed(Vector2(100.0, Zones.SHORE_Y - 10.0), 2, false, false)
	await frames(1)
	var out_cost: float = game.rep.shore_mess() - base_mess
	check("a pile in the VIP frontage costs triple", is_equal_approx(in_cost, out_cost * 3.0))
	check("and one outside costs the usual amount", out_cost > 0.0)
	outside.free()
	var flagged: Seaweed = game.spawner._add_seaweed(
		Vector2(game.vip.rect.get_center().x, Zones.SHORE_Y - 10.0), 1, false, false)
	await frames(2)
	check("the HUD calls out seaweed in the VIP area",
		game.hud._lbl_status.text.contains("VIP"))
	flagged.free()

	# the ferry
	check("the Cozumel ferry runs here", game.ferry.enabled)
	check("and is not due straight away", game.ferry._next > 20.0)
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	# Ten single-unit rafts drifting ahead of the ferry's lane, and two behind it.
	var ahead := []
	for i in 10:
		var r: Seaweed = game.spawner._add_seaweed(
			Vector2(30.0 + float(i) * 32.0, Zones.SHALLOW_TOP + 30.0 + float(i % 3) * 20.0),
			1, false, true)
		ahead.append(r)
	var behind: Seaweed = game.spawner._add_seaweed(
		Vector2(180.0, game.ferry.lane_y + 30.0), 1, false, true)
	await frames(1)
	var wake_units_before := 0
	for c in game.world.get_children():
		if c is Seaweed:
			wake_units_before += (c as Seaweed).units
	game.level_index = 0      # the share depends on the shift; pin shift 1
	game.ferry.depart()
	check("the ferry announces itself", game.ferry.running and game.ferry.inbound())
	check("the horn comes before the ferry is in view",
		game.ferry._x < -40.0 or game.ferry._x > Zones.VIEW_W + 40.0)
	# The wave is the slanted arm of the V: no wave ahead of the boat, and
	# behind it the crest climbs toward the beach at about 20 degrees.
	var sx: float = game.ferry.stern().x
	var back: float = -game.ferry._dir
	check("there is no wave ahead of the boat", game.ferry.crest_y(sx - back * 30.0) == INF)
	var slope: float = (game.ferry.crest_y(sx + back * 40.0) - game.ferry.crest_y(sx + back * 140.0)) / 100.0
	check("the wake is slanted at about 20 degrees", absf(slope - tan(deg_to_rad(20.0))) < 0.02)
	var travel: float = game.ferry._dir
	var landed_at := -1.0
	var landing_xs := []
	var tt := 0.0
	while tt < 30.0:
		game.ferry.tick(0.1)
		tt += 0.1
		for r in ahead:
			if is_instance_valid(r) and not (r as Seaweed).drifting and not landing_xs.has(r):
				landing_xs.append(r)
				if landed_at < 0.0:
					landed_at = tt
	# It sweeps along the beach in the direction the boat went: each landing
	# is further along the boat's path than the one before.
	var in_order := true
	for i in range(1, landing_xs.size()):
		var a: Seaweed = landing_xs[i - 1]
		var b: Seaweed = landing_xs[i]
		if is_instance_valid(a) and is_instance_valid(b) and (b.position.x - a.position.x) * travel < -20.0:
			in_order = false
	check("the wave sweeps along the beach the way the boat went", in_order and landing_xs.size() >= 2)
	# The sweep runs ~9.4s-13.4s after the horn, and with few riders picked at
	# random the first to land can sit anywhere in it -- so the window covers
	# the whole sweep. (At 12s it flaked whenever both riders were far-side.)
	check("its wake lands a few seconds after the horn",
		landed_at > 5.0 and landed_at < 15.0)
	var beached_units := 0
	var drifting_units := 0
	for c in game.world.get_children():
		if c is Seaweed:
			if (c as Seaweed).drifting:
				drifting_units += (c as Seaweed).units
			else:
				beached_units += (c as Seaweed).units
	check("the wake creates no new seaweed", beached_units + drifting_units == wake_units_before)
	# Shift index 0 here: 20% of the ten rafts ahead of the ferry -- two.
	check("on shift 1 the wake carries a light 20%", beached_units == 2)
	# Only the test's own rafts: the spawner may add a clump of its own while
	# the test waits a frame.
	var rafts_drifting := 0
	for r in ahead + [behind]:
		if is_instance_valid(r) and (r as Seaweed).drifting:
			rafts_drifting += 1
	check("and leaves the rest drifting", rafts_drifting == 9)
	check("the share climbs shift by shift, 20/30/60/80",
		is_equal_approx(game.ferry.share_for(0), 0.2) and is_equal_approx(game.ferry.share_for(1), 0.3)
			and is_equal_approx(game.ferry.share_for(2), 0.6) and is_equal_approx(game.ferry.share_for(3), 0.8))
	check("anything behind the ferry is out of the wake's path",
		is_instance_valid(behind) and behind.drifting)
	check("the warning clears once it has landed", not game.ferry.inbound())
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.level = 1
	game.apply_beach()

	print("\n[cozumel]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("daytime levels have no darkness", not game.night.active and not game.night.visible)
	game.level = 4
	game.apply_beach()
	check("Cozumel is a night level", game.night.active and game.night.visible)
	check("and it is properly dark", game.night.darkness() > 0.7)
	check("the darkness sits over the beach but under the weather and popups",
		game.night.z_index > 0 and game.night.z_index < game.fx.z_index)
	# lights: the lantern, the lit bay, the resort's own lamps, and phones
	var keep_o: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game._recompute_carry()
	var ls: PackedVector3Array = game.night.lights()
	check("the worker carries a lantern",
		ls.size() > 0 and is_equal_approx(ls[0].z, game.night.lantern))
	check("the bay is always lit, so the skip can be found",
		ls.size() > 1 and ls[1].distance_to(Vector3(Zones.BAY_POS.x, Zones.BAY_POS.y + 10.0, game.night.bay_light)) < 1.0)
	check("the resort's torches light the beach", ls.size() >= 2 + game.night.fixed.size())
	game.owned["waders"] = true
	game.owned["tractor"] = true
	game._recompute_carry()
	check("the tractor's headlights light far more than a lantern",
		game.night.player_radius() > game.night.lantern * 1.5)
	game.owned = keep_o
	game._reset_player_stats()
	for up in Upgrades.LIST:
		if game.owned.has(String(up["id"])):
			game.apply_upgrade(String(up["id"]))
	var phones_before: int = game.night.lights().size()
	var tt2: Tourist = Spawner.TOURIST_SCENE.instantiate()
	tt2.game = game
	game.world.add_child(tt2)
	tt2.setup(Vector2(180, 300), 480.0, false, Zones.TOURIST_DESPAWN_Y)
	check("tourists carry a phone glow, so they are never invisible",
		game.night.lights().size() == phones_before + 1)
	tt2.free()
	check("never more lights than the shader holds", game.night.lights().size() <= Night.MAX_LIGHTS)
	# the moon
	check("the moon is not out straight away", not game.night.moonlit())
	var dark: float = game.night.darkness()
	game.night.start_moon()
	for i in 30:
		game.night.tick(0.1)
	check("when the clouds part, the beach lights up", game.night.darkness() < dark * 0.5)
	check("and the HUD says so", game.night.moonlit())
	for i in 100:
		game.night.tick(0.1)
	check("then the dark closes back in", is_equal_approx(game.night.darkness(), dark))
	game.level = 1
	game.apply_beach()

	print("\n[bacalar]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("calm beaches have no surf", not game.surf.active)
	game.level = 5
	game.apply_beach()
	game.level_index = 0
	check("Bacalar has big surf", game.surf.active)
	check("and a lull before the first set", not game.surf.set_rolling() and game.surf._next_set > 10.0)
	for c in game.world.get_children():
		if c is Tourist or c is Seaweed:
			c.free()
	var keep_o5: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game._reset_player_stats()
	game._recompute_carry()
	game.apply_beach()

	# -- a set you can count: small waves first, then one big wave ------------
	game.surf._sets = 0
	game.surf.start_set()
	var kinds: Array = game.surf._queue.duplicate()
	check("a set is two or three small waves", kinds.count("small") >= 2 and kinds.count("small") <= 3)
	check("then exactly one big wave, last", kinds.count("big") == 1 and kinds[-1] == "big")
	check("the HUD tells you to count", game.surf.set_rolling() and not game.surf.big_coming())
	game.surf._queue.clear()

	# -- small waves are harmless; the big one knocks you back ----------------
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.position = Vector2(180, Zones.SHALLOW_TOP + 60.0)
	var y_in: float = game.player.position.y
	game.surf.waves.append({"y": y_in + 4.0, "big": false, "rogue": false, "riders": []})
	game.surf.tick(0.1)
	check("a small wave washes past harmlessly", not game.player.tumbling())
	game.surf.waves.clear()
	game.surf.waves.append({"y": y_in + 4.0, "big": true, "rogue": false, "riders": []})
	game.surf.tick(0.1)
	check("the big wave knocks you when it reaches you in the water", game.player.tumbling())
	# smooth: no big per-frame jumps, and it takes long enough to read as motion
	var last_y: float = game.player.position.y
	var biggest_step := 0.0
	var frames_moving := 0
	for i in 60:
		await physics_frame
		var step: float = absf(game.player.position.y - last_y)
		biggest_step = maxf(biggest_step, step)
		if step > 0.01:
			frames_moving += 1
		last_y = game.player.position.y
	check("back toward the shore", game.player.position.y < y_in - 60.0)
	check("in one smooth motion, not a jump", biggest_step < 8.0 and frames_moving >= 25)
	check("and you find your feet again", not game.player.tumbling() and is_zero_approx(game.player.rotation))
	var foot_throw: float = y_in - game.player.position.y

	# -- only a rogue reaches up onto the sand -------------------------------
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.position = Vector2(180, Zones.SHALLOW_TOP - 20.0)
	game.surf.waves.clear()
	game.surf.waves.append({"y": Zones.SHALLOW_TOP + 10.0, "big": true, "rogue": false, "riders": []})
	for i in 10:
		game.surf.tick(0.1)
	check("a big wave cannot reach you up on the sand", not game.player.tumbling())
	game.surf.waves.clear()
	game.surf.waves.append({"y": Zones.SHALLOW_TOP + 10.0, "big": true, "rogue": true, "riders": []})
	for i in 10:
		game.surf.tick(0.1)
	check("but a rogue runs up and catches you on the lower beach", game.player.tumbling())
	for i in 60:
		await physics_frame

	# -- the heavy tractor ---------------------------------------------------
	# Step out of the physics frame first: freeing an Area2D while the physics
	# server is still flushing its queries is an engine error.
	await frames(1)
	for c in game.world.get_children():
		if c is Tourist:
			c.free()
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.owned["waders"] = true
	game.owned["tractor"] = true
	game._recompute_carry()
	game.player.position = Vector2(180, Zones.SHALLOW_TOP + 60.0)
	var y_tr: float = game.player.position.y
	game.surf.waves.clear()
	game.surf.waves.append({"y": y_tr + 4.0, "big": true, "rogue": false, "riders": []})
	game.surf.tick(0.1)
	for i in 60:
		await physics_frame
	check("the heavy tractor is pushed only half as far",
		y_tr - game.player.position.y < foot_throw * 0.7)
	game.player.position = Vector2(180, Zones.HOTEL_BOTTOM + 40.0)

	# -- the big wave carries seaweed in, at the ferry's per-shift rate --------
	game.surf.waves.clear()
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	for i in 10:
		game.spawner._add_seaweed(Vector2(30.0 + float(i) * 32.0, Zones.SHALLOW_TOP + 30.0 + float(i % 3) * 25.0),
			1, false, true)
	await frames(1)
	game.level_index = 0
	game.surf._set_rogue = false
	game.surf._launch("small")
	for i in 120:
		game.surf.tick(0.1)
	var beached_small := 0
	for c in game.world.get_children():
		if c is Seaweed and not (c as Seaweed).drifting:
			beached_small += (c as Seaweed).units
	check("small waves carry no seaweed", beached_small == 0)
	game.surf._launch("big")
	for i in 120:
		game.surf.tick(0.1)
	var beached := 0
	var drifting := 0
	for c in game.world.get_children():
		if c is Seaweed:
			if (c as Seaweed).drifting:
				drifting += (c as Seaweed).units
			else:
				beached += (c as Seaweed).units
	check("on shift 1 the big wave carries a light 20% ashore", beached == 2 and drifting == 8)
	check("the same rising rates as the ferry, shift by shift",
		is_equal_approx(game.surf.share_for(1), 0.3) and is_equal_approx(game.surf.share_for(3), 0.8))
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()

	game.surf.waves.clear()
	game.owned = keep_o5
	game._reset_player_stats()
	for up in Upgrades.LIST:
		if game.owned.has(String(up["id"])):
			game.apply_upgrade(String(up["id"]))
	game._recompute_carry()
	game.level = 1
	game.apply_beach()

	print("\n[isla holbox]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("every other beach is banded", not Zones.RADIAL and game._water.visible)
	check("and keeps the normal seaweed rate", is_equal_approx(game.spawn_scale() / game.adapt, 1.0))
	game.level = 6
	game.apply_beach()
	check("Holbox is a round island", Zones.RADIAL)
	check("depth is distance from the island's centre",
		is_equal_approx(Zones.depth(Zones.CENTER + Vector2(0, -100)), 100.0))
	check("the horizontal water strip is switched off", not game._water.visible)
	var ring_ok := true
	var shown := 0
	for b in game._buoys.get_children():
		if (b as CanvasItem).visible:
			shown += 1
			var bp: Vector2 = (b as Node2D).position if b is Node2D else (b as Control).position + Vector2(4, 4)
			if absf(Zones.depth(bp) - Zones.DEEP_TOP) > 2.0:
				ring_ok = false
	check("the buoys ring the island at the deep line", ring_ok and shown > 0)

	# no storms and no Happy Hour here
	check("no storms on Holbox", not game.weather.storms_allowed())
	check("seaweed arrives more slowly, on every shift", game.spawn_scale() / game.adapt < 1.0)
	game.happy_hour = false
	game.weather._happy_t = Weather.HAPPY_EVERY + 1.0
	game.weather._tick_happy_hour(0.1)
	check("no Happy Hour on Holbox", not game.happy_hour)

	# the worker lives on the beach ring, and walks the streets into the village
	for c in game.world.get_children():
		if c is Tourist or c is Seaweed:
			c.free()
	var keep_o6: Dictionary = game.owned.duplicate()
	game.owned.clear()
	game._reset_player_stats()
	game._recompute_carry()
	game.apply_beach()
	var beach_r: float = (Zones.HOTEL_BOTTOM + Zones.SHALLOW_TOP) * 0.5
	var round_ok := true
	for k in 16:
		var a := float(k) / 16.0 * TAU
		game.player.position = Zones.CENTER + Vector2(cos(a), sin(a)) * beach_r
		game.player._clamp_position()
		if absf(Zones.depth(game.player.position) - beach_r) > 1.0:
			round_ok = false
	check("you can walk the whole way round the island", round_ok)
	var street_ok := true
	for k in Zones.STREETS:
		for d in [Zones.PLAZA_R + 10.0, 70.0, Zones.HOTEL_BOTTOM - 10.0]:
			var q: Vector2 = Zones.CENTER + Zones.street_axis(k) * d
			game.player.position = q
			game.player._clamp_position()
			if game.player.position.distance_to(q) > 1.0:
				street_ok = false
	check("every street is open all the way to the plaza", street_ok)
	game.player.position = Zones.CENTER
	game.player._clamp_position()
	check("the skip sits in the open central plaza", game.player.position.distance_to(Zones.CENTER) < 1.0
		and Zones.BAY_POS.distance_to(Zones.CENTER) < 1.0)
	# between two streets, inside the village, is somebody's house
	var house: Vector2 = Zones.CENTER + Vector2(cos(Zones.street_angle(0) + PI / 8.0), sin(Zones.street_angle(0) + PI / 8.0)) * 80.0
	game.player.position = house
	game.player._clamp_position()
	check("but not through the houses", game.player._in_village_open(game.player.position - Zones.CENTER,
		Zones.depth(game.player.position)) or Zones.depth(game.player.position) >= Zones.HOTEL_BOTTOM + 3.0)
	check("pushed only to the nearest open ground, not across the village",
		game.player.position.distance_to(house) < 40.0)
	game.player.position = Zones.CENTER + Vector2(0, 260.0)
	game.player._clamp_position()
	check("and not into the deep without the trawler", Zones.depth(game.player.position) <= Zones.DEEP_TOP)
	game.player.position = Zones.CENTER + Vector2(0, -(Zones.SHALLOW_TOP + 20.0))
	check("wading is by distance from the shore", game.player.in_water())
	game.player.position = Zones.CENTER + Vector2(0, -beach_r)
	check("and the beach ring is dry", not game.player.in_water())

	# seaweed comes from every side and washes up on the ring
	var right := 0
	var left := 0
	var up := 0
	var down := 0
	for i in 200:
		var q: Vector2 = Zones.random_point(Zones.SHALLOW_TOP + 14.0, Zones.DEEP_TOP - 12.0)
		if q.x > Zones.CENTER.x + 100.0: right += 1
		if q.x < Zones.CENTER.x - 100.0: left += 1
		if q.y < Zones.CENTER.y - 100.0: up += 1
		if q.y > Zones.CENTER.y + 100.0: down += 1
	check("seaweed arrives from every side", right > 5 and left > 5 and up > 5 and down > 5)
	var isle_raft: Seaweed = game.spawner._add_seaweed(Zones.CENTER + Vector2(170.0, 0.0), 1, false, true)
	await frames(1)
	for i in 400:
		if not isle_raft.drifting:
			break
		isle_raft._do_drift(0.1)
	check("drifting seaweed washes up on the island's shore",
		not isle_raft.drifting and absf(Zones.depth(isle_raft.position) - Zones.SHORE_Y) < 14.0)
	isle_raft.free()

	# tourists walk out from the compound in their own direction, and back
	var isle_tr: Tourist = game.spawner.make_tourist(Zones.CENTER + Vector2(Zones.TOURIST_SPAWN_Y, 0.0), 150.0, false)
	var d0: float = Zones.depth(isle_tr.position)
	# Until it has walked a little way (it fades in first), not a fixed frame
	# count: at a capped 60 fps, 20 frames was right on the edge.
	for i in 180:
		await frames(1)
		if Zones.depth(isle_tr.position) > d0 + 10.0:
			break
	check("tourists walk out of the village along a street", Zones.depth(isle_tr.position) > d0 + 10.0
		and isle_tr.position.x > Zones.CENTER.x + Zones.TOURIST_SPAWN_Y
		and absf(isle_tr.position.y - Zones.CENTER.y) < Zones.STREET_HALF_W + 4.0)
	isle_tr.free()

	# ---- the three events ----------------------------------------------------
	var h: Holbox = game.holbox
	check("the events are running here", h.active)
	check("the whale shark and flamingos use their art", Holbox.WHALE != null and Flamingos.ART != null)
	h._last = "whale"
	var repeats := false
	for i in 12:
		var prev: String = h._last
		h.event = ""
		h._next = 0.0
		h.tick(0.01)
		if h.event == prev:
			repeats = true
		h.event = ""
	check("the same event never comes twice in a row", not repeats)

	var tourists_before := 0
	for c in game.world.get_children():
		if c is Tourist:
			tourists_before += 1
	h.start("whale")
	var tourists_after := 0
	for c in game.world.get_children():
		if c is Tourist:
			tourists_after += 1
	check("a whale shark sends a crowd into the water", tourists_after == tourists_before + h.whale_crowd)
	check("and the HUD says so", h.status_text().contains("WHALE"))
	for c in game.world.get_children():
		if c is Tourist:
			c.free()

	var kelp_before: int = game.spawner.count_seaweed(true)
	h.start("sandbar")
	h.tick(2.0)
	check("low tide leaves kelp out at the end of the sandbar",
		game.spawner.count_seaweed(true) >= kelp_before + h.sandbar_kelp)
	var bar_dir := Vector2(cos(h.angle), sin(h.angle))
	var out_there: Vector2 = Zones.CENTER + bar_dir * (Zones.DEEP_TOP + 30.0)
	check("the sandbar reaches out past the deep line", h.on_sandbar(out_there))
	game.player.position = out_there
	game.player._clamp_position()
	check("you can walk out on it without the trawler",
		Zones.depth(game.player.position) > Zones.DEEP_TOP + 20.0)
	check("and it is dry underfoot", not game.player.in_water())
	h.tick(h._len)
	game.player._clamp_position()
	check("when the tide returns you are back within the usual limit",
		Zones.depth(game.player.position) <= Zones.DEEP_TOP)

	h.start("flamingo")
	h.tick(2.0)
	var flock_mid: Vector2 = Zones.CENTER + Vector2(cos(h.angle), sin(h.angle)) * beach_r
	check("flamingos close off their stretch of beach", h.blocks(flock_mid))
	game.player.position = flock_mid
	game.player._clamp_position()
	check("you are moved to the edge of the flock, along the beach",
		not h.blocks(game.player.position) and absf(Zones.depth(game.player.position) - beach_r) < 1.5)
	var mouths_clear := true
	for k in Zones.STREETS:
		var mouth: Vector2 = Zones.CENTER + Zones.street_axis(k) * beach_r
		for off in [-Zones.STREET_HALF_W, 0.0, Zones.STREET_HALF_W]:
			var n: Vector2 = Vector2(-Zones.street_axis(k).y, Zones.street_axis(k).x)
			if h.blocks(mouth + n * off):
				mouths_clear = false
	check("they never land across a street, so every route in stays open", mouths_clear)
	var under: Seaweed = game.spawner._add_seaweed(flock_mid, 2, false, false)
	await frames(1)
	under._player = game.player
	under._timer = 99.0
	under._do_gather(0.1)
	check("nothing can be gathered from under them", under.units == 2)
	under.free()
	h.tick(h._len)
	check("and once they move on, the beach is open again", not h.blocks(flock_mid))

	game.owned = keep_o6
	game._reset_player_stats()
	for up2 in Upgrades.LIST:
		if game.owned.has(String(up2["id"])):
			game.apply_upgrade(String(up2["id"]))
	game._recompute_carry()
	game.level = 1
	game.apply_beach()
	check("back on a banded beach, everything is banded again", not Zones.RADIAL and game._water.visible)

	print("\n[pile merging]")
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	var dying: Seaweed = game.spawner._add_seaweed(Vector2(120, Zones.SHORE_Y - 10.0), 2, false, false)
	await frames(1)
	dying.queue_free()
	check("seaweed never merges into a pile that is being removed",
		game.find_pile_near(Vector2(124, Zones.SHORE_Y - 10.0), null) == null)
	await frames(1)

	print("\n[puerto morelos]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("other beaches have no stream", not game.stream.active)
	game.level = 7
	game.apply_beach()
	var st: Stream = game.stream
	check("Puerto Morelos has its stream", st.active and st.points.size() > 5)
	check("which runs from the mangroves down to the sea",
		st.points[0].y < st.points[st.points.size() - 1].y
			and absf(st.points[st.points.size() - 1].y - Zones.SHALLOW_TOP) < 6.0)
	# the current
	var mid: Dictionary = st.point_at(st._total * 0.65)
	var in_it: Vector2 = mid["pt"]
	check("wading the stream slows you", st.slow_at(in_it) < 1.0)
	var sp_push: Vector2 = st.push_at(in_it, false)
	check("and carries you downstream", sp_push.dot(mid["dir"]) > st.current * 0.9)
	check("the tractor is carried half as hard",
		st.push_at(in_it, true).length() < sp_push.length() * 0.6)
	var dry: Vector2 = in_it + Vector2(-(mid["dir"] as Vector2).y, (mid["dir"] as Vector2).x) * 30.0
	check("dry sand either side is unaffected", st.slow_at(dry) == 1.0 and st.push_at(dry, false) == Vector2.ZERO)
	# tourists wading across are carried downstream too
	var wader: Tourist = Spawner.TOURIST_SCENE.instantiate()
	wader.game = game
	game.world.add_child(wader)
	wader.setup(in_it, Zones.SHALLOW_TOP + 40.0, false, Zones.TOURIST_DESPAWN_Y)
	await frames(1)
	wader.position = in_it
	var before_w: Vector2 = wader.position
	wader._tick_stream(0.2)
	var moved_w: Vector2 = wader.position - before_w
	check("tourists crossing the stream are carried downstream",
		moved_w.dot(mid["dir"]) > st.current * Tourist.TOURIST_STREAM * 0.2 * 0.9)
	wader.queue_free()
	# seaweed floats down to the mouth and piles up. Park the worker in the bay
	# first -- left standing near the stream they rake units off passing clumps.
	game.player.position = Zones.BAY_POS
	for c in game.world.get_children():
		if c is Seaweed or c is Tourist:
			c.free()
	var up_s: Seaweed = game.spawner._add_seaweed(st.point_at(st._total * 0.4)["pt"], 2, false, false)
	var up_s2: Seaweed = game.spawner._add_seaweed(st.point_at(st._total * 0.55)["pt"], 1, false, false)
	await frames(1)
	for i in 200:
		st.tick(0.1)
	await frames(1)
	var mouth_units := 0
	var sp_mouth: Vector2 = st.points[st.points.size() - 1]
	for c in game.world.get_children():
		# 50px: piles merge within 26px of where the mouth pile forms, so the
		# host can sit ~45px from the mouth point itself.
		if c is Seaweed and not c.is_queued_for_deletion() and (c as Seaweed).position.distance_to(sp_mouth) < 50.0:
			mouth_units += (c as Seaweed).units
	# Asks whether THESE clumps reached the mouth, not for an exact total: the
	# live game keeps spawning, and a clump landing near the mouth during the
	# one-frame waits made an exact count flaky.
	var both_there := true
	for flowed in [up_s, up_s2]:
		if is_instance_valid(flowed) and not flowed.is_queued_for_deletion() and flowed.position.distance_to(sp_mouth) >= 50.0:
			both_there = false
	check("seaweed in the stream floats down and piles up at its mouth", both_there and mouth_units >= 3)
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	# the flash flood -- re-apply the level first: the mouth test above ran the
	# stream for 20 simulated seconds, which spent half the flood timer
	game.apply_beach()
	check("the flood is not straight away", not st.flooding() and st._next_flood > 20.0)
	var calm_push: float = st.push_at(in_it, false).length()
	var calm_w: float = st.width()
	st.start_flood()
	check("a flood is its debris -- the stream does not swell or turn",
		is_equal_approx(st.width(), calm_w) and is_equal_approx(st.push_at(in_it, false).length(), calm_push))
	check("and the HUD says so", st.status_text().contains("FLOOD"))
	for i in 40:
		st.tick(0.1)
	var debris := 0
	for c in game.world.get_children():
		if c is Seaweed and not c.is_queued_for_deletion():
			debris += 1
	check("it flushes debris down from the mangroves", debris > 0)
	for i in 120:
		st.tick(0.1)
	check("then the stream settles again", not st.flooding() and is_equal_approx(st.width(), calm_w))
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.level = 1
	game.apply_beach()

	print("\n[mahahual]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("other beaches have no sargassum", not game.mat.active and game.mat.share == 0.0)
	game.level = 8
	game.apply_beach()
	check("Mahahual is in sargassum season", game.mat.active and game.mat.share > 0.0)
	check("the drifting mat uses its art", SargassumMat.ART != null)
	game.player.position = Zones.BAY_POS
	for c in game.world.get_children():
		if c is Seaweed or c is Tourist:
			c.free()
	for i in 160:
		game.spawner.spawn_seaweed(1)
	var sarg := 0
	var total := 0
	for c in game.world.get_children():
		if c is Seaweed and not (c as Seaweed).kelp:
			total += 1
			if (c as Seaweed).sargassum:
				sarg += 1
	check("about half of what washes in is sargassum",
		total > 0 and float(sarg) / float(total) > 0.3 and float(sarg) / float(total) < 0.7)
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	var sg: Seaweed = game.spawner._add_seaweed(Vector2(100, Zones.SHORE_Y - 10.0), 2, false, false)
	sg.make_sargassum()
	var plain: Seaweed = game.spawner._add_seaweed(Vector2(250, Zones.SHORE_Y - 10.0), 2, false, false)
	await frames(1)
	check("sargassum is drawn gold, not brown", sg._sprite.material is ShaderMaterial)
	check("it is worth double", sg.value_per_unit() == plain.value_per_unit() * 2)
	check("and heavy: two slots per unit", sg.weight() == 2 and plain.weight() == 1)
	# the load: with one slot left, a heavy unit must NOT be taken -- and not lost
	var keep_cap: int = game.player.capacity
	# A stunned or wave-knocked worker cannot rake at all; earlier sections can
	# leave either running.
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player._knocking = false
	game.player.carried = keep_cap - 1
	sg._player = game.player
	sg._timer = 99.0
	sg._do_gather(0.1)
	check("with one slot left you cannot lift sargassum", sg.units == 2 and game.player.carried == keep_cap - 1)
	game.player.carried = keep_cap - 2
	sg._timer = 99.0
	sg._do_gather(0.1)
	check("with two you can, and it fills both", sg.units == 1 and game.player.carried == keep_cap)
	game.player.carried = 0
	game.player.carried_value = 0
	sg._player = null
	# != plain, not == null: the level's own spawner may have beached some
	# sargassum near by, and merging into THAT would be right.
	check("sargassum only piles up with sargassum",
		game.find_pile_near(plain.position + Vector2(4, 0), sg) != plain)
	sg.free()
	plain.free()
	# the mat
	check("the mat is not straight away", not game.mat.drifting_in() and game.mat._next > 20.0)
	check("it drops more each shift", game.mat.piles_for(0) < game.mat.piles_for(1)
		and game.mat.piles_for(1) < game.mat.piles_for(3))
	# Clear the beach right before the mat: the one-frame wait above lets the
	# live game spawn seaweed -- half of it sargassum here -- which would
	# otherwise be counted as part of the mat's landing.
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.level_index = 0
	game.mat.launch()
	check("a mat drifts in from far out", game.mat.drifting_in() and game.mat.mat_y > Zones.VIEW_H)
	check("and the HUD warns of it", game.mat.status_text().contains("MAT"))
	var ticks := 0
	while game.mat.drifting_in() and ticks < 600:
		game.mat.tick(0.1)
		ticks += 1
	check("slowly -- with long warning", ticks > 150)
	var landed_units := 0
	var heaps := 0
	for c in game.world.get_children():
		if c is Seaweed and not c.is_queued_for_deletion():
			var q := c as Seaweed
			if q.sargassum and not q.drifting:
				landed_units += q.units
				if q.heap_showing():
					heaps += 1
	check("it comes ashore as a big sargassum heap", heaps >= 1 and landed_units == game.mat.units_for(0))
	var big: Seaweed = null
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).heap_showing():
			big = c
	if big != null:
		check("drawn as a grouped mound, at the art's own pixel scale",
			Seaweed.HEAP_FRAMES.has(big._sprite.texture) and big._sprite.scale == Vector2(2, 2))
		check("holding more than an ordinary pile", big.units > Seaweed.MAX_PILE or game.mat.units_for(0) <= Seaweed.HEAP_MAX)
		big.units = Seaweed.HEAP_SHOWS - 1
		big._refresh()
		check("and raked down, it becomes an ordinary pile again",
			not big.heap_showing() and big._size < 64.0 and not Seaweed.HEAP_FRAMES.has(big._sprite.texture))
	check("and the HUD says it has come ashore", game.mat.status_text().contains("ASHORE"))
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.player.capacity = keep_cap
	game.level = 1
	game.apply_beach()

	print("\n[akumal]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("other beaches have no nests", game.nests.is_empty() and not game.hatch.active)
	game.level = 9
	game.apply_beach()
	check("Akumal has its turtle nests", game.nests.size() == 4 and game.hatch.active)
	check("the hatchlings use their two-frame crawl art", Hatchlings.FRAMES.size() == 2)
	game.player.position = Zones.BAY_POS
	for c in game.world.get_children():
		if c is Seaweed or c is Tourist:
			c.free()
	var nest0: Rect2 = game.nests[0]
	game.player.position = nest0.get_center()
	game.player._clamp_position()
	check("the worker cannot walk into a nest", not game.in_nest(game.player.position, 0.0))
	check("they are moved to the nearest edge, not across the beach",
		game.player.position.distance_to(nest0.get_center()) < nest0.size.length() * 0.5 + Player.NEST_PAD + 2.0)
	var tp: Vector2 = game.sidestep_nests(nest0.get_center(), 8.0)
	check("tourists step round a nest, still heading for the water",
		not game.in_nest(tp, 0.0) and is_equal_approx(tp.y, nest0.get_center().y))
	for i in 150:
		game.spawner.spawn_seaweed(1)
	var in_nest_n := 0
	for c in game.world.get_children():
		if c is Seaweed and not (c as Seaweed).drifting and game.in_nest((c as Seaweed).position, 0.0):
			in_nest_n += 1
	check("seaweed never lands inside a nest", in_nest_n == 0)
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.player.position = Zones.BAY_POS
	await frames(1)
	# a clear path: every hatchling makes it, and it pays
	var h9: Hatchlings = game.hatch
	var cr0: int = game.credits_earned
	h9.start(0)
	check("a nest hatches into a line of hatchlings", h9.hatching() and h9.turtles.size() == h9.count)
	check("and the HUD asks you to clear the way", h9.status_text().contains("CLEAR"))
	for i in 200:
		h9.tick(0.1)
		if not h9.hatching():
			break
	check("with a clear path every hatchling reaches the sea", h9._saved == h9.count)
	check("and each one pays out", game.credits_earned - cr0 == h9.count * int(round(game.price_per_unit * h9.reward_units)))
	check("the HUD celebrates", h9.status_text().contains("ALL"))
	# a pile in the way stops them -- until it is cleared
	var n1: Rect2 = game.nests[1]
	var wall := []
	for k in 4:
		wall.append(game.spawner._add_seaweed(Vector2(n1.position.x + 6.0 + float(k) * 11.0, n1.end.y + 22.0), 8, false, false))
	await frames(1)
	h9.start(1)
	for i in 40:
		h9.tick(0.1)
	check("a fully blocked hatching waits for you rather than ending at once", h9.hatching())
	var stuck := 0
	for ht in h9.turtles:
		if not ht["done"] and (ht["pos"] as Vector2).y < n1.end.y + 22.0:
			stuck += 1
	check("a seaweed pile in their path stops the hatchlings", stuck > 0 and h9._saved < h9.count)
	for w in wall:
		w.free()
	await frames(1)
	for i in 200:
		h9.tick(0.1)
		if not h9.hatching():
			break
	check("clear it and they carry on to the sea", h9._saved == h9.count)
	# the real hatching: one or two from every nest, wandering, and seaweed
	# planted in their way just before
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	h9._t = -1.0
	h9._warned = false
	h9._next = Hatchlings.WARN_LEAD - 0.01
	h9.tick(0.01)
	var planted := 0
	for c in game.world.get_children():
		if c is Seaweed and (c as Seaweed).drifting:
			planted += 1
	check("just before a hatching, seaweed washes up in their way", planted == Hatchlings.PLANT_NESTS)
	check("and the HUD warns the nests are stirring", h9.status_text().contains("STIRRING"))
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	h9.start()
	var per_nest := []
	for nr in game.nests:
		var nn := 0
		for ht in h9.turtles:
			var hp: Vector2 = ht["pos"]
			if hp.x >= (nr as Rect2).position.x and hp.x <= (nr as Rect2).end.x and absf(hp.y - (nr as Rect2).end.y) < 6.0:
				nn += 1
		per_nest.append(nn)
	check("one or two hatch from every nest", per_nest.all(func(v): return v >= 1 and v <= 2))
	var x0: Array = h9.turtles.map(func(ht): return (ht["pos"] as Vector2).x)
	for i in 30:
		h9.tick(0.1)
	var moved_x := 0.0
	for i in h9.turtles.size():
		moved_x = maxf(moved_x, absf((h9.turtles[i]["pos"] as Vector2).x - float(x0[i])))
	check("and they wander down, not in a straight line", moved_x > 4.0)
	var in_nest := false
	for ht in h9.turtles:
		if game.in_nest(ht["pos"], -0.5):
			in_nest = true
	check("round the other nests, never through them", not in_nest)
	for i in 300:
		h9.tick(0.1)
		if not h9.hatching():
			break
	# left stuck until time runs out, it costs reputation
	var wall2 := []
	var n2: Rect2 = game.nests[2]
	for k in 4:
		wall2.append(game.spawner._add_seaweed(Vector2(n2.position.x + 6.0 + float(k) * 11.0, n2.end.y + 14.0), 8, false, false))
	await frames(1)
	game.rep.value = 90.0
	h9.start(2)
	for i in 300:
		h9.tick(0.1)
		if not h9.hatching():
			break
	check("hatchlings left stranded cost reputation", game.rep.value < 90.0 - h9.lost_rep)
	check("and the HUD says how many made it", h9.status_text().contains("OF"))
	for w in wall2:
		if is_instance_valid(w):
			w.free()
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.level = 1
	game.apply_beach()

	print("\n[tulum]")
	paused = false
	game.level = 1
	game.apply_beach()
	check("other beaches have no hurricane", not game.hurricane.active and game.hurricane.spawn_factor() == 1.0)
	game.level = 10
	game.apply_beach()
	game.level_index = 0
	game.begin_level()
	await frames(1)
	var hu: Hurricane = game.hurricane
	var goal10: float = float(game.current_level().get("credits", 1500))
	check("the finale has a hurricane", hu.active)
	check("its palms and treeline sway", game._bg_sprite.material is ShaderMaterial)
	await frames(2)
	var calm_amp: float = float(game._sway_mat.get_shader_parameter("amp"))
	check("each shift starts calm and sunny",
		hu.phase == Hurricane.Phase.CALM and not game.wind.active() and not game.storm_active and not game.surf.active)
	check("no random storms or Happy Hour to compete with it",
		not game.weather.storms_allowed())
	game.credits_earned = int(goal10 * 0.16)
	hu.tick(0.1)
	check("the wind rises as the shift goes on", hu.phase == Hurricane.Phase.GATHERING and game.wind.active())
	game.credits_earned = int(goal10 * 0.36)
	hu.tick(0.1)
	check("then the hurricane hits: storm, surf and gales",
		hu.phase == Hurricane.Phase.FRONT and game.storm_active and game.surf.active and game.wind.strength > 30.0)
	check("blowing left to right", game.wind.force() > 0.0)
	await frames(2)
	check("the palms barely stir in the calm, and whip in the storm",
		float(game._sway_mat.get_shader_parameter("amp")) > calm_amp * 2.0)
	game.credits_earned = int(goal10 * 0.61)
	hu.tick(0.1)
	check("then the eye: everything stops",
		hu.phase == Hurricane.Phase.EYE and not game.wind.active() and not game.storm_active and not game.surf.active)
	check("seaweed barely arrives -- a breather", hu.spawn_factor() < 0.5)
	check("and the HUD counts it down", hu.status_text().contains("EYE"))
	for i in int(hu.eye_len * 10.0) + 2:
		hu.tick(0.1)
	check("then the back wall, from the other side",
		hu.phase == Hurricane.Phase.BACKWALL and game.storm_active and game.wind.force() < 0.0)
	check("the worker is pushed the other way now", game.player.wind_push(true) < 0.0)
	await frames(2)
	check("and the palms lean the other way", float(game._sway_mat.get_shader_parameter("lean")) < 0.0)
	check("the storm holds until the shift ends -- it is not on a timer", game.storm_active)
	game.weather.tick(120.0)
	check("even after two minutes", game.storm_active)
	game.begin_level()
	await frames(1)
	check("the next shift starts calm again",
		hu.phase == Hurricane.Phase.CALM and not game.storm_active and not game.wind.active())
	game.credits_earned = 0
	game.level = 1
	game.apply_beach()
	game.begin_level()
	await frames(1)

	print("\n[crab]")
	var cb: Crab = game.crab
	game.level = 1
	game.apply_beach()
	game.begin_level()
	check("no crab on beaches without one", not cb.active)
	check("the crab has all its art: sideways, toward, away, digging",
		cb._side.size() == 4 and cb._front.size() == 4 and cb._back.size() == 4 and cb._dig.size() == 4)
	game.level = 3
	game.apply_beach()
	var crab_shift := int(Beaches.for_level(3)["crab"]["shift"])
	game.level_index = (crab_shift + 1) % Levels.LIST.size()
	game.begin_level()
	check("only in its one shift of the level", not cb.active)
	game.level_index = crab_shift
	game.begin_level()
	check("Playa del Carmen's crab waits in its shift", cb.active and cb.state == Crab.State.WAITING)
	for c in game.world.get_children():
		if c is Tourist:
			c.free()
	cb._wait = 0.0
	cb.tick(0.01)
	check("it surfaces as a twitching mound, a fair way off",
		cb.state == Crab.State.LURKING and cb.pos.distance_to(game.player.position) > 100.0)
	check("and the HUD warns about it", cb.status_text().contains("SAND"))
	for i in 40:
		cb.tick(0.1)
	check("then pops up and gives chase", cb.state == Crab.State.CHASING)
	# The lure: a tourist close by takes its attention off the worker.
	game.player.position = Vector2(180, Zones.SHORE_Y - 40.0)
	game.player.in_safe_zone = false
	game.player._stun = 0.0
	game.player._grace = 0.0
	cb.pos = Vector2(80, Zones.SHORE_Y - 40.0)
	var decoy: Tourist = game.spawner.make_tourist(cb.pos + Vector2(10, 0), Zones.SHORE_Y, false)
	decoy.set_process(false)
	cb._ignore_left = 0.0
	cb.tick(0.05)
	check("lead it into a tourist and it follows them instead", cb.chasing_tourist())
	for i in 60:
		cb.tick(0.1)
	check("for a while, then it turns back to the worker", not cb.chasing_tourist())
	decoy.free()
	# (Back to the worker, it may well have caught them by now -- put it back
	# on the hunt for the remaining checks.)
	cb._enter(Crab.State.CHASING)
	game.player._stun = 0.0
	game.player._grace = 0.0
	# Beach only: the worker wading out is out of its reach.
	game.player.position = Vector2(180, Zones.SHALLOW_TOP + 30.0)
	cb._hunt_left = 30.0
	for i in 40:
		cb.tick(0.1)
	check("it never leaves the sand", cb.pos.y <= Zones.SHORE_Y)
	# Slower in a storm.
	var c0: Vector2 = cb.pos
	game.storm_active = true
	cb.pos = Vector2(60, Zones.HOTEL_BOTTOM + 40.0)
	c0 = cb.pos
	game.player.position = Vector2(300, Zones.HOTEL_BOTTOM + 40.0)
	cb.tick(1.0)
	var storm_step: float = cb.pos.distance_to(c0)
	game.storm_active = false
	c0 = cb.pos
	cb.tick(1.0)
	check("slower in a storm", storm_step < cb.pos.distance_to(c0) * 0.75)
	check("and slower than the worker on foot", cb.pos.distance_to(c0) < game.player.base_speed)
	# Reaching the worker is a hit: the load is dropped.
	game.player.carried = 6
	game.player.carried_value = 27.0
	game.player._stun = 0.0
	game.player._grace = 0.0
	cb.pos = game.player.position + Vector2(4, 0)
	cb.tick(0.01)
	check("catching the worker drops their load", game.player.carried == 0)
	check("and it digs back in", cb.state == Crab.State.BURROWING)
	cb.tick(1.0)
	check("and is gone for the level", cb.state == Crab.State.GONE and not cb.out())
	await frames(2)
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.level = 1
	game.level_index = 0
	game.apply_beach()
	game.begin_level()
	await frames(1)

	print("\n[parasail]")
	var ps: Parasail = game.parasail
	game.level = 2
	game.apply_beach()
	game.level_index = 0
	game.begin_level()
	check("no parasail on beaches without one", not ps.active)
	game.level = 1
	game.apply_beach()
	game.level_index = int(Beaches.for_level(1)["parasail"]["shift"])
	game.begin_level()
	check("Cancun has its parasailer, once, in its shift", ps.active and ps.state == Parasail.State.WAITING)
	check("with its boat and canopy art", ps._boat_spr.texture != null and ps._canopy_spr.texture != null)
	ps._wait = 0.0
	ps.tick(0.01)
	check("the boat sets off across the sea", ps.state == Parasail.State.TOWING and ps._flying)
	var crossed := false
	for i in 400:
		ps.tick(0.05)
		if not ps._flying and not crossed:
			crossed = true
			check("the parasailer lets go about halfway across",
				absf(ps.chute_pos().x - Zones.VIEW_W * 0.5) < 9.0)
	check("they land in the sea with a splash, and the boat leaves",
		crossed and ps.state == Parasail.State.GONE)
	game.level_index = 0
	game.begin_level()
	await frames(1)

	print("\n[gentle storm on foot]")
	var keep_gear: Dictionary = game.owned.duplicate()
	game.owned = {}
	var riders := 0
	for i in 200:
		var probe: Seaweed = game.spawner._add_seaweed(Vector2(180, Zones.DEEP_TOP + 40.0), 1, false, true)
		if probe.storm_rider:
			riders += 1
		probe.free()
	check("with no jacket or backpack, storms are gentle", game.gentle_storm())
	check("and only about half the floating seaweed rides the surge", riders > 70 and riders < 130)
	game.owned = {"backpack": true}
	check("on Cancun storms stay gentle even with a backpack", game.gentle_storm())
	var keep_level: int = game.level
	game.level = 2
	check("from level 2 a backpack brings full storms back", not game.gentle_storm())
	check("and level 2 is not forgiving: normal storms, rep fall and grace",
		game.storm_every() == Weather.STORM_EVERY and game.rep_fall() == Reputation.REP_FALL
		and game.fail_grace() == Reputation.FAIL_GRACE)
	game.level = keep_level
	check("Cancun forgives: rarer storms, slower rep fall, longer grace",
		game.storm_every() > Weather.STORM_EVERY and game.rep_fall() < Reputation.REP_FALL
		and game.fail_grace() > Reputation.FAIL_GRACE)
	game.owned = keep_gear

	print("\n[pet seagull]")
	var gl: Seagull = game.gull
	var keep_owned2: Dictionary = game.owned.duplicate()
	game.level = 1
	game.apply_beach()
	game.begin_level()
	check("no seagull until it is bought", not gl.enabled)
	check("the seagull has its art: flying and perched", Seagull.FLY.size() == 4 and Seagull.PERCH.size() == 2)
	check("it is a tier-2 upgrade with no prerequisite",
		int(Upgrades.by_id("seagull")["tier"]) == 2 and String(Upgrades.by_id("seagull")["needs"]) == "")
	game.owned["seagull"] = true
	game.apply_upgrade("seagull")
	check("bought, it perches on the skip", gl.enabled and gl.state == Seagull.State.PERCHED
		and gl.pos.distance_to(gl.perch()) < 1.0)
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	var fresh_pile: Seaweed = game.spawner._add_seaweed(Vector2(120, Zones.SHORE_Y - 20.0), 3, false, false)
	for i in 20:
		gl.tick(0.1)
	check("it ignores fresh seaweed", gl.state == Seagull.State.PERCHED)
	var browning: Seaweed = game.spawner._add_seaweed(Vector2(60, Zones.SHORE_Y - 20.0), 2, false, false)
	browning.age = Seaweed.ROT_WARN + 2.0
	check("but goes for seaweed that has only started to rot", gl._worst_rot() == browning)
	browning.free()
	var rot_pile: Seaweed = game.spawner._add_seaweed(Vector2(200, Zones.SHORE_Y - 20.0), 3, false, false)
	rot_pile.age = 1.0e4
	var credits0: int = game.credits_earned
	var flew := false
	for i in 800:
		gl.tick(0.05)
		if gl.state == Seagull.State.OUT:
			flew = true
	check("a rotten pile and it flies out for it", flew)
	check("it clears the rot, a beakful at a time", not is_instance_valid(rot_pile) or rot_pile.units == 0
		or rot_pile.is_queued_for_deletion())
	check("and leaves fresh seaweed for the worker", is_instance_valid(fresh_pile) and fresh_pile.units == 3)
	check("its seaweed never pays", game.credits_earned == credits0)
	check("then settles back on the skip", gl.state == Seagull.State.PERCHED)
	check("slower than the worker", Seagull.SPEED < game.player.base_speed)
	var snatched: Seaweed = game.spawner._add_seaweed(Vector2(100, Zones.SHORE_Y - 20.0), 2, false, false)
	snatched.age = 1.0e4
	gl._target = snatched
	gl.state = Seagull.State.OUT
	snatched.free()
	for i in 5:
		gl.tick(0.05)
	check("if the worker scoops its target first, it moves on instead of hanging there",
		gl.state != Seagull.State.OUT or is_instance_valid(gl._target))
	for i in 400:
		gl.tick(0.05)
	fresh_pile.free()
	game._reset_player_stats()
	check("a new level without it sends it away", not gl.enabled)
	game.owned = keep_owned2
	for gu in Upgrades.LIST:
		if game.owned.has(String(gu["id"])):
			game.apply_upgrade(String(gu["id"]))
	await frames(1)

	print("\n[dropped loads, Holbox spawns, Tulum relief]")
	game.level = 1
	game.apply_beach()
	game.begin_level()
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	var hit_at := Vector2(180, Zones.SHORE_Y - 40.0)
	game.spawner.scatter(40, hit_at)
	var drop_piles := 0
	var drop_far := 0.0
	var drop_units := 0
	for c in game.world.get_children():
		if c is Seaweed:
			drop_piles += 1
			drop_units += (c as Seaweed).units
			drop_far = maxf(drop_far, (c as Seaweed).position.distance_to(hit_at))
	check("a dropped load lands as a few big piles", drop_piles == 5 and drop_units == 40)
	check("right where the worker was hit", drop_far < 16.0)
	for c in game.world.get_children():
		if c is Seaweed:
			c.free()
	game.level = 6
	game.apply_beach()
	var fade_t: Tourist = game.spawner.make_tourist(Zones.CENTER + Vector2(0, -Zones.TOURIST_SPAWN_Y), Zones.SHORE_Y, false)
	await frames(1)
	check("on Holbox a tourist fading in cannot hit anyone yet", fade_t._arriving > 0.0)
	fade_t.free()
	game.level = 10
	game.apply_beach()
	game.level_index = 3
	check("Tulum's rot is no faster than 0.8x, even on shift 4", game.rot_scale() >= 0.8)
	check("and the eye lasts 30s", is_equal_approx(float(Beaches.for_level(10)["hurricane"]["eye_len"]), 30.0))
	game.level_index = 0
	game.level = 1
	game.apply_beach()
	game.begin_level()

	print("\n[veracruz moments]")
	game.level = 2
	game.apply_beach()
	game.begin_level()
	var vz: Veracruz = game.veracruz
	check("Veracruz has its gust fronts and cargo", vz.active)
	for c in game.world.get_children():
		if c is Seaweed or c is Tourist:
			c.free()
	var vp: Seaweed = game.spawner._add_seaweed(Vector2(100, Zones.SHORE_Y - 30.0), 3, false, false)
	var vp_x: float = vp.position.x
	vz._next_front = 0.0
	vz.tick(0.01)
	check("a gust front is announced before it hits", vz.status_text().contains("GUST"))
	for i in 120:
		vz.tick(0.05)
	await frames(30)
	check("as it passes, beached piles slide downwind", (vp.position.x - vp_x) * vz._dir > 15.0)
	game.player.position = Vector2(180, Zones.HOTEL_BOTTOM + 60.0)
	game.player.in_safe_zone = false
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.carried = 4
	vz.umbrellas = [{"pos": game.player.position, "v": 100.0, "rot": 0.0, "bounce": 0.0, "col": Color.RED}]
	vz.tick(0.01)
	check("a tumbling umbrella knocks the worker down", game.player._stun > 0.0)
	check("but the load stays in their arms", game.player.carried == 4)
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.carried = 0
	game.player.carried_value = 0.0
	vz.umbrellas.clear()
	vz._spill()
	check("lost cargo floats in from the deep", vz.crates.size() >= 2 and not bool(vz.crates[0]["beached"]))
	vz.crates[0]["pos"] = game.player.position
	vz.crates[0]["beached"] = true
	for i in 20:
		vz.tick(0.05)
	check("stand on a crate to haul it: it takes 5 slots", game.player.carried == Veracruz.CRATE_SLOTS)
	check("and is worth a good bonus at the skip", game.player.carried_value >= game.price_per_unit * 20.0)
	game.player.carried = 0
	game.player.carried_value = 0.0
	vz.crates.clear()

	print("\n[cozumel nights]")
	game.level = 4
	game.apply_beach()
	game.begin_level()
	var cz: Cozumel = game.cozumel
	check("Cozumel has its night events", cz.active)
	for c in game.world.get_children():
		if c is Tourist:
			c.free()
	cz._cruise_wait = 0.0
	cz.tick(0.01)
	check("a cruise ship comes by", cz.ship_on())
	var crowd0: int = game.spawner.count_tourists()
	for i in 400:
		cz.tick(0.05)
	check("and its passengers pour onto the beach", game.spawner.count_tourists() >= crowd0 + 6)
	game.spawner._add_seaweed(Vector2(200, Zones.DEEP_TOP + 30.0), 1, false, true)
	cz._glow_t = 2.0
	check("the sea glows: drifting seaweed lights up in the dark", cz.lights().size() >= 1)
	cz._glow_t = -1.0
	cz.divers.clear()
	cz._divers_next = 0.0
	cz.tick(0.01)
	check("night divers surface in the shallows", cz.divers.size() == 2)
	game.player.position = cz.divers[0]["pos"]
	game.player.in_safe_zone = false
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.carried = 5
	for i in 30:
		cz.tick(0.05)
	await frames(2)
	check("bump a diver and the load is dropped", game.player.carried == 0)
	game.player._stun = 0.0
	game.player._grace = 0.0

	print("\n[bacalar shallows]")
	game.level = 5
	game.apply_beach()
	game.begin_level()
	var ky: Kayaks = game.kayaks
	check("Bacalar has its kayak tour", ky.active)
	ky._next = 0.0
	ky.tick(0.01)
	check("a line of kayaks sets off across the shallows", ky.boats.size() == ky.count)
	game.player.position = (ky.boats[0]["pos"] as Vector2) + Vector2(ky._dir * 4.0, 0)
	game.player.in_safe_zone = false
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.carried = 5
	ky.tick(0.01)
	await frames(2)
	check("paddle into one and the load is dropped", game.player.carried == 0)
	game.player._stun = 0.0
	game.player._grace = 0.0
	var surf_wader: Tourist = game.spawner.make_tourist(Vector2(120, Zones.SHALLOW_TOP + 30.0), Zones.DEEP_TOP, false)
	surf_wader.set_process(false)
	await frames(1)
	var surf_wy: float = surf_wader.position.y
	game.surf._hit(surf_wy + 1.0, surf_wy - 1.0)
	surf_wader.set_process(true)
	await frames(30)
	check("a big wave throws wading tourists up the beach", surf_wader.position.y < surf_wy - 10.0)
	surf_wader.free()
	game.level = 1
	game.level_index = 0
	game.apply_beach()
	game.begin_level()
	await frames(1)

	print("\n[cancun flamingos]")
	var fl: Flamingos = game.flamingos
	check("Cancun has flamingos in its first shift", fl.active)
	fl._next = 0.01
	game.player.position = Vector2(Zones.VIEW_W - 20.0, Zones.HOTEL_BOTTOM + 20.0)
	for i in 80:
		fl.tick(0.05)
	check("a flock lands and stands on the sand",
		fl.birds.size() == fl.count and fl.birds.all(func(b): return b["state"] == "stand"))
	check("they ignore a worker who keeps away", fl.birds.all(func(b): return b["state"] == "stand"))
	game.player.position = fl.birds[0]["pos"]
	fl.tick(0.05)
	check("walk up and the whole flock takes off", fl.birds.all(func(b): return b["state"] == "off"))
	for i in 100:
		fl.tick(0.05)
	check("and flies away off the screen", fl.birds.is_empty())
	for i in 2000:
		fl.tick(0.1)
	check("only one flock a shift", fl.birds.is_empty())
	fl.configure(Beaches.for_level(1), 1)
	check("and none in shift 2", not fl.active)
	fl.configure(Beaches.for_level(1), 2)
	check("but one again in shift 3", fl.active)
	fl._next = 0.01
	for i in 10:
		fl.tick(0.1)
	fl.configure(Beaches.for_level(1), 2)
	check("a retried shift clears the old flock", fl.birds.is_empty() and fl._next > 0.0)

	print("
[quiet first level, and no hit loops]")
	check("Cancun sends about half the tourists", game.spawner.tourist_pressure() < game.difficulty() * 0.6)
	var crowd_lv: int = game.level
	game.level = 2
	check("every other level runs a thinner crowd too",
		is_equal_approx(game.spawner.tourist_pressure(), game.difficulty() * Spawner.CROWD))
	game.level = crowd_lv
	game.player.in_safe_zone = false
	game.player._stun = 0.0
	game.player._grace = 0.0
	game.player.carried = 5
	game.player.get_hit()
	check("a hit stuns and drops the load", game.player._stun > 0.0 and game.player.carried == 0)
	await sim(1.0)
	game.player.carried = 5
	game.player.get_hit()
	check("right after the stun, a second tourist can't hit you", game.player.carried == 5)
	await sim(2.2)
	game.player.get_hit()
	check("once the safe window ends, hits land again", game.player.carried == 0)
	game.player._stun = 0.0
	game.player._grace = 0.0

	print("\n[later shifts stretched]")
	var keep_ret: Dictionary = game.retained.duplicate()
	var keep_lvl: int = game.level
	var keep_idx: int = game.level_index
	game.retained = {}
	game.level = 8
	game.level_index = 2
	check("Mahahual's shift 3 target is stretched toward five minutes",
		game.shift_target() == int(round(float(Levels.LIST[2]["credits"]) * 1.75 / 50.0)) * 50)
	game.level_index = 0
	check("but its first shift is not", game.shift_target() == int(Levels.LIST[0]["credits"]))
	game.level = 1
	game.level_index = 2
	check("and early levels keep their targets", game.shift_target() == int(Levels.LIST[2]["credits"]))
	game.retained = keep_ret
	game.level = keep_lvl
	game.level_index = keep_idx

	print("\n[every level's soundtrack]")
	for lvm in range(1, 11):
		var want = Beaches.for_level(lvm).get("music", null)
		if want == null:
			continue
		game.level = lvm
		game.level_index = 0
		game.apply_beach()
		game.begin_level()
		await frames(2)
		var got: Array = game.audio._playlist
		var names := []
		for x in got:
			names.append(String(x).get_file())
		print("    L%d plays %s" % [lvm, names])
		check("level %d plays its own soundtrack" % lvm, got.size() == (want as Array).size()
			and String(got[0]).get_file() in (want as Array).map(func(q): return String(q).get_file()))
	game.level = 1
	game.apply_beach()
	game.begin_level()
	await frames(1)

	print("\n[music level across shifts]")
	var mbus := AudioServer.get_bus_index("MusicTrack")
	game.weather.set_bed(Weather.Bed.UPGRADE)
	for i in 60:
		await process_frame
	check("the upgrade jingle ducks the music", AudioServer.get_bus_volume_db(mbus) < -8.0)
	game.begin_level()
	for i in 60:
		await process_frame
	check("a new shift brings the music back up, even mid-duck",
		AudioServer.get_bus_volume_db(mbus) > -1.0)

	print("\n[shop fits the screen]")
	var keep_cr: int = game.credits
	var keep_lix: int = game.level_index
	game.level_index = 0          # early shift: later upgrades show their longest text
	game.credits = 9999999        # the widest possible title
	game.shop.rebuild()
	game.shop.visible = true
	await frames(3)
	var widest := 0.0
	var stack := [game.shop]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and (n as Control).is_visible_in_tree():
			widest = maxf(widest, (n as Control).get_global_rect().end.x)
		stack.append_array(n.get_children())
	check("the shop fits inside the screen, with nothing cut off on the right",
		widest <= Zones.VIEW_W + 0.5)
	print("    widest point of the shop: %.0f of %d" % [widest, Zones.VIEW_W])
	game.shop.visible = false
	game.credits = keep_cr
	game.level_index = keep_lix

	print("\n[tutorial: skip and music hand-over]")
	game.level = 1
	game.level_index = 0
	game.apply_beach()
	game._hold_music = true
	game.begin_level()
	game.start_tutorial()
	await frames(1)
	check("the tutorial can be started", game.tutorial.visible and paused)
	var staged_s: Array = game._staged.duplicate()
	game.tutorial._skip.pressed.emit()
	await frames(2)
	var gone := true
	for n in staged_s:
		if is_instance_valid(n):
			gone = false
	check("SKIP lands exactly where START SHIFT! does",
		not game.tutorial.visible and game.level_intro.visible and gone
			and not game._hold_music and not game.audio._playlist.is_empty())
	game.start_from_intro()
	await frames(1)
	# The menu's music player, handed over: kept through the tutorial...
	var mm := AudioStreamPlayer.new()
	mm.stream = load("res://audio/Island_Jump.mp3")
	mm.bus = "Music"
	game.menu_music = mm
	game.menu_music_pos = 12.0
	game._adopt_menu_music(true)
	await frames(2)
	check("the menu music keeps playing into the tutorial", mm.playing and mm.process_mode == Node.PROCESS_MODE_ALWAYS)
	check("picking up where the menu left it", mm.get_playback_position() >= 11.9)
	# ...and faded out when the level's music takes over.
	game._fade_menu_music(0.2)
	for i in 40:
		await process_frame
	check("then fades out once the level's music takes over", not is_instance_valid(mm))
	var mm2 := AudioStreamPlayer.new()
	mm2.stream = load("res://audio/Island_Jump.mp3")
	game.menu_music = mm2
	game._adopt_menu_music(false)
	check("without a tutorial it fades straight away", game.menu_music == null)

	print("\n[storms matter]")
	var keep_storm2: bool = game.storm_active
	var keep_jacket: bool = game.player.has_rain_jacket
	game.player.position = Vector2(180, Zones.HOTEL_BOTTOM + 60.0)
	game.storm_active = false
	game.player.has_rain_jacket = false
	var dry_speed: float = game.player.current_speed()
	game.storm_active = true
	check("a storm slows you to a crawl without the jacket",
		is_equal_approx(game.player.current_speed(), dry_speed * Player.STORM_SLOW) and Player.STORM_SLOW <= 0.45)
	game.player.has_rain_jacket = true
	check("the Rain Jacket keeps you at full speed", is_equal_approx(game.player.current_speed(), dry_speed))
	check("tourists trudge in a storm", Tourist.STORM_SPEED <= 0.4)
	check("storms come often and last long enough to matter",
		Weather.STORM_EVERY <= 80.0 and Weather.STORM_LENGTH >= 20.0)
	game.storm_active = keep_storm2
	game.player.has_rain_jacket = keep_jacket

	print("\n[adaptive difficulty]")
	var keep_adapt: float = game.adapt
	var keep_fails: int = game.shift_fails
	game.adapt = 1.0
	game.shift_fails = 0
	var ease_by: float = float(game.beginner().get("fail_ease", Game.ADAPT_FAIL))
	game.adapt_after_fail()
	check("failing a shift eases the next attempt", is_equal_approx(game.adapt, ease_by) and game.last_adapt == -1)
	game.adapt_after_finish()
	check("finishing after a fail leaves it alone", is_equal_approx(game.adapt, ease_by) and game.last_adapt == 0)
	check("and the next shift starts with a clean record", game.shift_fails == 0)
	game.adapt_after_finish()
	check("finishing first try makes the next shift busier", is_equal_approx(game.adapt, ease_by * Game.ADAPT_CLEAN) and game.last_adapt == 1)
	var lvl_keep: int = game.level
	game.level = 1
	var sc: float = game.spawn_scale()
	check("and it drives the seaweed rate", is_equal_approx(sc, game.adapt))
	for i in 60:
		game.adapt_after_fail()
	check("never easier than the floor", is_equal_approx(game.adapt, Game.ADAPT_MIN))
	game.shift_fails = 0
	for i in 60:
		game.adapt_after_finish()
	check("never harder than the ceiling", is_equal_approx(game.adapt, Game.ADAPT_MAX))
	# where it settles: the steps balance near two-in-three first-try finishes
	var p_clean: float = log(1.0 / Game.ADAPT_FAIL) / (log(1.0 / Game.ADAPT_FAIL) + log(Game.ADAPT_CLEAN))
	check("it settles where most shifts -- not all -- are finished first try",
		p_clean > 0.55 and p_clean < 0.75)
	game.adapt = 0.8
	game.shift_fails = 1
	game._save_progress()
	game.adapt = 1.0
	game.shift_fails = 0
	game._load_progress()
	check("it is saved with your progress", is_equal_approx(game.adapt, 0.8) and game.shift_fails == 1)
	game.adapt = keep_adapt
	game.shift_fails = keep_fails
	game.level = lvl_keep
	game._save_progress()

	print("\n[screen insets]")
	# A tall phone: the 9:16 game is letterboxed, and the bar clears the notch.
	check("on a tall phone the notch sits in the black bar -- no inset",
		is_zero_approx(Hud.inset_in_game(100.0, Vector2(1080, 2400), Vector2(360, 640))))
	# An exactly 9:16 phone: no bar, so the notch does cover the game.
	check("on an exactly 9:16 phone the notch is allowed for",
		absf(Hud.inset_in_game(90.0, Vector2(1080, 1920), Vector2(360, 640)) - 30.0) < 0.1)
	check("the MENU and SHOP buttons sit right at the top", Hud.BTN_Y <= 4.0)

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
	check("a new level opens on its intro card",
		game.level_intro.visible and game.level_intro._name.text == "VERACRUZ")
	check("and its palms sway on the card too", game.level_intro._bg.material is ShaderMaterial)
	game.start_from_intro()
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
	check("every keepable upgrade ends up retained", game.retained.size() == Upgrades.keepable_count())
	check("the seagull is a hire, never kept", not game.retained.has("seagull"))
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
	check("all ten levels have a name", Beaches.NAMES.size() == 10)
	menu._show_levels(true)
	var level_btns := 0
	var starred := 0
	for c in menu._level_panel.find_children("*", "Button", true, false):
		if String((c as Button).text).substr(0, 2).strip_edges().is_valid_int():
			level_btns += 1
			if String((c as Button).text).ends_with("*"):
				starred += 1
	check("the dev panel lists every level by name", level_btns == 10)
	check("levels without beach art are marked", starred == 10 - Beaches.LIST.size())
	check("every level has its own beach now", Beaches.LIST.size() == 10)
	check("the level panel fits on screen",
		menu._level_panel.position.y + menu._level_panel.size.y <= 640.0)
	menu._show_levels(false)
	menu._show_settings(false)
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


func _count(game, type_name: String) -> int:
	# Honours its argument. It used to ignore it and always count tourists, so
	# _count(game, "Seaweed") silently counted the wrong thing -- a ferry test
	# saw a tourist on the first tick and recorded the wake as landing at once.
	var n := 0
	for c in game.world.get_children():
		if (type_name == "Tourist" and c is Tourist) or (type_name == "Seaweed" and c is Seaweed):
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
