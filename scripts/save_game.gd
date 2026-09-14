class_name SaveGame
extends RefCounted

# Progress lives in user://, which Godot maps to the right per-platform app data
# directory (including on Android and iOS) without any extra work.
#
# Only BETWEEN-shift state is stored: credits, upgrades owned, which shift you
# are on. Mid-shift progress (credits earned so far, the reputation hold timer)
# is deliberately not saved -- quitting mid-shift restarts that shift, which is
# simpler to reason about and impossible to exploit.

const PATH := "user://seaweed_shift_save.json"


static func store(data: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file: %s" % FileAccess.get_open_error())
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


static func load_data() -> Dictionary:
	# Named load_data rather than load() so it doesn't shadow the built-in.
	if not FileAccess.file_exists(PATH):
		return {}
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file was unreadable; starting fresh.")
		return {}
	return parsed


static func wipe() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
