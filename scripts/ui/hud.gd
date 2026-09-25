class_name Hud
extends CanvasLayer

# The readout layer.
#
# Everything except the two buttons lives in a strip along the very bottom of
# the screen, over deep water. That is the one region with no reason to tap, and
# white text reads cleanly against navy in a way it never did over pale sand.
#
# The fullscreen tint and the joystick deliberately do NOT live here -- the
# joystick does its drawing and its touch handling in raw screen coordinates, so
# offsetting it would render the stick somewhere other than your thumb.

const SAFE_AREA_MAX := 72.0

const STRIP_H := 42.0
const BTN_Y := 8.0

var game

var _lbl_credits: Label
var _lbl_carry: Label
var _lbl_shift: Label
var _lbl_rep: Label
var _lbl_status: Label
var _strip: ColorRect
var _goal_bg: ColorRect
var _goal_fill: ColorRect
var _goal_hold: ColorRect
var _rep_bg: ColorRect
var _rep_fill: ColorRect
var _pause_panel: PanelContainer
var _menu_btn: Button
var _shop_btn: Button

var _top_inset := 0.0
var _bottom_inset := 0.0


func build() -> void:
	layer = 1
	_build_buttons()
	_build_strip()
	_build_pause_panel()
	apply_safe_area()
	get_tree().root.size_changed.connect(apply_safe_area)


func _build_buttons() -> void:
	# MENU opens the pause panel rather than quitting outright. It sits next to
	# SHOP, so a stray thumb would otherwise throw away the shift's progress --
	# and it doubles as the manual pause the game didn't have.
	_menu_btn = UiTheme.button(Button.new())
	_menu_btn.text = "MENU"
	_menu_btn.position = Vector2(184, BTN_Y)
	_menu_btn.size = Vector2(68, 44)
	_menu_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_btn.pressed.connect(func(): game.pause_for_system())
	add_child(_menu_btn)

	_shop_btn = UiTheme.button(Button.new())
	_shop_btn.text = "SHOP"
	_shop_btn.position = Vector2(258, BTN_Y)
	_shop_btn.size = Vector2(92, 44)
	_shop_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	_shop_btn.pressed.connect(func(): game.toggle_shop())
	add_child(_shop_btn)


func _build_strip() -> void:
	var top := Zones.VIEW_H - STRIP_H

	_strip = ColorRect.new()
	_strip.position = Vector2(0, top)
	_strip.size = Vector2(Zones.VIEW_W, STRIP_H)
	_strip.color = Color(0.03, 0.06, 0.10, 0.70)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)

	_lbl_credits = _label(Vector2(8, top + 4), Vector2(72, 18), 15,
		UiTheme.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	# Sits between credits and the shift readout. Kept narrow and left of 150
	# so it cannot collide with the shift text, which grows as the numbers do.
	_lbl_carry = _label(Vector2(80, top + 6), Vector2(64, 16), 12,
		UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_shift = _label(Vector2(150, top + 6), Vector2(138, 16), 12,
		UiTheme.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_rep = _label(Vector2(288, top + 6), Vector2(64, 16), 12,
		UiTheme.TEXT, HORIZONTAL_ALIGNMENT_RIGHT)

	# Shift progress sits directly under the label as a second thin bar, so the
	# two things that end a shift -- money earned and reputation held -- are
	# both visible at a glance rather than buried in the shop.
	_goal_bg = ColorRect.new()
	_goal_bg.position = Vector2(150, top + 22)
	_goal_bg.size = Vector2(138, 4)
	_goal_bg.color = Color(0.10, 0.13, 0.17, 0.9)
	_goal_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_goal_bg)

	_goal_fill = ColorRect.new()
	_goal_fill.position = Vector2(150, top + 22)
	_goal_fill.size = Vector2(0, 4)
	_goal_fill.color = UiTheme.ACCENT
	_goal_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_goal_fill)

	_goal_hold = ColorRect.new()
	_goal_hold.position = Vector2(150, top + 22)
	_goal_hold.size = Vector2(0, 4)
	_goal_hold.color = Color(0.35, 0.85, 0.45, 0.85)
	_goal_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_goal_hold)

	_rep_bg = ColorRect.new()
	_rep_bg.position = Vector2(8, top + 29)
	_rep_bg.size = Vector2(344, 8)
	_rep_bg.color = Color(0.10, 0.13, 0.17, 0.9)
	_rep_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rep_bg)

	_rep_fill = ColorRect.new()
	_rep_fill.position = Vector2(9, top + 30)
	_rep_fill.size = Vector2(342, 6)
	_rep_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rep_fill)

	# Transient warnings float just above the strip so they never crowd it.
	_lbl_status = _label(Vector2(0, top - 22), Vector2(Zones.VIEW_W, 18), 12,
		Color(1.0, 0.86, 0.55), HORIZONTAL_ALIGNMENT_CENTER)


func _label(pos: Vector2, size: Vector2, fsize: int, c: Color, align: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.outline(l)
	add_child(l)
	return l


func apply_safe_area() -> void:
	# The layer itself is NOT offset any more. With readouts pinned to the
	# bottom, shifting the whole layer down would push them off the screen, so
	# top and bottom insets are applied to their own elements instead.
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var vis := get_viewport().get_visible_rect().size

	_top_inset = clampf((float(safe.position.y) / float(win.y)) * vis.y, 0.0, SAFE_AREA_MAX)
	var bottom_px := float(win.y - (safe.position.y + safe.size.y))
	_bottom_inset = clampf((bottom_px / float(win.y)) * vis.y, 0.0, SAFE_AREA_MAX)

	_menu_btn.position.y = BTN_Y + _top_inset
	_shop_btn.position.y = BTN_Y + _top_inset

	var shift := -_bottom_inset
	var top := Zones.VIEW_H - STRIP_H + shift
	_strip.position.y = top
	_lbl_credits.position.y = top + 4
	_lbl_carry.position.y = top + 6
	_lbl_shift.position.y = top + 6
	_lbl_rep.position.y = top + 6
	_goal_bg.position.y = top + 22
	_goal_fill.position.y = top + 22
	_goal_hold.position.y = top + 22
	_rep_bg.position.y = top + 29
	_rep_fill.position.y = top + 30
	_lbl_status.position.y = top - 22


# =============================================================================
# Pause
# =============================================================================

func _build_pause_panel() -> void:
	_pause_panel = UiTheme.panel(PanelContainer.new())
	_pause_panel.position = Vector2(40, 230)
	_pause_panel.size = Vector2(280, 230)
	_pause_panel.visible = false
	_pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_pause_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var body := Label.new()
	body.text = "The shift is on hold."
	body.add_theme_font_size_override("font_size", 13)
	body.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)

	var resume := UiTheme.button(Button.new())
	resume.text = "RESUME"
	resume.custom_minimum_size = Vector2(0, 52)
	resume.pressed.connect(func(): game.resume_from_pause())
	box.add_child(resume)

	var quit := UiTheme.button(Button.new())
	quit.text = "QUIT TO MENU"
	quit.custom_minimum_size = Vector2(0, 40)
	quit.add_theme_font_size_override("font_size", 13)
	quit.pressed.connect(func(): game.quit_to_menu())
	box.add_child(quit)


func pause_visible() -> bool:
	return _pause_panel != null and _pause_panel.visible


func show_pause(v: bool) -> void:
	if _pause_panel == null:
		return
	if not v:
		_pause_panel.visible = false
		return

	UiTheme.present(_pause_panel)


# =============================================================================
# Readouts
# =============================================================================

func refresh() -> void:
	var rep: Reputation = game.rep
	var player: Player = game.player

	_lbl_credits.text = "%d cr" % game.credits
	_lbl_carry.text = "%d / %d" % [player.carried, player.capacity]

	if game.free_play:
		_lbl_shift.text = "FREE PLAY"
		_goal_bg.visible = false
		_goal_fill.visible = false
		_goal_hold.visible = false
	else:
		var lv: Dictionary = game.current_level()
		var need: int = int(lv["credits"])
		var earned: int = game.credits_earned
		var hold_need: float = float(lv["hold"])

		_lbl_shift.text = "L%d  S%d/%d  %d/%d cr" % [
			game.level, game.level_index + 1, Levels.LIST.size(), earned, need,
		]
		_goal_bg.visible = true
		_goal_fill.visible = true
		_goal_hold.visible = true
		_goal_fill.size.x = 138.0 * clampf(float(earned) / maxf(1.0, float(need)), 0.0, 1.0)
		# The green overlay is the reputation-hold half of the goal, drawn on the
		# same bar so a full bar genuinely means "shift about to end".
		_goal_hold.size.x = 138.0 * clampf(game.rep.held / maxf(1.0, hold_need), 0.0, 1.0)
		_goal_hold.position.x = 150.0

	_refresh_meter(rep)
	_refresh_status(rep, player)


func _refresh_meter(rep: Reputation) -> void:
	var v := int(round(rep.value))
	_lbl_rep.text = "REP %d" % v

	var c: Color
	if rep.value >= rep.target:
		c = Color(0.35, 0.85, 0.45)
	elif rep.value >= 40.0:
		c = Color(0.95, 0.80, 0.30)
	else:
		c = Color(0.92, 0.34, 0.31)

	_lbl_rep.add_theme_color_override("font_color", c)
	_rep_fill.color = c
	_rep_fill.size = Vector2(342.0 * (rep.value / 100.0), 6)


func _refresh_status(rep: Reputation, player: Player) -> void:
	# The countdown outranks everything: if the shift is about to be lost, that
	# is the only thing worth saying.
	if rep.failing():
		_lbl_status.text = "REPUTATION GONE -- FIRED IN %d" % ceili(rep.fail_countdown())
		_lbl_status.add_theme_color_override("font_color", Color(0.98, 0.35, 0.32))
		return
	_lbl_status.add_theme_color_override("font_color", Color(1.0, 0.86, 0.55))

	# Level warnings, below the failure countdown but above everything else.
	if game.ferry != null and game.ferry.inbound():
		_lbl_status.text = "FERRY INBOUND -- WAKE COMING"
		return
	if game.vip != null and game.vip.visible and game.vip_units() > 0:
		_lbl_status.text = "SEAWEED IN THE VIP AREA"
		return
	if game.night != null and game.night.moonlit():
		_lbl_status.text = "THE CLOUDS PART -- LOOK AROUND"
		return

	if player.in_safe_zone:
		_lbl_status.text = "Loading bay -- safe"
	elif game.happy_hour:
		_lbl_status.text = "HAPPY HOUR -- the bar has emptied out"
	elif game.storm_active and not player.has_rain_jacket:
		_lbl_status.text = "STORM -- slowed! (buy a jacket)"
	elif game.storm_active:
		_lbl_status.text = "STORM -- jacket holding"
	elif rep.rotten_piles > 0 and rep.value < 85.0:
		_lbl_status.text = "%d rotten pile(s) -- clear them" % rep.rotten_piles
	elif player.is_full():
		_lbl_status.text = "FULL -- head to the dump bin"
	elif not player.can_enter_deep and player.position.y > Zones.DEEP_TOP - 40.0:
		_lbl_status.text = "Buoy line -- need a Trawler Rig"
	elif player.position.y >= Zones.SHALLOW_TOP and not player.has_waders:
		_lbl_status.text = "Wading -- you need the waders for this"
	else:
		_lbl_status.text = ""
