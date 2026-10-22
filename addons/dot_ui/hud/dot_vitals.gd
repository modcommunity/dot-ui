@tool
class_name DotVitals
extends DotHudPiece

## Bottom left: health as a bar with its number in big type at the bar's end, armour as a
## thin bar under it with a smaller number when there is any, and a drawn cross. On one
## plate, because white numbers on a white floor are an outline and nothing else.
##
## [b]The bar eases and the number never does[/b], for the reason [DotStatBar] gives: a hit
## that takes a third of your health is legible as a slide and invisible as a jump, and a
## lagging number is a lie about the current value.
##
## A [member bonus] (health that drains away, a shield over the real thing) is drawn after
## the real fill in its own colour. A [member status] ("DOWN", "DEAD") replaces the number.
##
## The cross and the number go to the theme's `low` colour at or under [member low_fraction]:
## the state worth seeing is the one a fixture picked at random misses, so the suite and the
## screenshot both put health under it.

## Where the bars start and end in this control's space; the number sits just past the end.
@export var bar_start: float = 38.0
@export var bar_end: float = 300.0
@export var bar_height: float = 16.0
@export var armour_height: float = 7.0
@export_range(0.0, 1.0, 0.01) var low_fraction: float = 0.25
## Seconds the bar takes to close most of a gap. 0 jumps.
@export_range(0.0, 2.0, 0.01) var ease_sec: float = 0.18
## Draw the cross. Off for a game whose health is not a body's (a vehicle, a balloon).
@export var show_cross: bool = true

@export var fill_colour: Color = Color(0.36, 0.86, 0.48)
@export var bonus_colour: Color = Color(0.92, 0.92, 0.92, 0.85)
@export var armour_colour: Color = Color(0.4, 0.66, 1.0)

var health: float = 100.0
var max_health: float = 100.0
var armour: float = 0.0
var max_armour: float = 100.0
var bonus: float = 0.0
## Drawn instead of the number when not empty.
var status: String = ""

var _shown: float = 1.0
var _shown_armour: float = 0.0
var _primed := false


## Hands over what to draw. A redraw only on a change.
func show_vitals(p_health: float, p_max: float, p_armour: float = 0.0, p_max_armour: float = 100.0, p_bonus: float = 0.0) -> void:
	if (is_equal_approx(p_health, health) and is_equal_approx(p_max, max_health)
			and is_equal_approx(p_armour, armour) and is_equal_approx(p_max_armour, max_armour)
			and is_equal_approx(p_bonus, bonus) and _primed):
		return
	health = p_health
	max_health = maxf(p_max, 0.001)
	armour = p_armour
	max_armour = maxf(p_max_armour, 0.001)
	bonus = maxf(p_bonus, 0.0)
	if not _primed:
		_shown = fraction()
		_shown_armour = armour_fraction()
		_primed = true
	queue_redraw()


func show_status(words: String) -> void:
	if words != status:
		status = words
		queue_redraw()


func fraction() -> float:
	return clampf(health / max_health, 0.0, 1.0)


func armour_fraction() -> float:
	return clampf(armour / max_armour, 0.0, 1.0)


func is_low() -> bool:
	return fraction() <= low_fraction


## What the bar shows this frame, eased. What a check reads.
func shown_fraction() -> float:
	return _shown


## The number as drawn: the status when there is one, else health rounded up (a player
## on 0.4 is alive, and "0" says otherwise).
func number_text() -> String:
	return status if status != "" else str(int(ceilf(health)))


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	advance(delta)


## Moves the eased bars on by [param delta] seconds. Public so a suite can step it.
func advance(delta: float) -> void:
	var target := fraction()
	var target_armour := armour_fraction()
	var before := _shown
	var before_armour := _shown_armour
	if ease_sec <= 0.0:
		_shown = target
		_shown_armour = target_armour
	else:
		# Exponential, not linear: a linear catch-up takes as long for one point as for a
		# hundred, which reads as a bar that is broken for small hits.
		var k := 1.0 - exp(-delta * 3.0 / ease_sec)
		_shown = lerpf(_shown, target, k)
		_shown_armour = lerpf(_shown_armour, target_armour, k)
		if absf(_shown - target) < 0.001:
			_shown = target
		if absf(_shown_armour - target_armour) < 0.001:
			_shown_armour = target_armour
	if _shown != before or _shown_armour != before_armour:
		queue_redraw()


func _plate() -> Rect2:
	return Rect2(0.0, 0.0, bar_end + 22.0 + text_width(number_text(), 30), 72.0 if armour > 0.0 else 56.0)


func footprint() -> Rect2:
	return _plate()


func _draw() -> void:
	var low := is_low()
	var text_c := colour(&"text")
	var low_c := colour(&"low")
	ink_plate(_plate(), Color(0, 0, 0, -1), 9)
	if show_cross:
		# A cross, drawn: the genre's health mark, and no art to go missing.
		var c := Vector2(maxf(bar_start - 28.0, 10.0), 14.0 + bar_height * 0.5)
		draw_rect(Rect2(c - Vector2(3.0, 9.0), Vector2(6.0, 18.0)), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(c - Vector2(9.0, 3.0), Vector2(18.0, 6.0)), Color(0, 0, 0, 0.5))
		var mark := low_c if low else colour(&"good")
		draw_rect(Rect2(c - Vector2(2.0, 8.0), Vector2(4.0, 16.0)), mark)
		draw_rect(Rect2(c - Vector2(8.0, 2.0), Vector2(16.0, 4.0)), mark)
	var width := bar_end - bar_start
	var top := 14.0
	draw_rect(Rect2(bar_start, top, width, bar_height), Color(0.0, 0.0, 0.0, 0.55))
	var fill := width * _shown
	draw_rect(Rect2(bar_start, top, fill, bar_height), low_c if low else fill_colour)
	if bonus > 0.0:
		var extra := minf(width * clampf(bonus / max_health, 0.0, 1.0), width - fill)
		draw_rect(Rect2(bar_start + fill, top, maxf(extra, 0.0), bar_height), bonus_colour)
	# A lighter top third, so the bar reads as a bar and not as a stripe of paint.
	draw_rect(Rect2(bar_start, top, fill, bar_height * 0.3), Color(1, 1, 1, 0.18))
	ink_text(Vector2(bar_end + 10.0, 40.0), number_text(), 30, low_c if low or status != "" else text_c)
	if armour > 0.0:
		var a_top := top + bar_height + 8.0
		draw_rect(Rect2(bar_start, a_top, width, armour_height), Color(0.0, 0.0, 0.0, 0.45))
		draw_rect(Rect2(bar_start, a_top, width * _shown_armour, armour_height), armour_colour)
		# Toward the text's own lightness: a pale blue on a light theme's plate was not there
		# at all (hud_pieces_light.png, first render).
		var tone := armour_colour.lightened(0.3) if text_c.get_luminance() >= 0.5 else armour_colour.darkened(0.35)
		ink_text(Vector2(bar_end + 10.0, 62.0), str(int(ceilf(armour))), 16, tone, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)


func describe() -> Dictionary:
	var out := super()
	out.merge({"health": health, "max": max_health, "armour": armour, "bonus": bonus, "status": status, "low": is_low()})
	return out
