# dot-ui

Screens, HUD and menus. Read `../../CLAUDE.md` first for the family-wide rules; this
file is only what is specific to the interface.

## The one idea

**Z-order, input blocking, mouse mode and pause are derived in one place, from one
stack.**

Each is easy alone. Collectively they are where UI bugs live: a menu that renders under
the HUD, a scoreboard that captures the mouse, an escape key that closes two screens,
a settings panel that blocks input to a pause menu it is supposed to sit on top of.
`DotScreenStack._refresh()` recomputes all four from `_stack` every time it changes,
and nothing else in the addon touches `Input.mouse_mode`, `mouse_filter`, `visible` or
`move_child` for a screen.

The two flags that look like one and are not:

- `blocks_input` — a scoreboard held down over a live game is *visible* and must not
  stop the player moving.
- `hides_below` — a settings panel over a pause menu blocks input and should still let
  the menu show through.

## Ships no art, imports nothing

`DotUiTheme` generates a whole `Theme` from `StyleBoxFlat`s and a palette. An addon
that shipped textures would impose its art on every game that installed it, and the
first thing anyone does is replace it. A game with a designed theme assigns one and
`DotUiTheme` is never used; a game that wants to ship today gets something legible.

`build()` returns a **fresh** `Theme` every call. A `Theme` is mutable and shared, so
handing out one instance means a game that tweaks one window tweaks both.

The same rule applies to types: dot-ui names nothing outside dot-core.

- `DotFeedView.add_kill` takes strings and colours, not a `DotKillFeed.Entry`.
- `DotTableView` takes columns and rows of dictionaries, not a `DotScoreboard`.
- `DotStatBar` and `DotCrosshair` take `Callable`s, not a `DotHealth` or a
  `DotWeaponBallistics`.

`DotTableView.scoreboard_columns()` is the one concession: the standard columns as
data, so a game does not reinvent them, without dot-ui knowing what fills them.

## Open screens are moved to the *end* of the child list

`_refresh` moves each open screen to `get_child_count() - 1`, bottom of the stack
first — not to its stack index.

A closed screen is still a child of the stack. Indexing from zero leaves closed screens
*after* open ones in sibling order; they are invisible so nothing draws wrongly today,
but any other child a host adds under the stack would render above every open screen.
The self-test asserts the top screen is the last sibling, and it caught exactly this.

## Pushing what is already open raises it

Almost always a double-fired input rather than an intention. Stacking a second copy
gives a menu that takes two escapes to close, and the player has no idea why.

Popping from the *middle* of the stack is allowed rather than refused, for the opposite
reason: a screen closing itself in response to a game event does not know what has been
opened over it, and refusing would leave a dead screen in the stack forever.

## A screen that refuses to close still consumes the key

If `_can_pop()` returns false, `_unhandled_input` marks the event handled anyway.
Otherwise the escape key both fails to close the menu *and* falls through to gameplay,
opening the one below it.

`pop_to()` stops at a screen that refuses rather than looping — a bounded walk, not a
`while not empty`.

**Use `_can_pop` sparingly.** A screen a player can be trapped in is indistinguishable
from a bug.

## `allow_pause` defaults to off

Pausing the tree pauses only the *local* simulation, which desynchronises it from a
server that carried on. A menu that pauses is a single-player feature that looks like a
general one, and turning it on in a multiplayer game is a client that drifts every time
someone opens the settings.

## Widgets pull, and the throttle is the point

A widget wired to a signal misses the change that happened before it was created and
fires four times when four things change in one tick. `DotHudWidget` holds a
`Callable` and re-reads on a throttle.

Without the throttle a HUD re-lays-out text at frame rate to show a number that changes
twice a second. `refresh_on_change` is the escape hatch for anything where lateness is
a lie rather than a delay — health during a burst, ammo mid-magazine.

`DotStatBar` eases the *bar* and never the *number*. Lag on a bar is a readability
feature: a hit that takes a third of your health is legible as a slide and invisible as
a jump. Lag on the number is a lie about the current value. The easing is exponential,
not linear — a linear catch-up takes as long for a one-point change as a hundred-point
one, which reads as a bar that is broken for small hits.

## The crosshair does the real projection

`gap_pixels()` = `base_gap + (viewport_height/2 / tan(fov/2)) * tan(spread)`.

A crosshair that opens by an arbitrary factor is *worse* than a fixed one: it tells the
player something confident and wrong. And `fov_degrees` is exported because a crosshair
that assumes 90 is wrong at every other setting — which is most of them.

`suppressed`, not `hidden`: `Control` already has a `hidden` and redefining it is a
parse error. It is also not `visible`, deliberately — a scoped crosshair keeps
refreshing so a game reading `gap_pixels()` for a scope reticle still gets an answer.

## `DotSettingsPanel` must never show a secret

`sensitive_keys()` is honoured and `show_sensitive` defaults to off. Same reason
`DotConfig` refuses secrets from the environment and argv: both end up in `ps` output,
screenshots and pasted bug reports.

Two other things it gets right that a naive version does not:

- **Group headings are added lazily**, once a group turns out to have something visible
  in it. Adding them up front leaves a bare "Storage" heading over nothing whenever a
  group holds only secrets.
- **Text is committed on submit and focus-out, not on `text_changed`.** With `live` on,
  per-keystroke would be a `validate()` per character typed.

`apply()` **rolls back every edit** on a validation failure. Applying half of an invalid
set leaves the config in a state nobody chose.

## `DotBindingsPanel`: three things a naive rebinder gets wrong

1. **An action left bound to nothing.** `load_saved` resets any action a file leaves
   with no events back to its default. A truncated, hand-edited or older-build file
   otherwise leaves the player with a control they cannot use and cannot reach the
   rebinder for.
2. **Conflicts detected after committing.** `bind_action` checks first, so a refusal is
   a no-op rather than something the caller undoes.
3. **Escape binding itself.** During capture, escape cancels. Without it, a player who
   opens the capture by accident binds escape to something and can no longer leave any
   menu.

Comparison is by **physical keycode**, which is what makes a binding survive a layout
change — mixing physical and logical makes a French player's `A` conflict with an
English player's `Q`.

An absent `bindings` key in the file is a **failure**; a present-but-empty one is a
player who unbound everything. Treating the first as "change nothing" silently accepts
a file written by a different tool.

`ui_*` actions are hidden by default: they are the engine's navigation, and rebinding
them from a settings screen breaks the settings screen.

## The chat box four games did not have

`DotChatWindow`, in `hud/`. A log that fades, a line to type in, and a key that opens it.

**It is here rather than in dot-chat for the reason `DotFeedView` is here.** dot-chat is the decision layer — who hears a line, what it may contain, what name is drawn beside it — and it ships no art on purpose. What happened next is what always happens: four clients in this family could *receive* a chat line and could not *send* one. game-arena's own note called that "a level of ambition rather than an oversight" on the grounds that a scrolling window with an input field is a `DotScreen`. It is not: a screen is modal and takes the whole display, and a chat box is eight lines in a corner that has to leave the game visible behind it. That is a HUD widget.

So this knows nothing about chat. It takes coloured fragments to draw and emits the string somebody typed; a game hands `submitted` to whatever its send path already is and feeds arriving lines back through `add_message`. dot-ui still depends on dot-core and nothing else.

**The open key is an action, not a key.** `open_action` names an `InputMap` action so the binding is the player's — rebindable through `DotBindingsPanel`, or stored in a settings document as text through `DotInputBinding`. `KEY_Y` hardcoded is a key nobody can move, on a keyboard whose Y is somewhere else.

### Three bugs in it, and a picture found all three

- **Consuming keys in `_input` starved the line edit of the keys being typed.** Godot delivers an event to `_input`, *then* to the focused control, then to shortcut and unhandled input. The first draft consumed every key in `_input` to keep them away from the game, which is a chat box nobody can type in. What actually keeps keys out of a game is the focused `LineEdit` itself; what this adds is `gui_input` on the entry, ahead of it, for escape, recall and the channel cycle.
- **`anchor_right = 1.0` on a fresh `Control` leaves it nought pixels wide.** The setter *recomputes the offsets to preserve the control's current rectangle*, and a control built in code has no rectangle yet — so the log drew nothing while every property about it read correctly. This family has now paid for that trap seven times; every offset here is set explicitly, and all four of them after the anchors.
- **A line put in before `_ready` vanished.** A host that builds the box and immediately announces something — or builds it in `SceneTree._initialize`, where *nothing* is inside the tree and no `_ready` has run — was writing into a log that did not exist. The pieces are built on demand now, and `ui_selftest` asserts a line added before the node is readied survives.

**And the log wraps, which `DotFeedView` does not.** A feed entry is two names and a weapon; a chat line is up to the server's 127 characters, and unwrapped it runs out of the box and across the middle of the screen. `DotChatWindow._wrap` splits at word boundaries, keeping each fragment's colour, so a wrap inside what somebody said does not take the speaker's colour with it. It wraps rather than truncating: chat is the one place where the text *is* the content.

`max_lines` bounds **rows**, not messages, and the box's height is derived from it — two numbers for one thing is two numbers that disagree, and the way they disagree is a log drawn through the field somebody is typing in. The log is anchored to the bottom and resized as lines arrive, so the newest line is always against the entry.

`margin_left` and `margin_bottom` are separate because the thing in the way is never in both directions: game-arena has health and armour in that corner and needs the box lifted above them and still flush with the same left edge.

## `DotInputBinding`: one binding as a short string

`"Y"`, `"Shift+A"`, `"Mouse 1"`, `"Pad 0"`, `"Axis 0+"`. `DotBindingsPanel` stores a whole screen's worth as dictionaries in a file of its own, which is right for a rebinder; a *single* binding that travels in a settings document needs a form a person can read in a JSON file and type by hand, and `{"type":"key","code":89,"physical":true}` is neither.

The vocabulary is deliberately the one `DotBindingsPanel.event_name` already draws on a button. Two spellings of one binding is a settings file that disagrees with the rebinding screen.

**Keys are physical.** A binding stored as a keycode is stored in the player's current layout, and the same file on an AZERTY keyboard binds a key that is not where the label says.

**`apply` replaces rather than adds.** `InputMap.action_add_event` on an action that already has one leaves *both* bound — a rebound key that still answers to its old one, invisible until somebody rebinds crouch onto their forward key and both fire. `ensure_action` is the boot path and never overwrites what a player chose.

## Two screens every game was writing for itself

`DotPauseScreen` and `DotSettingsScreen`, in `screens/`. Four clients in this family had independently written the same forty lines — a centred `PanelContainer`, a heading, a column of `Button`s, a focus path — and differed only in which words were on the buttons and which document the panel was bound to. Two copies of one thing is this tree's most expensive mistake; four is that mistake with a number on it.

**The settings source is an `Object` and is never named.** dot-ui depends on dot-core and nothing else, and a script that so much as *mentions* `DotSettingsManager` fails to compile in a project without dot-settings — which is most of them. The contract is two methods, `to_config()` and `absorb_config()`, and that the screen also accepts a bare `DotConfig` is the proof the seam is real. Same shape as dot-chat's backbone client.

**The two-step apply is the whole reason the screen exists.** `to_config()` hands out a *snapshot*: writing to it does not write to the manager. A screen that called only `DotSettingsPanel.apply()` would report success and change nothing, for ever — and every structural check about it passes either way. It builds, it has a size, it has focus, the panel has editors. Only a check that edits a value, presses Apply and then reads the **manager** can tell the two apart.

**A pause menu's button ids are derived from its labels**, never paired with them. `"Rock the vote"` is `&"rock_the_vote"`. A list of labels and a parallel list of ids is two lists that can disagree, and this tree has paid for that shape more than any other.

**`id_override`, not `screen_id`.** `DotScreen` already has a `screen_id()` method and a property cannot shadow one — GDScript refuses it with *"Could not resolve external class member"*, reported against the file that **uses** the property rather than the one that declares it, with `--check-only` on the declaring file saying nothing. The scene then hangs rather than failing. It is configurable at all because a game legitimately has two of these: the player's settings and the interface's own `DotUiConfig` are different documents, and a stack registers by id.

## The addon that draws had no picture of anything

`tools/screenshot.sh` renders `DotPauseScreen` and `DotSettingsScreen` to `screenshots/` through `xvfb-run`. It found two bugs on its first run, and neither was reachable from any assertion:

**The pause menu drew nothing at all.** `DotScreen._screen_id()` defaults to `StringName(name)` — the NODE NAME — so a screen called `Pause` registered as `&"Pause"` and `push(&"pause")` answered "no such screen". That is reported and nothing treats it as fatal, so the menu simply never opened. **Every structural check passed**, in this suite and in game-playground's, because a *registered* screen is sized and focusable whether or not it is on screen: the size check, the focus-path check and the button check were all asserting a screen that was not there. `DotPauseScreen` declares `id_override` now, and both suites assert `stack.top_id()` after the push — which is the check that was missing.

**The settings panel grew past the bottom of the window**, taking Apply, Revert and Back with it: a settings screen a player can read and cannot save from or leave. A `DotSettingsPanel` is as tall as the document it was handed and `DotUiConfig` alone comes out around 600 pixels. The rows are in a `ScrollContainer` now and the buttons sit below it.

### Three assertions were tried against that second one and none of them could fail

| tried | why it passed with the bug in place |
| --- | --- |
| Apply is inside the panel | a `PanelContainer` **grows** to fit, so the button stays inside a panel that has itself left the window |
| Apply is inside the screen | **a headless viewport is 64 × 64**, so every screen in this suite is 64 × 64 and nothing measured against one means anything |
| a long and a short document give the same-sized panel | at 64 × 64 the layout resolves the same either way |

Each was armed by replacing the `ScrollContainer` with a plain box and re-running. None fired. What ships is the **structure plus the reason** — the panel is inside a scroll, the buttons are outside it — which does fire, and the real guard is the screenshot.

### And pointing one at a game's own screens found three more

`game-arena/tools/screenshot_menus.sh` renders that game's pause, controls and scoreboard — the screens this addon does not own. Two of the three bugs were in **this addon**:

- **`DotTableView`: an absent column `width` collapsed the column to nothing.** It meant `SIZE_FILL`, which reads as "take your content's width" and is not, because `clip_text` sets a `Label`'s minimum size to zero. `scoreboard_columns()` gives a width only to `name` — so **every scoreboard and every server browser in this family drew one column**, with the data correct and `describe()` agreeing. An absent width is an equal share now; zero means "shrink to the content" and turns `clip_text` off with it.
- **`DotTableView` honoured no column width at all, ever.** It used a `GridContainer`, which gives every column the SAME width whatever ratio a cell asks for — `size_flags_stretch_ratio` is read by a `BoxContainer` and by nothing else. Measured: four columns declaring 0.4, 3.0, 1.0 and 1.0 came out **308 pixels each**. `width` was documented here, set to 3.0 for the name column in `scoreboard_columns()`, copied into four games' lists, and inert in all of them — which is why long player names were clipped in a table with empty space in it. It is a `VBoxContainer` of `HBoxContainer`s now; the columns still line up across rows because every row is built from the same ratios at the same width. **The first fix made this visible rather than fixing it**: with the columns collapsed to nothing, nobody could see that the widths they came back at were equal. A second picture of the corrected screen is what found it.
- **`DotBindingsPanel.rebindable_actions()` said "sorted" and was not.** `out.sort()` on an `Array[StringName]` compares **interned pointers** — the same trap that gave two peers two different wire ids for one message type in dot-net. The rebinder listed Noclip, Walk, Sprint, Crouch, Jump, Back, Forward, Right, Left, in an order that is not stable between builds either. Sorted as Strings now, and the label drops the `prefix`, which is the part that is not information.

### The HUD too, which nothing had ever looked at

`screenshot.sh` draws a third frame: a `DotStatBar` pair, a `DotCrosshair` and a `DotFeedView` with names of the length a real one has. Every check about those is a number or a property — the bar's eased value, the crosshair's computed gap, the feed's opacity at a given millisecond — all correct, and none of them says whether the thing is legible.

It found no bug, and one thing worth keeping anyway: **a fixture picked at random misses the state worth seeing.** Health at 28% draws in the ordinary colour, because `low_fraction` is 0.25 — and a bar that never goes below the threshold looks exactly like one whose `low_colour` does not work. The fixture is 18 now, and the picture shows red.

That 64 × 64 is worth carrying away on its own: **no assertion in any headless suite in this family can say anything about layout relative to the window.** `size.y > 0` passes at 64 as happily as at 800.

## Validating changes

```bash
cd godot/dot-ui
ln -s ../../dot-core/addons/dot_core addons/dot_core   # gitignored
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/ui_selftest.tscn
```

218 checks, all offline, plus `tools/screenshot.sh` which is not. **Nothing the suite
checks is rendered** — a headless run has no display, and its viewport is 64 × 64 — and
nothing tested depends on rendering. `DotFeedView.expire()` and `opacity_of()` take an
explicit millisecond clock so the fade can be tested without waiting out six real
seconds.

**One bug that "nothing is rendered" hid for the whole life of this addon.**
`set_anchors_preset(Control.PRESET_FULL_RECT)` sets the anchors and **leaves the offsets
alone**, so a `Control` built in code keeps the zero size it was created with: the
thing lays out inside nothing and is invisible while being, by every property,
correctly configured. The family's own CLAUDE.md has carried that warning since dot-ui
was written — and `DotScreenStack` had two of them, `DotCrosshair`, `DotHud` and
`DotTableView` one each. Every screen this addon has ever hosted was 0 × 0 unless its
host happened to size it. All five now use `set_anchors_and_offsets_preset`, and the
suite measures a **size** rather than a property, because a property is exactly what
was already right. Found by game-playground, which was the first project to put a
screen on a stack whose parent is a plain `Node`.

## Things deliberately not here

- **Transitions and animation.** `DotUiConfig.transition_sec` and `reduced_motion` are
  declared and nothing reads them. A tween that a headless test cannot observe, on a
  stack whose whole value is being deterministic, is a bad first thing to add.
- **Localisation.** Every string here is either a player-supplied name or a debug
  label. A game calls `tr()` on what it passes in.
- **Gamepad focus navigation.** `DotScreen.initial_focus` grabs focus and Godot's own
  focus neighbours do the rest. A focus *ring* and edge-wrapping between containers is
  a real design problem and half of one is worse than none.
- **A console.** dot-server has `DotConsole` and its own command surface; a Control
  that renders it belongs in a game, and would make dot-ui depend on dot-server.
- **A server browser.** `DotTableView` is what one is built on. What fills it is
  dot-auth's backbone client and the site's listing API.
- **Nine-patch or textured styling.** Deliberate — see "ships no art". A game assigns
  its own `Theme` and every widget here obeys it.
- **Touch controls.** dot-player-controller ships `DotFpsTouchSampler`, which turns
  fingers into commands and deliberately ships no layout. The on-screen buttons that
  drive it are a game's design, and `DotScreen` is enough to build them on.
