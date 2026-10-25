# dot-ui

Screens, HUD and menus with no art assets: a screen stack that owns z-order, input, mouse mode and pause; pause, settings and scoreboard screens; a settings panel and a rebinder; HUD widgets (stat bar, crosshair, feed, table, chat box, ballot) and the glance pieces (vitals, ammo, score strip and clock, hit marker, damage numbers, key prompt and hints); and a theme generated from a palette.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to the interface. The reasoning is in [docs/](docs/README.md). dot-menu builds the designed Escape menu and Tab scoreboard on top of this.

**Depends on dot-core and nothing else, and names nothing outside it.** Widgets take strings, dictionaries and `Callable`s; a settings source is an untyped `Object`. A script that so much as mentions another addon's class fails to compile without it. [hud](docs/hud.md#ships-no-art-names-nothing-outside-dot-core)

Also requires **dot-profile** (`DotProfileSet`, `DotProfile`, `DotProfileRuntime`, split from dot-core): link `addons/dot_profile` next to `addons/dot_core`.

## Read before

| Read | Before |
| --- | --- |
| [docs/README.md](docs/README.md) | the index |
| [docs/screens.md](docs/screens.md) | the stack, screen ids, pause, the shared screens, the settings and bindings panels, `DotInputBinding` |
| [docs/hud.md](docs/hud.md) | the theme, widgets, crosshair, table, chat box, ballot, the glance pieces and which arena pieces moved, what is deliberately not here |
| [docs/testing.md](docs/testing.md) | adding a check, or believing one; the screenshots |
| [docs/history.md](docs/history.md) | the bugs, and how each looked |

## Layout

| Path | What |
| --- | --- |
| `addons/dot_ui/core/` | `DotScreen`, `DotScreenStack`, `DotUiTheme`, `DotInputBinding` |
| `addons/dot_ui/hud/` | `DotHud`, `DotHudWidget`, `DotStatBar`, `DotCrosshair`, `DotFeedView`, `DotTableView`, `DotChatWindow`, `DotBallotPanel`, `DotStarfield`; the glance pieces on `DotHudPiece`: `DotVitals`, `DotAmmoCounter`, `DotScoreStrip`, `DotHitMarker`, `DotDamageNumbers`, `DotKeyPrompt`, `DotKeyHints` |
| `addons/dot_ui/panels/` | `DotSettingsPanel`, `DotBindingsPanel` |
| `addons/dot_ui/screens/` | `DotPauseScreen`, `DotSettingsScreen`, `DotScoreboardScreen`; `DotWinnerReveal`, the end-of-match winner and podium (its own layer, not a stack screen) |
| `addons/dot_ui/form/` | `DotUiForm` (schema-driven form), `DotFormTokens`, `DotFormSchema`, `DotFormRow`, `DotFormGroup`, `DotFormSlider`, `DotFormToggle`, `DotFormKeypad` (on-screen keyboard); [docs/form.md](docs/form.md), `examples/form_demo.tscn`, `examples/form_selftest.tscn`, `tools/form_screenshot.sh` |
| `addons/dot_ui/dot_ui_config.gd` | `DotUiConfig`, the interface's own settings document |
| `examples/ui_selftest.tscn` | the suite, offline |
| `tools/screenshot.sh` | renders pause, settings, HUD, chat, ballot, ballot-result and the three glance-piece frames (`hud_pieces*.png`: no theme, light theme, fitted to 854x480) to `screenshots/` through `xvfb-run` |

## Running and testing

- Link `addons/dot_core` once ([development setup](../../docs/development-setup.md)), then the family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)) and `godot --headless --path . res://examples/ui_selftest.tscn`.
- **Every visual change wants `tools/screenshot.sh` run and the frame looked at.** A headless viewport is 64 × 64, so no assertion can say anything about layout relative to the window; most of this addon's bugs were found by a picture. [testing](docs/testing.md#what-a-headless-suite-cannot-see)
- Measure a size in a check, never a property. Pick fixtures that put a widget in the state its options exist for. [testing](docs/testing.md)

## Rules that bite

**The stack**

- Only `DotScreenStack._refresh()` touches `Input.mouse_mode`, `mouse_filter`, `visible` or `move_child` for a screen. `DotBallotPanel` is the one widget exception, and restores the mode it found. [screens](docs/screens.md#the-one-idea)
- `blocks_input` and `hides_below` are different flags. [screens](docs/screens.md#the-one-idea)
- Open screens go to the end of the child list, bottom first. [screens](docs/screens.md#open-screens-are-moved-to-the-end-of-the-child-list)
- Pushing an open screen raises it; popping from the middle is allowed. [screens](docs/screens.md#pushing-what-is-already-open-raises-it)
- A screen refusing `_can_pop` still consumes the key; use it sparingly. [screens](docs/screens.md#a-screen-that-refuses-to-close-still-consumes-the-key)
- A screen's id defaults to its NODE NAME; set one, and assert `stack.top_id()` after a push. A property named like a `DotScreen` method (`screen_id`) breaks the *using* file and hangs the scene: it is `id_override`. [screens](docs/screens.md#a-screens-id)
- `DotWinnerReveal` is timed by `advance`, never tweens, so a check steps it exactly; `reduced_motion` draws its last frame from the first and bursts nothing. [screens](docs/screens.md#the-winner-reveal)
- `allow_pause` defaults to off: pausing desyncs a networked client. [screens](docs/screens.md#allow_pause-defaults-to-off)

**Panels and screens**

- `DotSettingsScreen` applies in two steps (panel into the snapshot, snapshot into the source via `absorb_config`); a check must read the manager after Apply. [screens](docs/screens.md#the-pause-and-settings-screens)
- Pause button ids are derived from labels, never a parallel list. [screens](docs/screens.md#the-pause-and-settings-screens)
- `DotSettingsPanel` never shows a secret (`show_sensitive` off), commits text on submit/focus-out, and rolls back every edit on a failed `apply()`. [screens](docs/screens.md#dotsettingspanel-must-never-show-a-secret)
- Bindings compare by physical keycode; an action left with no events resets to default; escape cancels capture; an absent `bindings` key is a failure; `ui_*` hidden. Sort `StringName`s as Strings. [screens](docs/screens.md#dotbindingspanel-three-things-a-naive-rebinder-gets-wrong)
- `DotInputBinding.apply` replaces, never adds; `ensure_action` never overwrites a player's choice; its vocabulary is `event_name`'s. [screens](docs/screens.md#dotinputbinding-one-binding-as-a-short-string)
- The wheel and side buttons are written by name (`Wheel up`, `Mouse back`), and the old `Mouse 4` must keep reading as the wheel; a rename here is an API level. [screens](docs/screens.md#dotinputbinding-one-binding-as-a-short-string)

**Widgets**

- `DotUiTheme.build()` returns a fresh `Theme` every call. [hud](docs/hud.md#ships-no-art-names-nothing-outside-dot-core)
- Widgets pull on a throttle; `refresh_on_change` where lateness is a lie. A stat bar eases the bar, never the number, exponentially. [hud](docs/hud.md#widgets-pull-and-the-throttle-is-the-point)
- The crosshair gap is the real projection at the real FOV; `suppressed`, not `hidden` or `visible`. [hud](docs/hud.md#the-crosshair-does-the-real-projection)
- The crosshair fades out while aiming down sights through `aim_source` (the view model's aim fraction) or `set_aim`, never snapped; a game with its own dot uses `opacity_for_aim`. [hud](docs/hud.md#the-crosshair-fades-while-aiming-down-sights)
- `DotTableView` is boxes, never a grid; an absent width is an equal share, zero shrinks to content. [hud](docs/hud.md#dottableview)
- A control built in code: use `set_anchors_and_offsets_preset`, or set all four offsets after the anchors. [hud](docs/hud.md#the-chat-box)
- Never consume every key in `_input` (it starves a focused `LineEdit`); the ballot takes only its number keys, and none while a text field has focus. [hud](docs/hud.md#the-chat-box)
- An open key is an `InputMap` action, never a hardcoded key. [hud](docs/hud.md#the-chat-box)
- `DotChatWindow` runs `!sm` / `/sm` itself and never emits them; `add_said` drops a self-muted speaker. The list is found by registry name or path, never named. [hud](docs/hud.md#the-chat-box)
- A ballot's unconfirmed local click outranks a disagreeing server state for `PENDING_MS` on the same options; a closed result snaps the avatars. [hud](docs/hud.md#a-ballot-on-the-hud)
- A glance piece takes values, never a game object; its colours are theme colours on `DotHudPiece` with `DEFAULTS` behind them; it says where it draws in `footprint()`. [hud](docs/hud.md#the-glance-pieces)
- The default HUD is dark (deep plates, dark key caps, tinted score plates); the bright look is a theme, never the default. A layer's look is one `Theme` on its root (`DotHudPiece.theme_from`), replaced live, never a walk of the pieces; a game's accent theme sets `highlight`/`plate_edge` and leaves plate, text and ink to the theme. [hud](docs/hud.md#the-glance-pieces)
- A piece's font is a `font` a theme sets on the type `DotHudPiece`, looked up by name; never `has_theme_font`, which is true whenever any theme has a default font (the engine's does). [hud](docs/hud.md#the-glance-pieces)
- A piece tests each `dot_hud_cover` member on its own against its footprint, never the merged rect, and the full-rect pieces (hit marker, damage numbers) default to `IGNORE`. [hud](docs/hud.md#the-glance-pieces)
- `DotHud.fit_design` scales the whole HUD below the design frame and never lays it out again; zero keeps the full-rect anchoring. [hud](docs/hud.md#the-glance-pieces)
- A new piece or a new public method on one is an API level (`dot_ui_api.gd`): a delivered pack runs on the shell's dot-ui. [hud](docs/hud.md#the-glance-pieces)

## Where a game plugs in

| To change | Where |
| --- | --- |
| What the interface looks like | assign a `Theme`, or `DotUiTheme` with a palette |
| A screen | `DotScreen` subclass registered on a `DotScreenStack` |
| What a HUD number shows | a `Callable` on `DotHudWidget` / `DotStatBar` / `DotCrosshair` |
| The scoreboard's rows and columns | `DotScoreboardScreen.row_fn` / `columns`; `DotTableView.scoreboard_columns()` for the standard ones |
| Where settings come from | any `Object` with `to_config()` / `absorb_config()`, or a `DotConfig`, on `DotSettingsScreen` |
| What may be rebound | `DotBindingsPanel` (prefix filter, `ui_*` hidden) |
| One binding in a settings document | `DotInputBinding` |
| How chat is sent and received | `DotChatWindow.submitted` and `add_message`; `open_action`, `max_lines`, margins, `outline_size` |
| What a ballot choice does | `DotBallotPanel.chosen` |
| Health, ammunition, the clock and scores, hit feedback, key prompts | the glance pieces' `show_*` / `flash` / `add`; `cover_mode`; theme colours on `DotHudPiece` |
| Scaling a HUD on a small frame, or to the player's size | `DotHud.fit_design`, `fit_scale`, `fit_to_frame`; `user_scale`, `fit_control` |
| A whole HUD layer's colours, switched live | `DotHudPiece.theme_from` on the layer's root (dot-menu's `follow_hud` does it per theme) |
| Keeping a game's HUD out from under a ballot | read the visible members of the `dot_hud_cover` group by that string ([hud](docs/hud.md#a-ballot-on-the-hud)) |

Deliberately not here: screen transitions (`transition_sec` and `DotUiConfig.reduced_motion` are read by nothing; `DotWinnerReveal` has its own `reduced_motion`), localisation, gamepad focus rings, a console, a server browser, textured styling, touch layouts. [hud](docs/hud.md#deliberately-not-here)
