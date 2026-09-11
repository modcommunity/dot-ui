extends SceneTree

## Renders the shared screens to `screenshots/` so a person can look at them.
##
## [b]This addon had no picture of anything, and it is the addon that draws.[/b] Every
## check in `ui_selftest` is a size, a focus path, a stack depth or a visibility flag —
## and this family has shipped a 0 x 0 [Control] twice, a tab bar that hid two of its
## three tabs, and a silhouette that came out as a coloured bar, none of which any
## assertion could reach. The rule the games already follow is that an interface change
## wants a frame rendered and looked at; dot-ui was the one place that could not.
##
## Run it through `tools/screenshot.sh`, which uses `xvfb-run`. [b]Not `--headless`[/b]:
## that gives a null renderer and every frame it saves is empty, which is worse than no
## screenshot because it looks like one.

const OUT_DIR := "res://screenshots"

## Frames to let pass before grabbing.
##
## The viewport's texture is the last COMPLETED frame, so grabbing on the frame a screen
## was pushed saves whatever was on screen before it — which for the first shot is an
## empty viewport and looks exactly like a screen that failed to draw.
const SETTLE := 3

var _stack: DotScreenStack = null
var _hud: DotHud = null
var _shots: Array[Dictionary] = []
var _at := 0
var _wait := SETTLE
var _done := false


func _initialize() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	_stack = DotScreenStack.new()
	_stack.name = "Stack"
	_stack.register_service = false
	# Off, because there is nobody here to take the mouse back from.
	_stack.manage_mouse = false
	_stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_stack)
	_stack.setup()

	# A pause menu with the longest label any game in this family uses, because a button
	# that fits at "Resume" and clips at "Rock the vote" is exactly the kind of thing only
	# a picture shows -- and `TabBar.clip_tabs` already cost this family two unreachable
	# tabs for the same reason.
	var pause := DotPauseScreen.new()
	pause.name = "Pause"
	pause.build(PackedStringArray([
		"Resume", "Settings", "Interface", "Servers", "Rock the vote", "Leave",
	]))
	_stack.register(pause)

	# The settings screen over a real config with one of every editor kind in it: a
	# checkbox, a spin box, a line edit and an option button. A panel that laid one of
	# those out at zero height would still pass every check in the suite.
	var settings := DotSettingsScreen.new()
	settings.name = "Settings"
	settings.build(DotUiConfig.new())
	_stack.register(settings)

	_build_hud()

	_shots = [
		{"id": &"pause", "file": "pause.png"},
		{"id": &"settings", "file": "settings.png"},
		# Nothing, so the HUD behind the stack is what is drawn.
		{"id": &"", "file": "hud.png"},
	]


## A HUD with every widget this addon ships on it.
##
## [b]A HUD is the one interface surface in this family nothing had ever looked at.[/b]
## `DotStatBar`, `DotCrosshair` and `DotFeedView` are drawn entirely in `_draw` and by
## `Label`s this addon builds, and every check about them is a number or a property — the
## bar's eased value, the crosshair's computed gap, the feed's opacity at a given
## millisecond. All correct, and none of them says whether the thing is legible.
func _build_hud() -> void:
	_hud = DotHud.new()
	_hud.name = "Hud"
	_hud.config = DotUiConfig.new()
	root.add_child(_hud)

	# Health BELOW `low_fraction` and armour nearly full, because the low-value colour is
	# the state worth looking at and it is the one a fixture picked at random will miss:
	# the default threshold is 0.25, and a bar at 0.28 draws in the ordinary colour and
	# looks exactly like a bar whose low colour does not work.
	var health := DotStatBar.new()
	health.name = "Health"
	health.max_value = 100.0
	health.suffix = " HP"
	health.position = Vector2(40.0, 640.0)
	health.custom_minimum_size = Vector2(240.0, 28.0)
	health.size = health.custom_minimum_size
	_hud.add_child(health)
	# `bind`, not a setter: a widget PULLS. One wired to a signal misses the change that
	# happened before it was created and fires four times when four things change in one
	# tick, which is the reason this class holds a Callable at all.
	health.bind(func() -> float: return 18.0)
	health.refresh()

	var armour := DotStatBar.new()
	armour.name = "Armour"
	armour.max_value = 100.0
	armour.suffix = " AR"
	armour.fill_colour = Color(0.65, 0.72, 0.85)
	armour.position = Vector2(40.0, 680.0)
	armour.custom_minimum_size = Vector2(240.0, 28.0)
	armour.size = armour.custom_minimum_size
	_hud.add_child(armour)
	armour.bind(func() -> float: return 92.0)
	armour.refresh()

	var crosshair := DotCrosshair.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(crosshair)
	crosshair.bind(func() -> float: return 0.04)
	crosshair.refresh()

	var feed := DotFeedView.new()
	feed.name = "Feed"
	feed.position = Vector2(880.0, 40.0)
	feed.custom_minimum_size = Vector2(360.0, 160.0)
	feed.size = feed.custom_minimum_size
	_hud.add_child(feed)

	# Names of the length a real one has, and one headshot, because the marker is the part
	# a fixed-width fixture never exercises.
	feed.add_kill(
		"gamemann", Color(0.45, 0.75, 1.0), "rifle",
		"a_very_long_display_name", Color(1.0, 0.55, 0.4), true
	)
	feed.add_kill(
		"bo", Color(1.0, 0.55, 0.4), "grenade", "quiet_one", Color(0.45, 0.75, 1.0)
	)
	feed.add_kill("", Color.WHITE, "fell", "newcomer", Color(0.45, 0.75, 1.0))


func _process(_delta: float) -> bool:
	if _done:
		return true

	if _at >= _shots.size():
		_done = true
		return false

	var shot: Dictionary = _shots[_at]

	if _wait == SETTLE:
		_stack.clear()

		# An empty id means "show nothing", which is how the HUD gets a frame of its own:
		# the stack's `hides_below` takes it down under an opaque screen, deliberately.
		if str(shot["id"]) != "":
			_stack.push(StringName(shot["id"]))

	if _wait > 0:
		_wait -= 1
		return false

	var image := root.get_texture().get_image()
	var path := OUT_DIR.path_join(str(shot["file"]))
	image.save_png(path)
	print("wrote %s (%d x %d)" % [path, image.get_width(), image.get_height()])

	_at += 1
	_wait = SETTLE
	return false
