# Progress, HUD, hit feedback, kill feed: duplication study (2026-11-07)

Item `dedupe-progress-hud-fx`. Counted on dev02 `~/godot` (main of each game; arena `wt-*` copies ignored).

| Concern | Copies per game | Existing addon class | Verdict |
| --- | --- | --- | --- |
| Hit marker | 8 HUDs build `DotHitMarker` by hand (arena, g2gfast, playlot, zombie-zone, prop-hunt, deathrun, wipeout, smash-copter) | `DotHitMarker` (dot-ui) | Class exists and is used. What repeats is the mount (new, name, full rect, mouse ignore, add_child) and the `flash` call. Moved: `DotHitFeedback` |
| Damage numbers | 4 (arena, g2gfast, playlot, zombie-zone), each next to the marker | `DotDamageNumbers` (dot-ui) | Same: class exists; the 4 `confirm_hit(victim, amount, point, killed, headshot)` bodies are identical (flash, then add). Moved with the marker |
| Kill feed | data: `DotKillFeed` (dot-match) used by arena, g2gfast. View: `DotFeedView` (dot-ui) used by hungario only; arena keeps its own `ArenaHudGlance.KillFeed` (hand-drawn rows, 1 copy) | `DotKillFeed`, `DotFeedView` | Not a copy problem. Arena's view is a single game-specific class; porting it to `DotFeedView` is a look-and-feel decision, not a byte-identical move. Leave |
| Progress (the `*_progress.gd`) | 14, 218-784 lines, all `extends Node`, no md5 matches. hs vs mm differ in 333 diff lines | none; `DotStats`/`DotAchievement` are the parts underneath | Not a progress bar: it is per-game stat ids + achievement wiring. Shared skeleton (`setup`, `record`, `_key`, `_begin`/`_end`, `leave`, `session_values`, `filed_under`, `_on_unlocked`, `describe`) with game-specific `on_*` hooks. Real candidate, but a design job (a `DotStatsProgress` base in dot-stats with `CHANNEL` and a stat table), not behaviour-identical. Next item |
| Progress bar / ring | `DotStatBar`, `DotCrosshair.hold_progress` exist; hungario, dd, lm draw `ProgressBar` for loading/beacon | `DotStatBar` | No copies to merge; loading bars are per-game screens |
| HUD (14 files, 245-1400 lines) | one extends `DotHud` (arena, hungario); rest are `Control`/`Node` built over `DotHudPiece`s | `DotHud`, `DotHudPiece` family | Per-game layout; shared parts already pieces. No byte-identical block beyond the hit feedback mount |

## Moved: DotHitFeedback (dot-ui API 21)

`DotHitFeedback.mount(parent)` adds a full-rect click-through layer holding `numbers` (under) and `marker`; `confirm_hit(victim, amount, point, killed, headshot)` and `confirm_hit_at(...)` for 2D; `clear()`. Games not switched. To switch a game: replace the two `new()`/add_child blocks and `confirm_hit` body with `hit_fx = DotHitFeedback.mount(root)` and `hit_fx.confirm_hit(...)`. Arena's `_build_feedback` and `note_hit` keep their `hit_marker`/`damage_numbers` fields as aliases (`hit_fx.marker`, `hit_fx.numbers`) because its presentation suite reads them.

## Next candidates

1. Progress skeleton base class in dot-stats (needs a diff of all 14 first).
2. Arena `KillFeed` to `DotFeedView` (needs a screenshot comparison).
