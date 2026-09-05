@tool
extends EditorPlugin

## Editor entry point for dot-ui. Registers inspector types only.
##
## No autoload, for the family's reason: a process may run two windows or a server and
## a client at once, and a singleton screen stack makes that impossible.
## [DotScreenStack] registers itself in [DotRegistry] instead.

const _ICON := "res://addons/dot_ui/icon_placeholder.svg"

const _TYPES := [
	["DotScreenStack", "Control", "res://addons/dot_ui/core/dot_screen_stack.gd"],
	["DotScreen", "Control", "res://addons/dot_ui/core/dot_screen.gd"],
	["DotHud", "Control", "res://addons/dot_ui/hud/dot_hud.gd"],
	["DotStatBar", "Control", "res://addons/dot_ui/hud/dot_stat_bar.gd"],
	["DotCrosshair", "Control", "res://addons/dot_ui/hud/dot_crosshair.gd"],
	["DotFeedView", "Control", "res://addons/dot_ui/hud/dot_feed_view.gd"],
	["DotTableView", "Control", "res://addons/dot_ui/hud/dot_table_view.gd"],
	[
		"DotSettingsPanel",
		"VBoxContainer",
		"res://addons/dot_ui/panels/dot_settings_panel.gd",
	],
	[
		"DotBindingsPanel",
		"VBoxContainer",
		"res://addons/dot_ui/panels/dot_bindings_panel.gd",
	],
]


func _enter_tree() -> void:
	var icon: Texture2D = null
	if ResourceLoader.exists(_ICON):
		icon = load(_ICON) as Texture2D

	for entry in _TYPES:
		add_custom_type(entry[0], entry[1], load(entry[2]), icon)


func _exit_tree() -> void:
	for i in range(_TYPES.size() - 1, -1, -1):
		remove_custom_type(_TYPES[i][0])
