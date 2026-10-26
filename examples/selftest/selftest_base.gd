extends Node

## State, fixtures and checks every section of ui_selftest.gd shares.

const BINDINGS_FILE := "user://test_bindings.json"

var _passed := 0
var _failed := 0
var _failures := PackedStringArray()
var _entered := 0
var _completed := 0


## A config with one of everything, including a secret, so the generated panel can be
## checked against something with a known shape.
class TestConfig extends DotConfig:
	@export_group("Network")
	@export var port: int = 27015
	@export_range(1, 240, 1) var tick_rate: int = 64
	@export var hostname: String = "A server"
	@export var rcon_password: String = "hunter2"

	@export_group("Gameplay")
	@export var friendly_fire: bool = false
	@export_range(0.0, 10.0, 0.5) var gravity: float = 8.0
	@export_enum("easy", "normal", "hard") var difficulty: String = "normal"

	func env_prefix() -> String:
		return "TEST_"

	func cli_prefix() -> String:
		return "--test-"

	func sensitive_keys() -> PackedStringArray:
		return PackedStringArray(["rcon_password"])

	func validate() -> DotResult:
		if port < 1024:
			return DotResult.fail(
				DotError.CODE_INVALID, "Ports below 1024 need root."
			)
		return DotResult.success(null)


## A screen that records every lifecycle call, so the ordering can be asserted.
class TestScreen extends DotScreen:
	var id: StringName = &"test"
	var events: Array[String] = []
	var refuse_pop: bool = false

	func _screen_id() -> StringName:
		return id

	func _can_pop() -> bool:
		return not refuse_pop

	func _on_push() -> void:
		events.append("push")

	func _on_pop() -> void:
		events.append("pop")

	func _on_cover() -> void:
		events.append("cover")

	func _on_reveal() -> void:
		events.append("reveal")


func _section(title: String) -> void:
	_entered += 1
	_group(title)


## A section reached its last line. See [constant SECTIONS].
func _done() -> void:
	_completed += 1


func _check(condition: bool, what: String, detail: String = "") -> bool:
	if condition:
		_passed += 1
		print("  ok    %s" % what)
	else:
		_failed += 1
		_failures.append(what if detail == "" else "%s — %s" % [what, detail])
		print("  FAIL  %s%s" % [what, "" if detail == "" else " — " + detail])
	return condition


func _close(a: float, b: float, what: String, epsilon: float = 0.01) -> bool:
	return _check(absf(a - b) <= epsilon, what, "%.3f vs %.3f" % [a, b])


func _group(title: String) -> void:
	print("")
	print("%s" % title)


## A piece in the tree, laid out at [param rect] in this node's space.
func _piece(piece: DotHudPiece, rect: Rect2) -> DotHudPiece:
	piece.position = rect.position
	piece.size = rect.size
	add_child(piece)
	return piece


func _make_stack() -> DotScreenStack:
	var stack := DotScreenStack.new()
	stack.register_service = false
	stack.manage_mouse = false
	stack.config = DotUiConfig.new()
	stack.config.allow_pause = false
	add_child(stack)
	return stack


func _make_screen(id: StringName) -> TestScreen:
	var screen := TestScreen.new()
	screen.id = id
	screen.name = String(id).capitalize()
	return screen


func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


## A plain RefCounted with `to_config()` and `absorb_config()`: the whole settings-source contract, with no DotSettingsManager, because dot-ui depends on dot-core only.
class FakeSettingsSource:
	extends RefCounted

	var stored: Dictionary = {"port": 111, "hostname": "before"}
	var absorbed := 0

	func to_config() -> DotConfig:
		var cfg := TestConfig.new()
		cfg.port = int(stored["port"])
		cfg.hostname = str(stored["hostname"])
		return cfg

	func absorb_config(cfg: DotConfig) -> PackedStringArray:
		absorbed += 1
		var changed := PackedStringArray()
		var typed := cfg as TestConfig
		if typed.port != int(stored["port"]):
			stored["port"] = typed.port
			changed.append("port")
		if typed.hostname != str(stored["hostname"]):
			stored["hostname"] = typed.hostname
			changed.append("hostname")
		return changed


## Counts unhandled mouse clicks that reach it (ballot-panel-avatar-stale-row-1 and pointer recapture).
class ClickProbe extends Node:
	var seen := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			seen += 1


class FakeSelfMute extends RefCounted:
	var ran: Array[String] = []
	var muted: Dictionary = {}
	func claims_chat(text: String) -> bool:
		var t := text.strip_edges().to_lower()
		return (t.begins_with("!") or t.begins_with("/")) and (t.substr(1) == "sm" or t.substr(1).begins_with("sm "))
	func handle_chat(text: String) -> PackedStringArray:
		ran.append(text)
		return PackedStringArray(["ran"])
	func is_muted(name: String, _sender: String = "") -> bool:
		return muted.has(name)
