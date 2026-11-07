@tool
class_name DotHitFeedback
extends Control

## The hit marker and the damage numbers of one HUD, mounted and driven together. Eight
## games built the same pair by hand (a full-rect, mouse-ignoring [DotDamageNumbers] and
## [DotHitMarker] added under the HUD) and each wrote the same `confirm_hit` that flashes
## one and feeds the other; this is that, once.
##
## [codeblock]
## var fx := DotHitFeedback.mount(hud_root)        # in the HUD's build
## fx.confirm_hit(victim, amount, point, killed, headshot)   # from the server's hit event
## [/codeblock]
##
## [b]Call [method confirm_hit] only for a hit the authority applied[/b], never from a
## prediction (see [DotHitMarker]). Both pieces stay reachable ([member marker],
## [member numbers]) for a game that tunes colours or sizes.

var marker: DotHitMarker = null
var numbers: DotDamageNumbers = null


## A feedback layer full-rect and click-through under [param parent], with its two pieces.
## The numbers sit under the marker, as every game had them.
static func mount(parent: Node) -> DotHitFeedback:
	var fx := DotHitFeedback.new()
	fx.name = "HitFeedback"
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fx)
	return fx


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	numbers = DotDamageNumbers.new()
	numbers.name = "DamageNumbers"
	_fill(numbers)
	marker = DotHitMarker.new()
	marker.name = "HitMarker"
	_fill(marker)


func _fill(piece: Control) -> void:
	piece.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(piece)


## A hit of this player's that the authority applied: the marker flashes (red on a kill)
## and the number rises off [param point], grouped by [param victim].
func confirm_hit(victim: int, amount: float, point: Vector3, killed: bool, headshot: bool) -> void:
	marker.flash(killed, headshot)
	numbers.add(victim, amount, point, headshot)


## The same for a 2D game: [param at] is in this control's space.
func confirm_hit_at(victim: int, amount: float, at: Vector2, killed: bool, headshot: bool) -> void:
	marker.flash(killed, headshot)
	numbers.add_at(victim, amount, at, headshot)


## Drops every number and ends the flash (a round restart, a respawn).
func clear() -> void:
	numbers.clear()
	marker.age = marker.life
	marker.queue_redraw()
