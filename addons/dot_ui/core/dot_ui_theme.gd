@tool
class_name DotUiTheme
extends Resource

## Builds a whole [Theme] out of a palette and a scale, with no art assets.
##
## [b]dot-ui ships no textures, no fonts and no nine-patches, and that is the point.[/b]
## An addon that shipped art would impose its art on every game that installed it, and
## the first thing anyone does is replace it — so the theme is generated from
## [StyleBoxFlat]s at runtime. A game that wants a real theme assigns one and this
## class is never used; a game that wants to ship *today* gets something legible.
##
## The palette is deliberately flat and high-contrast, which is what a dev-textured
## arena shooter wants anyway.

const CHANNEL := "ui.theme"

@export_group("Palette")

@export var background: Color = Color(0.08, 0.09, 0.11, 0.92)
@export var surface: Color = Color(0.14, 0.15, 0.18, 0.95)
@export var surface_hover: Color = Color(0.20, 0.22, 0.26, 0.95)
@export var surface_pressed: Color = Color(0.10, 0.11, 0.13, 0.95)
@export var outline: Color = Color(0.32, 0.35, 0.40, 1.0)
@export var accent: Color = Color(0.35, 0.70, 1.0, 1.0)
@export var text: Color = Color(0.92, 0.93, 0.95, 1.0)
@export var text_dim: Color = Color(0.62, 0.65, 0.70, 1.0)
@export var danger: Color = Color(0.90, 0.30, 0.28, 1.0)
@export var good: Color = Color(0.35, 0.80, 0.45, 1.0)

@export_group("Metrics")

@export_range(0.0, 24.0, 1.0) var corner: float = 3.0
@export_range(0.0, 6.0, 1.0) var border: float = 1.0
@export_range(2.0, 32.0, 1.0) var padding: float = 8.0
@export_range(8, 48, 1) var font_size: int = 15
@export_range(8, 64, 1) var heading_size: int = 22

@export_group("Font")

## Optional. Left null the engine default is used, which is legible everywhere and is
## the only font guaranteed to exist on a web export.
@export var font: Font = null


static func dark() -> DotUiTheme:
	return DotUiTheme.new()


static func light() -> DotUiTheme:
	var theme := DotUiTheme.new()
	theme.background = Color(0.94, 0.94, 0.96, 0.96)
	theme.surface = Color(0.99, 0.99, 1.0, 1.0)
	theme.surface_hover = Color(0.92, 0.93, 0.96, 1.0)
	theme.surface_pressed = Color(0.86, 0.88, 0.92, 1.0)
	theme.outline = Color(0.72, 0.74, 0.78, 1.0)
	theme.text = Color(0.10, 0.11, 0.13, 1.0)
	theme.text_dim = Color(0.38, 0.40, 0.44, 1.0)
	return theme


## Dark, in deep blue, for a game that happens somewhere with stars in it.
##
## A palette and nothing more — same builder, same metrics discipline as [method dark].
## The reason it exists rather than each game hand-tinting nine colours: a neutral grey
## card in front of [DotStarfield] reads as a screenshot of a different program pasted over
## the game, and the fix for that is one palette shared by the menu and the HUD, not two
## that nearly agree.
static func space() -> DotUiTheme:
	var theme := DotUiTheme.new()
	theme.background = Color(0.055, 0.062, 0.100, 0.92)
	theme.surface = Color(0.075, 0.085, 0.135, 0.92)
	theme.surface_hover = Color(0.110, 0.130, 0.190, 0.95)
	theme.surface_pressed = Color(0.042, 0.048, 0.082, 0.95)
	theme.outline = Color(0.30, 0.44, 0.72, 0.45)
	theme.accent = Color(0.36, 0.68, 1.00, 1.0)
	theme.text = Color(0.90, 0.93, 0.98, 1.0)
	theme.text_dim = Color(0.55, 0.61, 0.72, 1.0)
	# Rounder than the default, which is 3px and deliberately utilitarian. A panel floating
	# on a starfield is a card, and a card with square corners looks like a crash dialog.
	theme.corner = 12.0
	theme.padding = 13.0
	theme.heading_size = 26
	return theme


## Builds a [Theme]. [param scale] multiplies every metric.
##
## A fresh object every call rather than a cached one: a [Theme] is mutable and shared,
## and handing the same instance to two windows means a game that tweaks one tweaks
## both.
func build(scale: float = 1.0) -> Theme:
	var theme := Theme.new()
	var unit := maxf(0.25, scale)

	theme.default_font_size = int(round(float(font_size) * unit))

	if font != null:
		theme.default_font = font

	_style_panel(theme, unit)
	_style_button(theme, unit)
	_style_label(theme, unit)
	_style_line_edit(theme, unit)
	_style_ranges(theme, unit)
	_style_containers(theme, unit)

	return theme


func _box(fill: Color, unit: float, line: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill

	var radius := int(round(corner * unit))
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius

	var inset := int(round(padding * unit))
	box.content_margin_left = inset
	box.content_margin_right = inset
	box.content_margin_top = int(round(padding * 0.6 * unit))
	box.content_margin_bottom = int(round(padding * 0.6 * unit))

	if line.a > 0.0 and border > 0.0:
		var width := maxi(1, int(round(border * unit)))
		box.border_color = line
		box.set_border_width_all(width)

	return box


func _style_panel(theme: Theme, unit: float) -> void:
	theme.set_stylebox("panel", "Panel", _box(background, unit, outline))
	theme.set_stylebox("panel", "PanelContainer", _box(surface, unit, outline))

	var transparent := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "DotHudPanel", transparent)


func _style_button(theme: Theme, unit: float) -> void:
	theme.set_stylebox("normal", "Button", _box(surface, unit, outline))
	theme.set_stylebox("hover", "Button", _box(surface_hover, unit, accent))
	theme.set_stylebox("pressed", "Button", _box(surface_pressed, unit, accent))
	theme.set_stylebox("focus", "Button", _box(Color.TRANSPARENT, unit, accent))

	var disabled := _box(surface, unit, outline)
	disabled.bg_color.a *= 0.5
	theme.set_stylebox("disabled", "Button", disabled)

	theme.set_color("font_color", "Button", text)
	theme.set_color("font_hover_color", "Button", text)
	theme.set_color("font_pressed_color", "Button", accent)
	theme.set_color("font_disabled_color", "Button", text_dim)
	theme.set_font_size("font_size", "Button", int(round(float(font_size) * unit)))

	for variation in ["CheckBox", "CheckButton", "OptionButton", "MenuButton"]:
		theme.set_color("font_color", variation, text)
		theme.set_font_size(
			"font_size", variation, int(round(float(font_size) * unit))
		)


func _style_label(theme: Theme, unit: float) -> void:
	theme.set_color("font_color", "Label", text)
	theme.set_font_size("font_size", "Label", int(round(float(font_size) * unit)))

	# Type variations, so a heading is `theme_type_variation = &"DotHeading"` rather
	# than a hand-set font size that stops scaling.
	theme.set_type_variation(&"DotHeading", &"Label")
	theme.set_color("font_color", "DotHeading", text)
	theme.set_font_size(
		"font_size", "DotHeading", int(round(float(heading_size) * unit))
	)

	theme.set_type_variation(&"DotDim", &"Label")
	theme.set_color("font_color", "DotDim", text_dim)
	theme.set_font_size("font_size", "DotDim", int(round(float(font_size) * unit)))

	theme.set_type_variation(&"DotDanger", &"Label")
	theme.set_color("font_color", "DotDanger", danger)

	theme.set_type_variation(&"DotGood", &"Label")
	theme.set_color("font_color", "DotGood", good)

	theme.set_color("default_color", "RichTextLabel", text)
	theme.set_font_size(
		"normal_font_size", "RichTextLabel", int(round(float(font_size) * unit))
	)


func _style_line_edit(theme: Theme, unit: float) -> void:
	theme.set_stylebox("normal", "LineEdit", _box(surface_pressed, unit, outline))
	theme.set_stylebox("focus", "LineEdit", _box(surface_pressed, unit, accent))
	theme.set_color("font_color", "LineEdit", text)
	theme.set_color("font_placeholder_color", "LineEdit", text_dim)
	theme.set_color("caret_color", "LineEdit", accent)
	theme.set_font_size("font_size", "LineEdit", int(round(float(font_size) * unit)))


func _style_ranges(theme: Theme, unit: float) -> void:
	var track := _box(surface_pressed, unit, outline)
	track.content_margin_top = 0
	track.content_margin_bottom = 0

	var fill := _box(accent, unit)
	fill.content_margin_top = 0
	fill.content_margin_bottom = 0

	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)

	theme.set_stylebox("background", "ProgressBar", track)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", text)


func _style_containers(theme: Theme, unit: float) -> void:
	var gap := int(round(padding * 0.75 * unit))
	theme.set_constant("separation", "VBoxContainer", gap)
	theme.set_constant("separation", "HBoxContainer", gap)
	theme.set_constant("h_separation", "GridContainer", gap)
	theme.set_constant("v_separation", "GridContainer", gap)
	theme.set_constant("margin_left", "MarginContainer", gap)
	theme.set_constant("margin_right", "MarginContainer", gap)
	theme.set_constant("margin_top", "MarginContainer", gap)
	theme.set_constant("margin_bottom", "MarginContainer", gap)


func describe() -> Dictionary:
	return {
		"font_size": font_size,
		"heading_size": heading_size,
		"corner": corner,
		"custom_font": font != null,
	}
