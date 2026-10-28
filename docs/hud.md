# HUD widgets and the theme

## Weapon icons

`DotIconSet` (`addons/dot_ui/icons/`) answers an icon by id, else by type tag, from a sprite sheet cut into cells, trimmed to the opaque pixels so a small sprite is not drawn small by its margin. Overrides (`override`, `load_overrides`) win over the sheet and may be per profile (`profile`); `flat` redraws every icon as one colour for a UI the pixel art would clash with; `silhouette_for` gives a flat copy to draw as a halo, which is what keeps dark sprite outlines readable on dark plates. `DotWeaponIcons.stock()` is the set with Jestan's CC0 sheet and thirty type tags; a game aliases its weapon ids to tags. Draw with `DotIconSet.pixel_perfect(canvas)` (nearest filtering) or enlarge by an integer first. Not here: which game weapon is which tag (the game's table), and the 3D view models these 2D side-on sprites cannot replace.

## Ships no art, names nothing outside dot-core

The one exception is the optional icon sheet above (18 kB, CC0, credited in `icons/jestan/CREDITS.md`).

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

## The crosshair fades while aiming down sights

Christian's first play test (2026-10-11): the dot crosshair stayed on over the iron sight, two aiming marks that disagree. `aim_source` is a `func() -> float` returning the weapon's aim fraction (zee-dot-weapons' `ZeeViewModel.aim_fraction`, bound by the game, because this addon names nothing outside dot-core), or a game pushes it with `set_aim`. The crosshair's opacity is `opacity_for_aim(fraction, aim_hide_by)`: 1 at the hip, gone by `aim_hide_by` (0.5, halfway up the raise, when the sight is what the player looks through), eased with a smoothstep; `aim_opacity` then follows that over `aim_fade_sec` (0.08 s), so a weapon switch that drops the fraction to 0 at once still fades the crosshair back in rather than snapping it. The aim fraction is itself a ramp over the weapon's aim time, so the fade tracks the raise. A scope is unaffected: the game still hides the crosshair for its own reticle. `opacity_for_aim` is static for a game that draws its own dot.

## The crosshair hides while the viewer is dead (API 14)

A dead, spectating or kill-view viewer has nothing in hand to aim, so `DotCrosshair` draws nothing unless the viewer's player is alive. `alive_source` is a `func() -> bool` read every frame (the game binds its player's `is_alive`; this addon names nothing outside dot-core), or a game pushes it with `set_alive`. Default on; `hide_when_dead = false` opts out. `is_shown()` is the one answer, shared with `_draw`.

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
- **The one chat thing it knows is the player's own block list (`!sm` / `/sm`).** `sm` must never reach the server, or the muted player could be told, and every game sends what `submitted` emits by its own path; the one place that stops it in all of them is before the signal. A line `self_mute.claims_chat()` takes is run (`handle_chat`), its reply drawn in `self_mute_colour`, and never emitted; `add_said` drops a line from a speaker `is_muted()` names, for games that draw without dot-chat's client. The list is dot-chat's `DotChatSelfMute`, found as the registry's `dot_self_mute` or by path and duck-typed, so dot-ui still depends on dot-core alone. `self_mute_enabled = false` turns both off.

## Outlines, because a game is not one colour

`DotFeedView.outline_size`, off by default, and passed through by `DotChatWindow`. White text disappears over pale ground in bright light, black text over a dark map, and a panel behind the text covers a rectangle of the thing the player is trying to see. Measured in mg-buses-from-hell (pale sand under a low sun): three chat lines in three colours, all unreadable, in a frame where every property was correct.

## A ballot on the HUD

`DotBallotPanel`: numbered options a player picks with a number key or a click, a countdown, and every voter's avatar sitting on what they chose, sliding to another row when they change their mind. It takes a dictionary (dot-vote's `DotVoteBallotView` state) and emits `chosen(index, id, command)`; what a choice turns into is the host's.

**It touches `Input.mouse_mode`, the one exception to "the stack owns it".** It is not a screen: a ballot is a widget over a live game, and pushing a screen would stop the player moving. Under `pointer` or `both`, `pointer_key` (F3) frees the mouse and the panel restores **the mode it found**, not "captured": a 2D game or a game in a menu must not have the mouse taken by a ballot closing. A game that recaptures the mouse every frame will fight it.

**The number keys are consumed in `_input`, and only those**, and nothing at all while a `LineEdit` or `TextEdit` has focus: "gg 1" typed in chat is not a vote. A game that POLLS `Input` for weapon slots still sees the key, because the engine updates action state before any node hears the event; `ballot_input: pointer` is the server's answer for a game whose number keys matter.

**A game makes room for it by reading a group, not by being told.** The panel is usually drawn by something the game did not build: a client shell's overlay over a delivered game, in a column down the right-hand side. A top-right leaderboard and a wide lot screen sat under it unread, and the shell has no way to reach into a game. So every panel is in the group `dot_hud_cover` (`DotBallotPanel.COVER_GROUP`), and a game, each frame, takes the rect of every member that `is_visible_in_tree()` (through `get_global_transform_with_canvas()`, then into its own HUD's space, because a `DotHud` is inset and scaled) and keeps its widgets off it. The game spells the group as a string: a delivered pack runs on the shell's dot-ui, and a constant an older shell lacks is a parse error where a missing group is just nothing to avoid. Any other widget that holds screen space over a game may join the same group. game-hungario (the leaderboard shrinks to fit above the column) and mg-dangerous-delivery (the lot narrows to the left of it) are the first readers.

**The local player's click outranks the server for a round trip, and a result snaps.** `choose()` moves the local avatar at once; a server state sent before the server heard the click can arrive after it, so for `PENDING_MS` (3 s), on the same options in the same order, a state that disagrees does not take the click back (one that agrees confirms it, and after that the server's word is the vote). A closed state with a result snaps every avatar onto its row: a ballot decided by the click that closes it (one voter, or the last vote needed) is drawn a frame or two after the click, and a rendered game-vote frame showed the voter's avatar mid-slide, a row short of the marked "Don't change". Without the hold, a stale state followed by a close on the click left the result showing the voter on the row they had left, with nothing after it to correct it.

**It draws itself.** Avatars travel across rows, and a container would fight every one of them; rows, labels and discs are `_draw`, and the hit test is the same rects. A picture avatar is a textured polygon (a Control cannot clip one draw call to a circle); a voter with no picture is a disc coloured from their id by golden-ratio hue, because neighbouring ids hash to neighbouring numbers and a plain modulo drew nine people in two colours. Labels are cut with an ellipsis, never mid-word.

## The glance pieces

`DotVitals`, `DotAmmoCounter`, `DotScoreStrip`, `DotHitMarker`, `DotDamageNumbers`, `DotKeyPrompt` and `DotKeyHints`, all on `DotHudPiece`. They were game-arena's "glance" HUD (`game/arena_hud_glance.gd` and the feedback classes in `arena_hud.gd`, 2026-10-10), and moved here once more than one game drew its own version of each.

- **Values in, never a game object.** Each piece draws from what it is handed (`show_vitals`, `show_ammo`, `show_clock`, `flash`, `add`), so a suite drives one alone and a render tool puts one up with chosen numbers. The host reads its game once a frame.
- **Readable over a pale map.** Bold text with an outline in the theme's `ink`, on a translucent `plate`. The first arena HUD drew thin regular-weight text straight over white tiles and the health, ammunition and key hints all but vanished.
- **Theme-driven, with defaults that need no theme.** Colours are theme colours on the type `DotHudPiece` (`COLOUR_KEYS`: `plate`, `plate_edge`, `text`, `dim`, `low`, `good`, `highlight`, `ink`, `keycap`, `keycap_text`, `keycap_edge`) and one constant, `team_fill` (how much of a side's colour fills its score plate, in percent); an absent one is `DotHudPiece.DEFAULTS` / `DEFAULT_CONSTANTS`. `DotUiTheme.build()` fills every one from its palette (`highlight` is a palette colour), and makes `ink` the background, so a light palette draws dark numbers ringed in light. A theme `font` set on the type itself replaces the emboldened fallback font; it is looked up by name through the themes up the tree (`_theme_font`), never with `has_theme_font`, which answers yes for any name once a theme has a default font, as the engine's always does.
- **The default is the dark HUD.** Christian's first play test (2026-10-11) found arena's HUD "too similar to" a block-built platform shooter: pale see-through plates, white key caps, score plates painted bright blue and red. The defaults are now deep plates at 0.74 alpha, white words ringed in black, dark key caps with a light letter and a faint edge, and score plates tinted (`team_fill` 38) with the side's colour as the edge and a bar along the top. The bright look is a theme a player can pick (dot-menu's "Arcade": `team_fill` 100, white caps), never the default.
- **A whole layer follows one theme, live.** `DotHudPiece.theme_from(colours, constants)` builds the `Theme` a game sets on the node above its pieces; every piece reads its colours when it draws, so setting a new one restyles the layer with nothing rebuilt. It also gives every plain `Label` under that node the theme's text colour outlined in its ink, because a game's own HUD lines are Labels and four games' were pale and unreadable over pale maps in the play test; a Label with its own colour keeps it and still gets the outline. dot-menu's themes hand a game's root this theme on every theme change (`DotMenu.follow_hud`); a game's accent (`highlight`, `plate_edge`) is laid over it, so each game keeps its colour in every theme. `DotUiTheme` does not use it for its own whole-interface `Theme`: an outline on every menu Label is wrong.
- **The player's size.** `DotHud.user_scale` multiplies the fit (dot-menu's `hud_scale` setting, 0.7 to 1.4); a plain `Control` root is scaled the same way through `DotHud.fit_control`, top-left anchored and sized to the frame divided by the scale so its children's anchors still reach the edges.
- **Scaled with the HUD, never laid out again.** Every number is in the HUD's units. `DotHud.fit_design` (1280x720 for these pieces) makes a `DotHud` place itself by hand and scale the whole layer by `DotHud.fit_scale` on a smaller frame (the short side's share, never under `fit_min`, never above 1). Arena found the need standalone at 854x480, where the pieces ran into each other; one scale keeps every piece and every distance between them, and is the same answer a client shell's 1280x720 canvas gives. Zero, the default, is the old full-rect anchoring.
- **Out from under a ballot.** Each frame a piece reads every visible member of `dot_hud_cover` (the string, `DotHudPiece.COVER_GROUP`, for the reason in [a ballot on the HUD](#a-ballot-on-the-hud)) into its own space through the canvas transforms, and where one meets its `footprint()` does what `cover_mode` says: `DIM` (the default, to `cover_alpha`), `HIDE` or `IGNORE`. **Each cover is tested on its own**: merged, two covers in opposite corners cover everything between them (the first suite run found exactly that with a ballot left over from an earlier section). The hit marker and damage numbers are full-rect and default to `IGNORE`, since their rect always meets a cover. `DotHudPiece.covered_rect()` (merged) is for a host that moves its own widgets out of the way, as arena's weapon slots do.
- **Every piece says where it draws** (`footprint()`, its own space). A host collects them to check that no two meet at several frame sizes, which is how arena's layout check works.
- `DotVitals` eases the bar and never the number, exponentially, for the reason `DotStatBar` does; a first value is drawn at once, not eased in from full. A `bonus` (health that drains away) is drawn after the real fill, a `status` ("DOWN") replaces the number, and health is rounded up, because a player on 0.4 is alive.
- `DotScoreStrip.clock_text` rounds up, so a clock never says 0:00 with time left; arena's own clock rounded down. The score plates are optional: seven games draw a clock alone.
- `DotHitMarker` is flashed by the host from a hit the server confirmed, never the local prediction; a non-lethal hit does not turn a fresh kill marker white (pellets after the lethal one).
- `DotDamageNumbers` projects a world point through the viewport's camera (or `camera`) every frame, so a number stays on the body as the view moves; `add_at` takes a point in its own space for a 2D game. Hits on one victim within `merge_sec` add up.
- `DotKeyPrompt` and `DotKeyHints` take the key's name from the host (the player's binding as text), never a letter written into the game.

### Which pieces moved, and which stayed in game-arena

Decided 2026-10-11 by grepping every game's HUD for its own version (`dot-ui-hud-pieces-1`). "Draws its own" is a hand-rolled equivalent today; "wants" is a game with the need and nothing on screen.

| Arena piece | Games that would use it | Decision | Why |
| --- | --- | --- | --- |
| `Vitals` (+ two `DotStatBar`s) | arena; game-zombie-zone (bar, borrowed health, DOWN/DEAD); mg-smash-copter, mg-buses-from-hell, mg-wipeout, mg-deathrun (a bare number `Label`, red under a quarter); mg-prop-hunt (number on its disc) | moved: `DotVitals` | seven games draw health, each its own way |
| `AmmoCounter` | arena; game-zombie-zone (`"%d / ∞"` label); game-playground wants one (carries the weapon pack, shows no count) | moved: `DotAmmoCounter` | three games; the endless reserve is zombie-zone's |
| `ScoreStrip` | arena (scores and clock); game-hide-n-seek, mg-prop-hunt, mg-smash-copter, mg-buses-from-hell, mg-wipeout, mg-deathrun, game-zombie-zone, game-hungario (a centred `"%d:%02d"` label) | moved: `DotScoreStrip`, plates optional | nine games draw a clock |
| `HitMarker` | arena; wanted by game-playground, game-g2gfast (combat maps) and game-zombie-zone, which all fire the weapon pack and confirm no hit on screen | moved: `DotHitMarker` | three more shooters |
| `DamageNumbers` | arena; the same three | moved: `DotDamageNumbers`, plus `add_at` for 2D | same consumers as the marker |
| `Prompt` | arena; game-hide-n-seek (door), mg-deathrun (trap), mg-look-at-me (`"[E] …"`), mg-prop-hunt (`"press %s"`), game-zombie-zone (kits) | moved: `DotKeyPrompt` | five games write the key into a sentence |
| `KeyHints` | arena; game-zombie-zone's kit line | moved: `DotKeyHints` | the prompt's keycap, and a second game |
| `make_room` / `covered_rect` | arena, game-hungario and mg-dangerous-delivery each read `dot_hud_cover` by hand | moved: `DotHudPiece.cover_mode`, `cover_rects`, `covered_rect` | three readers of one group |
| `fit_scale` / `fit_to_frame` | arena (HUD and chat box) | moved: `DotHud.fit_design`, `fit_scale`, `fit_to_frame` | every piece above is drawn in a 1280x720 design |
| `KillFeed` (weapon silhouettes) | arena; game-hungario uses `DotFeedView` | stays in arena | `DotFeedView` is the shared feed; the silhouettes are arena's generated art and no other game has weapon icons. An icon fragment in `DotFeedView` is the move when one does |
| `Portraits` + `PortraitCache` | arena | stays | renders arena's avatar rig into viewports; the ranked row can move once dot-user-avatar renders heads |
| `WeaponSlots` | arena | stays | arena's silhouettes, and its ballot tightening is tuned to arena's column; no other game shows carried slots |
| `AbilityBar` | arena | stays | arena's movement abilities |
| `MedalRow` | arena | stays | draws arena's medal enum and icons; no second game awards medals |
| `StreakMeter` | arena | stays | killstreaks are arena's |

**An extraction is finished when the last caller moves.** Each game above with a hand-rolled equivalent has a queue item `hud-pieces-<game>-1`; until it is done that game still draws its own, arena included.

## Deliberately not here

- **Transitions and animation.** `DotUiConfig.transition_sec` and `reduced_motion` are declared and nothing reads them. A tween that a headless test cannot observe, on a stack whose whole value is being deterministic, is a bad first thing to add.
- **Localisation.** Every string here is either a player-supplied name or a debug label. A game calls `tr()` (or dot-locale) on what it passes in.
- **Gamepad focus navigation.** `DotScreen.initial_focus` grabs focus and Godot's own focus neighbours do the rest. A focus *ring* and edge-wrapping between containers is a real design problem and half of one is worse than none.
- **A console.** dot-server has `DotConsole` and its command surface; the player's console is dot-console. Rendering it here would make dot-ui depend on dot-server.
- **A server browser.** `DotTableView` is what one is built on; the query client and list model are dot-browser's.
- **Nine-patch or textured styling.** See "ships no art". A game assigns its own `Theme` and every widget here obeys it.
- **Touch controls.** dot-player-controller ships `DotFpsTouchSampler`, which turns fingers into commands and deliberately ships no layout. The on-screen buttons are a game's design.
