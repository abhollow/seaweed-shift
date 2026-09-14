class_name Reputation
extends Node

# The resort's rating, 1-100, driven entirely by what is sitting on the
# shoreline. Rotten seaweed counts six times a fresh unit, so neglect costs you
# twice: half value at the bin AND six times the reputation damage.

# --- tuning -----------------------------------------------------------------
const MESS_FULL := 28.0        # weighted units that drag reputation to 1
const ROT_WEIGHT := 6.0        # a rotten unit counts as six fresh ones
const REP_FALL := 22.0         # points/sec the meter drops when the beach is dirty
const REP_RISE := 8.0          # points/sec it recovers -- deliberately slower
const REP_GOOD := 70.0         # default target if a shift doesn't name one
# ----------------------------------------------------------------------------

var game

var value := 100.0
var held := 0.0                # seconds continuously at or above target
var target := REP_GOOD
var rotten_piles := 0

var _was_good := true


func reset(new_target: float) -> void:
	target = new_target
	value = 100.0
	held = 0.0
	rotten_piles = 0
	_was_good = true


func tick(delta: float) -> void:
	# Floor is 0, not 1: the meter has to be able to bottom out for the shift to
	# be failable.
	var goal := clampf(100.0 - shore_mess() * (100.0 / MESS_FULL), 0.0, 100.0)

	# Eased rather than snapped, and asymmetric: reputation falls faster than it
	# recovers, so letting the beach go is cheap and digging out of it is not.
	var rate := REP_FALL if goal < value else REP_RISE
	value = move_toward(value, goal, rate * delta)

	var good := value >= target
	if good:
		held += delta
	else:
		held = 0.0

	# Fire once on the way down only -- a tone every frame below target would be
	# unbearable, and a tone on recovery would reward the wrong moment.
	if _was_good and not good:
		game.sfx("warn", 1.0, -3.0)
	_was_good = good


func shore_mess() -> float:
	# Only seaweed actually sitting on the shoreline counts against you. Clumps
	# still drifting are the ocean's problem, and kelp is out of sight.
	var mess := 0.0
	rotten_piles = 0
	for c in game.world.get_children():
		if not (c is Seaweed):
			continue
		var sw := c as Seaweed
		if sw.kelp or sw.drifting:
			continue
		if sw.is_rotten():
			mess += float(sw.units) * ROT_WEIGHT
			rotten_piles += 1
		else:
			mess += float(sw.units)
	return mess
