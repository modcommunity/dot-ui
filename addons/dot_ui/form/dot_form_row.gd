class_name DotFormRow
extends MarginContainer

## One field of a form: name, description, the editor its type needs, reset-to-default and an inline error.

## [param error] is empty when [param value] is valid; otherwise [param value] is the last good one.
signal edited(key: String, value: Variant, error: String)
signal reset_requested(key: String)
signal undo_requested(key: String)
## A controller pressed accept on a text box; the form decides whether to open its on-screen keyboard.
signal keypad_requested(edit: LineEdit, numeric: bool)

var field: Dictionary = {}
var key := ""
var tokens: DotFormTokens = DotFormTokens.new()

var bar := 0.0:
	set(v):
		bar = v
		queue_redraw()
var _value: Variant = null
var _error := ""
var _modified := false
var _compact := false

var _box: BoxContainer
var _name: Label
var _desc: Label
var _err: Label
var _reset: Button
var _undo: Button
var _actions: HBoxContainer
var _unit: Label
var _slider: DotFormSlider
var _entry: LineEdit
var _toggle: DotFormToggle
var _option: OptionButton
var _picker: ColorPickerButton
var _list: VBoxContainer
var _syncing := false
var _line: HBoxContainer
var _right: VBoxContainer


func build(p_field: Dictionary, p_tokens: DotFormTokens) -> void:
	field = p_field
	key = field["name"]
	tokens = p_tokens
	_value = field["default"]
	add_theme_constant_override("margin_left", tokens.sp(3))
	add_theme_constant_override("margin_right", tokens.sp(3))
	add_theme_constant_override("margin_top", tokens.sp(2))
	add_theme_constant_override("margin_bottom", tokens.sp(2))
	mouse_filter = Control.MOUSE_FILTER_PASS

	_box = BoxContainer.new()
	_box.add_theme_constant_override("separation", tokens.sp(4))
	add_child(_box)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_stretch_ratio = 0.8
	info.add_theme_constant_override("separation", 2)
	_box.add_child(info)
	_name = Label.new()
	_name.theme_type_variation = &"FormName"
	_name.text = field["label"]
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_name)
	_desc = Label.new()
	_desc.theme_type_variation = &"FormCaption"
	_desc.text = field["description"]
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.visible = _desc.text != ""
	info.add_child(_desc)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.2
	right.add_theme_constant_override("separation", 2)
	_box.add_child(right)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", tokens.sp(2))
	right.add_child(line)
	_line = line
	_right = right
	_build_editor(line)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 0)
	_actions.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(_actions)
	_undo = Button.new()
	_undo.theme_type_variation = &"FormReset"
	_undo.text = "Undo"
	_undo.tooltip_text = "Back to the value when this form opened"
	_undo.pressed.connect(func() -> void: undo_requested.emit(key))
	_undo.modulate.a = 0.0
	_undo.focus_mode = Control.FOCUS_NONE
	_undo.disabled = true
	_undo.custom_minimum_size.y = tokens.target()
	_actions.add_child(_undo)
	_reset = Button.new()
	_reset.theme_type_variation = &"FormReset"
	_reset.text = "Reset"
	_reset.tooltip_text = "Back to the default (%s)" % DotFormSchema.display(field, field["default"])
	_reset.pressed.connect(func() -> void: reset_requested.emit(key))
	_reset.modulate.a = 0.0
	_reset.focus_mode = Control.FOCUS_NONE
	_reset.custom_minimum_size.y = tokens.target()
	_actions.add_child(_reset)
	_err = Label.new()
	_err.theme_type_variation = &"FormError"
	_err.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_err.visible = false
	right.add_child(_err)
	set_compact(false)


func _build_editor(line: HBoxContainer) -> void:
	var type: String = field["type"]
	var expand := Control.SIZE_EXPAND_FILL
	if field.has("enum") and type == "string":
		_option = OptionButton.new()
		_option.size_flags_horizontal = expand
		_option.custom_minimum_size.y = tokens.target()
		for opt in field["enum"]:
			_option.add_item(str(opt))
		_option.item_selected.connect(func(i: int) -> void: _emit_value((field["enum"] as Array)[i]))
		line.add_child(_option)
	elif type == "bool":
		_toggle = DotFormToggle.new()
		_toggle.tokens = tokens
		_toggle.toggled.connect(func(on: bool) -> void: _emit_value(on))
		var spacer := Control.new()
		spacer.size_flags_horizontal = expand
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(_toggle)
		line.add_child(spacer)
	elif type == "color":
		_picker = ColorPickerButton.new()
		_picker.custom_minimum_size = Vector2(tokens.px(54.0), tokens.target())
		_picker.edit_alpha = false
		_picker.color_changed.connect(_on_picker)
		line.add_child(_picker)
		_make_entry(line, "#rrggbb")
	elif type == "list":
		_list = VBoxContainer.new()
		_list.size_flags_horizontal = expand
		_list.add_theme_constant_override("separation", tokens.sp(1))
		line.add_child(_list)
	else:
		if field["slider"]:
			_slider = DotFormSlider.new()
			_slider.tokens = tokens
			_slider.min_value = float(field["min"])
			_slider.max_value = float(field["max"])
			_slider.step = float(field["step"])
			_slider.size_flags_horizontal = expand
			_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_slider.value_changed.connect(_on_slider)
			line.add_child(_slider)
		_make_entry(line, "")
		if DotFormSchema.is_numeric(field):
			_unit = Label.new()
			_unit.theme_type_variation = &"FormUnit"
			_unit.text = field["unit"]
			_unit.custom_minimum_size.x = tokens.px(54.0)
			line.add_child(_unit)
		if type == "string" or type == "dict" or type == "any":
			_entry.size_flags_horizontal = expand
			_entry.secret = bool(field.get("secret", false))
			if type != "string":
				_entry.placeholder_text = "JSON"
		elif _slider != null:
			_entry.custom_minimum_size.x = tokens.px(64.0)
			_entry.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		else:
			_entry.size_flags_horizontal = expand
			_entry.alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _make_entry(line: HBoxContainer, placeholder: String) -> void:
	_entry = LineEdit.new()
	_entry.custom_minimum_size.y = tokens.target()
	_entry.placeholder_text = placeholder
	_entry.text_changed.connect(_on_entry_text)
	_entry.focus_exited.connect(_on_entry_blur)
	_entry.text_submitted.connect(func(_t: String) -> void: _on_entry_blur())
	_hook_keypad(_entry, DotFormSchema.is_numeric(field))
	if field["type"] == "color":
		_entry.custom_minimum_size.x = tokens.px(104.0)
		_entry.max_length = 9
	line.add_child(_entry)


func set_compact(on: bool) -> void:
	_compact = on
	_box.vertical = on
	_box.get_child(0).size_flags_stretch_ratio = 1.0 if on else 0.8
	_box.get_child(1).size_flags_stretch_ratio = 1.0 if on else 1.2
	if _actions != null:
		var home: Node = _right if on else _line
		if _actions.get_parent() != home:
			_actions.get_parent().remove_child(_actions)
			home.add_child(_actions)
			if on:
				_right.move_child(_actions, 1)
		_actions.size_flags_horizontal = Control.SIZE_SHRINK_END if on else Control.SIZE_FILL


## Shows [param v] without emitting; the row remembers it as the current value.
func show_value(v: Variant) -> void:
	_syncing = true
	_value = v
	var type: String = field["type"]
	if _option != null:
		_option.select((field["enum"] as Array).find(v))
	elif _toggle != null:
		_toggle.set_pressed_no_signal(bool(v))
	elif _picker != null:
		_picker.color = _as_color(v)
		_entry.text = DotFormSchema.display(field, v)
	elif _list != null:
		_rebuild_list(v as Array)
	else:
		if _slider != null:
			_slider.set_value_no_signal(float(v))
		_entry.text = DotFormSchema.display(field, v)
	_syncing = false
	_set_error("")
	_sync_default_state()


func value() -> Variant:
	return _value


func error() -> String:
	return _error


## Types into the text box the way a person would; returns the resulting error ("" if fine).
func type_text(text: String) -> String:
	if _entry == null:
		return "no text box"
	_entry.text = text
	_on_entry_text(text)
	return _error


func set_modified(on: bool) -> void:
	_modified = on
	tokens.go(self, self, "bar", 1.0 if on else 0.0, 0.2)
	if _undo != null:
		tokens.go(self, _undo, "modulate:a", 1.0 if on else 0.0, 0.14)
		_undo.focus_mode = Control.FOCUS_ALL if on else Control.FOCUS_NONE
		_undo.disabled = not on


func is_modified() -> bool:
	return _modified


func is_default() -> bool:
	return DotValue.same(_value, _normal(field["default"]))


func _normal(v: Variant) -> Variant:
	var r := DotFormSchema.validate(field, v)
	return r.value if r.ok else v


func _sync_default_state() -> void:
	var off := is_default()
	tokens.go(self, _reset, "modulate:a", 0.0 if off else 1.0, 0.14)
	_reset.focus_mode = Control.FOCUS_NONE if off else Control.FOCUS_ALL
	_reset.disabled = off


## True when a search matches the key, label, description or group.
func matches(query: String) -> bool:
	if query == "":
		return true
	var q := query.to_lower()
	for s in [key, str(field["label"]), str(field["description"]), str(field["group"])]:
		if (s as String).to_lower().contains(q):
			return true
	return false


## The control keyboard or gamepad focus lands on first.
func editor() -> Control:
	for c in [_slider, _toggle, _option, _picker, _entry]:
		if c != null:
			return c
	if _list != null and _list.get_child_count() > 0:
		return _item_edit(_item_rows()[0]) if not _item_rows().is_empty() else null
	return null


func _emit_value(v: Variant) -> void:
	if _syncing:
		return
	var r := DotFormSchema.validate(field, v)
	if r.ok:
		_value = r.value
		_set_error("")
	else:
		_set_error(r.error.message)
	_sync_default_state()
	edited.emit(key, _value, _error)


func _on_slider(v: float) -> void:
	var out: Variant = int(round(v)) if field["type"] == "int" else v
	if _entry != null:
		_entry.text = DotFormSchema.display(field, out)
	_emit_value(out)


func _on_entry_text(text: String) -> void:
	if _syncing:
		return
	var r := DotFormSchema.parse_text(field, text)
	if r.ok:
		_value = r.value
		_set_error("")
		if _slider != null:
			_slider.set_value_no_signal(float(_value))
		if _picker != null:
			_picker.color = _as_color(_value)
	else:
		_set_error(r.error.message)
	_sync_default_state()
	edited.emit(key, _value, _error)


func _on_entry_blur() -> void:
	if _error == "" and _entry != null and not _syncing:
		_entry.text = DotFormSchema.display(field, _value)


func _on_picker(c: Color) -> void:
	_entry.text = "#" + c.to_html(false)
	_on_entry_text(_entry.text)


func _as_color(v: Variant) -> Color:
	return v if v is Color else Color.from_string(str(v), Color.WHITE)


func _hook_keypad(e: LineEdit, numeric: bool) -> void:
	e.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventJoypadButton and ev.pressed and (ev.button_index == JOY_BUTTON_A or ev.is_action(&"ui_accept")) and e.editable:
			e.accept_event()
			keypad_requested.emit(e, numeric))


func _item_rows() -> Array[HBoxContainer]:
	var out: Array[HBoxContainer] = []
	for c in _list.get_children():
		if c is HBoxContainer:
			out.append(c)
	return out


func _item_edit(row: HBoxContainer) -> LineEdit:
	return row.get_meta("edit") as LineEdit


func _rebuild_list(items: Array) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var reorder: bool = field.get("reorder", true)
	var numeric_items: bool = field.get("items", "string") == "int" or field.get("items", "string") == "float"
	for i in items.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", tokens.sp(1))
		var e := LineEdit.new()
		e.custom_minimum_size.y = tokens.target()
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		e.text = DotFormSchema.display({"type": field.get("items", "string")}, items[i])
		e.text_changed.connect(func(_t: String) -> void: _list_changed())
		e.gui_input.connect(func(ev: InputEvent) -> void:
			if reorder and ev is InputEventKey and ev.pressed and ev.alt_pressed and (ev.keycode == KEY_UP or ev.keycode == KEY_DOWN):
				e.accept_event()
				move_item(row.get_index(), row.get_index() + (-1 if ev.keycode == KEY_UP else 1), "edit"))
		_hook_keypad(e, numeric_items)
		row.set_meta("edit", e)
		if reorder:
			var grip := Control.new()
			grip.custom_minimum_size = Vector2(tokens.px(18.0), tokens.target())
			grip.mouse_default_cursor_shape = Control.CURSOR_DRAG
			grip.tooltip_text = "Drag to reorder"
			grip.draw.connect(_draw_grip.bind(grip))
			grip.set_drag_forwarding(_drag_item.bind(row), Callable(), Callable())
			row.add_child(grip)
			for c in [row, e]:
				(c as Control).set_drag_forwarding(Callable(), _can_drop_item.bind(row), _drop_item.bind(row))
		row.add_child(e)
		if reorder:
			row.add_child(_step_button("▲", "Move up", row, -1))
			row.add_child(_step_button("▼", "Move down", row, 1))
		var rm := Button.new()
		rm.theme_type_variation = &"FormGhost"
		rm.text = "×"
		rm.tooltip_text = "Remove"
		rm.custom_minimum_size = Vector2(tokens.target(), tokens.target())
		rm.pressed.connect(func() -> void:
			row.get_parent().remove_child(row)
			row.queue_free()
			_sync_list_buttons()
			_list_changed())
		row.add_child(rm)
		_list.add_child(row)
	var add := Button.new()
	add.theme_type_variation = &"FormGhost"
	add.text = "+ Add"
	add.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add.pressed.connect(_add_item)
	_list.add_child(add)
	_sync_list_buttons()


func _step_button(glyph: String, tip: String, row: HBoxContainer, dir: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"FormGhost"
	b.text = glyph
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(tokens.target(), tokens.target())
	b.set_meta("dir", dir)
	b.pressed.connect(func() -> void: move_item(row.get_index(), row.get_index() + dir, "up" if dir < 0 else "down"))
	return b


func _draw_grip(grip: Control) -> void:
	var r := maxf(1.5, tokens.px(1.6))
	var gap := float(tokens.px(6.0))
	var mid := grip.size * 0.5
	for dx in [-0.5, 0.5]:
		for dy in [-1.0, 0.0, 1.0]:
			grip.draw_circle(mid + Vector2(dx * gap * 0.8, dy * gap), r, tokens.text_faint)


## Up and down are disabled at the ends of the list.
func _sync_list_buttons() -> void:
	var rows := _item_rows()
	for i in rows.size():
		for c in rows[i].get_children():
			if c is Button and c.has_meta("dir"):
				c.disabled = (i == 0 and int(c.get_meta("dir")) < 0) or (i == rows.size() - 1 and int(c.get_meta("dir")) > 0)


## Moves list item [param from] to position [param to] (clamped), as an edit. [param focus] is "up", "down" or "edit": what keeps the controller's focus afterwards.
func move_item(from: int, to: int, focus: String = "") -> bool:
	if _list == null:
		return false
	var rows := _item_rows()
	to = clampi(to, 0, rows.size() - 1)
	if from < 0 or from >= rows.size() or from == to:
		return false
	var row := rows[from]
	_list.move_child(row, to)
	_sync_list_buttons()
	_list_changed()
	if focus != "":
		var want: Control = _item_edit(row)
		if focus != "edit":
			for c in row.get_children():
				if c is Button and c.has_meta("dir") and not c.disabled:
					if (int(c.get_meta("dir")) < 0) == (focus == "up") or want is LineEdit:
						want = c
		if want.is_inside_tree():
			want.grab_focus()
	return true


func _drag_item(_at: Vector2, row: HBoxContainer) -> Variant:
	if row.get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = "  " + _item_edit(row).text
		preview.add_theme_stylebox_override("normal", tokens.box(tokens.card_inner, tokens.radius - 2, tokens.accent, 1, 2))
		(row.get_child(0) as Control).set_drag_preview(preview)
	return {"dot_form_list": get_instance_id(), "from": row.get_index()}


func _can_drop_item(_at: Vector2, data: Variant, _row: HBoxContainer) -> bool:
	return data is Dictionary and data.get("dot_form_list", 0) == get_instance_id()


func _drop_item(_at: Vector2, data: Variant, row: HBoxContainer) -> void:
	move_item(int(data["from"]), row.get_index())


func _add_item() -> void:
	var items := _list_texts()
	items.append("")
	_value = items
	_rebuild_list(items)
	var rows := _item_rows()
	_item_edit(rows[rows.size() - 1]).grab_focus()
	_list_changed()


func _list_texts() -> Array:
	var out := []
	for r in _item_rows():
		out.append(_item_edit(r).text)
	return out


func _list_changed() -> void:
	if _syncing:
		return
	var item_field := {"type": str(field.get("items", "string"))}
	var parsed := []
	var bad := ""
	for t in _list_texts():
		var r := DotFormSchema.parse_text(item_field, str(t))
		if r.ok:
			parsed.append(r.value)
		elif bad == "":
			bad = "Item %d: %s" % [parsed.size() + 1, r.error.message]
			parsed.append(t)
	if bad == "":
		var whole := DotFormSchema.validate(field, parsed)
		if whole.ok:
			_value = whole.value
			_set_error("")
		else:
			_set_error(whole.error.message)
	else:
		_set_error(bad)
	_sync_default_state()
	edited.emit(key, _value, _error)


func _set_error(message: String) -> void:
	var changed := message != _error
	_error = message
	if _err == null:
		return
	_err.text = message
	_err.visible = message != ""
	if changed and message != "":
		_err.modulate.a = 0.0
		tokens.go(self, _err, "modulate:a", 1.0, 0.18)
	for e in [_entry]:
		if e == null:
			continue
		if message != "":
			var b := tokens.box(tokens.field, tokens.radius - 2, tokens.danger, maxi(2, tokens.px(2.0)))
			b.content_margin_left = tokens.sp(3)
			b.content_margin_right = tokens.sp(3)
			b.content_margin_top = tokens.px(6.0 if not tokens.touch else 10.0)
			b.content_margin_bottom = b.content_margin_top
			e.add_theme_stylebox_override("normal", b)
		else:
			e.remove_theme_stylebox_override("normal")


func _draw() -> void:
	if bar <= 0.001:
		return
	var tint := tokens.box(Color(tokens.accent, 0.09 * bar), tokens.radius - 2)
	draw_style_box(tint, Rect2(Vector2.ZERO, size))
	var h := size.y * 0.6
	draw_style_box(tokens.box(Color(tokens.accent, bar), 4), Rect2(0, (size.y - h) * 0.5, maxf(3.0, float(tokens.px(3.0))), h))
