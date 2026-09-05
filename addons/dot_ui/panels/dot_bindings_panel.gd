@tool
class_name DotBindingsPanel
extends VBoxContainer

## Rebinding, with conflict detection and a file that survives a restart.
##
## Reads Godot's [InputMap] rather than a table of its own, so it always shows the
## actions the game actually has — the same argument [DotSettingsPanel] makes about
## reading a [DotConfig].
##
## [b]Three things this does that a naive rebinder does not.[/b] It refuses to leave an
## action with no binding at all, it detects conflicts before committing rather than
## after, and it saves through [DotPaths] so a web build's IndexedDB is flushed. The
## first is the one that matters: an action bound to nothing is a control the player
## cannot use and cannot get back without deleting a file they cannot find.

const CHANNEL := "ui.bindings"

## A binding was committed to the [InputMap].
signal binding_changed(action: StringName, event: InputEvent)

## A capture was refused. [param reason] is player-facing.
signal binding_refused(action: StringName, reason: String)

## The panel is waiting for a key. A game usually dims the rest of the screen.
signal capture_started(action: StringName)
signal capture_ended()

@export_group("Configuration")

@export var config: DotUiConfig = null

@export_group("Filtering")

## Only show actions whose name starts with this. Empty shows everything except
## Godot's own `ui_*` actions.
@export var prefix: String = ""

## Show Godot's built-in `ui_*` actions.
##
## Off by default: they are the engine's navigation, rebinding them from a settings
## screen breaks the settings screen, and a player who has done it has no way back.
@export var show_builtin: bool = false

@export_group("Behaviour")

## Refuse a binding already used by another action.
##
## Off lets two actions share a key, which some games want deliberately (crouch and
## slide). On, the conflict is reported and nothing changes.
@export var refuse_conflicts: bool = true

## Whether the mouse wheel and buttons may be bound.
@export var allow_mouse: bool = true

## The action currently being captured, or empty.
var _capturing: StringName = &""

## action -> the Button showing its current binding.
var _buttons: Dictionary = {}

## action -> the events it had when the panel was built, for [method reset_all].
var _defaults: Dictionary = {}


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if config == null:
		config = DotUiConfig.new()

	_snapshot_defaults()


func _snapshot_defaults() -> void:
	if not _defaults.is_empty():
		return

	for action in InputMap.get_actions():
		_defaults[action] = InputMap.action_get_events(action).duplicate()


## Builds a row per rebindable action.
func build() -> DotResult:
	if config == null:
		config = DotUiConfig.new()

	_snapshot_defaults()
	_buttons.clear()

	for child in get_children():
		remove_child(child)
		child.queue_free()

	var built := 0

	for action in rebindable_actions():
		var row := HBoxContainer.new()
		row.name = "Row_%s" % action

		var label := Label.new()
		label.text = String(action).replace("_", " ").capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.tooltip_text = String(action)
		row.add_child(label)

		var button := Button.new()
		button.text = describe_binding(action)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(begin_capture.bind(action))
		row.add_child(button)

		_buttons[action] = button
		add_child(row)
		built += 1

	return DotResult.success(built)


## Actions a player may rebind, sorted.
func rebindable_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	var locked := config.locked_actions if config != null else []

	for action in InputMap.get_actions():
		var name_str := String(action)

		if not show_builtin and name_str.begins_with("ui_"):
			continue

		if prefix != "" and not name_str.begins_with(prefix):
			continue

		if locked.has(action):
			continue

		out.append(action)

	out.sort()
	return out


## The current binding as a readable string.
##
## Deliberately not a translation: a game shows the player whatever it wants, and this
## is what a console dump and a default button label use.
func describe_binding(action: StringName) -> String:
	var events := InputMap.action_get_events(action)

	if events.is_empty():
		return "—"

	return event_name(events[0])


static func event_name(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return OS.get_keycode_string(code)

	if event is InputEventMouseButton:
		return "Mouse %d" % (event as InputEventMouseButton).button_index

	if event is InputEventJoypadButton:
		return "Pad %d" % (event as InputEventJoypadButton).button_index

	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "Axis %d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]

	return event.as_text()


# --- Capture ---------------------------------------------------------------

func begin_capture(action: StringName) -> void:
	if _capturing != &"":
		cancel_capture()

	_capturing = action

	var button: Button = _buttons.get(action)

	if button != null:
		button.text = "…"

	set_process_input(true)
	capture_started.emit(action)


func cancel_capture() -> void:
	if _capturing == &"":
		return

	var button: Button = _buttons.get(_capturing)

	if button != null:
		button.text = describe_binding(_capturing)

	_capturing = &""
	set_process_input(false)
	capture_ended.emit()


func is_capturing() -> bool:
	return _capturing != &""


func _input(event: InputEvent) -> void:
	if _capturing == &"":
		return

	if event is InputEventMouseMotion:
		return

	if not event.is_pressed() or event.is_echo():
		return

	if event is InputEventMouseButton and not allow_mouse:
		return

	# Escape cancels rather than binding. Without it, a player who opens the capture
	# by accident binds escape to something and can no longer leave any menu.
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		cancel_capture()
		get_viewport().set_input_as_handled()
		return

	var action := _capturing
	var res := bind_action(action, event)

	get_viewport().set_input_as_handled()

	if not res.ok:
		binding_refused.emit(action, res.error.message)

	cancel_capture()


## Binds [param event] to [param action], replacing what was there.
##
## Returns a failure on a conflict, and changes nothing in that case. Checking before
## committing rather than after is what makes a refusal a no-op rather than something
## the caller has to undo.
func bind_action(action: StringName, event: InputEvent) -> DotResult:
	if not InputMap.has_action(action):
		return DotResult.fail(DotError.CODE_INVALID, "No action '%s'." % action)

	if refuse_conflicts:
		var clash := conflicting_action(action, event)

		if clash != &"":
			return DotResult.fail(
				DotError.CODE_INVALID,
				"That is already bound to %s."
					% String(clash).replace("_", " ").capitalize()
			)

	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)

	var button: Button = _buttons.get(action)

	if button != null:
		button.text = describe_binding(action)

	binding_changed.emit(action, event)
	return DotResult.success(event)


## The action already using [param event], or empty.
func conflicting_action(action: StringName, event: InputEvent) -> StringName:
	for other in InputMap.get_actions():
		if other == action:
			continue

		if not show_builtin and String(other).begins_with("ui_"):
			continue

		for existing in InputMap.action_get_events(other):
			if _same_event(existing, event):
				return other

	return &""


## Whether two events are the same binding.
##
## Compared by physical keycode where there is one, not by keycode: a physical
## comparison is what makes a binding survive a layout change, and mixing the two makes
## a French player's `A` conflict with an English player's `Q`.
static func _same_event(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		var ca := ka.physical_keycode if ka.physical_keycode != 0 else ka.keycode
		var cb := kb.physical_keycode if kb.physical_keycode != 0 else kb.keycode
		return ca == cb

	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index \
			== (b as InputEventMouseButton).button_index

	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index \
			== (b as InputEventJoypadButton).button_index

	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)

	return false


## Puts one action back to what it was when the panel first saw the [InputMap].
func reset_action(action: StringName) -> void:
	var events: Array = _defaults.get(action, [])

	InputMap.action_erase_events(action)

	for event in events:
		InputMap.action_add_event(action, event)

	var button: Button = _buttons.get(action)

	if button != null:
		button.text = describe_binding(action)


func reset_all() -> void:
	for action in _defaults.keys():
		reset_action(action)


# --- Persistence -----------------------------------------------------------

## Writes the rebindable actions' bindings to [member DotUiConfig.bindings_file].
##
## Through [DotPaths.write_json], which does the temporary file, the rename and the
## browser's IndexedDB flush — a web build that wrote directly would lose the file on
## the next load.
func save() -> DotResult:
	var data := {}

	for action in rebindable_actions():
		var events := []

		for event in InputMap.action_get_events(action):
			var encoded := _encode(event)
			if not encoded.is_empty():
				events.append(encoded)

		data[String(action)] = events

	return DotPaths.write_json(config.bindings_file, {"bindings": data}, true, true)


## Applies a saved bindings file.
##
## [b]An action that ends up with no events is put back to its default.[/b] A file that
## is truncated, hand-edited or written by an older build otherwise leaves the player
## with a control bound to nothing and no way to reach the rebinder for it.
func load_saved() -> DotResult:
	if not FileAccess.file_exists(config.bindings_file):
		return DotResult.success(0)

	var read := DotPaths.read_json(config.bindings_file)

	if not read.ok:
		return read.wrap("Could not read the saved bindings.")

	if not (read.value is Dictionary):
		return DotResult.fail(DotError.CODE_PARSE, "The bindings file is not an object.")

	var root: Dictionary = read.value

	# Absent is a malformed file; present-and-empty is a player who unbound
	# everything. The first must be refused rather than applied as "change nothing",
	# or a file written by a different tool is silently accepted as valid.
	if not root.has("bindings"):
		return DotResult.fail(
			DotError.CODE_PARSE, "The bindings file has no bindings section."
		)

	var raw: Variant = root["bindings"]

	if typeof(raw) != TYPE_DICTIONARY:
		return DotResult.fail(
			DotError.CODE_PARSE, "The bindings section is not an object."
		)

	_snapshot_defaults()

	var applied := 0
	var bindings: Dictionary = raw

	for key in bindings.keys():
		var action := StringName(str(key))

		if not InputMap.has_action(action):
			continue

		var events: Variant = bindings[key]

		if typeof(events) != TYPE_ARRAY:
			continue

		var decoded: Array[InputEvent] = []

		for entry in (events as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var event := _decode(entry as Dictionary)
			if event != null:
				decoded.append(event)

		if decoded.is_empty():
			reset_action(action)
			continue

		InputMap.action_erase_events(action)

		for event in decoded:
			InputMap.action_add_event(action, event)

		applied += 1

	for action in _buttons.keys():
		(_buttons[action] as Button).text = describe_binding(action)

	return DotResult.success(applied)


static func _encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		return {
			"type": "key",
			"code": key.physical_keycode if key.physical_keycode != 0 else key.keycode,
			"physical": key.physical_keycode != 0,
		}

	if event is InputEventMouseButton:
		return {"type": "mouse", "button": (event as InputEventMouseButton).button_index}

	if event is InputEventJoypadButton:
		return {"type": "pad", "button": (event as InputEventJoypadButton).button_index}

	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "axis", "axis": motion.axis, "value": motion.axis_value}

	return {}


static func _decode(data: Dictionary) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			var key := InputEventKey.new()
			var code := int(data.get("code", 0))
			if code == 0:
				return null
			if bool(data.get("physical", true)):
				key.physical_keycode = code
			else:
				key.keycode = code
			return key
		"mouse":
			var button := InputEventMouseButton.new()
			button.button_index = int(data.get("button", 0))
			return null if button.button_index == 0 else button
		"pad":
			var pad := InputEventJoypadButton.new()
			pad.button_index = int(data.get("button", -1))
			return null if pad.button_index < 0 else pad
		"axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(data.get("axis", -1))
			motion.axis_value = float(data.get("value", 0.0))
			return null if motion.axis < 0 else motion
		_:
			return null


func describe() -> Dictionary:
	var out := {}

	for action in rebindable_actions():
		out[String(action)] = describe_binding(action)

	return {
		"actions": out,
		"capturing": String(_capturing),
		"refuse_conflicts": refuse_conflicts,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()

	for action in rebindable_actions():
		out.append("  %-22s %s" % [action, describe_binding(action)])

	return out
