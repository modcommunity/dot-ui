@tool
class_name DotKeyPrompt
extends DotHudPiece

## What can be done right now, with the key drawn as a key: "Open door [E]", "Reload [R]",
## "Cancel slide [C]". Centred on this control's middle, on a plate; hidden while there is
## nothing to say.
##
## [b]The key is the player's[/b]: the host passes the bound key's name (dot-ui's
## [method DotInputBinding.to_text] or [method DotBindingsPanel.event_name]), never a letter
## written into the game, because a rebound key the prompt still calls "E" is worse than no
## prompt.

@export var font_size: int = 17

var words: String = ""
var key: String = ""


func show_prompt(p_words: String, p_key: String = "") -> void:
	if p_words != words or p_key != key:
		words = p_words
		key = p_key
		queue_redraw()
	visible = words != ""


func clear() -> void:
	show_prompt("", "")


## The prompt as words: what a suite reads.
func text() -> String:
	if words == "":
		return ""
	return "%s  %s" % [words, key] if key != "" else words


func _total() -> float:
	var cap_w := keycap_width(key, font_size - 4) + 10.0 if key != "" else 0.0
	return text_width(words, font_size) + cap_w


func footprint() -> Rect2:
	if words == "":
		return Rect2()
	var total := _total()
	return Rect2(size.x * 0.5 - total * 0.5 - 12.0, 0.0, total + 24.0, float(font_size) + 17.0)


func _draw() -> void:
	if words == "":
		return
	var total := _total()
	var h := float(font_size) + 17.0
	var x := size.x * 0.5 - total * 0.5
	ink_plate(Rect2(x - 12.0, 0.0, total + 24.0, h), Color(0, 0, 0, -1), 8)
	ink_text(Vector2(x, h * 0.5 + float(font_size) * 0.36), words, font_size, colour(&"text"), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 4)
	if key != "":
		var _w := ink_keycap(Vector2(x + text_width(words, font_size) + 10.0, h * 0.5), key, font_size - 4)


func describe() -> Dictionary:
	var out := super()
	out.merge({"text": text()})
	return out
