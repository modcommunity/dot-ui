class_name DotHudElementCvars
extends RefCounted

## The player's per-element HUD switches as client cvars: `cl_hud_show_<element>` (0 or 1) and
## `cl_hud_scale`. Archived, never replicated. First slice of the shared HUD redesign.
##
## A game attaches the controls it has under the stock element ids ([constant ELEMENTS]) with
## [method attach], binds a console with [method bind_console], and the cvars show and hide
## them. An element the game never attaches costs nothing; its cvar still registers so a
## config file written for one game loads in another. The perf panel is [code]perf[/code],
## off by default; every other element is on.

signal changed

## id: [default, description]. Ids are the HUD vocabulary every game shares.
const ELEMENTS := {
	&"vitals": [1, "Health, downs and the bottom-left prompts"],
	&"weapons": [1, "Weapon list and carry weight"],
	&"ammo": [1, "Ammo counter"],
	&"fire_mode": [1, "Fire-mode indicator"],
	&"flashlight": [1, "Flashlight key and state"],
	&"teammates": [1, "Teammates' health and downed state"],
	&"wave": [1, "Wave progress and breather timer"],
	&"objective": [1, "Objective text"],
	&"prompts": [1, "Interaction prompts"],
	&"damage_dir": [1, "Damage direction indicators"],
	&"hit_markers": [1, "Hit markers and damage numbers"],
	&"perf": [0, "Frame graph and network panel"],
}

const SCALE := "cl_hud_scale"
const SCALE_MIN := 0.5
const SCALE_MAX := 2.0

var visible_by_id: Dictionary = {}
var scale: float = 1.0

## The HUD whose [member DotHud.user_scale] the scale cvar drives; optional.
var hud: DotHud = null

var _nodes: Dictionary = {}


func _init() -> void:
	for id: StringName in ELEMENTS:
		visible_by_id[id] = int((ELEMENTS[id] as Array)[0]) != 0


static func cvar_name(id: StringName) -> String:
	return "cl_hud_show_" + String(id)


func is_shown(id: StringName) -> bool:
	return bool(visible_by_id.get(id, true))


## Puts [param control] under element [param id]; its visibility follows the cvar from now on.
## False for an id that is not in [constant ELEMENTS].
func attach(id: StringName, control: CanvasItem) -> bool:
	if not ELEMENTS.has(id) or control == null:
		return false
	if not _nodes.has(id):
		_nodes[id] = []
	(_nodes[id] as Array).append(control)
	control.visible = is_shown(id)
	return true


## Applies one cvar by name; false for another name or an unreadable value.
func set_cvar(cvar: String, value: String) -> bool:
	var text := value.strip_edges()
	if not text.is_valid_float():
		return false
	if cvar == SCALE:
		scale = clampf(text.to_float(), SCALE_MIN, SCALE_MAX)
		changed.emit()
		return true
	for id: StringName in ELEMENTS:
		if cvar_name(id) == cvar:
			visible_by_id[id] = text.to_float() > 0.5
			changed.emit()
			return true
	return false


## Registers every cvar on a console's local source (`add_var(name, help, getter, setter)`).
func bind_console(local: Object) -> bool:
	if local == null or not local.has_method(&"add_var"):
		return false
	for id: StringName in ELEMENTS:
		var name := cvar_name(id)
		local.call(&"add_var", StringName(name), String((ELEMENTS[id] as Array)[1]) + " (0 hides, 1 shows)",
			func() -> Variant: return "1" if is_shown(id) else "0",
			func(v: Variant) -> Variant: return _set_and_apply(name, str(v)))
	local.call(&"add_var", StringName(SCALE), "HUD size, 0.5 to 2 (1 is the design)",
		func() -> Variant: return str(scale),
		func(v: Variant) -> Variant: return _set_and_apply(SCALE, str(v)))
	return true


func _set_and_apply(cvar: String, value: String) -> Variant:
	if not set_cvar(cvar, value):
		return DotResult.fail(DotError.CODE_INVALID, "unreadable value: " + value)
	apply()
	return null


## Copies the cvars onto the attached controls and the HUD scale.
func apply() -> void:
	for id: StringName in _nodes:
		for node: Variant in _nodes[id]:
			if is_instance_valid(node):
				(node as CanvasItem).visible = is_shown(id)
	if hud != null and is_instance_valid(hud):
		hud.user_scale = scale
