@tool
class_name DotScoreboardScreen
extends DotScreen

## The scoreboard a player holds Tab for: a title, and one row per player, ranked by the
## game. Every game in the family wants one; what is IN it is each game's.
##
## [b]The game supplies the rows, not a scoreboard object[/b] ([member row_fn]), because the
## numbers are not the same everywhere: a deathmatch has kills and deaths, an obstacle
## course points and the checkpoint reached, an eating game mass. [member columns] are the
## game's too, defaulting to [method DotTableView.scoreboard_columns]; a column with
## `"kind": &"icon"` draws the row's value as a picture (an avatar).
##
## [b]Transparent, and does not block input[/b], like game-arena's own: it is held down
## during a live game, so it must not stop the player moving or hide what they look at.
##
## [codeblock]
## var board := DotScoreboardScreen.new()
## board.title_text = "Wipeout - Course 3"
## board.columns = [{"key": &"avatar", "kind": &"icon", "width": 0.0}, ...]
## board.row_fn = func() -> Array[Dictionary]: return my_rows()
## stack.register(board)
## [/codeblock]

## The line over the table: the game, the map, the round.
var title_text: String = "Scoreboard"

## Returns the rows, best first: Dictionaries keyed by column keys, with "highlight" true
## on the player looking at it.
var row_fn: Callable = Callable()

## The table's columns. Empty uses [method DotTableView.scoreboard_columns].
var columns: Array[Dictionary] = []

## Seconds between refreshes while it is open.
var refresh_sec: float = 0.5

var table: DotTableView = null
var _title: Label = null
var _since: float = 0.0


func _screen_id() -> StringName:
	return &"scoreboard"


func _ready() -> void:
	blocks_input = false
	hides_below = false
	closable = true
	mouse_mode = DotScreen.Mouse.INHERIT
	_build()


func _build() -> void:
	if table != null:
		return

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -380.0
	panel.offset_right = 380.0
	# Below the top of the screen's middle, where a HUD keeps its clock and its titles: the
	# first render (mg-wipeout) put this title on top of the course's name.
	panel.offset_top = -170.0
	panel.offset_bottom = 260.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	# A margin inside the panel: a right-aligned last column ran to the panel's edge and its
	# header was clipped ("Pin" in the same render).
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	table = DotTableView.new()
	table.max_rows = 32
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(table)
	table.set_columns(columns if not columns.is_empty() else DotTableView.scoreboard_columns())


func _on_push() -> void:
	refresh()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not visible:
		return
	_since += delta
	if _since >= refresh_sec:
		refresh()


## Rebuilds the rows from [member row_fn] now.
func refresh() -> void:
	_since = 0.0
	_build()
	_title.text = title_text
	if not columns.is_empty():
		table.set_columns(columns)
	if row_fn.is_valid():
		var rows: Variant = row_fn.call()
		if rows is Array:
			var typed: Array[Dictionary] = []
			for row in rows:
				if row is Dictionary:
					typed.append(row)
			table.set_rows(typed)


func describe() -> Dictionary:
	return {"title": title_text, "rows": table.row_count() if table != null else 0}
