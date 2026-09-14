class_name UiTheme
extends RefCounted

# One place for the look of every button, panel and readout.
#
# The game draws UI over sand, surf and deep water, so nothing can rely on the
# background behind it. Buttons and panels get near-opaque fills, and every
# label gets a dark outline so white text survives on pale sand as well as on
# navy ocean.

const INK := Color(0.05, 0.08, 0.12)
const ACCENT := Color(0.98, 0.86, 0.52)
const TEXT := Color(0.96, 0.97, 0.98)
const TEXT_DIM := Color(0.62, 0.68, 0.74)

const OUTLINE := Color(0.02, 0.04, 0.07, 0.85)
const OUTLINE_SIZE := 5

# Chunky playful display face, title screen only. Everything else emboldens the
# default font at runtime rather than shipping a second file.
const TITLE_FONT := preload("res://assets/fonts/TitanOne-Regular.ttf")

static var _bold: FontVariation


static func bold() -> FontVariation:
	# FontVariation fakes weight on whatever the fallback font is, so button
	# text gets heavier without bundling a bold cut of anything.
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = ThemeDB.fallback_font
		_bold.variation_embolden = 0.55
	return _bold


static func _box(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func button(b: Button) -> Button:
	# Near-solid rather than the theme default, which is translucent enough to
	# disappear against bright sand.
	b.add_theme_stylebox_override("normal",
		_box(Color(0.07, 0.11, 0.16, 0.94), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.55), 2, 6))
	b.add_theme_stylebox_override("hover",
		_box(Color(0.12, 0.17, 0.23, 0.97), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), 2, 6))
	b.add_theme_stylebox_override("pressed",
		_box(Color(0.20, 0.26, 0.32, 0.98), ACCENT, 2, 6))
	b.add_theme_stylebox_override("disabled",
		_box(Color(0.07, 0.11, 0.16, 0.62), Color(0.4, 0.44, 0.48, 0.4), 2, 6))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", bold())
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_color_override("font_disabled_color", Color(0.48, 0.52, 0.56))
	return b


static func panel(p: PanelContainer) -> PanelContainer:
	# Panels sit over live gameplay, so they are effectively opaque -- reading a
	# price list through a moving beach is not a feature.
	var sb := _box(Color(0.05, 0.08, 0.12, 0.985),
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45), 2, 10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	return p


static func outline(l: Label) -> Label:
	# White on pale sand needs this as much as white on navy does.
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return l
