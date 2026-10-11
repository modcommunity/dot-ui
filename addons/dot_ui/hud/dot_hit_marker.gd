@tool
class_name DotHitMarker
extends DotHudPiece

## Four ticks round the middle of this control: white on a hit, warm on a headshot, larger
## and in the theme's `low` colour on a kill, with a short pop outward as it appears and a
## fade. Placed full-rect over the HUD, so the middle is the crosshair's.
##
## [b]Flash it only for a hit the server confirmed.[/b] A marker drawn from the local
## prediction says "hit" for shots the server then refused, and a player learns to
## distrust it in a minute; the host calls [method flash] from the confirmation.
##
## A later non-lethal hit does not turn a fresh kill marker white: a shotgun's pellets land
## after the lethal one in the same burst, and the kill is the news.

@export_range(0.05, 2.0, 0.01) var hit_sec: float = 0.28
@export_range(0.05, 2.0, 0.01) var kill_sec: float = 0.6
@export var hit_colour: Color = Color.WHITE
@export var headshot_colour: Color = Color(1.0, 0.9, 0.6)

var age: float = 99.0
var life: float = 0.28
var kill: bool = false
var headshot: bool = false


func _init() -> void:
	super()
	# The middle of the screen is never under a ballot's column, and this control's rect is
	# the whole HUD, which always is.
	cover_mode = CoverMode.IGNORE


## 1 when it has just flashed, 0 when it is gone.
func alpha() -> float:
	return clampf(1.0 - age / life, 0.0, 1.0)


func flash(p_kill: bool = false, p_headshot: bool = false) -> void:
	if kill and not p_kill and age < life * 0.5:
		return
	kill = p_kill
	headshot = p_headshot
	age = 0.0
	life = kill_sec if p_kill else hit_sec
	queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	advance(delta)


func advance(delta: float) -> void:
	if age > life:
		return
	age += delta
	queue_redraw()


func footprint() -> Rect2:
	if alpha() <= 0.0:
		return Rect2()
	var reach := 9.0 + 16.0 + 14.0
	return Rect2(size * 0.5 - Vector2(reach, reach), Vector2(reach, reach) * 2.0)


func _draw() -> void:
	var a := alpha()
	if a <= 0.0:
		return
	var c := size * 0.5
	var pop := 1.0 + 0.5 * maxf(0.0, 1.0 - age / 0.08)
	var gap := (9.0 if kill else 7.0) * pop
	var reach := gap + (16.0 if kill else 10.0) * pop
	var thick := 4.0 if kill else 2.5
	var tint := colour(&"low") if kill else (headshot_colour if headshot else hit_colour)
	for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var v: Vector2 = (d as Vector2).normalized()
		draw_line(c + v * (gap - 1.0), c + v * (reach + 1.0), Color(0.0, 0.0, 0.0, 0.55 * a), thick + 2.5, true)
		draw_line(c + v * gap, c + v * reach, Color(tint, a), thick, true)


func describe() -> Dictionary:
	var out := super()
	out.merge({"alpha": alpha(), "kill": kill, "headshot": headshot})
	return out
