@tool
class_name DotUiConfig
extends DotConfig

## Everything configurable about the interface. Layered like every [DotConfig]:
## exported defaults, then a JSON file, then [code]DOT_UI_*[/code] environment
## variables, then [code]--ui-*[/code] arguments.

@export_group("Scale")

## Multiplies every size in the generated theme.
##
## Not a replacement for the window's own content scale — this is the accessibility
## knob, and a player who needs bigger text needs it bigger than the layout intended.
@export_range(0.5, 3.0, 0.05) var scale: float = 1.0

## Inset from the screen edge, in pixels before scaling.
##
## Phones with notches, televisions with overscan. A HUD that assumes it owns the
## whole rectangle is a HUD with an ammo counter under a camera cutout.
@export_range(0.0, 200.0, 1.0) var safe_area: float = 16.0

@export_group("Behaviour")

## Whether the escape key pops a screen.
##
## Off for a game that wants to handle it itself. On, [DotScreenStack] consumes the
## event, which is why it is a setting rather than something a game overrides.
@export var back_pops_screen: bool = true

## Whether opening a screen that requests it pauses the tree.
##
## [b]Off on a dedicated-server client.[/b] Pausing a multiplayer game pauses only the
## local simulation, which desynchronises it from a server that carried on — so a menu
## that pauses is a single-player feature that looks like a general one.
@export var allow_pause: bool = false

## Seconds a screen transition takes. Zero is instant.
##
## [b]Not applied yet.[/b] [DotScreenStack] switches instantly whatever this says;
## the field is here so a game that animates its own screens reads one number.
## Declared honestly rather than quietly ignored.
@export_range(0.0, 2.0, 0.05) var transition_sec: float = 0.12

## Skip transitions entirely.
##
## Respects a player who gets motion sick, and makes a UI test deterministic — which
## is why the self-test turns it on rather than waiting out tweens.
@export var reduced_motion: bool = false

@export_group("HUD")

## Seconds a kill-feed entry stays up.
@export_range(1.0, 60.0, 0.5) var feed_lifetime_sec: float = 6.0

## Lines the kill feed shows at once.
@export_range(1, 12, 1) var feed_lines: int = 5

## Seconds a chat line stays up when the chat is not focused. dot-ui ships no chat
## widget — a game's own reads this and [member chat_lines], as dot-2d-hungry's could.
@export_range(1.0, 120.0, 1.0) var chat_lifetime_sec: float = 12.0

@export_range(1, 40, 1) var chat_lines: int = 8

@export_group("Input")

## Where rebindings are saved.
@export var bindings_file: String = "user://cfg/bindings.json"

## Actions a player may not rebind. Movement is usually left alone; a menu-back or a
## console key that can be rebound to nothing is a player who cannot get out.
@export var locked_actions: Array[StringName] = [&"ui_cancel", &"ui_accept"]


func env_prefix() -> String:
	return "DOT_UI_"


func cli_prefix() -> String:
	return "--ui-"


func validate() -> DotResult:
	if scale <= 0.0:
		return DotResult.fail(DotError.CODE_INVALID, "A UI scale of zero.")

	if allow_pause:
		# Not an error: a single-player game wants it. But it is the setting most
		# likely to be turned on by habit and then to desynchronise a multiplayer
		# client from a server that did not pause with it.
		DotLog.debug(
			"ui.config",
			"allow_pause is on; a menu will pause the local tree only, "
			+ "which desynchronises a networked game"
		)

	return DotResult.success(null)


func describe_summary() -> String:
	return "x%.2f%s%s" % [
		scale,
		", reduced motion" if reduced_motion else "",
		", pauses" if allow_pause else "",
	]
