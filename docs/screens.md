# Screens, the stack, and the panels

## The one idea

**Z-order, input blocking, mouse mode and pause are derived in one place, from one stack.**

Each is easy alone. Collectively they are where UI bugs live: a menu that renders under the HUD, a scoreboard that captures the mouse, an escape key that closes two screens, a settings panel that blocks input to a pause menu it is supposed to sit on top of. `DotScreenStack._refresh()` recomputes all four from `_stack` every time it changes, and nothing else in the addon touches `Input.mouse_mode`, `mouse_filter`, `visible` or `move_child` for a screen. (The one exception is `DotBallotPanel`, which is a widget, not a screen: see [hud.md](hud.md#a-ballot-on-the-hud).)

The two flags that look like one and are not:

- `blocks_input`: a scoreboard held down over a live game is *visible* and must not stop the player moving.
- `hides_below`: a settings panel over a pause menu blocks input and should still let the menu show through.

## Open screens are moved to the end of the child list

`_refresh` moves each open screen to `get_child_count() - 1`, bottom of the stack first, not to its stack index. A closed screen is still a child of the stack. Indexing from zero leaves closed screens *after* open ones in sibling order; they are invisible so nothing draws wrongly, but any other child a host adds under the stack would render above every open screen. The self-test asserts the top screen is the last sibling.

## Pushing what is already open raises it

Almost always a double-fired input rather than an intention. Stacking a second copy gives a menu that takes two escapes to close, and the player has no idea why.

Popping from the *middle* of the stack is allowed rather than refused, for the opposite reason: a screen closing itself in response to a game event does not know what has been opened over it, and refusing would leave a dead screen in the stack for ever.

## A screen that refuses to close still consumes the key

If `_can_pop()` returns false, `_unhandled_input` marks the event handled anyway. Otherwise the escape key both fails to close the menu *and* falls through to gameplay, opening the one below it. `pop_to()` stops at a screen that refuses rather than looping: a bounded walk, not a `while not empty`.

**Use `_can_pop` sparingly.** A screen a player can be trapped in is indistinguishable from a bug.

## A screen's id

`DotScreen._screen_id()` defaults to `StringName(name)`, the NODE NAME. A screen called `Pause` registers as `&"Pause"`, and `push(&"pause")` answers "no such screen", which nothing treats as fatal, so the menu never opens. Ship a screen with an explicit id, and assert `stack.top_id()` after a push: a *registered* screen is sized and focusable whether or not it is on screen.

## `allow_pause` defaults to off

Pausing the tree pauses only the *local* simulation, which desynchronises it from a server that carried on. A menu that pauses is a single-player feature that looks like a general one, and turning it on in a multiplayer game is a client that drifts every time someone opens the settings.

## The pause and settings screens

`DotPauseScreen` and `DotSettingsScreen`, in `screens/`, exist because four clients had each written the same forty lines (a centred `PanelContainer`, a heading, a column of `Button`s, a focus path) and differed only in the words on the buttons and the document the panel was bound to.

Today game-arena and game-hungario use them; the other games are on dot-menu's Escape menu, which builds on this addon's primitives (`DotScreenStack`, `DotInputBinding`, `DotChatWindow`) and adds a designed look. **An extraction is finished when the last caller moves, and nothing in the extracted repository can tell you whether that happened.** The grep is `grep -rn 'extends DotScreen'` (and the screen class names) over the games.

**The settings source is an `Object` and is never named.** dot-ui depends on dot-core and nothing else, and a script that so much as *mentions* `DotSettingsManager` fails to compile in a project without dot-settings. The contract is two methods, `to_config()` and `absorb_config()`; that the screen also accepts a bare `DotConfig` is the proof the seam is real.

**The two-step apply is the whole reason the screen exists.** `to_config()` hands out a *snapshot*: writing to it does not write to the manager. A screen that called only `DotSettingsPanel.apply()` would report success and change nothing, for ever, and every structural check passes either way. Only a check that edits a value, presses Apply and then reads the **manager** can tell the two apart.

**A pause menu's button ids are derived from its labels**, never paired with them. `"Rock the vote"` is `&"rock_the_vote"`. A list of labels and a parallel list of ids is two lists that can disagree.

**`id_override`, not `screen_id`.** `DotScreen` already has a `screen_id()` method and a property cannot shadow one: GDScript refuses it with *"Could not resolve external class member"*, reported against the file that **uses** the property rather than the one that declares it, with `--check-only` on the declaring file saying nothing. The scene then hangs rather than failing. It is configurable because a game legitimately has two settings screens (the player's settings and the interface's own `DotUiConfig` are different documents), and a stack registers by id.

**The settings rows are in a `ScrollContainer` and the buttons sit below it.** A `DotSettingsPanel` is as tall as the document it was handed (`DotUiConfig` alone is around 600 pixels), and without the scroll Apply, Revert and Back left the window. Only a picture catches a regression; see [testing.md](testing.md#what-a-headless-suite-cannot-see).

## The scoreboard screen

`DotScoreboardScreen` is the Tab screen, shared: a title and a ranked `DotTableView`, with the **rows and the columns the game's** (`row_fn`, `columns`), because a deathmatch counts kills, an obstacle course points and an eating game mass. Transparent and non-blocking. game-arena still has its own `ScoreboardScreen`, which predates it; dot-menu's Tab scoreboard is what the other games use.

## `DotSettingsPanel` must never show a secret

`sensitive_keys()` is honoured and `show_sensitive` defaults to off, for the reason `DotConfig` refuses secrets from the environment and argv: both end up in `ps` output, screenshots and pasted bug reports.

- **Group headings are added lazily**, once a group turns out to have something visible in it. Adding them up front leaves a bare "Storage" heading over nothing whenever a group holds only secrets.
- **Text is committed on submit and focus-out, not on `text_changed`.** With `live` on, per-keystroke would be a `validate()` per character typed.
- `apply()` **rolls back every edit** on a validation failure. Applying half of an invalid set leaves the config in a state nobody chose.

## `DotBindingsPanel`: three things a naive rebinder gets wrong

1. **An action left bound to nothing.** `load_saved` resets any action a file leaves with no events back to its default. A truncated, hand-edited or older-build file otherwise leaves the player with a control they cannot use and cannot reach the rebinder for.
2. **Conflicts detected after committing.** `bind_action` checks first, so a refusal is a no-op rather than something the caller undoes.
3. **Escape binding itself.** During capture, escape cancels. Without it, a player who opens the capture by accident binds escape to something and can no longer leave any menu.

Comparison is by **physical keycode**, which is what makes a binding survive a layout change; mixing physical and logical makes a French player's `A` conflict with an English player's `Q`.

An absent `bindings` key in the file is a **failure**; a present-but-empty one is a player who unbound everything. Treating the first as "change nothing" silently accepts a file written by a different tool.

`ui_*` actions are hidden by default: they are the engine's navigation, and rebinding them from a settings screen breaks the settings screen.

`rebindable_actions()` sorts as Strings: `Array.sort()` on `StringName`s compares interned pointers, an order that is neither alphabetical nor stable between builds.

## `DotInputBinding`: one binding as a short string

`"Y"`, `"Shift+A"`, `"Mouse 1"`, `"Wheel up"`, `"Mouse back"`, `"Pad 0"`, `"Axis 0+"`. `DotBindingsPanel` stores a whole screen's worth as dictionaries in a file of its own, which is right for a rebinder; a *single* binding that travels in a settings document needs a form a person can read in a JSON file and type by hand.

The vocabulary is deliberately the one `DotBindingsPanel.event_name` already draws on a button. Two spellings of one binding is a settings file that disagrees with the rebinding screen.

**The wheel and the side buttons are written by name** (API level 2, `MOUSE_NAMES`): `Wheel up` / `down` / `left` / `right` for Godot's buttons 4 to 7, `Mouse back` / `Mouse forward` for 8 and 9. Godot's numbering made the wheel "Mouse 4", which every player reads as the thumb button. The side buttons cannot take "Mouse 4" / "Mouse 5" because `from_text` still reads that old spelling as the wheel: every binding stored before the names says it, and reading it any other way moves a player's key on upgrade. Names read case-blind; "Mouse N" reads for every N. A game that patched its own labels around "Mouse 4" checks `DotAddonApi.build_level("dot_ui") >= 2` before dropping the patch, because a delivered pack runs on the shell's dot-ui.

**Keys are physical.** A binding stored as a keycode is stored in the player's current layout, and the same file on an AZERTY keyboard binds a key that is not where the label says.

**`apply` replaces rather than adds.** `InputMap.action_add_event` on an action that already has one leaves *both* bound: a rebound key that still answers to its old one, invisible until somebody rebinds crouch onto their forward key and both fire. `ensure_action` is the boot path and never overwrites what a player chose.
