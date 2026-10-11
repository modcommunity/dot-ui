@tool
class_name DotScoreStrip
extends DotHudPiece

## Top centre: the clock on its own plate, the two scores either side of it when there are
## sides, and a line under them ("First to 25 · Team deathmatch", "Round 2 of 5").
##
## [b]The clock is the piece every game had written for itself[/b]: a centred `Label` with
## `"%d:%02d"`, in seven games, each at its own size and none outlined. A game with no
## scores calls [method show_clock] alone and gets the clock and the line under it; one
## with two sides (two teams, or "you" against the leader in a free-for-all) adds
## [method show_scores].
##
## The plates are drawn centred on this control's middle, so it is placed with
## `PRESET_CENTER_TOP` and any width at least [method footprint]'s.

const PLATE_W := 132.0
const CLOCK_W := 112.0
const H := 46.0
const GAP := 6.0

var left_score: int = 0
var right_score: int = 0
var left_tag: String = ""
var right_tag: String = ""
var left_colour: Color = Color(0.22, 0.5, 0.95)
var right_colour: Color = Color(0.9, 0.24, 0.32)
## Whether the score plates are drawn: on from the first [method show_scores].
var sides: bool = false
var clock: String = ""
## Under the plates: what wins, and the mode's name, joined by a dot.
var target: String = ""
var mode_name: String = ""
## The clock in the theme's `low` colour: the last seconds, a round about to end.
var clock_low: bool = false


## "M:SS" for [param seconds], rounded up so a clock never says 0:00 while time is left;
## "H:MM:SS" from an hour. Negative reads as 0:00.
static func clock_text(seconds: float) -> String:
	var whole := int(ceilf(maxf(seconds, 0.0)))
	if whole >= 3600:
		return "%d:%02d:%02d" % [whole / 3600, (whole / 60) % 60, whole % 60]
	return "%d:%02d" % [whole / 60, whole % 60]


func show_scores(p_left: int, p_right: int, p_left_tag: String, p_right_tag: String, p_left_colour: Color, p_right_colour: Color) -> void:
	left_score = p_left
	right_score = p_right
	left_tag = p_left_tag
	right_tag = p_right_tag
	left_colour = p_left_colour
	right_colour = p_right_colour
	sides = true
	queue_redraw()


## Takes the score plates down: a mode with no sides, a warmup.
func hide_scores() -> void:
	if sides:
		sides = false
		queue_redraw()


## [param p_clock] is the words to draw ([method clock_text] makes them); empty hides the
## clock plate (between rounds).
func show_clock(p_clock: String, p_low: bool = false, p_target: String = "", p_mode: String = "") -> void:
	if p_clock == clock and p_low == clock_low and p_target == target and p_mode == mode_name:
		return
	clock = p_clock
	clock_low = p_low
	target = p_target
	mode_name = p_mode
	queue_redraw()


## The line under the plates.
func under_text() -> String:
	if mode_name == "":
		return target
	return "%s   ·   %s" % [target, mode_name] if target != "" else mode_name


func footprint() -> Rect2:
	var plates := (PLATE_W * 2.0 + GAP * 2.0 + CLOCK_W) if sides else (CLOCK_W if clock != "" else 0.0)
	var under := under_text()
	var w := maxf(plates, text_width(under, 15) if under != "" else 0.0)
	if w <= 0.0:
		return Rect2()
	var top := 0.0 if (sides or clock != "") else H + 6.0
	return Rect2(size.x * 0.5 - w * 0.5, top, w, H + 28.0 - top)


func _draw() -> void:
	var mid := size.x * 0.5
	var clock_rect := Rect2(mid - CLOCK_W * 0.5, 0.0, CLOCK_W, H)
	if sides:
		_side(Rect2(clock_rect.position.x - GAP - PLATE_W, 0.0, PLATE_W, H), left_colour, left_tag, left_score)
		_side(Rect2(clock_rect.end.x + GAP, 0.0, PLATE_W, H), right_colour, right_tag, right_score)
	if clock != "" or sides:
		var plate := colour(&"plate")
		ink_plate(clock_rect, Color(plate, minf(plate.a + 0.2, 1.0)), 8, Color(1, 1, 1, 0.22), 1)
		ink_text(Vector2(clock_rect.position.x, clock_rect.end.y - 12.0), clock, 26,
			colour(&"low") if clock_low else colour(&"text"), HORIZONTAL_ALIGNMENT_CENTER, CLOCK_W, 5)
	var under := under_text()
	if under != "":
		ink_text(Vector2(0.0, H + 22.0), under, 15, Color(colour(&"text"), 0.92), HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)


func _side(rect: Rect2, fill: Color, tag: String, score: int) -> void:
	ink_plate(rect, Color(fill.darkened(0.15), 0.9), 8, Color(1, 1, 1, 0.35), 1)
	# A lighter top half: the plates read as buttons, not as flat paint.
	ink_plate(Rect2(rect.position + Vector2(2.0, 2.0), Vector2(rect.size.x - 4.0, rect.size.y * 0.45)), Color(1, 1, 1, 0.12), 6, Color(0, 0, 0, 0), 0)
	if tag != "":
		ink_text(Vector2(rect.position.x, rect.position.y + 13.0), tag, 11, Color(1, 1, 1, 0.9), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 3)
	ink_text(Vector2(rect.position.x, rect.end.y - 7.0), str(score), 26, colour(&"text"), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 5)


func describe() -> Dictionary:
	var out := super()
	out.merge({"clock": clock, "sides": sides, "left": left_score, "right": right_score, "under": under_text()})
	return out
