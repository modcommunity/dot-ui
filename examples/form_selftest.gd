extends Node

## The form kit, offline and headless: schema, widget per type, validation, reset, search, dirty, navigation.
##
## godot --headless --path . res://examples/form_selftest.tscn

const CHECKS := 111
const SECTIONS := 9

var _passed := 0
var _failed := 0
var _entered := 0
var _completed := 0
var form: DotUiForm = null


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-ui form self-test")
	_test_schema()
	await _test_widgets()
	await _test_validation()
	await _test_reset()
	await _test_search()
	await _test_dirty()
	await _test_navigation()
	await _test_layout()
	await _test_bad_input()
	print("")
	print("%d sections of %d, %d checks of %d, %d failed" % [_completed, SECTIONS, _passed + _failed, CHECKS, _failed])
	var ok := _failed == 0 and _completed == SECTIONS and _passed + _failed == CHECKS
	get_tree().quit(0 if ok else 1)


func _check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _section(title: String) -> void:
	_entered += 1
	print("- " + title)


func _fresh(values: Dictionary = {}) -> DotUiForm:
	if form != null:
		form.queue_free()
		await get_tree().process_frame
	form = DotUiForm.new()
	form.custom_minimum_size = Vector2(800, 600)
	form.size = Vector2(800, 600)
	add_child(form)
	form.tokens.animate = false
	var res := form.build(preload("res://examples/form_demo.gd").weapon_schema(), values)
	_check(res.ok, "demo schema builds")
	await get_tree().process_frame
	return form


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _test_schema() -> void:
	_section("schema")
	var F := DotProfileSet.field
	var norm := DotFormSchema.normalize([
		F.call("max_health", "int", 100, {"min": 1, "max": 500, "unit": "hp"}),
		F.call("mode", "string", "a", {"enum": ["a", "b"]}),
		F.call("big", "int", 5, {"min": 0, "max": 1000000}),
	])
	_check(norm.ok, "normalize accepts profile fields")
	var f: Array = norm.value
	_check(f[0]["label"] == "Max health", "label is prettified from the name")
	_check(f[0]["slider"] and not f[2]["slider"], "a huge span gets no slider")
	_check(DotFormSchema.normalize([{"name": "x", "type": "wat"}]).error.code == DotError.CODE_INVALID, "unknown type is invalid")
	_check(not DotFormSchema.normalize([{"name": "x", "type": "int"}, {"name": "x", "type": "int"}]).ok, "duplicate name fails")
	_check(not DotFormSchema.normalize([5]).ok, "non-dictionary entry fails")
	var health: Dictionary = f[0]
	_check(DotFormSchema.validate(health, 50).ok, "in range passes")
	_check(not DotFormSchema.validate(health, 0).ok, "below min fails")
	_check(not DotFormSchema.validate(health, 501).ok, "above max fails")
	_check(not DotFormSchema.validate(health, 2.5).ok, "fraction in an int fails")
	_check(DotFormSchema.parse_text(health, " 42 ").value == 42, "text parses to int")
	_check(not DotFormSchema.parse_text(health, "4x").ok, "garbage text fails")
	_check(not DotFormSchema.validate(f[1], "z").ok, "value outside enum fails")
	var custom := {"type": "int", "validator": func(v: int) -> String: return "even only" if v % 2 == 1 else ""}
	_check(DotFormSchema.validate(custom, 3).error.message == "even only", "custom validator message")
	_check(DotFormSchema.validate(custom, 4).ok, "custom validator passes")
	_check(DotFormSchema.parse_text({"type": "dict"}, "{\"a\": 1}").value["a"] == 1, "json text parses")
	_check(not DotFormSchema.parse_text({"type": "dict"}, "{oops").ok, "bad json fails")
	_done()


func _test_widgets() -> void:
	_section("a widget per type")
	await _fresh()
	_check(form.row("damage").editor() is DotFormSlider, "ranged float is a slider")
	_check(form.row("magazine").editor() is DotFormSlider, "ranged int is a slider")
	_check(form.row("reserve").editor() is LineEdit, "slider:false is a number field")
	_check(form.row("automatic").editor() is DotFormToggle, "bool is a toggle")
	_check(form.row("rarity").editor() is OptionButton, "enum is a dropdown")
	_check(form.row("tint").editor() is ColorPickerButton, "color is a picker")
	_check(form.row("name").editor() is LineEdit, "string is a text field")
	_check(form.row("extra").editor() is LineEdit, "dict is a JSON field")
	_check(form.row("tags").editor() is LineEdit, "list is rows of text fields")
	_check((form.row("rarity").editor() as OptionButton).item_count == 4, "dropdown has every enum value")
	_check(form.row("damage")._unit.text == "hp", "unit is shown")
	_check(form.row("damage")._desc.text != "", "description is shown")
	_check(form.groups().size() == 7, "groups are cards, nested one included (%d)" % form.groups().size())
	var nested := false
	for g in form.groups():
		nested = nested or (g.depth == 1 and g.title == "Falloff")
	_check(nested, "Damage/Falloff nests")
	_check(form.row("damage").size.y > 0.0 and form.row("damage").size.x > 100.0, "a row has a real size")
	var tog: DotFormToggle = form.row("automatic").editor()
	var seen := []
	form.value_changed.connect(func(k: String, v: Variant) -> void: seen.append([k, v]))
	tog.flip()
	_check(seen == [["automatic", true]], "a toggle edit emits value_changed")
	_check(form.values()["automatic"] == true, "and shows in values()")
	_done()


func _test_validation() -> void:
	_section("inline validation")
	await _fresh()
	var r := form.row("magazine")
	_check(r.type_text("500") != "", "out of range typed text is an error")
	_check(r._err.visible and r._err.text.contains("at most"), "the message shows under the field")
	_check(form.has_errors() and form.errors().has("magazine"), "the form knows")
	_check(form.values()["magazine"] == 12, "an invalid entry never reaches values()")
	_check(form.apply_button().disabled, "Apply is disabled while invalid")
	_check(not form.apply().ok and form.apply().error.code == DotError.CODE_INVALID, "apply() fails with CODE_INVALID")
	_check(r.type_text("20") == "", "a valid value clears the error")
	_check(not form.has_errors() and form.values()["magazine"] == 20, "and is accepted")
	_check(form.row("name").type_text("") == "Required.", "required string")
	_check(form.set_value("damage", 9999.0).error.code == DotError.CODE_INVALID, "set_value rejects out of range")
	_check(not form.set_value("nope", 1).ok, "set_value rejects unknown key")
	_check(form.row("extra").type_text("{bad") != "", "bad JSON flags the field")
	_check(form.row("extra").type_text("{\"a\": 2}") == "", "good JSON clears it")
	var res := form.set_values({"damage": 9999.0, "ghost": 1})
	_check(not res.ok and res.error.message.contains("ghost") and res.error.message.contains("damage"), "set_values reports every problem")
	_done()


func _test_reset() -> void:
	_section("reset to default")
	await _fresh({"damage": 40.0})
	_check(form.row("damage")._reset.disabled == false, "a non-default row offers reset")
	_check(form.row("spread")._reset.disabled, "a default row does not")
	form.set_value("fire_rate", 12.0)
	var reset := []
	form.key_reset.connect(func(k: String) -> void: reset.append(k))
	form.reset_key("fire_rate")
	_check(form.values()["fire_rate"] == 6.0 and reset == ["fire_rate"], "reset_key restores the default and signals")
	form.row("damage")._reset.pressed.emit()
	_check(form.values()["damage"] == 24.0, "the Reset button restores the default")
	_check(form.row("damage")._slider.value == 24.0, "and moves the slider")
	form.reset_key("tags")
	_check(form.values()["tags"] == ["sidearm", "starter"], "list reset")
	_done()


func _test_search() -> void:
	_section("search and filter")
	await _fresh()
	var all := form.visible_keys().size()
	_check(all == 19, "everything shows by default (%d)" % all)
	form.search_box().text_changed.emit("reload")
	_check(form.visible_keys() == PackedStringArray(["reload_time"]), "matches the label")
	form.set_filter("hp")
	_check(form.visible_keys().is_empty(), "unit text is not searched")
	form.set_filter("tracer")
	_check(form.visible_keys() == PackedStringArray(["tint"]), "matches the description")
	form.set_filter("falloff")
	_check(form.visible_keys().size() == 3, "matches the group name")
	_check(form.groups()[0].visible == false, "a group with no match hides")
	form.set_filter("zzzz")
	_check(form._empty.visible, "an empty result says so")
	form.set_filter("")
	_check(form.visible_keys().size() == all and not form._empty.visible, "clearing restores everything")
	for g in form.groups():
		if g.title == "Ammo":
			g.set_open(false, false)
			form.set_filter("magazine")
			_check(g.is_shown_open(), "search opens a shut card")
			form.set_filter("")
			_check(not g.is_shown_open() and not g.open, "and shuts it again afterwards")
	_done()


func _test_dirty() -> void:
	_section("dirty, apply, revert")
	await _fresh()
	var dirt := []
	var applied := []
	var reverts := [0]
	form.dirty_changed.connect(func(d: bool) -> void: dirt.append(d))
	form.applied.connect(func(c: Dictionary) -> void: applied.append(c))
	form.reverted.connect(func() -> void: reverts[0] += 1)
	_check(not form.is_dirty() and form.revert_button().disabled, "starts clean")
	form.set_value("damage", 30.0)
	_check(form.is_dirty() and dirt == [true], "an edit makes it dirty once")
	_check(form.row("damage").is_modified(), "the edited row is highlighted")
	_check(not form.row("spread").is_modified(), "an untouched row is not")
	_check(form.changes() == {"damage": 30.0}, "changes() lists only the edit")
	form.set_value("damage", 24.0)
	_check(not form.is_dirty() and dirt == [true, false], "editing back to the baseline is clean again")
	form.set_value("damage", 30.0)
	form.set_value("automatic", true)
	var res := form.apply()
	_check(res.ok and applied.size() == 1 and applied[0] == {"damage": 30.0, "automatic": true}, "apply emits the changed keys")
	_check(not form.is_dirty() and form.changes().is_empty(), "apply is the new baseline")
	form.set_value("damage", 50.0)
	form.row("magazine").type_text("0")
	form.revert()
	_check(reverts[0] == 1 and form.values()["damage"] == 30.0, "revert restores the baseline")
	_check(form.row("damage")._slider.value == 30.0 and not form.has_errors(), "revert moves the widgets and drops errors")
	_check(not form.is_dirty(), "and is clean")
	form.revert_button().pressed.emit()
	_check(reverts[0] == 2, "the Revert button reverts")
	form.set_value("damage", 31.0)
	form.apply_button().pressed.emit()
	_check(applied.size() == 2, "the Apply button applies")
	_done()


func _test_navigation() -> void:
	_section("keyboard, gamepad and focus")
	await _fresh()
	_check(form.focus_first(), "focus_first lands somewhere")
	_check(get_viewport().gui_get_focus_owner() == form.row("name").editor(), "on the first editor")
	var slider: DotFormSlider = form.row("damage").editor()
	form.focus_key("damage")
	_check(get_viewport().gui_get_focus_owner() == slider, "focus_key focuses a slider")
	var before := slider.value
	slider._gui_input(_key(KEY_RIGHT))
	_check(slider.value > before, "right arrow raises the slider")
	slider._gui_input(_key(KEY_LEFT))
	_check(is_equal_approx(slider.value, before), "left arrow lowers it")
	slider._gui_input(_key(KEY_END))
	_check(slider.value == 200.0, "End jumps to the max")
	slider._gui_input(_key(KEY_HOME))
	_check(slider.value == 1.0, "Home jumps to the min")
	var tog: DotFormToggle = form.row("automatic").editor()
	tog._gui_input(_key(KEY_ENTER))
	_check(tog.pressed, "Enter flips a toggle")
	var next := slider.find_next_valid_focus()
	_check(next != null and next != slider, "focus moves on from a slider")
	var every := true
	for key in ["damage", "automatic", "rarity", "tint", "name", "tags", "price"]:
		every = every and form.row(key).editor().focus_mode == Control.FOCUS_ALL
	_check(every, "every editor is focusable")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(slider.size.x * 0.5, 5)
	slider.size = Vector2(300, 30)
	click.position = Vector2(150, 15)
	slider._gui_input(click)
	_check(absf(slider.fraction() - 0.5) < 0.06, "a tap or click sets the value by position")
	form.focus_search()
	_check(get_viewport().gui_get_focus_owner() == form.search_box(), "focus_search")
	form.search_box().text = "x"
	form.set_filter("x")
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	form._on_search_input(esc)
	_check(form.filter() == "", "Escape clears the search")
	_done()


func _test_layout() -> void:
	_section("layout, themes and tokens")
	await _fresh()
	var wide: DotFormRow = form.row("damage")
	_check(not wide._box.vertical, "wide rows sit side by side")
	form.custom_minimum_size = Vector2.ZERO
	form.size = Vector2(380, 700)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_check(form.row("damage")._box.vertical, "narrow rows stack")
	_check(form.row("damage").editor().size.x > 0.0, "and the editor still has width")
	_check(form.tokens.touch, "narrow means touch-sized targets")
	form.set_value("damage", 44.0)
	form.set_tokens(DotFormTokens.light())
	await get_tree().process_frame
	_check(form.values()["damage"] == 44.0 and form.is_dirty(), "switching theme keeps edits and dirty state")
	_check(form.theme != null and form.theme.has_stylebox("normal", "LineEdit"), "the form carries its own theme")
	var t := DotFormTokens.from_theme(DotUiTheme.space())
	_check(t.accent == DotUiTheme.space().accent, "tokens follow a DotUiTheme")
	_check(DotFormTokens.dark().sp(3) == 12 and DotFormTokens.new().px(10.0) == 10, "spacing tokens")
	var t2 := DotFormTokens.dark()
	t2.scale = 2.0
	_check(t2.sp(3) == 24, "scale multiplies spacing")
	var g: DotFormGroup = form.groups()[1]
	g.set_open(false, false)
	_check(g.reveal == 0.0 and g._clip.custom_minimum_size.y == 0.0, "a shut card has no body height")
	g.set_open(true, false)
	_check(g.reveal == 1.0 and g._clip.custom_minimum_size.y > 0.0, "an open card has")
	_check(form.describe().contains("changed"), "describe")
	_done()


func _test_bad_input() -> void:
	_section("bad input")
	var f := DotUiForm.new()
	add_child(f)
	var res := f.build([{"name": "a", "type": "nope"}])
	_check(not res.ok and res.error.code == DotError.CODE_INVALID, "build fails cleanly on a bad schema")
	var res2 := f.build([DotProfileSet.field("n", "int", 3, {"min": 0, "max": 5})], {"n": 99})
	_check(not res2.ok and f.values()["n"] == 3, "an invalid starting value falls back to the default")
	f.queue_free()
	_done()


func _done() -> void:
	_completed += 1
