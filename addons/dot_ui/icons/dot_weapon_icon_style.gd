class_name DotWeaponIconStyle
extends RefCounted

## A game's weapon pictures: the stock sprite sheet, the game's id-to-tag table, the player's overrides and the `cl_weapon_icons` cvars.
##
## [codeblock]
## var icons := DotWeaponIconStyle.new()
## icons.tags = {&"zz_ak": &"assault_rifle"}   # or subclass and set it in _init
## icons.bind_console(console_local_source)
## var tex := icons.texture(weapon_id)           # null: draw the name or the rendered model
## [/codeblock]

## `pixel` is the sprites as drawn, `flat` one colour, `silhouette` no sprite (the caller draws its rendered model).
const STYLES := [&"pixel", &"flat", &"silhouette"]

## Weapon id to the sprite sheet's type tag. A weapon not here keeps the rendered model or its name.
var tags: Dictionary = {}
var style: StringName = &"pixel"
## A game's own "draw the held weapon as a flat sprite" switch; the addon only stores it.
var sprites := false
## Where the player's overrides live (`{"id": path}` or per-profile nested documents).
var overrides_path := "user://weapon_icons.json"

var _set: DotIconSet = null
var _menu: Dictionary = {}


## The shared set: stock sheet, [member tags] as aliases, and the player's overrides.
func icon_set() -> DotIconSet:
	if _set == null:
		_set = DotWeaponIcons.stock()
		for id in tags:
			_set.alias(id, tags[id])
		if FileAccess.file_exists(overrides_path):
			var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(overrides_path))
			if doc is Dictionary:
				_set.load_overrides(doc)
	_set.flat = style == &"flat"
	_set.flat_colour = Color.WHITE
	return _set


## The sprite for [param id], or null. Always null under `silhouette`.
func texture(id: StringName) -> Texture2D:
	if style == &"silhouette" or id == &"":
		return null
	return icon_set().texture_for(id)


func set_style(value: StringName) -> bool:
	if not STYLES.has(value):
		return false
	style = value
	return true


## Selects the overrides profile (`overrides_path`'s nested keys).
func set_profile(value: StringName) -> void:
	icon_set().profile = value


## Nearest filtering for pixel art; [param sprite] false (a rendered model) keeps it smooth.
func filter(canvas: CanvasItem, sprite := true) -> void:
	var want := CanvasItem.TEXTURE_FILTER_NEAREST if sprite and style != &"silhouette" else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	if canvas.texture_filter != want:
		canvas.texture_filter = want


## A pale one-pixel halo behind a sprite so its dark outline reads on dark plates; pixel style only.
func halo(canvas: CanvasItem, id: StringName, at: Vector2, height: float, alpha: float, max_width: float) -> void:
	if style != &"pixel":
		return
	var tex := icon_set().silhouette_for(id, &"", Color(1, 1, 1, 0.9))
	if tex == null:
		return
	var s := tex.get_size()
	var w := minf(s.x * height / maxf(s.y, 1.0), max_width)
	var h := w * s.y / maxf(s.x, 1.0)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		canvas.draw_texture_rect(tex, Rect2(at.x + d.x, at.y - h * 0.5 + d.y, w, h), false, Color(1, 1, 1, 0.55 * alpha))


## A card picture: the sprite with a halo, enlarged four times unfiltered because a TextureRect filters linearly.
func menu_texture(id: StringName) -> Texture2D:
	var tex := texture(id)
	if tex == null:
		return null
	var key := [id, style, icon_set().profile]
	if _menu.has(key):
		return _menu[key]
	var src := tex.get_image()
	if src == null:
		return tex
	src.convert(Image.FORMAT_RGBA8)
	var out := Image.create(src.get_width() + 2, src.get_height() + 2, false, Image.FORMAT_RGBA8)
	if style == &"pixel":
		for y in src.get_height():
			for x in src.get_width():
				if src.get_pixel(x, y).a > 0.0:
					for d: Vector2i in [Vector2i(0, 1), Vector2i(2, 1), Vector2i(1, 0), Vector2i(1, 2)]:
						out.set_pixel(x + d.x, y + d.y, Color(1, 1, 1, 0.6))
	out.blend_rect(src, Rect2i(Vector2i.ZERO, src.get_size()), Vector2i(1, 1))
	out.resize(out.get_width() * 4, out.get_height() * 4, Image.INTERPOLATE_NEAREST)
	var made := ImageTexture.create_from_image(out)
	_menu[key] = made
	return made


## Registers `cl_weapon_icons` and `cl_weapon_icon_profile` on a console's local source (`add_var`). False when it cannot.
func bind_console(local: Object) -> bool:
	if local == null or not local.has_method(&"add_var"):
		return false
	local.call(&"add_var", &"cl_weapon_icons", "Weapon pictures: pixel (the sprites), flat (one colour) or silhouette (the rendered model).",
		func() -> Variant: return String(style),
		func(v: Variant) -> Variant:
			if not set_style(StringName(str(v).strip_edges())):
				return DotResult.fail(DotError.CODE_INVALID, "cl_weapon_icons is pixel, flat or silhouette")
			return DotResult.success(String(style)))
	local.call(&"add_var", &"cl_weapon_icon_profile", "Icon override profile from the overrides file; empty for the shared overrides.",
		func() -> Variant: return String(icon_set().profile),
		func(v: Variant) -> Variant:
			set_profile(StringName(str(v).strip_edges()))
			return DotResult.success(str(v)))
	return true
