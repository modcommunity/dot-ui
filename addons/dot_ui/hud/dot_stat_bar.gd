@tool
class_name DotStatBar
extends DotHudWidget

## A number, a bar, or both. Health, armour, ammunition, a capture progress ring.
##
## Draws itself rather than composing a [ProgressBar] and a [Label], because a HUD
## element that is a container of two Controls is three nodes and two theme lookups to
## show one number, and a HUD has a dozen of them.

@export_group("Range")

## Denominator. Read from [member max_source] when one is bound.
@export var max_value: float = 100.0

## `func() -> float`. Reads the maximum, for a bar whose maximum changes — a magazine
## after a weapon switch, health after a buff.
var max_source: Callable = Callable()

@export_group("Appearance")

## Show the bar.
@export var show_bar: bool = true

## Show the number.
@export var show_text: bool = true

## Format applied to the value. `%d` and `%.0f` are the usual ones.
@export var format: String = "%d"

## Appended after the formatted value: `%`, ` HP`, a reserve count.
@export var suffix: String = ""

@export var fill_colour: Color = Color(0.35, 0.70, 1.0, 1.0)

## Used when the fraction is at or below [member low_fraction].
@export var low_colour: Color = Color(0.90, 0.30, 0.28, 1.0)

@export_range(0.0, 1.0, 0.01) var low_fraction: float = 0.25

@export var track_colour: Color = Color(0.0, 0.0, 0.0, 0.45)

@export var text_colour: Color = Color(0.95, 0.96, 0.98, 1.0)

@export_range(0.0, 40.0, 1.0) var bar_height: float = 8.0

@export_group("Motion")

## Seconds the bar takes to catch up with a change. Zero snaps.
##
## Lag on a bar is a readability feature — a hit that takes a third of your health is
## legible as a slide and invisible as a jump — and it is a lie about the current
## value, so the *number* never lags.
@export_range(0.0, 2.0, 0.05) var ease_sec: float = 0.15

var _shown: float = 0.0
var _target: float = 0.0
var _max: float = 100.0


func _ready() -> void:
	super._ready()
	_max = max_value
	custom_minimum_size.y = maxf(custom_minimum_size.y, bar_height)


func _on_value(current: Variant) -> void:
	_target = float(current) if typeof(current) != TYPE_NIL else 0.0

	if max_source.is_valid():
		var limit: Variant = max_source.call()
		_max = maxf(0.0001, float(limit))
	else:
		_max = maxf(0.0001, max_value)

	if ease_sec <= 0.0:
		_shown = _target

	queue_redraw()


func _process(delta: float) -> void:
	super._process(delta)

	if is_equal_approx(_shown, _target):
		return

	if ease_sec <= 0.0:
		_shown = _target
	else:
		# Exponential rather than linear: a linear catch-up takes the same time for a
		# one-point change as for a hundred-point one, which reads as a bar that is
		# broken for small hits.
		_shown = lerpf(_shown, _target, clampf(delta / ease_sec, 0.0, 1.0))

		if absf(_shown - _target) < 0.01:
			_shown = _target

	queue_redraw()


func fraction() -> float:
	return clampf(_target / _max, 0.0, 1.0)


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	var filled := clampf(_shown / _max, 0.0, 1.0)
	var colour := low_colour if fraction() <= low_fraction else fill_colour

	if show_bar:
		var bar := Rect2(
			Vector2(0.0, size.y - bar_height), Vector2(size.x, bar_height)
		)
		draw_rect(bar, track_colour)
		draw_rect(
			Rect2(bar.position, Vector2(bar.size.x * filled, bar.size.y)), colour
		)

	if not show_text:
		return

	var font := get_theme_default_font()

	if font == null:
		return

	var font_size := get_theme_default_font_size()
	var text := (format % _target) + suffix
	var text_size := font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)

	draw_string(
		font,
		Vector2(0.0, text_size.y),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		box.size.x,
		font_size,
		text_colour
	)


func describe() -> Dictionary:
	var out := super.describe()
	out["max"] = _max
	out["fraction"] = fraction()
	return out
