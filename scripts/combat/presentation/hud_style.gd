class_name HudStyle
extends RefCounted
## Shared HUD look: text colours for defence feedback, label and panel builders. Big text with
## dark outlines so it reads over any background.

const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.92)
const TEXT := Color(0.95, 0.94, 0.9)
const TEXT_DIM := Color(0.55, 0.55, 0.58)
const GOLD := Color(1.0, 0.82, 0.3)
const PANEL_BG := Color(0.05, 0.05, 0.08, 0.78)
const PANEL_BORDER := Color(0.25, 0.25, 0.3, 0.9)
const HP_FILL := Color(0.36, 0.8, 0.38)
const HP_LOW := Color(0.92, 0.32, 0.25)
const HP_BG := Color(0.12, 0.1, 0.1, 0.9)
const ENEMY_HP_FILL := Color(0.78, 0.25, 0.22)

## Defence feedback colours (DESIGN.md 3.6).
const PARRY := Color(1.0, 0.95, 0.55)
const DODGE := Color(0.62, 1.0, 0.7)
const JUMP := Color(0.55, 0.88, 1.0)
const EARLY := Color(0.38, 0.62, 1.0)
const LATE := Color(1.0, 0.36, 0.3)
const WRONG := Color(1.0, 0.6, 0.15)
const MISS := Color(0.86, 0.86, 0.86)
const DAMAGE_TAKEN := Color(1.0, 0.32, 0.27)
const DAMAGE_DEALT := Color(1.0, 1.0, 1.0)
const RING_NORMAL := Color(0.9, 0.95, 1.0)
const RING_GROUND := Color(1.0, 0.6, 0.15)

const OUTLINE_RATIO: float = 0.2


static func label_settings(size: int, color: Color = TEXT) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = size
	s.font_color = color
	s.outline_size = maxi(2, roundi(float(size) * OUTLINE_RATIO))
	s.outline_color = OUTLINE_COLOR
	return s


static func make_label(text: String, size: int, color: Color = TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.label_settings = label_settings(size, color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func panel(bg: Color = PANEL_BG, border: Color = PANEL_BORDER, border_px: int = 2, padding: int = 12) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_px)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(padding)
	return box


static func bar(fill: Color, height: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0.0, height)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = HP_BG
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


## Sets the fill colour of a bar made by bar().
static func set_bar_color(b: ProgressBar, fill: Color) -> void:
	var fg := b.get_theme_stylebox("fill") as StyleBoxFlat
	if fg != null:
		fg.bg_color = fill


## "+12" / "-8" for a millisecond offset.
static func signed_ms(ms: int) -> String:
	return ("+%d" % ms) if ms >= 0 else str(ms)
