@tool
class_name DotAmmoCounter
extends DotHudPiece

## Bottom right: what is in hand, and `magazine | reserve` in big numbers under its name,
## right-aligned to this control's right edge. A weapon with no magazine shows its name
## alone; an endless reserve draws "∞".
##
## The magazine goes to the theme's `low` colour when the host says so ([member low]): only
## the host knows whether eight rounds is low for this weapon.

## Drawn instead of the reserve count when [member infinite] is set.
const INFINITE := "∞"

var weapon_name: String = ""
## Rounds in the magazine; below 0 for a weapon with none (melee, a tool).
var magazine: int = -1
## Rounds in reserve; below 0 draws no reserve at all.
var reserve: int = -1
var low: bool = false
var infinite: bool = false


func show_ammo(p_name: String, p_magazine: int, p_reserve: int, p_low: bool = false, p_infinite: bool = false) -> void:
	if p_name != weapon_name or p_magazine != magazine or p_reserve != reserve or p_low != low or p_infinite != infinite:
		weapon_name = p_name
		magazine = p_magazine
		reserve = p_reserve
		low = p_low
		infinite = p_infinite
		queue_redraw()


## Nothing in hand.
func clear() -> void:
	show_ammo("", -1, -1)


## The count as words, "12 | 90": what a suite reads.
func count_text() -> String:
	if magazine < 0:
		return ""
	var rest := _rest()
	return str(magazine) if rest == "" else "%d %s" % [magazine, rest]


func _rest() -> String:
	if infinite:
		return "| " + INFINITE
	return "| %d" % reserve if reserve >= 0 else ""


func _plate() -> Rect2:
	var name_w := text_width(weapon_name.to_upper(), 15)
	var count_w := 0.0
	if magazine >= 0:
		var rest := _rest()
		count_w = text_width(str(magazine), 36) + (10.0 + text_width(rest, 22) if rest != "" else 0.0)
	var plate_w := maxf(name_w, count_w) + 28.0
	return Rect2(size.x - plate_w + 14.0, -4.0, plate_w, 70.0 if magazine >= 0 else 32.0)


## The plate under the name and the count; nothing with nothing in hand.
func footprint() -> Rect2:
	return _plate() if weapon_name != "" or magazine >= 0 else Rect2()


func _draw() -> void:
	if weapon_name == "" and magazine < 0:
		return
	var right := size.x
	ink_plate(_plate(), Color(0, 0, 0, -1), 9)
	ink_text(Vector2(0.0, 18.0), weapon_name.to_upper(), 15, Color(colour(&"text"), 0.95), HORIZONTAL_ALIGNMENT_RIGHT, right, 4)
	if magazine < 0:
		return
	var mag := str(magazine)
	var rest := _rest()
	var rest_w := text_width(rest, 22) if rest != "" else 0.0
	if rest != "":
		ink_text(Vector2(right - rest_w, 56.0), rest, 22, colour(&"dim"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5)
	var mag_w := text_width(mag, 36)
	var gap := 10.0 if rest != "" else 0.0
	ink_text(Vector2(right - rest_w - gap - mag_w, 56.0), mag, 36, colour(&"low") if low else colour(&"text"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 6)


func describe() -> Dictionary:
	var out := super()
	out.merge({"weapon": weapon_name, "count": count_text(), "low": low})
	return out
