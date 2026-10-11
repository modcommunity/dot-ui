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
const LEVEL := 3
const OLDEST := 1
