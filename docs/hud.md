# HUD widgets and the theme

## Ships no art, names nothing outside dot-core

`DotUiTheme` generates a whole `Theme` from `StyleBoxFlat`s and a palette. An addon that shipped textures would impose its art on every game that installed it, and the first thing anyone does is replace it. A game with a designed theme assigns one and `DotUiTheme` is never used; a game that wants to ship today gets something legible.

`build()` returns a **fresh** `Theme` every call. A `Theme` is mutable and shared, so handing out one instance means a game that tweaks one window tweaks both.

The same rule applies to types:

- `DotFeedView.add_kill` takes strings and colours, not a `DotKillFeed.Entry`.
- `DotTableView` takes columns and rows of dictionaries, not a `DotScoreboard`.
- `DotStatBar` and `DotCrosshair` take `Callable`s, not a `DotHealth` or a `DotWeaponBallistics`.
- `DotChatWindow` and `DotBallotPanel` take dictionaries and emit what was typed or chosen.

`DotTableView.scoreboard_columns()` is the one concession: the standard columns as data, so a game does not reinvent them, without dot-ui knowing what fills them.

## Widgets pull, and the throttle is the point

A widget wired to a signal misses the change that happened before it was created and fires four times when four things change in one tick. `DotHudWidget` holds a `Callable` and re-reads on a throttle.

Without the throttle a HUD re-lays-out text at frame rate to show a number that changes twice a second. `refresh_on_change` is the escape hatch for anything where lateness is a lie rather than a delay: health during a burst, ammo mid-magazine.

`DotStatBar` eases the *bar* and never the *number*. Lag on a bar is a readability feature: a hit that takes a third of your health is legible as a slide and invisible as a jump. Lag on the number is a lie about the current value. The easing is exponential, not linear: a linear catch-up takes as long for a one-point change as a hundred-point one, which reads as a bar that is broken for small hits.

## The crosshair does the real projection

`gap_pixels()` = `base_gap + (viewport_height/2 / tan(fov/2)) * tan(spread)`.

A crosshair that opens by an arbitrary factor is *worse* than a fixed one: it tells the player something confident and wrong. `fov_degrees` is exported because a crosshair that assumes 90 is wrong at every other setting.

`suppressed`, not `hidden`: `Control` already has a `hidden` and redefining it is a parse error. It is also not `visible`, deliberately: a scoped crosshair keeps refreshing so a game reading `gap_pixels()` for a scope reticle still gets an answer.

## `DotTableView`

A `VBoxContainer` of `HBoxContainer`s, never a `GridContainer`: a grid gives every column the same width whatever ratio a cell asks for (`size_flags_stretch_ratio` is read by a `BoxContainer` and nothing else). The columns line up across rows because every row is built from the same ratios at the same width.

An absent column `width` is an equal share; zero means "shrink to the content" and turns `clip_text` off with it. (`SIZE_FILL` alone collapses a clipped `Label` to nothing, because `clip_text` sets its minimum size to zero.)

An icon column (`"kind": &"icon"`, a `Texture2D` per row) puts an avatar beside a name; a row with no picture keeps the column's width, so the columns after it do not shift.

## The chat box

`DotChatWindow`: a log that fades, a line to type in, and a key that opens it.

**It is here rather than in dot-chat for the reason `DotFeedView` is here.** dot-chat is the decision layer (who hears a line, what it may contain, what name is drawn beside it) and it ships no art on purpose. A chat box is not a `DotScreen`: a screen is modal and takes the whole display, and a chat box is eight lines in a corner that has to leave the game visible behind it. That is a HUD widget. It knows nothing about chat: it takes coloured fragments to draw and emits the string somebody typed (`submitted`); a game feeds arriving lines back through `add_message`.

- **The open key is an action, not a key.** `open_action` names an `InputMap` action so the binding is the player's. A hardcoded key is a key nobody can move, on a keyboard whose Y is somewhere else.
- **It never consumes keys in `_input`.** Godot delivers an event to `_input`, *then* to the focused control. What keeps keys out of a game is the focused `LineEdit` itself; escape, recall and the channel cycle are handled in `gui_input` on the entry, ahead of it.
- **Its pieces are built on demand**, so a line added before `_ready` (or from `SceneTree._initialize`, where nothing is in the tree) survives. The suite asserts it.
- **Every offset is set explicitly, after the anchors.** `anchor_right = 1.0` on a fresh `Control` recomputes the offsets to preserve the current rectangle, and a control built in code has none, so it stays nought pixels wide. See [bugs-found](../../../docs/bugs-found.md).
- **The log wraps, which `DotFeedView` does not.** A chat line is up to the server's 127 characters. `_wrap` splits at word boundaries, keeping each fragment's colour, so a wrap inside what somebody said does not take the speaker's colour with it. It wraps rather than truncating: chat is the one place where the text *is* the content.
- **`max_lines` bounds rows, not messages, and the box's height is derived from it.** Two numbers for one thing disagree, and the way they disagree is a log drawn through the field somebody is typing in. The log is anchored to the bottom and resized as lines arrive.
- `margin_left` and `margin_bottom` are separate because the thing in the way is never in both directions (a game with health in that corner lifts the box and keeps the left edge).

## Outlines, because a game is not one colour

`DotFeedView.outline_size`, off by default, and passed through by `DotChatWindow`. White text disappears over pale ground in bright light, black text over a dark map, and a panel behind the text covers a rectangle of the thing the player is trying to see. Measured in mg-buses-from-hell (pale sand under a low sun): three chat lines in three colours, all unreadable, in a frame where every property was correct.

## A ballot on the HUD

`DotBallotPanel`: numbered options a player picks with a number key or a click, a countdown, and every voter's avatar sitting on what they chose, sliding to another row when they change their mind. It takes a dictionary (dot-vote's `DotVoteBallotView` state) and emits `chosen(index, id, command)`; what a choice turns into is the host's.

**It touches `Input.mouse_mode`, the one exception to "the stack owns it".** It is not a screen: a ballot is a widget over a live game, and pushing a screen would stop the player moving. Under `pointer` or `both`, `pointer_key` (F3) frees the mouse and the panel restores **the mode it found**, not "captured": a 2D game or a game in a menu must not have the mouse taken by a ballot closing. A game that recaptures the mouse every frame will fight it.

**The number keys are consumed in `_input`, and only those**, and nothing at all while a `LineEdit` or `TextEdit` has focus: "gg 1" typed in chat is not a vote. A game that POLLS `Input` for weapon slots still sees the key, because the engine updates action state before any node hears the event; `ballot_input: pointer` is the server's answer for a game whose number keys matter.

**It draws itself.** Avatars travel across rows, and a container would fight every one of them; rows, labels and discs are `_draw`, and the hit test is the same rects. A picture avatar is a textured polygon (a Control cannot clip one draw call to a circle); a voter with no picture is a disc coloured from their id by golden-ratio hue, because neighbouring ids hash to neighbouring numbers and a plain modulo drew nine people in two colours. Labels are cut with an ellipsis, never mid-word.

## Deliberately not here

- **Transitions and animation.** `DotUiConfig.transition_sec` and `reduced_motion` are declared and nothing reads them. A tween that a headless test cannot observe, on a stack whose whole value is being deterministic, is a bad first thing to add.
- **Localisation.** Every string here is either a player-supplied name or a debug label. A game calls `tr()` (or dot-locale) on what it passes in.
- **Gamepad focus navigation.** `DotScreen.initial_focus` grabs focus and Godot's own focus neighbours do the rest. A focus *ring* and edge-wrapping between containers is a real design problem and half of one is worse than none.
- **A console.** dot-server has `DotConsole` and its command surface; the player's console is dot-console. Rendering it here would make dot-ui depend on dot-server.
- **A server browser.** `DotTableView` is what one is built on; the query client and list model are dot-browser's.
- **Nine-patch or textured styling.** See "ships no art". A game assigns its own `Theme` and every widget here obeys it.
- **Touch controls.** dot-player-controller ships `DotFpsTouchSampler`, which turns fingers into commands and deliberately ships no layout. The on-screen buttons are a game's design.
