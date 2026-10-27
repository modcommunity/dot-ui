class_name DotWeaponIcons
extends RefCounted

## The stock weapon icon set: Jestan's CC0 pixel-art sprites by type tag (see icons/jestan/CREDITS.md).

const SHEET := "res://addons/dot_ui/icons/jestan/ultimate_weapons_pack.png"

## Type tag to the sprite's (column, row) in the sheet.
const TAGS := {
	&"grenade": Vector2i(0, 0), &"flashbang": Vector2i(0, 1), &"sticky": Vector2i(0, 3), &"mine": Vector2i(0, 5),
	&"hatchet": Vector2i(0, 4), &"knife": Vector2i(0, 8), &"dagger": Vector2i(0, 9), &"hammer": Vector2i(0, 10),
	&"axe": Vector2i(0, 11), &"pickaxe": Vector2i(0, 12), &"sword": Vector2i(0, 13),
	&"derringer": Vector2i(1, 3), &"pistol": Vector2i(1, 5), &"revolver": Vector2i(1, 6), &"machine_pistol": Vector2i(1, 12),
	&"smg": Vector2i(2, 6), &"shotgun": Vector2i(3, 6), &"drum_shotgun": Vector2i(3, 8), &"sawn_off": Vector2i(3, 4),
	&"assault_rifle": Vector2i(4, 1), &"carbine": Vector2i(4, 4), &"bullpup": Vector2i(4, 6), &"battle_rifle": Vector2i(6, 5),
	&"rifle": Vector2i(5, 3), &"marksman": Vector2i(5, 8), &"sniper": Vector2i(5, 9), &"energy_rifle": Vector2i(5, 11),
	&"charge_rifle": Vector2i(4, 7), &"lmg": Vector2i(6, 8), &"launcher": Vector2i(7, 2),
}


## A fresh set with the stock sheet and every tag in [constant TAGS]; add [method DotIconSet.alias]es for your ids.
static func stock() -> DotIconSet:
	var set := DotIconSet.new()
	var sheet := load(SHEET) as Texture2D
	if sheet == null:
		return set
	set.use_sheet(sheet, Vector2i(48, 24))
	for tag in TAGS:
		set.map(tag, TAGS[tag])
	return set
