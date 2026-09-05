@tool
class_name DotCrosshair
extends DotHudWidget

## A crosshair that opens with the weapon's spread.
##
## Drawn rather than a texture, for the reason the whole of dot-ui is: shipping art
## imposes it. Four lines and a dot cover most of what a shooter wants, and a game with
## a designed crosshair replaces the node.
##
## [b]The gap is derived from the actual spread angle, not from a made-up number.[/b]
## A crosshair that opens by an arbitrary amount is worse than a fixed one: it tells
## the player something confident and wrong about where their shots will go.

@export_group("Shape")

## Half-length of each arm, in pixels.
@export_range(0.0, 100.0, 1.0) var length: float = 8.0

## Gap from the centre at zero spread.
@export_range(0.0, 100.0, 1.0) var base_gap: float = 4.0

@export_range(1.0, 12.0, 1.0) var thickness: float = 2.0

## Draw a dot in the middle.
@export var centre_dot: bool = true

@export_range(0.0, 10.0, 0.5) var dot_radius: float = 1.0

## Draw the top arm. Off is the T shape a lot of shooters use.
@export var top_arm: bool = true

@export_group("Colour")

@export var colour: Color = Color(1.0, 1.0, 1.0, 0.85)

## Used while [member hit_flash_sec] is running after [method flash_hit].
@export var hit_colour: Color = Color(1.0, 0.35, 0.3, 1.0)

@export_range(0.0, 2.0, 0.05) var hit_flash_sec: float = 0.15

@export var outline_colour: Color = Color(0.0, 0.0, 0.0, 0.6)

## Draw a dark outline behind the arms.
##
## Worth having: a white crosshair on a white wall is invisible, and every shipped
## shooter has solved it this way.
@export var outline: bool = true

@export_group("Spread")

## The camera's vertical field of view, in degrees. Needed to turn an angle into
## pixels; a crosshair that assumes 90 is wrong at every other setting.
@export_range(10.0, 170.0, 1.0) var fov_degrees: float = 75.0

## Most pixels the gap may open to, whatever the spread says.
@export_range(0.0, 500.0, 1.0) var max_gap: float = 90.0

## Hide the crosshair entirely. What aiming down a scope does.
##
## Not `visible`: the crosshair is a [DotHudWidget] and keeps refreshing its spread
## while scoped, so a game reading `gap_pixels()` for a scope reticle still gets an
## answer. (`hidden` is taken — [Control] already has one.)
@export var suppressed: bool = false

var _spread_degrees: float = 0.0
var _hit_until_ms: int = 0


func _ready() -> void:
	super._ready()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called with the current spread in degrees, from `DotWeaponState.spread_degrees()`.
##
## The widget's [member DotHudWidget.source] returns it, so a game binds one callable
## and nothing else.
func _on_value(current: Variant) -> void:
	_spread_degrees = float(current) if typeof(current) != TYPE_NIL else 0.0
	queue_redraw()


## Flashes the crosshair. What a confirmed hit does.
func flash_hit() -> void:
	_hit_until_ms = Time.get_ticks_msec() + int(hit_flash_sec * 1000.0)
	queue_redraw()


func _process(delta: float) -> void:
	super._process(delta)

	if _hit_until_ms > 0 and Time.get_ticks_msec() >= _hit_until_ms:
		_hit_until_ms = 0
		queue_redraw()


## Pixels from the centre the arms sit at, for the current spread.
##
## The projection a camera actually uses: half the viewport height divided by the
## tangent of half the field of view gives the focal length in pixels, and the spread
## angle through that is the radius the shots could land in.
func gap_pixels() -> float:
	if _spread_degrees <= 0.0:
		return base_gap

	var height := size.y

	if height <= 0.0:
		return base_gap

	var focal := (height * 0.5) / tan(deg_to_rad(fov_degrees) * 0.5)
	var radius := focal * tan(deg_to_rad(_spread_degrees))

	return minf(max_gap, base_gap + radius)


func _draw() -> void:
	if suppressed:
		return

	var centre := size * 0.5
	var gap := gap_pixels()
	var tint := hit_colour if _hit_until_ms > 0 else colour

	var arms: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]

	if top_arm:
		arms.append(Vector2.UP)

	if outline:
		for direction in arms:
			draw_line(
				centre + direction * gap,
				centre + direction * (gap + length),
				outline_colour,
				thickness + 2.0
			)

	for direction in arms:
		draw_line(
			centre + direction * gap,
			centre + direction * (gap + length),
			tint,
			thickness
		)

	if not centre_dot:
		return

	if outline:
		draw_circle(centre, dot_radius + 1.0, outline_colour)

	draw_circle(centre, dot_radius, tint)


func describe() -> Dictionary:
	var out := super.describe()
	out["spread"] = _spread_degrees
	out["gap"] = gap_pixels()
	out["suppressed"] = suppressed
	return out
