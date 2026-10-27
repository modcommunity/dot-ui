# The form kit

`DotUiForm` builds a settings form from a profile schema (`DotProfileSet.field` dictionaries: name, type, default, `min`, `max`, `enum`, plus the form's own `group`, `unit`, `description`, `label`, `step`, `slider`, `secret`, `items`, `validator`) and the current values. It is the owner of the look for admin and settings forms; `DotSettingsPanel` is ported (below); dot-menu's Escape-menu rows are not.

```gdscript
var form := DotUiForm.new()
add_child(form)
var res := form.build(schema, values)            # DotResult; a bad schema or value says so
form.applied.connect(func(changes): save(changes))
```

| Type | Widget |
| --- | --- |
| `int`, `float` with `min` and `max` | slider and number entry with the unit; `slider: false` leaves the entry only |
| `int`, `float` without a range | number entry with the unit |
| `bool` | `DotFormToggle` |
| `string` with `enum` | dropdown |
| `string` | text field (`secret` masks it) |
| `color` | colour picker and hex entry |
| `list` | one text field per item, add, remove and reorder (`items` types them; `reorder: false` leaves reordering out) |
| `dict`, `any` | JSON text field |

- **Groups** are cards; `group: "Damage/Falloff"` nests one inside another. Cards collapse with a tween, and a badge counts the unsaved changes inside.
- **Validation** is inline and never reaches `values()`: an invalid entry keeps the last good value, shows its message under the field, and disables Apply (`apply()` fails with `CODE_INVALID`).
- **Reset** brings one key back to its schema default; **dirty** is any difference from the baseline; `apply()` makes the edits the baseline and emits `applied(changes)`, `revert()` drops them. `set_values` replaces the baseline.
- **Undo** (next to Reset, shown while a row differs from the baseline) puts one key back to its value when the form opened (`undo_key`, `key_undone`). On a narrow form Undo and Reset sit under the editor on every row.
- **Search** filters by key, label, description and group, opens a shut card while it matches, and Escape clears it. Ctrl+F focuses it.
- **Look**: `DotFormTokens` holds spacing, radius, type sizes, colours and elevation, and builds the `Theme` the form carries (it touches nothing outside itself). `dark()`, `light()`, `from_theme(DotUiTheme)`; `form.set_tokens()` swaps live and keeps every edit. `tokens.animate = false` makes every transition a jump (tests, screenshots).
- **Input**: every editor takes focus (ring drawn), sliders take left and right, Home and End, a toggle takes accept, so the d-pad and keyboard walk the form and the scroll follows focus. Below `compact_below` (560) rows stack and targets grow to 44 px for touch.
- Nothing is an autoload and nothing names a scene path; the only engine feature beyond Controls is `DisplayServer.is_touchscreen_available()`.

- **List reorder**: each item has a grip (mouse and touch drag; a drop on any part of another item's row lands there), up and down buttons (focusable, so the d-pad and accept move an item; focus follows it, and the end buttons are disabled) and Alt+Up / Alt+Down inside the text box. `DotFormRow.move_item(from, to)` does the same from code. A move is one edit: one `value_changed`, dirty, undone by `revert()`. On a narrow form Reset moves below the list to leave the boxes width.
- **Gamepad text entry**: a controller's accept (the south button, or `ui_accept` from a pad) on any text box (strings, numbers, JSON, colour hex, list items) opens `DotFormKeypad`, an on-screen keyboard over the form. The d-pad walks the keys and accept presses; X deletes, Y types a space, a shoulder shifts for one letter, Start confirms, cancel closes and restores the text. Edits land in the box as they are typed, so inline validation shows under the field behind the pad; a secret is masked in the preview; a number field opens on the digit and symbol page; focus cannot leave the pad and returns to the box. The keyboard's own Enter never opens it. `gamepad_entry = false` turns it off; `form.open_keypad(edit)` opens it from code (touch players have the system keyboard).

`examples/form_demo.tscn` is a weapon profile (T switches light and dark); `tools/form_screenshot.sh` renders `docs/form_dark.png`, `form_light.png`, `form_search.png`, `form_collapsed.png` and the phone-sized `form_phone_dark.png`, `form_phone_light.png`, and for the list and the keyboard `form_reorder.png`, `form_keypad.png`, `form_light_keypad.png`, `form_phone_reorder.png`, `form_phone_keypad.png`. The suite is `examples/form_selftest.tscn`.

`chrome = false` leaves out the title, search and Apply bar and lets the cards take their full height, for a host that scrolls and applies itself. `DotSettingsPanel` is exactly that: it builds a schema from a `DotConfig`'s property list (range hints become sliders, int enums become dropdowns stored by index, secrets are left out), keeps `bind`, `apply` (validate and roll back), `revert`, `refresh`, `live`, `only_groups` and its three signals, and exposes the form as `panel.form`. `editor_for(key)` now answers the form's own widget (`DotFormToggle`, `DotFormSlider`, `LineEdit`, `OptionButton`), not a `CheckBox` or `SpinBox`.

Not ported on purpose: dot-menu's Escape menu. Its rows are views of settings written on change with the game's palette themes, server clamp notes, live and custom rows and key buttons, and its suite and rules address them by name; the form's card look would drop all of that for no gain. Not done: per-row undo.
