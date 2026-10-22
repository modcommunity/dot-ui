class_name DotFormSchema
extends RefCounted

## Turns a profile schema (as [method DotProfileSet.field] builds it) into form fields and checks values against them.

const TYPES: Array[String] = ["int", "float", "string", "bool", "list", "dict", "any", "color"]

## Slider only when both ends are known and the span is not enormous.
const SLIDER_MAX_SPAN := 100000.0


## Fills defaults (label, group, step, slider) and rejects a schema the form could not show.
static func normalize(schema: Array) -> DotResult:
	var out: Array[Dictionary] = []
	var seen := {}
	for raw in schema:
		if not raw is Dictionary:
			return DotResult.fail(DotError.CODE_INVALID, "A schema entry must be a Dictionary.")
		var d: Dictionary = (raw as Dictionary).duplicate(true)
		var key := str(d.get("name", ""))
		if key == "":
			return DotResult.fail(DotError.CODE_INVALID, "A schema entry has no name.")
		if seen.has(key):
			return DotResult.fail(DotError.CODE_INVALID, "Duplicate field '%s'." % key)
		var type := str(d.get("type", "any"))
		if not TYPES.has(type):
			return DotResult.fail(DotError.CODE_INVALID, "Field '%s' has unknown type '%s'." % [key, type])
		seen[key] = true
		d["name"] = key
		d["type"] = type
		d["label"] = str(d.get("label", prettify(key)))
		d["group"] = str(d.get("group", ""))
		d["description"] = str(d.get("description", ""))
		d["unit"] = str(d.get("unit", ""))
		if not d.has("default"):
			d["default"] = default_for(type)
		d["slider"] = bool(d.get("slider", true)) and is_ranged(d)
		if not d.has("step"):
			d["step"] = 1.0 if type == "int" else _auto_step(d)
		out.append(d)
	return DotResult.success(out)


static func prettify(key: String) -> String:
	var words := key.replace("/", " ").replace(".", " ").replace("_", " ").strip_edges()
	return words.substr(0, 1).to_upper() + words.substr(1)


static func default_for(type: String) -> Variant:
	match type:
		"int":
			return 0
		"float":
			return 0.0
		"bool":
			return false
		"string":
			return ""
		"list":
			return []
		"dict":
			return {}
		"color":
			return "#ffffff"
	return null


static func is_numeric(d: Dictionary) -> bool:
	return d["type"] == "int" or d["type"] == "float"


static func is_ranged(d: Dictionary) -> bool:
	if not is_numeric(d) or not d.has("min") or not d.has("max"):
		return false
	return float(d["max"]) - float(d["min"]) <= SLIDER_MAX_SPAN and float(d["max"]) > float(d["min"])


static func _auto_step(d: Dictionary) -> float:
	if not d.has("min") or not d.has("max"):
		return 0.1
	var span := float(d["max"]) - float(d["min"])
	if span <= 2.0:
		return 0.01
	if span <= 20.0:
		return 0.1
	if span <= 200.0:
		return 0.5
	return 1.0


static func fmt(n: float) -> String:
	if is_equal_approx(n, round(n)):
		return str(int(round(n)))
	return String.num(n, 3)


## Checks [param value] against the field; success carries the value coerced to the field's type.
static func validate(d: Dictionary, value: Variant) -> DotResult:
	var type: String = d["type"]
	var v: Variant = value
	match type:
		"int", "float":
			if not (value is int or value is float):
				return _bad("Enter a number.")
			var n := float(value)
			if type == "int" and not is_equal_approx(n, round(n)):
				return _bad("Enter a whole number.")
			if d.has("min") and n < float(d["min"]) - 0.0000001:
				return _bad("Must be at least %s." % fmt(float(d["min"])))
			if d.has("max") and n > float(d["max"]) + 0.0000001:
				return _bad("Must be at most %s." % fmt(float(d["max"])))
			v = int(round(n)) if type == "int" else n
		"bool":
			if not value is bool:
				return _bad("Must be on or off.")
		"string":
			if not (value is String or value is StringName):
				return _bad("Enter text.")
			v = str(value)
			if d.has("enum") and not (d["enum"] as Array).has(v):
				return _bad("Pick one of the listed options.")
			if bool(d.get("required", false)) and (v as String).strip_edges() == "":
				return _bad("Required.")
			if d.has("max_length") and (v as String).length() > int(d["max_length"]):
				return _bad("At most %d characters." % int(d["max_length"]))
		"color":
			if value is Color:
				v = value
			elif value is String and Color.html_is_valid(value):
				v = value
			else:
				return _bad("Use a colour like #ff8800.")
		"list":
			if not value is Array:
				return _bad("Must be a list.")
			var item_type := str(d.get("items", "string"))
			var items := []
			for i in (value as Array).size():
				var sub := validate({"type": item_type}, (value as Array)[i])
				if not sub.ok:
					return _bad("Item %d: %s" % [i + 1, sub.error.message])
				items.append(sub.value)
			if d.has("max") and items.size() > int(d["max"]):
				return _bad("At most %d items." % int(d["max"]))
			v = items
		"dict":
			if not value is Dictionary:
				return _bad("Must be an object.")
	if d.has("validator") and d["validator"] is Callable:
		var verdict: Variant = (d["validator"] as Callable).call(v)
		if verdict is DotResult:
			if not (verdict as DotResult).ok:
				return _bad((verdict as DotResult).error.message)
		elif verdict is String and verdict != "":
			return _bad(verdict)
	return DotResult.success(v)


## Reads what a person typed into a number, JSON or list-item box.
static func parse_text(d: Dictionary, raw: String) -> DotResult:
	var t := raw.strip_edges()
	match d["type"]:
		"int":
			if not t.is_valid_int():
				return _bad("Enter a whole number.")
			return validate(d, t.to_int())
		"float":
			if not t.is_valid_float():
				return _bad("Enter a number.")
			return validate(d, t.to_float())
		"color":
			if not t.begins_with("#"):
				t = "#" + t
			return validate(d, t)
		"dict", "any":
			if t == "":
				return validate(d, default_for(d["type"]))
			var json := JSON.new()
			if json.parse(t) != OK:
				return _bad("Not valid JSON: " + json.get_error_message())
			return validate(d, json.data)
	return validate(d, raw)


## How a value reads in a text box.
static func display(d: Dictionary, value: Variant) -> String:
	if value == null:
		return ""
	match d["type"]:
		"int", "float":
			return fmt(float(value))
		"color":
			return ("#" + (value as Color).to_html(false)) if value is Color else str(value)
		"dict", "any":
			return JSON.stringify(value)
	return str(value)


static func _bad(message: String) -> DotResult:
	return DotResult.fail(DotError.CODE_INVALID, message)
