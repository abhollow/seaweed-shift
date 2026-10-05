class_name Flamingos
extends Node2D

# Cancun's flamingos: once in each of the level's chosen shifts, a small flock
# glides in and stands about on the dry sand above the waterline. Walk up to them and they scatter and fly
# off. Pure scenery for now -- they block nothing (Holbox's flock is the one
# that gets in the way; see holbox.gd).

var game
var active := false

var count := 3

const ART := preload("res://assets/sprites/flamingo.png")   # facing right
const FLY := [preload("res://assets/sprites/flamingo_fly_f0.png"), preload("res://assets/sprites/flamingo_fly_f1.png"),
	preload("res://assets/sprites/flamingo_fly_f2.png"), preload("res://assets/sprites/flamingo_fly_f3.png")]
# Flap, then coast, like the seagull: three wingbeats, then a glide on the
# wings-level frame.
const FLAP_FPS := 10.0
const FLAP_LEN := 1.2
const GLIDE_LEN := 0.9
const GLIDE_FRAME := 1
const ARRIVE_TIME := 3.0
const SPOOK := 48.0               # this close and the flock takes off
const FLEE_SPEED := 130.0

var _next := 0.0
var _anim := 0.0
var birds: Array = []             # {home, pos, from, t, state, flip, phase, vel, delay}


func configure(beach: Dictionary, shift_index: int) -> void:
	var f: Dictionary = beach.get("flamingos", {})
	active = not f.is_empty() and shift_index in f.get("shifts", [])
	visible = active
	count = int(f.get("count", 3))
	var at: Array = f.get("at", [30.0, 120.0])
	_next = randf_range(float(at[0]), float(at[1]))
	birds.clear()
	# Without this a retried shift kept showing the old flock, frozen, until
	# the next one landed.
	queue_redraw()


func tick(delta: float) -> void:
	if not active:
		return
	_anim += delta
	if birds.is_empty():
		if _next > 0.0:
			_next -= delta
			if _next <= 0.0:
				_land()      # once this shift; _next stays spent
		return
	var spooked := false
	for b in birds:
		if b["state"] == "stand" and (b["pos"] as Vector2).distance_to(game.player.position) < SPOOK:
			spooked = true
	if spooked:
		game.sfx("flamingo_flap", randf_range(0.9, 1.1), -4.0)
	for b in birds:
		match b["state"]:
			"in":
				b["t"] = minf(1.0, b["t"] + delta / ARRIVE_TIME)
				var k := ease(maxf(b["t"], 0.0), 0.4)
				b["pos"] = (b["from"] as Vector2).lerp(b["home"], k)
				if b["t"] >= 1.0:
					b["state"] = "stand"
			"stand":
				if spooked:
					_flee(b)
			"off":
				b["delay"] -= delta
				if b["delay"] <= 0.0:
					b["vel"] = (b["vel"] as Vector2) * (1.0 + delta * 0.8)
					b["pos"] += (b["vel"] as Vector2) * delta
	birds = birds.filter(func(b): return b["state"] != "off" or _on_screen(b["pos"]))
	queue_redraw()


func _on_screen(p: Vector2) -> bool:
	return p.x > -30.0 and p.x < Zones.VIEW_W + 30.0 and p.y > -40.0


func _land() -> void:
	var side := -1.0 if randf() < 0.5 else 1.0
	var cx := randf_range(60.0, Zones.VIEW_W - 100.0)   # clear of the bay side
	var y := Zones.SHORE_Y - randf_range(30.0, 60.0)
	for i in count:
		var home := Vector2(cx + float(i) * 16.0 + randf_range(-4.0, 4.0), y + randf_range(-10.0, 10.0))
		birds.append({"home": home, "pos": home, "from": home + Vector2(side * 220.0, -180.0),
			"t": -float(i) * 0.15, "state": "in", "flip": side > 0.0,
			"phase": randf() * TAU, "vel": Vector2.ZERO, "delay": 0.0})


func _flee(b: Dictionary) -> void:
	var away: Vector2 = (b["pos"] as Vector2) - game.player.position
	var dir := -1.0 if away.x < 0.0 else 1.0
	b["state"] = "off"
	b["flip"] = dir < 0.0
	b["delay"] = randf_range(0.0, 0.3)
	b["vel"] = Vector2(dir * randf_range(0.7, 1.0), -randf_range(0.6, 0.9)).normalized() * FLEE_SPEED


# The flight frame at time t (each bird passes its own phase so a flock is
# never in step). Holbox's flock uses it too.
static func flight_tex(t: float) -> Texture2D:
	var c := fmod(t, FLAP_LEN + GLIDE_LEN)
	return FLY[GLIDE_FRAME] if c >= FLAP_LEN else FLY[int(c * FLAP_FPS) % FLY.size()]


func _draw() -> void:
	if not active:
		return
	for b in birds:
		var flying: bool = b["state"] != "stand" and not (b["state"] == "off" and b["delay"] > 0.0)
		if not flying:
			draw_circle(b["pos"] + Vector2(0, 1), 5.0, Color(0, 0, 0, 0.18))
		draw_bird(self, b["pos"], flying, b["flip"], _anim, b["phase"])


static func draw_bird(c: CanvasItem, p: Vector2, flying: bool, flip: bool, anim: float, ph: float) -> void:
	# One flamingo at 2x, art facing right (flip for left), with its feet at p.
	# Standing, it bobs gently; flying, it beats or glides (flight_tex) and is
	# lifted off its feet so taking off or landing never jumps. Shared with
	# Holbox's flock.
	var face := Vector2(-1.0 if flip else 1.0, 1.0)
	if flying:
		var tex := flight_tex(anim + ph)
		var fs := tex.get_size() * 2.0
		c.draw_set_transform(p + Vector2(0, -fs.y * 0.5 + sin(anim * 3.0 + ph) * 2.0), 0.0, face)
		c.draw_texture_rect(tex, Rect2(-fs * 0.5, fs), false)
	else:
		var sz := ART.get_size() * 2.0
		c.draw_set_transform(p + Vector2(0, sin(anim * 1.5 + ph)), 0.0, face)
		c.draw_texture_rect(ART, Rect2(Vector2(-sz.x * 0.5, -sz.y), sz), false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
