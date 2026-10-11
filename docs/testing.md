# Testing an addon that draws

## The suite

`examples/ui_selftest.tscn`, offline. `DotFeedView.expire()` and `opacity_of()` take an explicit millisecond clock so the fade can be tested without waiting out real seconds.

**Measure a size, never a property.** `set_anchors_preset(Control.PRESET_FULL_RECT)` sets the anchors and leaves the offsets alone, so a `Control` built in code keeps the zero size it was created with: invisible while being, by every property, correctly configured. Everything here uses `set_anchors_and_offsets_preset`, and the suite measures sizes because the properties were exactly what was already right.

## What a headless suite cannot see

**A headless viewport is 64 × 64.** Every screen in the suite is 64 × 64, so no assertion in any headless suite in this family can say anything about layout relative to the window: `size.y > 0` passes at 64 as happily as at 800.

Three assertions were tried against the settings panel growing past the bottom of the window, and none could fail with the bug in place:

| tried | why it passed |
| --- | --- |
| Apply is inside the panel | a `PanelContainer` **grows** to fit, so the button stays inside a panel that has itself left the window |
| Apply is inside the screen | the screen is 64 × 64 |
| a long and a short document give the same-sized panel | at 64 × 64 the layout resolves the same either way |

Each was armed by replacing the `ScrollContainer` with a plain box. None fired. What ships is the **structure plus the reason** (the rows are inside a scroll, the buttons outside it), and the real guard is the screenshot.

## The pictures

`tools/screenshot.sh` renders through `xvfb-run` to `screenshots/`: `pause.png`, `settings.png`, `hud.png` (a `DotStatBar` pair, a `DotCrosshair`, a `DotFeedView` with names of a real length), `chat.png` and `ballot.png` (mid-vote, the mouse freed, a row hovered, a crowded row, one picture among initials, the local player's choice marked). `ballot_result.png` is a six-row game ballot the local player decides with one click, closed in the same frame: their avatar must already sit on the winning row. `hud_pieces.png` is every glance piece laid out as arena lays them out, over a pale floor with a dark block, health under the low threshold, a kill marker, two damage numbers and a cover stand-in down the right edge over a hint column that must come out dimmed; `hud_pieces_light.png` is the same in `DotUiTheme.light()`, and `hud_pieces_small.png` the same HUD fitted to 854x480 (inside the outline), where nothing may meet. **Any visual change wants the affected frame rendered and looked at.** Pointing the same kind of script at a game's own screens (`game-arena/tools/screenshot_menus.sh`) has found bugs in this addon too.

**A fixture picked at random misses the state worth seeing.** Health at 28% draws in the ordinary colour because `low_fraction` is 0.25, and a bar that never goes below the threshold looks exactly like one whose `low_colour` does not work. The fixture is 18%. Pick fixtures that put each widget in the state its options exist for.
