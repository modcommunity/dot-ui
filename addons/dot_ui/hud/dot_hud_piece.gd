@tool
class_name DotHudPiece
extends Control

## The base of the glance HUD's pieces ([DotVitals], [DotAmmoCounter], [DotScoreStrip],
## [DotHitMarker], [DotDamageNumbers], [DotKeyPrompt], [DotKeyHints]): how they are drawn,
## where each says it draws, and what each does when something covers it.
##
## [b]Values in, never a game object.[/b] Every piece draws from plain values it is handed
## (`show_*`, `add`, `flash`) and knows nothing about a player or a match, so a suite can
## drive one without a game and a render tool can put one up with chosen numbers. The host
## reads its game once a frame and hands them over.
##
## [b]Readable over a pale map.[/b] Bold text with a dark outline, on a dark translucent
## plate. The first arena HUD drew thin regular-weight text straight over white prototype
## tiles, and health, ammunition and the key hints all but vanished.
##
## [b]Coloured by the theme, with defaults that need none.[/b] Each colour is looked up as
## a theme colour on the type [constant THEME_TYPE] ([constant COLOUR_KEYS]), and an absent
## one is the matching entry of [constant DEFAULTS]. `DotUiTheme.build()` fills every one
## from its palette, dot-menu's themes through [method theme_from], live; a game with a
## designed [Theme] sets the ones it cares about.
##
## [b]Scaled by the HUD, never laid out again.[/b] Every number here is in the HUD's own
## units: a [DotHud] with a [member DotHud.fit_design] scales the whole layer on a frame
## smaller than the one it was designed for, so a piece and the distances between pieces
## shrink together. See [method DotHud.fit_scale].
##
## [b]Out of the way of a ballot.[/b] A client shell draws ballots over a delivered game it
## cannot reach into, and every such widget joins the group [constant COVER_GROUP]. Each
## frame a piece takes the visible members' rect into its own space and, where it meets
## [method footprint], does what [member cover_mode] says.

# No log channel: a piece draws numbers somebody else owns and decides nothing.

## The group every widget that holds screen space over a game joins
## ([constant DotBallotPanel.COVER_GROUP]). The same string, never the other constant, for
## the reason a game spells it: a pack built against a newer dot-ui runs on the shell's.
const COVER_GROUP := "dot_hud_cover"

## The theme type every piece reads its colours from.
const THEME_TYPE := &"DotHudPiece"

## What each colour is without a theme: the dark HUD, deep translucent plates under bold
## white text ringed in black (Christian's first play test, 2026-10-11: the pale plates,
## white key caps and saturated score plates before this read as a toy over a pale map).
## dot-menu's default theme draws the same; the old bright look is its "Arcade" theme.
const DEFAULTS := {
	&"plate": Color(0.025, 0.03, 0.05, 0.74),
	&"plate_edge": Color(1.0, 1.0, 1.0, 0.12),
	&"text": Color(0.97, 0.98, 1.0),
	&"dim": Color(0.72, 0.76, 0.84),
	&"low": Color(1.0, 0.34, 0.3),
	&"good": Color(0.42, 0.9, 0.55),
	&"highlight": Color(1.0, 0.8, 0.22),
	&"ink": Color(0.0, 0.0, 0.0, 0.9),
	&"keycap": Color(0.13, 0.15, 0.2, 0.96),
	&"keycap_text": Color(0.95, 0.96, 0.99),
	&"keycap_edge": Color(1.0, 1.0, 1.0, 0.3),
}

## The theme constants a piece reads (ints, as a [Theme] holds them), and what each is
## without one. `team_fill` is how much of a side's own colour fills its score plate, in
## percent: the dark HUD tints a dark plate and edges it in the colour (38); the bright one
## paints the plate (100).
const DEFAULT_CONSTANTS := {
	&"team_fill": 38,
}

## Every colour key a theme may set on [constant THEME_TYPE], in the order
## [method theme_from] reads them.
const COLOUR_KEYS: Array[StringName] = [
	&"plate", &"plate_edge", &"text", &"dim", &"low", &"good", &"highlight", &"ink",
	&"keycap", &"keycap_text", &"keycap_edge",
]

## What a piece does while a cover meets its footprint.
enum CoverMode {
	## Draws as if nothing were there. For a piece that is never under a cover.
	IGNORE,
	## Fades to [member cover_alpha], so the ballot over it reads and the number is still
	## there for whoever looks.
	DIM,
	## Not drawn at all while covered.
	HIDE,
}

@export var cover_mode: CoverMode = CoverMode.DIM

## How opaque a dimmed piece is.
@export_range(0.0, 1.0, 0.05) var cover_alpha: float = 0.25

## Whether a cover met [method footprint] on the last frame. What a check reads.
var covered: bool = false

static var _fonts: Dictionary = {}


func _init() -> void:
	# A HUD piece never eats the click that should have fired the weapon.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	refresh_cover()


## Where this piece draws, in its own space. Empty when it draws nothing. A host collects
## every piece's to check that no two meet (game-arena's layout check does this at five
## frame sizes), and the cover test reads it.
func footprint() -> Rect2:
	return Rect2()


## Re-reads the cover group and applies [member cover_mode]. Called every frame; public so
## a suite can call it without waiting for one. Each cover is tested on its own: merged, two
## ballots in opposite corners would cover everything between them.
func refresh_cover() -> void:
	covered = false
	if cover_mode != CoverMode.IGNORE:
		var mine := footprint()
		if mine.has_area():
			for rect in cover_rects(self):
				if rect.intersects(mine):
					covered = true
					break
	var alpha := 1.0 if not covered else (cover_alpha if cover_mode == CoverMode.DIM else 0.0)
	if self_modulate.a != alpha:
		self_modulate.a = alpha


## Every visible member of [constant COVER_GROUP], each in [param control]'s own space
## (through the canvas transforms, because a [DotHud] is inset and scaled). Empty when
## nothing covers it, or when [param control] is not in the tree.
static func cover_rects(control: Control) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if control == null or not control.is_inside_tree():
		return out
	var to_me := control.get_global_transform_with_canvas().affine_inverse()
	for node in control.get_tree().get_nodes_in_group(COVER_GROUP):
		var other := node as Control
		if other == null or other == control or not other.is_visible_in_tree() or control.is_ancestor_of(other):
			continue
		var rect := to_me * (other.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, other.size))
		if rect.has_area():
			out.append(rect)
	return out


## [method cover_rects] merged into one: what a host that moves its own widgets out of the
## way reads (game-arena's weapon slots tighten to end above it).
static func covered_rect(control: Control) -> Rect2:
	var out := Rect2()
	for rect in cover_rects(control):
		out = rect if not out.has_area() else out.merge(rect)
	return out


# --- Drawing -------------------------------------------------------------------------

## A colour by name: the theme's, or [constant DEFAULTS].
func colour(key: StringName) -> Color:
	if has_theme_color(key, THEME_TYPE):
		return get_theme_color(key, THEME_TYPE)
	return DEFAULTS.get(key, Color.WHITE)


## A theme constant by name: the theme's, or [constant DEFAULT_CONSTANTS].
func number(key: StringName) -> int:
	if has_theme_constant(key, THEME_TYPE):
		return get_theme_constant(key, THEME_TYPE)
	return int(DEFAULT_CONSTANTS.get(key, 0))


## A [Theme] for a whole HUD layer from [param colours] (keys of [constant COLOUR_KEYS]; one
## left out is not set, so it falls through to a theme further up or to [constant DEFAULTS])
## and [param constants] ([constant DEFAULT_CONSTANTS]' keys).
##
## [b]It also styles a plain [Label] under the layer[/b]: the theme's text colour, outlined
## in its ink. A game's own HUD lines (a round's state, a course's name) are Labels, and
## the first play test found them pale and unreadable over pale maps in four games; a
## Label with its own colour override keeps it, and still gets the outline.
##
## This is what dot-menu's themes hand a game's HUD root, and what [DotUiTheme] fills; a
## game sets it on the node above its pieces and every piece and Label below follows.
static func theme_from(colours: Dictionary, constants: Dictionary = {}) -> Theme:
	var t := Theme.new()
	for key in COLOUR_KEYS:
		if colours.has(key):
			t.set_color(key, THEME_TYPE, colours[key])
	for key in constants:
		t.set_constant(StringName(key), THEME_TYPE, int(constants[key]))
	if colours.has(&"text"):
		t.set_color(&"font_color", &"Label", colours[&"text"])
	if colours.has(&"ink"):
		t.set_color(&"font_outline_color", &"Label", colours[&"ink"])
		t.set_constant(&"outline_size", &"Label", 5)
	return t


## The theme's `font` on [constant THEME_TYPE], or the engine's fallback font emboldened
## (and slanted when [param italic]). Bold, because a regular weight over a moving map
## reads as a debug overlay.
func font(italic: bool = false) -> Font:
	var themed := _theme_font()
	return themed if themed != null else bold_font(italic)


## The `font` a theme sets on [constant THEME_TYPE] itself, from this piece's own theme up
## through its ancestors' to the project's; null when none does.
##
## [b]Not `has_theme_font`[/b], which is true for any name on any type as soon as a theme in
## the chain has a default font, and the engine's own theme always has one: every piece drew
## in the regular-weight fallback and never in [method bold_font] (game-arena's glance HUD,
## rendered after the move, 2026-10-11). A font set on the type is asked for by name instead.
## Private, so the API level does not move: a game sets the font through a theme.
func _theme_font() -> Font:
	var node: Node = self
	while node != null:
		var owned: Theme = null
		if node is Control:
			owned = (node as Control).theme
		elif node is Window:
			owned = (node as Window).theme
		if owned != null and owned.get_font_list(THEME_TYPE).has("font"):
			return owned.get_font(&"font", THEME_TYPE)
		node = node.get_parent()
	var project := ThemeDB.get_project_theme()
	if project != null and project.get_font_list(THEME_TYPE).has("font"):
		return project.get_font(&"font", THEME_TYPE)
	return null


## The emboldened fallback font, shared by every piece.
static func bold_font(italic: bool = false) -> Font:
	if not _fonts.has(italic):
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 0.85
		if italic:
			f.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.2, 1.0), Vector2.ZERO)
		_fonts[italic] = f
	return _fonts[italic]


func text_width(words: String, font_size: int, italic: bool = false) -> float:
	return font(italic).get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


## [param words] with its baseline at [param at], outlined in the `ink` colour.
func ink_text(
	at: Vector2, words: String, font_size: int, fill: Color,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, box: float = -1.0, outline: int = 6,
	italic: bool = false
) -> void:
	var f := font(italic)
	if outline > 0:
		var ink := colour(&"ink")
		draw_string_outline(f, at, words, align, box, font_size, outline, Color(ink, ink.a * fill.a))
	draw_string(f, at, words, align, box, font_size, fill)


## A rounded plate. [param fill] defaults to the theme's `plate`, [param edge] to
## `plate_edge`.
func ink_plate(rect: Rect2, fill: Color = Color(0, 0, 0, -1), radius: int = 7, edge: Color = Color(0, 0, 0, -1), edge_width: int = 1) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = colour(&"plate") if fill.a < 0.0 else fill
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	var line := colour(&"plate_edge") if edge.a < 0.0 else edge
	if line.a > 0.0 and edge_width > 0:
		box.border_color = line
		box.set_border_width_all(edge_width)
	draw_style_box(box, rect)


## A key drawn as a key: a cap in the theme's `keycap` with the key's name, its left edge at [param at].x and
## its centre at [param at].y. Returns its width.
func ink_keycap(at: Vector2, key: String, font_size: int = 13, alpha: float = 1.0) -> float:
	var w := keycap_width(key, font_size)
	var h := float(font_size) + 10.0
	var rect := Rect2(at.x, at.y - h * 0.5, w, h)
	ink_plate(Rect2(rect.position + Vector2(0.0, 2.0), rect.size), Color(0.0, 0.0, 0.0, 0.45 * alpha), 5, Color(0, 0, 0, 0), 0)
	var cap := colour(&"keycap")
	var edge := colour(&"keycap_edge")
	ink_plate(rect, Color(cap, cap.a * alpha), 5, Color(edge, edge.a * alpha), 1 if edge.a > 0.0 else 0)
	draw_string(font(), Vector2(rect.position.x, rect.end.y - 6.0), key, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, Color(colour(&"keycap_text"), alpha))
	return w


func keycap_width(key: String, font_size: int = 13) -> float:
	return maxf(text_width(key, font_size) + 12.0, float(font_size) + 10.0)


func describe() -> Dictionary:
	return {
		"name": String(name),
		"footprint": footprint(),
		"covered": covered,
		"cover_mode": cover_mode,
	}
