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
var _ballot: DotBallotPanel = null
var _result: DotBallotPanel = null
var _pieces: Control = null
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
		# A ballot over the HUD, mid-vote, with the mouse freed and a row hovered: the
		# state with the most on screen at once — numbers, a hint, counts, a crowded row
		# that has to squeeze its avatars, one picture avatar among initials, and the local
		# player's own choice marked.
		{"id": &"", "file": "ballot.png", "ballot": true},
		# The result of a ballot the local player decided with one click: they pick the last
		# row, the server closes it at once, and the frame a few frames later must already
		# show their avatar on that row. A game vote with one player on it does exactly this,
		# and a frame of it once showed the avatar a row short of the marked choice.
		{"id": &"", "file": "ballot_result.png", "result": true},
		# The glance pieces (DotVitals, DotAmmoCounter, DotScoreStrip, DotHitMarker,
		# DotDamageNumbers, DotKeyPrompt, DotKeyHints) laid out the way game-arena lays them
		# out, over a pale floor with a dark block, because pale ground is where the first
		# arena HUD vanished. A cover stand-in down the right edge, where a client shell
		# draws its ballots, sits over a right-hand hint column: that column must be dimmed.
		{"id": &"", "file": "hud_pieces.png", "pieces": "dark"},
		# The same in DotUiTheme.light(): every colour from the theme, dark numbers ringed in
		# light.
		{"id": &"", "file": "hud_pieces_light.png", "pieces": "light"},
		# The same HUD fitted to 854x480 (drawn in the top-left of the 1280x800 window,
		# inside the outline): scaled, never laid out again, so nothing may meet.
		{"id": &"", "file": "hud_pieces_small.png", "pieces": "small"},
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


## The glance pieces over a pale floor, the way game-arena places them. [param kind] is
## "dark" (no theme: the defaults), "light" (DotUiTheme.light()) or "small" (fitted to
## 854x480).
func _build_pieces(kind: String) -> void:
	if _pieces != null:
		_pieces.free()
	var frame := Vector2(854.0, 480.0) if kind == "small" else Vector2(1280.0, 800.0)
	_pieces = Control.new()
	_pieces.name = "Pieces"
	_pieces.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pieces.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pieces)

	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pieces.add_child(black)
	# Pale ground, the case that matters, with a dark block on the right third.
	var floor_rect := ColorRect.new()
	floor_rect.color = Color(0.88, 0.88, 0.85)
	floor_rect.size = frame
	_pieces.add_child(floor_rect)
	for i in range(0, int(frame.x), 64):
		var line := ColorRect.new()
		line.color = Color(0.72, 0.72, 0.70)
		line.position = Vector2(float(i), 0.0)
		line.size = Vector2(2.0, frame.y)
		_pieces.add_child(line)
	var block := ColorRect.new()
	block.color = Color(0.16, 0.18, 0.22)
	block.position = Vector2(frame.x * 0.66, frame.y * 0.25)
	block.size = Vector2(frame.x * 0.34, frame.y * 0.75)
	_pieces.add_child(block)

	var hud := DotHud.new()
	hud.name = "PiecesHud"
	hud.config = DotUiConfig.new()
	hud.fit_design = Vector2(1280.0, 720.0)
	if kind == "light":
		hud.theme = DotUiTheme.light().build()
	_pieces.add_child(hud)
	hud.fit_to_frame(frame)

	var vitals := DotVitals.new()
	_place(hud, vitals, Control.PRESET_BOTTOM_LEFT, Rect2(0.0, -84.0, 380.0, 76.0))
	# Under the 0.25 threshold, with armour: the low colour is the state worth seeing.
	vitals.show_vitals(18.0, 100.0, 45.0, 100.0)

	var ammo := DotAmmoCounter.new()
	_place(hud, ammo, Control.PRESET_BOTTOM_RIGHT, Rect2(-300.0, -84.0, 290.0, 70.0))
	ammo.show_ammo("Assault rifle", 7, 120, true)

	# The three states of the fire-mode indicator, stacked above the ammo plate.
	for i in range(3):
		var fm := DotFireModeIndicator.new()
		_place(hud, fm, Control.PRESET_BOTTOM_RIGHT, Rect2(-300.0, -122.0 - 32.0 * float(i), 290.0, 26.0))
		fm.show_modes([&"auto", &"semi", &"burst"], [&"auto", &"semi", &"burst"][i])

	var strip := DotScoreStrip.new()
	_place(hud, strip, Control.PRESET_CENTER_TOP, Rect2(-260.0, 0.0, 520.0, 72.0))
	strip.show_scores(23, 19, "BLUE", "RED", Color(0.22, 0.5, 0.95), Color(0.9, 0.24, 0.32))
	strip.show_clock(DotScoreStrip.clock_text(47.0), true, "First to 25", "Team deathmatch")

	var hints := DotKeyHints.new()
	_place(hud, hints, Control.PRESET_CENTER_LEFT, Rect2(62.0, -128.0, 220.0, 120.0))
	hints.show_hints([["Scoreboard", "Tab"], ["Vote", "F3"], ["Chat", "Y"], ["Throw", "Mouse back"]])

	var prompt := DotKeyPrompt.new()
	_place(hud, prompt, Control.PRESET_CENTER, Rect2(-330.0, 120.0, 300.0, 36.0))
	prompt.show_prompt("Open door", "E")

	var marker := DotHitMarker.new()
	marker.kill_sec = 600.0
	_place(hud, marker, Control.PRESET_FULL_RECT, Rect2())
	marker.flash(true, false)

	var numbers := DotDamageNumbers.new()
	numbers.life_sec = 600.0
	_place(hud, numbers, Control.PRESET_FULL_RECT, Rect2())
	var centre := hud.size * 0.5
	numbers.add_at(1, 27.0, centre + Vector2(140.0, 40.0))
	numbers.add_at(2, 104.0, centre + Vector2(-170.0, 10.0), true)

	# A client shell's ballot column, stand-in: in the cover group, over a right-hand hint
	# column, which must come out dimmed.
	var right_hints := DotKeyHints.new()
	right_hints.align_right = true
	_place(hud, right_hints, Control.PRESET_CENTER_RIGHT, Rect2(-280.0, -60.0, 270.0, 90.0))
	right_hints.show_hints([["Under a ballot", "F4"], ["Dimmed", "F5"]])
	var cover := ColorRect.new()
	cover.color = Color(0.1, 0.12, 0.2, 0.55)
	cover.add_to_group("dot_hud_cover")
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.position = Vector2(frame.x - 16.0 - minf(360.0, frame.x / 3.0), 110.0)
	cover.size = Vector2(minf(360.0, frame.x / 3.0), frame.y * 0.45)
	_pieces.add_child(cover)
	var cover_label := Label.new()
	cover_label.text = "cover stand-in\n(dot_hud_cover)"
	cover_label.position = Vector2(12.0, 8.0)
	cover.add_child(cover_label)

	if kind == "small":
		var edge := ReferenceRect.new()
		edge.border_color = Color(1.0, 0.2, 0.8)
		edge.border_width = 2.0
		edge.editor_only = false
		edge.size = frame
		_pieces.add_child(edge)


func _place(hud: Control, piece: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	piece.set_anchors_preset(preset)
	piece.offset_left = rect.position.x
	piece.offset_top = rect.position.y
	piece.offset_right = rect.end.x
	piece.offset_bottom = rect.end.y
	hud.add_child(piece)


func _build_ballot() -> void:
	_ballot = DotBallotPanel.new()
	_ballot.name = "Ballot"
	_ballot.position = Vector2(40.0, 120.0)
	_ballot.local_voter = "u3"
	_hud.add_child(_ballot)

	# A stand-in picture, generated: dot-ui ships no art, and the point is to see a texture
	# drawn where an initial would be.
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			image.set_pixel(x, y, Color(0.2 + x / 48.0, 0.3, 0.9 - y / 48.0))
	var picture := ImageTexture.create_from_image(image)
	_ballot.avatar_fn = func(voter: String, _url: String) -> Texture2D:
		return picture if voter == "u1" else null

	var voters := {}
	var people := {}
	var names := ["gamemann", "bo", "quiet_one", "newcomer", "ana", "zed", "kit", "mo", "lu", "pip", "rex"]
	var picks := [0, 0, 1, 1, 0, 2, 0, 0, 4, 0, 1]
	for i in names.size():
		voters["u%d" % (i + 1)] = picks[i]
		people["u%d" % (i + 1)] = {"name": names[i], "avatar": "https://example.invalid/%d.png" % i}

	_ballot.show_state({
		"open": true, "title": "Vote for the next map", "command": "votefor",
		"seconds": 24.0, "input": "both",
		"options": [
			{"id": "atrium", "label": "Atrium", "votes": 6.0},
			{"id": "foundry", "label": "Foundry (low gravity)", "votes": 3.0},
			{"id": "reactor", "label": "Reactor", "votes": 1.0},
			{"id": "yard", "label": "a_very_long_map_name_that_has_to_clip", "votes": 0.0},
			{"id": "extend", "label": "Extend", "votes": 1.0},
		],
		"voters": voters, "people": people,
	})
	_ballot.snap_avatars()


## A six-row ballot the local player decides: a click on the last row, and the close that
## follows at once, as a server with one voter on it sends.
func _build_result() -> void:
	_result = DotBallotPanel.new()
	_result.name = "Result"
	_result.position = Vector2(40.0, 120.0)
	_result.local_voter = "u3"
	_result.result_hold_sec = 30.0
	_hud.add_child(_result)
	_result.show_state({
		"open": true, "title": "Vote for the next game", "command": "game_vote",
		"seconds": 24.0, "input": "both",
		"options": [
			{"id": "wipeout", "label": "Wipeout", "votes": 0.0},
			{"id": "zombiezone", "label": "Zombie Zone", "votes": 0.0},
			{"id": "g2gfast", "label": "g2gfast", "votes": 0.0},
			{"id": "deathrun", "label": "Deathrun", "votes": 0.0},
			{"id": "arena", "label": "Arena", "votes": 0.0},
			{"id": "__keep__", "label": "Don't change", "votes": 0.0},
		],
		"voters": {}, "people": {"u3": {"name": "quiet_one", "avatar": ""}},
	})
	_result.snap_avatars()
	_result.choose(5)
	_result.show_state({"open": false, "winner": "Don't change"})


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

		if bool(shot.get("ballot", false)):
			if _ballot == null:
				_build_ballot()
			_ballot.visible = true
			_ballot._set_pointer(true)
			_ballot._hover = 1
		elif _ballot != null:
			_ballot.visible = false

		if bool(shot.get("result", false)):
			_build_result()

		var pieces := str(shot.get("pieces", ""))
		_hud.visible = pieces == ""
		if pieces != "":
			_build_pieces(pieces)
		elif _pieces != null:
			_pieces.free()
			_pieces = null

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
