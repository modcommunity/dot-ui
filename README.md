This is the **interface** asset for TMC's **Dot** collection. It is the plumbing behind screens and menus, and it deliberately ships no art so it never fights your own.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Screens, HUD and Menus
Screens, HUD and menus for a Godot 4 game, with **no art assets**. A screen stack that derives z-order, input blocking and mouse mode from one place; a settings panel generated from any `DotConfig`; a rebinder with conflict detection; and data-driven HUD widgets.

Part of the [dot-*](https://github.com/modcommunity) family. Needs **dot-core** and nothing else.

## Install

Copy `addons/dot_ui/` and `addons/dot_core/` into your project and enable both in *Project → Project Settings → Plugins*.

## Use

```gdscript
var stack := DotScreenStack.new()
add_child(stack)
stack.register(pause_menu)
stack.register(settings_screen)

hud.bind_stack(stack)

# A settings screen, from the config you already have.
settings_panel.bind(server_config)

# A health bar, from the health you already have.
health_bar.bind(func(): return health.health)
```

## The idea

**Four things have to agree, and they are usually written in four places.** Z-order, input blocking, mouse capture and the back key are each simple alone. The bug is a pause menu that is visible but not focused, a scoreboard that captures the mouse, or an escape key that closes two screens at once.

`DotScreenStack` derives all four from one stack, every time it changes.

The second idea is that **dot-ui ships no art and imports nothing.** No textures, no fonts, no nine-patches, and no knowledge of dot-match or dot-combat. The theme is generated from `StyleBoxFlat`s; the kill feed takes coloured string fragments; the scoreboard takes rows of dictionaries.

## What is in the box

| | |
| --- | --- |
| `DotScreenStack` / `DotScreen` | What is open, in what order, and who gets input. |
| `DotUiTheme` | A whole `Theme` from a palette and a scale. No assets. |
| `DotHud` / `DotHudWidget` | The always-on layer, and widgets that *pull* rather than being pushed. |
| `DotStatBar` | Health, armour, ammo. Eased bar, un-eased number. |
| `DotCrosshair` | Opens by the actual spread angle through the actual camera projection. |
| `DotStarfield` | A parallax starfield drawn into any `CanvasItem`. Hashed, so nothing is stored. |
| `DotFeedView` | A bounded, self-expiring list of coloured fragments. Kill feed and chat. |
| `DotChatWindow` | A chat box: a log that fades, a line to type in, and a key that opens it. |
| `DotTableView` | Rows and columns. Scoreboard, server browser, ban list. |
| `DotSettingsPanel` | Builds itself from a `DotConfig`. Never shows a secret. |
| `DotBindingsPanel` | Rebinding, conflict detection, and a file that survives a restart. |
| `DotInputBinding` | One binding as a short string — `"Y"`, `"Shift+A"`, `"Mouse 1"` — and back. |

## `DotSettingsPanel` reads the config you already wrote

Every project in this family already describes its settings in `@export` annotations: keys, types, ranges, enum choices, groups, and which ones are secrets. A hand-built settings screen restates all of that and then drifts from it, one field at a time, until a setting exists that no screen can reach.

So this reads the config and builds the controls. It honours `sensitive_keys()`, for the same reason `DotConfig` refuses secrets from the environment and argv: they end up in screenshots and pasted bug reports.

Edits are held until `apply()`, and **an invalid set is rolled back entirely**. Applying half of them leaves the config in a state nobody chose and the player cannot tell which half survived.

## `DotChatWindow` is a chat box, and knows nothing about chat

A log that fades when the box is closed and holds while it is open, a line to type in, and an action that opens it — `Y` by default, because that is where this genre has put it for twenty-five years.

It takes coloured fragments to draw and emits the string somebody typed. Point `submitted` at whatever your send path already is, feed arriving lines back through `add_message`, and connect `opened` and `closed` to whatever suspends your controller:

```gdscript
var chat := DotChatWindow.new()
chat.submitted.connect(func(text: String, _channel: StringName) -> void:
    link.send_chat(text))
chat.opened.connect(func(_c: StringName) -> void: controller.suspended = true)
chat.closed.connect(func() -> void: controller.suspended = false)
add_child(chat)
```

**That last pair is not optional.** A focused `LineEdit` keeps typed keys out of `_unhandled_input`, but it cannot do a thing about `Input.is_action_pressed`, which is polled straight off the device and does not care what consumed the event. Without it, typing "sw" walks the player backwards.

Long lines wrap at word boundaries, because a chat line is as long as the server's limit and an unwrapped one runs out of the box and across the screen. `max_lines` bounds drawn **rows** rather than messages, and the box's height is derived from it — a log allowed more rows than it is tall draws the overflow through the field somebody is typing in.

**The binding is the player's.** `open_action` is an `InputMap` action, so it is rebindable through `DotBindingsPanel` or storable in a settings document as text through `DotInputBinding`. Nothing here hardcodes a key.

## Widgets pull

A health bar wired to a `health_changed` signal misses the change that happened before it was created, and fires four times when four things change in one tick. A `DotHudWidget` holds a `Callable` that reads the value, on a throttle of ten times a second by default, which is faster than anyone can read, with an immediate path for anything where lateness is a lie.

## The crosshair does the projection

`gap_pixels()` is `half_viewport_height / tan(fov/2)`, the focal length in pixels, times `tan(spread)`. A crosshair that opens by an arbitrary amount is worse than a fixed one: it tells the player something confident and wrong about where their shots will go, and a crosshair that assumes a 90° field of view is wrong at every other setting.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/ui_selftest.tscn
```

136 checks, all offline, nothing rendered. Exits non-zero on any failure.
