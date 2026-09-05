@tool
class_name DotScreen
extends Control

## One full-screen thing: a pause menu, a settings panel, a scoreboard, a loadout
## picker.
##
## A [Control] with a lifecycle a [DotScreenStack] manages. Subclass it and the stack
## takes care of z-order, input blocking, mouse mode and the back key — all four of
## which are easy to get individually right and collectively wrong.
##
## [codeblock]
## class_name PauseMenu extends DotScreen
##
## func _screen_id() -> StringName: return &"pause"
##
## func _on_push() -> void:
##     $Resume.grab_focus()
## [/codeblock]

## What the mouse should do while this screen is on top.
enum Mouse {
	## Leave it alone. For a HUD-like overlay that does not take input.
	INHERIT,
	## Visible and free. What a menu wants.
	VISIBLE,
	## Captured. What gameplay wants; a screen almost never asks for it, but the
	## bottom-most one in a game does.
	CAPTURED,
	## Visible but confined to the window.
	CONFINED,
}

## Pushed onto a stack.
signal pushed()

## Popped off.
signal popped()

## Another screen was pushed on top of this one.
signal covered()

## The screen above this one was popped.
signal revealed()

## Ask the stack to pop this screen. What a Back button emits.
signal close_requested()

@export_group("Behaviour")

## Screens below this one do not receive input.
##
## Off for a transparent overlay — a scoreboard held down over a live game — which
## must not stop the player moving.
@export var blocks_input: bool = true

## Screens below this one are hidden entirely.
##
## Distinct from [member blocks_input]: a settings panel over a pause menu blocks input
## and should still let the menu show through, and a main menu over everything should
## not.
@export var hides_below: bool = false

## What the mouse does while this screen is on top.
@export var mouse_mode: Mouse = Mouse.VISIBLE

## Ask the tree to pause. Honoured only when
## [member DotUiConfig.allow_pause] is on — see there for why.
@export var pauses_game: bool = false

## The back key pops this screen.
##
## Off for a screen that must be dismissed deliberately: a disconnection notice, a
## first-run flow, an end-of-match screen with a timer.
@export var closable: bool = true

## Control to focus when this screen appears. Empty focuses nothing.
##
## Worth setting on every screen: a menu that appears with nothing focused cannot be
## used with a gamepad at all, and that is invisible to anyone testing with a mouse.
@export var initial_focus: NodePath = NodePath()

## The stack this screen is on. Null when it is not on one.
var stack: Node = null

## Whether it is the top screen.
var is_top: bool = false


# --- Subclass interface ----------------------------------------------------

## Identifier the stack addresses this screen by. Must be unique within a stack.
func _screen_id() -> StringName:
	return StringName(name)


## Called when the screen is pushed. The place to populate it.
func _on_push() -> void:
	pass


func _on_pop() -> void:
	pass


## Another screen was pushed on top.
func _on_cover() -> void:
	pass


## The screen above was popped and this one is on top again.
func _on_reveal() -> void:
	pass


## Return false to refuse a pop. For an unsaved-changes prompt.
##
## [b]Use sparingly.[/b] A screen that refuses to close is a screen a player can be
## trapped in, and the escape key not working is indistinguishable from a bug.
func _can_pop() -> bool:
	return true


# --- Called by the stack ---------------------------------------------------

func screen_id() -> StringName:
	return _screen_id()


func can_pop() -> bool:
	return closable and _can_pop()


func notify_pushed(owner_stack: Node) -> void:
	stack = owner_stack
	is_top = true
	visible = true
	_apply_focus()
	_on_push()
	pushed.emit()


func notify_popped() -> void:
	is_top = false
	stack = null
	_on_pop()
	popped.emit()


func notify_covered() -> void:
	is_top = false
	_on_cover()
	covered.emit()


func notify_revealed() -> void:
	is_top = true
	visible = true
	_apply_focus()
	_on_reveal()
	revealed.emit()


func _apply_focus() -> void:
	if initial_focus.is_empty():
		return

	var target := get_node_or_null(initial_focus) as Control

	if target == null:
		DotLog.warn(
			"ui.screen",
			"initial_focus does not resolve to a Control",
			{"screen": String(screen_id()), "path": String(initial_focus)}
		)
		return

	target.grab_focus()


## Asks the stack to close this screen.
func close() -> void:
	close_requested.emit()

	if stack != null and is_instance_valid(stack):
		stack.call(&"pop", screen_id())


func describe() -> Dictionary:
	return {
		"id": String(screen_id()),
		"top": is_top,
		"blocks": blocks_input,
		"hides": hides_below,
		"mouse": Mouse.keys()[mouse_mode],
		"closable": closable,
	}
