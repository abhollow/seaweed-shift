class_name GameAudio
extends Node

# A small pool of AudioStreamPlayers cycled round-robin. Pooling matters here
# because pickups can fire several times a second once the rake is upgraded --
# a single player would cut itself off mid-blip.
#
# Filenames are the contract. Drop a real recording in over any of these and
# nothing in the game code changes.

const POOL_SIZE := 14

const SOUNDS := {
	"pickup": "res://audio/pickup.mp3",
	"dump": "res://audio/dump.mp3",
	"full": "res://audio/full.mp3",
	"purchase": "res://audio/purchase.mp3",
	"package": "res://audio/package.mp3",
	"hit": "res://audio/hit.wav",
	"gust": "res://audio/gust.wav",
	"horn": "res://audio/horn.wav",
	"rot": "res://audio/rot.mp3",
	"warn": "res://audio/warn.mp3",
	"complete": "res://audio/complete.mp3",

	# Weather one-shots, fired at random intervals by the game.
	"thunder_1": "res://audio/thunder_1.ogg",
	"thunder_2": "res://audio/thunder_2.ogg",
	"thunder_3": "res://audio/thunder_3.ogg",
	"yell_1": "res://audio/yell_1.ogg",
	"yell_2": "res://audio/yell_2.ogg",
	"yell_3": "res://audio/yell_3.ogg",
	"yell_4": "res://audio/yell_4.ogg",
}

# Per-key voice caps. `pickup` is a two-note motif that rings for about a
# second, and at the Wide Rake's 0.35s gather rate it would otherwise stack six
# deep into mush. Capping at 3 keeps the overlap musical: a new pickup steals
# the oldest pickup voice rather than adding to the pile.
const MAX_VOICES := {
	"pickup": 3,
}

const MUSIC_FADE_IN := 2.0     # first track of a shift, up from silence
const CROSSFADE := 5.0         # overlap between consecutive tracks
const MUSIC_SILENCE_DB := -40.0

var sfx_enabled := true
var music_base_db := -8.0
var music_path := ""           # what's on the music player right now

var _playlist: Array[String] = []
var _play_idx := 0
var _crossfading := false
# Set while the shift-complete sting plays. The Audio node keeps processing
# through a paused tree (so fades survive panels), which means that without this
# a song ending mid-sting would advance the playlist and start the next track.
var _music_paused := false

# Two players so the outgoing track can still be sounding while the incoming
# one comes up. With a single player there is no way to overlap, which is what
# left dead air between songs.
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _xfade_tw: Tween

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _keys: Array[String] = []
var _started: Array[float] = []
var _next := 0
var _music: AudioStreamPlayer
var _event: AudioStreamPlayer
var _event_base_db := -6.0
var _event_tw: Tween
var _music_tw: Tween
var _amb: AudioStreamPlayer
var _amb_base_db := -8.0
var _amb_tw: Tween
var _amb_path := ""


func _music_tween() -> Tween:
	# Music tweens must survive a paused tree. The shift-complete panel pauses
	# the game, and a crossfade frozen mid-ramp leaves the incoming track stuck
	# at partial volume for as long as the panel is up -- which is exactly the
	# "first song of the shift is barely audible" bug.
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	return tw


func _ready() -> void:
	# Audio keeps running while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Preloaded up front: loading a stream on the frame it first plays causes a
	# hitch, and the frames these fire on are the worst ones to hitch.
	for key in SOUNDS:
		var stream = load(SOUNDS[key])
		if stream != null:
			_streams[key] = stream

	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		# Keeps firing while the tree is paused, so shop and shift-complete
		# sounds aren't silently swallowed.
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
		_keys.append("")
		_started.append(0.0)

	# Weather beds (storm / happy hour) get their own player so they can run
	# under or over the main track without fighting it for a voice.
	_event = AudioStreamPlayer.new()
	_event.bus = "Music"
	_event.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_event)

	# Environmental layer: rain, crowd. Its own bus so it can sit under both the
	# music and the SFX without either fighting it.
	_amb = AudioStreamPlayer.new()
	_amb.bus = "Ambience"
	_amb.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_amb)

	# On their own sub-bus that feeds Music. Ducking moves the BUS while track
	# fades move the PLAYERS, so a storm rolling in mid-crossfade doesn't fight
	# the fade for control of the same volume_db.
	for i in 2:
		var mp := AudioStreamPlayer.new()
		mp.bus = "MusicTrack"
		mp.process_mode = Node.PROCESS_MODE_ALWAYS
		mp.volume_db = MUSIC_SILENCE_DB
		mp.finished.connect(_on_track_finished.bind(i))
		add_child(mp)
		_players.append(mp)
	_music = _players[0]

	# So music and ducking tweens keep running while the shop or the
	# shift-complete panel has the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS


# Per-cue level trim, applied on top of whatever a call site asks for.
#
# The cues came from different sources at wildly different levels: measured RMS
# ran from -35 dBFS (pickup) to -18 (purchase, warn). Normalising the FILES
# would be wrong -- a quiet pickup is deliberate, it fires constantly -- so the
# mix is balanced here instead, where the intent is visible and tunable.
const SFX_TRIM := {
	"purchase": -7.0,
	"package": -4.0,
	"rot": -5.0,
	"warn": -5.0,
	"complete": -3.0,
}


func play(key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not sfx_enabled or not _streams.has(key):
		return

	var idx := _claim_voice(key)
	var p := _pool[idx]
	_keys[idx] = key
	_started[idx] = Time.get_ticks_msec() / 1000.0

	p.stream = _streams[key]
	p.pitch_scale = clampf(pitch, 0.4, 2.5)
	p.volume_db = volume_db + float(SFX_TRIM.get(key, 0.0))
	p.play()


func _claim_voice(key: String) -> int:
	var limit: int = MAX_VOICES.get(key, 0)
	if limit > 0:
		var live: Array[int] = []
		for i in _pool.size():
			if _keys[i] == key and _pool[i].playing:
				live.append(i)
		if live.size() >= limit:
			var oldest: int = live[0]
			for i in live:
				if _started[i] < _started[oldest]:
					oldest = i
			return oldest

	var idx := _next
	_next = (_next + 1) % _pool.size()
	return idx


func _kill(tw: Tween) -> void:
	if tw != null and tw.is_valid():
		tw.kill()


func play_event(path: String, volume_db: float = -5.0, fade: float = 1.0) -> void:
	# A looping bed for the duration of a weather event.
	if not ResourceLoader.exists(path):
		push_warning("No event track at %s" % path)
		return
	var stream = load(path)
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true

	# Kill any in-flight fade first, or a lingering stop_event tween will drag
	# the new bed's volume straight back down.
	_kill(_event_tw)

	_event_base_db = volume_db
	_event.stream = stream
	_event.volume_db = volume_db - 20.0
	_event.play()
	_event.stream_paused = _music_paused

	_event_tw = _music_tween()
	_event_tw.tween_property(_event, "volume_db", volume_db, fade)


func stop_event(fade: float = 1.4) -> void:
	if not _event.playing:
		return
	_kill(_event_tw)
	_event_tw = _music_tween()
	_event_tw.tween_property(_event, "volume_db", _event_base_db - 30.0, fade)
	_event_tw.tween_callback(_event.stop)


func play_ambience(path: String, volume_db: float = -8.0, fade: float = 1.2) -> void:
	if path == _amb_path and _amb.playing:
		return
	if not ResourceLoader.exists(path):
		push_warning("No ambience at %s" % path)
		return
	var stream = load(path)
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true

	_kill(_amb_tw)
	_amb_path = path
	_amb_base_db = volume_db
	_amb.stream = stream
	_amb.volume_db = volume_db - 18.0
	_amb.play()

	_amb_tw = _music_tween()
	_amb_tw.tween_property(_amb, "volume_db", volume_db, fade)


func stop_ambience(fade: float = 1.6) -> void:
	if not _amb.playing:
		return
	_kill(_amb_tw)
	_amb_path = ""
	_amb_tw = _music_tween()
	_amb_tw.tween_property(_amb, "volume_db", _amb_base_db - 30.0, fade)
	_amb_tw.tween_callback(_amb.stop)


func play_music(path: String, volume_db: float = -8.0) -> void:
	play_playlist([path], volume_db)


func play_playlist(paths, volume_db: float = -8.0) -> void:
	if paths == null:
		return
	var list: Array[String] = []
	if paths is String:
		list.append(String(paths))
	else:
		for p in paths:
			if ResourceLoader.exists(String(p)):
				list.append(String(p))
	if list.is_empty():
		push_warning("Playlist had no loadable tracks")
		return

	# Consecutive shifts sharing a playlist shouldn't yank the music back to the
	# top of the first track.
	if list == _playlist and current_player().playing:
		# ...but the NEW base has to reach the player that is already singing.
		# Setting music_base_db alone left the live track at the previous
		# shift's level until the next song began, which is why shift 3 opened
		# barely audible and then corrected itself one track later.
		# Restore the level whether or not the base changed: a transition can
		# land mid-fade and leave the live track quiet.
		music_base_db = volume_db
		var quiet: bool = current_player().volume_db < music_base_db - 0.5
		if quiet and not _crossfading:
			var lvl_tw := _music_tween()
			lvl_tw.tween_property(current_player(), "volume_db", music_base_db, 1.2)
		return

	# Fade the outgoing track down. _begin_track deliberately leaves this to its
	# caller (a crossfade handles it separately), and play_playlist never did --
	# so changing shift started the new track over the top of the old one.
	var outgoing := current_player()
	if outgoing.playing:
		if _xfade_tw != null and _xfade_tw.is_valid():
			_xfade_tw.kill()
		var out_tw := _music_tween()
		out_tw.tween_property(outgoing, "volume_db", music_base_db + MUSIC_SILENCE_DB, 0.6)
		out_tw.tween_callback(outgoing.stop)

	_playlist = list
	# The FIRST entry always opens the shift -- that track sets the tone for the
	# first minute of play, so it shouldn't be down to a coin flip. Only the
	# remainder is shuffled.
	_shuffle_tail()
	music_base_db = volume_db
	_play_idx = 0
	_begin_track(0, MUSIC_FADE_IN)


func current_player() -> AudioStreamPlayer:
	return _players[_active]


func _shuffle_tail() -> void:
	# Leaves index 0 alone and shuffles everything after it.
	if _playlist.size() < 3:
		return
	var head := _playlist[0]
	var rest := _playlist.slice(1)
	rest.shuffle()
	_playlist = [head] as Array[String]
	_playlist.append_array(rest)


func _shuffle() -> void:
	# Full reshuffle, used once the playlist has been played through. By then the
	# opener has done its job, so any track may come up first. The last track of
	# the old order is moved off the front where possible, so a song never plays
	# twice back to back across the wrap.
	if _playlist.size() < 2:
		return
	var last := _playlist[_playlist.size() - 1]
	_playlist.shuffle()
	if _playlist.size() > 2 and _playlist[0] == last:
		var swap_to := 1 + (randi() % (_playlist.size() - 1))
		var tmp := _playlist[0]
		_playlist[0] = _playlist[swap_to]
		_playlist[swap_to] = tmp


func _begin_track(idx: int, fade: float) -> void:
	# Starts `idx` on the INACTIVE player and fades it up, leaving the outgoing
	# player to be faded down separately by whoever called us.
	if _playlist.is_empty():
		return
	var path := _playlist[idx]
	var stream = load(path)
	if stream == null:
		return
	# Looping must be OFF or the track never ends and the playlist stalls on
	# whichever song happens to be first.
	if "loop" in stream:
		stream.loop = false

	var next_i := 1 - _active
	var p := _players[next_i]
	p.stream = stream
	p.volume_db = music_base_db + MUSIC_SILENCE_DB
	p.play()
	p.stream_paused = _music_paused

	_active = next_i
	_music = p
	_play_idx = idx
	music_path = path
	_crossfading = false

	var tw := _music_tween()
	tw.tween_property(p, "volume_db", music_base_db, fade)


func _advance() -> int:
	var idx := _play_idx + 1
	if idx >= _playlist.size():
		idx = 0
		_shuffle()
	return idx


func _on_track_finished(which: int) -> void:
	if _music_paused:
		return
	# Normally the crossfade has already moved on and this is just the outgoing
	# player going quiet. It only matters if the ACTIVE track ran out without a
	# crossfade -- a track shorter than the overlap window, say.
	if which != _active or _playlist.is_empty():
		return
	_begin_track(_advance(), 0.5)


func _process(_delta: float) -> void:
	if _music_paused:
		return
	# Start the next track before this one ends so the two overlap and there is
	# never silence between songs. Driven off playback position because
	# AudioStreamPlayer has no "about to finish" signal.
	if _crossfading or _playlist.size() < 2:
		return
	var cur := current_player()
	if not cur.playing or cur.stream == null:
		return
	var length := cur.stream.get_length()
	if length <= CROSSFADE + 1.0:
		return
	if cur.get_playback_position() < length - CROSSFADE:
		return

	_crossfading = true
	var outgoing := cur
	_begin_track(_advance(), 0.0)
	var incoming := current_player()
	_crossfading = true
	_equal_power_crossfade(outgoing, incoming, CROSSFADE)


func _equal_power_crossfade(out_p: AudioStreamPlayer, in_p: AudioStreamPlayer,
		dur: float) -> void:
	# Linear dB on both sides would dip in the middle -- at the halfway point
	# each track sits 20 dB down and the pair sounds like a hole. cos/sin keeps
	# the summed power constant instead, so the handover is level.
	if _xfade_tw != null and _xfade_tw.is_valid():
		_xfade_tw.kill()
	in_p.volume_db = music_base_db + MUSIC_SILENCE_DB

	var base := music_base_db
	_xfade_tw = _music_tween()
	_xfade_tw.tween_method(
		func(t: float):
			out_p.volume_db = base + linear_to_db(maxf(cos(t * PI * 0.5), 0.0001))
			in_p.volume_db = base + linear_to_db(maxf(sin(t * PI * 0.5), 0.0001)),
		0.0, 1.0, dur)
	_xfade_tw.tween_callback(func():
		out_p.stop()
		out_p.volume_db = base + MUSIC_SILENCE_DB
		_crossfading = false)


func pause_music(on: bool) -> void:
	# Silences ALL music for the shift-complete sting and resumes it after.
	#
	# Pausing rather than ducking, for two reasons. The event beds (storm,
	# Happy Hour) play on the Music bus directly, not the MusicTrack sub-bus,
	# so ducking MusicTrack left Happy Hour's music running at full volume. And
	# the Music bus itself is what the player's volume slider sets, so ducking
	# that would overwrite their setting. Pausing touches neither.
	_music_paused = on
	for p in _players:
		p.stream_paused = on
	if _event != null:
		_event.stream_paused = on


func duck_music(to_db: float, time: float = 0.9) -> void:
	# Relative attenuation applied to the MusicTrack bus, so it composes with
	# whatever the playlist's own fade is doing instead of overwriting it.
	_tween_bus("MusicTrack", to_db, time)


func restore_music_level(time: float = 1.4) -> void:
	_tween_bus("MusicTrack", 0.0, time)


func _tween_bus(bus_name: String, to_db: float, time: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	_kill(_music_tw)
	var from := AudioServer.get_bus_volume_db(idx)
	_music_tw = create_tween()
	_music_tw.tween_method(
		func(v: float): AudioServer.set_bus_volume_db(idx, v), from, to_db, time)


func restore_music(time: float = 1.4) -> void:
	restore_music_level(time)


func music_playing() -> bool:
	return current_player().playing


func stop_music() -> void:
	music_path = ""
	_playlist.clear()
	for p in _players:
		p.stop()


func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
