extends "widget_checks.gd"

## The ballot panel and chat window sections of ui_selftest.gd, split out to keep that file under the size gate.


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


func _click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(2, 2)
	click.global_position = click.position
	return click


## Every modal that frees the mouse must keep it free on a click outside it and when another screen closes.
func _test_pointer_recapture() -> void:
	_section("pointer recapture")
	var saved := Input.mouse_mode

	var probe := ClickProbe.new()
	add_child(probe)
	var panel := DotBallotPanel.new()
	panel.local_voter = "u9"
	add_child(panel)
	panel.show_state(_ballot_state("both"))
	_check(panel.is_in_group(&"dot_pointer_modal"), "the ballot is in the pointer-modal group a host reads")
	panel._input(_key(panel.pointer_key))
	_check(panel.is_pointer_mode(), "the ballot frees the mouse")
	var outside := _click()
	outside.position = panel.get_global_rect().end + Vector2(8, 8)
	outside.global_position = outside.position
	get_viewport().push_input(outside)
	await get_tree().process_frame
	_check(probe.seen == 0, "a click outside the ballot's rows is consumed, so a host's click-to-capture never sees it")

	var stack := DotScreenStack.new()
	stack.register_service = false
	stack.config = DotUiConfig.new()
	stack.config.allow_pause = false
	add_child(stack)
	var pause := DotPauseScreen.new()
	pause.name = "Pause"
	var _b := pause.build(PackedStringArray(["Resume"]))
	var board := DotScoreboardScreen.new()
	var visible_screen := _make_screen(&"modal")
	visible_screen.mouse_mode = DotScreen.Mouse.VISIBLE
	for each in [pause, board, visible_screen]:
		var _r := stack.register(each)
	for id in [&"pause", &"scoreboard", &"modal"]:
		var _p := stack.push(id)
		var _q := stack.pop(id)
		_check(stack.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE,
			"%s closing leaves the mouse free while the ballot holds it" % id)

	# Ballot back to the captured game; a screen's own mouse wish applies again.
	panel._input(_key(panel.pointer_key))
	_check(stack.wanted_mouse_mode() == Input.MOUSE_MODE_CAPTURED, "the ballot back to the game, the idle stack captures again")
	for id in [&"pause", &"modal"]:
		var _p := stack.push(id)
		get_viewport().push_input(_click())
		await get_tree().process_frame
		_check(stack.wanted_mouse_mode() == Input.MOUSE_MODE_VISIBLE, "%s: with the ballot back to the game, the open screen still wants the mouse free" % id)
		var _q := stack.pop(id)

	Input.mouse_mode = saved
	stack.queue_free()
	panel.queue_free()
	probe.queue_free()
	_done()


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

	# A line added before the node is readied must be kept: the log is built on demand.
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

	# Wrapping: DotFeedView does not clip an entry, so a 127-character line ran out of the 460 px box.
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

	var bold_before := DotHudPiece.bold_font()
	DotHudPiece.clear_cache()
	_check(DotHudPiece._fonts.is_empty(), "clear_cache() empties the shared fonts")
	_check(DotHudPiece.bold_font() != null and DotHudPiece._fonts.size() == 1 and bold_before != null, "and a font refills it")

	window.queue_free()
	InputMap.erase_action(&"probe_chat_open")
	InputMap.erase_action(&"probe_chat_team")
	_done()

