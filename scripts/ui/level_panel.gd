class_name LevelPanel
extends PanelContainer

# Shown when a shift's two conditions are both met. The button either advances
# to the next authored shift or drops into free play if there are none left.

var game

var _title: Label
var _body: Label
var _button: Button
var _failed := false
var _choices: VBoxContainer


func build() -> void:
	UiTheme.panel(self)
	position = Vector2(18, 170)
	size = Vector2(324, 280)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 14)
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A PanelContainer grows to fit its content, so an unwrapped Label just
	# pushed the whole panel off the right of a 360px screen. Wrapping plus a
	# hard width cap keeps it on screen whatever the text says.
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(288, 0)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_body)

	# One button per retainable upgrade, shown only on the end-of-level screen.
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 8)
	_choices.visible = false
	box.add_child(_choices)

	_button = UiTheme.button(Button.new())
	_button.custom_minimum_size = Vector2(0, 48)
	_button.pressed.connect(_on_pressed)
	box.add_child(_button)


func _on_pressed() -> void:
	if _failed:
		game.retry_shift()
	else:
		game.next_shift()


func show_failure() -> void:
	if _choices != null:
		_choices.visible = false
	_button.visible = true
	# Say plainly what went wrong and what it cost. A bare "you lost" would be
	# infuriating given the shift restarts from scratch.
	_failed = true
	var lv: Dictionary = game.current_level()
	_title.text = "FIRED"
	_title.add_theme_color_override("font_color", Color(0.95, 0.42, 0.42))
	_body.text = ("Reputation hit zero.\n\n"
		+ "Too much seaweed was left to rot. A rotten pile "
		+ "counts six times a fresh one.\n\n"
		+ "%s restarts from the beginning. The %d credits "
		+ "earned this shift are gone.") % [
			String(lv["name"]).split("  --  ")[0],
			game.credits_earned,
		]
	_button.text = "RETRY SHIFT"
	_present()


func show_retain(options: Array) -> void:
	# End of a level. The whole point of this screen is that the reset reads as
	# a reward the player chose, not a wipe they suffered -- so it leads with
	# what they are KEEPING, and only mentions the reset second.
	_failed = false
	_title.text = "LEVEL %d COMPLETE" % game.level
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	var kept: int = game.retained.size()
	_body.text = ("Choose one upgrade to keep for good.\n\n"
		+ "It carries into every level from now on. Everything else resets, "
		+ "and the beach gets a little harder.\n\n%d of 10 kept so far.") % kept

	for c in _choices.get_children():
		_choices.remove_child(c)
		c.queue_free()
	for id in options:
		var up: Dictionary = Upgrades.by_id(String(id))
		var b := UiTheme.button(Button.new())
		b.custom_minimum_size = Vector2(0, 44)
		b.text = "KEEP  %s" % String(up["name"]).to_upper()
		b.pressed.connect(func(): game.retain_and_advance(String(id)))
		_choices.add_child(b)

	_choices.visible = true
	_button.visible = false
	_present()


func show_summary(is_last: bool) -> void:
	if _choices != null:
		_choices.visible = false
	_button.visible = true
	_failed = false
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	var lv: Dictionary = game.current_level()
	_title.text = "SHIFT COMPLETE"

	var mins := int(game.shift_elapsed) / 60
	var secs := int(game.shift_elapsed) % 60
	# "Closest call" is the stat worth reporting: it is the only one that says
	# anything about HOW the shift went rather than that it ended.
	_body.text = ("%s\n\nEarned this shift   %d cr\nResort bonus   +%d cr\n"
		+ "In the bank   %d cr\n\nShift time   %d:%02d\nClosest call   reputation %d") % [
		String(lv["name"]).split("  --  ")[0],
		game.credits_earned,
		game.shift_bonus,
		game.credits,
		mins, secs,
		int(game.best_rep),
	]
	_button.text = "KEEP PLAYING" if is_last else "NEXT SHIFT"
	_present()


func _present() -> void:
	UiTheme.present(self)
