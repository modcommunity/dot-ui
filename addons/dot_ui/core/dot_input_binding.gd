@tool
class_name DotInputBinding
extends RefCounted

## One input binding as a short string, and back again.
##
## [b]Why a string and not a dictionary.[/b] [DotBindingsPanel] already stores bindings
## as a dictionary in a file of its own, which is right for a whole rebinding screen. A
## single binding that travels in a settings document — [code]DotSettingsDef.binding[/code],
## a console variable, a query string — needs a form a person can read in a JSON file and
## type by hand, and [code]{"type":"key","code":89,"physical":true}[/code] is neither.
## [code]"Y"[/code] is both.
##
## The vocabulary is deliberately the one [method DotBindingsPanel.event_name] already
## draws on a button, so what a settings file says and what the rebinding screen shows are
## the same word. Two spellings of one binding is how a player ends up with a settings
## file that disagrees with their own keyboard.
##
## [codeblock]
## DotInputBinding.to_text(event)          # "Y", "Space", "Shift+A", "Mouse 1", "Wheel up"
## DotInputBinding.from_text("Y")          # an InputEventKey on the physical Y
## DotInputBinding.ensure_action(&"chat_open", "Y")
## [/codeblock]
##
## [b]Keys are physical.[/b] A binding stored as a keycode is stored in the player's
## current layout, and the same file on an AZERTY keyboard then binds a key that is not
## where the label says. Physical keycodes are positions, which is what a player who chose
## a key actually chose. The text is still the US label, because that is the only stable
## name a position has.

const CHANNEL := "ui.binding"

## What [method from_text] and [method to_text] call "nothing bound".
const UNBOUND := ""

## The mouse buttons that are written by name rather than as "Mouse N" (dot-ui API level 2).
##
## [b]Why names.[/b] Godot numbers the wheel as mouse buttons 4 to 7 and the two side
## buttons as 8 and 9, so "Mouse 4" was the wheel turning up while every player reads it
## as the thumb button (the one their mouse software calls "Mouse 4"). A Controls page
## that says "Mouse 4" for previous weapon sends the player to the wrong button. The side
## buttons are "Mouse back" / "Mouse forward" rather than "Mouse 4" / "Mouse 5" because
## that spelling is already taken: a settings file written before these names says
## "Mouse 4" and means the wheel, and [method from_text] still reads it that way.
##
## Left, right and middle stay "Mouse 1" to "Mouse 3": nobody misreads those.
const MOUSE_NAMES := {
	MOUSE_BUTTON_WHEEL_UP: "Wheel up",
	MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
	MOUSE_BUTTON_WHEEL_LEFT: "Wheel left",
	MOUSE_BUTTON_WHEEL_RIGHT: "Wheel right",
	MOUSE_BUTTON_XBUTTON1: "Mouse back",
	MOUSE_BUTTON_XBUTTON2: "Mouse forward",
}


## A binding as text. Empty for anything with no short form.
static func to_text(event: InputEvent) -> String:
	if event == null:
		return UNBOUND

	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode

		if code == 0:
			return UNBOUND

		# The modifier mask is part of the keycode string both ways round, so
		# "Shift+A" round-trips without this having to spell out four modifiers.
		return OS.get_keycode_string(code | _modifier_mask(key))

	if event is InputEventMouseButton:
		return mouse_text((event as InputEventMouseButton).button_index)

	if event is InputEventJoypadButton:
		return "Pad %d" % (event as InputEventJoypadButton).button_index

	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "Axis %d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]

	return UNBOUND


## A mouse button as text: its name from [constant MOUSE_NAMES], else "Mouse N".
static func mouse_text(button_index: int) -> String:
	return str(MOUSE_NAMES.get(button_index, "Mouse %d" % button_index))


## The event a binding string names, or null.
##
## [b]Null rather than a [DotResult].[/b] Every caller is either "bind this" or "show
## this", and both want the same thing from "Qwerty" as from "": nothing. A result here
## would be a result every caller unwraps into a null check.
static func from_text(text: String) -> InputEvent:
	var trimmed := text.strip_edges()

	if trimmed == UNBOUND:
		return null

	# Names first, case-blind, because a person types these by hand. "Mouse back" also
	# starts with "Mouse ", and the number parse below would read it as button 0.
	var lowered := trimmed.to_lower()
	for index in MOUSE_NAMES:
		if str(MOUSE_NAMES[index]).to_lower() == lowered:
			var named := InputEventMouseButton.new()
			named.button_index = index as MouseButton
			return named

	# "Mouse N" is still read for every N, wheel included: it is what every binding was
	# stored as before MOUSE_NAMES, so "Mouse 4" in an old settings file is the wheel up.
	if trimmed.begins_with("Mouse "):
		var button := InputEventMouseButton.new()
		button.button_index = trimmed.substr(6).strip_edges().to_int() as MouseButton
		return null if button.button_index == 0 else button

	if trimmed.begins_with("Pad "):
		var pad := InputEventJoypadButton.new()
		pad.button_index = trimmed.substr(4).strip_edges().to_int() as JoyButton
		return null if pad.button_index < 0 else pad

	if trimmed.begins_with("Axis "):
		var body := trimmed.substr(5).strip_edges()
		if not (body.ends_with("+") or body.ends_with("-")):
			return null

		var motion := InputEventJoypadMotion.new()
		motion.axis = body.substr(0, body.length() - 1).strip_edges().to_int() as JoyAxis
		motion.axis_value = 1.0 if body.ends_with("+") else -1.0
		return null if motion.axis < 0 else motion

	var code := OS.find_keycode_from_string(trimmed)

	if code == KEY_NONE:
		return null

	var key := InputEventKey.new()
	key.physical_keycode = (code & KEY_CODE_MASK) as Key
	key.shift_pressed = (code & KEY_MASK_SHIFT) != 0
	key.ctrl_pressed = (code & KEY_MASK_CTRL) != 0
	key.alt_pressed = (code & KEY_MASK_ALT) != 0
	key.meta_pressed = (code & KEY_MASK_META) != 0
	return key


## Whether [param text] names anything at all.
static func is_bound(text: String) -> bool:
	return from_text(text) != null


## Points an action at exactly this binding, creating the action if it is new.
##
## Returns the binding that ended up on the action, which is [constant UNBOUND] when the
## text named nothing — a caller that shows the player their key wants what happened, not
## what was asked for.
##
## [b]It replaces rather than adds.[/b] A setting is one value; applying it twice must not
## leave the action bound to two keys, which is what `action_add_event` on an existing
## action does, and what makes a rebound key still work on its old one.
static func apply(action: StringName, text: String) -> String:
	var event := from_text(text)

	if not InputMap.has_action(action):
		InputMap.add_action(action)

	InputMap.action_erase_events(action)

	if event == null:
		# Text that names nothing is not the same as asking for nothing. A settings file
		# that says "Qwerty" for a key has just left the action with no binding at all,
		# and the player's only symptom is a key that does nothing. WARN, because the
		# person who can fix it is whoever wrote that value, and the value is in a file.
		if text.strip_edges() != UNBOUND:
			DotLog.warn(CHANNEL, "a binding names no input, so the action is unbound", {
				"action": String(action), "text": text,
			})
		return UNBOUND

	InputMap.action_add_event(action, event)
	return to_text(event)


## Creates the action with this binding only if the project does not already have it.
##
## What a game calls at boot for an action it ships a default for: a project that declares
## `chat_open` in its input map, or a player who has rebound it, keeps what they have.
## [method apply] is what a settings change calls.
static func ensure_action(action: StringName, text: String) -> String:
	if InputMap.has_action(action) and not InputMap.action_get_events(action).is_empty():
		return describe_action(action)

	return apply(action, text)


## The first binding on an action, as text. Empty for an action with none.
static func describe_action(action: StringName) -> String:
	if not InputMap.has_action(action):
		return UNBOUND

	var events := InputMap.action_get_events(action)
	return UNBOUND if events.is_empty() else to_text(events[0])


static func _modifier_mask(key: InputEventKey) -> int:
	var mask := 0

	if key.shift_pressed:
		mask |= KEY_MASK_SHIFT
	if key.ctrl_pressed:
		mask |= KEY_MASK_CTRL
	if key.alt_pressed:
		mask |= KEY_MASK_ALT
	if key.meta_pressed:
		mask |= KEY_MASK_META

	return mask
