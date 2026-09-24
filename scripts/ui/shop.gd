class_name Shop
extends PanelContainer

# The supply shed. Purely presentation: it renders the upgrade list from
# Upgrades.LIST and calls game.buy(). All the stat effects live in Game, so the
# shop never has to know what a hopper does.

var game

var _list: VBoxContainer
var _title: Label


func build() -> void:
	UiTheme.panel(self)
	position = Vector2(12, 86)
	size = Vector2(336, 470)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	margin.add_child(outer)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	outer.add_child(_title)

	# Scroll, because the upgrade list is taller than a phone screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var close := UiTheme.button(Button.new())
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func(): game.toggle_shop())
	outer.add_child(close)


func rebuild() -> void:
	_title.text = "SUPPLY SHED   (%d credits)" % game.credits

	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	# Each shift features its own tier. Anything from an EARLIER tier that has
	# not been bought yet stays available, so skipping the waders in shift 1
	# never locks the player out of the shallows. Owned upgrades are hidden
	# rather than listed as OWNED -- the shop shows what you can still get.
	var shop_tier: int = game.shop_tier()
	var last_tier := 0
	for up in Upgrades.LIST:
		var tier := int(up["tier"])
		if tier > shop_tier or game.owned.has(up["id"]):
			continue
		if tier != last_tier:
			last_tier = tier
			if _list.get_child_count() > 0:
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(0, 10)
				_list.add_child(spacer)
			var header := Label.new()
			header.text = String(Upgrades.TIER_NAMES[tier])
			header.add_theme_font_size_override("font_size", 13)
			header.add_theme_color_override("font_color", Color(0.98, 0.82, 0.45))
			_list.add_child(header)

		var b := UiTheme.button(Button.new())
		b.custom_minimum_size = Vector2(0, 38)

		var is_owned: bool = game.owned.has(up["id"])
		var needs: String = up["needs"]
		var locked: bool = needs != "" and not game.owned.has(needs)

		if is_owned:
			b.text = "%s  --  OWNED" % up["name"]
			b.disabled = true
		elif locked:
			b.text = "%s  --  locked" % up["name"]
			b.disabled = true
		else:
			b.text = "%s  --  %d cr" % [up["name"], up["cost"]]
			b.disabled = game.credits < int(up["cost"])
			b.pressed.connect(_on_buy.bind(String(up["id"])))

		_list.add_child(b)

		var desc := Label.new()
		desc.text = "Requires the %s first." % _name_of(needs) if locked else String(up["desc"])
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_list.add_child(desc)



func _on_buy(id: String) -> void:
	game.buy(id)
	rebuild()


func _name_of(id: String) -> String:
	for up in Upgrades.LIST:
		if String(up["id"]) == id:
			return String(up["name"])
	return id
