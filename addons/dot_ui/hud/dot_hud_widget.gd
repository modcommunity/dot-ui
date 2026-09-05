@tool
class_name DotHudWidget
extends Control

## Base for anything that shows a number the game already has.
##
## [b]Widgets pull, they are not pushed.[/b] A health bar wired to a `health_changed`
## signal is a health bar that misses the change that happened before it was created,
## and that fires four times when four things change in one tick. A widget here holds a
## [Callable] that reads the value and re-reads it on a throttle.
##
## The throttle is the second half: a HUD refreshed at frame rate is a HUD that
## re-lays-out text sixty times a second to show a number that changes twice. The
## default is ten times a second, which is faster than anyone can read.

## The value changed and the widget redrew.
signal refreshed(value: Variant)

@export_group("Source")

## Refreshes per second. Zero refreshes only when [method refresh] is called.
@export_range(0.0, 60.0, 1.0) var refresh_rate: float = 10.0

## Refresh immediately when the value differs, ignoring the throttle.
##
## For anything where lateness is a lie rather than a delay: a health bar during a
## burst, an ammo counter mid-magazine.
@export var refresh_on_change: bool = true

## `func() -> Variant`. Reads the value. Left unset the widget shows nothing.
var source: Callable = Callable()

## The value at the last refresh.
var value: Variant = null

var _accumulator: float = 0.0
var _has_value: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()


## Binds a reader. Returns self, so a HUD is one chained expression.
func bind(reader: Callable) -> DotHudWidget:
	source = reader
	refresh()
	return self


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not source.is_valid():
		return

	if refresh_on_change:
		var current: Variant = source.call()

		if not _has_value or not _same(current, value):
			_commit(current)
			return

	if refresh_rate <= 0.0:
		return

	_accumulator += delta

	if _accumulator < 1.0 / refresh_rate:
		return

	_accumulator = 0.0
	refresh()


## Re-reads the value now.
func refresh() -> void:
	if not source.is_valid():
		return

	_commit(source.call())


func _commit(current: Variant) -> void:
	value = current
	_has_value = true
	_accumulator = 0.0
	_on_value(current)
	refreshed.emit(current)


static func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false

	if typeof(a) == TYPE_FLOAT:
		return is_equal_approx(float(a), float(b))

	return a == b


# --- Subclass interface ----------------------------------------------------

## Called with the new value. Update the display here.
func _on_value(_current: Variant) -> void:
	pass


func describe() -> Dictionary:
	return {
		"node": name,
		"bound": source.is_valid(),
		"value": value,
		"rate": refresh_rate,
	}
