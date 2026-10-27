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

## Open the gap with the spread. Off keeps it at [member base_gap].
@export var dynamic: bool = true

@export_group("Aiming")

## Aim fraction (0 at the hip, 1 fully aimed) at which the crosshair has faded out entirely.
## Halfway up by default: the sight is what the player looks through by then, and a crosshair
## over an iron sight is two aiming marks that disagree (Christian's first play test).
@export_range(0.05, 1.0, 0.05) var aim_hide_by: float = 0.5

## Seconds the fade takes to follow a jump in the aim fraction (a weapon switch drops it to 0 at
## once): a fade, never a snap, both ways.
@export_range(0.0, 1.0, 0.01) var aim_fade_sec: float = 0.08

## `func() -> float`: the weapon's aim fraction, read every frame (a view model's
## `aim_fraction`). Unset is never aimed, unless [method set_aim] is called.
var aim_source: Callable = Callable()

## How much of the crosshair is drawn now, 0..1, after the fade.
var aim_opacity: float = 1.0

var _aim: float = 0.0
var _spread_degrees: float = 0.0
var _hit_until_ms: int = 0


func _ready() -> void:
	super._ready()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Called with the current spread in degrees, from `DotWeaponBallistics.spread_for()`.
##
## The widget's [member DotHudWidget.source] returns it, so a game binds one callable
## and nothing else.
func _on_value(current: Variant) -> void:
	_spread_degrees = float(current) if typeof(current) != TYPE_NIL else 0.0
	queue_redraw()


## Sets the spread in degrees directly, for a game with no widget source bound.
func set_spread(degrees: float) -> void:
	_on_value(degrees)


## Flashes the crosshair. What a confirmed hit does.
func flash_hit() -> void:
	_hit_until_ms = Time.get_ticks_msec() + int(hit_flash_sec * 1000.0)
	queue_redraw()


## Pushes the aim fraction, for a game that has no callable to hand over.
func set_aim(fraction: float) -> void:
	_aim = clampf(fraction, 0.0, 1.0) if is_finite(fraction) else 0.0


## How much crosshair an aim fraction leaves: 1 at the hip, 0 from [param hide_by] up, eased.
## Static so a game drawing its own dot can fade it the same way.
static func opacity_for_aim(fraction: float, hide_by: float = 0.5) -> float:
	if not is_finite(fraction):
		return 1.0
	return 1.0 - smoothstep(0.0, maxf(hide_by, 0.001), clampf(fraction, 0.0, 1.0))


## Moves [member aim_opacity] toward what the aim says, over [member aim_fade_sec]. Public so a
## suite can step it without a frame.
func follow_aim(delta: float) -> void:
	if aim_source.is_valid():
		var v: Variant = aim_source.call()
		set_aim(float(v) if (v is float or v is int) else 0.0)
	var target := opacity_for_aim(_aim, aim_hide_by)
	var was := aim_opacity
	if aim_fade_sec <= 0.0:
		aim_opacity = target
	else:
		aim_opacity = move_toward(aim_opacity, target, delta / aim_fade_sec)
	if not is_equal_approx(was, aim_opacity):
		queue_redraw()


func _process(delta: float) -> void:
	super._process(delta)
	follow_aim(delta)

	if _hit_until_ms > 0 and Time.get_ticks_msec() >= _hit_until_ms:
		_hit_until_ms = 0
		queue_redraw()


## Pixels from the centre the arms sit at, for the current spread.
##
## The projection a camera actually uses: half the viewport height divided by the
## tangent of half the field of view gives the focal length in pixels, and the spread
## angle through that is the radius the shots could land in.
func gap_pixels() -> float:
	if _spread_degrees <= 0.0 or not dynamic:
		return base_gap

	var height := size.y

	if height <= 0.0:
		return base_gap

	var focal := (height * 0.5) / tan(deg_to_rad(fov_degrees) * 0.5)
	var radius := focal * tan(deg_to_rad(_spread_degrees))

	return minf(max_gap, base_gap + radius)


func _draw() -> void:
	if suppressed or aim_opacity <= 0.01:
		return

	var centre := size * 0.5
	var gap := gap_pixels()
	var tint := hit_colour if _hit_until_ms > 0 else colour
	tint.a *= aim_opacity
	var edge := Color(outline_colour, outline_colour.a * aim_opacity)

	var arms: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]

	if top_arm:
		arms.append(Vector2.UP)

	if outline:
		for direction in arms:
			draw_line(
				centre + direction * gap,
				centre + direction * (gap + length),
				edge,
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
		draw_circle(centre, dot_radius + 1.0, edge)

	draw_circle(centre, dot_radius, tint)


func describe() -> Dictionary:
	var out := super.describe()
	out["spread"] = _spread_degrees
	out["gap"] = gap_pixels()
	out["suppressed"] = suppressed
	out["aim"] = _aim
	out["aim_opacity"] = aim_opacity
	return out
