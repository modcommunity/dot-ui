class_name DotWinnerReveal
extends CanvasLayer

## The end-of-match announcement: the winner's name revealed under a title, then a podium of the
## top three rising, then [signal finished]. Skippable; [member reduced_motion] shows the final
## frame at once, with nothing moving. Driven by [method advance], so a test steps it exactly.

const CHANNEL := "dot_ui.winner"

## Podium layout per place (first, second, third): column height as a share of the screen, offset from centre in column widths and gaps, and rise start time.
const PODIUM_HEIGHTS: Array[float] = [0.3, 0.22, 0.16]
const PODIUM_COLS: Array[float] = [-0.5, -1.5, 0.5]
const PODIUM_GAPS: Array[float] = [0.0, -1.0, 1.0]
const PODIUM_STARTS: Array[float] = [1.6, 1.4, 1.2]

## The reveal is over (its time ran out, or [param skipped]).
signal finished(skipped: bool)

## Seconds it stays up when not skipped.
@export_range(1.0, 30.0, 0.5) var hold_seconds: float = 5.0

## Everything in its final place from the first frame, and no confetti.
@export var reduced_motion: bool = false

## Advance from [method Node._process]; a test turns this off and calls [method advance].
@export var auto_process: bool = true

## Input actions that skip it. Missing actions are ignored.
@export var skip_actions: PackedStringArray = ["ui_cancel", "ui_accept"]

## Colours. Null uses [method DotUiTheme.dark].
@export var palette: DotUiTheme = null

## Podium colours for first, second and third.
@export var medal_colours: Array[Color] = [Color(1.0, 0.8, 0.22), Color(0.78, 0.8, 0.86), Color(0.8, 0.52, 0.3)]

var root: Control = null
var backdrop: ColorRect = null
var title_label: Label = null
var name_label: Label = null
var subtitle_label: Label = null
var stripe: ColorRect = null
var hint_label: Label = null
var skip_button: Button = null
var confetti: CPUParticles2D = null
## One per podium place: {column: ColorRect, rank: Label, name: Label, score: Label, height: float}.
var places: Array[Dictionary] = []

var _t: float = -1.0
var _burst := false


func _init() -> void:
	layer = 95
	visible = false


func _ready() -> void:
	_build()


func is_active() -> bool:
	return _t >= 0.0


## Seconds since [method present], or -1 when idle.
func elapsed() -> float:
	return _t


## Shows [param entries] (best first: `name`, optional `score` text and `colour`). [param options]:
## `title` (default "WINNER"), `subtitle` (default the winner's score), `hint`.
func present(entries: Array, options: Dictionary = {}) -> DotResult:
	if entries.is_empty() or not (entries[0] is Dictionary):
		return DotResult.fail(DotError.CODE_INVALID, "A winner reveal needs at least one entry.")
	if root == null:
		_build()
	var winner: Dictionary = entries[0]
	var theme := palette if palette != null else DotUiTheme.dark()
	title_label.text = String(options.get("title", "WINNER"))
	name_label.text = String(winner.get("name", "?"))
	name_label.add_theme_color_override("font_color", winner.get("colour", theme.text))
	subtitle_label.text = String(options.get("subtitle", winner.get("score", "")))
	hint_label.text = String(options.get("hint", "Press Esc to skip"))
	stripe.color = theme.highlight
	for i in places.size():
		var place: Dictionary = places[i]
		var shown := i < entries.size() and entries[i] is Dictionary
		for key: String in ["column", "rank", "name", "score"]:
			(place[key] as CanvasItem).visible = shown
		if shown:
			(place["name"] as Label).text = String(entries[i].get("name", ""))
			(place["score"] as Label).text = String(entries[i].get("score", ""))
	_t = 0.0
	_burst = false
	visible = true
	_pose()
	DotLog.debug(CHANNEL, "winner reveal", {"winner": name_label.text, "places": mini(entries.size(), 3)})
	return DotResult.success()


func skip() -> void:
	if is_active():
		_end(true)


func advance(delta: float) -> void:
	if not is_active():
		return
	_t += delta
	if _t >= hold_seconds:
		_end(false)
		return
	_pose()


func _process(delta: float) -> void:
	if auto_process:
		advance(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active():
		return
	for action in skip_actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			skip()
			return


func _end(skipped: bool) -> void:
	_t = -1.0
	visible = false
	if confetti != null:
		confetti.emitting = false
	finished.emit(skipped)


# 0 before [param from], 1 after [param from] + [param span], eased between.
func _phase(from: float, span: float) -> float:
	if reduced_motion:
		return 1.0
	return clampf((_t - from) / span, 0.0, 1.0)


static func _ease_back(x: float) -> float:
	var c := 1.70158
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)


func _pose() -> void:
	var size := root.get_viewport_rect().size if root.is_inside_tree() else Vector2(1280, 720)
	root.size = size
	backdrop.size = size
	backdrop.color.a = 0.78 * _phase(0.0, 0.35)

	var unit := size.y / 720.0
	title_label.add_theme_font_size_override("font_size", int(34 * unit))
	name_label.add_theme_font_size_override("font_size", int(64 * unit))
	subtitle_label.add_theme_font_size_override("font_size", int(22 * unit))

	var t_in := _phase(0.15, 0.55)
	title_label.size = Vector2(size.x, 50 * unit)
	title_label.position = Vector2(0, size.y * 0.1)
	title_label.pivot_offset = title_label.size * 0.5
	title_label.scale = Vector2.ONE * lerpf(2.4, 1.0, _ease_back(t_in)) if t_in > 0.0 else Vector2.ONE
	title_label.modulate.a = t_in

	var n_in := _phase(0.55, 0.7)
	name_label.size = Vector2(size.x, 84 * unit)
	name_label.position = Vector2(0, size.y * 0.1 + 48 * unit)
	name_label.visible_ratio = n_in
	name_label.modulate.a = minf(1.0, n_in * 2.0)
	var stripe_w := size.x * 0.36 * _phase(0.5, 0.6)
	stripe.size = Vector2(stripe_w, maxf(3.0, 4.0 * unit))
	stripe.position = Vector2((size.x - stripe_w) * 0.5, name_label.position.y + 86 * unit)
	subtitle_label.size = Vector2(size.x, 34 * unit)
	subtitle_label.position = Vector2(0, stripe.position.y + 12 * unit)
	subtitle_label.modulate.a = _phase(1.1, 0.4)

	# Podium: second left, first centre, third right; third rises first.
	var col_w := minf(size.x * 0.17, 260 * unit)
	var gap := col_w * 0.12
	for i in places.size():
		var place: Dictionary = places[i]
		var start: float = PODIUM_STARTS[i]
		var height: float = size.y * PODIUM_HEIGHTS[i]
		var x: float = size.x * 0.5 + col_w * PODIUM_COLS[i] + gap * PODIUM_GAPS[i]
		var rise := _phase(start, 0.6)
		var h: float = height * (_ease_back(rise) if rise > 0.0 else 0.0)
		var col: ColorRect = place["column"]
		col.color = medal_colours[i] if i < medal_colours.size() else Color.GRAY
		col.color.a = 0.92
		col.size = Vector2(col_w, maxf(h, 0.0))
		col.position = Vector2(x, size.y - h)
		var rank: Label = place["rank"]
		rank.add_theme_font_size_override("font_size", int(54 * unit))
		rank.size = Vector2(col_w, 70 * unit)
		rank.position = Vector2(x, size.y - h + 8 * unit)
		rank.modulate.a = rise
		var label_in := _phase(start + 0.45, 0.35)
		for key: String in ["name", "score"]:
			var l: Label = place[key]
			l.add_theme_font_size_override("font_size", int((24 if key == "name" else 17) * unit))
			l.size = Vector2(col_w + gap * 2.0, 32 * unit)
			l.modulate.a = label_in
		(place["name"] as Label).position = Vector2(x - gap, size.y - height - 62 * unit)
		(place["score"] as Label).position = Vector2(x - gap, size.y - height - 34 * unit)

	hint_label.add_theme_font_size_override("font_size", int(15 * unit))
	hint_label.size = Vector2(size.x * 0.4, 32 * unit)
	hint_label.position = Vector2(size.x - 104 * unit - hint_label.size.x, size.y - 44 * unit)
	skip_button.position = Vector2(size.x - 92 * unit, size.y - 44 * unit)
	skip_button.size = Vector2(76 * unit, 32 * unit)
	skip_button.add_theme_font_size_override("font_size", int(15 * unit))

	if not reduced_motion and not _burst and _t >= 1.6 + 0.3:
		_burst = true
		confetti.position = Vector2(size.x * 0.5, size.y * 0.55)
		confetti.emission_rect_extents = Vector2(col_w * 1.5, 4.0)
		confetti.scale_amount_min = 4.0 * unit
		confetti.scale_amount_max = 8.0 * unit
		confetti.initial_velocity_min = 260.0 * unit
		confetti.initial_velocity_max = 520.0 * unit
		confetti.gravity = Vector2(0, 520.0 * unit)
		confetti.restart()


func _label(align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	root.add_child(l)
	return l


func _build() -> void:
	if root != null:
		return
	var theme := palette if palette != null else DotUiTheme.dark()
	root = Control.new()
	root.name = "WinnerReveal"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	backdrop = ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.05, 0.0)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(backdrop)

	for i in 3:
		var col := ColorRect.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(col)
		var rank := _label()
		rank.text = str(i + 1)
		rank.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
		var name_l := _label()
		name_l.add_theme_color_override("font_color", theme.text)
		name_l.clip_text = true
		var score_l := _label()
		score_l.add_theme_color_override("font_color", theme.text_dim)
		places.append({"column": col, "rank": rank, "name": name_l, "score": score_l})

	confetti = CPUParticles2D.new()
	confetti.emitting = false
	confetti.one_shot = true
	confetti.amount = 140
	confetti.lifetime = 2.6
	confetti.explosiveness = 0.9
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.direction = Vector2(0, -1)
	confetti.spread = 55.0
	confetti.angular_velocity_min = -540.0
	confetti.angular_velocity_max = 540.0
	confetti.angle_max = 360.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	ramp.colors = PackedColorArray([theme.highlight, theme.accent, theme.good, theme.danger])
	confetti.color_initial_ramp = ramp
	root.add_child(confetti)

	title_label = _label()
	title_label.add_theme_color_override("font_color", theme.highlight)
	name_label = _label()
	stripe = ColorRect.new()
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stripe)
	subtitle_label = _label()
	subtitle_label.add_theme_color_override("font_color", theme.text_dim)
	hint_label = _label(HORIZONTAL_ALIGNMENT_RIGHT)
	hint_label.add_theme_color_override("font_color", theme.text_dim)
	skip_button = Button.new()
	skip_button.text = "Skip"
	skip_button.focus_mode = Control.FOCUS_NONE
	skip_button.pressed.connect(skip)
	root.add_child(skip_button)


func describe() -> Dictionary:
	return {"active": is_active(), "elapsed": snappedf(_t, 0.01), "winner": name_label.text if name_label != null else "",
		"reduced_motion": reduced_motion}


func describe_lines() -> PackedStringArray:
	var d := describe()
	return PackedStringArray(["DotWinnerReveal: %s, %s" % [
		"showing %s at %.2f s" % [d["winner"], d["elapsed"]] if d["active"] else "idle",
		"reduced motion" if reduced_motion else "animated"]])
