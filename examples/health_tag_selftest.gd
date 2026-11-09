extends Node

## DotHealthTag, offline and headless.
##
## godot --headless --path . res://examples/health_tag_selftest.tscn

const CHECKS := 10

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
	print("dot-ui health tag self-test")
	var tag := DotHealthTag.new()
	add_child(tag)
	tag.update(1.0, false, false, "", true, 0.016)
	_check(not tag.visible, "hidden with neither bar nor name")
	tag.update(0.5, true, true, "Ann", true, 0.016)
	_check(tag.visible, "shown with a bar and a name")
	tag.update(0.2, true, false, "Ann", true, 10.0)
	_check(is_equal_approx(tag.shown_fraction, 0.2), "the bar eases to its mark")
	_check(tag.trail_fraction >= tag.shown_fraction, "the trail never trails below the fill")
	tag.update(0.2, true, false, "Ann", true, 0.016, Color(0.2, 0.4, 1.0, 1.0), 0.7)
	_check(is_equal_approx(tag.scale.x, 0.7), "tag_scale sizes the tag")
	_check(DotHealthTag.fill_for(1.0) == DotHealthTag.FILL_FULL and DotHealthTag.fill_for(0.0) == DotHealthTag.FILL_LOW, "fill runs green to red")
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 0.0, 5.0)
	tag.face(cam)
	_check(tag.global_transform.basis.z.normalized().dot(Vector3.BACK) > 0.99, "faces a camera along +Z")
	cam.position = Vector3(0.0, 5.0, 0.0)
	tag.face(cam)
	_check(tag.global_transform.basis.is_finite() and absf(tag.global_transform.basis.z.normalized().dot(Vector3.UP)) > 0.99, "faces a camera straight above without a degenerate basis")
	tag.face(null)
	_check(true, "a null camera is ignored")
	var other := DotHealthTag.new()
	_check(other._bar.mesh == tag._bar.mesh, "tags share one mesh")
	other.free()
	tag.queue_free()
	print("%d checks of %d, %d failed" % [_passed + _failed, CHECKS, _failed])
	get_tree().quit(0 if _failed == 0 and _passed + _failed == CHECKS else 1)
