extends Node

## Exercises everything in dot-ui, offline and headless.
##
## [codeblock]
## godot --headless --path . res://examples/ui_selftest.tscn
## [/codeblock]
##
## Exits non-zero on any failure, so it works as a smoke test as-is.
##
## Nothing is rendered — a headless run has no display — and nothing here depends on
## rendering. What is tested is the part that is actually hard: the four things a
## screen stack has to keep in agreement, a settings panel that must never show a
## secret, and a rebinder that must never leave an action bound to nothing.

const BINDINGS_FILE := "user://test_bindings.json"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()


## A config with one of everything, including a secret, so the generated panel can be
## checked against something with a known shape.
class TestConfig extends DotConfig:
	@export_group("Network")
	@export var port: int = 27015
	@export_range(1, 240, 1) var tick_rate: int = 64
	@export var hostname: String = "A server"
	@export var rcon_password: String = "hunter2"

	@export_group("Gameplay")
	@export var friendly_fire: bool = false
	@export_range(0.0, 10.0, 0.5) var gravity: float = 8.0
	@export_enum("easy", "normal", "hard") var difficulty: String = "normal"

	func env_prefix() -> String:
		return "TEST_"

	func cli_prefix() -> String:
		return "--test-"

	func sensitive_keys() -> PackedStringArray:
		return PackedStringArray(["rcon_password"])

	func validate() -> DotResult:
		if port < 1024:
			return DotResult.fail(
				DotError.CODE_INVALID, "Ports below 1024 need root."
			)
		return DotResult.success(null)


## A screen that records every lifecycle call, so the ordering can be asserted.
class TestScreen extends DotScreen:
	var id: StringName = &"test"
	var events: Array[String] = []
	var refuse_pop: bool = false

	func _screen_id() -> StringName:
		return id

	func _can_pop() -> bool:
		return not refuse_pop

	func _on_push() -> void:
		events.append("push")

	func _on_pop() -> void:
		events.append("pop")

	func _on_cover() -> void:
		events.append("cover")

	func _on_reveal() -> void:
		events.append("reveal")


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("dot-ui self-test")
	print("")

	_test_theme()
	_test_screen_stack()
	_test_stack_visibility()
	_test_stack_input_blocking()
	_test_stack_refusal()
	_test_hud()
	_test_widget_throttle()
	_test_stat_bar()
	_test_crosshair()
	_test_feed()
	_test_table()
	_test_settings_panel()
	_test_settings_apply()
	_test_bindings()

	DotPaths.remove_tree(BINDINGS_FILE)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	get_tree().quit(1 if _failed > 0 else 0)


# --- Assertions ------------------------------------------------------------

func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s — %s" % [what, detail])
		print("  FAIL  %s%s" % [what, "" if detail == "" else " — " + detail])
	return condition


func _close(a: float, b: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(a - b) <= epsilon, what, "%.3f vs %.3f" % [a, b])


func _group(title: String) -> void:
	print("")
	print("%s" % title)


# --- Fixtures --------------------------------------------------------------

func _make_stack() -> DotScreenStack:
	var stack := DotScreenStack.new()
	stack.register_service = false
	stack.manage_mouse = false
	stack.config = DotUiConfig.new()
	stack.config.allow_pause = false
	add_child(stack)
	return stack


func _make_screen(id: StringName) -> TestScreen:
	var screen := TestScreen.new()
	screen.id = id
	screen.name = String(id).capitalize()
	return screen


# --- Theme -----------------------------------------------------------------

func _test_theme() -> void:
	_group("theme")

	var palette := DotUiTheme.dark()
	var theme := palette.build(1.0)

	_check(theme != null, "a theme is built from a palette alone")
	_check(
		theme.default_font_size == palette.font_size,
		"at the declared font size",
		str(theme.default_font_size)
	)
	_check(
		theme.has_stylebox("normal", "Button"),
		"with a button style"
	)
	_check(
		theme.is_type_variation(&"DotHeading", &"Label"),
		"and a heading variation, so a heading is not a hand-set font size"
	)

	var big := palette.build(2.0)
	_check(
		big.default_font_size == palette.font_size * 2,
		"scaling scales the font",
		str(big.default_font_size)
	)

	# A fresh Theme per call. Handing out one shared mutable object means a game that
	# tweaks one window tweaks both.
	_check(
		palette.build(1.0) != theme,
		"each build produces its own Theme rather than a shared one"
	)

	var light := DotUiTheme.light()
	_check(
		light.text.get_luminance() < light.surface.get_luminance(),
		"the light palette is actually light"
	)


# --- Screen stack ----------------------------------------------------------

func _test_screen_stack() -> void:
	_group("screen stack")

	var stack := _make_stack()
	var menu := _make_screen(&"menu")
	var settings := _make_screen(&"settings")

	_check(stack.register(menu).ok, "a screen registers")
	_check(stack.register(settings).ok, "and another")
	_check(
		menu.get_parent() == stack,
		"registering reparents the screen, because z-order is sibling order"
	)
	_check(not menu.visible, "a registered screen starts hidden")

	# A registered screen has a SIZE, which is not free. `set_anchors_preset` sets
	# the anchors and leaves the offsets alone, so a Control built in code keeps the
	# zero size it was created with — the screen then lays out inside nothing and is
	# invisible while being, by every property, correctly configured. Nothing errors,
	# nothing warns, and only a screenshot shows it. dot-ui had five of them.
	_check(
		stack.size.x > 0.0 and stack.size.y > 0.0,
		"the stack fills its parent",
		"%.0f x %.0f" % [stack.size.x, stack.size.y]
	)
	_check(
		menu.size.is_equal_approx(stack.size),
		"and a screen fills the stack",
		"%.0f x %.0f" % [menu.size.x, menu.size.y]
	)

	# Two screens claiming the same id is a scene mistake that would otherwise show up
	# as one of them being unreachable.
	var clash := _make_screen(&"menu")
	_check(not stack.register(clash).ok, "two screens with one id is refused")
	clash.queue_free()

	_check(stack.push(&"menu").ok, "pushing opens a screen")
	_check(stack.top_id() == &"menu", "which is then on top")
	_check(menu.events == ["push"], "and was told", str(menu.events))
	_check(stack.any_open(), "the stack reports a menu is open")

	stack.push(&"settings")
	_check(stack.top_id() == &"settings", "pushing again stacks")
	_check(menu.events == ["push", "cover"], "and covers what was there", str(menu.events))
	_check(stack.depth() == 2, "to a depth of two")

	# The double-fire case. Pushing what is already open must not stack a second copy,
	# or one menu takes two escapes to close.
	stack.push(&"menu")
	_check(stack.depth() == 2, "pushing an open screen does not stack a second copy")
	_check(stack.top_id() == &"menu", "it is raised instead")

	stack.pop()
	_check(stack.top_id() == &"settings", "popping reveals what was underneath")

	stack.pop()
	_check(stack.depth() == 0, "and again empties the stack")
	_check(not stack.any_open(), "which is reported")

	# Popping from the middle rather than refusing: a screen closing itself in
	# response to a game event does not know what has been opened over it.
	stack.push(&"menu")
	stack.push(&"settings")
	_check(stack.pop(&"menu").ok, "a screen can be popped from under another")
	_check(stack.top_id() == &"settings", "leaving the top one alone")
	_check(stack.depth() == 1, "and the stack shorter")

	stack.clear()
	_check(stack.depth() == 0, "clearing empties it")

	# toggle and replace.
	stack.toggle(&"menu")
	_check(stack.is_open(&"menu"), "toggle opens")
	stack.toggle(&"menu")
	_check(not stack.is_open(&"menu"), "and closes")

	stack.push(&"menu")
	stack.replace(&"settings")
	_check(
		stack.depth() == 1 and stack.top_id() == &"settings",
		"replace swaps rather than stacking"
	)

	_check(not stack.push(&"nonexistent").ok, "pushing an unknown id fails")

	stack.queue_free()
	remove_child(stack)


func _test_stack_visibility() -> void:
	_group("screen stack: visibility")

	var stack := _make_stack()

	var menu := _make_screen(&"menu")
	var overlay := _make_screen(&"overlay")
	var opaque := _make_screen(&"opaque")

	overlay.hides_below = false
	opaque.hides_below = true

	stack.register(menu)
	stack.register(overlay)
	stack.register(opaque)

	stack.push(&"menu")
	stack.push(&"overlay")

	_check(menu.visible, "a transparent screen leaves what is below it visible")
	_check(overlay.visible, "and is visible itself")

	stack.push(&"opaque")
	_check(not menu.visible, "an opaque screen hides what is below it")
	_check(not overlay.visible, "all of it")
	_check(opaque.visible, "and is visible itself")

	stack.pop()
	_check(menu.visible, "and popping it brings them back")

	# Z-order is sibling order. A stack that did not maintain it would render a menu
	# under the screen that opened it.
	_check(
		stack.get_child(stack.get_child_count() - 1) == overlay,
		"the top screen is the last sibling",
		stack.get_child(stack.get_child_count() - 1).name
	)

	stack.queue_free()
	remove_child(stack)


func _test_stack_input_blocking() -> void:
	_group("screen stack: input")

	var stack := _make_stack()

	var scoreboard := _make_screen(&"scoreboard")
	scoreboard.blocks_input = false
	scoreboard.hides_below = false

	var menu := _make_screen(&"menu")
	menu.blocks_input = true

	stack.register(scoreboard)
	stack.register(menu)

	stack.push(&"scoreboard")
	_check(
		scoreboard.mouse_filter == Control.MOUSE_FILTER_STOP,
		"the top screen takes input"
	)

	# The distinction that matters: a scoreboard held down over a live game is visible
	# and must not stop the player moving, which is a different thing from being
	# invisible.
	_check(
		scoreboard.visible and not scoreboard.blocks_input,
		"a non-blocking screen is visible and does not block"
	)

	stack.push(&"menu")
	_check(
		scoreboard.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"a blocking screen above stops the one below receiving input"
	)

	stack.pop()
	_check(
		scoreboard.mouse_filter == Control.MOUSE_FILTER_STOP,
		"and popping gives it back"
	)

	stack.queue_free()
	remove_child(stack)


func _test_stack_refusal() -> void:
	_group("screen stack: refusing to close")

	var stack := _make_stack()
	var modal := _make_screen(&"modal")
	modal.refuse_pop = true

	stack.register(modal)
	stack.push(&"modal")

	_check(not stack.pop().ok, "a screen can refuse to close")
	_check(stack.is_open(&"modal"), "and stays open")

	modal.refuse_pop = false
	_check(stack.pop().ok, "and closes once it stops refusing")

	var locked := _make_screen(&"locked")
	locked.closable = false
	stack.register(locked)
	stack.push(&"locked")
	_check(not stack.pop().ok, "an unclosable screen cannot be popped")

	# pop_to must not spin forever on a screen that will not close.
	stack.push(&"modal")
	var popped := stack.pop_to()
	_check(
		popped <= 1 and stack.is_open(&"locked"),
		"clearing stops at a screen that refuses rather than looping",
		"%d popped, depth %d" % [popped, stack.depth()]
	)

	locked.closable = true
	stack.clear()

	stack.queue_free()
	remove_child(stack)


# --- HUD -------------------------------------------------------------------

func _test_hud() -> void:
	_group("hud")

	var stack := _make_stack()
	var hud := DotHud.new()
	hud.config = DotUiConfig.new()
	add_child(hud)

	_check(
		hud.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"a HUD never eats the click that should have fired the weapon"
	)

	var opaque := _make_screen(&"opaque")
	opaque.hides_below = true
	var overlay := _make_screen(&"overlay")

	stack.register(opaque)
	stack.register(overlay)
	hud.bind_stack(stack)

	stack.push(&"overlay")
	_check(hud.visible, "a transparent screen leaves the HUD up")

	stack.push(&"opaque")
	_check(not hud.visible, "an opaque one takes it down")

	stack.pop()
	_check(hud.visible, "and closing it brings it back")

	# The game's own hide is separate, so closing a menu does not undo it.
	hud.set_hidden_by_game(true)
	_check(not hud.visible, "a game can hide the HUD itself")
	stack.push(&"overlay")
	stack.pop()
	_check(not hud.visible, "and a menu opening and closing does not undo that")
	hud.set_hidden_by_game(false)
	_check(hud.visible, "until the game says otherwise")

	# The safe area, which is what stops an ammo counter under a camera cutout.
	hud.config.safe_area = 24.0
	hud.config.scale = 2.0
	hud._apply_safe_area()
	_close(hud.offset_left, 48.0, "the safe area is inset and scaled")
	_close(hud.offset_right, -48.0, "on both sides")

	hud.queue_free()
	remove_child(hud)
	stack.queue_free()
	remove_child(stack)


func _test_widget_throttle() -> void:
	_group("hud widget")

	var widget := DotHudWidget.new()
	var reads: Array[int] = []
	var current := [7]

	widget.source = func() -> Variant:
		reads.append(1)
		return current[0]

	add_child(widget)

	_check(widget.value == 7, "a widget reads its source on ready")

	# Captured Arrays rather than counters: a GDScript lambda captures locals by
	# value, so an incremented int stays zero outside the lambda and the assertion
	# reports a failure for a callable that fired perfectly.
	var refreshes: Array[int] = []
	widget.refreshed.connect(func(_v: Variant) -> void: refreshes.append(1))

	current[0] = 9
	widget.refresh()
	_check(widget.value == 9, "and again when refreshed")
	_check(refreshes.size() == 1, "emitting once")

	widget.refresh_on_change = false
	widget.refresh_rate = 10.0
	current[0] = 11

	widget._process(0.05)
	_check(widget.value == 9, "the throttle holds a value back")
	widget._process(0.06)
	_check(widget.value == 11, "and lets it through on schedule")

	# Change-driven refresh, for anything where lateness is a lie.
	widget.refresh_on_change = true
	current[0] = 13
	widget._process(0.001)
	_check(widget.value == 13, "a change is picked up immediately when asked for")

	widget.queue_free()
	remove_child(widget)


func _test_stat_bar() -> void:
	_group("stat bar")

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


func _test_crosshair() -> void:
	_group("crosshair")

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

	spread[0] = 80.0
	crosshair.refresh()
	_close(crosshair.gap_pixels(), 200.0, "and it is capped")

	crosshair.queue_free()
	remove_child(crosshair)


# --- Feed and table --------------------------------------------------------

func _test_feed() -> void:
	_group("feed")

	var feed := DotFeedView.new()
	feed.max_lines = 3
	feed.lifetime_sec = 5.0
	feed.fade_sec = 1.0
	add_child(feed)

	feed.add_text("one")
	feed.add_text("two")
	_check(feed.line_count() == 2, "lines are added")

	feed.add_text("three")
	feed.add_text("four")
	_check(feed.line_count() == 3, "and bounded", str(feed.line_count()))

	# Driven with an explicit clock rather than by waiting: a test that waits out six
	# real seconds is a test nobody runs.
	var now := Time.get_ticks_msec()
	_check(feed.expire(now) == 0, "nothing expires early")
	_check(feed.expire(now + 6000) == 3, "and everything does once it is due")
	_check(feed.line_count() == 0, "leaving the feed empty")

	var line := feed.add_text("fading")
	_close(feed.opacity_of(line, now), 1.0, "a fresh line is opaque")
	_close(
		feed.opacity_of(line, now + 4500),
		0.5,
		"and fades over the last of its life",
		0.05
	)
	_close(feed.opacity_of(line, now + 5000), 0.0, "to nothing")

	# Held lines never expire. A chat message that fades while you are reading it is
	# a message you have to ask someone to repeat.
	feed.hold = true
	feed.add_text("held")
	_check(feed.expire(now + 100000) == 0, "a held feed expires nothing")
	_close(feed.opacity_of(line, now + 100000), 1.0, "and stays opaque")

	feed.hold = false
	feed.clear()

	var kill := feed.add_kill(
		"Alice", Color.RED, "rifle", "Bob", Color.BLUE, true
	)
	var parts: Array = kill["parts"]
	_check(parts.size() >= 3, "a kill line is built from coloured fragments")
	_check(
		str((parts[0] as Dictionary)["text"]) == "Alice",
		"starting with the killer"
	)

	var world := feed.add_kill("", Color.RED, "fall", "Bob", Color.BLUE)
	var world_parts: Array = world["parts"]
	_check(
		str((world_parts[0] as Dictionary)["text"]).begins_with("["),
		"and a world death has no killer fragment"
	)

	feed.queue_free()
	remove_child(feed)


func _test_table() -> void:
	_group("table")

	var table := DotTableView.new()
	add_child(table)

	table.set_columns(DotTableView.scoreboard_columns())
	_check(table.columns.size() == 6, "the standard scoreboard columns exist")

	var rows: Array[Dictionary] = []
	for index in range(10):
		rows.append({
			&"name": "Player %d" % index,
			&"kills": index,
			&"deaths": 10 - index,
			&"assists": 0,
			&"score": index * 2,
			&"ping": 30,
			"highlight": index == 3,
		})

	table.set_rows(rows)
	_check(table.row_count() == 10, "rows are held")
	_check(table.visible_row_count() == 10, "and all shown by default")

	# A 64-player server produces 64 rows of Labels for a scoreboard nobody scrolls.
	table.max_rows = 5
	table.set_rows(rows)
	_check(table.visible_row_count() == 5, "a row cap limits what is built")

	table.clear()
	_check(table.row_count() == 0, "clearing empties it")

	table.queue_free()
	remove_child(table)


# --- Settings --------------------------------------------------------------

func _test_settings_panel() -> void:
	_group("settings panel")

	var config := TestConfig.new()
	var panel := DotSettingsPanel.new()
	add_child(panel)

	var res := panel.bind(config)
	_check(res.ok, "a panel builds itself from a config")
	_check(int(res.value) == 6, "with a control per editable key", str(res.value))

	# The one that matters: a secret must never end up in a screenshot or a pasted
	# bug report, which is the same reason DotConfig refuses them from argv.
	_check(
		panel.editor_for("rcon_password") == null,
		"and never one for a secret"
	)

	_check(panel.editor_for("friendly_fire") is CheckBox, "a bool is a checkbox")
	_check(panel.editor_for("port") is SpinBox, "an int is a spin box")
	_check(panel.editor_for("hostname") is LineEdit, "a string is a line edit")
	_check(
		panel.editor_for("difficulty") is OptionButton,
		"and an enum is an option button"
	)

	var spin := panel.editor_for("tick_rate") as SpinBox
	_close(spin.min_value, 1.0, "a range hint becomes the spin box's minimum")
	_close(spin.max_value, 240.0, "and its maximum")
	_close(spin.value, 64.0, "starting at the config's value")

	var options := panel.editor_for("difficulty") as OptionButton
	_check(
		options.get_item_text(options.selected) == "normal",
		"an enum starts on the config's value",
		options.get_item_text(options.selected)
	)

	# Group filtering.
	var filtered := DotSettingsPanel.new()
	filtered.only_groups = ["Gameplay"]
	add_child(filtered)
	var count := filtered.bind(config)
	_check(int(count.value) == 3, "a group filter narrows the panel", str(count.value))
	_check(filtered.editor_for("port") == null, "leaving the other group out")

	panel.queue_free()
	remove_child(panel)
	filtered.queue_free()
	remove_child(filtered)


func _test_settings_apply() -> void:
	_group("settings panel: applying")

	var config := TestConfig.new()
	var panel := DotSettingsPanel.new()
	panel.live = false
	add_child(panel)
	panel.bind(config)

	(panel.editor_for("port") as SpinBox).value = 27016.0
	_check(panel.has_pending(), "an edit is held rather than written through")
	_check(config.port == 27015, "and the config is untouched")

	var applied: Array[int] = []
	panel.applied.connect(func() -> void: applied.append(1))

	_check(panel.apply().ok, "applying writes them")
	_check(config.port == 27016, "and the config has the new value")
	_check(applied.size() == 1, "and says so")
	_check(not panel.has_pending(), "with nothing left pending")

	# The rollback. Applying half of an invalid set leaves the config in a state
	# nobody chose, and the player cannot tell which half survived.
	var failures: Array[String] = []
	panel.apply_failed.connect(
		func(error: DotError) -> void: failures.append(error.message)
	)

	(panel.editor_for("port") as SpinBox).value = 80.0
	(panel.editor_for("hostname") as LineEdit).text = "New name"
	panel.editor_for("hostname").focus_exited.emit()

	var refused := panel.apply()
	_check(not refused.ok, "an invalid set is refused")
	_check(config.port == 27016, "the invalid value is rolled back")
	_check(
		config.hostname == "A server",
		"and so is the valid one that came with it",
		config.hostname
	)
	_check(failures.size() == 1, "and the failure is reported")

	panel.revert()
	_check(not panel.has_pending(), "reverting throws the edits away")
	_check(
		(panel.editor_for("port") as SpinBox).value == 27016.0,
		"and puts the controls back"
	)

	# Live mode writes through.
	var live_panel := DotSettingsPanel.new()
	live_panel.live = true
	add_child(live_panel)
	live_panel.bind(config)
	(live_panel.editor_for("friendly_fire") as CheckBox).button_pressed = true
	_check(config.friendly_fire, "a live panel writes through immediately")

	panel.queue_free()
	remove_child(panel)
	live_panel.queue_free()
	remove_child(live_panel)


# --- Bindings --------------------------------------------------------------

func _test_bindings() -> void:
	_group("bindings")

	for action in [&"test_fire", &"test_jump", &"test_use"]:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action)

	var fire := InputEventKey.new()
	fire.physical_keycode = KEY_F
	InputMap.action_add_event(&"test_fire", fire)

	var jump := InputEventKey.new()
	jump.physical_keycode = KEY_SPACE
	InputMap.action_add_event(&"test_jump", jump)

	var panel := DotBindingsPanel.new()
	panel.config = DotUiConfig.new()
	panel.config.bindings_file = BINDINGS_FILE
	panel.prefix = "test_"
	add_child(panel)

	var built := panel.build()
	_check(built.ok and int(built.value) == 3, "a row per rebindable action",
		str(built.value))
	_check(
		panel.rebindable_actions().size() == 3,
		"and Godot's own ui_ actions are left out"
	)
	_check(
		panel.describe_binding(&"test_fire") == "F",
		"a binding reads back",
		panel.describe_binding(&"test_fire")
	)
	_check(
		panel.describe_binding(&"test_use") == "—",
		"and an unbound action says so"
	)

	# The conflict, detected before committing so a refusal changes nothing.
	var taken := InputEventKey.new()
	taken.physical_keycode = KEY_SPACE
	var clash := panel.bind_action(&"test_fire", taken)
	_check(not clash.ok, "binding a key another action has is refused")
	_check(
		panel.describe_binding(&"test_fire") == "F",
		"and the old binding is untouched"
	)
	_check(
		panel.conflicting_action(&"test_fire", taken) == &"test_jump",
		"with the conflicting action named"
	)

	var free_key := InputEventKey.new()
	free_key.physical_keycode = KEY_G
	_check(panel.bind_action(&"test_fire", free_key).ok, "a free key binds")
	_check(panel.describe_binding(&"test_fire") == "G", "and takes effect")

	panel.refuse_conflicts = false
	_check(
		panel.bind_action(&"test_fire", taken).ok,
		"conflicts can be permitted deliberately"
	)
	panel.refuse_conflicts = true
	panel.bind_action(&"test_fire", free_key)

	# Persistence, through DotPaths so a web build's IndexedDB is flushed.
	DotPaths.remove_tree(BINDINGS_FILE)
	_check(panel.save().ok, "bindings save")

	var restore := InputEventKey.new()
	restore.physical_keycode = KEY_Z
	panel.refuse_conflicts = false
	panel.bind_action(&"test_fire", restore)
	panel.refuse_conflicts = true
	_check(panel.describe_binding(&"test_fire") == "Z", "then are changed")

	var loaded := panel.load_saved()
	_check(loaded.ok, "and load back")
	_check(
		panel.describe_binding(&"test_fire") == "G",
		"restoring what was saved",
		panel.describe_binding(&"test_fire")
	)

	# The one that leaves a player stuck: a truncated or hand-edited file that gives
	# an action no events at all.
	DotPaths.write_json(
		BINDINGS_FILE, {"bindings": {"test_fire": []}}, true, true
	)
	panel.load_saved()
	_check(
		panel.describe_binding(&"test_fire") != "—",
		"an action a saved file leaves unbound is put back to its default",
		panel.describe_binding(&"test_fire")
	)

	# A garbage file must not be applied as though it were valid.
	DotPaths.write_json(BINDINGS_FILE, {"nonsense": 1}, true, true)
	_check(
		not panel.load_saved().ok,
		"a bindings file with no bindings is refused"
	)

	# Locked actions are never offered.
	panel.config.locked_actions = [&"test_fire"]
	_check(
		not panel.rebindable_actions().has(&"test_fire"),
		"a locked action is not rebindable"
	)

	panel.reset_all()
	panel.queue_free()
	remove_child(panel)

	for action in [&"test_fire", &"test_jump", &"test_use"]:
		InputMap.erase_action(action)
