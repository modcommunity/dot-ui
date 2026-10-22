class_name DotFormGroup
extends PanelContainer

## A collapsible rounded card holding rows and nested cards; the body eases open and shut.

signal toggled(open: bool)

var tokens: DotFormTokens = DotFormTokens.new()
var title := ""
var path := ""
var depth := 0
var open := true
var forced := false
## 0 (shut) to 1 (open): the visible fraction of the body.
var reveal := 1.0:
	set(v):
		reveal = v
		_layout()
var chev := 1.0:
	set(v):
		chev = v
		if _chev != null:
			_chev.queue_redraw()

var _header: Button
var _chev: Control
var _badge: Label
var _clip: Control
var _body: VBoxContainer


func build(p_title: String, p_path: String, p_depth: int, p_tokens: DotFormTokens) -> void:
	title = p_title
	path = p_path
	depth = p_depth
	tokens = p_tokens
	var inner := depth > 0
	var sb := tokens.box(tokens.card_inner if inner else tokens.card, tokens.radius + (0 if inner else 4), tokens.border, 1, 0 if inner else 1)
	sb.content_margin_left = tokens.sp(2)
	sb.content_margin_right = tokens.sp(2)
	sb.content_margin_top = tokens.sp(2) if title != "" else tokens.sp(3)
	sb.content_margin_bottom = tokens.sp(3)
	add_theme_stylebox_override("panel", sb)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	if title != "":
		_header = Button.new()
		_header.theme_type_variation = &"FormHeader"
		_header.text = title
		_header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_header.toggle_mode = false
		_header.pressed.connect(func() -> void: set_open(not open))
		_header.resized.connect(_place_header_parts)
		root.add_child(_header)
		_chev = Control.new()
		_chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_chev.size = Vector2(tokens.px(14.0), tokens.px(14.0))
		_chev.draw.connect(_draw_chevron)
		_header.add_child(_chev)
		_badge = Label.new()
		_badge.theme_type_variation = &"FormCaption"
		_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_badge.visible = false
		_header.add_child(_badge)

	_clip = Control.new()
	_clip.clip_contents = true
	_clip.resized.connect(_layout)
	root.add_child(_clip)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	_body.minimum_size_changed.connect(_layout)
	_clip.add_child(_body)
	_body.add_theme_constant_override("separation", tokens.px(2.0))


func add_row(row: Control) -> void:
	_body.add_child(row)


func add_group(g: DotFormGroup) -> void:
	g.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_body.add_child(g)


func body() -> VBoxContainer:
	return _body


func set_open(on: bool, animated: bool = true) -> void:
	open = on
	_update_reveal(animated)
	toggled.emit(on)


## Search opens a shut card without forgetting that it was shut.
func set_forced(on: bool) -> void:
	if forced == on:
		return
	forced = on
	_update_reveal(false)


func is_shown_open() -> bool:
	return open or forced


func set_badge(count: int) -> void:
	if _badge == null:
		return
	_badge.visible = count > 0
	_badge.text = "%d changed" % count
	_badge.add_theme_color_override("font_color", tokens.accent)
	_place_header_parts()


func _update_reveal(animated: bool) -> void:
	var to := 1.0 if is_shown_open() else 0.0
	if animated:
		tokens.go(self, self, "reveal", to, 0.22)
		tokens.go(self, self, "chev", to, 0.22)
	else:
		reveal = to
		chev = to


func _layout() -> void:
	if _clip == null:
		return
	var h := _body.get_combined_minimum_size().y
	_clip.custom_minimum_size.y = h * reveal
	_clip.visible = reveal > 0.002
	_body.position = Vector2.ZERO
	_body.size = Vector2(_clip.size.x, h)
	_body.modulate.a = clampf(reveal * 1.4, 0.0, 1.0)


func _place_header_parts() -> void:
	if _header == null:
		return
	var w := _header.size.x
	var h := _header.size.y
	_chev.position = Vector2(w - tokens.sp(4) - _chev.size.x, (h - _chev.size.y) * 0.5)
	_badge.position = Vector2(_chev.position.x - tokens.sp(3) - _badge.get_minimum_size().x, (h - _badge.get_minimum_size().y) * 0.5)


func _draw_chevron() -> void:
	var s := _chev.size.x
	var c := tokens.text_dim
	var a := Vector2(s * 0.22, s * 0.38)
	var b := Vector2(s * 0.5, s * 0.66)
	var d := Vector2(s * 0.78, s * 0.38)
	_chev.draw_set_transform(Vector2(s * 0.5, s * 0.5), -PI * 0.5 * (1.0 - chev), Vector2.ONE)
	var o := Vector2(s * 0.5, s * 0.5)
	_chev.draw_polyline(PackedVector2Array([a - o, b - o, d - o]), c, float(tokens.px(2.0)), true)
