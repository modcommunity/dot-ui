extends SceneTree

## Renders DotTouchButtons at phone size (390x844 portrait, 844x390 landscape) over a pale floor to screenshots/touch_buttons*.png.
## Run through tools/touch_shot.sh (xvfb-run, not --headless).

const OUT := "res://screenshots"


func _initialize() -> void:
	DotPlatform.touch_override = 1
	root.size = Vector2i(390, 844)
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.85, 0.85, 0.82)
	floor_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(floor_rect)
	var buttons := DotTouchButtons.new()
	buttons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	buttons.set_buttons(DotTouchButtons.fps_stock())
	root.add_child(buttons)
	await _frames(6)
	await _shot("touch_buttons")
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = true
	e.position = buttons.centre_of(&"fire")
	buttons._input(e)
	root.size = Vector2i(844, 390)
	await _shot("touch_buttons_landscape")
	quit(0)


func _shot(name: String) -> void:
	await _frames(4)
	var err := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT, name]))
	print("%s %s" % ["wrote" if err == OK else "FAILED", name])


func _frames(n: int) -> void:
	for i in n:
		await process_frame
