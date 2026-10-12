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

const CHECKS := 386

## Sections entered against sections that ran to their last line, and against this. A
## runtime error inside a section aborts that function and nothing says so; a section that
## bailed out early after a failed guard is counted as not finished on purpose. The CHECKS
## total is the other half — see docs/testing.md.
const SECTIONS := 28

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


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
	_test_input_binding()
	_test_chat_window()
	_test_ballot_panel()
	_test_ballot_avatar_rows()
	_test_hud_piece()
	_test_hud_fit()
	_test_vitals()
	_test_ammo_counter()
	_test_score_strip()
	_test_hit_marker()
	_test_damage_numbers()
	_test_key_prompt_and_hints()
	await _test_settings_screen()
	await _test_scoreboard_screen()

	DotPaths.remove_tree(BINDINGS_FILE)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	print("%d of %d sections ran to their last line" % [_completed, _entered])
	if _entered != SECTIONS or _completed != _entered:
		print("ERROR: %d sections entered and %d completed, %d expected. One aborted or was skipped." % [
			_entered, _completed, SECTIONS
		])
		get_tree().quit(1)
		return
	# The total the section counter cannot be. A runtime error inside a section aborts
	# that function, and the counter is satisfied because the section had already
	# announced itself. See docs/testing.md.
	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		get_tree().quit(1)
		return
	get_tree().quit(1 if _failed > 0 else 0)


# --- Assertions ------------------------------------------------------------

## The shared scoreboard: the game's rows and columns, an icon column, a title.
func _test_scoreboard_screen() -> void:
	_section("scoreboard screen")

	var stack := DotScreenStack.new()
	add_child(stack)
	var board := DotScoreboardScreen.new()
	board.title_text = "Course 3"
	var avatar := GradientTexture2D.new()
	board.columns = [
		{"key": &"avatar", "kind": &"icon", "width": 0.0, "size": 20.0},
		{"key": &"name", "title": "Player", "width": 3.0},
		{"key": &"points", "title": "Points", "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"ping", "title": "Ping", "align": HORIZONTAL_ALIGNMENT_RIGHT},
	]
	var rows := [
		{&"avatar": avatar, &"name": "Ada", &"points": 30, &"ping": 41, "highlight": true},
		{&"avatar": null, &"name": "Bo", &"points": 10, &"ping": 77},
	]
	board.row_fn = func() -> Array: return rows
	stack.register(board)
	var pushed := stack.push(&"scoreboard")
	await get_tree().process_frame

	_check(pushed.ok and stack.top_id() == &"scoreboard", "a game registers it and pushes it by its id")
	_check(not board.blocks_input, "and it does not stop the player moving")
	_check(board.table.row_count() == 2 and board._title.text == "Course 3",
		"it shows the game's rows under the game's title")
	var first_row := board.table._grid.get_child(1)
	_check(first_row.get_child(0) is TextureRect and (first_row.get_child(0) as TextureRect).texture == avatar,
		"an icon column draws the row's picture")
	var second_row := board.table._grid.get_child(2)
	_check(second_row.get_child(0) is TextureRect and (second_row.get_child(0) as TextureRect).texture == null,
		"and a player with none keeps the column's width")

	stack.queue_free()
	_done()


func _section(title: String) -> void:
	_entered += 1
	_group(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


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


# --- The glance pieces -------------------------------------------------------

## A piece in the tree, laid out at [param rect] in this node's space.
func _piece(piece: DotHudPiece, rect: Rect2) -> DotHudPiece:
	piece.position = rect.position
	piece.size = rect.size
	add_child(piece)
	return piece


## Colours from the theme or the defaults, and what a piece does under a cover.
func _test_hud_piece() -> void:
	_section("hud piece: theme and cover")

	var vitals := _piece(DotVitals.new(), Rect2(0.0, 600.0, 380.0, 76.0)) as DotVitals
	vitals.show_vitals(60.0, 100.0)
	_check(vitals.mouse_filter == Control.MOUSE_FILTER_IGNORE, "a piece never takes the click that fires the weapon")
	_check(vitals.colour(&"low") == DotHudPiece.DEFAULTS[&"low"], "with no theme a piece draws in the defaults")
	var palette := DotUiTheme.light()
	palette.danger = Color(0.7, 0.1, 0.6)
	vitals.theme = palette.build()
	_check(vitals.colour(&"low") == palette.danger, "with a theme, in the theme's colours")
	_check(vitals.colour(&"plate").a < 1.0, "and the plate is see-through, not a panel")
	vitals.theme = null

	# The default is the dark HUD (first play test, 2026-10-11): a dark plate, light words.
	_check(DotHudPiece.DEFAULTS[&"plate"].get_luminance() < 0.1 and DotHudPiece.DEFAULTS[&"plate"].a >= 0.7,
		"the default plate is deep and dark, and opaque enough to read on a white wall")
	_check(DotHudPiece.DEFAULTS[&"keycap"].get_luminance() < 0.3 and DotHudPiece.DEFAULTS[&"keycap_text"].get_luminance() > 0.8,
		"and a default key cap is a dark cap with a light letter, not a white tile")
	_check(vitals.number(&"team_fill") == DotHudPiece.DEFAULT_CONSTANTS[&"team_fill"],
		"a constant with no theme is the default")
	for key in DotHudPiece.COLOUR_KEYS:
		if not DotHudPiece.DEFAULTS.has(key):
			_check(false, "every colour key has a default: %s" % key)
	# A layer theme from colours: every piece and every plain Label under the node follows it.
	var layer := Control.new()
	layer.size = Vector2(800.0, 700.0)
	add_child(layer)
	var lit := DotHudPiece.theme_from({&"plate": Color(0.9, 0.9, 0.9, 0.8), &"text": Color(0.1, 0.1, 0.1), &"ink": Color(1, 1, 1, 0.9)}, {&"team_fill": 100})
	layer.theme = lit
	var under := DotVitals.new()
	layer.add_child(under)
	var words := Label.new()
	layer.add_child(words)
	_check(under.colour(&"plate") == Color(0.9, 0.9, 0.9, 0.8) and under.colour(&"text") == Color(0.1, 0.1, 0.1),
		"a layer theme reaches a piece under it")
	_check(under.colour(&"low") == DotHudPiece.DEFAULTS[&"low"], "and a colour it leaves out is still the default")
	_check(under.number(&"team_fill") == 100, "and its constants")
	_check(words.get_theme_color(&"font_color") == Color(0.1, 0.1, 0.1) and words.get_theme_constant(&"outline_size") > 0
		and words.get_theme_color(&"font_outline_color") == Color(1, 1, 1, 0.9),
		"and a plain Label under it takes the text colour, outlined in the ink")
	layer.theme = DotHudPiece.theme_from({&"plate": Color(0.02, 0.02, 0.04, 0.75)})
	_check(under.colour(&"plate") == Color(0.02, 0.02, 0.04, 0.75), "a new layer theme is followed at once, nothing rebuilt")
	layer.queue_free()
	var built := DotUiTheme.dark().build()
	vitals.theme = built
	_check(vitals.colour(&"keycap").get_luminance() < 0.4 and vitals.number(&"team_fill") < 100,
		"DotUiTheme's dark palette gives dark caps and tinted score plates")
	vitals.theme = DotUiTheme.light().build()
	_check(vitals.number(&"team_fill") == 100, "and its light one painted plates, the bright look")
	vitals.theme = null
	# The engine's own theme has a default font, which made `has_theme_font` true for every
	# name, so the pieces drew regular weight: the bold fallback is what no theme gives.
	_check(vitals.font() == DotHudPiece.bold_font() and vitals._theme_font() == null,
		"with no theme font on the type, a piece draws bold, not the engine's regular weight")
	var with_font := Theme.new()
	var chosen := SystemFont.new()
	with_font.set_font(&"font", DotHudPiece.THEME_TYPE, chosen)
	vitals.theme = with_font
	_check(vitals.font() == chosen, "and a font a theme sets on the type replaces it")
	vitals.theme = null

	_check(vitals.footprint().has_area(), "a piece says where it draws")
	vitals.refresh_cover()
	_check(not vitals.covered and vitals.self_modulate.a == 1.0, "nothing over it: drawn in full")

	# A ballot stand-in, in the group by its string, over the piece's plate.
	var cover := Control.new()
	cover.position = Vector2(100.0, 580.0)
	cover.size = Vector2(300.0, 200.0)
	cover.add_to_group("dot_hud_cover")
	add_child(cover)
	_check(DotHudPiece.covered_rect(vitals).has_area(), "the cover is found by its group, in the piece's own space")
	vitals.refresh_cover()
	_check(vitals.covered, "a cover over its footprint is seen")
	_close(vitals.self_modulate.a, vitals.cover_alpha, "and the piece dims under it, so the ballot reads")
	vitals.cover_mode = DotHudPiece.CoverMode.HIDE
	vitals.refresh_cover()
	_close(vitals.self_modulate.a, 0.0, "or hides, when told to")
	cover.visible = false
	vitals.refresh_cover()
	_check(not vitals.covered and vitals.self_modulate.a == 1.0, "a hidden cover covers nothing")
	cover.visible = true
	cover.position = Vector2(500.0, 580.0)
	vitals.refresh_cover()
	_check(not vitals.covered, "nor does one beside the footprint, inside the control's rect or not")
	cover.position = Vector2(100.0, 580.0)
	vitals.cover_mode = DotHudPiece.CoverMode.IGNORE
	vitals.refresh_cover()
	_check(not vitals.covered and vitals.self_modulate.a == 1.0, "IGNORE draws through it")

	var marker := DotHitMarker.new()
	_check(marker.cover_mode == DotHudPiece.CoverMode.IGNORE,
		"the crosshair's pieces ignore covers: their rect is the whole HUD, which always meets one")
	marker.free()

	cover.queue_free()
	vitals.queue_free()
	_done()


## The HUD scaled below the frame it was designed for, never laid out again.
func _test_hud_fit() -> void:
	_section("hud fit")

	_close(DotHud.fit_scale(Vector2(1280.0, 720.0)), 1.0, "1280x720 is drawn as designed")
	_close(DotHud.fit_scale(Vector2(1920.0, 1080.0)), 1.0, "a larger frame does not grow the HUD")
	_close(DotHud.fit_scale(Vector2(854.0, 480.0)), 480.0 / 720.0, "854x480 scales by the short side's share")
	_close(DotHud.fit_scale(Vector2(720.0, 1280.0)), 720.0 / 1280.0, "a portrait frame by its width")
	_close(DotHud.fit_scale(Vector2(320.0, 180.0)), 0.5, "never under half")

	var hud := DotHud.new()
	hud.config = DotUiConfig.new()
	hud.config.safe_area = 16.0
	hud.fit_design = Vector2(1280.0, 720.0)
	add_child(hud)
	hud.fit_to_frame(Vector2(854.0, 480.0))
	_close(hud.fit(), 480.0 / 720.0, "a HUD with a design frame scales itself")
	_close(hud.position.x + (hud.size.x + 16.0) * hud.fit(), 854.0, "and still fills the frame, inset included", 0.5)
	var ammo := DotAmmoCounter.new()
	ammo.position = Vector2(100.0, 100.0)
	ammo.size = Vector2(290.0, 70.0)
	hud.add_child(ammo)
	ammo.show_ammo("Rifle", 30, 90)
	var on_screen := ammo.get_global_transform() * ammo.footprint()
	_close(on_screen.size.x, ammo.footprint().size.x * hud.fit(), "a piece inside it is drawn at the HUD's scale", 0.5)
	hud.fit_to_frame(Vector2(1600.0, 900.0))
	_close(hud.fit(), 1.0, "and back at full size on a big frame")
	hud.user_scale = 0.8
	hud.fit_to_frame(Vector2(1600.0, 900.0))
	_close(hud.fit(), 0.8, "the player's HUD size multiplies the fit")
	_close(hud.position.x + (hud.size.x + 16.0) * hud.fit(), 1600.0, "and the HUD still reaches the frame's far edge", 0.5)
	hud.fit_to_frame(Vector2(854.0, 480.0))
	_close(hud.fit(), 0.8 * 480.0 / 720.0, "on a small frame too")
	hud.queue_free()

	# A plain Control as a HUD root (most games: a full-rect Control under a CanvasLayer).
	var root := Control.new()
	add_child(root)
	DotHud.fit_control(root, Vector2(1280.0, 720.0), 1.25)
	_close(root.scale.x, 1.25, "a plain HUD root is scaled")
	_close(root.size.x * root.scale.x, 1280.0, "and sized so its anchors still reach the frame's edges", 0.5)
	root.queue_free()
	_done()


func _test_vitals() -> void:
	_section("vitals")

	var v := _piece(DotVitals.new(), Rect2(0.0, 0.0, 380.0, 76.0)) as DotVitals
	# Under the 0.25 threshold: the state the low colour exists for.
	v.show_vitals(18.0, 100.0)
	_check(v.is_low() and v.number_text() == "18", "18 of 100 is low, and says 18")
	_close(v.shown_fraction(), 0.18, "the first value is drawn at once, not eased in from full")
	var plain := v.footprint()
	_check(plain.size.x > v.bar_end and plain.size.y == 56.0, "the plate reaches past the bar to the number")
	v.show_vitals(0.4, 100.0)
	_check(v.number_text() == "1", "0.4 is alive, and says 1, not 0")

	v.show_vitals(100.0, 100.0)
	v.advance(10.0)
	v.show_vitals(50.0, 100.0)
	_check(v.number_text() == "50", "the number is the value at once")
	v.advance(0.03)
	_check(v.shown_fraction() < 1.0 and v.shown_fraction() > 0.5, "the bar slides toward it", "%.3f" % v.shown_fraction())
	v.advance(5.0)
	_close(v.shown_fraction(), 0.5, "and arrives")
	_check(not v.is_low(), "half is not low")

	v.show_vitals(50.0, 100.0, 40.0, 100.0, 20.0)
	_check(v.footprint().size.y == 72.0, "armour makes the plate taller for its bar")
	_close(v.bonus, 20.0, "a bonus is kept beside the real health")
	v.show_status("DOWN")
	_check(v.number_text() == "DOWN", "a status replaces the number")
	v.show_status("")
	_check(v.number_text() == "50", "and clearing it brings the number back")
	_check(int(v.describe().get("health", -1)) == 50, "describe() reports the health")
	v.queue_free()
	_done()


func _test_ammo_counter() -> void:
	_section("ammo counter")

	var a := _piece(DotAmmoCounter.new(), Rect2(0.0, 0.0, 290.0, 70.0)) as DotAmmoCounter
	_check(not a.footprint().has_area(), "nothing in hand draws nothing")
	a.show_ammo("Rifle", 12, 90)
	_check(a.count_text() == "12 | 90", "magazine | reserve")
	var full := a.footprint()
	_check(full.end.x <= a.size.x + 14.0 + 0.5 and full.size.y == 70.0, "right-aligned, on a plate for the name and the count")
	a.show_ammo("Pistol", 7, 0, false, true)
	_check(a.count_text() == "7 | ∞", "an endless reserve draws as one")
	a.show_ammo("Pistol", 7, -1)
	_check(a.count_text() == "7", "no reserve draws the magazine alone")
	a.show_ammo("Knife", -1, -1)
	_check(a.count_text() == "" and a.footprint().size.y == 32.0, "a weapon with no magazine shows its name alone")
	a.show_ammo("Rifle", 3, 90, true)
	_check(a.low, "the host says when it is low")
	a.clear()
	_check(not a.footprint().has_area(), "and clear() takes it down")
	a.queue_free()
	_done()


func _test_score_strip() -> void:
	_section("score strip")

	_check(DotScoreStrip.clock_text(0.0) == "0:00", "0:00 at the end")
	_check(DotScoreStrip.clock_text(59.2) == "1:00", "rounded up, so it never says 0:00 with time left")
	_check(DotScoreStrip.clock_text(61.0) == "1:01", "M:SS")
	_check(DotScoreStrip.clock_text(3661.0) == "1:01:01", "H:MM:SS from an hour")
	_check(DotScoreStrip.clock_text(-4.0) == "0:00", "never negative")

	var s := _piece(DotScoreStrip.new(), Rect2(0.0, 0.0, 520.0, 72.0)) as DotScoreStrip
	_check(not s.footprint().has_area(), "nothing handed over draws nothing")
	s.show_clock(DotScoreStrip.clock_text(95.0), false, "", "")
	var clock_only := s.footprint()
	_check(not s.sides and is_equal_approx(clock_only.size.x, DotScoreStrip.CLOCK_W), "a game with no scores gets the clock alone")
	_close(clock_only.get_center().x, 260.0, "centred on the control's middle")
	s.show_scores(12, 9, "BLUE", "RED", Color.BLUE, Color.RED)
	_check(s.sides and s.footprint().size.x > clock_only.size.x * 2.0, "two sides put the plates either side of it")
	s.show_clock("0:09", true, "First to 25", "Team deathmatch")
	_check(s.under_text() == "First to 25   ·   Team deathmatch", "what wins and the mode, under them")
	_check(s.footprint().size.y > DotScoreStrip.H, "and the footprint takes the line in")
	s.hide_scores()
	_check(not s.sides, "a mode with no sides takes the plates down")
	s.queue_free()
	_done()


func _test_hit_marker() -> void:
	_section("hit marker")

	var m := _piece(DotHitMarker.new(), Rect2(0.0, 0.0, 400.0, 300.0)) as DotHitMarker
	_check(m.alpha() == 0.0 and not m.footprint().has_area(), "nothing until a hit")
	m.flash()
	_close(m.alpha(), 1.0, "a confirmed hit flashes it")
	_close(m.footprint().get_center().x, 200.0, "round the middle, where the crosshair is")
	m.advance(m.hit_sec + 0.01)
	_close(m.alpha(), 0.0, "and it is gone after hit_sec")
	m.flash(true)
	m.advance(0.05)
	m.flash(false)
	_check(m.kill, "a pellet after the lethal one does not turn the kill marker white")
	_close(m.life, m.kill_sec, "and a kill holds longer than a hit")
	m.advance(m.kill_sec)
	m.flash(false, true)
	_check(not m.kill and m.headshot, "after it fades, the next hit is its own")
	m.queue_free()
	_done()


func _test_damage_numbers() -> void:
	_section("damage numbers")

	var d := _piece(DotDamageNumbers.new(), Rect2(0.0, 0.0, 400.0, 300.0)) as DotDamageNumbers
	d.add_at(7, 20.0, Vector2(200.0, 150.0))
	d.advance(0.1)
	d.add_at(7, 15.0, Vector2(200.0, 150.0), true)
	_check(d.texts() == PackedStringArray(["35"]), "a burst on one victim adds up into one number", str(d.texts()))
	_check(bool(d.entries[0]["headshot"]), "and a headshot in it marks the total")
	d.add_at(8, 9.0, Vector2(100.0, 150.0))
	_check(d.entries.size() == 2, "another victim gets a number of its own")
	_check(d.footprint().has_area(), "and they say where they draw")
	d.advance(d.merge_sec + 0.05)
	d.add_at(7, 5.0, Vector2(200.0, 150.0))
	_check(d.entries.size() == 3, "a hit after merge_sec is a new number")
	d.advance(d.life_sec + 0.01)
	_check(d.entries.is_empty(), "every number fades out")
	# A world point with no camera: headless, and a host that has not attached one yet.
	d.add(9, 10.0, Vector3(0.0, 1.0, -5.0))
	_check(not d.footprint().has_area(), "with no camera a world point is not drawn, and nothing fails")
	d.clear()
	_check(d.entries.is_empty(), "clear() empties it")
	d.queue_free()
	_done()


func _test_key_prompt_and_hints() -> void:
	_section("key prompt and hints")

	var p := _piece(DotKeyPrompt.new(), Rect2(0.0, 0.0, 400.0, 40.0)) as DotKeyPrompt
	p.show_prompt("Open door", "E")
	_check(p.visible and p.text() == "Open door  E", "a prompt says what and which key")
	_close(p.footprint().get_center().x, 200.0, "centred on its middle")
	var with_key := p.footprint().size.x
	p.show_prompt("Spent", "")
	_check(p.text() == "Spent" and p.footprint().size.x < with_key, "a prompt with no key is the words alone")
	p.clear()
	_check(not p.visible and not p.footprint().has_area(), "nothing to say hides it")

	var h := _piece(DotKeyHints.new(), Rect2(0.0, 0.0, 300.0, 200.0)) as DotKeyHints
	h.show_hints([["Scoreboard", "Tab"], ["Vote", "F3"], ["Chat", "Y"]])
	var left := h.footprint()
	_check(is_equal_approx(left.size.y, 3.0 * h.row_height), "a row per hint")
	_check(left.position.x == 0.0, "from the left edge by default")
	h.align_right = true
	_check(is_equal_approx(h.footprint().end.x, 300.0), "or to the right edge")
	h.clear()
	_check(not h.footprint().has_area(), "and clear() takes them down")
	p.queue_free()
	h.queue_free()
	_done()


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
	_section("theme")

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
	_done()


# --- Screen stack ----------------------------------------------------------

func _test_screen_stack() -> void:
	_section("screen stack")

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
	_done()


func _test_stack_visibility() -> void:
	_section("screen stack: visibility")

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
	_done()


func _test_stack_input_blocking() -> void:
	_section("screen stack: input")

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
	_done()


func _test_stack_refusal() -> void:
	_section("screen stack: refusing to close")

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
	_done()


# --- HUD -------------------------------------------------------------------

func _test_hud() -> void:
	_section("hud")

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
	_done()


func _test_widget_throttle() -> void:
	_section("hud widget")

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
	_done()


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


func _test_crosshair() -> void:
	_section("crosshair")

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

	crosshair.queue_free()
	remove_child(crosshair)
	_done()


# --- Feed and table --------------------------------------------------------

func _test_feed() -> void:
	_section("feed")

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
	_done()


func _test_table() -> void:
	_section("table")

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
	_done()


# --- Settings --------------------------------------------------------------

	# EVERY COLUMN GETS ROOM, which is what a rendered frame of a scoreboard found.
	#
	# An absent `width` used to mean `SIZE_FILL`, which reads as "take your content's
	# width" and is not: `clip_text` sets a Label's minimum size to ZERO, so a column with
	# no width collapsed to nothing. `scoreboard_columns()` gives a width only to `name`,
	# so every scoreboard and every server browser in this family drew ONE column -- no
	# kills, no deaths, no score, no ping -- with the data correct and `describe()`
	# agreeing. Armed by putting the `0.0` default back: this check fails, and nothing
	# about rows, columns or values does.
	var widths := DotTableView.new()
	add_child(widths)
	widths.set_columns(DotTableView.scoreboard_columns())
	widths.set_rows([{&"name": "somebody", &"kills": 3, &"deaths": 1, &"assists": 0,
		&"score": 3, &"ping": 40}])

	# A GridContainer, so the header is the first N children of the grid rather than a row
	# node of its own. Counted over that first row only: the data rows are built by the
	# same call and would double every number.
	# A VBox of HBoxes, so the header is the first row and its cells are that row's
	# children. It is an HBox rather than a `GridContainer` because a GridContainer gives
	# every column the SAME width whatever ratio a cell asks for -- see `_ensure_grid`.
	var grid := widths.get_node_or_null("Grid") as VBoxContainer
	var wanted := DotTableView.scoreboard_columns().size()
	var expanding := 0
	var ratios := PackedFloat32Array()

	if grid != null and grid.get_child_count() > 0:
		for cell in grid.get_child(0).get_children():
			var label := cell as Control
			if label == null:
				continue
			ratios.append(label.size_flags_stretch_ratio)
			if label.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
				expanding += 1

	_check(
		expanding == wanted,
		"every scoreboard column asks for room (%d of %d)" % [expanding, wanted],
		"a column with no width used to collapse to nothing, so only Player was drawn"
	)

	# AND THE RATIOS ARE HONOURED, which they were not for the life of this class.
	#
	# `size_flags_stretch_ratio` is read by a `BoxContainer` and by nothing else, so the
	# `GridContainer` this used to be gave every column the same width — `width` was
	# documented, set to 3.0 for the name column in `scoreboard_columns()`, and inert.
	# Measured before the fix: ratios 0.4, 3.0, 1.0, 1.0 came out 308 pixels each.
	_check(
		ratios.size() == wanted and is_equal_approx(ratios[0], 3.0),
		"and the name column asks for three times the share (%s)" % [ratios]
	)
	_check(
		grid.get_child(0) is HBoxContainer,
		"because a row is a BoxContainer, which is the only thing that reads a ratio"
	)

	widths.queue_free()


func _test_settings_panel() -> void:
	_section("settings panel")

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
	_done()


func _test_settings_apply() -> void:
	_section("settings panel: applying")

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
	_done()


# --- Bindings --------------------------------------------------------------

## A source that is not a DotConfig: `to_config()` out, `absorb_config()` back.
##
## Deliberately NOT a `DotSettingsManager`. dot-ui depends on dot-core and nothing else,
## and a suite that could only test this against the real thing would be a suite proving
## the dependency rather than the seam. A plain `RefCounted` with two methods is the whole
## contract, and that this passes is what says so.
class FakeSettingsSource:
	extends RefCounted

	var stored: Dictionary = {"port": 111, "hostname": "before"}
	var absorbed := 0

	func to_config() -> DotConfig:
		var cfg := TestConfig.new()
		cfg.port = int(stored["port"])
		cfg.hostname = str(stored["hostname"])
		return cfg

	func absorb_config(cfg: DotConfig) -> PackedStringArray:
		absorbed += 1
		var changed := PackedStringArray()
		var typed := cfg as TestConfig
		if typed.port != int(stored["port"]):
			stored["port"] = typed.port
			changed.append("port")
		if typed.hostname != str(stored["hostname"]):
			stored["hostname"] = typed.hostname
			changed.append("hostname")
		return changed


func _test_settings_screen() -> void:
	_section("settings screen")

	var stack := DotScreenStack.new()
	stack.register_service = false
	stack.manage_mouse = false
	add_child(stack)
	stack.setup()

	# A bare DotConfig first: the screen has to work without dot-settings existing at all,
	# which is the case every project that has dot-ui and not dot-settings is in.
	var direct := TestConfig.new()
	var plain := DotSettingsScreen.new()
	plain.name = "PlainSettings"
	_check(plain.build(direct).ok, "a screen builds straight onto a DotConfig")
	stack.register(plain)
	stack.push(&"settings")
	await get_tree().process_frame
	await get_tree().process_frame

	# The one thing an assertion reaches about a Control, and this family has shipped a
	# 0 x 0 one twice.
	_check(plain.size.x > 0.0 and plain.size.y > 0.0, "and it has a size")
	var body := plain.get_node_or_null("Panel") as Control
	_check(body != null and body.size.y > 0.0, "and so does the panel inside it")
	_check(
		plain.get_node_or_null(plain.initial_focus) != null,
		"with a focus path that resolves, which get_path() before the tree does not"
	)

	# THE CHECK A PICTURE HAD TO FIND FIRST.
	#
	# A `DotSettingsPanel` is as tall as the document it was handed, and `DotUiConfig` alone
	# comes out around 600 pixels. Without a scroll container the column grew past the panel
	# and past the bottom of the SCREEN, taking Apply, Revert and Back with it -- a settings
	# screen a player can read and cannot save from or leave. Every assertion passed: the
	# screen had a size, the panel had a size, the editors existed, and Apply worked when
	# called in code.
	# A STRUCTURAL CHECK, DELIBERATELY, because the behavioural ones cannot fail here.
	#
	# The bug was the panel growing past the bottom of the window and taking Apply, Revert
	# and Back with it — a settings screen a player can read and cannot save from. Three
	# assertions were tried against it and all three passed with the bug in place:
	#
	#   "Apply is inside the panel"   — a PanelContainer GROWS to fit, so the button stays
	#                                   inside a panel that has itself left the window.
	#   "Apply is inside the screen"  — a headless viewport is 64 x 64, so every screen in
	#                                   this suite is 64 x 64 and nothing measured against
	#                                   one means anything. `plain.size.y > 0` passes at 64
	#                                   as happily as at 800.
	#   "a long and a short document  — at 64 x 64 the layout resolves the same either way.
	#    make the same-sized panel"
	#
	# Each was armed by replacing the ScrollContainer with a plain box and re-running; none
	# fired. So the guard is the structure plus the reason, and the actual guard is
	# `tools/screenshot.sh`. A check that reports its healthy case while blind is the shape
	# this family stopped reading `tools/check.sh` over, and shipping one here would have
	# been worse than shipping none.
	var apply_button := plain.get_node_or_null("Panel/Column/Buttons/Apply") as Control
	_check(apply_button != null, "the panel has an Apply button")

	_check(
		plain.get_node_or_null("Panel/Column/Scroll") is ScrollContainer,
		"and the rows are in a scroll container",
		"a DotSettingsPanel is as tall as the document it was handed; without this the "
		+ "column grows past the panel and past the bottom of the window, taking Apply, "
		+ "Revert and Back with it"
	)
	_check(
		panel_parent_of(plain) is ScrollContainer,
		"with the panel inside it and the buttons outside, so they stay reachable"
	)

	plain.panel._edited("port", 4242)
	plain.apply()
	_check(
		direct.port == 4242,
		"Apply writes straight through when the source IS the config (%d)" % direct.port
	)
	stack.pop()

	# And the two-step, which is the reason this screen exists. `to_config()` hands out a
	# SNAPSHOT: a screen that called only `panel.apply()` would report success and change
	# nothing, for ever, and every check above would still pass.
	var source := FakeSettingsSource.new()
	var screen := DotSettingsScreen.new()
	screen.name = "SourceSettings"
	# Its own id, because the stack registers by id and `plain` already holds the default.
	# A second screen under one name is refused or silently replaces the first, and the
	# menu button then opens the wrong document -- which is what this test did first.
	screen.id_override = &"player_settings"
	_check(screen.build(source).ok, "a screen builds onto a source that is not a config")
	_check(
		stack.register(screen).ok,
		"and registers beside the other one rather than replacing it"
	)

	var announced: Array[PackedStringArray] = []
	screen.applied.connect(func(keys: PackedStringArray) -> void: announced.append(keys))

	stack.push(&"player_settings")
	await get_tree().process_frame

	screen.panel._edited("port", 9001)
	screen.apply()
	_check(source.absorbed == 1, "Apply hands the snapshot back to the source")
	_check(
		int(source.stored["port"]) == 9001,
		"and the source has the new value (%s)" % source.stored["port"]
	)
	_check(
		announced.size() == 1 and Array(announced[0]) == ["port"],
		"announcing which keys changed, rather than that something did"
	)

	# Opened twice. The snapshot is taken at bind time, so a screen that did not re-read
	# would show whatever was true when it was built -- and Apply would put it back.
	stack.pop()
	source.stored["port"] = 7

	stack.push(&"player_settings")
	await get_tree().process_frame
	_check(
		(screen.config as TestConfig).port == 7,
		"re-opening re-reads the source rather than showing a stale snapshot (%d)"
			% (screen.config as TestConfig).port
	)

	var orphan := DotSettingsScreen.new()
	_check(not orphan.build(null).ok, "a screen with nothing to edit is refused")
	orphan.free()

	# The pause menu beside it, for the same reason: four games wrote the same forty lines.
	var pause := DotPauseScreen.new()
	pause.name = "Pause"
	_check(
		pause.build(PackedStringArray(["Resume", "Rock the vote", "Leave"])).ok,
		"a pause menu builds from a list of labels"
	)
	_check(
		Array(pause.ids()) == [&"resume", &"rock_the_vote", &"leave"],
		"whose ids are DERIVED from the labels, so two lists cannot disagree (%s)"
			% [pause.ids()]
	)
	_check(stack.register(pause).ok, "and registers")
	stack.push(&"pause")
	await get_tree().process_frame
	await get_tree().process_frame

	# THAT THE PUSH LANDED, which nothing asserted and a rendered frame is what found.
	#
	# `DotScreen`'s default id is the NODE NAME, so a screen called `Pause` registered as
	# `&"Pause"` and `push(&"pause")` answered "no such screen" -- reported, not fatal, so
	# the menu simply never opened. Every check below this line passed anyway: a registered
	# screen is sized and focusable whether or not it is on screen. A test that asserts
	# only the things that are true either way is a test that passes for the wrong reason.
	_check(stack.top_id() == &"pause", "and OPENS, rather than registering under its node name")
	_check(pause.visible, "so the screen is actually visible")

	_check(pause.size.x > 0.0 and pause.size.y > 0.0, "and it has a size")
	_check(
		pause.get_node_or_null(pause.initial_focus) != null,
		"with a focus path that resolves to the first button"
	)

	var pressed: Array[StringName] = []
	pause.chosen.connect(func(id: StringName) -> void: pressed.append(id))
	pause.button(&"rock_the_vote").pressed.emit()
	_check(
		pressed == [&"rock_the_vote"],
		"pressing one announces which, rather than which index"
	)
	_check(pause.button(&"nothing_like_this") == null, "and a button nobody made is null")

	var empty := DotPauseScreen.new()
	_check(
		not empty.build(PackedStringArray()).ok,
		"a pause menu with no buttons is refused, because it could not be left"
	)
	empty.free()

	stack.clear()
	stack.queue_free()
	_done()


## The node a settings screen's panel is parented to.
##
## A helper rather than a path, so the check reads as "the panel is inside a scroll" rather
## than as a string that silently stops matching when the tree changes shape.
func panel_parent_of(screen: DotSettingsScreen) -> Node:
	return screen.panel.get_parent() if screen.panel != null else null


func _test_bindings() -> void:
	_section("bindings")

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

	# SORTED AS STRINGS, AND THE LABEL DROPS THE PREFIX.
	#
	# `Array.sort()` on a `StringName` compares interned POINTERS, so this method's own
	# "sorted" was whatever order the names happened to be created in -- and unstable
	# between builds, since it depends on which script interned each name first. It is the
	# same trap that gave two peers two different wire ids for one message type in dot-net.
	# A rendered frame of game-arena's rebinder is what showed it; nothing about the
	# CONTENTS of the array could.
	InputMap.add_action("probe_zulu")
	InputMap.add_action("probe_alpha")
	InputMap.add_action("probe_mike")

	var sorted_panel := DotBindingsPanel.new()
	sorted_panel.prefix = "probe_"
	add_child(sorted_panel)
	sorted_panel.build()

	var listed := PackedStringArray()
	for action in sorted_panel.rebindable_actions():
		listed.append(String(action))

	_check(
		Array(listed) == ["probe_alpha", "probe_mike", "probe_zulu"],
		"rebindable actions come out in alphabetical order (%s)" % [listed],
		"Array.sort() on a StringName compares interned pointers, not text"
	)

	# One HBox per action, named `Row_<action>`, with the label as its first child.
	var label_texts := PackedStringArray()

	for child in sorted_panel.get_children():
		var row := child as Control
		if row == null:
			continue
		var l := row.get_child(0) as Label if row.get_child_count() > 0 else null
		if l != null:
			label_texts.append(l.text)

	_check(
		Array(label_texts).has("Alpha") and not Array(label_texts).has("Probe Alpha"),
		"and the label drops the prefix, which is the part that is not information (%s)"
			% [label_texts]
	)

	# [b]A game's bindable actions are not all in one namespace.[/b] A first-person game's
	# movement is `dot_fps_*` and its chat key is its own `<game>_chat`; a panel filtered on
	# one prefix showed one of those and silently dropped the other, which is an action a
	# player cannot discover on any screen.
	InputMap.add_action("other_chat")

	var two_panel := DotBindingsPanel.new()
	two_panel.prefix = "probe_"
	two_panel.also_prefixed = PackedStringArray(["other_"])
	add_child(two_panel)
	two_panel.build()

	var both := PackedStringArray()
	for action in two_panel.rebindable_actions():
		both.append(String(action))

	_check(
		Array(both).has("other_chat") and Array(both).has("probe_alpha"),
		"a second prefix shows the actions the first one filtered out (%s)" % [both]
	)

	var two_labels := PackedStringArray()
	for child in two_panel.get_children():
		var row := child as Control
		if row == null or row.get_child_count() == 0:
			continue
		var l := row.get_child(0) as Label
		if l != null:
			two_labels.append(l.text)

	_check(
		Array(two_labels).has("Chat") and not Array(two_labels).has("Other Chat"),
		"and the prefix that MATCHED is the one stripped from the label (%s)" % [two_labels]
	)

	two_panel.queue_free()
	InputMap.erase_action("other_chat")

	sorted_panel.queue_free()
	for name_str in ["probe_zulu", "probe_alpha", "probe_mike"]:
		InputMap.erase_action(name_str)
	_done()


# --- The binding codec -----------------------------------------------------

func _test_input_binding() -> void:
	print("")
	_section("input binding text")

	var y := InputEventKey.new()
	y.physical_keycode = KEY_Y

	_check(DotInputBinding.to_text(y) == "Y", "a key is its own name")

	var back := DotInputBinding.from_text("Y") as InputEventKey
	_check(
		back != null and back.physical_keycode == KEY_Y,
		"and reads back as the same PHYSICAL key",
		"a keycode round-trip binds the wrong key on a non-QWERTY layout"
	)

	var shifted := InputEventKey.new()
	shifted.physical_keycode = KEY_A
	shifted.shift_pressed = true

	var shift_text := DotInputBinding.to_text(shifted)
	var shift_back := DotInputBinding.from_text(shift_text) as InputEventKey
	_check(
		shift_back != null and shift_back.physical_keycode == KEY_A and shift_back.shift_pressed,
		"a modifier survives the round trip (%s)" % shift_text
	)

	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_MIDDLE
	_check(DotInputBinding.to_text(mouse) == "Mouse 3", "a mouse button has a short form")
	_check(
		(DotInputBinding.from_text("Mouse 3") as InputEventMouseButton) != null,
		"and comes back as a mouse button"
	)

	# The wheel and the side buttons are written by name (API level 2). Godot numbers the
	# wheel 4 to 7, so "Mouse 4" was the wheel while a player reads it as the thumb button.
	var expected := {
		MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down",
		MOUSE_BUTTON_WHEEL_LEFT: "Wheel left", MOUSE_BUTTON_WHEEL_RIGHT: "Wheel right",
		MOUSE_BUTTON_XBUTTON1: "Mouse back", MOUSE_BUTTON_XBUTTON2: "Mouse forward",
	}
	var written: Array[String] = []
	var read_back: Array[String] = []
	for index in expected:
		var named := InputEventMouseButton.new()
		named.button_index = index as MouseButton
		var text := DotInputBinding.to_text(named)
		if text != str(expected[index]):
			written.append("%d -> %s" % [index, text])
		var again := DotInputBinding.from_text(str(expected[index])) as InputEventMouseButton
		if again == null or again.button_index != index:
			read_back.append(str(expected[index]))
	_check(written.is_empty(), "the wheel and the side buttons are written by name", ", ".join(written))
	_check(read_back.is_empty(), "and every name reads back as its own button", ", ".join(read_back))
	var lower := DotInputBinding.from_text("  wheel DOWN ") as InputEventMouseButton
	_check(
		lower != null and lower.button_index == MOUSE_BUTTON_WHEEL_DOWN,
		"a name typed by hand in any case still reads"
	)

	# The old spelling. Every binding stored before the names says "Mouse 4" for the wheel
	# up; reading it as anything else rebinds a player's previous-weapon key on upgrade.
	var old_up := DotInputBinding.from_text("Mouse 4") as InputEventMouseButton
	var old_down := DotInputBinding.from_text("Mouse 5") as InputEventMouseButton
	_check(
		old_up != null and old_up.button_index == MOUSE_BUTTON_WHEEL_UP
			and old_down != null and old_down.button_index == MOUSE_BUTTON_WHEEL_DOWN,
		"the old \"Mouse 4\" / \"Mouse 5\" still read as the wheel",
		"a stored binding from before the names would move to another button"
	)
	_check(
		DotInputBinding.to_text(old_up) == "Wheel up",
		"and an old binding is written back under its new name"
	)
	_check(
		(DotInputBinding.from_text("Mouse 8") as InputEventMouseButton).button_index == MOUSE_BUTTON_XBUTTON1,
		"a numbered side button still reads"
	)
	_check(
		DotBindingsPanel.event_name(old_up) == "Wheel up",
		"the rebinding screen draws the same word as the settings file"
	)

	_check(DotInputBinding.from_text("") == null, "nothing is bound to nothing")
	_check(DotInputBinding.from_text("Qwerty") == null, "and so is a word that is not a key")
	_check(not DotInputBinding.is_bound("Qwerty"), "is_bound agrees")

	# The replacement rule. `action_add_event` on an action that already has one leaves
	# BOTH bound, so a rebound key still works on its old one — invisible until a player
	# rebinds crouch onto their forward key and both still fire.
	DotInputBinding.apply(&"probe_chat", "Y")
	DotInputBinding.apply(&"probe_chat", "T")

	_check(
		InputMap.action_get_events(&"probe_chat").size() == 1,
		"applying a binding twice leaves one binding, not two",
		"a rebound action that still answers to its old key"
	)
	_check(
		DotInputBinding.describe_action(&"probe_chat") == "T",
		"and it is the new one"
	)

	# ensure_action is the boot path: it must never overwrite what a player chose.
	DotInputBinding.ensure_action(&"probe_chat", "Y")
	_check(
		DotInputBinding.describe_action(&"probe_chat") == "T",
		"ensure_action leaves an action that already has a binding alone"
	)

	DotInputBinding.apply(&"probe_chat", "")
	_check(
		InputMap.has_action(&"probe_chat")
			and InputMap.action_get_events(&"probe_chat").is_empty(),
		"an empty binding unbinds the action rather than deleting it"
	)
	DotInputBinding.ensure_action(&"probe_chat", "Y")
	_check(
		DotInputBinding.describe_action(&"probe_chat") == "Y",
		"and ensure_action then gives an unbound action its default back"
	)

	_check(
		DotInputBinding.describe_action(&"probe_missing") == "",
		"an action that does not exist describes as nothing rather than erroring"
	)

	InputMap.erase_action(&"probe_chat")
	_done()


# --- The chat window -------------------------------------------------------

func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _ballot_state(input: String, voters: Dictionary = {}) -> Dictionary:
	return {
		"open": true, "title": "Vote for the next map", "command": "votefor",
		"seconds": 20.0, "input": input,
		"options": [
			{"id": "a", "label": "Alpha", "votes": 1.0},
			{"id": "b", "label": "Bravo", "votes": 0.0},
			{"id": "c", "label": "Charlie\u202e", "votes": 0.0},
		],
		"voters": voters,
		"people": {"u1": {"name": "ana", "avatar": ""}},
	}


func _test_ballot_panel() -> void:
	print("")
	_section("ballot panel")

	var panel := DotBallotPanel.new()
	panel.local_voter = "u9"
	add_child(panel)

	var picked: Array = []
	panel.chosen.connect(func(i: int, id: String, cmd: String) -> void: picked.append([i, id, cmd]))

	_check(not panel.visible and not panel.is_open(), "a ballot panel starts hidden")

	panel.show_state(_ballot_state("both", {"u1": 0}))
	_check(panel.visible and panel.is_open() and panel.option_count() == 3, "a state opens it with its options")
	_check(panel.size.x > 100.0 and panel.size.y > 100.0, "and it has a size of its own (%s)" % str(panel.size))
	# By the string a game uses, not the constant: see COVER_GROUP.
	var covers := get_tree().get_nodes_in_group(&"dot_hud_cover").filter(
		func(n: Node) -> bool: return n is Control and (n as Control).is_visible_in_tree())
	_check(covers.has(panel), "an open panel is a visible member of the dot_hud_cover group, which is how a game makes room")
	_check(panel.seconds_left() > 19.0, "and counts the time it was told")
	_check(
		panel.row_rect(2).size.y > 0.0 and panel.row_rect(2).position.y > panel.row_rect(0).position.y,
		"its rows stack downwards"
	)
	_check(not str(panel._options[2]["label"]).contains("\u202e"), "a bidi override in a label is stripped")

	panel._input(_key(KEY_2))
	_check(
		picked.size() == 1 and picked[0] == [1, "b", "votefor"],
		"the 2 key chooses the second option, with the command to send", str(picked)
	)
	_check(panel.choice_of("u9") == 1, "and the local player's avatar moves at once, before the server answers")

	panel._input(_key(KEY_7))
	_check(picked.size() == 1, "a number past the last option chooses nothing")

	# The avatar travels.
	var target := panel.avatar_target("u1")
	panel._process(0.0)
	var start := panel.avatar_position("u1")
	for i in 30:
		panel._process(1.0 / 30.0)
	var after := panel.avatar_position("u1")
	_check(
		start.distance_to(target) > 1.0 and after.distance_to(target) < start.distance_to(target) * 0.1,
		"a vote's avatar slides from the heading onto its row", "%s -> %s, target %s" % [start, after, target]
	)
	_check(
		panel.row_rect(0).has_point(target),
		"and the row it lands on is the option voted for"
	)

	panel.show_state(_ballot_state("both", {"u1": 2}))
	_check(
		panel.row_rect(2).has_point(panel.avatar_target("u1")) and panel.row_rect(0).has_point(panel.avatar_position("u1")),
		"a changed vote moves the avatar from where it was, rather than teleporting it"
	)
	panel.snap_avatars()
	_check(panel.row_rect(2).has_point(panel.avatar_position("u1")), "and a late joiner sees every avatar already in place")

	panel.show_state(_ballot_state("both", {}))
	_check(panel.avatar_position("u1") == Vector2(-1, -1), "a voter the server no longer has leaves the board")

	# Pointer mode.
	var mouse_before := Input.mouse_mode
	panel._input(_key(panel.pointer_key))
	_check(panel.is_pointer_mode() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the pointer key frees the mouse")
	panel._input(_key(panel.pointer_key))
	_check(not panel.is_pointer_mode() and Input.mouse_mode == mouse_before, "and again puts it back the way it was found")

	# Numbers only, pointer only.
	panel.show_state(_ballot_state("numbers"))
	panel._input(_key(panel.pointer_key))
	_check(not panel.is_pointer_mode(), "under numbers the pointer key does nothing")

	panel.show_state(_ballot_state("pointer"))
	picked.clear()
	panel._input(_key(KEY_1))
	_check(picked.is_empty(), "under pointer the number keys are left to the game")
	panel._input(_key(panel.pointer_key))
	_check(panel.is_pointer_mode(), "and the pointer key frees the mouse")

	panel.take_numbers = false
	panel.show_state(_ballot_state("both"))
	panel._input(_key(KEY_1))
	_check(picked.is_empty(), "a panel told not to take the numbers does not, for the other ballot on screen")
	panel.take_numbers = true

	# Typing is not voting.
	var line := LineEdit.new()
	add_child(line)
	line.grab_focus()
	panel._input(_key(KEY_1))
	_check(picked.is_empty(), "a 1 typed into a text field is not a vote")
	line.queue_free()
	line.release_focus()

	# Closed.
	var gone := [false]
	panel.dismissed.connect(func() -> void: gone[0] = true)
	panel.result_hold_sec = 0.5
	panel.show_state({"open": false, "winner": "Bravo"})
	_check(
		panel.visible and not panel.is_open() and not panel.is_pointer_mode() and Input.mouse_mode == mouse_before,
		"closing shows the result, and gives the mouse back"
	)
	_check("Bravo won" in "\n".join(panel.describe_lines()), "and says what won")
	panel._result_until_ms = Time.get_ticks_msec() - 1
	panel._process(0.0)
	_check(not panel.visible and gone[0], "then goes away on its own")

	panel.show_state(_ballot_state("both"))
	panel.show_state({"open": false})
	_check(not panel.visible, "a close with no result takes it down at once")

	panel.queue_free()
	_done()


func _game_ballot(voters: Dictionary, ids: Array = ["wipeout", "zombie", "g2g", "deathrun", "arena", "__keep__"]) -> Dictionary:
	var labels := {
		"wipeout": "Wipeout", "zombie": "Zombie Zone", "g2g": "g2gfast", "deathrun": "Deathrun",
		"arena": "Arena", "__keep__": "Don't change", "smash": "Smash Copter",
	}
	var options := []
	for id: String in ids:
		options.append({"id": id, "label": labels.get(id, id), "votes": 0.0})
	return {
		"open": true, "title": "Vote for the next game", "command": "game_vote",
		"seconds": 24.0, "input": "both", "options": options, "voters": voters,
	}


## Steps [param panel]'s avatars [param frames] frames at 60 fps.
func _frames(panel: DotBallotPanel, frames: int) -> void:
	for i in frames:
		panel._process(1.0 / 60.0)


## The row [param voter]'s avatar is drawn on now, or -1.
func _row_drawn(panel: DotBallotPanel, voter: String) -> int:
	var at := panel.avatar_position(voter)
	for i in panel.option_count():
		if panel.row_rect(i).has_point(at):
			return i
	return -1


## The local voter's avatar against the row marked as theirs: ballot-panel-avatar-stale-row-1.
##
## A rendered game-vote frame showed the voter's avatar on row 5 while row 6, "Don't change",
## was the marked choice and the result was up. Two ways to get there, both reproduced here:
## a ballot decided by the click itself (the server closes it at once, so the result is
## drawn while the avatar is still sliding down from the heading), and a server state sent
## before the click arriving after it (the stale vote replaced the click, and with the
## ballot closing on that click no later state ever corrected it).
func _test_ballot_avatar_rows() -> void:
	print("")
	_section("ballot panel: the avatar sits on the row marked as the voter's")

	var panel := DotBallotPanel.new()
	panel.local_voter = "u9"
	panel.result_hold_sec = 30.0
	add_child(panel)

	# 1. One player, one click, and the server closes the ballot on it.
	panel.show_state(_game_ballot({}))
	panel.snap_avatars()
	panel.choose(5)
	_frames(panel, 1)
	panel.show_state({"open": false, "winner": "Don't change"})
	_frames(panel, 2)
	_check(
		panel.choice_of("u9") == 5 and _row_drawn(panel, "u9") == 5,
		"a ballot closed by the voter's own click shows their avatar on that row at once (row %d, drawn on %d)"
			% [panel.choice_of("u9") + 1, _row_drawn(panel, "u9") + 1],
		"the result was drawn while the avatar was still sliding from the heading"
	)
	panel.dismiss()

	# 2. A state the server sent before the click arrives after it.
	panel.show_state(_game_ballot({"u9": 4}))
	panel.snap_avatars()
	panel.choose(5)
	panel.show_state(_game_ballot({"u9": 4}))
	_check(
		panel.choice_of("u9") == 5,
		"a server state older than the click does not take the click back (row %d)" % (panel.choice_of("u9") + 1),
		"the stale vote replaced the click; a ballot that then closed on it showed the old row"
	)
	panel.show_state({"open": false, "winner": "Don't change"})
	_frames(panel, 2)
	_check(
		panel.choice_of("u9") == 5 and _row_drawn(panel, "u9") == 5,
		"and the result closed on that click shows the avatar on the clicked row (drawn on %d)" % (_row_drawn(panel, "u9") + 1)
	)
	panel.dismiss()

	# 3. The server's word wins once a round trip has had time to happen.
	panel.show_state(_game_ballot({"u9": 4}))
	panel.choose(5)
	panel._pending_until_ms = Time.get_ticks_msec() - 1
	panel.show_state(_game_ballot({"u9": 4}))
	_check(panel.choice_of("u9") == 4, "a server that still says otherwise after the round trip is believed (row %d)" % (panel.choice_of("u9") + 1))
	panel.show_state(_game_ballot({"u9": 5}))
	panel.choose(5)
	panel.show_state(_game_ballot({"u9": 5}))
	panel.show_state(_game_ballot({"u9": 2}))
	_check(panel.choice_of("u9") == 2, "and once the server has confirmed the click, its next word is the vote (row %d)" % (panel.choice_of("u9") + 1))
	panel.dismiss()

	# 4. A new ballot over an old one: nothing carries over.
	panel.show_state(_game_ballot({}))
	panel.choose(5)
	panel.show_state(_game_ballot({}, ["smash", "arena", "__keep__"]))
	_frames(panel, 30)
	_check(
		panel.choice_of("u9") == -1 and panel.avatar_position("u9") == Vector2(-1, -1),
		"a new ballot does not inherit the last one's click (row %d)" % (panel.choice_of("u9") + 1)
	)
	panel.dismiss()

	# 5. The same options in another order: the vote follows the option, not the number.
	panel.show_state(_game_ballot({}))
	panel.choose(4)
	panel.show_state(_game_ballot({"u9": 0}, ["arena", "wipeout", "zombie", "g2g", "deathrun", "__keep__"]))
	_frames(panel, 60)
	_check(
		str(panel._options[panel.choice_of("u9")]["id"]) == "arena" and _row_drawn(panel, "u9") == panel.choice_of("u9"),
		"reordered options keep the voter on the option they chose, avatar and mark together (row %d, drawn on %d)"
			% [panel.choice_of("u9") + 1, _row_drawn(panel, "u9") + 1]
	)

	# 6. Votes changing under everybody: every avatar settles on its own voter's row.
	panel.show_state(_game_ballot({"u1": 0, "u2": 5, "u9": 0}, ["arena", "wipeout", "zombie", "g2g", "deathrun", "__keep__"]))
	_frames(panel, 10)
	panel.show_state(_game_ballot({"u1": 3, "u2": 1, "u9": 5}, ["arena", "wipeout", "zombie", "g2g", "deathrun", "__keep__"]))
	_frames(panel, 90)
	_check(
		_row_drawn(panel, "u1") == 3 and _row_drawn(panel, "u2") == 1 and _row_drawn(panel, "u9") == 5,
		"changed votes settle every avatar on its voter's new row (%d, %d, %d)"
			% [_row_drawn(panel, "u1") + 1, _row_drawn(panel, "u2") + 1, _row_drawn(panel, "u9") + 1]
	)

	panel.queue_free()
	_done()


class FakeSelfMute extends RefCounted:
	var ran: Array[String] = []
	var muted: Dictionary = {}
	func claims_chat(text: String) -> bool:
		var t := text.strip_edges().to_lower()
		return (t.begins_with("!") or t.begins_with("/")) and (t.substr(1) == "sm" or t.substr(1).begins_with("sm "))
	func handle_chat(text: String) -> PackedStringArray:
		ran.append(text)
		return PackedStringArray(["ran"])
	func is_muted(name: String, _sender: String = "") -> bool:
		return muted.has(name)


func _test_chat_window() -> void:
	print("")
	_section("chat window")

	var window := DotChatWindow.new()
	window.open_action = &"probe_chat_open"
	window.team_action = &"probe_chat_team"
	window.cycle_action = &""
	window.channels = [
		{"id": &"all", "label": "Say", "colour": Color.WHITE},
		{"id": &"team", "label": "Team", "colour": Color.GREEN, "team": true},
	]
	add_child(window)

	_check(
		DotInputBinding.describe_action(&"probe_chat_open") == "Y",
		"the box registers its open key at Y when the project has no action for it"
	)
	_check(
		DotInputBinding.describe_action(&"probe_chat_team") == "U",
		"and team chat at U"
	)
	_check(window.channel() == &"all", "it starts on the first channel")
	_check(not window.is_open(), "and closed")
	_check(
		window.entry() != null and not window.entry().visible,
		"with nothing to type in until it is opened"
	)
	_check(
		window.entry().max_length == window.max_length,
		"the line carries the length limit the server will also enforce"
	)

	var opened_on: Array[StringName] = []
	# A one-element array, not an int: a lambda captures a primitive BY VALUE, so
	# `closes += 1` inside one increments a copy and the counter outside stays zero.
	var closes := [0]
	var said: Array[Dictionary] = []
	window.opened.connect(func(c: StringName) -> void: opened_on.append(c))
	window.closed.connect(func() -> void: closes[0] += 1)
	window.submitted.connect(
		func(text: String, c: StringName) -> void: said.append({"text": text, "channel": c})
	)

	window.open()
	_check(window.is_open() and opened_on == [&"all"], "opening says which channel it opened on")
	_check(window.entry().visible, "and shows the line")

	# The hold rule: a line must not fade while somebody is reading it.
	window.add_said("someone", "hello")
	_check(window.line_count() == 1, "a line lands in the log")
	_check(
		window.feed().expire(Time.get_ticks_msec() + 600_000) == 0,
		"nothing expires while the box is open",
		"a message that fades while you read it is one you have to ask for again"
	)

	window.entry().text = "  hello there  "
	window.entry().text_submitted.emit(window.entry().text)

	_check(said.size() == 1 and said[0]["text"] == "hello there", "a submitted line is trimmed")
	_check(
		said.size() == 1 and said[0]["channel"] == &"all",
		"and carries the channel it was typed on"
	)
	_check(not window.is_open() and closes[0] == 1, "and the box closes behind it")
	_check(
		window.feed().expire(Time.get_ticks_msec() + 600_000) == 1,
		"once closed, the log expires again"
	)

	# An empty line is how a player abandons one, and it must not reach the server.
	window.open()
	window.entry().text = "   "
	window.entry().text_submitted.emit(window.entry().text)
	_check(said.size() == 1, "an empty line sends nothing")
	_check(not window.is_open(), "and still closes the box")


	# Escape, on the entry's own gui_input, which is the path a focused LineEdit takes.
	window.open()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	window.entry().gui_input.emit(escape)
	_check(not window.is_open(), "escape closes the box")

	# Recall. Up walks back through what was sent, down walks forward again.
	window.open()
	var up := InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	window.entry().gui_input.emit(up)
	_check(window.entry().text == "hello there", "up recalls the last line sent")

	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	window.entry().gui_input.emit(down)
	_check(window.entry().text == "", "and down comes back to an empty line")
	window.close()

	# `!sm` / `/sm`, the player's own block list: run here and never emitted, so it cannot
	# reach the server and nobody is told. A stand-in for dot-chat's DotChatSelfMute, which
	# dot-ui does not link.
	var mutes := FakeSelfMute.new()
	window.self_mute = mutes
	for typed in ["!sm ada", "/SM"]:
		window.open()
		window.entry().text = typed
		window.entry().text_submitted.emit(window.entry().text)
	_check(said.size() == 1 and mutes.ran == ["!sm ada", "/SM"],
		"!sm and /sm run on this client and are never emitted (%s)" % str(mutes.ran))
	window.open()
	window.entry().text = "!smile"
	window.entry().text_submitted.emit(window.entry().text)
	_check(said.size() == 2 and said[-1]["text"] == "!smile", "a longer word is still sent")
	said.pop_back()
	var before := window.line_count()
	mutes.muted["Ada"] = true
	window.add_said("Ada", "you do not see this")
	_check(window.line_count() == before, "a line from a muted player is not drawn")
	mutes.muted.erase("Ada")
	window.add_said("Ada", "you see this")
	_check(window.line_count() > before, "and is again once they are unmuted")
	window.self_mute = null
	window.self_mute_enabled = false

	# Channels.
	var changed: Array[StringName] = []
	window.channel_changed.connect(func(c: StringName) -> void: changed.append(c))
	window.cycle_channel()
	_check(window.channel() == &"team" and changed == [&"team"], "cycling moves to the next channel")
	window.cycle_channel()
	_check(window.channel() == &"all", "and wraps")

	window.open(&"nonsense")
	_check(
		window.channel() == &"all",
		"opening on a channel the box does not have keeps the one it was on",
		"a game with no teams must not end up sending to a channel nobody receives"
	)
	window.close()

	opened_on.clear()
	window.open(&"team")
	_check(window.channel() == &"team", "and opening on one it does have moves there")
	window.close()

	# `enabled` is the switch for a deployment whose players chat somewhere else.
	window.enabled = false
	window.open()
	_check(not window.is_open(), "a disabled box does not open")
	window.add_said("someone", "but you can still hear this")
	_check(
		window.line_count() > 0,
		"and still shows what was said",
		"off means you cannot type, not that you are out of the conversation"
	)

	window.enabled = true
	window.open()
	_check(window.is_open(), "and it opens again when it is turned back on")
	window.enabled = false
	_check(not window.is_open(), "turning it off while it is open closes it")

	# --- The two things only a picture found -------------------------------

	# [b]A line put in before the engine readied the node.[/b] A host that builds the box
	# and immediately announces something — or builds it in `SceneTree._initialize`, where
	# nothing is inside the tree at all — was writing into a log that did not exist yet,
	# and the line vanished with nothing said.
	var early := DotChatWindow.new()
	early.register_actions = false
	early.add_text("connecting to the server")
	_check(
		early.line_count() == 1,
		"a line added before the box is readied is kept, not dropped",
		"the log is built on demand, not in _ready"
	)
	add_child(early)
	_check(early.line_count() == 1, "and survives being added to the tree")

	# [b]Wrapping.[/b] DotFeedView draws an entry as one run of text and does not clip it,
	# which is right for a kill feed and wrong for chat: the server's own limit is 127
	# characters and the box is 460 pixels wide, so an ordinary sentence ran out of the box
	# and across the middle of the screen.
	early.clear()
	early.add_said("someone", "short")
	var short_rows := early.line_count()
	_check(short_rows == 1, "a line that fits is one row")

	early.clear()
	early.add_said(
		"someone",
		"a sentence long enough that it cannot possibly fit inside four hundred and sixty"
			+ " pixels of a chat box, which is the ordinary case rather than the extreme one"
	)
	_check(
		early.line_count() > 1,
		"and one that does not is wrapped across several (%d)" % early.line_count(),
		"unwrapped, chat runs out of the box and across the screen"
	)

	# The wrap must not cost any of what was said.
	var joined := ""
	for row in early.feed().lines():
		for part in (row["parts"] as Array):
			joined += str((part as Dictionary).get("text", ""))
	_check(
		joined.contains("the ordinary case rather than the extreme one"),
		"wrapping keeps every word, rather than truncating the end"
	)

	# Rows are bounded by what the box is tall enough to draw, or the overflow is drawn
	# straight through the field somebody is typing in.
	early.clear()
	early.max_lines = 3
	early.feed().max_lines = 3
	for i in range(8):
		early.add_text("line %d" % i)
	_check(early.line_count() == 3, "the log keeps only as many rows as it can draw")

	early.queue_free()

	# --- History ---------------------------------------------------------------

	# [b]What faded is still there to read.[/b] A closed log is a glance and lets go of a
	# line after ten seconds; a player who opens the box to find what somebody said a
	# minute ago was finding nothing.
	var past := DotChatWindow.new()
	past.register_actions = false
	past.history_limit = 30
	past.history_lines = 4
	past.history_page = 2
	add_child(past)

	for i in range(10):
		past.add_text("old %d" % i)
	past.feed().expire(Time.get_ticks_msec() + 600_000)
	_check(past.line_count() == 0, "the closed log lets its lines fade")
	_check(past.history().size() == 10, "and the history keeps every one of them")

	past.open()
	var view := past.get_node("History") as DotFeedView
	_check(
		view.visible and view.line_count() == 4,
		"opening shows the newest rows of the history, as many as it is tall (%d)" % view.line_count()
	)
	_check(
		str(((view.lines()[3]["parts"] as Array)[0] as Dictionary)["text"]) == "old 9",
		"with the newest against the line being typed"
	)

	var page_up := InputEventKey.new()
	page_up.keycode = KEY_PAGEUP
	page_up.pressed = true
	past.entry().gui_input.emit(page_up)
	_check(past.history_scroll() == 2, "Page Up goes back a page")
	_check(
		str(((view.lines()[0]["parts"] as Array)[0] as Dictionary)["text"]) == "old 4",
		"and the view shows the older rows"
	)
	_check(
		str(((view.lines()[3]["parts"] as Array)[0] as Dictionary)["text"]).contains("2 newer"),
		"with a row saying how much is below it"
	)

	past.add_text("new one")
	_check(
		past.history_scroll() == 3,
		"a line arriving while somebody reads back does not move what they are reading"
	)

	_check(past.scroll_history(1000) == 7, "scrolling stops at the oldest row")
	_check(past.scroll_history(-1000) == 0, "and at the newest")

	past.close()
	past.open()
	_check(past.history_scroll() == 0, "the box reopens on the newest line")
	past.close()
	_check(not view.visible, "and closed, the fading log is what shows")

	for i in range(40):
		past.add_text("flood %d" % i)
	_check(past.history().size() == 30, "the history is bounded")

	past.clear()
	_check(past.history().is_empty(), "and clear() empties it too")
	_check(past.outline_size > 0, "the log is outlined by default")
	past.queue_free()

	var state := window.describe()
	_check(
		str(state.get("open_binding", "")) == "Y",
		"describe() reports the key, which is what a bug report needs"
	)

	window.queue_free()
	InputMap.erase_action(&"probe_chat_open")
	InputMap.erase_action(&"probe_chat_team")
	_done()
