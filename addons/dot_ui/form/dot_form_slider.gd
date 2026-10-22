class_name DotFormSlider
extends Control

## A rounded slider: drag, touch, arrow keys and gamepad d-pad; the knob grows while held or focused.

signal value_changed(v: float)

var tokens: DotFormTokens = DotFormTokens.new()
var min_value := 0.0
var max_value := 1.0
var step := 0.01
var value := 0.0
var lift := 0.0:
	set(v):
		lift = v
		queue_redraw()
var _drag := false
var _hover := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _hover = true; _refresh())
	mouse_exited.connect(func() -> void: _hover = false; _refresh())
	focus_entered.connect(_refresh)
	focus_exited.connect(_refresh)


func _get_minimum_size() -> Vector2:
	return Vector2(tokens.px(80.0), tokens.px(26.0 if not tokens.touch else 34.0))


## Sets the value (snapped, clamped) without emitting.
func set_value_no_signal(v: float) -> void:
	value = _snap(v)
	queue_redraw()


func fraction() -> float:
	return 0.0 if max_value <= min_value else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)


func _snap(v: float) -> float:
	var s := snappedf(v - min_value, step) + min_value
	return clampf(snappedf(s, 0.0000001), min_value, max_value)


func _refresh() -> void:
	tokens.go(self, self, "lift", 1.0 if (_drag or has_focus() or _hover) else 0.0, 0.12)


func _set_from_x(x: float) -> void:
	var pad := _pad()
	var f := clampf((x - pad) / maxf(1.0, size.x - pad * 2.0), 0.0, 1.0)
	_commit(min_value + f * (max_value - min_value))


func _commit(v: float) -> void:
	var nv := _snap(v)
	if is_equal_approx(nv, value):
		return
	value = nv
	queue_redraw()
	value_changed.emit(value)


func _pad() -> float:
	return float(tokens.px(10.0))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_drag = event.pressed
		if event.pressed:
			grab_focus()
			_set_from_x(event.position.x)
		_refresh()
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_set_from_x(event.position.x)
		accept_event()
	elif event.is_action_pressed(&"ui_left", true):
		_commit(value - step)
		accept_event()
	elif event.is_action_pressed(&"ui_right", true):
		_commit(value + step)
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_HOME:
		_commit(min_value)
		accept_event()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_END:
		_commit(max_value)
		accept_event()


func _draw() -> void:
	var pad := _pad()
	var th := float(tokens.px(6.0))
	var cy := size.y * 0.5
	var track := Rect2(pad, cy - th * 0.5, size.x - pad * 2.0, th)
	draw_style_box(tokens.box(tokens.field_hover, 99), track)
	var fill := Rect2(track.position, Vector2(track.size.x * fraction(), th))
	if fill.size.x > 0.5:
		draw_style_box(tokens.box(tokens.accent, 99), fill)
	var cx := track.position.x + track.size.x * fraction()
	var radius := float(tokens.px(8.0)) + float(tokens.px(2.0)) * lift
	draw_circle(Vector2(cx, cy + 1.0), radius + 1.0, Color(0, 0, 0, 0.18))
	draw_circle(Vector2(cx, cy), radius, tokens.text if tokens.is_dark else Color.WHITE)
	draw_arc(Vector2(cx, cy), radius, 0.0, TAU, 32, tokens.accent, float(tokens.px(2.0)), true)
	if has_focus():
		draw_arc(Vector2(cx, cy), radius + float(tokens.px(4.0)), 0.0, TAU, 40, Color(tokens.accent, 0.55), float(tokens.px(2.0)), true)
