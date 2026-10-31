@tool
class_name DotVitals
extends DotHudPiece

## Bottom left: health as a rounded bar with quarter ticks and its number in big type at the
## bar's end, armour as a thin bar under it with a smaller number when there is any, a
## drawn cross, and (once [method show_streak] is called) a killstreak row: icon, label and
## a gold bar. On one plate, because white numbers on a white floor are an outline and
## nothing else.
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

## Words of the streak row; one `%d` for the count. A game with a locale catalogue assigns it.
@export var streak_format: String = "Killstreak x%d"
## Drawn in the streak row's icon slot (tinted gold). Null draws a drawn flame.
@export var streak_icon: Texture2D
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

var streak: int = 0
var streak_full: int = 0
var _shown_streak: float = 0.0
## Seconds since the streak last rose, for the icon's pulse.
var _since_streak: float = 99.0
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


## Hands over the killstreak: [param count] kills toward [param full]. A [param full] of 0
## hides the row. The row appears on the first call, so a streak of 0 still shows a dim one.
func show_streak(count: int, full: int) -> void:
	if count == streak and full == streak_full:
		return
	if count > streak:
		_since_streak = 0.0
	if full != streak_full and streak_full == 0:
		_shown_streak = clampf(float(count) / float(maxi(1, full)), 0.0, 1.0)
	streak = count
	streak_full = maxi(full, 0)
	queue_redraw()


func streak_fraction() -> float:
	return clampf(float(streak) / float(maxi(1, streak_full)), 0.0, 1.0)


func shown_streak_fraction() -> float:
	return _shown_streak


func has_streak_row() -> bool:
	return streak_full > 0


func streak_text() -> String:
	return streak_format % streak


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
	var before_streak := _shown_streak
	var target_streak := streak_fraction()
	var pulsing := _since_streak < 0.3
	_since_streak += delta
	if ease_sec <= 0.0:
		_shown = target
		_shown_armour = target_armour
		_shown_streak = target_streak
	else:
		# Exponential, not linear: a linear catch-up takes as long for one point as for a
		# hundred, which reads as a bar that is broken for small hits.
		var k := 1.0 - exp(-delta * 3.0 / ease_sec)
		_shown = lerpf(_shown, target, k)
		_shown_armour = lerpf(_shown_armour, target_armour, k)
		_shown_streak = lerpf(_shown_streak, target_streak, k)
		if absf(_shown_streak - target_streak) < 0.001:
			_shown_streak = target_streak
		if absf(_shown - target) < 0.001:
			_shown = target
		if absf(_shown_armour - target_armour) < 0.001:
			_shown_armour = target_armour
	if _shown != before or _shown_armour != before_armour or _shown_streak != before_streak or pulsing:
		queue_redraw()


func _plate() -> Rect2:
	var h := 72.0 if armour > 0.0 else 56.0
	if streak_full > 0:
		h += 32.0
	return Rect2(0.0, 0.0, bar_end + 22.0 + text_width(number_text(), 30), h)


func footprint() -> Rect2:
	return _plate()


## A rounded rectangle; the corner is capped at half the height so a thin bar is a pill.
func _pill(rect: Rect2, c: Color, edge: Color = Color(0, 0, 0, 0)) -> void:
	if rect.size.x <= 0.5:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = c
	box.set_corner_radius_all(int(minf(rect.size.y * 0.5, rect.size.x * 0.5)))
	if edge.a > 0.0:
		box.border_color = edge
		box.set_border_width_all(1)
	draw_style_box(box, rect)


func _draw() -> void:
	var low := is_low()
	var text_c := colour(&"text")
	var low_c := colour(&"low")
	ink_plate(_plate(), Color(0, 0, 0, -1), 12)
	var width := bar_end - bar_start
	var top := 14.0
	var mid := top + bar_height * 0.5
	if show_cross:
		# A cross on a round badge, drawn: no art to go missing.
		var c := Vector2(bar_start - 18.0, mid)
		var mark := low_c if low else colour(&"good")
		draw_circle(c, 11.0, Color(0, 0, 0, 0.45))
		draw_rect(Rect2(c - Vector2(2.0, 6.0), Vector2(4.0, 12.0)), mark)
		draw_rect(Rect2(c - Vector2(6.0, 2.0), Vector2(12.0, 4.0)), mark)
	var track := Rect2(bar_start, top, width, bar_height)
	_pill(track, Color(0.0, 0.0, 0.0, 0.55), Color(1, 1, 1, 0.14))
	var fill := (width - 2.0) * _shown
	var body := low_c if low else fill_colour
	_pill(Rect2(bar_start + 1.0, top + 1.0, fill, bar_height - 2.0), body)
	if bonus > 0.0:
		var extra := minf((width - 2.0) * clampf(bonus / max_health, 0.0, 1.0), width - 2.0 - fill)
		if extra > 1.0:
			_pill(Rect2(bar_start + 1.0 + fill, top + 1.0, extra, bar_height - 2.0), bonus_colour)
	if fill > 6.0:
		# A sheen along the upper half, so the bar reads as a bar and not as a stripe of paint.
		_pill(Rect2(bar_start + 4.0, top + 3.0, maxf(fill - 6.0, 0.0), bar_height * 0.28), Color(1, 1, 1, 0.22))
	for q in 3:
		var x := bar_start + width * 0.25 * (q + 1)
		draw_line(Vector2(x, top + 3.0), Vector2(x, top + bar_height - 3.0), Color(0, 0, 0, 0.4), 1.0)
	ink_text(Vector2(bar_end + 10.0, 40.0), number_text(), 30, low_c if low or status != "" else text_c)
	var next_y := top + bar_height + 6.0
	if armour > 0.0:
		_pill(Rect2(bar_start, next_y, width, armour_height), Color(0.0, 0.0, 0.0, 0.45))
		_pill(Rect2(bar_start + 1.0, next_y + 1.0, (width - 2.0) * _shown_armour, armour_height - 2.0), armour_colour)
		# Toward the text's own lightness: a pale blue on a light theme's plate was not there at all.
		var tone := armour_colour.lightened(0.3) if text_c.get_luminance() >= 0.5 else armour_colour.darkened(0.35)
		ink_text(Vector2(bar_end + 10.0, 62.0), str(int(ceilf(armour))), 16, tone, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)
		next_y += armour_height + 8.0
	if streak_full > 0:
		_draw_streak(next_y + 2.0, width)


func _draw_streak(y: float, width: float) -> void:
	var gold := colour(&"highlight")
	var live := streak > 0
	var tint := gold if live else Color(colour(&"dim"), 0.6)
	var pulse := 1.0 + 0.35 * maxf(0.0, 1.0 - _since_streak / 0.3)
	var side := 22.0 * pulse
	var centre := Vector2(bar_start - 18.0, y + 12.0)
	var slot := Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side))
	if streak_icon != null:
		draw_texture_rect(streak_icon, slot.grow(1.5), false, Color(0.1, 0.05, 0.0, 0.6))
		draw_texture_rect(streak_icon, slot, false, tint)
	else:
		draw_circle(centre + Vector2(0.0, 2.0), side * 0.32, tint)
		draw_colored_polygon(PackedVector2Array([centre + Vector2(-side * 0.3, 2.0), centre + Vector2(0.0, -side * 0.5), centre + Vector2(side * 0.3, 2.0)]), tint)
	ink_text(Vector2(bar_start, y + 12.0), streak_text(), 15, tint, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 5)
	var track := Rect2(bar_start, y + 17.0, width, 7.0)
	_pill(track, Color(0.0, 0.0, 0.0, 0.55), Color(1, 1, 1, 0.14))
	_pill(Rect2(bar_start + 1.0, track.position.y + 1.0, (width - 2.0) * _shown_streak, 5.0), gold)


func describe() -> Dictionary:
	var out := super()
	out.merge({"health": health, "max": max_health, "armour": armour, "bonus": bonus, "status": status, "low": is_low(), "streak": streak, "streak_full": streak_full})
	return out
