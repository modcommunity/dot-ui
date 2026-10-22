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

## The form that draws the rows; the panel is its adapter to a [DotConfig].
var form: DotUiForm = null

## key -> int enum option names, for enums stored as an index.
var _index_enums: Dictionary = {}

## Pending edits when [member live] is off.
var _pending: Dictionary = {}

var _syncing := false


## Builds the panel from [param config].
##
## Safe to call again with a different config; the old controls are freed.
func bind(config: DotConfig) -> DotResult:
	if config == null:
		return DotResult.fail(DotError.CODE_INVALID, "No config to bind.")

	_config = config
	_pending.clear()
	_index_enums.clear()

	if form != null:
		remove_child(form)
		form.queue_free()

	var sensitive := config.sensitive_keys()
	var current_group := ""
	var schema: Array = []
	var values := {}

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

		var field := _field_for(property, current_group)

		if field.is_empty():
			DotLog.debug(CHANNEL, "no editor for property type", {"key": key, "type": int(property["type"])})
			continue

		schema.append(field)
		values[key] = _form_value(key, config.get(key))

	form = DotUiForm.new()
	form.name = "Form"
	form.chrome = false
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(form)
	var built := form.build(schema, values)

	if not built.ok:
		DotLog.warn(CHANNEL, "the form refused the settings", {"why": built.error.message})

	form.value_changed.connect(_on_form_value)

	if schema.is_empty():
		DotLog.warn(CHANNEL, "the config produced no editable settings", {"groups": only_groups})

	return DotResult.success(schema.size())


## One form field per config property; empty for a type the form has no editor for.
func _field_for(property: Dictionary, group: String) -> Dictionary:
	var key := str(property["name"])
	var hint := int(property["hint"])
	var hint_string := str(property["hint_string"])
	var field := {"name": key, "label": _label_for(key), "group": group, "tooltip": key}

	match int(property["type"]):
		TYPE_BOOL:
			field["type"] = "bool"
		TYPE_INT, TYPE_FLOAT:
			var is_int := int(property["type"]) == TYPE_INT
			if hint == PROPERTY_HINT_ENUM:
				var names: Array = []
				for choice in hint_string.split(",", false):
					names.append(choice.get_slice(":", 0))
				_index_enums[key] = names
				field["type"] = "string"
				field["enum"] = names
			else:
				field["type"] = "int" if is_int else "float"
				if hint == PROPERTY_HINT_RANGE and hint_string != "":
					var bounds := _range_from(hint, hint_string, int(property["type"]))
					field["min"] = bounds.x if not is_int else int(bounds.x)
					field["max"] = bounds.y if not is_int else int(bounds.y)
					field["step"] = bounds.z
		TYPE_STRING, TYPE_STRING_NAME:
			field["type"] = "string"
			if hint == PROPERTY_HINT_ENUM:
				var names: Array = []
				for choice in hint_string.split(",", false):
					names.append(choice.get_slice(":", 0))
				field["enum"] = names
		_:
			return {}

	return field


func _form_value(key: String, value: Variant) -> Variant:
	if _index_enums.has(key):
		var names: Array = _index_enums[key]
		return names[clampi(int(value), 0, maxi(0, names.size() - 1))] if not names.is_empty() else ""

	if value is StringName:
		return str(value)

	return value


func _config_value(key: String, value: Variant) -> Variant:
	if _index_enums.has(key):
		return maxi(0, (_index_enums[key] as Array).find(str(value)))

	return value


func _on_form_value(key: String, value: Variant) -> void:
	if _syncing:
		return

	_edited(key, _config_value(key, value))


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


## Turns a key into something readable. `max_rewind_ms` becomes `Max rewind ms`.
static func _label_for(key: String) -> String:
	return key.replace("_", " ").capitalize()


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
	refresh()
	applied.emit()
	return DotResult.success(count)


## Throws the pending edits away and puts the controls back to what the config says.
func revert() -> void:
	_pending.clear()

	if _config != null:
		refresh()


## Re-reads every value from the config into its control.
func refresh() -> void:
	if _config == null or form == null:
		return

	var values := {}

	for key in form.values().keys():
		values[key] = _form_value(key, _config.get(key))

	_syncing = true
	form.set_values(values)
	_syncing = false
	_pending.clear()


func bound_config() -> DotConfig:
	return _config


## The control editing [param key], or null.
func editor_for(key: String) -> Control:
	if form == null or form.row(key) == null:
		return null

	return form.row(key).editor()


func pending_count() -> int:
	return _pending.size()


func has_pending() -> bool:
	return not _pending.is_empty()


func describe() -> Dictionary:
	return {
		"config": _config.get_class() if _config != null else "<none>",
		"editors": form.values().size() if form != null else 0,
		"pending": _pending.size(),
		"live": live,
	}
