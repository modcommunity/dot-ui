class_name DotFormToggle
extends Control

## A pill switch whose knob slides; clicks, touch, Enter and Space all flip it.

signal toggled(on: bool)

var tokens: DotFormTokens = DotFormTokens.new()
var pressed := false
## 0 (off) to 1 (on); the knob and colour follow it.
var t := 0.0:
	set(v):
		t = v
		queue_redraw()
var _hover := false


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _hover = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hover = false; queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _get_minimum_size() -> Vector2:
	return Vector2(tokens.px(46.0), tokens.px(26.0 if not tokens.touch else 30.0))


## Sets the state without emitting; [param animated] slides the knob.
func set_pressed_no_signal(on: bool, animated: bool = false) -> void:
	pressed = on
	if animated:
		tokens.go(self, self, "t", 1.0 if on else 0.0, 0.16)
	else:
		t = 1.0 if on else 0.0


func flip() -> void:
	pressed = not pressed
	tokens.go(self, self, "t", 1.0 if pressed else 0.0, 0.16)
	toggled.emit(pressed)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		flip()
		accept_event()
	elif event.is_action_pressed(&"ui_accept"):
		flip()
		accept_event()


func _draw() -> void:
	var h := minf(size.y, tokens.px(26.0 if not tokens.touch else 30.0))
	var w := minf(size.x, tokens.px(46.0))
	var r := Rect2(Vector2(0, (size.y - h) * 0.5), Vector2(w, h))
	var off := tokens.field_hover if _hover else tokens.field
	var track := off.lerp(tokens.accent, t)
	var sb := tokens.box(track, int(h / tokens.scale / 2.0) + 1)
	if not pressed and t < 0.5:
		sb.border_color = tokens.border.lerp(tokens.text_faint, 0.4)
		sb.set_border_width_all(1)
	draw_style_box(sb, r)
	var pad := tokens.px(3.0)
	var d := h - pad * 2.0
	var x := r.position.x + pad + (w - pad * 2.0 - d) * t
	var knob_col := tokens.text_dim.lerp(tokens.accent_ink if tokens.is_dark else Color.WHITE, t)
	if tokens.is_dark and t < 0.5:
		knob_col = tokens.text_dim
	draw_circle(Vector2(x + d * 0.5, r.position.y + h * 0.5), d * 0.5, knob_col)
	if has_focus():
		var ring := tokens.box(Color.TRANSPARENT, int(h / tokens.scale / 2.0) + 3, tokens.accent, maxi(2, tokens.px(2.0)))
		draw_style_box(ring, r.grow(tokens.px(3.0)))
