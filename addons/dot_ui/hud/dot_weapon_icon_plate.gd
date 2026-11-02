@tool
class_name DotWeaponIconPlate
extends DotHudPiece

## The carried weapon's sprite on a plate, kept to its aspect and right-aligned to this
## control's right edge, so it sits beside a [DotAmmoCounter] on the same baseline. A weapon
## with no sprite draws nothing: the counter still names it.

## The sprite's height; its width follows the aspect up to [member max_width].
@export var icon_height: float = 56.0
@export var max_width: float = 150.0
@export var padding: float = 8.0
## A dark offset copy under the sprite, so a white gun reads on a white wall.
@export var shadow: bool = true
## Draw the sprite through mipmaps; a 128 px icon drawn at 56 shimmers without them.
@export var smooth: bool = true
## Draw the plate under the sprite.
@export var show_plate: bool = true

var texture: Texture2D = null
var weapon_id: StringName = &""


func _ready() -> void:
	_apply_filter()


## [param p_texture] null, or an id with no sprite, takes the plate down.
func show_icon(p_texture: Texture2D, p_id: StringName = &"") -> void:
	if p_texture != texture or p_id != weapon_id:
		texture = p_texture
		weapon_id = p_id
		queue_redraw()


func clear() -> void:
	show_icon(null)


## The sprite's size as drawn.
func icon_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	var s := texture.get_size()
	var w := minf(s.x * icon_height / maxf(s.y, 1.0), max_width)
	return Vector2(w, w * s.y / maxf(s.x, 1.0))


func footprint() -> Rect2:
	if texture == null:
		return Rect2()
	var s := icon_size() + Vector2(padding, padding) * 2.0
	return Rect2(size.x - s.x, (size.y - s.y) * 0.5, s.x, s.y)


func _apply_filter() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if smooth else CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if texture == null:
		return
	_apply_filter()
	var box := footprint()
	if show_plate:
		ink_plate(box, Color(0, 0, 0, -1), 9)
	var at := box.position + Vector2(padding, padding)
	var s := icon_size()
	if shadow:
		draw_texture_rect(texture, Rect2(at + Vector2(1.5, 1.5), s), false, Color(0, 0, 0, 0.55))
	draw_texture_rect(texture, Rect2(at, s), false, Color.WHITE)


func describe() -> Dictionary:
	var out := super()
	out.merge({"weapon": weapon_id, "icon_size": icon_size()})
	return out
