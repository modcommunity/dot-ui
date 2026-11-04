class_name DotTouchButtons
extends DotHudPiece

## Round on-screen buttons for a touch player, anchored to the bottom-right and drawn in the HUD theme.
## It owns no game logic: [signal button_down] / [signal button_up] carry an id, and the game wires them to
## whatever it does (dot-player-controller's [code]DotFpsTouchSampler.hold[/code], a weapon, a menu).
## Fingers are tracked by index, so a thumb on a button and another on the stick or the look side do not disturb each other.
##
## [codeblock]
## var buttons := DotTouchButtons.new()
## buttons.set_buttons(DotTouchButtons.fps_stock())
## buttons.button_down.connect(func(id): sampler.hold(bit_for(id), true))
## buttons.button_up.connect(func(id): sampler.hold(bit_for(id), false))
## sampler.ignore_fn = buttons.contains_point
## [/codeblock]

signal button_down(id: StringName)
signal button_up(id: StringName)

## Hidden unless [method DotPlatform.has_touch], so a game adds it unconditionally.
@export var only_on_touch: bool = true

## Extra radius a finger may miss by, as a fraction of the button's.
@export_range(0.0, 0.6, 0.05) var slop: float = 0.2

## Gap in pixels from the right and bottom edges.
@export var margin: float = 28.0

## Multiplier for every button's size and offset.
@export var button_scale: float = 1.0

## Each: id, label, offset (from the bottom-right corner, towards the middle of the screen, px), radius px.
var _buttons: Array[Dictionary] = []

## Finger index -> button id.
var _fingers: Dictionary = {}


## A fire button with jump, crouch and reload round it: what a first-person game needs and no more.
static func fps_stock() -> Array[Dictionary]:
	return [
		{"id": &"fire", "label": "FIRE", "offset": Vector2(96, 110), "radius": 54.0},
		{"id": &"jump", "label": "JUMP", "offset": Vector2(210, 80), "radius": 40.0},
		{"id": &"reload", "label": "R", "offset": Vector2(60, 238), "radius": 32.0},
		{"id": &"crouch", "label": "DUCK", "offset": Vector2(196, 184), "radius": 34.0},
	]


func _ready() -> void:
	if only_on_touch and not Engine.is_editor_hint():
		visible = DotPlatform.has_touch()
	set_process_input(true)


func set_buttons(list: Array[Dictionary]) -> void:
	release_all()
	_buttons = list
	queue_redraw()


func is_held(id: StringName) -> bool:
	return id in _fingers.values()


func release_all() -> void:
	for finger in _fingers.keys():
		_release(finger)


## Centre of a button in this control's space, or Vector2.ZERO for an unknown id.
func centre_of(id: StringName) -> Vector2:
	for b in _buttons:
		if b["id"] == id:
			return _centre(b)
	return Vector2.ZERO


## Radius a button draws at, in pixels.
func radius_of(id: StringName) -> float:
	for b in _buttons:
		if b["id"] == id:
			return float(b["radius"]) * button_scale
	return 0.0


## Whether a screen position (viewport space) lands on a button; a look or move sampler asks this to leave the touch alone.
func contains_point(screen_pos: Vector2) -> bool:
	return visible and _hit(_to_local(screen_pos)) != &""


func footprint() -> Rect2:
	var out := Rect2()
	for b in _buttons:
		var r := float(b["radius"]) * button_scale
		var rect := Rect2(_centre(b) - Vector2(r, r), Vector2(r, r) * 2.0)
		out = rect if out.size == Vector2.ZERO else out.merge(rect)
	return out


func _centre(b: Dictionary) -> Vector2:
	var off: Vector2 = b["offset"]
	return size - Vector2(margin, margin) - off * button_scale


func _to_local(screen_pos: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_pos


func _hit(local: Vector2) -> StringName:
	var best: StringName = &""
	var best_d := INF
	for b in _buttons:
		var r := float(b["radius"]) * button_scale * (1.0 + slop)
		var d := local.distance_to(_centre(b))
		if d <= r and d < best_d:
			best = b["id"]
			best_d = d
	return best


func _input(event: InputEvent) -> void:
	if not visible or not event is InputEventScreenTouch:
		return
	var touch := event as InputEventScreenTouch
	if touch.pressed:
		var id := _hit(_to_local(touch.position))
		if id == &"" or is_held(id):
			return
		_fingers[touch.index] = id
		queue_redraw()
		button_down.emit(id)
		get_viewport().set_input_as_handled()
	elif _fingers.has(touch.index):
		_release(touch.index)
		get_viewport().set_input_as_handled()


func _release(finger: int) -> void:
	var id: StringName = _fingers[finger]
	_fingers.erase(finger)
	queue_redraw()
	button_up.emit(id)


func _draw() -> void:
	for b in _buttons:
		var id: StringName = b["id"]
		var c := _centre(b)
		var r := float(b["radius"]) * button_scale
		var held := is_held(id)
		var plate := colour(&"plate")
		var fill := Color(plate, minf(1.0, plate.a + 0.25)) if held else Color(plate, plate.a * 0.8)
		draw_circle(c, r, fill)
		draw_arc(c, r - 1.0, 0.0, TAU, 48, colour(&"text") if held else colour(&"plate_edge"), 3.0 if held else 2.0, true)
		var fs := int(clampf(r * 0.38, 11.0, 24.0))
		ink_text(Vector2(c.x - r, c.y + fs * 0.36), str(b["label"]), fs, colour(&"text"), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 4)


func describe() -> Dictionary:
	var out := super()
	out.merge({"buttons": _buttons.size(), "held": ",".join(PackedStringArray(_fingers.values().map(func(v): return String(v))))})
	return out
