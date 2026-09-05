@tool
class_name DotScreenStack
extends Control

## The screen stack: what is open, in what order, and who gets input.
##
## [b]Four things have to agree and are usually written in four places.[/b] Z-order,
## input blocking, mouse capture and the back key are each simple alone; the bug is
## that a game ends up with a pause menu that is visible but not focused, or a
## scoreboard that captures the mouse, or an escape key that closes two screens at
## once. All four are derived here from one stack.
##
## [b]No autoload.[/b] It registers itself in [DotRegistry] under [constant SERVICE] so
## a screen anywhere in the tree can find it, and so a process running two windows can
## have two.
##
## [codeblock]
## stack.register(pause_menu)
## stack.register(settings)
##
## stack.push(&"pause")
## stack.push(&"settings")   # pause is covered, still visible beneath
## stack.pop()               # back to pause
## [/codeblock]

const CHANNEL := "ui.stack"
const SERVICE := &"dot_screen_stack"

signal screen_pushed(id: StringName)
signal screen_popped(id: StringName)

## The top screen changed for any reason. What a game binds to when it wants to know
## whether a menu is open.
signal top_changed(id: StringName)

## The stack became empty, or stopped being empty.
signal menu_state_changed(any_open: bool)

@export_group("Configuration")

@export var config: DotUiConfig = null

@export var config_file: String = "user://cfg/ui.json"

@export var load_layered_config: bool = false

@export_group("Theme")

## Generated and applied on ready when [member theme] is not already set.
@export var ui_theme: DotUiTheme = null

@export_group("Service")

@export var register_service: bool = true

@export var service_scope: StringName = &""

@export_group("Mouse")

## Mouse mode when no screen is open. Usually captured, for a first-person game.
@export var idle_mouse_mode: DotScreen.Mouse = DotScreen.Mouse.CAPTURED

## Whether the stack sets the mouse mode at all.
##
## Off for a game that owns it. On is right for almost everything, and getting it
## wrong in the other direction — two owners fighting over `Input.mouse_mode` — is a
## cursor that flickers.
@export var manage_mouse: bool = true

## id -> [DotScreen].
var _registered: Dictionary = {}

## Screen ids, bottom first.
var _stack: Array[StringName] = []

var _registered_name: StringName = &""


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	var res := setup()

	if not res.ok:
		DotLog.result(CHANNEL, "screen stack setup", res)


func _exit_tree() -> void:
	if _registered_name != &"":
		DotRegistry.unregister_instance(_registered_name, self)
		_registered_name = &""


func setup() -> DotResult:
	if config == null:
		config = DotUiConfig.new()

	if load_layered_config:
		var loaded := config.load_layered(config_file)
		if not loaded.ok:
			return loaded.wrap("Could not load the UI configuration.")

	var valid := config.validate()

	if not valid.ok:
		return valid

	# The stack fills its parent and passes clicks through when nothing is open.
	# `set_anchors_and_offsets_preset`, not `set_anchors_preset`. The second sets the
	# anchors and leaves the offsets alone, so a Control built in code keeps the zero
	# size it was created with — the whole thing then lays out inside nothing and is
	# invisible while being, by every property, correctly configured. The family has
	# lost a day to this once already, and dot-ui had five of them.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if theme == null:
		if ui_theme == null:
			ui_theme = DotUiTheme.dark()
		theme = ui_theme.build(config.scale)

	if register_service:
		_registered_name = (
			DotRegistry.scoped_name(SERVICE, service_scope)
			if service_scope != &""
			else SERVICE
		)
		DotRegistry.register(_registered_name, self)

	_apply_mouse()
	return DotResult.success(null)


# --- Registration ----------------------------------------------------------

## Makes a screen pushable by id. Reparents it under the stack if it is not already.
##
## Reparenting rather than requiring the host to build the tree correctly: z-order is
## sibling order, so a screen that is not a child of the stack cannot be ordered by it,
## and the symptom is a menu that renders under the HUD.
func register(screen: DotScreen) -> DotResult:
	if screen == null:
		return DotResult.fail(DotError.CODE_INVALID, "No screen.")

	var id := screen.screen_id()

	if id == &"":
		return DotResult.fail(
			DotError.CODE_INVALID, "A screen with an empty id."
		)

	if _registered.has(id) and _registered[id] != screen:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Two screens both call themselves '%s'." % id
		)

	_registered[id] = screen

	if screen.get_parent() != self:
		if screen.get_parent() != null:
			screen.get_parent().remove_child(screen)
		add_child(screen)

	screen.visible = false
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	if not screen.close_requested.is_connected(_on_close_requested):
		screen.close_requested.connect(_on_close_requested.bind(id))

	return DotResult.success(id)


func unregister(id: StringName) -> void:
	pop(id)
	_registered.erase(id)


func screen(id: StringName) -> DotScreen:
	return _registered.get(id)


func registered_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _registered.keys():
		out.append(key)
	out.sort()
	return out


# --- Stack -----------------------------------------------------------------

func push(id: StringName) -> DotResult:
	var target := screen(id)

	if target == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "No screen registered as '%s'." % id
		)

	if _stack.has(id):
		# Pushing what is already open is almost always a double-fired input, not an
		# intention. Bringing it to the top rather than stacking a second copy avoids
		# a stack that has to be popped twice to close one menu.
		return _raise(id)

	var previous := top_id()

	if previous != &"":
		screen(previous).notify_covered()

	_stack.append(id)
	_refresh()
	target.notify_pushed(self)

	screen_pushed.emit(id)
	top_changed.emit(id)

	if _stack.size() == 1:
		menu_state_changed.emit(true)

	return DotResult.success(id)


## Pops the top screen, or a specific one.
##
## Popping a screen that is not on top removes it from the middle of the stack rather
## than refusing: a screen closing itself in response to a game event does not know
## what has been opened over it, and refusing would leave a dead screen in the stack.
func pop(id: StringName = &"") -> DotResult:
	if _stack.is_empty():
		return DotResult.fail(DotError.CODE_STATE, "Nothing is open.")

	var target_id := id if id != &"" else top_id()
	var index := _stack.find(target_id)

	if index < 0:
		return DotResult.fail(
			DotError.CODE_STATE, "'%s' is not open." % target_id
		)

	var target := screen(target_id)

	if not target.can_pop():
		return DotResult.fail(
			DotError.CODE_FORBIDDEN, "'%s' refused to close." % target_id
		)

	var was_top := index == _stack.size() - 1

	_stack.remove_at(index)
	target.visible = false
	target.notify_popped()

	_refresh()

	screen_popped.emit(target_id)

	if was_top:
		var now := top_id()

		if now != &"":
			screen(now).notify_revealed()

		top_changed.emit(now)

	if _stack.is_empty():
		menu_state_changed.emit(false)

	return DotResult.success(target_id)


## Pops everything down to and including [param id], or everything.
func pop_to(id: StringName = &"") -> int:
	var popped := 0

	while not _stack.is_empty():
		var current := top_id()

		if id != &"" and current == id:
			break

		var res := pop(current)

		if not res.ok:
			break

		popped += 1

	return popped


## Replaces the top screen. What a menu that navigates rather than nests wants.
func replace(id: StringName) -> DotResult:
	if not _stack.is_empty():
		var res := pop()
		if not res.ok:
			return res

	return push(id)


func clear() -> int:
	return pop_to()


func _raise(id: StringName) -> DotResult:
	var index := _stack.find(id)

	if index < 0 or index == _stack.size() - 1:
		return DotResult.success(id)

	var previous := top_id()

	_stack.remove_at(index)
	_stack.append(id)

	screen(previous).notify_covered()
	screen(id).notify_revealed()
	_refresh()

	top_changed.emit(id)
	return DotResult.success(id)


func top_id() -> StringName:
	return _stack[_stack.size() - 1] if not _stack.is_empty() else &""


func top() -> DotScreen:
	var id := top_id()
	return null if id == &"" else screen(id)


func is_open(id: StringName) -> bool:
	return _stack.has(id)


func any_open() -> bool:
	return not _stack.is_empty()


func depth() -> int:
	return _stack.size()


func open_ids() -> Array[StringName]:
	return _stack.duplicate()


## Opens a screen if it is closed, closes it if it is open. What a scoreboard key does.
func toggle(id: StringName) -> DotResult:
	return pop(id) if is_open(id) else push(id)


# --- Derived state ---------------------------------------------------------

## Recomputes visibility, z-order, input blocking, mouse mode and pause.
##
## One place, from one source. That is the entire reason this class exists.
func _refresh() -> void:
	var hidden_below := false

	# Top down, so the first screen that hides what is below it stops the walk.
	for index in range(_stack.size() - 1, -1, -1):
		var current := screen(_stack[index])

		if current == null:
			continue

		current.visible = not hidden_below

		if current.hides_below:
			hidden_below = true

	# Sibling order is z-order. Every open screen is moved to the end, bottom of the
	# stack first, so the stack order *is* the draw order.
	#
	# Moving each to the end rather than to its stack index: a closed screen is still
	# a child of the stack, and indexing from zero leaves closed screens after open
	# ones. They are invisible so nothing is drawn wrongly today, but any other child
	# a host adds under the stack would then render above every open screen.
	for id in _stack:
		var open_screen := screen(id)
		if open_screen != null:
			move_child(open_screen, get_child_count() - 1)

	# Input blocking is separate from visibility: a transparent scoreboard is visible
	# and must not stop the player moving, and a settings panel over a pause menu
	# blocks input while the menu still shows through.
	var blocked := false

	for index in range(_stack.size() - 1, -1, -1):
		var current := screen(_stack[index])

		if current == null:
			continue

		current.mouse_filter = (
			Control.MOUSE_FILTER_IGNORE if blocked else Control.MOUSE_FILTER_STOP
		)

		if current.blocks_input:
			blocked = true

	_apply_mouse()
	_apply_pause()


func _apply_mouse() -> void:
	if not manage_mouse:
		return

	var wanted := idle_mouse_mode
	var current := top()

	if current != null and current.mouse_mode != DotScreen.Mouse.INHERIT:
		wanted = current.mouse_mode

	var mode := Input.MOUSE_MODE_VISIBLE

	match wanted:
		DotScreen.Mouse.CAPTURED:
			mode = Input.MOUSE_MODE_CAPTURED
		DotScreen.Mouse.CONFINED:
			mode = Input.MOUSE_MODE_CONFINED
		DotScreen.Mouse.INHERIT:
			return
		_:
			mode = Input.MOUSE_MODE_VISIBLE

	if Input.mouse_mode != mode:
		Input.mouse_mode = mode


func _apply_pause() -> void:
	if not config.allow_pause or not is_inside_tree():
		return

	var wanted := false

	for id in _stack:
		var current := screen(id)
		if current != null and current.pauses_game:
			wanted = true
			break

	var tree := get_tree()

	if tree != null and tree.paused != wanted:
		tree.paused = wanted


# --- Input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not config.back_pops_screen:
		return

	if not event.is_action_pressed(&"ui_cancel"):
		return

	if _stack.is_empty():
		return

	var current := top()

	if current == null or not current.can_pop():
		# Still consumed. A screen that refuses to close must not let the key fall
		# through to gameplay, or the escape key both fails to close the menu and
		# opens the one below it.
		get_viewport().set_input_as_handled()
		return

	pop()
	get_viewport().set_input_as_handled()


func _on_close_requested(id: StringName) -> void:
	pop(id)


func describe() -> Dictionary:
	var open := []
	for id in _stack:
		open.append(String(id))

	return {
		"registered": _registered.size(),
		"open": open,
		"top": String(top_id()),
		"mouse": DotScreen.Mouse.keys()[idle_mouse_mode],
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("screens  %d registered, %d open" % [_registered.size(), _stack.size()])

	for index in range(_stack.size()):
		var current := screen(_stack[index])
		out.append("  %d %-16s %s%s" % [
			index,
			_stack[index],
			"visible" if current != null and current.visible else "hidden",
			"  blocks" if current != null and current.blocks_input else "",
		])

	return out
