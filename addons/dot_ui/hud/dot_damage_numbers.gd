@tool
class_name DotDamageNumbers
extends DotHudPiece

## Damage numbers: each rises off the point a hit landed and fades. A world point is
## projected through the camera every frame, so the number stays on the body while the view
## moves; a 2D game hands a point in this control's space instead ([method add_at]).
##
## Hits on one victim within [member merge_sec] add up into one number, the way a burst
## reads as one hit. A headshot's number is larger and in the theme's `highlight` colour.
## A small deterministic sideways scatter keeps two numbers on one body from stacking.
##
## Placed full-rect over the HUD.

@export_range(0.1, 5.0, 0.05) var life_sec: float = 0.9
@export_range(0.0, 2.0, 0.05) var merge_sec: float = 0.35
@export var rise_px: float = 70.0
@export var font_size: int = 24
@export var headshot_size: int = 30

## The camera world points are projected through; null uses the viewport's current one.
var camera: Camera3D = null

## `{victim, amount, point, at, headshot, age, drift}` per number on screen.
var entries: Array[Dictionary] = []
var _seed: int = 0


func _init() -> void:
	super()
	cover_mode = CoverMode.IGNORE


## A hit of [param amount] on [param victim] at the world point [param point].
func add(victim: int, amount: float, point: Vector3, headshot: bool = false) -> void:
	_add(victim, amount, point, Vector2(NAN, NAN), headshot)


## The same at [param at], in this control's space: for a 2D game, or a host that projects
## itself.
func add_at(victim: int, amount: float, at: Vector2, headshot: bool = false) -> void:
	_add(victim, amount, Vector3.ZERO, at, headshot)


func _add(victim: int, amount: float, point: Vector3, at: Vector2, headshot: bool) -> void:
	for e in entries:
		if int(e["victim"]) == victim and float(e["age"]) < merge_sec:
			e["amount"] = float(e["amount"]) + amount
			e["headshot"] = bool(e["headshot"]) or headshot
			e["age"] = 0.0
			queue_redraw()
			return
	_seed += 1
	var drift := float((_seed * 37) % 7 - 3) * 9.0
	entries.append({
		"victim": victim, "amount": amount, "point": point, "at": at,
		"headshot": headshot, "age": 0.0, "drift": drift,
	})
	queue_redraw()


## The numbers on screen as words, oldest first: what a suite reads.
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		out.append(str(int(roundf(float(e["amount"])))))
	return out


func clear() -> void:
	entries.clear()
	queue_redraw()


func _process(delta: float) -> void:
	super(delta)
	if Engine.is_editor_hint():
		return
	advance(delta)


func advance(delta: float) -> void:
	if entries.is_empty():
		return
	for i in range(entries.size() - 1, -1, -1):
		entries[i]["age"] = float(entries[i]["age"]) + delta
		if float(entries[i]["age"]) >= life_sec:
			entries.remove_at(i)
	queue_redraw()


## Where an entry is drawn this frame, in this control's space; NAN when it is behind the
## camera or there is no camera.
func _where(e: Dictionary) -> Vector2:
	var at: Vector2 = e["at"]
	if not is_nan(at.x):
		return at
	var cam := camera
	if cam == null and is_inside_tree():
		cam = get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return Vector2(NAN, NAN)
	var point: Vector3 = e["point"]
	if cam.is_position_behind(point):
		return Vector2(NAN, NAN)
	return get_global_transform().affine_inverse() * cam.unproject_position(point)


func footprint() -> Rect2:
	var out := Rect2()
	for e in entries:
		var at := _where(e)
		if is_nan(at.x):
			continue
		var one := Rect2(at + Vector2(float(e["drift"]) - 40.0, -rise_px - 34.0), Vector2(80.0, rise_px + 40.0))
		out = one if not out.has_area() else out.merge(one)
	return out


func _draw() -> void:
	for e in entries:
		var base := _where(e)
		if is_nan(base.x):
			continue
		var t := float(e["age"]) / life_sec
		var head := bool(e["headshot"])
		var at := base + Vector2(float(e["drift"]), -rise_px * (1.0 - pow(1.0 - t, 2.0)))
		var pop := 1.0 + 0.6 * maxf(0.0, 1.0 - float(e["age"]) / 0.1)
		var size_now := int(round(float(headshot_size if head else font_size) * pop))
		var tint := colour(&"highlight") if head else colour(&"text")
		tint.a = clampf((1.0 - t) / 0.4, 0.0, 1.0)
		ink_text(at + Vector2(-60.0, 0.0), str(int(roundf(float(e["amount"])))), size_now, tint,
			HORIZONTAL_ALIGNMENT_CENTER, 120.0, 7, true)


func describe() -> Dictionary:
	var out := super()
	out.merge({"numbers": texts()})
	return out
