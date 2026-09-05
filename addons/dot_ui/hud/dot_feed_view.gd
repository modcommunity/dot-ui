@tool
class_name DotFeedView
extends Control

## A bounded, self-expiring list of lines. The kill feed, and the chat history.
##
## [b]It takes dictionaries, not dot-match types.[/b] dot-ui does not import dot-match
## and does not know what a kill is; it knows how to show a bounded list of coloured
## fragments that time out. A game feeds it whatever it has, and the same class shows
## kills, chat and system messages.
##
## Each line is `{"parts": [{"text": String, "colour": Color}, ...], "at_ms": int}`.
## Fragments rather than one string because a kill feed is two player names in two team
## colours around a weapon, and rendering that from a single string means parsing it
## back out.

const CHANNEL := "ui.feed"

signal line_added(line: Dictionary)
signal line_expired(line: Dictionary)

@export_group("Bounds")

## Lines shown at once. Older ones fall off the top.
@export_range(1, 40, 1) var max_lines: int = 5

## Seconds a line stays up. Zero keeps them until they fall off the top.
@export_range(0.0, 600.0, 0.5) var lifetime_sec: float = 6.0

## Ignore [member lifetime_sec] and keep every line up to [member max_lines].
##
## What a chat window does while it is focused: a message that fades while you are
## reading it is a message you have to ask someone to repeat.
@export var hold: bool = false

@export_group("Layout")

## Newest at the bottom. Off puts it at the top, which is where a kill feed goes.
@export var newest_last: bool = true

@export_range(0.0, 40.0, 1.0) var line_height: float = 18.0

@export_range(0.0, 20.0, 1.0) var line_gap: float = 2.0

@export var alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT

@export_group("Fade")

## Seconds a line spends fading out at the end of its life.
@export_range(0.0, 5.0, 0.05) var fade_sec: float = 0.5

## `[{"parts": [...], "at_ms": int}, ...]`, oldest first.
var _lines: Array[Dictionary] = []


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Adds a line built from fragments.
##
## `parts` is `[{"text": ..., "colour": ...}]`. A missing colour uses the theme's.
func add_line(parts: Array) -> Dictionary:
	var line := {"parts": parts, "at_ms": Time.get_ticks_msec()}

	_lines.append(line)

	while _lines.size() > max_lines:
		var dropped: Dictionary = _lines[0]
		_lines.remove_at(0)
		line_expired.emit(dropped)

	line_added.emit(line)
	queue_redraw()
	return line


## Adds a plain one-colour line. What a system message is.
func add_text(text: String, colour: Color = Color.WHITE) -> Dictionary:
	return add_line([{"text": text, "colour": colour}])


## Adds a kill line from the pieces a kill feed has.
##
## Takes strings and colours rather than a `DotKillFeed.Entry`, so dot-ui never names
## a dot-match type. A game passes whatever its own feed holds.
func add_kill(
	killer_name: String,
	killer_colour: Color,
	cause: String,
	victim_name: String,
	victim_colour: Color,
	headshot: bool = false
) -> Dictionary:
	var parts: Array = []

	if killer_name != "":
		parts.append({"text": killer_name, "colour": killer_colour})
		parts.append({"text": "  ", "colour": Color.TRANSPARENT})

	parts.append({
		"text": "[%s]%s" % [cause, "!" if headshot else ""],
		"colour": Color(0.75, 0.77, 0.80),
	})
	parts.append({"text": "  ", "colour": Color.TRANSPARENT})
	parts.append({"text": victim_name, "colour": victim_colour})

	return add_line(parts)


func lines() -> Array[Dictionary]:
	return _lines


func line_count() -> int:
	return _lines.size()


func clear() -> void:
	_lines.clear()
	queue_redraw()


## Drops expired lines. Returns how many went.
##
## Called from `_process`, and public so a headless test can drive it without waiting
## out real seconds — which is the difference between a test that runs in a millisecond
## and one that runs in six.
func expire(now_ms: int) -> int:
	if hold or lifetime_sec <= 0.0:
		return 0

	var limit := int(lifetime_sec * 1000.0)
	var dropped := 0

	# From the front: lines are appended in time order, so the first one that is still
	# alive means every one after it is too.
	while not _lines.is_empty():
		var oldest: Dictionary = _lines[0]

		if now_ms - int(oldest["at_ms"]) < limit:
			break

		_lines.remove_at(0)
		line_expired.emit(oldest)
		dropped += 1

	if dropped > 0:
		queue_redraw()

	return dropped


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if expire(Time.get_ticks_msec()) == 0 and fade_sec > 0.0 and not _lines.is_empty():
		# Redrawn every frame only while something could be fading. A feed with lines
		# that never expire redraws once.
		if not hold and lifetime_sec > 0.0:
			queue_redraw()


## How opaque a line should be, from its age.
func opacity_of(line: Dictionary, now_ms: int) -> float:
	if hold or lifetime_sec <= 0.0 or fade_sec <= 0.0:
		return 1.0

	var age := float(now_ms - int(line["at_ms"])) * 0.001
	var remaining := lifetime_sec - age

	if remaining >= fade_sec:
		return 1.0

	return clampf(remaining / fade_sec, 0.0, 1.0)


func _draw() -> void:
	var font := get_theme_default_font()

	if font == null or _lines.is_empty():
		return

	var font_size := get_theme_default_font_size()
	var now := Time.get_ticks_msec()
	var step := line_height + line_gap

	for index in range(_lines.size()):
		var line: Dictionary = _lines[index]
		var row := index if newest_last else _lines.size() - 1 - index
		var y := float(row) * step + line_height
		var alpha := opacity_of(line, now)

		if alpha <= 0.0:
			continue

		var parts: Array = line["parts"]
		var width := 0.0

		for part in parts:
			width += font.get_string_size(
				str((part as Dictionary).get("text", "")),
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size
			).x

		var x := 0.0

		match alignment:
			HORIZONTAL_ALIGNMENT_RIGHT:
				x = size.x - width
			HORIZONTAL_ALIGNMENT_CENTER:
				x = (size.x - width) * 0.5
			_:
				x = 0.0

		for part in parts:
			var fragment: Dictionary = part
			var text := str(fragment.get("text", ""))

			if text == "":
				continue

			var colour: Color = fragment.get("colour", Color.WHITE)
			colour.a *= alpha

			draw_string(
				font,
				Vector2(x, y),
				text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1.0,
				font_size,
				colour
			)

			x += font.get_string_size(
				text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
			).x


func describe() -> Dictionary:
	return {
		"lines": _lines.size(),
		"max": max_lines,
		"lifetime": lifetime_sec,
		"hold": hold,
	}
