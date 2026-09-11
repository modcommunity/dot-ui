class_name DotSettingsScreen
extends DotScreen

## A settings screen, generated from a document, with the way back wired up.
##
## [codeblock]
## var screen := DotSettingsScreen.new()
## screen.name = "Settings"
## screen.build(presentation.settings)     # a DotSettingsManager, or any DotConfig
## stack.register(screen)
## [/codeblock]
##
## [b]It exists because the alternative was four copies of it.[/b] Every game in this
## family reached the same shape independently — a `PanelContainer`, a title, a
## [DotSettingsPanel], and Apply / Revert / Back — and two copies of one thing is this
## tree's most expensive mistake. What is a game's own is which document it hands over and
## where the screen sits in its stack; the rest is the same everywhere and is here.
##
## [b]The source is an [Object] and is never named.[/b] dot-ui depends on dot-core and
## nothing else, and a script that so much as MENTIONS [code]DotSettingsManager[/code]
## fails to compile in a project without dot-settings — which is most of them. The contract
## is two methods, [code]to_config()[/code] and [code]absorb_config()[/code], and that this
## screen also accepts a bare [DotConfig] is the proof the seam is real. Same shape as
## dot-chat's backbone client.
##
## [b]The two-step apply is the whole point.[/b] [code]to_config()[/code] hands out a
## SNAPSHOT — writing to it does not write to the manager — so a screen that called only
## [method DotSettingsPanel.apply] would report success and change nothing, and would go on
## reporting success for ever. Until this screen, the round trip had no caller anywhere in
## this family: the second half was written, tested, documented and consumed by nobody.

## Applied, with the keys that actually changed.
signal applied(changed: PackedStringArray)

## Apply was pressed and the panel refused the edits.
signal refused(result: DotResult)

const CHANNEL := "ui.settings"

## The generated panel. Read it to drive a check; do not rebuild it.
var panel: DotSettingsPanel = null

## What the panel is bound to. A snapshot when [member source] is a manager.
var config: DotConfig = null

## The document this edits. Either a [DotConfig], or anything with `to_config()` and
## `absorb_config()`.
var source: Object = null

## Heading text. A game that wants another word sets it before [method build].
var title_text: String = "Settings"

## Half-width and half-height of the panel, in pixels.
##
## The panel is this size whatever the document's length: the rows scroll inside it and the
## buttons sit below the scroll, so a config with eleven settings and one with a hundred
## both produce a screen a player can leave.
var half_size: Vector2 = Vector2(260.0, 240.0)

## Groups to show, or empty for all. Passed to [member DotSettingsPanel.only_groups].
var groups: Array[String] = []

## The id the stack registers this under. Set it before [method DotScreenStack.register].
##
## [b]Configurable because a game legitimately has two of these.[/b] The player's own
## settings and the interface's own [DotUiConfig] are different documents that both want
## this screen, and a stack registers by id — so a second one under the same name is
## either refused or silently replaces the first, and a menu button then opens the wrong
## document with no error anywhere.
##
## [b]Not [code]screen_id[/code], which is what it was called first.[/b] [DotScreen]
## already has a METHOD of that name, and a property cannot shadow an inherited method:
## GDScript refuses it with "Could not resolve external class member", which is reported
## against the file that USES it rather than the file that declares it — and the scene
## then hangs rather than failing, because a script that will not parse never reaches
## [code]get_tree().quit()[/code].
var id_override: StringName = &"settings"


func _screen_id() -> StringName:
	return id_override


## Builds the screen around [param p_source].
func build(p_source: Object) -> DotResult:
	source = p_source

	if source == null:
		return DotResult.fail(
			DotError.CODE_INVALID, "A settings screen needs something to edit."
		)

	hides_below = false
	blocks_input = true
	mouse_mode = DotScreen.Mouse.VISIBLE

	var container := PanelContainer.new()
	container.name = "Panel"
	# set_anchors_AND_OFFSETS_preset. `set_anchors_preset` does NOT set offsets, so a
	# Control built in code keeps the zero size it was created with -- and every child
	# then lays out inside nothing, invisibly, while being by every property correctly
	# configured. This family has shipped that twice, once five times in one addon.
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	container.offset_left = -half_size.x
	container.offset_right = half_size.x
	container.offset_top = -half_size.y
	container.offset_bottom = half_size.y
	add_child(container)

	var column := VBoxContainer.new()
	column.name = "Column"
	container.add_child(column)

	var heading := Label.new()
	heading.name = "Title"
	heading.text = title_text
	heading.theme_type_variation = &"DotHeading"
	column.add_child(heading)

	# A SCROLL CONTAINER, and it is not a nicety.
	#
	# A `DotSettingsPanel` is as tall as the document it was handed, and a document is as
	# long as somebody's `@export` list: `DotUiConfig` alone is eleven rows across four
	# groups and comes out around 600 pixels. Without this the column simply grew past the
	# panel and past the bottom of the screen, taking Apply, Revert and Back with it --
	# a settings screen a player can read and cannot leave or save from.
	#
	# Every assertion passed throughout. The screen had a size, the panel had a size, the
	# editors existed, Apply worked when called in code. A rendered frame is what showed
	# the buttons hanging off the bottom edge, which is this family's fourth or fifth time.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	# The one that does the work: without it the container asks for its content's full
	# height as a minimum and grows exactly as the column did, scrolling nothing.
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	panel = DotSettingsPanel.new()
	panel.name = "Settings"
	# Held until Apply. A live panel validates a half-edited document, which can
	# legitimately be invalid on its way to being valid -- a port typed one digit at a
	# time is out of range for every keystroke but the last.
	panel.live = false
	panel.only_groups = groups
	# Wide as the scroll area rather than as its own content: a settings row is a label and
	# an editor, and an editor sized to its text is a column of ragged boxes.
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)

	var bound := _rebind()

	if not bound.ok:
		return bound

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	column.add_child(buttons)

	_add_button(buttons, "Apply", apply)
	_add_button(buttons, "Revert", func() -> void: panel.revert())
	_add_button(buttons, "Back", close)

	# The first control, by NAME rather than by `get_path()`: this runs before the screen
	# is registered with a stack, so the node is not in the tree and `get_path()` pushes an
	# error and returns nothing. game-arena's pause menu shipped exactly that and opened
	# with nothing focused -- unusable with a gamepad, invisible with a mouse.
	initial_focus = NodePath("Panel/Column/Buttons/Apply")
	return DotResult.success(self)


## Writes the panel's edits through to the source.
func apply() -> void:
	if panel == null:
		return

	var wrote := panel.apply()

	if not wrote.ok:
		refused.emit(wrote)
		DotLog.result(CHANNEL, "settings", wrote)
		return

	# A bare DotConfig IS the document, so the panel writing into it is the whole of it.
	# A manager handed out a copy, and this is the half that makes it real.
	if source == config:
		applied.emit(PackedStringArray())
		return

	if not source.has_method("absorb_config"):
		# Said out loud rather than silently skipped: a source with `to_config` and no way
		# back is a screen whose Apply button cannot work, and the only symptom otherwise
		# is a setting that goes back to what it was.
		DotLog.warn(CHANNEL, "the settings source cannot take the values back", {
			"source": source.get_class(),
		})
		return

	var changed: Variant = source.call("absorb_config", config)
	var keys := changed as PackedStringArray if changed is PackedStringArray \
		else PackedStringArray()
	applied.emit(keys)
	DotLog.info(CHANNEL, "settings applied", {"changed": ", ".join(keys)})


## Re-reads the source. Called on every push.
##
## [b]The snapshot is taken at bind time, so a screen opened twice would otherwise show
## the values from whenever it was built[/b] — and a player who changed one from the
## console and then opened the menu would find Apply putting it back.
func _on_push() -> void:
	if panel != null:
		var _ignored := _rebind()


func _rebind() -> DotResult:
	if source is DotConfig:
		config = source as DotConfig
	elif source.has_method("to_config"):
		var made: Variant = source.call("to_config")

		if not (made is DotConfig):
			return DotResult.fail(
				DotError.CODE_UNSUPPORTED,
				"to_config() did not answer with a DotConfig.",
				type_string(typeof(made))
			)

		config = made as DotConfig
	else:
		return DotResult.fail(
			DotError.CODE_UNSUPPORTED,
			"That source is neither a DotConfig nor something with to_config().",
			source.get_class()
		)

	return panel.bind(config)


func _add_button(into: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = text
	button.text = text
	button.pressed.connect(action)
	into.add_child(button)
	return button
