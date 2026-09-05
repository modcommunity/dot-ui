@tool
class_name DotHud
extends Control

## The always-on layer: crosshair, health, ammo, kill feed, chat.
##
## Separate from [DotScreenStack] rather than being the bottom screen on it, because a
## HUD is not a screen: it never takes focus, it never blocks input, and it should
## disappear when a menu that hides what is below it opens — which is three exceptions
## a screen would need.
##
## Binding it to a stack is one call and it then hides and shows itself.

const CHANNEL := "ui.hud"

@export_group("Configuration")

@export var config: DotUiConfig = null

@export_group("Behaviour")

## Hide the HUD while a screen that hides what is below it is open.
@export var hide_under_screens: bool = true

## Hide it while any screen at all is open. For a game whose menus are opaque anyway.
@export var hide_under_any_screen: bool = false

var _stack: DotScreenStack = null
var _hidden_by_screen: bool = false
var _hidden_by_game: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if config == null:
		config = DotUiConfig.new()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A HUD that stops mouse events is a HUD that eats the click that should have
	# fired the weapon.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_apply_safe_area()


## Applies the configured inset, so nothing sits under a notch or off a television.
func _apply_safe_area() -> void:
	var inset := config.safe_area * config.scale

	offset_left = inset
	offset_top = inset
	offset_right = -inset
	offset_bottom = -inset


## Follows a screen stack, hiding and showing itself.
func bind_stack(stack: DotScreenStack) -> void:
	if _stack != null and is_instance_valid(_stack):
		if _stack.top_changed.is_connected(_on_top_changed):
			_stack.top_changed.disconnect(_on_top_changed)

	_stack = stack

	if stack == null:
		return

	stack.top_changed.connect(_on_top_changed)
	_on_top_changed(stack.top_id())


func _on_top_changed(_id: StringName) -> void:
	if _stack == null:
		return

	var should_hide := false

	if hide_under_any_screen:
		should_hide = _stack.any_open()
	elif hide_under_screens:
		var top := _stack.top()
		should_hide = top != null and top.hides_below

	_hidden_by_screen = should_hide
	_refresh_visibility()


## Hides the HUD for a game's own reason: a cinematic, a screenshot mode, a death cam.
##
## Kept separate from the screen-driven flag so that closing a menu does not undo it.
func set_hidden_by_game(hidden: bool) -> void:
	_hidden_by_game = hidden
	_refresh_visibility()


func _refresh_visibility() -> void:
	visible = not (_hidden_by_screen or _hidden_by_game)


## Every [DotHudWidget] below this node.
func widgets() -> Array[DotHudWidget]:
	var out: Array[DotHudWidget] = []
	_collect(self, out)
	return out


func _collect(node: Node, out: Array[DotHudWidget]) -> void:
	for child in node.get_children():
		if child is DotHudWidget:
			out.append(child)
		_collect(child, out)


## Refreshes every widget. What a game calls after a state change it knows about.
func refresh_all() -> void:
	for widget in widgets():
		widget.refresh()


func describe() -> Dictionary:
	return {
		"visible": visible,
		"widgets": widgets().size(),
		"hidden_by_screen": _hidden_by_screen,
		"hidden_by_game": _hidden_by_game,
		"bound": _stack != null,
	}
