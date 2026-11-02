@tool
class_name DotStatusLines
extends DotHudPiece

## Short stacked status text, one line each ("Down, hold on for help", "Haste x2  0:12"),
## top to bottom, left- or right-aligned to this control's edge. A row is a String or
## `{text, colour}`; the host passes the words already translated.

@export var row_height: float = 22.0
@export var font_size: int = 15
@export var align_right: bool = false
## Lines past this are dropped; the newest rows are the host's last.
@export var max_lines: int = 8
## The theme colour a plain row is drawn in (`text`, `dim`, `highlight`, `low`, `good`).
@export var colour_key: StringName = &"text"
@export var show_plate: bool = false

var rows: Array = []


func show_lines(p_rows: Array) -> void:
	var kept := p_rows.slice(0, max_lines)
	if str(kept) != str(rows):
		rows = kept
		queue_redraw()


func clear() -> void:
	show_lines([])


## The row's words as a suite reads them.
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for r in rows:
		out.append(_text_of(r))
	return out


## "Title x2  0:12": a timed effect line. [param seconds] below 0 is "until the round ends"
## and says [param endless]; [param stacks] over 1 adds a multiplier.
static func effect_text(title: String, stacks: int, seconds: float, endless: String = "this round") -> String:
	var tag := " x%d" % stacks if stacks > 1 else ""
	return "%s%s  %s" % [title, tag, DotScoreStrip.clock_text(seconds) if seconds >= 0.0 else endless]


func _text_of(r: Variant) -> String:
	return str((r as Dictionary).get("text", "")) if r is Dictionary else str(r)


func _row_width(r: Variant) -> float:
	return text_width(_text_of(r), font_size)


func footprint() -> Rect2:
	if rows.is_empty():
		return Rect2()
	var w := 0.0
	for r in rows:
		w = maxf(w, _row_width(r))
	w += 16.0 if show_plate else 0.0
	return Rect2(size.x - w if align_right else 0.0, 0.0, w, float(rows.size()) * row_height)


func _draw() -> void:
	if rows.is_empty():
		return
	var box := footprint()
	if show_plate:
		ink_plate(box, Color(0, 0, 0, -1), 7)
	var y := row_height * 0.5 + float(font_size) * 0.38
	var pad := 8.0 if show_plate else 0.0
	for r in rows:
		var fill := colour(colour_key)
		if r is Dictionary and (r as Dictionary).has("colour"):
			fill = (r as Dictionary)["colour"]
		var x := size.x - pad if align_right else pad
		var align := HORIZONTAL_ALIGNMENT_RIGHT if align_right else HORIZONTAL_ALIGNMENT_LEFT
		ink_text(Vector2(0.0 if align_right else x, y), _text_of(r), font_size, fill, align, x if align_right else -1.0, 5)
		y += row_height


func describe() -> Dictionary:
	var out := super()
	out.merge({"lines": texts()})
	return out
