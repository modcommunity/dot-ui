extends Control

## A weapon profile in a DotUiForm. T switches light and dark, Ctrl+F searches.
##
## With "-- --shots=dark,light,search,collapsed,reorder,keypad" it renders those frames into docs/ and quits.

const OUT_DIR := "res://docs"

var form: DotUiForm = null
var _light := false


static func weapon_schema() -> Array:
	var F := DotProfileSet.field
	return [
		F.call("name", "string", "Service Pistol", {"group": "General", "required": true, "description": "Shown in the loadout and the kill feed.", "max_length": 32}),
		F.call("rarity", "string", "common", {"group": "General", "enum": ["common", "uncommon", "rare", "epic"], "description": "Tints the card in the shop."}),
		F.call("tint", "color", "#4f9dff", {"group": "General", "description": "Muzzle flash and tracer colour."}),
		F.call("tags", "list", ["sidearm", "starter"], {"group": "General", "description": "Used by loadout rules."}),
		F.call("automatic", "bool", false, {"group": "Handling", "description": "Hold to keep firing."}),
		F.call("fire_rate", "float", 6.0, {"group": "Handling", "min": 0.5, "max": 20.0, "unit": "shots/s", "description": "Rounds leaving the barrel per second."}),
		F.call("spread", "float", 1.2, {"group": "Handling", "min": 0.0, "max": 10.0, "unit": "deg", "description": "Cone of fire when standing still."}),
		F.call("magazine", "int", 12, {"group": "Ammo", "min": 1, "max": 60, "unit": "rounds"}),
		F.call("reload_time", "float", 1.6, {"group": "Ammo", "min": 0.2, "max": 5.0, "unit": "s", "description": "Time from reload key to a full magazine."}),
		F.call("reserve", "int", 96, {"group": "Ammo", "min": 0, "max": 999, "unit": "rounds", "slider": false}),
		F.call("damage", "float", 24.0, {"group": "Damage", "min": 1.0, "max": 200.0, "unit": "hp", "description": "Per hit, before multipliers."}),
		F.call("headshot_multiplier", "float", 2.0, {"group": "Damage", "min": 1.0, "max": 5.0, "unit": "x"}),
		F.call("falloff_start", "float", 18.0, {"group": "Damage/Falloff", "min": 0.0, "max": 100.0, "unit": "m", "description": "Full damage up to here."}),
		F.call("falloff_end", "float", 60.0, {"group": "Damage/Falloff", "min": 0.0, "max": 200.0, "unit": "m"}),
		F.call("falloff_floor", "float", 0.35, {"group": "Damage/Falloff", "min": 0.0, "max": 1.0, "description": "Share of damage kept at the far end."}),
		F.call("pierces_armor", "bool", false, {"group": "Damage"}),
		F.call("price", "int", 450, {"group": "Shop", "min": 0, "max": 100000, "unit": "coins", "slider": false}),
		F.call("unlock_level", "int", 1, {"group": "Shop", "min": 1, "max": 50}),
		F.call("extra", "dict", {"sound": "pistol_a"}, {"group": "Advanced", "description": "Pack-specific keys, as JSON."}),
	]


func _ready() -> void:
	form = DotUiForm.new()
	form.title = "Service Pistol"
	form.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(form)
	form.tokens.animate = true
	var res := form.build(weapon_schema(), {"damage": 31.0, "fire_rate": 6.0, "price": 450})
	if not res.ok:
		push_error(res.error.message)
	form.applied.connect(func(ch: Dictionary) -> void: print("applied: ", ch))
	form.reverted.connect(func() -> void: print("reverted"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots.call_deferred(arg.trim_prefix("--shots=").split(","))


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		_set_light(not _light)


func _set_light(on: bool) -> void:
	_light = on
	var t := DotFormTokens.light() if on else DotFormTokens.dark()
	t.animate = form.tokens.animate
	form.set_tokens(t)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shots(names: PackedStringArray) -> void:
	form.tokens.animate = false
	await _frames(4)
	for n in names:
		await _stage(n)
		await _frames(8)
		var img := get_viewport().get_texture().get_image()
		if img.get_width() > 1000:
			img.resize(1000, int(img.get_height() * 1000.0 / img.get_width()), Image.INTERPOLATE_LANCZOS)
		img.save_png("%s/form_%s.png" % [OUT_DIR, n])
	get_tree().quit()


func _stage(n: String) -> void:
	_set_light(n.contains("light"))
	await _frames(4)
	form.set_filter("")
	for g in form.groups():
		g.set_open(true, false)
	form.set_value("damage", 48.0)
	form.set_value("automatic", true)
	form.set_value("rarity", "epic")
	form.set_value("tags", ["sidearm", "starter", "night"])
	form.row("name").type_text("")
	form.row("magazine").type_text("200")
	if n.contains("keypad"):
		form.row("name").type_text("Service Pisto")
		form.row("magazine").type_text("12")
		form.set_value("tags", ["sidearm", "night", "starter"])
		var pad := form.open_keypad(form.row("name").editor())
		if n.contains("light"):
			pad.set_shifted(true)
		await _frames(4)
		return
	if n.contains("reorder"):
		form.row("tags").move_item(2, 1, "down")
		await _frames(2)
		form.focus_key("tags")
		(form.row("tags")._item_rows()[1].get_child(2) as Control).grab_focus()
		return
	if n.contains("search"):
		form.set_filter("damage")
	elif n.contains("collapsed"):
		form.groups()[0].set_open(false, false)
		form.groups()[1].set_open(false, false)
	form.focus_key("fire_rate" if n.contains("phone") else "damage" if n.contains("collapsed") else "reserve")
