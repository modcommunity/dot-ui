class_name DotPauseScreen
extends DotScreen

## A pause menu: a title, a column of buttons, and a signal saying which was pressed.
##
## [codeblock]
## var pause := DotPauseScreen.new()
## pause.build(["Resume", "Settings", "Servers", "Leave"])
## pause.chosen.connect(func(id: StringName) -> void: ...)   # &"resume", &"settings", …
## stack.register(pause)
## [/codeblock]
##
## [b]It exists for the same reason [DotSettingsScreen] does.[/b] Four games in this family
## wrote the same forty lines — a centred [PanelContainer], a heading, a [VBoxContainer] of
## [Button]s, and a focus path — and differed only in which words were on the buttons. Two
## copies of one thing is this tree's most expensive mistake; four is that mistake with a
## number on it.
##
## The buttons are DATA rather than subclass points, because that is what actually varies:
## a lobby has no controls screen and a deathmatch has no server browser button, and both
## are a string in a list.

## A button was pressed. The id is its label, lower-cased, spaces to underscores.
signal chosen(id: StringName)

## Heading text.
var title_text: String = "Paused"

## Half-width and half-height of the panel, in pixels.
var half_size: Vector2 = Vector2(150.0, 120.0)

## The id the stack registers this under.
##
## [b]Declared, because [DotScreen]'s default is the NODE NAME and that is a trap.[/b] A
## screen called `Pause` registers as `&"Pause"`, a host pushes `&"pause"`, and
## [method DotScreenStack.push] answers "no such screen" — which it reports and nothing
## treats as fatal, so the menu simply never opens. Every structural check still passes,
## because a registered screen is sized and focusable whether or not it was ever pushed:
## this addon's own suite, and two games', asserted a size and a focus path on a screen
## that was not on screen at all, and a rendered frame is what said so.
##
## Not `screen_id`: [DotScreen] has a method of that name and a property cannot shadow one.
var id_override: StringName = &"pause"

var _ids: Array[StringName] = []


func _screen_id() -> StringName:
	return id_override


## The id a label becomes: `"Rock the vote"` -> `&"rock_the_vote"`.
##
## Derived rather than paired, because a list of labels and a parallel list of ids is two
## lists that can disagree — and this tree has paid for that shape more than any other.
static func id_for(label: String) -> StringName:
	return StringName(label.strip_edges().to_lower().replace(" ", "_"))


## Builds the menu. [param labels] is what is on the buttons, top to bottom.
func build(labels: PackedStringArray) -> DotResult:
	if labels.is_empty():
		return DotResult.fail(
			DotError.CODE_INVALID, "A pause menu with no buttons cannot be left."
		)

	hides_below = true
	blocks_input = true
	mouse_mode = DotScreen.Mouse.VISIBLE

	var panel := PanelContainer.new()
	panel.name = "Panel"
	# set_anchors_AND_OFFSETS_preset: `set_anchors_preset` does NOT set offsets, so a
	# Control built in code keeps the zero size it was created with and every child lays
	# out inside nothing -- invisibly, while being by every property correctly configured.
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -half_size.x
	panel.offset_right = half_size.x
	panel.offset_top = -half_size.y
	panel.offset_bottom = half_size.y
	add_child(panel)

	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Title"
	heading.text = title_text
	heading.theme_type_variation = &"DotHeading"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	_ids.clear()

	for label in labels:
		var id := DotPauseScreen.id_for(label)
		_ids.append(id)

		var button := Button.new()
		button.name = String(id)
		button.text = label
		button.pressed.connect(func() -> void: chosen.emit(id))
		column.add_child(button)

	# The first button, by NAME rather than by `get_path()`: this runs before the screen is
	# registered with a stack, so the node is not in the tree and `get_path()` pushes an
	# error and returns nothing. A menu that opens with nothing focused cannot be used with
	# a gamepad at all, and is invisible to anybody testing with a mouse -- which is how
	# this family shipped it once already.
	initial_focus = NodePath("Panel/Column/%s" % _ids[0])
	return DotResult.success(self)


## The ids this menu will emit, in order. For a check, or for a game building a keymap.
func ids() -> Array[StringName]:
	return _ids.duplicate()


## The button with [param id], or null. For greying one out.
func button(id: StringName) -> Button:
	return get_node_or_null("Panel/Column/%s" % id) as Button
