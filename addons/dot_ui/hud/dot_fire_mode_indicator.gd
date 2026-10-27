@tool
class_name DotFireModeIndicator
extends DotHudPiece

## The fire modes the held gun offers, in a row: "A" for auto, one bullet for semi, three bullets
## for burst. The selected one is lit, the others dim, and a mode the gun lacks is not drawn. A gun
## with a single mode draws nothing. Place it by the ammo counter; the host feeds it from
## `DotWeaponArsenal.fire_modes_available()` and `fire_mode()` (this addon does not depend on dot-weapon).

const AUTO := &"auto"
const SEMI := &"semi"
const BURST := &"burst"

## Order the modes are drawn in, whatever order the gun lists them.
const ORDER: Array[StringName] = [AUTO, SEMI, BURST]

@export var cell_width: float = 44.0
@export var cell_height: float = 26.0

## Modes on offer, as [constant AUTO], [constant SEMI], [constant BURST].
var available: Array[StringName] = []
var active: StringName = &""


## Shows [param p_available] with [param p_active] lit.
func show_modes(p_available: Array, p_active: StringName) -> void:
	var list: Array[StringName] = []
	for m in ORDER:
		if p_available.has(m):
			list.append(m)
	if list != available or p_active != active:
		available = list
		active = p_active
		queue_redraw()


func clear() -> void:
	show_modes([], &"")


func _shown() -> bool:
	return available.size() > 1


func footprint() -> Rect2:
	if not _shown():
		return Rect2()
	var w := cell_width * float(available.size())
	return Rect2(size.x - w, 0.0, w, cell_height)


func _draw() -> void:
	if not _shown():
		return
	var x := size.x - cell_width * float(available.size())
	for m in available:
		var lit := m == active
		var col := colour(&"text") if lit else colour(&"dim")
		var cell := Rect2(x + 2.0, 0.0, cell_width - 4.0, cell_height)
		ink_plate(cell, Color(0, 0, 0, -1), 6, col if lit else Color(0, 0, 0, -1), 2 if lit else 1)
		var cx := cell.position.x + cell.size.x * 0.5
		var cy := cell.position.y + cell.size.y * 0.5
		match m:
			AUTO:
				ink_text(Vector2(cx, cy + 6.0), "A", 17, col, HORIZONTAL_ALIGNMENT_CENTER, 0.0, 3)
			SEMI:
				_bullet(cx, cy, col)
			BURST:
				_bullet(cx - 8.0, cy, col)
				_bullet(cx, cy, col)
				_bullet(cx + 8.0, cy, col)
		x += cell_width


## One round standing up: a case and a rounded tip.
func _bullet(cx: float, cy: float, col: Color) -> void:
	draw_rect(Rect2(cx - 2.5, cy - 1.0, 5.0, 8.0), col)
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx - 2.5, cy - 1.0), Vector2(cx - 1.5, cy - 5.0), Vector2(cx, cy - 7.0),
		Vector2(cx + 1.5, cy - 5.0), Vector2(cx + 2.5, cy - 1.0),
	]), col)


func describe() -> Dictionary:
	var d := super.describe()
	d["modes"] = available.duplicate()
	d["active"] = active
	return d
