extends Node

## DotHitFeedback, offline and headless.
##
## godot --headless --path . res://examples/hit_feedback_selftest.tscn

const CHECKS := 11

var _passed := 0
var _failed := 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % what)


func _run() -> void:
	print("dot-ui hit feedback self-test")
	var host := Control.new()
	host.size = Vector2(400.0, 300.0)
	add_child(host)
	var fx := DotHitFeedback.mount(host)
	await get_tree().process_frame
	_check(fx.get_parent() == host, "mounted under the host")
	_check(fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "layer ignores the mouse")
	_check(fx.marker.mouse_filter == Control.MOUSE_FILTER_IGNORE and fx.numbers.mouse_filter == Control.MOUSE_FILTER_IGNORE, "pieces ignore the mouse")
	_check(fx.numbers.get_index() < fx.marker.get_index(), "numbers under the marker")
	_check(fx.size == host.size, "full rect")
	_check(fx.marker.alpha() == 0.0 and fx.numbers.entries.is_empty(), "nothing until a hit")
	fx.confirm_hit_at(7, 20.0, Vector2(200.0, 150.0), false, false)
	_check(fx.marker.alpha() == 1.0 and not fx.marker.kill and fx.numbers.entries.size() == 1, "a hit flashes the marker and raises a number")
	fx.confirm_hit_at(7, 5.0, Vector2(200.0, 150.0), true, true)
	_check(fx.marker.kill and fx.marker.headshot, "a kill headshot is flagged")
	_check(fx.numbers.entries.size() == 1, "hits on one victim merge")
	fx.clear()
	_check(fx.marker.alpha() == 0.0, "clear ends the flash")
	_check(fx.numbers.entries.is_empty(), "and drops the numbers")
	print("%d checks of %d, %d failed" % [_passed + _failed, CHECKS, _failed])
	get_tree().quit(0 if _failed == 0 and _passed + _failed == CHECKS else 1)
