@tool
class_name DotSettingsPanel
extends VBoxContainer

## Builds an editable settings panel out of any [DotConfig], automatically.
##
## [b]Every project in this family already describes its settings.[/b] A [DotConfig]
## knows its keys, their types, their ranges, their enum choices, their groups and
## which of them are secrets — all of it in `@export` annotations the engine already
## exposes through [method Object.get_property_list]. A hand-built settings screen
## restates every one of those and then drifts from them, one field at a time, until
## a setting exists that no screen can reach.
##
## So this reads the config and builds the controls. A game that wants a designed
## settings screen builds one; this is what a game gets for free, and it is never
## wrong about what the settings are.
##
## [b]Secrets are never shown.[/b] [method DotConfig.sensitive_keys] is honoured, for
## the same reason `DotConfig` refuses them from the environment and argv: they end up
## in screenshots and pasted bug reports.

const CHANNEL := "ui.settings"

## A control changed. Emitted per edit, not per keystroke for text.
signal setting_changed(key: String, value: Variant)

## [method apply] was called and the config validated.
signal applied()

## [method apply] was called and the config refused the new values.
signal apply_failed(error: DotError)

@export_group("Behaviour")

## Write straight through to the config as controls change.
##
## Off collects the edits and applies them on [method apply], which is what a panel
## with an Apply button wants — and what anything with a validated config needs, since
## a half-edited config can be invalid on the way to being valid.
@export var live: bool = false

## Show keys listed by [method DotConfig.sensitive_keys]. **Leave this off.**
@export var show_sensitive: bool = false

## Groups to show. Empty shows all.
@export var only_groups: Array[String] = []

var _config: DotConfig = null

## key -> the Control editing it.
var _editors: Dictionary = {}

## Pending edits when [member live] is off.
var _pending: Dictionary = {}


## Builds the panel from [param config].
##
## Safe to call again with a different config; the old controls are freed.
func bind(config: DotConfig) -> DotResult:
	if config == null:
		return DotResult.fail(DotError.CODE_INVALID, "No config to bind.")

	_config = config
	_pending.clear()
	_editors.clear()

	for child in get_children():
		remove_child(child)
		child.queue_free()

	var sensitive := config.sensitive_keys()
	var current_group := ""
	var heading_shown := ""
	var built := 0

	for property in config.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_GROUP != 0:
			current_group = str(property["name"])
			continue

		if int(property["usage"]) & PROPERTY_USAGE_SUBGROUP != 0:
			continue

		var key := str(property["name"])

		if not config.has_key(key):
			continue

		if not only_groups.is_empty() and not only_groups.has(current_group):
			continue

		if sensitive.has(key) and not show_sensitive:
			continue


		var editor := _build_editor(property, config.get(key))

		if editor == null:
			# A type with no editor is skipped rather than shown as a dead row: an
			# uneditable control in a settings panel reads as a broken one.
			DotLog.debug(
				CHANNEL,
				"no editor for property type",
				{"key": key, "type": int(property["type"])}
			)
			continue

		# The heading is added only once a group turns out to have something visible
		# in it. Adding it before the walk leaves a bare "Storage" heading over
		# nothing whenever a group holds only secrets.
		if heading_shown != current_group:
			heading_shown = current_group
			_add_heading(current_group)

		_editors[key] = editor
		_add_row(key, _label_for(key), editor)
		built += 1

	if built == 0:
		DotLog.warn(
			CHANNEL, "the config produced no editable settings", {"groups": only_groups}
		)

	return DotResult.success(built)


func _add_heading(group: String) -> void:
	if group == "":
		return

	var heading := Label.new()
	heading.text = group
	heading.theme_type_variation = &"DotHeading"
	add_child(heading)


func _add_row(key: String, label_text: String, editor: Control) -> void:
	var row := HBoxContainer.new()
	row.name = "Row_%s" % key

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = key
	row.add_child(label)

	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)

	add_child(row)


## Turns a key into something readable. `max_rewind_ms` becomes `Max rewind ms`.
static func _label_for(key: String) -> String:
	return key.replace("_", " ").capitalize()


func _build_editor(property: Dictionary, value: Variant) -> Control:
	var key := str(property["name"])
	var type := int(property["type"])
	var hint := int(property["hint"])
	var hint_string := str(property["hint_string"])

	match type:
		TYPE_BOOL:
			var check := CheckBox.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(on: bool) -> void: _edited(key, on))
			return check

		TYPE_INT, TYPE_FLOAT:
			if hint == PROPERTY_HINT_ENUM:
				var options := OptionButton.new()
				var choices := hint_string.split(",", false)
				for index in range(choices.size()):
					options.add_item(choices[index].get_slice(":", 0), index)
				options.selected = clampi(int(value), 0, maxi(0, choices.size() - 1))
				options.item_selected.connect(
					func(index: int) -> void: _edited(key, index)
				)
				return options

			var spin := SpinBox.new()
			var bounds := _range_from(hint, hint_string, type)
			spin.min_value = bounds.x
			spin.max_value = bounds.y
			spin.step = bounds.z
			spin.allow_greater = hint != PROPERTY_HINT_RANGE
			spin.allow_lesser = hint != PROPERTY_HINT_RANGE
			spin.value = float(value)
			spin.value_changed.connect(func(v: float) -> void:
				_edited(key, int(v) if type == TYPE_INT else v)
			)
			return spin

		TYPE_STRING, TYPE_STRING_NAME:
			if hint == PROPERTY_HINT_ENUM:
				var options := OptionButton.new()
				var choices := hint_string.split(",", false)
				var selected := 0
				for index in range(choices.size()):
					var choice := choices[index].get_slice(":", 0)
					options.add_item(choice, index)
					if choice == str(value):
						selected = index
				options.selected = selected
				options.item_selected.connect(func(index: int) -> void:
					_edited(key, options.get_item_text(index))
				)
				return options

			var edit := LineEdit.new()
			edit.text = str(value)
			# text_submitted and focus_exited rather than text_changed: a config write
			# per keystroke is a write per keystroke, and with `live` on that is a
			# validate() per character typed.
			edit.text_submitted.connect(func(text: String) -> void: _edited(key, text))
			edit.focus_exited.connect(func() -> void: _edited(key, edit.text))
			return edit

		_:
			return null


## Range and step from an `@export_range` hint string, with sane fallbacks.
static func _range_from(hint: int, hint_string: String, type: int) -> Vector3:
	var default_step := 1.0 if type == TYPE_INT else 0.01

	if hint != PROPERTY_HINT_RANGE or hint_string == "":
		return Vector3(-1000000.0, 1000000.0, default_step)

	var parts := hint_string.split(",", false)

	if parts.size() < 2:
		return Vector3(-1000000.0, 1000000.0, default_step)

	var step := default_step

	if parts.size() >= 3 and parts[2].is_valid_float():
		step = parts[2].to_float()

	return Vector3(parts[0].to_float(), parts[1].to_float(), step)


func _edited(key: String, value: Variant) -> void:
	setting_changed.emit(key, value)

	if live:
		_config.set(key, value)
		return

	_pending[key] = value


# --- Applying --------------------------------------------------------------

## Writes the pending edits to the config and validates it.
##
## [b]On a validation failure every edit is rolled back.[/b] Applying half of them
## leaves the config in a state neither the player nor the code chose, and the player
## has no way to tell which half survived.
func apply() -> DotResult:
	if _config == null:
		return DotResult.fail(DotError.CODE_STATE, "Nothing is bound.")

	if _pending.is_empty():
		applied.emit()
		return DotResult.success(0)

	var rollback := {}

	for key in _pending.keys():
		rollback[key] = _config.get(key)

	for key in _pending.keys():
		_config.set(key, _pending[key])

	var valid := _config.validate()

	if not valid.ok:
		for key in rollback.keys():
			_config.set(key, rollback[key])
		apply_failed.emit(valid.error)
		return valid

	var count := _pending.size()
	_pending.clear()
	applied.emit()
	return DotResult.success(count)


## Throws the pending edits away and puts the controls back to what the config says.
func revert() -> void:
	_pending.clear()

	if _config != null:
		refresh()


## Re-reads every value from the config into its control.
##
## Setting a control's value fires its own signal, which would be read back as an edit
## and re-queued — so the pending map is cleared afterwards rather than before.
func refresh() -> void:
	if _config == null:
		return

	for key in _editors.keys():
		_set_editor_value(_editors[key], _config.get(key))

	_pending.clear()


static func _set_editor_value(editor: Control, value: Variant) -> void:
	if editor is CheckBox:
		(editor as CheckBox).button_pressed = bool(value)
	elif editor is SpinBox:
		(editor as SpinBox).value = float(value)
	elif editor is LineEdit:
		(editor as LineEdit).text = str(value)
	elif editor is OptionButton:
		var options := editor as OptionButton
		if typeof(value) == TYPE_INT:
			options.selected = int(value)
		else:
			for index in range(options.item_count):
				if options.get_item_text(index) == str(value):
					options.selected = index
					break


func bound_config() -> DotConfig:
	return _config


func editor_for(key: String) -> Control:
	return _editors.get(key)


func pending_count() -> int:
	return _pending.size()


func has_pending() -> bool:
	return not _pending.is_empty()


func describe() -> Dictionary:
	return {
		"config": _config.get_class() if _config != null else "<none>",
		"editors": _editors.size(),
		"pending": _pending.size(),
		"live": live,
	}
