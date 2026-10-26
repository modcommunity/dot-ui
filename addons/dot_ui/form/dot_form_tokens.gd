class_name DotFormTokens
extends RefCounted

## The form kit's design tokens: palette, spacing, radius, type and elevation, and the Theme built from them.

const SPACING: Array[int] = [0, 4, 8, 12, 16, 24, 32]

var is_dark := true
var scale := 1.0
## False turns every tween into an instant jump (tests and screenshots).
var animate := true
## Touch-sized targets: set by the form on narrow viewports.
var touch := false

var bg := Color(0.063, 0.070, 0.086)
var card := Color(0.098, 0.108, 0.133)
var card_inner := Color(0.125, 0.137, 0.167)
var field := Color(0.152, 0.165, 0.200)
var field_hover := Color(0.188, 0.204, 0.245)
var border := Color(0.20, 0.22, 0.27)
var text := Color(0.93, 0.94, 0.97)
var text_dim := Color(0.62, 0.65, 0.72)
var text_faint := Color(0.45, 0.48, 0.55)
var accent := Color(0.38, 0.62, 1.0)
var accent_ink := Color(0.04, 0.07, 0.14)
var danger := Color(1.0, 0.42, 0.42)
var good := Color(0.40, 0.84, 0.55)
var shadow := Color(0, 0, 0, 0.35)

var radius := 10
var font_body := 15
var font_small := 12
var font_section := 16
var font_title := 24

var _bold: Font = null


static func dark() -> DotFormTokens:
	return DotFormTokens.new()


static func light() -> DotFormTokens:
	var t := DotFormTokens.new()
	t.is_dark = false
	t.bg = Color(0.945, 0.953, 0.968)
	t.card = Color(1, 1, 1)
	t.card_inner = Color(0.965, 0.972, 0.985)
	t.field = Color(0.925, 0.935, 0.955)
	t.field_hover = Color(0.89, 0.905, 0.935)
	t.border = Color(0.84, 0.86, 0.90)
	t.text = Color(0.09, 0.10, 0.13)
	t.text_dim = Color(0.36, 0.39, 0.46)
	t.text_faint = Color(0.56, 0.59, 0.65)
	t.accent = Color(0.12, 0.42, 0.92)
	t.accent_ink = Color(1, 1, 1)
	t.danger = Color(0.82, 0.18, 0.20)
	t.good = Color(0.10, 0.60, 0.30)
	t.shadow = Color(0.1, 0.15, 0.3, 0.14)
	return t


## Tokens in the colours and corner of an existing [DotUiTheme], so the form sits with a game's own screens.
static func from_theme(theme: DotUiTheme) -> DotFormTokens:
	var t := DotFormTokens.light() if theme.text.v < 0.5 else DotFormTokens.dark()
	t.accent = theme.accent
	t.danger = theme.danger
	t.good = theme.good
	t.radius = clampi(int(theme.corner) + 6, 6, 18)
	t.font_body = theme.font_size
	return t


## A spacing step (0 to 6) in pixels at the current scale.
func sp(level: int) -> int:
	return px(SPACING[clampi(level, 0, SPACING.size() - 1)])


func px(v: float) -> int:
	return int(round(v * scale))


## Minimum height of an interactive control.
func target() -> int:
	return px(44.0 if touch else 36.0)


func bold() -> Font:
	if _bold == null:
		var v := FontVariation.new()
		v.base_font = ThemeDB.fallback_font
		v.variation_embolden = 0.55
		_bold = v
	return _bold


func box(fill: Color, r: int = -1, edge: Color = Color.TRANSPARENT, edge_w: int = 0, lift: int = 0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fill
	b.set_corner_radius_all(px(radius if r < 0 else r))
	b.anti_aliasing = true
	if edge_w > 0:
		b.border_color = edge
		b.set_border_width_all(edge_w)
	if lift > 0:
		b.shadow_color = shadow
		b.shadow_size = px(4.0 * lift)
		b.shadow_offset = Vector2(0, px(1.5 * lift))
	return b


func _pad(b: StyleBoxFlat, h: int, v: int) -> StyleBoxFlat:
	b.content_margin_left = h
	b.content_margin_right = h
	b.content_margin_top = v
	b.content_margin_bottom = v
	return b


## Starts a tween on [param obj]'s [param prop], replacing one already running there; jumps when animate is off.
func go(node: Node, obj: Object, prop: String, to: Variant, dur: float = 0.16) -> void:
	var meta := "_form_tw_" + prop.replace(":", "_")
	if obj.has_meta(meta):
		var old: Tween = obj.get_meta(meta)
		if old != null and old.is_valid():
			old.kill()
	if not animate or not node.is_inside_tree():
		obj.set_indexed(NodePath(prop), to)
		return
	var tw := node.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(obj, prop, to, dur)
	obj.set_meta(meta, tw)


## A [Theme] for every control the form uses; assigned on the form root so nothing else is touched.
func build_theme() -> Theme:
	var th := Theme.new()
	var pad_h := sp(3)
	var pad_v := px(6.0 if not touch else 10.0)
	th.default_font_size = px(font_body)
	th.set_color("font_color", "Label", text)

	var ring := box(Color.TRANSPARENT, radius, accent, maxi(2, px(2.0)))
	ring.expand_margin_left = 1
	ring.expand_margin_right = 1
	ring.expand_margin_top = 1
	ring.expand_margin_bottom = 1

	for kind in ["LineEdit"]:
		th.set_stylebox("normal", kind, _pad(box(field, radius - 2, border, 1), pad_h, pad_v))
		th.set_stylebox("read_only", kind, _pad(box(field, radius - 2, border, 1), pad_h, pad_v))
		th.set_stylebox("focus", kind, ring)
		th.set_color("font_color", kind, text)
		th.set_color("font_placeholder_color", kind, text_faint)
		th.set_color("caret_color", kind, accent)
		th.set_color("selection_color", kind, Color(accent, 0.35))
		th.set_color("clear_button_color", kind, text_dim)
		th.set_color("clear_button_color_pressed", kind, text)

	for kind in ["Button", "OptionButton", "ColorPickerButton"]:
		th.set_stylebox("normal", kind, _pad(box(field, radius - 2, border, 1), pad_h, pad_v))
		th.set_stylebox("hover", kind, _pad(box(field_hover, radius - 2, border, 1), pad_h, pad_v))
		th.set_stylebox("pressed", kind, _pad(box(card_inner, radius - 2, border, 1), pad_h, pad_v))
		th.set_stylebox("disabled", kind, _pad(box(Color(field, 0.45), radius - 2, Color.TRANSPARENT, 0), pad_h, pad_v))
		th.set_stylebox("focus", kind, ring)
		th.set_color("font_color", kind, text)
		th.set_color("font_hover_color", kind, text)
		th.set_color("font_pressed_color", kind, text)
		th.set_color("font_focus_color", kind, text)
		th.set_color("font_disabled_color", kind, text_faint)
	th.set_constant("h_separation", "OptionButton", sp(2))
	th.set_color("font_color", "OptionButton", text)

	_theme_buttons(th, ring, pad_h, pad_v)
	_theme_labels_and_popups(th)
	return th


## The button variations: primary, ghost, reset and section header.
func _theme_buttons(th: Theme, ring: StyleBox, pad_h: int, pad_v: int) -> void:
	th.set_type_variation("FormPrimary", "Button")
	th.set_stylebox("normal", "FormPrimary", _pad(box(accent, radius - 2), pad_h * 2, pad_v))
	th.set_stylebox("hover", "FormPrimary", _pad(box(accent.lightened(0.15), radius - 2), pad_h * 2, pad_v))
	th.set_stylebox("pressed", "FormPrimary", _pad(box(accent.darkened(0.15), radius - 2), pad_h * 2, pad_v))
	th.set_stylebox("disabled", "FormPrimary", _pad(box(Color(accent, 0.28), radius - 2), pad_h * 2, pad_v))
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, "FormPrimary", accent_ink)
	th.set_color("font_disabled_color", "FormPrimary", Color(accent_ink, 0.55))
	th.set_font("font", "FormPrimary", bold())

	th.set_type_variation("FormGhost", "Button")
	var none := box(Color.TRANSPARENT, radius - 2)
	th.set_stylebox("normal", "FormGhost", _pad(none, pad_h, pad_v))
	th.set_stylebox("hover", "FormGhost", _pad(box(field, radius - 2), pad_h, pad_v))
	th.set_stylebox("pressed", "FormGhost", _pad(box(field_hover, radius - 2), pad_h, pad_v))
	th.set_stylebox("disabled", "FormGhost", _pad(none, pad_h, pad_v))
	th.set_stylebox("focus", "FormGhost", ring)
	th.set_color("font_color", "FormGhost", text_dim)
	th.set_color("font_hover_color", "FormGhost", text)
	th.set_color("font_disabled_color", "FormGhost", text_faint)

	th.set_type_variation("FormReset", "FormGhost")
	th.set_color("font_color", "FormReset", accent)
	th.set_color("font_hover_color", "FormReset", accent)
	th.set_font_size("font_size", "FormReset", px(font_small + 1))
	th.set_stylebox("normal", "FormReset", _pad(none, sp(2), px(4.0)))
	th.set_stylebox("hover", "FormReset", _pad(box(Color(accent, 0.14), radius - 2), sp(2), px(4.0)))
	th.set_stylebox("pressed", "FormReset", _pad(box(Color(accent, 0.24), radius - 2), sp(2), px(4.0)))

	th.set_type_variation("FormHeader", "Button")
	var head_pad_v := px(10.0 if not touch else 14.0)
	for state in ["normal", "disabled"]:
		th.set_stylebox(state, "FormHeader", _pad(none, sp(4), head_pad_v))
	th.set_stylebox("hover", "FormHeader", _pad(box(Color(text, 0.05), radius), sp(4), head_pad_v))
	th.set_stylebox("pressed", "FormHeader", _pad(box(Color(text, 0.09), radius), sp(4), head_pad_v))
	th.set_stylebox("focus", "FormHeader", ring)
	th.set_color("font_color", "FormHeader", text)
	th.set_color("font_hover_color", "FormHeader", text)
	th.set_color("font_pressed_color", "FormHeader", text)
	th.set_color("font_focus_color", "FormHeader", text)
	th.set_font("font", "FormHeader", bold())
	th.set_font_size("font_size", "FormHeader", px(font_section))


## The label variations, popup menus and the scroll bar.
func _theme_labels_and_popups(th: Theme) -> void:
	th.set_type_variation("FormCaption", "Label")
	th.set_font_size("font_size", "FormCaption", px(font_small))
	th.set_color("font_color", "FormCaption", text_dim)
	th.set_type_variation("FormName", "Label")
	th.set_font("font", "FormName", bold())
	th.set_type_variation("FormTitle", "Label")
	th.set_font("font", "FormTitle", bold())
	th.set_font_size("font_size", "FormTitle", px(font_title))
	th.set_type_variation("FormError", "Label")
	th.set_font_size("font_size", "FormError", px(font_small + 1))
	th.set_color("font_color", "FormError", danger)
	th.set_type_variation("FormUnit", "Label")
	th.set_font_size("font_size", "FormUnit", px(font_small + 1))
	th.set_color("font_color", "FormUnit", text_dim)

	th.set_stylebox("panel", "PopupMenu", box(card_inner, radius - 2, border, 1, 2))
	th.set_stylebox("hover", "PopupMenu", box(Color(accent, 0.22), radius - 4))
	th.set_stylebox("separator", "PopupMenu", StyleBoxLine.new())
	th.set_color("font_color", "PopupMenu", text)
	th.set_color("font_hover_color", "PopupMenu", text)
	th.set_constant("v_separation", "PopupMenu", px(8.0 if not touch else 14.0))
	th.set_stylebox("panel", "PopupPanel", box(card_inner, radius, border, 1, 2))

	th.set_stylebox("scroll", "VScrollBar", box(Color.TRANSPARENT, 4))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var c := Color(text, 0.16 if state == "grabber" else 0.3)
		var g := box(c, 4)
		g.content_margin_left = px(4.0)
		g.content_margin_right = px(4.0)
		th.set_stylebox(state, "VScrollBar", g)
