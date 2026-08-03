package main

// Gameplay and vehicle ownership outrank emotes even while development
// playback is frozen. This runs from the global frame path because the normal
// on-foot animation update is intentionally skipped in several of these states.
mouse_emote_enforce_player_priority :: proc(editor: ^Editor) {
    if editor == nil || !mouse_emote_active(&editor.mouse_emote) do return
    incompatible :=
        editor.pilot.mode != .On_Foot || !editor.in_map || !editor.player.grounded || pause_menu_is_open(editor)
    if incompatible do mouse_emote_cancel(&editor.mouse_emote)
}
