class_name DotBallotPanel
extends Control

## A ballot on the HUD: numbered options a player picks with a number key or a click, a
## countdown, and every voter's avatar sitting beside what they chose.
##
## [codeblock]
## var panel := DotBallotPanel.new()
## hud.add_child(panel)
## panel.chosen.connect(func(index: int, _id: String, command: String) -> void:
##     chat.send("!%s %d" % [command, index + 1]))
## panel.show_state(state)      # a dot-vote DotVoteBallotView dictionary, as it arrives
## [/codeblock]
##
## [b]A dictionary in, a signal out, and nothing else[/b], because this addon must not name
## dot-vote's classes or a netcode's: the state is whatever [code]DotVoteBallotView[/code]
## built on the server and whatever carried it here, and what a choice turns into — a typed
## command, an RPC — is the host's. Every field is read defensively, so a server newer or
## older than this panel draws a plainer ballot rather than an error.
##
## [b]Three ways to choose, and the server picks[/b] ([code]"input"[/code]):
##
## - [code]numbers[/code] — 1 to 9, and 0 for a tenth, as a numbered vote menu has always
##   worked. The keys are consumed while the ballot is open, so a game listening for them
##   by event does not also switch weapon. A game that POLLS [Input] still sees them: the
##   engine updates action state before any node hears the event, and no Control can take
##   that back. [member take_numbers] lets a host give the keys to one of two ballots.
## - [code]pointer[/code] — [member pointer_key] frees the mouse, the player clicks an
##   option, and the mouse goes back to how it was. The number keys stay the game's.
## - [code]both[/code] — the default.
##
## [b]Avatars move.[/b] Each voter is drawn on the row they chose and slides to another when
## they change their mind — the thing a community map vote on a moddable sandbox did that a
## numbered menu never could. A picture comes from [member avatar_fn]; without one, or until
## it has loaded, a voter is a disc in a colour of their own with their initial on it. The
## local player's choice moves the moment they make it rather than after the round trip.
##
## Draws itself in [method _draw] rather than out of child Controls: the avatars move freely
## across rows, and a layout container would fight every one of them.

## The player chose [param index] — 0-based, so [code]index + 1[/code] is what they would
## type — and [param command] is the state's own, for a host sending it on as text.
signal chosen(index: int, option_id: String, command: String)

## [member pointer_key] freed or recaptured the mouse.
signal pointer_mode_changed(on: bool)

## The ballot went away: it closed and its result has been shown, or the server took it down.
signal dismissed()

const CHANNEL := "ui.ballot"

## Rows drawn at most. A ballot is at most a handful; the number keys reach ten.
const MAX_ROWS := 10

## The key that frees the mouse for clicking, under [code]pointer[/code] or [code]both[/code].
##
## F3 by default: not a movement key, not a weapon slot, and not the chat or console key
## every game in this family already binds.
@export var pointer_key: Key = KEY_F3

## Whether the number keys vote on this panel. A host with two ballots on screen — the next
## game and the next map — gives them to the one opened last.
@export var take_numbers: bool = true

## Seconds the result stays up after the ballot closes.
@export_range(0.0, 15.0, 0.5) var result_hold_sec: float = 4.0

## Width of the panel, in pixels before [member ui_theme]'s scale.
@export_range(200.0, 800.0, 10.0) var panel_width: float = 360.0

## Diameter of one avatar.
@export_range(12.0, 64.0, 1.0) var avatar_size: float = 22.0

## How fast an avatar travels to its row. Higher is quicker; it eases in either way.
@export_range(1.0, 40.0, 1.0) var avatar_speed: float = 10.0

@export var ui_theme: DotUiTheme = null

## The voter id this client votes as — [code]u<userid>[/code] for dot-server — so its own
## choice is marked and moves at once. Empty marks nothing.
var local_voter: String = ""

## [code]func(voter: String, url: String) -> Texture2D[/code], or null while it is not loaded.
## Asked again each frame until it answers, so a loader that fetches in the background just
## returns null until it has the picture.
var avatar_fn: Callable = Callable()

## What [method show_state] last adopted, as sent.
var state: Dictionary = {}

var _open := false
var _options: Array[Dictionary] = []
var _voters: Dictionary = {}
var _people: Dictionary = {}
var _input_mode := "both"
var _title := "Vote"
var _command := ""
var _winner := ""
var _deadline_ms := 0
var _result_until_ms := 0

var _pointer := false
var _mouse_before: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _hover := -1
var _row_rects: Array[Rect2] = []

## voter -> Vector2, where its avatar is drawn now.
var _positions: Dictionary = {}

## voter -> Texture2D, once [member avatar_fn] has answered.
var _textures: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(true)


## Adopts a ballot state. See the class notes for the shape; every field is optional.
func show_state(p_state: Dictionary) -> void:
	state = p_state.duplicate(true)

	var open := bool(state.get("open", false))

	if not open:
		_open = false
		_winner = _clean(state.get("winner", ""), 48)

		if _winner != "" and result_hold_sec > 0.0:
			_result_until_ms = Time.get_ticks_msec() + int(result_hold_sec * 1000.0)
			_set_pointer(false)
			visible = true
			queue_redraw()
		else:
			dismiss()
		return

	_open = true
	_winner = ""
	_result_until_ms = 0
	_title = _clean(state.get("title", "Vote"), 64)
	_command = _clean(state.get("command", ""), 32)
	_input_mode = str(state.get("input", "both"))

	if not _input_mode in ["numbers", "pointer", "both"]:
		_input_mode = "both"

	var seconds: Variant = state.get("seconds", 0.0)
	_deadline_ms = Time.get_ticks_msec() + int(maxf(float(seconds) if (seconds is float or seconds is int) else 0.0, 0.0) * 1000.0)

	_options.clear()
	var raw: Variant = state.get("options", [])

	if raw is Array:
		for entry: Variant in raw:
			if _options.size() >= MAX_ROWS:
				break
			if entry is Dictionary:
				var votes: Variant = (entry as Dictionary).get("votes", 0.0)
				_options.append({
					"id": str((entry as Dictionary).get("id", "")),
					"label": _clean((entry as Dictionary).get("label", ""), 48),
					"votes": float(votes) if (votes is float or votes is int) else 0.0,
				})

	_voters.clear()
	var who: Variant = state.get("voters", {})

	if who is Dictionary:
		for voter: Variant in who:
			var index: Variant = (who as Dictionary)[voter]
			if (index is int or index is float) and int(index) >= 0 and int(index) < _options.size():
				_voters[str(voter)] = int(index)

	_people = state.get("people", {}) if state.get("people", {}) is Dictionary else {}

	# Somebody who left, or whose vote the server no longer has, leaves the board.
	for voter: Variant in _positions.keys():
		if not _voters.has(voter):
			_positions.erase(voter)

	if not allows_pointer():
		_set_pointer(false)

	visible = true
	_layout()
	queue_redraw()


## Takes the ballot off the screen now.
func dismiss() -> void:
	var was := visible
	_open = false
	_winner = ""
	_result_until_ms = 0
	_set_pointer(false)
	_positions.clear()
	visible = false

	if was:
		dismissed.emit()


func is_open() -> bool:
	return _open


func option_count() -> int:
	return _options.size()


func allows_numbers() -> bool:
	return _input_mode != "pointer"


func allows_pointer() -> bool:
	return _input_mode != "numbers"


func is_pointer_mode() -> bool:
	return _pointer


## Seconds left on the ballot, as this client counts them.
func seconds_left() -> float:
	return maxf(float(_deadline_ms - Time.get_ticks_msec()) / 1000.0, 0.0) if _open else 0.0


## The option index [param voter] is drawn on, or -1.
func choice_of(voter: String) -> int:
	return int(_voters.get(voter, -1))


## Where [param voter]'s avatar is drawn now, in this Control's coordinates. For a test.
func avatar_position(voter: String) -> Vector2:
	return _positions.get(voter, Vector2(-1, -1))


## Where [param voter]'s avatar is heading. For a test.
func avatar_target(voter: String) -> Vector2:
	return _target_of(voter)


## Puts every avatar on its row at once, with no travel. For a player who arrives in the
## middle of a ballot, to whom every vote already cast is not news.
func snap_avatars() -> void:
	for voter: Variant in _voters:
		_positions[voter] = _target_of(str(voter))
	queue_redraw()


## Chooses [param index] as if the player had pressed its number. Returns whether it could.
func choose(index: int) -> bool:
	if not _open or index < 0 or index >= _options.size():
		return false

	if local_voter != "":
		_voters[local_voter] = index

	chosen.emit(index, str(_options[index]["id"]), _command)
	queue_redraw()
	return true


## The rect of option [param index]'s row, for a host or a test that wants to click it.
func row_rect(index: int) -> Rect2:
	return _row_rects[index] if index >= 0 and index < _row_rects.size() else Rect2()


# --- Input --------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not _open or not visible:
		return

	# Somebody typing — in the chat box, the console — is typing, and "gg 1" is not a vote.
	# Keys reach _input before the focused control, which is DotChatWindow's own finding.
	var focus := get_viewport().gui_get_focus_owner()

	if event is InputEventKey and (focus is LineEdit or focus is TextEdit):
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode

		if key == pointer_key and allows_pointer():
			_set_pointer(not _pointer)
			get_viewport().set_input_as_handled()
			return

		if take_numbers and allows_numbers():
			var index := _number_of(key)

			if index >= 0 and index < _options.size():
				choose(index)
				get_viewport().set_input_as_handled()
				return

	if not _pointer:
		return

	if event is InputEventMouseMotion:
		var hovered := _row_at(get_local_mouse_position())

		if hovered != _hover:
			_hover = hovered
			queue_redraw()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var at := _row_at(get_local_mouse_position())

		if at >= 0:
			choose(at)
			get_viewport().set_input_as_handled()


static func _number_of(key: Key) -> int:
	if key >= KEY_1 and key <= KEY_9:
		return key - KEY_1
	if key == KEY_0:
		return 9
	if key >= KEY_KP_1 and key <= KEY_KP_9:
		return key - KEY_KP_1
	if key == KEY_KP_0:
		return 9
	return -1


func _row_at(point: Vector2) -> int:
	for i in _row_rects.size():
		if _row_rects[i].has_point(point):
			return i
	return -1


func _set_pointer(on: bool) -> void:
	if on == _pointer:
		return

	_pointer = on

	# The mouse is put back the way it was found, not to "captured": a game in a menu, or a
	# 2D game that never captures, must not have the mouse taken from it by a ballot closing.
	if on:
		_mouse_before = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		Input.mouse_mode = _mouse_before
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover = -1

	pointer_mode_changed.emit(on)
	queue_redraw()


# --- Layout and motion ------------------------------------------------------

func _theme() -> DotUiTheme:
	if ui_theme == null:
		ui_theme = DotUiTheme.dark()
	return ui_theme


func _row_height() -> float:
	return maxf(avatar_size + 12.0, float(_theme().font_size) + 18.0)


func _header_height() -> float:
	return float(_theme().heading_size) + float(_theme().font_size) + 26.0


func _layout() -> void:
	var pad := _theme().padding
	var y := _header_height()
	var h := _row_height()

	_row_rects.clear()

	for i in _options.size():
		_row_rects.append(Rect2(pad, y, panel_width - pad * 2.0, h - 4.0))
		y += h

	custom_minimum_size = Vector2(panel_width, y + pad)
	size = custom_minimum_size


## The slot [param voter] sits in on its row: avatars line up from the right edge and squeeze
## together when a row has more of them than room.
func _target_of(voter: String) -> Vector2:
	var index := int(_voters.get(voter, -1))

	if index < 0 or index >= _row_rects.size():
		return Vector2(-1, -1)

	var on_row: Array = []

	for v: Variant in _voters:
		if int(_voters[v]) == index:
			on_row.append(str(v))

	on_row.sort()
	var slot := on_row.find(voter)
	var rect := _row_rects[index]
	var room := rect.size.x * 0.45
	var step := minf(avatar_size + 3.0, room / maxf(float(on_row.size()), 1.0))
	var right := rect.end.x - 34.0 - avatar_size * 0.5

	return Vector2(right - step * slot, rect.position.y + rect.size.y * 0.5)


func _process(delta: float) -> void:
	if not visible:
		return

	if not _open and _result_until_ms > 0 and Time.get_ticks_msec() >= _result_until_ms:
		dismiss()
		return

	var moved := false

	for voter: Variant in _voters:
		var target := _target_of(str(voter))

		if not _positions.has(voter):
			# Arrives from the heading, where the title is: a new vote drops in.
			_positions[voter] = Vector2(target.x, _header_height() * 0.5)

		var at: Vector2 = _positions[voter]

		if at.distance_to(target) > 0.25:
			_positions[voter] = at.lerp(target, 1.0 - exp(-avatar_speed * delta))
			moved = true

		if not _textures.has(voter) and avatar_fn.is_valid():
			var person: Dictionary = _people.get(voter, {}) if _people.get(voter, {}) is Dictionary else {}
			var url := str(person.get("avatar", ""))

			if url != "":
				var tex: Variant = avatar_fn.call(str(voter), url)

				if tex is Texture2D:
					_textures[voter] = tex
					moved = true

	if moved or _open:
		queue_redraw()


# --- Drawing ----------------------------------------------------------------

func _draw() -> void:
	var t := _theme()
	var font := t.font if t.font != null else get_theme_default_font()
	var fs := t.font_size
	var pad := t.padding
	var box := StyleBoxFlat.new()
	box.bg_color = t.background
	box.border_color = t.outline
	box.set_border_width_all(int(t.border))
	box.set_corner_radius_all(int(t.corner))
	draw_style_box(box, Rect2(Vector2.ZERO, size))

	var heading_y := pad + float(t.heading_size)
	var left := int(ceil(seconds_left()))
	var clock := "%d:%02d" % [left / 60, left % 60] if _open else ""
	var clock_w := font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, t.heading_size).x if _open else 0.0
	var title_w := panel_width - pad * 2.0 - (clock_w + 12.0 if _open else 0.0)
	var title_size := _heading_size_for(font, _title, title_w, t.heading_size, fs)
	draw_string(font, Vector2(pad, heading_y), _fit(font, _title, title_w, title_size), HORIZONTAL_ALIGNMENT_LEFT, -1, title_size, t.text)

	if _open:
		draw_string(font, Vector2(pad, heading_y), clock, HORIZONTAL_ALIGNMENT_RIGHT, panel_width - pad * 2.0, t.heading_size, t.danger if left <= 5 else t.accent)
		draw_string(font, Vector2(pad, heading_y + fs + 8.0), _hint(), HORIZONTAL_ALIGNMENT_LEFT, panel_width - pad * 2.0, fs - 2, t.text_dim)
	elif _winner != "":
		draw_string(font, Vector2(pad, heading_y + fs + 8.0), "%s won" % _winner, HORIZONTAL_ALIGNMENT_LEFT, panel_width - pad * 2.0, fs, t.good)

	var mine := int(_voters.get(local_voter, -1)) if local_voter != "" else -1

	for i in _row_rects.size():
		var rect := _row_rects[i]
		var row := StyleBoxFlat.new()
		row.bg_color = t.surface_hover if i == _hover else t.surface
		row.set_corner_radius_all(int(t.corner))

		if i == mine:
			row.border_color = t.accent
			row.set_border_width_all(2)

		if not _open and _winner != "" and str(_options[i]["label"]) == _winner:
			row.border_color = t.good
			row.set_border_width_all(2)

		draw_style_box(row, rect)

		var baseline := rect.position.y + rect.size.y * 0.5 + fs * 0.35
		var number := ("%d" % ((i + 1) % 10)) if allows_numbers() else "•"
		draw_string(font, Vector2(rect.position.x + 8.0, baseline), number, HORIZONTAL_ALIGNMENT_LEFT, 20.0, fs, t.accent)
		# The label gets everything left of the avatars, and is shortened with an ellipsis
		# rather than cut: "Foundry (low gravit" reads as a typo, "Foundry (low…" does not.
		var label_width := _strip_left(i) - rect.position.x - 38.0
		draw_string(font, Vector2(rect.position.x + 30.0, baseline), _fit(font, str(_options[i]["label"]), label_width, fs), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, t.text)
		draw_string(font, Vector2(rect.position.x, baseline), _format_votes(float(_options[i]["votes"])), HORIZONTAL_ALIGNMENT_RIGHT, rect.size.x - 8.0, fs, t.text_dim)

	# Avatars last, over every row, because they travel between them.
	for voter: Variant in _positions:
		_draw_avatar(str(voter), _positions[voter], font)


## Where row [param index]'s avatars begin, from the left: the label stops short of it.
func _strip_left(index: int) -> float:
	var rect := _row_rects[index]
	var count := 0

	for v: Variant in _voters:
		if int(_voters[v]) == index:
			count += 1

	var room := rect.size.x * 0.45
	var step := minf(avatar_size + 3.0, room / maxf(float(count), 1.0))
	var right := rect.end.x - 34.0 - avatar_size * 0.5

	return right - step * maxf(float(count) - 1.0, 0.0) - avatar_size * 0.5 if count > 0 else rect.end.x - 34.0


## The heading's size: its own if the title fits, smaller down to [param floor_px] if not.
##
## The title used to be clipped at a fixed width with no ellipsis, and the server's own
## titles did not fit beside the clock: "Vote for the next ma". A title is a sentence, so
## it shrinks a little before it loses a word; [method _fit] cuts what still does not fit.
static func _heading_size_for(font: Font, text: String, width: float, size_px: int, floor_px: int) -> int:
	var px := size_px

	while px > floor_px and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > width:
		px -= 1

	return px


static func _fit(font: Font, text: String, width: float, size_px: int) -> String:
	if width <= 0.0:
		return ""

	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x <= width:
		return text

	var cut := text

	while cut.length() > 1 and font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x > width:
		cut = cut.left(cut.length() - 1)

	return cut.strip_edges() + "…"


func _draw_avatar(voter: String, at: Vector2, font: Font) -> void:
	var t := _theme()
	var r := avatar_size * 0.5
	var tex: Texture2D = _textures.get(voter, null)

	if tex != null:
		# A disc, not the square the picture is: a textured polygon, because a Control
		# cannot clip one draw call to a circle.
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()

		for k in 24:
			var a := TAU * k / 24.0
			var unit := Vector2(cos(a), sin(a))
			points.append(at + unit * r)
			uvs.append(Vector2(0.5, 0.5) + unit * 0.5)

		draw_colored_polygon(points, Color.WHITE, uvs, tex)
	else:
		draw_circle(at, r, _colour_of(voter))
		var initial := _name_of(voter).left(1).to_upper()
		var size_px := int(avatar_size * 0.55)
		draw_string(font, at + Vector2(-r, size_px * 0.36), initial, HORIZONTAL_ALIGNMENT_CENTER, avatar_size, size_px, Color.WHITE)

	draw_arc(at, r, 0.0, TAU, 24, t.accent if voter == local_voter else t.background, 2.0)


func _hint() -> String:
	var keys := "1-%d" % mini(_options.size(), 10) if _options.size() > 1 else "1"
	var pointer := OS.get_keycode_string(pointer_key)

	match _input_mode:
		"numbers":
			return "Press %s to vote" % keys
		"pointer":
			return "Click to vote" if _pointer else "Press %s, then click to vote" % pointer
		_:
			return ("Press %s, or click" % keys) if _pointer else ("Press %s · %s to use the mouse" % [keys, pointer])


func _name_of(voter: String) -> String:
	var person: Variant = _people.get(voter, {})

	if person is Dictionary:
		var n := _clean((person as Dictionary).get("name", ""), 32)
		if n != "":
			return n

	return voter.trim_prefix("u")


## A colour per voter, the same on every client: hue from the id, never from the order.
static func _colour_of(voter: String) -> Color:
	# Golden-ratio spread: neighbouring ids ("u3", "u4") hash to neighbouring numbers, and a
	# plain modulo gave a ballot of nine people in two colours.
	return Color.from_hsv(fposmod(float(voter.hash()) * 0.6180339887, 1.0), 0.55, 0.80)


static func _format_votes(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


## Plain text out of a server's tree: no control characters, no bidi overrides and no
## zero-width characters, which spoof a line on a HUD exactly as they do in chat.
static func _clean(value: Variant, max_length: int) -> String:
	if not (value is String or value is StringName):
		return ""

	var out := PackedStringArray()

	for ch in String(value):
		var code := ch.unicode_at(0)

		if code < 32 or code == 127:
			continue
		if (code >= 0x200B and code <= 0x200F) or (code >= 0x202A and code <= 0x202E) or (code >= 0x2066 and code <= 0x2069) or code == 0xFEFF:
			continue

		out.append(ch)

	return "".join(out).strip_edges().left(max_length)


func describe() -> Dictionary:
	return {
		"open": _open,
		"title": _title,
		"options": _options.size(),
		"voters": _voters.size(),
		"input": _input_mode,
		"pointer": _pointer,
		"seconds_left": snappedf(seconds_left(), 0.1),
		"winner": _winner,
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	out.append("ballot     %s, %d options, %d voters" % [
		("open, %ds left" % int(seconds_left())) if _open else ("closed, %s won" % _winner if _winner != "" else "closed"),
		_options.size(), _voters.size(),
	])
	out.append("input      %s%s" % [_input_mode, ", mouse free" if _pointer else ""])
	return out
