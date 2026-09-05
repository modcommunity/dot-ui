@tool
class_name DotStarfield
extends RefCounted

## A drawn parallax starfield: a sky for a menu, or for a world.
##
## [b]dot-ui ships no art, and this is what that costs and what it buys.[/b] The addon's
## whole position is that a game should be able to look like something before it has an
## artist — the theme is built from [StyleBoxFlat]s, the crosshair is drawn, and so is
## this. A backdrop is where the absence of art shows first: a flat fill behind a menu is
## the clearest signal there is that a build is unfinished.
##
## Two calls, into any [CanvasItem]: [method draw_nebula] for the clouds and
## [method draw_into] for the stars. Both take the rectangle to cover and the position
## parallax is measured against, so one field serves a fixed menu backdrop and a world
## scrolling under a camera.
##
## [b]Generated, never stored.[/b] There is no star list and no node per star: a cell grid
## is walked over the visible rectangle and each cell hashes its own contents. Nothing is
## allocated, nothing is freed when the view moves, and a field that is arbitrarily large
## costs exactly what is on screen — the same reasoning a renderer uses to draw a thousand
## pellets rather than instance them, applied to a backdrop that is bigger still.
##
## [b]The hash is the memory.[/b] A star's position, size and twinkle all come out of one
## integer derived from its cell coordinates, so the same cell yields the same star every
## frame, from any direction, at any zoom, on any machine. Random numbers would give a sky
## that boils as the camera moves, which is much worse than no sky at all.
##
## [b]Parallax is what makes it read as distance.[/b] Each layer is sampled at an offset of
## the camera position, so the far layer slides a quarter as fast as the world and the near
## one most of the way. A single-depth field moving exactly with the arena reads as a
## texture stuck to the floor; three depths read as space. It is the cheapest depth cue
## there is and the only one available to a renderer with no art.

## The layers, far to near.
##
## `cell` is the world spacing between candidate stars, so a smaller cell is a denser
## layer; `parallax` is how much of the camera's movement the layer takes (0 pins it to the
## screen, 1 pins it to the world).
const LAYERS: Array[Dictionary] = [
	{"cell": 150.0, "size": 1.4, "alpha": 0.32, "parallax": 0.25, "salt": 11},
	{"cell": 250.0, "size": 1.8, "alpha": 0.50, "parallax": 0.50, "salt": 29},
	{"cell": 520.0, "size": 2.1, "alpha": 0.72, "parallax": 0.80, "salt": 47},
]

## Cells with no star in them, as one in N. Some empty sky is what stops a hashed field
## from reading as a lattice.
const EMPTY_ONE_IN := 4

## A star bright enough to earn a halo, as one in N of those drawn.
##
## [b]Keep the sky under the game.[/b] A field drawn over an arena is competing with the
## things in that arena for a player's attention, and it must lose: no star may be as large
## or as bright as the smallest thing worth eating, or a player learns to check the
## background and stops trusting either. The sizes above and this ratio are the whole of
## that discipline — raise them and a haloed star starts reading as a rare pickup.
const BRIGHT_ONE_IN := 37

## Nebula cell size. Large, because two or three clouds in view is atmosphere and eight is
## a fog bank.
const NEBULA_CELL := 1500.0

const NEBULA_PARALLAX := 0.12

## The two tints a cloud is picked between. Cool on one side, warm on the other, so the
## sky has some variation without ever becoming colourful enough to compete with the food.
const NEBULA_TINTS: Array[Color] = [
	Color(0.22, 0.36, 0.85),
	Color(0.52, 0.22, 0.72),
]

## Star tints, picked per star. Mostly white — a sky of coloured stars looks like confetti.
const STAR_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 1.0, 1.0),
	Color(0.80, 0.88, 1.0),
	Color(1.0, 0.92, 0.80),
]


## Draws every layer into [param canvas].
##
## [param view] is the rectangle to cover, in the canvas's own coordinates. [param anchor]
## is the camera position that parallax is measured against — pass [code]Vector2.ZERO[/code]
## for a fixed field, or a slowly growing vector to make one drift on its own.
## [param time] drives the twinkle and may be any monotonic clock.
static func draw_into(
	canvas: CanvasItem, view: Rect2, anchor: Vector2, time: float, opacity: float = 1.0
) -> void:
	if opacity <= 0.0:
		return

	for index in LAYERS.size():
		_draw_layer(canvas, view, anchor, time, opacity, LAYERS[index])


static func _draw_layer(
	canvas: CanvasItem,
	view: Rect2,
	anchor: Vector2,
	time: float,
	opacity: float,
	layer: Dictionary
) -> void:
	var cell := float(layer["cell"])
	var size := float(layer["size"])
	var alpha := float(layer["alpha"]) * opacity
	var salt := int(layer["salt"])

	# What the layer is offset BY, and therefore what is subtracted before sampling and
	# added back before drawing. A layer that takes only a quarter of the camera's
	# movement sits three quarters of it behind.
	var offset := anchor * (1.0 - float(layer["parallax"]))
	var sample := Rect2(view.position - offset, view.size)

	var from_x := int(floorf(sample.position.x / cell))
	var to_x := int(ceilf(sample.end.x / cell))
	var from_y := int(floorf(sample.position.y / cell))
	var to_y := int(ceilf(sample.end.y / cell))

	for cx in range(from_x, to_x + 1):
		for cy in range(from_y, to_y + 1):
			var h := _hash(cx, cy, salt)

			if h % EMPTY_ONE_IN == 0:
				continue

			var at := Vector2(
				(float(cx) + _unit(h, 1)) * cell,
				(float(cy) + _unit(h, 2)) * cell
			) + offset

			# Twinkle: a slow sine per star, out of phase with its neighbours. Never to
			# zero — a star that blinks out entirely reads as a dropped frame.
			var phase := _unit(h, 3)
			var pulse := 0.68 + 0.32 * sin(time * (0.5 + phase * 1.4) + phase * TAU)

			var tint: Color = STAR_TINTS[h % STAR_TINTS.size()]
			var radius := size * (0.6 + _unit(h, 4) * 0.7)

			if h % BRIGHT_ONE_IN == 0:
				# A halo on the few bright ones, which is what keeps a field of even dots
				# from looking printed.
				canvas.draw_circle(
					at, radius * 4.0, Color(tint.r, tint.g, tint.b, alpha * pulse * 0.10)
				)
				canvas.draw_circle(
					at, radius * 1.9, Color(tint.r, tint.g, tint.b, alpha * pulse * 0.16)
				)

			canvas.draw_circle(at, radius, Color(tint.r, tint.g, tint.b, alpha * pulse))


## Draws the soft clouds the stars sit in front of.
##
## Called before [method draw_into] — it is a background for the background. Kept separate
## because the arena wants both and a menu backdrop that is mostly panel wants only the
## clouds behind its glow.
static func draw_nebula(
	canvas: CanvasItem, view: Rect2, anchor: Vector2, opacity: float = 1.0
) -> void:
	if opacity <= 0.0:
		return

	var offset := anchor * (1.0 - NEBULA_PARALLAX)
	var sample := Rect2(view.position - offset, view.size)

	var from_x := int(floorf(sample.position.x / NEBULA_CELL))
	var to_x := int(ceilf(sample.end.x / NEBULA_CELL))
	var from_y := int(floorf(sample.position.y / NEBULA_CELL))
	var to_y := int(ceilf(sample.end.y / NEBULA_CELL))

	for cx in range(from_x, to_x + 1):
		for cy in range(from_y, to_y + 1):
			var h := _hash(cx, cy, 97)

			# Most cells hold no cloud at all. Clouds everywhere is a haze, and a haze
			# over the whole arena is just a lighter background with a worse frame time.
			if h % 3 != 0:
				continue

			var at := Vector2(
				(float(cx) + _unit(h, 1)) * NEBULA_CELL,
				(float(cy) + _unit(h, 2)) * NEBULA_CELL
			) + offset

			var radius := NEBULA_CELL * (0.26 + _unit(h, 3) * 0.24)
			var tint: Color = NEBULA_TINTS[h % NEBULA_TINTS.size()]

			# Three rings rather than one disc: a flat circle at this size reads as a
			# planet. Falling off in steps is a cloud, at three draws each.
			canvas.draw_circle(at, radius, Color(tint.r, tint.g, tint.b, 0.028 * opacity))
			canvas.draw_circle(
				at, radius * 0.66, Color(tint.r, tint.g, tint.b, 0.036 * opacity)
			)
			canvas.draw_circle(
				at, radius * 0.34, Color(tint.r, tint.g, tint.b, 0.044 * opacity)
			)


## One integer per cell, and every property of the star comes out of it.
##
## Written out rather than taken from `hash()`, whose result is not promised to be stable
## across engine versions — and a sky that rearranges itself on an engine upgrade is a bug
## nobody would think to look for.
static func _hash(x: int, y: int, salt: int) -> int:
	var h := x * 374761393 + y * 668265263 + salt * 1442695041
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## A 0..1 float out of one of the hash's digit groups. [param slot] picks which, so several
## independent-looking values come out of a single hash.
static func _unit(h: int, slot: int) -> float:
	var shifted := h

	for _i in slot:
		shifted /= 1013

	return float(shifted % 1000) / 1000.0
