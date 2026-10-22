class_name DotFormKeypad
extends Control

## An on-screen keyboard for one LineEdit, so a controller-only player can type: d-pad walks the keys, accept presses, X backspaces, Y types a space, shoulder shifts, Start confirms, cancel restores the text.

signal closed(accepted: bool)

const LETTERS: Array[String] = ["1234567890", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
const SYMBOLS: Array[String] = ["1234567890", "!@#$%^&*()", "-_=+[]{}/\\", ":;'\"<>?.,"]

var tokens: DotFormTokens = DotFormTokens.new()
var target: LineEdit = null
var shifted := false
var symbols := false

var _caret := 0
var _original := ""
var _was_editable := true
var _preview: Label
var _keys: VBoxContainer
var _panel: PanelContainer
var _hint: Label
var _return_focus: Control = null
var _first: Button = null


## Shows the keypad over [param host] for [param edit]; edits land in the box live, so inline validation keeps working.
func open(host: Control, edit: LineEdit, p_tokens: DotFormTokens, numeric: bool = false) -> void:
	tokens = p_tokens
	target = edit
	_original = edit.text
	_return_focus = edit
	_caret = edit.text.length()
	symbols = numeric
	shifted = false
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(self)
	global_position = host.global_position
	size = host.size
	_build()
	_update_preview()
	get_viewport().gui_focus_changed.connect(_on_focus)
	if _first != null:
		_first.grab_focus()


func text() -> String:
	return target.text if target != null else ""


## Types [param s] at the caret.
func type(s: String) -> void:
	if target == null:
		return
	var at := clampi(_caret, 0, target.text.length())
	var t := target.text.insert(at, s)
	if target.max_length > 0 and t.length() > target.max_length:
		return
	target.text = t
	_caret = at + s.length()
	target.caret_column = _caret
	target.text_changed.emit(t)
	if shifted:
		set_shifted(false)
	_update_preview()


func backspace() -> void:
	if target == null:
		return
	var at := clampi(_caret, 0, target.text.length())
	if at == 0:
		return
	var t := target.text.substr(0, at - 1) + target.text.substr(at)
	target.text = t
	_caret = at - 1
	target.caret_column = _caret
	target.text_changed.emit(t)
	_update_preview()


func set_shifted(on: bool) -> void:
	shifted = on
	_rebuild_keys()


func set_symbols(on: bool) -> void:
	symbols = on
	_rebuild_keys()


## Confirms ([param accepted] true) or restores the text found on opening.
func close(accepted: bool) -> void:
	if target == null:
		return
	var edit := target
	target = null
	if not accepted and edit.text != _original:
		edit.text = _original
		edit.text_changed.emit(_original)
	if get_viewport().gui_focus_changed.is_connected(_on_focus):
		get_viewport().gui_focus_changed.disconnect(_on_focus)
	var back := _return_focus
	get_parent().remove_child(self)
	queue_free()
	if back != null and is_instance_valid(back) and back.is_inside_tree():
		back.grab_focus()
	closed.emit(accepted)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _panel_box())
	center.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", tokens.sp(2))
	_panel.add_child(col)

	var shell := PanelContainer.new()
	shell.add_theme_stylebox_override("panel", tokens.box(tokens.field, tokens.radius - 2, tokens.accent, maxi(2, tokens.px(2.0))))
	col.add_child(shell)
	_preview = Label.new()
	_preview.clip_text = true
	_preview.custom_minimum_size.y = tokens.target()
	_preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	shell.add_child(_preview)

	_keys = VBoxContainer.new()
	_keys.add_theme_constant_override("separation", tokens.sp(1))
	col.add_child(_keys)
	_hint = Label.new()
	_hint.theme_type_variation = &"FormCaption"
	_hint.text = "X delete    Y space    LB shift    Start done    B cancel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hint)
	_rebuild_keys()
	var width := minf(size.x - float(tokens.sp(4)), float(tokens.px(620.0)))
	_panel.custom_minimum_size.x = maxf(width, 200.0)


func _panel_box() -> StyleBoxFlat:
	var b := tokens.box(tokens.card, tokens.radius + 2, tokens.border, 1, 3)
	var m := tokens.sp(3)
	b.content_margin_left = m
	b.content_margin_right = m
	b.content_margin_top = m
	b.content_margin_bottom = m
	return b


func _rebuild_keys() -> void:
	if _keys == null:
		return
	var held := ""
	var owner_ := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if owner_ is Button and _keys.is_ancestor_of(owner_):
		held = (owner_ as Button).text.to_lower()
	for c in _keys.get_children():
		_keys.remove_child(c)
		c.queue_free()
	_first = null
	var rows := SYMBOLS if symbols else LETTERS
	for i in rows.size():
		var line := _line()
		if i == rows.size() - 1:
			line.add_child(_action("Shift", func() -> void: set_shifted(not shifted), 1.6, shifted and not symbols))
		for ch in rows[i]:
			var s: String = ch.to_upper() if (shifted and not symbols) else ch
			line.add_child(_key(s))
		if i == rows.size() - 1:
			line.add_child(_action("Del", backspace, 1.6))
	var bottom := _line()
	bottom.add_child(_action("abc" if symbols else "123", func() -> void: set_symbols(not symbols), 1.6))
	bottom.add_child(_action("Space", func() -> void: type(" "), 4.0))
	bottom.add_child(_action("Cancel", func() -> void: close(false), 2.0))
	bottom.add_child(_action("Done", func() -> void: close(true), 2.0, false, true))
	if not is_inside_tree():
		return
	var want := _first
	for b in _keys.find_children("*", "Button", true, false):
		if held != "" and (b as Button).text.to_lower() == held:
			want = b
	if want != null:
		want.grab_focus()


func _line() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", tokens.sp(1))
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_keys.add_child(h)
	return h


func _key(s: String) -> Button:
	var b := Button.new()
	b.text = s
	b.custom_minimum_size = Vector2(tokens.px(30.0), maxf(tokens.target(), float(tokens.px(40.0))))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _cap(tokens.field))
	b.pressed.connect(func() -> void: type(s))
	if _first == null:
		_first = b
	return b


func _action(label: String, fn: Callable, weight: float, lit: bool = false, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(tokens.px(30.0), maxf(tokens.target(), float(tokens.px(40.0))))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = weight
	if primary:
		b.theme_type_variation = &"FormPrimary"
	elif lit:
		b.add_theme_stylebox_override("normal", _cap(Color(tokens.accent, 0.35)))
	else:
		b.add_theme_stylebox_override("normal", _cap(tokens.card_inner))
	b.pressed.connect(fn)
	if _first == null:
		_first = b
	return b


func _cap(fill: Color) -> StyleBoxFlat:
	var b := tokens.box(fill, tokens.radius - 2, tokens.border, 1)
	b.content_margin_top = tokens.px(6.0)
	b.content_margin_bottom = tokens.px(6.0)
	b.content_margin_left = tokens.px(4.0)
	b.content_margin_right = tokens.px(4.0)
	return b


func _update_preview() -> void:
	if _preview == null or target == null:
		return
	var t := target.text
	if target.secret:
		t = "•".repeat(t.length())
	var at := clampi(_caret, 0, t.length())
	_preview.text = t.insert(at, "|")


func _input(event: InputEvent) -> void:
	if target == null:
		return
	var vp := get_viewport()
	if event.is_action_pressed(&"ui_cancel"):
		close(false)
	elif event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_X:
				backspace()
			JOY_BUTTON_Y:
				type(" ")
			JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
				set_shifted(not shifted)
			JOY_BUTTON_START:
				close(true)
			_:
				return
	else:
		return
	vp.set_input_as_handled()


func _on_focus(node: Control) -> void:
	if target == null or node == null or is_ancestor_of(node) or not is_inside_tree():
		return
	if _first != null and _first.is_inside_tree():
		_first.grab_focus.call_deferred()
