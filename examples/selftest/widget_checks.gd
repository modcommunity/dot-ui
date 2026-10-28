extends "selftest_base.gd"

## The crosshair, stat bar and ids sections of ui_selftest.gd, split out to keep that file under the size gate.


func _crosshair_alive_checks() -> void:
	var c := DotCrosshair.new()
	add_child(c)
	_check(c.is_shown(), "a crosshair is shown by default")
	var alive := [false]
	c.alive_source = func() -> bool: return alive[0]
	c._process(0.016)
	_check(not c.is_shown(), "hidden while the alive source says dead")
	alive[0] = true
	c._process(0.016)
	_check(c.is_shown(), "shown again once alive")
	c.alive_source = Callable()
	c.set_alive(false)
	_check(not c.is_shown(), "set_alive(false) hides it")
	c.hide_when_dead = false
	_check(c.is_shown(), "hide_when_dead = false opts out")
	_check(c.describe().get("alive") == false, "describe reports alive")
	remove_child(c)
	c.free()


func _test_crosshair() -> void:
	_section("crosshair")
	_crosshair_alive_checks()

	var crosshair := DotCrosshair.new()
	crosshair.base_gap = 4.0
	crosshair.fov_degrees = 90.0
	crosshair.max_gap = 200.0
	crosshair.size = Vector2(1920.0, 1080.0)

	var spread := [0.0]
	crosshair.source = func() -> Variant: return spread[0]
	add_child(crosshair)
	crosshair.size = Vector2(1920.0, 1080.0)

	_close(crosshair.gap_pixels(), 4.0, "zero spread sits at the base gap")

	spread[0] = 5.0
	crosshair.refresh()
	var wide := crosshair.gap_pixels()
	_check(wide > 4.0, "spread opens the crosshair", "%.1f" % wide)

	# The projection, not a made-up number: half the viewport height over the tangent
	# of half the field of view is the focal length in pixels.
	var focal := 540.0 / tan(deg_to_rad(90.0) * 0.5)
	_close(
		wide,
		4.0 + focal * tan(deg_to_rad(5.0)),
		"by the amount the camera projection actually gives",
		0.5
	)

	# A different field of view must give a different gap for the same spread. A
	# crosshair that assumes 90 is wrong at every other setting.
	crosshair.fov_degrees = 60.0
	var narrow := crosshair.gap_pixels()
	_check(
		narrow > wide,
		"a narrower field of view opens it further for the same angle",
		"%.1f vs %.1f" % [narrow, wide]
	)

	var ladder: Array[float] = []
	for deg: float in [0.5, 1.5, 3.5, 6.0]:
		spread[0] = deg
		crosshair.refresh()
		ladder.append(crosshair.gap_pixels())
	_check(ladder[0] < ladder[1] and ladder[1] < ladder[2] and ladder[2] < ladder[3], "the gap grows with every step of spread (still, walk, run, air)", str(ladder))

	spread[0] = 1.5
	crosshair.refresh()
	var usual := crosshair.gap_pixels()
	crosshair.gap_scale = 1.25
	_check(is_equal_approx(crosshair.gap_pixels(), minf(crosshair.max_gap, usual * 1.25)), "gap_scale multiplies the whole gap", "%.1f" % usual)
	crosshair.gap_scale = 1.0

	spread[0] = 80.0
	crosshair.refresh()
	_close(crosshair.gap_pixels(), 200.0, "and it is capped")

	# Aiming down the sights: the crosshair fades out, and back, never snaps.
	var aim := [0.0]
	crosshair.aim_source = func() -> float: return aim[0]
	crosshair.follow_aim(1.0)
	_close(crosshair.aim_opacity, 1.0, "at the hip the crosshair is all there")
	aim[0] = 1.0
	crosshair.follow_aim(0.016)
	_check(crosshair.aim_opacity > 0.0 and crosshair.aim_opacity < 1.0,
		"aiming fades it rather than snapping it off", "%.2f" % crosshair.aim_opacity)
	crosshair.follow_aim(1.0)
	_close(crosshair.aim_opacity, 0.0, "and fully aimed it is gone")
	_close(DotCrosshair.opacity_for_aim(0.25, 0.5), 0.5, "halfway to aim_hide_by it is half drawn")
	aim[0] = 0.0
	crosshair.follow_aim(0.016)
	_check(crosshair.aim_opacity < 1.0, "a released aim fades it back in too")
	crosshair.follow_aim(1.0)
	_close(crosshair.aim_opacity, 1.0, "and it returns whole")
	_close(DotCrosshair.opacity_for_aim(NAN), 1.0, "a NaN aim draws the crosshair rather than hiding it")

	_crosshair_cvar_checks(crosshair)

	crosshair.queue_free()
	remove_child(crosshair)
	_done()


func _crosshair_cvar_checks(crosshair: DotCrosshair) -> void:
	var cvars := DotCrosshairCvars.new()
	cvars.target = crosshair
	var seen := {}
	var local := _FakeLocal.new(seen)
	_check(cvars.bind_console(local) and seen.has(&"cl_crosshair_gap") and seen.has(&"cl_crosshair_colour"), "every crosshair cvar is registered")
	(seen[&"cl_crosshair_gap"] as Callable).call("9")
	_close(crosshair.base_gap, 9.0, "a cvar reaches the widget")
	(seen[&"cl_crosshair_style"] as Callable).call("1")
	_check(not crosshair.top_arm, "style 1 is a T")
	(seen[&"cl_crosshair_style"] as Callable).call("2")
	_close(crosshair.length, 0.0, "style 2 is a dot")
	(seen[&"cl_crosshair_dynamic"] as Callable).call("0")
	crosshair.set_spread(5.0)
	_close(crosshair.gap_pixels(), 9.0, "a static crosshair ignores the spread")
	(seen[&"cl_crosshair_colour"] as Callable).call("ff0000")
	_check(crosshair.colour.is_equal_approx(Color.RED), "colour is read from hex")
	var bad = (seen[&"cl_crosshair_size"] as Callable).call("x")
	_check(bad is DotResult and not (bad as DotResult).ok, "a bad value is refused")


class _FakeLocal:
	extends RefCounted
	var seen: Dictionary
	func _init(into: Dictionary) -> void:
		seen = into
	func add_var(name: StringName, _help: String, _get: Callable, set_it: Callable) -> void:
		seen[name] = set_it


func _test_stat_bar() -> void:
	_section("stat bar")

	var bar := DotStatBar.new()
	bar.max_value = 100.0
	bar.ease_sec = 0.0
	var health := [100.0]
	bar.source = func() -> Variant: return health[0]
	add_child(bar)

	_close(bar.fraction(), 1.0, "a full bar is full")

	health[0] = 25.0
	bar.refresh()
	_close(bar.fraction(), 0.25, "and follows the value")

	health[0] = -10.0
	bar.refresh()
	_close(bar.fraction(), 0.0, "a negative value clamps to empty")

	health[0] = 500.0
	bar.refresh()
	_close(bar.fraction(), 1.0, "and an overheal clamps to full")

	# A bar whose maximum changes: a magazine after a weapon switch.
	var magazine := [30.0]
	bar.max_source = func() -> Variant: return magazine[0]
	health[0] = 15.0
	bar.refresh()
	_close(bar.fraction(), 0.5, "a bound maximum is used")

	magazine[0] = 60.0
	bar.refresh()
	_close(bar.fraction(), 0.25, "and re-read when it changes")

	# The eased bar lags; the number must not.
	bar.ease_sec = 0.5
	health[0] = 60.0
	bar.refresh()
	_close(bar.fraction(), 1.0, "the reported fraction is the real value, not the eased one")

	bar.queue_free()
	remove_child(bar)
	_done()


func _registered_ids_checks() -> void:
	# registered_ids() must be alphabetical text, not StringName interning order.
	var order_stack := _make_stack()
	var made: Array[DotScreen] = []
	for n in ["zq_ids", "yq_ids", "xq_ids", "wq_ids", "vq_ids", "uq_ids", "tq_ids", "sq_ids"]:
		var sc := _make_screen(StringName(n))
		made.append(sc)
		order_stack.register(sc)
	var ids_listed := PackedStringArray()
	for sid in order_stack.registered_ids():
		ids_listed.append(String(sid))
	var ids_sorted := ids_listed.duplicate()
	ids_sorted.sort()
	_check(
		ids_listed == ids_sorted and ids_listed.size() == 8,
		"registered_ids() is sorted by text (%s)" % [ids_listed],
		"Array.sort() on StringNames orders by interning"
	)
