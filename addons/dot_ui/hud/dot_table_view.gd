@tool
class_name DotTableView
extends Control

## Rows and columns. The scoreboard, the server browser, and a stats panel.
##
## [b]It takes dictionaries, not dot-match types.[/b] dot-ui does not import dot-match:
## a table is given columns and an array of rows, and a game maps its own records onto
## them. The same class shows a scoreboard, a server list and a ban list.
##
## Built as a [GridContainer] of [Label]s rather than drawn, because a table needs the
## engine's text layout — column widths that depend on content, and clipping that
## depends on the widths.

# No log channel: a drawer of rows it is handed. What the rows say, and anything that
# went wrong producing them, belongs to the scoreboard or browser that built them.

## A row was clicked. [param index] is into the rows as last given, before sorting.
signal row_activated(index: int, row: Dictionary)

@export_group("Layout")

## Column separation, in pixels.
@export_range(0.0, 80.0, 1.0) var column_gap: float = 16.0

## Show the header row.
@export var show_header: bool = true

## Rows shown at once. Zero shows all of them.
##
## Worth setting on a scoreboard: a server with 64 players produces 64 rows of Labels,
## and a scoreboard nobody scrolls only ever shows the top of it.
@export_range(0, 256, 1) var max_rows: int = 0

@export_group("Colour")

@export var header_colour: Color = Color(0.62, 0.65, 0.70, 1.0)

@export var row_colour: Color = Color(0.92, 0.93, 0.95, 1.0)

## Applied to a row whose dictionary carries `"highlight": true`. The local player.
@export var highlight_colour: Color = Color(1.0, 0.85, 0.35, 1.0)

## `[{"key": StringName, "title": String, "width": float, "align": int}, ...]`.
##
## `width` is a size flag ratio, not pixels: a column of names should take the slack, and a
## column that omits one gets an equal share. Zero means "shrink to the content" and is the
## only value that does not expand — spell it when you mean it.
## and a column of numbers should not.
var columns: Array[Dictionary] = []

var _rows: Array[Dictionary] = []
var _grid: VBoxContainer = null


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ensure_grid()


## The rows container. A VBox of HBoxes, not a [GridContainer].
##
## [b]A `GridContainer` gives every column the same width, whatever ratio a cell asks
## for.[/b] `size_flags_stretch_ratio` is honoured by a [BoxContainer] and by nothing else,
## so `width` — documented here since this class was written, and set to 3.0 for the name
## column in `scoreboard_columns()` — did nothing at all, in every table, in every game.
## Measured: four columns with ratios 0.4, 3.0, 1.0 and 1.0 came out 308 pixels each.
##
## A row per `HBoxContainer` honours the ratios, and the columns still line up ACROSS rows
## because every row is built from the same ratio list at the same width. It is kept as
## `Grid` by name so a host or a check that found it by path still does.
func _ensure_grid() -> void:
	if _grid != null and is_instance_valid(_grid):
		return

	_grid = VBoxContainer.new()
	_grid.name = "Grid"
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_grid)


## Declares the columns. Rebuilds the table.
func set_columns(p_columns: Array[Dictionary]) -> void:
	columns = p_columns
	_ensure_grid()
	_rebuild()


## Replaces the rows. Each is `{column key: value}`, plus an optional
## `"highlight": bool` and an optional `"colour": Color` for the whole row.
func set_rows(rows: Array[Dictionary]) -> void:
	_rows = rows
	_rebuild()


func rows() -> Array[Dictionary]:
	return _rows


func row_count() -> int:
	return _rows.size()


func visible_row_count() -> int:
	return _rows.size() if max_rows <= 0 else mini(_rows.size(), max_rows)


func clear() -> void:
	_rows.clear()
	_rebuild()


func _rebuild() -> void:
	_ensure_grid()

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()

	if columns.is_empty():
		return

	if show_header:
		var header := _make_row()

		for column in columns:
			header.add_child(
				_make_cell(str(column.get("title", "")), header_colour, column)
			)

		_grid.add_child(header)

	for index in range(visible_row_count()):
		var row: Dictionary = _rows[index]
		var colour: Color = row.get("colour", row_colour)

		if bool(row.get("highlight", false)):
			colour = highlight_colour

		var line := _make_row()

		for column in columns:
			var key := StringName(str(column.get("key", "")))
			line.add_child(_make_cell(str(row.get(key, "")), colour, column))

		_grid.add_child(line)


func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(column_gap))
	return row


func _make_cell(text: String, colour: Color, column: Dictionary) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", colour)
	label.horizontal_alignment = int(
		column.get("align", HORIZONTAL_ALIGNMENT_LEFT)
	) as HorizontalAlignment
	label.clip_text = true

	# AN ABSENT WIDTH IS AN EQUAL SHARE, NOT NOTHING.
	#
	# It used to be `0.0` -> `SIZE_FILL`, which reads as "take your content's width" and is
	# not, because `clip_text` two lines above sets a Label's minimum size to ZERO. So a
	# column with no width collapsed to nothing and the one column that had one took the
	# whole row -- and `scoreboard_columns()` gives a width only to `name`.
	#
	# What that means is that **every scoreboard and every server browser in this family
	# has shown one column**: no kills, no deaths, no assists, no score, no ping, no mass,
	# no player count. The data was right, the columns were in `describe()`, and the suite
	# asserted both. A rendered frame of game-arena's scoreboard is what showed it, and
	# there is no assertion that could have: the cells exist, the rows exist, and the
	# widths they were laid out at are a property of a frame nothing was drawing.
	#
	# A column that genuinely wants to shrink to its content asks for it by name, because
	# that is the rarer thing and the one worth spelling.
	var width := float(column.get("width", 1.0))

	if width > 0.0:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = width
	else:
		# Explicitly zero, and therefore explicitly asked for. `clip_text` is turned off
		# with it: a column sized to its content whose minimum size is zero is a column
		# that is not there, which is the bug above.
		label.clip_text = false
		label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	return label


## The standard scoreboard columns, so a game does not have to invent them.
static func scoreboard_columns() -> Array[Dictionary]:
	return [
		{"key": &"name", "title": "Player", "width": 3.0},
		{"key": &"kills", "title": "K", "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"deaths", "title": "D", "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"assists", "title": "A", "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"score", "title": "Score", "align": HORIZONTAL_ALIGNMENT_RIGHT},
		{"key": &"ping", "title": "Ping", "align": HORIZONTAL_ALIGNMENT_RIGHT},
	]


func describe() -> Dictionary:
	var keys := []
	for column in columns:
		keys.append(str(column.get("key", "")))

	return {
		"columns": keys,
		"rows": _rows.size(),
		"shown": visible_row_count(),
	}
