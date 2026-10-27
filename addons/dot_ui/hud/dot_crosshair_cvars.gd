class_name DotCrosshairCvars
extends RefCounted

## The player's own crosshair as client cvars (`cl_crosshair_*`, archived, never replicated).
##
## [codeblock]
## var cvars := DotCrosshairCvars.new()
## cvars.target = crosshair
## cvars.bind_console(console_local_source)
## cvars.apply_to(crosshair)
## [/codeblock]

signal changed

## property: [default, min, max, description]
const FIELDS := {
	&"show": [1.0, 0.0, 1.0, "1 draws the weapon crosshair"],
	&"style": [0.0, 0.0, 2.0, "0 cross, 1 T (no top arm), 2 dot only"],
	&"size": [8.0, 0.0, 100.0, "Arm length in pixels"],
	&"gap": [4.0, 0.0, 100.0, "Gap at zero spread in pixels"],
	&"thickness": [2.0, 1.0, 12.0, "Arm thickness in pixels"],
	&"dot": [1.0, 0.0, 1.0, "1 draws a centre dot"],
	&"outline": [1.0, 0.0, 1.0, "1 draws a dark outline"],
	&"dynamic": [1.0, 0.0, 1.0, "1 opens the gap with the weapon's spread"],
}

const COLOUR := "cl_crosshair_colour"

var values: Dictionary = {}
var colour: Color = Color(1.0, 1.0, 1.0, 0.85)


func _init() -> void:
	for property: StringName in FIELDS:
		values[property] = float((FIELDS[property] as Array)[0])


func cvar_name(property: StringName) -> String:
	return "cl_crosshair_" + String(property)


## Applies one cvar by name; false for another name or an unreadable value.
func set_cvar(cvar: String, value: String) -> bool:
	var text := value.strip_edges()
	if cvar == COLOUR:
		if not Color.html_is_valid(text):
			return false
		colour = Color.html(text)
		changed.emit()
		return true
	if not text.is_valid_float():
		return false
	for property: StringName in FIELDS:
		if cvar_name(property) == cvar:
			var spec: Array = FIELDS[property]
			values[property] = clampf(text.to_float(), float(spec[1]), float(spec[2]))
			changed.emit()
			return true
	return false


## Registers every cvar on a console's local source (`add_var(name, help, getter, setter)`).
## False when [param local] cannot. Each set re-applies to [member target].
func bind_console(local: Object) -> bool:
	if local == null or not local.has_method(&"add_var"):
		return false
	for property: StringName in FIELDS:
		var name := cvar_name(property)
		local.call(&"add_var", StringName(name), String((FIELDS[property] as Array)[3]),
			func() -> Variant: return _text(values[property]),
			func(v: Variant) -> Variant: return _set_and_apply(name, str(v)))
	local.call(&"add_var", StringName(COLOUR), "Crosshair colour as RRGGBB or RRGGBBAA",
		func() -> Variant: return colour.to_html(true),
		func(v: Variant) -> Variant: return _set_and_apply(COLOUR, str(v)))
	return true


## The crosshair the cvars drive; set by the HUD.
var target: DotCrosshair = null


func _set_and_apply(cvar: String, value: String) -> Variant:
	if not set_cvar(cvar, value):
		return "unreadable value: " + value
	if target != null and is_instance_valid(target):
		apply_to(target)
	return null


static func _text(number: float) -> String:
	return str(int(number)) if is_equal_approx(number, roundf(number)) else str(number)


## Copies the cvars onto [param crosshair].
func apply_to(crosshair: DotCrosshair) -> void:
	var style := int(values[&"style"])
	crosshair.visible = values[&"show"] > 0.5
	crosshair.length = 0.0 if style == 2 else float(values[&"size"])
	crosshair.top_arm = style == 0
	crosshair.base_gap = float(values[&"gap"])
	crosshair.thickness = float(values[&"thickness"])
	crosshair.centre_dot = values[&"dot"] > 0.5 or style == 2
	crosshair.outline = values[&"outline"] > 0.5
	crosshair.dynamic = values[&"dynamic"] > 0.5
	crosshair.colour = colour
	crosshair.queue_redraw()
