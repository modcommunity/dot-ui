@tool
class_name DotKeyHints
extends DotHudPiece

## The keys worth knowing, one row each, top to bottom: a key drawn as a key and the words
## beside it. Left-aligned from this control's left edge by default, or right-aligned to
## its right edge ([member align_right]) for a hint column on the right.
##
## Rows are `[words, key]` pairs, the key being the player's binding as text (see
## [DotKeyPrompt]).

@export var row_height: float = 28.0
@export var font_size: int = 16
@export var align_right: bool = false

## `[words, key]` per row.
var rows: Array = []


func show_hints(p_rows: Array) -> void:
	if str(p_rows) != str(rows):
		rows = p_rows.duplicate()
		queue_redraw()


func clear() -> void:
	show_hints([])


func _row_width(r: Array) -> float:
	return keycap_width(str(r[1]), font_size - 4) + 8.0 + text_width(str(r[0]), font_size)


func footprint() -> Rect2:
	if rows.is_empty():
		return Rect2()
	var w := 0.0
	for r in rows:
		w = maxf(w, _row_width(r))
	return Rect2(size.x - w if align_right else 0.0, 0.0, w, float(rows.size()) * row_height)


func _draw() -> void:
	var y := row_height * 0.5
	for r in rows:
		var key := str(r[1])
		var x := size.x - _row_width(r) if align_right else 0.0
		var cap_w := ink_keycap(Vector2(x, y), key, font_size - 4)
		ink_text(Vector2(x + cap_w + 8.0, y + float(font_size) * 0.38), str(r[0]), font_size, colour(&"text"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5)
		y += row_height


func describe() -> Dictionary:
	var out := super()
	out.merge({"rows": rows.size()})
	return out
