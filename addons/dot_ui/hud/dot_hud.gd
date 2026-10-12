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

@export_group("Fit")

## The frame the HUD was laid out for, 1280x720 for the glance pieces ([DotHudPiece]).
## Zero (the default) anchors the HUD to the whole rect as before. Set, the HUD is placed by
## hand instead: on a frame smaller than this on either side the whole layer is scaled by
## [method fit_scale], never laid out again, so every piece and every distance between
## pieces shrinks together; on a larger frame nothing grows and the world gets the room.
## Re-fitted when the viewport changes size.
@export var fit_design: Vector2 = Vector2.ZERO

## Below this the words are unreadable anyway; a frame that small gets overlap, not dust.
@export_range(0.1, 1.0, 0.05) var fit_min: float = 0.5

## The player's own HUD size (dot-menu's `hud_scale` setting), multiplying the fit: 1 is the
## design, 0.8 a smaller HUD, 1.25 a larger one. Set, it lays the HUD out by hand as
## [member fit_design] does, so a HUD with no design frame is scaled about its top-left
## corner over a rect the frame's size divided by it, and its anchors still reach the edges.
var user_scale: float = 1.0:
	set(value):
		var v := clampf(value, 0.25, 4.0)
		if is_equal_approx(v, user_scale):
			return
		user_scale = v
		if is_inside_tree() and not Engine.is_editor_hint():
			_apply_safe_area()

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
	get_viewport().size_changed.connect(_apply_safe_area)


## How much a HUD laid out for [param design] is scaled on a frame [param frame] pixels:
## 1 at [param design] and up, the short side's share of it below, never under
## [param minimum]. game-arena found the need standalone at 854x480, where the challenge ran
## over the scores and the ability bar over the health; a client shell draws on a 1280x720
## canvas stretched to its window, so this is the same answer the shell gives.
static func fit_scale(frame: Vector2, design: Vector2 = Vector2(1280.0, 720.0), minimum: float = 0.5) -> float:
	if design.x <= 0.0 or design.y <= 0.0:
		return 1.0
	return clampf(minf(frame.x / design.x, frame.y / design.y), minimum, 1.0)


## The scale [method fit_to_frame] last applied; 1 while [member fit_design] is zero.
func fit() -> float:
	return scale.x


## Lays the HUD out on a frame [param frame] pixels: inset by the safe area and scaled by
## [method fit_scale], in units that are [member fit_design] or more however small the
## frame. Public so a suite can lay it out on a frame it does not have (a headless one is
## 64 px). The inset is in the HUD's own units, so it scales with it.
func fit_to_frame(frame: Vector2) -> void:
	if config == null:
		config = DotUiConfig.new()
	var k := (fit_scale(frame, fit_design, fit_min) if fit_design != Vector2.ZERO else 1.0) * user_scale
	var inset := config.safe_area * config.scale
	fit_control(self, frame, k, inset)


## Lays [param control] out over a frame [param frame] pixels at scale [param k], inset by
## [param inset] of its own units: top-left anchored, scaled, and sized to the frame divided
## by the scale, so its children's anchors still reach the frame's edges. What
## [method fit_to_frame] does to a [DotHud], for a game whose HUD root is a plain [Control]
## under a [CanvasLayer] (dot-menu's `hud_scale` uses it). Public and static so a suite can
## lay one out on a frame it does not have.
static func fit_control(control: Control, frame: Vector2, k: float, inset: float = 0.0) -> void:
	if control == null or k <= 0.0:
		return
	control.set_anchors_preset(Control.PRESET_TOP_LEFT)
	control.scale = Vector2(k, k)
	control.position = Vector2(inset, inset) * k
	control.size = frame / k - Vector2(inset, inset) * 2.0


## Applies the configured inset, so nothing sits under a notch or off a television.
func _apply_safe_area() -> void:
	if fit_design != Vector2.ZERO or not is_equal_approx(user_scale, 1.0):
		var design := fit_design if fit_design != Vector2.ZERO else Vector2(1280.0, 720.0)
		fit_to_frame(get_viewport_rect().size if is_inside_tree() else design)
		return

	if config == null:
		config = DotUiConfig.new()
	var inset := config.safe_area * config.scale
	# Back from a player's own size to the design: full-rect anchoring again.
	if scale != Vector2.ONE:
		scale = Vector2.ONE
		set_anchors_preset(Control.PRESET_FULL_RECT)

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


## DEBUG on the change, never on the call: "the HUD is gone" is a real bug report, and
## the answer is always one of two flags -- a screen that hides what is below it, or a
## game that hid it for a cinematic and never said so again. The line names which.
func _refresh_visibility() -> void:
	var should_show := not (_hidden_by_screen or _hidden_by_game)

	if should_show != visible:
		DotLog.debug(CHANNEL, "hud shown" if should_show else "hud hidden", {
			"by_screen": _hidden_by_screen,
			"by_game": _hidden_by_game,
			"top": String(_stack.top_id()) if _stack != null and is_instance_valid(_stack) else "",
		})

	visible = should_show


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
		"fit": scale.x,
		"user_scale": user_scale,
	}
