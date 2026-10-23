extends RefCounted

## dot-ui's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.

# 1: everything before this file existed (an absent file reads as 1).
# 2: DotInputBinding names the wheel and the side buttons ("Wheel up", "Mouse back";
#    MOUSE_NAMES, mouse_text) and still reads the old "Mouse 4". A game that wrote its own
#    "(wheel up)" beside a "Mouse 4" can ask for this level before dropping it.
# 3: DotChatWindow honours the player's own block list: self_mute, self_mute_enabled,
#    self_mute_colour, is_self_muted(); `!sm` / `/sm` are run and never emitted.
# 4: the glance pieces: DotHudPiece (theme colours, footprint, cover_mode, cover_rects,
#    covered_rect), DotVitals, DotAmmoCounter, DotScoreStrip, DotHitMarker,
#    DotDamageNumbers, DotKeyPrompt, DotKeyHints; DotHud.fit_design, fit_min, fit_scale,
#    fit, fit_to_frame; DotUiTheme.highlight and the DotHudPiece theme colours.
# 5: DotCrosshair fades out while aiming down sights: aim_source, set_aim(), aim_hide_by,
#    aim_fade_sec, aim_opacity, follow_aim(), opacity_for_aim().
# 6: the dark HUD and themes a game can switch live: DotHudPiece.theme_from(), number(),
#    COLOUR_KEYS, DEFAULT_CONSTANTS, the keycap_edge colour and the team_fill constant (the
#    defaults are now the dark HUD); DotHud.user_scale and fit_control().
# 7: the schema form kit: DotUiForm, DotFormTokens, DotFormSchema, DotFormRow, DotFormGroup,
#    DotFormSlider, DotFormToggle (addons/dot_ui/form/).
# 8: the form kit's list reorder (DotFormRow.move_item, the schema key `reorder`) and
#    gamepad text entry (DotFormKeypad, DotUiForm.open_keypad, keypad, gamepad_entry).
# 9: DotWinnerReveal, the end-of-match winner and podium (addons/dot_ui/screens/).
const LEVEL := 9
const OLDEST := 1
