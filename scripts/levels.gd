class_name Levels
extends RefCounted

# A shift ends when BOTH conditions are met:
#   1. you have earned `credits` this shift (earned, not held -- spending on
#      upgrades never sets you back), and
#   2. reputation has stayed at or above `rep` for `hold` continuous seconds.
#
# The hold timer resets to zero the instant reputation dips below the target, so
# the second condition is self-policing: there is no separate fail state, you
# simply cannot finish a shift on a dirty beach.
#
# Shift 1 is tuned so that ~1500 credits earned is roughly all of tier 1 plus
# most of the tractor, which was about 15 minutes in playtesting.
#
# `music` is the shift's playlist. Tracks are shuffled, played through with a
# fade between each, then reshuffled -- so no single song loops for 15 minutes.
# Shifts sharing a playlist don't restart it on advance.

const LIST := [
	{
		"name": "SHIFT 1  --  Low Season",
		"credits": 1500,
		"rep": 70.0,
		"hold": 90.0,
		"difficulty": 1.0,
		"rot_scale": 1.0,
		# Storm spawn interval multiplier and units per spawn. On foot with no
		# upgrades a full-strength storm produces ~18x what the player can
		# clear, which is not a difficulty curve, it is a wall.
		"storm_mult": 0.70,
		"storm_burst": 1,
		# First entry always opens the shift; the rest are shuffled.
		"music": [
			"res://audio/Pixel_Paradise_2.mp3",
			"res://audio/Pixel_Paradise_3.mp3",
			"res://audio/Island_Bit_Reggae.mp3",
			"res://audio/Pixel_Paradise_4.mp3",
		],
	},
	{
		"name": "SHIFT 2  --  Shoulder Season",
		"credits": 4000,
		"rep": 75.0,
		"hold": 120.0,
		# Tier-2 gear roughly doubles throughput, so the beach has to fill
		# faster or the shift plays exactly like shift 1 with bigger numbers.
		"difficulty": 1.5,
		"rot_scale": 0.8,
		"storm_mult": 0.50,
		"storm_burst": 2,
		# First entry always opens the shift; the rest are shuffled.
		"music": [
			"res://audio/Pixel_Paradise_2.mp3",
			"res://audio/Pixel_Paradise_3.mp3",
			"res://audio/Island_Bit_Reggae.mp3",
			"res://audio/Pixel_Paradise_4.mp3",
		],
	},
	{
		"name": "SHIFT 3  --  High Season",
		"credits": 11000,
		"rep": 80.0,
		"hold": 150.0,
		"difficulty": 2.1,
		"rot_scale": 0.62,
		"storm_mult": 0.35,
		"storm_burst": 3,
		# First entry always opens the shift; the rest are shuffled.
		"music": [
			"res://audio/Pixel_Paradise_2.mp3",
			"res://audio/Pixel_Paradise_3.mp3",
			"res://audio/Island_Bit_Reggae.mp3",
			"res://audio/Pixel_Paradise_4.mp3",
		],
	},
]
