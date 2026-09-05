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
  `DotWeaponState`.

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

138 checks, all offline. **Nothing is rendered** — a headless run has no display — and
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
- **Touch controls.** dot-fps-controller ships `DotFpsTouchSampler`, which turns
  fingers into commands and deliberately ships no layout. The on-screen buttons that
  drive it are a game's design, and `DotScreen` is enough to build them on.
