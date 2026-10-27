class_name DotIconSet
extends RefCounted

## Icons by id or type tag, drawn from sprite sheets, with per-profile overrides.

## A tag (`pistol`, `shotgun`) the stock sheet answers when an id has no icon of its own.
var _cells: Dictionary = {}
var _sheet: Texture2D
var _cell_size := Vector2i(48, 24)
var _by_id: Dictionary = {}
var _overrides: Dictionary = {}
var _cache: Dictionary = {}
var _flat_cache: Dictionary = {}

## Profile whose overrides win over the shared ones; empty is none.
var profile: StringName = &""
## Draw every icon as a flat silhouette in [member flat_colour] instead of the sheet's own pixels.
var flat := false
var flat_colour := Color.WHITE


## Uses [param sheet] cut into [param cell_size] cells; [method map] names cells by column and row.
func use_sheet(sheet: Texture2D, cell_size: Vector2i) -> DotIconSet:
	_sheet = sheet
	_cell_size = cell_size
	_cache.clear()
	_flat_cache.clear()
	return self


## [param key] (an id or a tag) is the sprite in cell [param cell] (column, row).
func map(key: StringName, cell: Vector2i) -> DotIconSet:
	_cells[key] = cell
	_cache.erase(key)
	_flat_cache.erase(key)
	return self


## Weapon [param id] is drawn as whatever [param key] draws (another id or a tag).
func alias(id: StringName, key: StringName) -> DotIconSet:
	_by_id[id] = key
	return self


## [param id]'s icon is [param source] (a Texture2D or a resource path), for [param for_profile] only when given.
func override(id: StringName, source: Variant, for_profile: StringName = &"") -> void:
	_overrides[[for_profile, id]] = source
	_flat_cache.erase(id)


## Overrides from a document: `{id: path}` shared, or `{profile: {id: path}}` when a value is a Dictionary.
func load_overrides(doc: Dictionary) -> void:
	for key in doc:
		var value: Variant = doc[key]
		if value is Dictionary:
			for id in value:
				override(StringName(str(id)), value[id], StringName(str(key)))
		else:
			override(StringName(str(key)), value)


func has_icon(id: StringName, tag: StringName = &"") -> bool:
	return texture_for(id, tag) != null


## The icon for [param id], else for [param tag], else null (draw the name).
func texture_for(id: StringName, tag: StringName = &"") -> Texture2D:
	var tex := _resolve(id, tag)
	if tex == null or not flat:
		return tex
	return _flat_of(id, tag, tex, flat_colour)


## The icon as one flat colour whatever [member flat] says: a halo or shadow to draw behind the sprite.
func silhouette_for(id: StringName, tag: StringName, colour: Color) -> Texture2D:
	var tex := _resolve(id, tag)
	return _flat_of(id, tag, tex, colour) if tex != null else null


func _flat_of(id: StringName, tag: StringName, tex: Texture2D, colour: Color) -> Texture2D:
	var cache_key := [id, tag, colour, profile]
	if not _flat_cache.has(cache_key):
		_flat_cache[cache_key] = _silhouette(tex, colour)
	return _flat_cache[cache_key]


## Pixel art blurs under the default filter; call this on whatever draws these icons.
static func pixel_perfect(canvas: CanvasItem) -> void:
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func describe() -> String:
	return "DotIconSet(%d sprites, %d aliases, %d overrides, profile=%s, flat=%s)" % [
		_cells.size(), _by_id.size(), _overrides.size(), profile, flat]


func _resolve(id: StringName, tag: StringName) -> Texture2D:
	for scope in [profile, &""]:
		if _overrides.has([scope, id]):
			var tex := _load(_overrides[[scope, id]])
			if tex != null:
				return tex
	var key := _by_id.get(id, id) as StringName
	if _cells.has(key):
		return _sprite(key)
	if tag != &"" and _cells.has(tag):
		return _sprite(tag)
	return null


func _load(source: Variant) -> Texture2D:
	if source is Texture2D:
		return source
	var path := str(source)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The cell trimmed to its opaque pixels, so a small sprite is not drawn small by its empty margin.
func _sprite(key: StringName) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var out: Texture2D = null
	if _sheet != null:
		var cell: Vector2i = _cells[key]
		var rect := Rect2i(cell * _cell_size, _cell_size)
		var image := _sheet.get_image()
		if image != null:
			var used := image.get_region(rect).get_used_rect()
			if used.size.x > 0:
				rect = Rect2i(rect.position + used.position, used.size)
		var atlas := AtlasTexture.new()
		atlas.atlas = _sheet
		atlas.region = Rect2(rect)
		out = atlas
	_cache[key] = out
	return out


func _silhouette(tex: Texture2D, colour: Color) -> Texture2D:
	var image := tex.get_image()
	if image == null:
		return tex
	image.convert(Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var a := image.get_pixel(x, y).a
			image.set_pixel(x, y, Color(colour, a * colour.a))
	return ImageTexture.create_from_image(image)
