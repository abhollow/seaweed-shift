class_name Settings
extends RefCounted

# Audio preferences, stored separately from progress so that wiping your save
# doesn't also reset your volume sliders.

const PATH := "user://seaweed_shift_settings.json"

const DEFAULTS := {
	"music": 0.80,
	"sfx": 0.90,
	"ambience": 0.80,
}


static func load_all() -> Dictionary:
	var out := DEFAULTS.duplicate()
	if not FileAccess.file_exists(PATH):
		return out
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	for key in DEFAULTS:
		if parsed.has(key):
			out[key] = clampf(float(parsed[key]), 0.0, 1.0)
	return out


static func store(data: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()


static func apply(data: Dictionary) -> void:
	_set_bus("Music", float(data.get("music", DEFAULTS["music"])))
	_set_bus("SFX", float(data.get("sfx", DEFAULTS["sfx"])))
	_set_bus("Ambience", float(data.get("ambience", DEFAULTS["ambience"])))


static func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	# A slider at zero should be silence, not -80 dB of very quiet audio.
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))
