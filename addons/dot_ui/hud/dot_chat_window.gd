@tool
class_name DotChatWindow
extends Control

## A chat box: a log that fades, a line to type in, and a key that opens it.
##
## [b]Why this is in dot-ui and not in dot-chat.[/b] dot-chat is the decision layer — who
## hears a line, what it may contain, what name is drawn beside it — and it ships no art
## on purpose. But every game in this family then wrote the same chat box, or, more often,
## wrote no chat box at all and shipped a game whose players could receive a line and
## never send one. Four clients here could be talked to and could not talk back.
##
## So this is the window, and it knows nothing about chat: it takes coloured fragments to
## draw and it emits the string somebody typed. A game hands [signal submitted] to
## whatever its send path already is — [code]DotClientChat.send[/code],
## [code]DotChatClient.compose[/code], a bridge's `say` — and feeds arriving lines back in
## through [method add_message]. dot-ui still depends on dot-core and nothing else.
##
## [codeblock]
## var chat := DotChatWindow.new()
## chat.submitted.connect(func(text: String, _channel: StringName) -> void:
##     link.chat.send(text))
## chat.opened.connect(func(_c: StringName) -> void: controller.suspended = true)
## chat.closed.connect(func() -> void: controller.suspended = false)
## add_child(chat)
## [/codeblock]
##
## [b]It does not touch the mouse mode, and it does not stop the player moving.[/b] Both
## are the game's, and both differ per game — a first-person client captures the mouse, a
## top-down one does not. A focused [LineEdit] keeps typed keys out of
## [method Node._unhandled_input], but it cannot do a thing about [method Input.is_action_pressed],
## which is polled straight off the device and does not care what consumed the event. Every
## game here polls its movement. [b]So connect [signal opened] and [signal closed] to
## whatever suspends your controller[/b] — without that, typing "sw" walks you backwards.
##
## [b]The open key is an action, not a key.[/b] [member open_action] names an [InputMap]
## action so the binding is the player's, rebindable through [DotBindingsPanel] or stored
## in a settings document as text through [DotInputBinding]. A hardcoded [constant KEY_Y]
## is a key somebody cannot move, on a keyboard whose Y is somewhere else.

const CHANNEL := "ui.chat"

## Somebody pressed enter on a non-empty line. [param text] is raw and unsanitised.
##
## [b]Unsanitised on purpose.[/b] The server decides what a line may contain and its answer
## is the only one that counts; a window that filtered first would be a second filter that
## drifts from the real one, and it would teach players their text was accepted when the
## thing that accepts it has not seen it yet.
signal submitted(text: String, channel: StringName)

## The box opened on a channel. A game suspends its controller here.
signal opened(channel: StringName)

## The box closed, whether the line was sent or abandoned.
signal closed()

## The player moved to another channel while the box was open.
signal channel_changed(channel: StringName)

@export_group("Input")

## The action that opens the box. Created at the default binding if the project has none.
@export var open_action: StringName = &"chat_open"

## The action that opens it on [member team_channel]. Empty for a game with no teams.
@export var team_action: StringName = &"chat_open_team"

## The action that moves to the next channel while the box is open. Empty to disable.
@export var cycle_action: StringName = &"chat_cycle"

## Bindings used only when the project does not already declare the action.
##
## [b]Y, because that is where this genre has put it for twenty-five years[/b] and muscle
## memory from the genre is worth more than a tidier layout. U is team chat for the same
## reason. A game that disagrees sets these; a player who disagrees rebinds them, and a
## rebinding is what the project's own input map or a settings document then carries.
@export var default_open_binding: String = "Y"
@export var default_team_binding: String = "U"
@export var default_cycle_binding: String = ""

## Whether to create missing actions at the default bindings at all.
##
## [b]Off for a shipped game whose input map is the project's.[/b] On, this is what makes
## a chat box work in a game that has not been told about chat yet, which is every game
## in this family the day before it is wired up.
@export var register_actions: bool = true

@export_group("Behaviour")

## Whether the box can be opened at all.
##
## [b]The lines still arrive and are still drawn.[/b] A deployment that turns the box off
## because its players chat somewhere else — a web client embedded in a page that has its
## own chat, a relayed room — still wants the player to see what was said. Off means "you
## cannot type here", not "you are not in this conversation".
@export var enabled: bool = true:
	set(value):
		enabled = value
		if not value and _open:
			close()

## Longest line the box will accept, in characters.
##
## The server has the real limit and refuses past it; this one is so a player finds out
## while typing rather than after sending.
@export_range(1, 1024, 1) var max_length: int = 127

## Rows drawn in the log, which is also what decides its height.
@export_range(1, 60, 1) var max_lines: int = 8

## Seconds a line stays on screen once the box is closed. Zero keeps them for ever.
@export_range(0.0, 120.0, 0.5) var lifetime_sec: float = 10.0

## How many sent lines the up arrow walks back through. Zero disables recall.
@export_range(0, 50, 1) var recall_limit: int = 12

@export_group("Layout")

## Anchor to the bottom left of the parent on ready.
##
## Off for a game that places the box itself, which is every game with a designed HUD.
## On is what makes this one line of setup.
##
## [b]Bottom left is also where health and armour usually go[/b], and a stat bar drawn
## through a line of chat is what the first picture of the two together showed. A game
## with anything in that corner places one of them.
@export var place_bottom_left: bool = true

## Inset from the left edge of the parent.
@export var margin_left: float = 16.0

## Inset from the bottom edge.
##
## [b]Separate from [member margin_left], because the thing in the way is never in both
## directions.[/b] A game with health and armour in the bottom-left corner needs the box
## lifted ABOVE them and still flush with the same left edge as everything else on the
## HUD; one margin for both would push it inwards to clear something below it.
@export var margin_bottom: float = 16.0
@export var width: float = 460.0
@export var entry_height: float = 26.0

## One drawn row.
##
## [b]Rows, not messages.[/b] A message too long for the box is wrapped across as many
## rows as it takes, so [member max_lines] bounds what is DRAWN — which is the number that
## has to agree with the height, because a log allowed more rows than it is tall draws the
## overflow straight through the entry field underneath it.
@export_range(8.0, 40.0, 1.0) var line_height: float = 18.0
@export_range(0.0, 20.0, 1.0) var line_gap: float = 2.0

## Channels the box can send on, in cycle order.
##
## `[{"id": StringName, "label": String, "colour": Color}]`. Dictionaries rather than
## [code]DotChatChannel[/code] for the reason [DotFeedView] takes them: dot-ui does not
## import dot-chat and does not know what a channel is. A game maps its own.
var channels: Array[Dictionary] = []

var _feed: DotFeedView = null
var _entry: LineEdit = null
var _prompt: Label = null
var _open: bool = false
var _channel: StringName = &""
var _sent: PackedStringArray = PackedStringArray()
var _recall: int = -1


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	if register_actions:
		_register_actions()

	if place_bottom_left:
		_place()

	_ensure_built()
	_apply_open_state()


## Builds the log and the entry, if they are not built yet.
##
## [b]Lazy rather than in [method Node._ready], and the difference is a line of chat.[/b]
## A host that creates this box and puts a line in it before the engine has readied it —
## a game announcing "connecting to %s", a fixture, anything built in
## [method SceneTree._initialize], where NOTHING is inside the tree yet — was writing into
## a log that did not exist, and the line vanished with nothing said. The screenshot that
## found this drew an empty box beside a kill feed with three lines in it.
##
## So every public method that needs the pieces asks for them first. Building children is
## safe outside the tree; only [method _place], which reads the parent, is not.
func _ensure_built() -> void:
	if _feed != null:
		return

	if channels.is_empty():
		channels = [{"id": &"all", "label": "Say", "colour": Color(0.88, 0.90, 0.94)}]

	if _channel == &"":
		_channel = StringName(str(channels[0].get("id", &"all")))

	_build()
	_apply_open_state()


func _register_actions() -> void:
	if open_action != &"":
		DotInputBinding.ensure_action(open_action, default_open_binding)
	if team_action != &"" and default_team_binding != "":
		DotInputBinding.ensure_action(team_action, default_team_binding)
	if cycle_action != &"" and default_cycle_binding != "":
		DotInputBinding.ensure_action(cycle_action, default_cycle_binding)


func _place() -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = margin_left
	offset_right = margin_left + width
	offset_top = -(_log_height() + entry_height + margin_bottom)
	offset_bottom = -margin_bottom


## How tall the log is: one row per line it is allowed to draw.
##
## Derived rather than exported beside [member max_lines]. Two numbers for one thing is
## two numbers that can disagree, and the way they disagree here is a log that draws
## through the field somebody is typing in.
func _log_height() -> float:
	return float(max_lines) * (line_height + line_gap)


## Keeps the newest row against the entry field as the log fills up.
func _relayout_log() -> void:
	if _feed == null:
		return

	var rows := clampi(_feed.line_count(), 1, max_lines)
	_feed.offset_top = -(float(rows) * (line_height + line_gap) + entry_height)


## Anchors and then offsets, in that order, because the anchor setter rewrites offsets.
func _anchor(
	control: Control,
	a_left: float, a_top: float, a_right: float, a_bottom: float,
	o_left: float, o_top: float, o_right: float, o_bottom: float
) -> void:
	control.anchor_left = a_left
	control.anchor_top = a_top
	control.anchor_right = a_right
	control.anchor_bottom = a_bottom
	control.offset_left = o_left
	control.offset_top = o_top
	control.offset_right = o_right
	control.offset_bottom = o_bottom


func _build() -> void:
	_feed = DotFeedView.new()
	_feed.name = "Log"
	_feed.max_lines = max_lines
	_feed.lifetime_sec = lifetime_sec
	_feed.newest_last = true
	_feed.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.line_height = line_height
	_feed.line_gap = line_gap
	# The log above the entry, both anchored to the BOTTOM of the box, and the log
	# re-sized as lines arrive so the newest one always sits just above the entry and
	# older ones climb away from it. Anchored to the top instead — which is what a feed
	# does — a half-full log leaves a gap over the entry field and a full one draws
	# through it.
	#
	# [b]Every offset is set, and all four of them AFTER the anchors.[/b] Assigning
	# `anchor_right` RECOMPUTES the offsets to preserve the control's current rectangle,
	# and a control built in code has no rectangle yet — so `anchor_right = 1.0` on a
	# fresh Control sets `offset_right` to minus the parent's width and the thing stays
	# nought pixels wide. It then draws nothing while every property about it reads
	# correctly, which is what the first picture of this box showed: an entry field, and
	# a log that was not there. This family has now paid for that trap seven times.
	_anchor(_feed, 0.0, 1.0, 1.0, 1.0, 0.0, -(_log_height() + entry_height), 0.0, -entry_height)
	add_child(_feed)
	_feed.line_added.connect(func(_line: Dictionary) -> void: _relayout_log())
	_feed.line_expired.connect(func(_line: Dictionary) -> void: _relayout_log())

	var row := HBoxContainer.new()
	row.name = "Entry"
	_anchor(row, 0.0, 1.0, 1.0, 1.0, 0.0, -entry_height, 0.0, 0.0)
	add_child(row)

	_prompt = Label.new()
	_prompt.name = "Prompt"
	row.add_child(_prompt)

	_entry = LineEdit.new()
	_entry.name = "Line"
	_entry.max_length = max_length
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.caret_blink = true
	_entry.text_submitted.connect(_on_submitted)
	_entry.gui_input.connect(_on_entry_gui_input)
	row.add_child(_entry)


# --- Opening and closing ---------------------------------------------------

## Opens the box on a channel, or on the current one.
func open(id: StringName = &"") -> void:
	_ensure_built()

	if not enabled or _open:
		return

	if id != &"" and _index_of(id) >= 0:
		_channel = id

	_open = true
	_recall = -1
	_entry.text = ""
	_apply_open_state()

	# [b]Focus is grabbed a frame late, and that is not tidiness.[/b] The key that opened
	# the box is still being processed: focus it now and the same press can be delivered to
	# the LineEdit, which types the open key into the line. Every chat box that opens with
	# a "y" already in it has this bug.
	_entry.call_deferred("grab_focus")

	opened.emit(_channel)


## Closes the box. Anything typed is discarded.
func close() -> void:
	if not _open:
		return

	_open = false
	_entry.text = ""
	_entry.release_focus()
	_apply_open_state()
	closed.emit()


func toggle(id: StringName = &"") -> void:
	if _open:
		close()
	else:
		open(id)


func is_open() -> bool:
	return _open


## The channel the box would send on.
func channel() -> StringName:
	return _channel


## Moves to a channel by id. Ignored if the box does not have it.
func set_channel(id: StringName) -> void:
	if _index_of(id) < 0 or id == _channel:
		return

	_channel = id
	_apply_open_state()
	channel_changed.emit(_channel)


## Moves to the next channel in [member channels].
func cycle_channel() -> void:
	if channels.size() < 2:
		return

	var next := (_index_of(_channel) + 1) % channels.size()
	set_channel(StringName(str(channels[next].get("id", &"all"))))


func _apply_open_state() -> void:
	# The log holds its lines while the box is open: a message that fades out while you are
	# reading it is a message you have to ask somebody to repeat.
	if _feed != null:
		_feed.hold = _open

	if _prompt != null:
		_prompt.text = "%s: " % _label_of(_channel)
		_prompt.add_theme_color_override("font_color", _colour_of(_channel))

	if _entry != null:
		_entry.visible = _open
		_entry.editable = _open

	if _prompt != null:
		_prompt.visible = _open


func _index_of(id: StringName) -> int:
	for i in range(channels.size()):
		if StringName(str(channels[i].get("id", &""))) == id:
			return i
	return -1


func _label_of(id: StringName) -> String:
	var index := _index_of(id)
	return "Say" if index < 0 else str(channels[index].get("label", "Say"))


func _colour_of(id: StringName) -> Color:
	var index := _index_of(id)

	if index < 0:
		return Color(0.88, 0.90, 0.94)

	var colour: Variant = channels[index].get("colour", Color(0.88, 0.90, 0.94))
	return colour if colour is Color else Color(0.88, 0.90, 0.94)


# --- Input -----------------------------------------------------------------

## Opening. Runs only when nothing else wanted the key.
func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if _open:
		# A fallback, for a box that is open with the focus somewhere else — a player who
		# clicked the world behind it. Escape must always close this.
		if event.is_action_pressed(&"ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		return

	if not enabled:
		return

	if _pressed(event, open_action):
		get_viewport().set_input_as_handled()
		open(_first_channel())
		return

	if _pressed(event, team_action):
		get_viewport().set_input_as_handled()
		open(_team_channel())


## True only for an action that exists. [method InputEvent.is_action_pressed] on an action
## the project does not have is an error per event, not a false — and a game that leaves
## [member register_actions] off has exactly that until it declares its own.
func _pressed(event: InputEvent, action: StringName) -> bool:
	if action == &"" or not InputMap.has_action(action):
		return false

	return event.is_action_pressed(action)


## Everything typed while the box is open, taken before the line edit sees it.
##
## [b]On the entry's own [signal Control.gui_input], not in [method Node._input].[/b]
## Godot delivers an event to [method Node._input] first, then to the focused control,
## then to shortcut and unhandled input. Consuming keys in `_input` to keep them away from
## the game therefore consumes them before the [LineEdit] — a chat box nobody can type in,
## which is what the first draft of this was. Here the box is already the focus owner, so
## what it does not accept is what the line edit gets.
func _on_entry_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return

	var key := event as InputEventKey

	match key.keycode:
		KEY_ESCAPE:
			close()
			_entry.accept_event()
			return
		KEY_UP:
			_recall_step(1)
			_entry.accept_event()
			return
		KEY_DOWN:
			_recall_step(-1)
			_entry.accept_event()
			return
		KEY_TAB:
			# Tab is focus navigation everywhere else in a user interface, and focus
			# navigation out of a chat box is a box that stops taking letters with no
			# visible reason. It cycles the channel here, or it does nothing.
			if cycle_action == &"" or not InputMap.has_action(cycle_action):
				cycle_channel()
			_entry.accept_event()
			return

	if _pressed(event, cycle_action):
		cycle_channel()
		_entry.accept_event()


func _on_submitted(text: String) -> void:
	var trimmed := text.strip_edges()

	if trimmed != "":
		_remember(trimmed)
		submitted.emit(trimmed, _channel)

	close()


func _remember(text: String) -> void:
	if recall_limit <= 0:
		return

	# Deduplicated at the head only: somebody saying "gg" twice in a row wants one entry,
	# and somebody who said it an hour ago wants their history in the order it happened.
	if _sent.size() > 0 and _sent[_sent.size() - 1] == text:
		return

	_sent.append(text)

	while _sent.size() > recall_limit:
		_sent.remove_at(0)


func _recall_step(direction: int) -> void:
	if _sent.is_empty():
		return

	_recall = clampi(_recall + direction, -1, _sent.size() - 1)

	if _recall < 0:
		_entry.text = ""
	else:
		_entry.text = _sent[_sent.size() - 1 - _recall]

	_entry.caret_column = _entry.text.length()


func _first_channel() -> StringName:
	if channels.is_empty():
		return &"all"

	return StringName(str(channels[0].get("id", &"all")))


## The channel marked `"team": true`, or the current one for a game with no teams.
func _team_channel() -> StringName:
	for entry in channels:
		if bool(entry.get("team", false)):
			return StringName(str(entry.get("id", &"all")))

	return _channel


# --- Lines -----------------------------------------------------------------

## Adds a line built from coloured fragments, as [DotFeedView] takes them.
##
## Wrapped to the width of the box first. See [method _wrap].
func add_message(parts: Array) -> void:
	_ensure_built()

	if _feed == null:
		return

	for row in _wrap(parts):
		_feed.add_line(row)


## Splits one line into as many as it takes to fit the box, at word boundaries.
##
## [b]Chat is the one feed that has to wrap.[/b] [DotFeedView] draws an entry as a single
## run of text and does not clip it — which is right for a kill feed, where an entry is
## two names and a weapon, and wrong for chat, where the server's own limit is 127
## characters and the box is 460 pixels wide. Unwrapped, a normal sentence runs out of the
## box and across the middle of the screen. A picture is the only thing that shows this;
## every assertion about the log passes either way.
##
## [b]It wraps rather than truncating.[/b] The alternative loses the end of what somebody
## said, which is worse than an extra row: chat is the one place where the text IS the
## content, and a player cannot ask the log to repeat itself.
##
## Falls back to the line as given when there is no font to measure with — outside the
## tree, or before a theme resolves — because an unwrapped line is legible and a line
## wrapped by a guess is not.
func _wrap(parts: Array) -> Array:
	var font := get_theme_default_font()
	var limit := _feed.size.x if _feed != null and _feed.size.x > 0.0 else width

	if font == null or limit <= 0.0:
		return [parts]

	var font_size := get_theme_default_font_size()

	# Words rather than fragments, each keeping the colour of the fragment it came from,
	# so a wrap inside what somebody said does not take the speaker's colour with it.
	var words: Array[Dictionary] = []

	for part in parts:
		var fragment: Dictionary = part
		var colour: Variant = fragment.get("colour", Color.WHITE)
		var text := str(fragment.get("text", ""))

		for word in text.split(" ", false):
			words.append({"text": word, "colour": colour})

	if words.is_empty():
		return [parts]

	var rows: Array = []
	var row: Array = []
	var row_width := 0.0

	for entry in words:
		var word := str(entry["text"])
		var piece := word if row.is_empty() else " " + word
		var piece_width := font.get_string_size(
			piece, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		).x

		# A word wider than the whole box goes on a line of its own and overflows it.
		# Breaking inside a word would turn one long URL into something nobody can copy.
		if not row.is_empty() and row_width + piece_width > limit:
			rows.append(row)
			row = []
			row_width = 0.0
			piece = word
			piece_width = font.get_string_size(
				piece, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
			).x

		# Merged into the previous fragment when the colour matches, so a row of one
		# person's words is one draw call rather than one per word.
		if not row.is_empty() and (row[row.size() - 1] as Dictionary)["colour"] == entry["colour"]:
			var last: Dictionary = row[row.size() - 1]
			last["text"] = str(last["text"]) + piece
		else:
			row.append({"text": piece, "colour": entry["colour"]})

		row_width += piece_width

	if not row.is_empty():
		rows.append(row)

	return rows


## Adds a one-colour line. What a system message is.
func add_text(text: String, colour: Color = Color(0.88, 0.90, 0.94)) -> void:
	add_message([{"text": text, "colour": colour}])


## Adds a line as a chat message usually arrives: a name, then what they said.
func add_said(
	speaker: String,
	text: String,
	speaker_colour: Color = Color(0.62, 0.78, 1.0),
	text_colour: Color = Color(0.88, 0.90, 0.94)
) -> void:
	_ensure_built()
	if _feed == null:
		return

	if speaker == "":
		add_text(text, text_colour)
		return

	add_message([
		{"text": "%s:" % speaker, "colour": speaker_colour},
		{"text": text, "colour": text_colour},
	])


func clear() -> void:
	_ensure_built()
	if _feed != null:
		_feed.clear()


## The log, for a game that wants to tune it further.
func feed() -> DotFeedView:
	_ensure_built()
	return _feed


## The line being typed in, for a game that wants to theme it.
func entry() -> LineEdit:
	_ensure_built()
	return _entry


func line_count() -> int:
	_ensure_built()
	return 0 if _feed == null else _feed.line_count()


func describe() -> Dictionary:
	return {
		"enabled": enabled,
		"open": _open,
		"channel": String(_channel),
		"channels": channels.size(),
		"lines": line_count(),
		"open_binding": DotInputBinding.describe_action(open_action),
		"team_binding": DotInputBinding.describe_action(team_action),
		"recalled": _sent.size(),
	}


func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var state := describe()

	for key in state:
		out.append("%s: %s" % [key, str(state[key])])

	return out
