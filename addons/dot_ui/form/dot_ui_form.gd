class_name DotUiForm
extends PanelContainer

## A form built from a profile schema: grouped cards, a widget per type, search, per-key reset, dirty state with apply and revert.
##
## [codeblock]
## var form := DotUiForm.new()
## add_child(form)
## var res := form.build(schema, current_values)   # DotResult
## form.applied.connect(func(changes): save(changes))
## [/codeblock]

signal value_changed(key: String, value: Variant)
signal key_reset(key: String)
signal dirty_changed(dirty: bool)
signal validation_changed(errors: Dictionary)
## The keys that changed since the last apply, with their new values.
signal applied(changes: Dictionary)
signal reverted()

## Shown above the search box.
@export var title := ""
## Below this width the rows stack and targets grow to touch size.
@export var compact_below := 560.0
## False leaves out the title, search and Apply bar and lets the cards take their full height, for a host (such as [DotSettingsPanel]) that scrolls and applies itself.
@export var chrome := true
## Group names are split on this to nest cards ("Damage/Falloff").
@export var group_separator := "/"

## A controller's accept on a text box opens an on-screen keyboard; false leaves the box alone.
@export var gamepad_entry := true

var tokens: DotFormTokens = DotFormTokens.dark()

var _schema: Array[Dictionary] = []
var _fields := {}
var _rows := {}
var _groups: Array[DotFormGroup] = []
var _group_rows := {}
var _group_kids := {}
var _tops: Array[DotFormGroup] = []
var _baseline := {}
var _current := {}
var _errors := {}
var _filter := ""
var _dirty := false
var _compact := false
var _built_touch := false
var _rebuild_queued := false

var _search: LineEdit
var _title_label: Label
var _sub: Label
var _scroll: ScrollContainer
var _content: VBoxContainer
var _empty: Label
var _status: Label
var _revert_btn: Button
var _apply_btn: Button
var _shell: VBoxContainer


func _init() -> void:
	resized.connect(_on_resized)


## Builds the widgets. [param values] are the current values; any key it lacks takes the schema default.
func build(schema: Array, values: Dictionary = {}) -> DotResult:
	var norm := DotFormSchema.normalize(schema)
	if not norm.ok:
		return norm.wrap("DotUiForm.build")
	_schema.clear()
	for f in norm.value:
		_schema.append(f)
	_fields.clear()
	for f in _schema:
		_fields[f["name"]] = f
	_baseline.clear()
	_current.clear()
	_errors.clear()
	var loaded := _load_values(values)
	_construct()
	_refresh_state()
	return loaded


## Replaces the baseline (what the server or file holds now); nothing is dirty afterwards.
func set_values(values: Dictionary) -> DotResult:
	var loaded := _load_values(values)
	for key in _rows:
		(_rows[key] as DotFormRow).show_value(_current[key])
	_errors.clear()
	_refresh_state()
	return loaded


## Every key's present value, edits included.
func values() -> Dictionary:
	return _current.duplicate(true)


## The keys that differ from the baseline.
func changes() -> Dictionary:
	var out := {}
	for key in _current:
		if not DotValue.same(_current[key], _baseline[key]):
			out[key] = _current[key]
	return out


func is_dirty() -> bool:
	return _dirty


func has_errors() -> bool:
	return not _errors.is_empty()


## Key to message for every field that currently fails validation.
func errors() -> Dictionary:
	return _errors.duplicate()


func row(key: String) -> DotFormRow:
	return _rows.get(key)


## Sets a value as an edit; fails with [constant DotError.CODE_INVALID] when it does not validate.
func set_value(key: String, value: Variant) -> DotResult:
	if not _fields.has(key):
		return DotResult.fail(DotError.CODE_INVALID, "No field '%s'." % key)
	var r := DotFormSchema.validate(_fields[key], value)
	if not r.ok:
		return r.wrap(key)
	(_rows[key] as DotFormRow).show_value(r.value)
	_accept(key, r.value, "")
	return r


## Puts one key back to its schema default.
func reset_key(key: String) -> void:
	if not _fields.has(key):
		return
	var def: Variant = (_rows[key] as DotFormRow)._normal(_fields[key]["default"])
	(_rows[key] as DotFormRow).show_value(def)
	_accept(key, def, "")
	key_reset.emit(key)


## Keeps the edits as the new baseline and emits [signal applied]; fails while any field is invalid.
func apply() -> DotResult:
	if not _errors.is_empty():
		return DotResult.fail(DotError.CODE_INVALID, "%d field(s) need fixing before apply." % _errors.size())
	var done := changes()
	_baseline = _current.duplicate(true)
	_refresh_state()
	applied.emit(done)
	return DotResult.success(done)


## Drops every edit back to the baseline.
func revert() -> void:
	_current = _baseline.duplicate(true)
	_errors.clear()
	for key in _rows:
		(_rows[key] as DotFormRow).show_value(_current[key])
	_refresh_state()
	validation_changed.emit(errors())
	reverted.emit()


## Hides rows and cards that do not match; empty shows everything.
func set_filter(text: String) -> void:
	_filter = text.strip_edges()
	if _search != null and _search.text != text:
		_search.text = text
	var any := false
	for g in _tops:
		any = _filter_group(g) or any
	_empty.visible = not any
	_empty.text = "Nothing matches \"%s\"" % _filter


func filter() -> String:
	return _filter


func visible_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for f in _schema:
		var r: DotFormRow = _rows[f["name"]]
		if r.is_visible_in_tree() or (r.visible and _group_shown(f["group"])):
			out.append(f["name"])
	return out


func groups() -> Array[DotFormGroup]:
	return _groups


func focus_first() -> bool:
	for f in _schema:
		var r: DotFormRow = _rows[f["name"]]
		if r.visible and _group_shown(f["group"]) and r.editor() != null:
			r.editor().grab_focus()
			return true
	return false


func focus_key(key: String) -> bool:
	var r: DotFormRow = _rows.get(key)
	if r == null or r.editor() == null:
		return false
	r.editor().grab_focus()
	return true


## Opens the on-screen keyboard for [param edit] (a text box in this form); null when one is already open.
func open_keypad(edit: LineEdit, numeric: bool = false) -> DotFormKeypad:
	if keypad() != null:
		return null
	var pad := DotFormKeypad.new()
	pad.name = "Keypad"
	pad.open(self, edit, tokens, numeric)
	return pad


## The open on-screen keyboard, or null.
func keypad() -> DotFormKeypad:
	for c in get_children():
		if c is DotFormKeypad:
			return c
	return null


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


func search_box() -> LineEdit:
	return _search


func apply_button() -> Button:
	return _apply_btn


func revert_button() -> Button:
	return _revert_btn


## Swaps the look; rebuilds the widgets and keeps every edit.
func set_tokens(t: DotFormTokens) -> void:
	tokens = t
	_rebuild_now()


func describe() -> String:
	return "DotUiForm: %d fields, %d changed, %d invalid, filter '%s'" % [_schema.size(), changes().size(), _errors.size(), _filter]


func _load_values(values: Dictionary) -> DotResult:
	var problems := PackedStringArray()
	for f in _schema:
		var key: String = f["name"]
		var v: Variant = values.get(key, f["default"])
		var r := DotFormSchema.validate(f, v)
		if r.ok:
			_baseline[key] = r.value
		else:
			problems.append("%s: %s" % [key, r.error.message])
			var d := DotFormSchema.validate(f, f["default"])
			_baseline[key] = d.value if d.ok else f["default"]
	for key in values:
		if not _fields.has(key):
			problems.append("%s: not in the schema" % str(key))
	_current = _baseline.duplicate(true)
	if problems.is_empty():
		return DotResult.success(null)
	return DotResult.fail(DotError.CODE_INVALID, "; ".join(problems))


func _construct() -> void:
	_rows.clear()
	_groups.clear()
	_group_rows.clear()
	_group_kids.clear()
	_tops.clear()
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if size.x > 0.0:
		_compact = size.x < compact_below
	tokens.touch = _compact or DisplayServer.is_touchscreen_available()
	_built_touch = tokens.touch
	theme = tokens.build_theme()
	add_theme_stylebox_override("panel", tokens.box(tokens.bg, 0))

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	add_child(outer)
	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, tokens.sp(4))
	margin.add_theme_constant_override("margin_bottom", 0)
	outer.add_child(margin)
	_shell = VBoxContainer.new()
	_shell.add_theme_constant_override("separation", tokens.sp(3))
	margin.add_child(_shell)

	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	_shell.add_child(head)
	_title_label = Label.new()
	_title_label.theme_type_variation = &"FormTitle"
	_title_label.text = title
	_title_label.visible = title != ""
	head.add_child(_title_label)
	_sub = Label.new()
	_sub.theme_type_variation = &"FormCaption"
	head.add_child(_sub)

	_search = LineEdit.new()
	_search.placeholder_text = "Search settings"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = tokens.target()
	_search.text_changed.connect(set_filter)
	_search.gui_input.connect(_on_search_input)
	_shell.add_child(_search)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	if not chrome:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.size_flags_vertical = Control.SIZE_FILL
		head.visible = false
		_search.visible = false
	_shell.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", tokens.sp(3))
	_scroll.add_child(_content)

	var by_path := {}
	for f in _schema:
		var parent := _ensure_group(str(f["group"]), by_path)
		var r := DotFormRow.new()
		r.build(f, tokens)
		r.show_value(_current[f["name"]])
		r.edited.connect(_on_row_edited)
		r.reset_requested.connect(reset_key)
		r.keypad_requested.connect(func(edit: LineEdit, numeric: bool) -> void:
			if gamepad_entry:
				open_keypad(edit, numeric))
		_rows[f["name"]] = r
		parent.add_row(r)
		(_group_rows[parent] as Array).append(r)
	_empty = Label.new()
	_empty.theme_type_variation = &"FormCaption"
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.visible = false
	_content.add_child(_empty)
	var gap := Control.new()
	gap.custom_minimum_size.y = tokens.sp(2)
	_content.add_child(gap)

	var footer := PanelContainer.new()
	var fsb := tokens.box(tokens.card, 0, tokens.border, 0, 2)
	fsb.border_width_top = 1
	fsb.border_color = tokens.border
	fsb.content_margin_left = tokens.sp(4)
	fsb.content_margin_right = tokens.sp(4)
	fsb.content_margin_top = tokens.sp(3)
	fsb.content_margin_bottom = tokens.sp(3)
	footer.add_theme_stylebox_override("panel", fsb)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", tokens.sp(2))
	footer.add_child(bar)
	_status = Label.new()
	_status.theme_type_variation = &"FormCaption"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_status)
	_revert_btn = Button.new()
	_revert_btn.theme_type_variation = &"FormGhost"
	_revert_btn.text = "Revert"
	_revert_btn.pressed.connect(revert)
	bar.add_child(_revert_btn)
	_apply_btn = Button.new()
	_apply_btn.theme_type_variation = &"FormPrimary"
	_apply_btn.text = "Apply"
	_apply_btn.custom_minimum_size.y = tokens.target()
	_apply_btn.pressed.connect(func() -> void: apply())
	bar.add_child(_apply_btn)
	footer.visible = chrome
	outer.add_child(footer)
	_apply_compact()
	if _filter != "":
		set_filter(_filter)


func _ensure_group(path: String, made: Dictionary) -> DotFormGroup:
	if made.has(path):
		return made[path]
	var g := DotFormGroup.new()
	var parts := path.split(group_separator, false) if path != "" else PackedStringArray()
	var depth := maxi(0, parts.size() - 1)
	g.build(parts[parts.size() - 1] if not parts.is_empty() else "", path, depth, tokens)
	g.toggled.connect(func(_o: bool) -> void: pass)
	_groups.append(g)
	_group_rows[g] = []
	_group_kids[g] = []
	made[path] = g
	if parts.size() <= 1:
		_content.add_child(g)
		_tops.append(g)
	else:
		var parent_path := group_separator.join(parts.slice(0, parts.size() - 1))
		var parent := _ensure_group(parent_path, made)
		parent.add_group(g)
		(_group_kids[parent] as Array).append(g)
	return g


func _filter_group(g: DotFormGroup) -> bool:
	var shown := false
	for r in _group_rows[g]:
		var m := (r as DotFormRow).matches(_filter)
		(r as DotFormRow).visible = m
		shown = shown or m
	for k in _group_kids[g]:
		shown = _filter_group(k) or shown
	g.visible = shown
	g.set_forced(_filter != "")
	return shown


func _group_shown(path: String) -> bool:
	for g in _groups:
		if g.path == path:
			return g.visible
	return true


func _on_row_edited(key: String, value: Variant, error: String) -> void:
	_accept(key, value, error)


func _accept(key: String, value: Variant, error: String) -> void:
	var had := not _errors.is_empty()
	if error == "":
		var changed := not DotValue.same(_current.get(key), value)
		_current[key] = value
		_errors.erase(key)
		if changed:
			value_changed.emit(key, value)
	else:
		_errors[key] = error
	_refresh_state()
	if had or not _errors.is_empty():
		validation_changed.emit(errors())


func _refresh_state() -> void:
	var ch := changes()
	for key in _rows:
		(_rows[key] as DotFormRow).set_modified(ch.has(key) or _errors.has(key))
	for g in _groups:
		g.set_badge(_count_changed(g, ch))
	var now := not ch.is_empty() or not _errors.is_empty()
	var off := 0
	for f in _schema:
		if not DotValue.same(_current[f["name"]], (_rows[f["name"]] as DotFormRow)._normal(f["default"])):
			off += 1
	_sub.text = "%d settings, %d differ from default" % [_schema.size(), off]
	_revert_btn.disabled = not now
	_apply_btn.disabled = not now or not _errors.is_empty()
	if not _errors.is_empty():
		_status.text = "%d invalid, fix to apply" % _errors.size()
		_status.add_theme_color_override("font_color", tokens.danger)
	elif not ch.is_empty():
		_status.text = "%d unsaved change%s" % [ch.size(), "" if ch.size() == 1 else "s"]
		_status.add_theme_color_override("font_color", tokens.accent)
	else:
		_status.text = "All changes applied"
		_status.add_theme_color_override("font_color", tokens.text_dim)
	if now != _dirty:
		_dirty = now
		dirty_changed.emit(now)


func _count_changed(g: DotFormGroup, ch: Dictionary) -> int:
	var n := 0
	for r in _group_rows[g]:
		if ch.has((r as DotFormRow).key):
			n += 1
	for k in _group_kids[g]:
		n += _count_changed(k, ch)
	return n


func _on_search_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _search.text != "":
		set_filter("")
		_search.accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F and (event.ctrl_pressed or event.meta_pressed):
		focus_search()
		accept_event()


func _on_resized() -> void:
	if _shell == null:
		return
	var compact := size.x < compact_below
	if compact != _compact:
		_compact = compact
		_apply_compact()
		var want := compact or DisplayServer.is_touchscreen_available()
		if want != _built_touch and not _rebuild_queued:
			_rebuild_queued = true
			_rebuild_now.call_deferred()


func _apply_compact() -> void:
	for key in _rows:
		(_rows[key] as DotFormRow).set_compact(_compact)


func _rebuild_now() -> void:
	_rebuild_queued = false
	var keep := _current.duplicate(true)
	var errs := _errors.duplicate()
	_construct()
	for key in _rows:
		(_rows[key] as DotFormRow).show_value(keep[key])
	_current = keep
	_errors = errs
	_refresh_state()
