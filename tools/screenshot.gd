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
var _chat: DotChatWindow = null
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
		# The same HUD with the chat box open. Two pictures rather than one because the
		# closed state is the one every player spends the match looking at, and the open
		# state is the only one with a prompt, a caret and a line that must not overlap
		# the log above it.
		{"id": &"", "file": "chat.png", "chat": true},
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
	health.position = Vector2(40.0, 470.0)
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
	armour.position = Vector2(40.0, 510.0)
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

	# Moved up off the bottom-left corner, because that is where the chat box goes by
	# default and the first picture of the two together was a stat bar drawn through a
	# line of chat. Which is a real warning for a game, not only for this fixture: see
	# `DotChatWindow.place_bottom_left`.
	#
	# The chat box, with the traffic a real one has: a long handle, a line long enough to
	# reach the right edge, a system line with no speaker, and a team line in the team
	# colour. A box that lays out correctly for "hi" is a box nobody has looked at.
	_chat = DotChatWindow.new()
	_chat.name = "Chat"
	_chat.register_actions = false
	# Nothing expires in a screenshot. Under software rendering a frame takes the better
	# part of a second, so a ten-second lifetime is spent before the grab — which is a
	# picture of an empty log that looks exactly like a log that cannot draw.
	_chat.lifetime_sec = 0.0
	_chat.channels = [
		{"id": &"all", "label": "Say", "colour": Color(0.88, 0.90, 0.94)},
		{"id": &"team", "label": "Say (TEAM)", "colour": Color(0.55, 0.85, 0.60), "team": true},
	]
	_hud.add_child(_chat)

	_chat.add_text("Welcome to the server.", Color(0.80, 0.82, 0.86))
	_chat.add_said("gamemann", "anybody up for a round on the atrium map?")
	_chat.add_said("a_very_long_display_name", "give me a minute, reloading content")
	_chat.add_said("quiet_one", "rotating B, need one more", Color(0.55, 0.85, 0.60))
	_chat.add_said(
		"bo",
		"that long sentence above is the one that matters here: it has to wrap inside the"
			+ " box rather than run across the middle of the screen"
	)


func _process(_delta: float) -> bool:
	if _done:
		return true

	if _at >= _shots.size():
		_done = true
		return false

	var shot: Dictionary = _shots[_at]

	if _wait == SETTLE:
		_stack.clear()

		if bool(shot.get("chat", false)):
			_chat.open(&"team")
		else:
			_chat.close()

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
