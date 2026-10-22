# The form kit

`DotUiForm` builds a settings form from a profile schema (`DotProfileSet.field` dictionaries: name, type, default, `min`, `max`, `enum`, plus the form's own `group`, `unit`, `description`, `label`, `step`, `slider`, `secret`, `items`, `validator`) and the current values. It is the owner of the look for admin and settings forms; the older panels are ported to it over time.

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
| `list` | one text field per item, add and remove (`items` types them) |
| `dict`, `any` | JSON text field |

- **Groups** are cards; `group: "Damage/Falloff"` nests one inside another. Cards collapse with a tween, and a badge counts the unsaved changes inside.
- **Validation** is inline and never reaches `values()`: an invalid entry keeps the last good value, shows its message under the field, and disables Apply (`apply()` fails with `CODE_INVALID`).
- **Reset** brings one key back to its schema default; **dirty** is any difference from the baseline; `apply()` makes the edits the baseline and emits `applied(changes)`, `revert()` drops them. `set_values` replaces the baseline.
- **Search** filters by key, label, description and group, opens a shut card while it matches, and Escape clears it. Ctrl+F focuses it.
- **Look**: `DotFormTokens` holds spacing, radius, type sizes, colours and elevation, and builds the `Theme` the form carries (it touches nothing outside itself). `dark()`, `light()`, `from_theme(DotUiTheme)`; `form.set_tokens()` swaps live and keeps every edit. `tokens.animate = false` makes every transition a jump (tests, screenshots).
- **Input**: every editor takes focus (ring drawn), sliders take left and right, Home and End, a toggle takes accept, so the d-pad and keyboard walk the form and the scroll follows focus. Below `compact_below` (560) rows stack and targets grow to 44 px for touch.
- Nothing is an autoload and nothing names a scene path; the only engine feature beyond Controls is `DisplayServer.is_touchscreen_available()`.

`examples/form_demo.tscn` is a weapon profile (T switches light and dark); `tools/form_screenshot.sh` renders `docs/form_dark.png`, `form_light.png`, `form_search.png`, `form_collapsed.png` and the phone-sized `form_phone_dark.png`, `form_phone_light.png`. The suite is `examples/form_selftest.tscn`.

Not done: porting `DotSettingsPanel` and dot-menu's screens onto the form, per-row undo, drag reordering of list items, a gamepad on-screen keyboard for text.
