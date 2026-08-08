package main

import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import dialogue "../packages/dialogue"
import dialogue_session "../packages/dialogue_session"
import flight "../packages/flight"
import libellula_game "../packages/libellula"
import story "../packages/story"
import tarot "../packages/tarot"
import terrain "../packages/terrain"
import "core:fmt"
import "core:math"
import "core:time"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import game_input "zelda_engine:game_input"
import third_person "zelda_engine:third_person"

attendant_spawn_position :: proc(editor: ^Editor, _: third_person.Vec3) -> third_person.Vec3 {
    // Marta works the reception counter in the east airport terminal, whose
    // forecourt is a node on the runway-to-town access road.
    x, z := terrain.default_airport_center_for_project(&editor.project, 1)
    return {x, terrain.sample_surface_height(&editor.project, 0, x, z), z}
}

@(no_instrumentation)
libellula_vertex_world :: #force_inline proc(
    runtime: ^libellula_game.Runtime,
    position: [3]f32,
    scale: f32,
) -> third_person.Vec3 {
    return world_model_vertex_world(world_aircraft_transform(runtime.body, scale), position)
}

gerta_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    x, z := terrain.default_airport_center_for_project(&editor.project, -1)
    return {x, terrain.sample_surface_height(&editor.project, 0, x, z), z}
}

attendant_speaker :: proc(_: ^dialogue.Context) -> string { return "MARTA" }
gerta_speaker :: proc(_: ^dialogue.Context) -> string { return "GERTA" }
attendant_menu_text :: proc(ctx: ^dialogue.Context) -> string {
    editor := attendant_context_editor(ctx)
    if editor != nil && editor.story_state.airfield_errand == .Not_Offered {
        return(
            "Questo magneto has una fine crack, comme a hair. Gerta keeps un replacement on west island; she must inspect the old magneto before she trusts it." \
        )
    }
    if editor != nil && editor.story_state.airfield_errand == .Completed {
        return "Ciao. The replacement magneto starts before my coffee now. How can io help vous?"
    }
    return "Ciao. How can io help vous?"
}
gerta_menu_text :: proc(ctx: ^dialogue.Context) -> string {
    editor := attendant_context_editor(ctx)
    if editor != nil && editor.story_state.airfield_errand == .Westbound {
        return(
            "Ja, same series. Marta keeps ogni machine until it becomes family. Take the replacement magneto—and do not let il mare taste it." \
        )
    }
    if editor != nil && editor.story_state.airfield_errand == .Completed {
        return(
            "Dobar dan. Marta reports the replacement magneto behaves—her word, not mine. What can sua sister do for you?" \
        )
    }
    return "Dobar dan. Marta manages the east apron; what can sua sister do for you?"
}
attendant_magneto_accept_text :: proc(_: ^dialogue.Context) -> string {
    return(
        "Wrap the broken magneto in this oilcloth, dobro, then bring it to Gerta on west island. She trusts a machine after inspection—and a courier after dry socks." \
    )
}
gerta_magneto_handoff_text :: proc(_: ^dialogue.Context) -> string {
    return(
        "Same series, stessa stubborn crack. Marta kept the old magneto running two summers past reason; naturally, it waited for her to be correct. Take this replacement magneto east." \
    )
}
attendant_magneto_return_text :: proc(_: ^dialogue.Context) -> string {
    return(
        "Gerta's replacement magneto, dry as a ledger. Und this knot is hers—she still thinks io open parcels with my teeth. Grazie; the aeroplano can return to work." \
    )
}
attendant_magneto_memory_text :: proc(ctx: ^dialogue.Context) -> string {
    if ctx == nil do return ""
    return story.magneto_memory_text(story.Resident(ctx.resident_index))
}
attendant_magneto_favor_marta_text :: proc(ctx: ^dialogue.Context) -> string {
    if ctx == nil do return ""
    return story.magneto_opinion_text(story.Resident(ctx.resident_index), .Marta)
}
attendant_magneto_favor_gerta_text :: proc(ctx: ^dialogue.Context) -> string {
    if ctx == nil do return ""
    return story.magneto_opinion_text(story.Resident(ctx.resident_index), .Gerta)
}
attendant_magneto_accept_careful_text :: proc(_: ^dialogue.Context) -> string {
    return story.magneto_accept_careful_text()
}
attendant_magneto_accept_inspection_text :: proc(_: ^dialogue.Context) -> string {
    return story.magneto_accept_inspection_text()
}
attendant_magneto_handoff_crack_text :: proc(_: ^dialogue.Context) -> string {
    return story.magneto_handoff_crack_text()
}
attendant_magneto_handoff_marta_text :: proc(_: ^dialogue.Context) -> string {
    return story.magneto_handoff_marta_text()
}
attendant_magneto_return_dry_text :: proc(_: ^dialogue.Context) -> string {
    return story.magneto_return_dry_text()
}
attendant_magneto_return_knot_text :: proc(_: ^dialogue.Context) -> string {
    return story.magneto_return_knot_text()
}
attendant_aircraft_text :: proc(_: ^dialogue.Context) -> string {
    return "Which aeroplano should io place on la line?"
}

attendant_context_editor :: proc(ctx: ^dialogue.Context) -> ^Editor {
    if ctx == nil || ctx.data == nil do return nil
    return cast(^Editor)ctx.data
}

attendant_local_news_text :: proc(ctx: ^dialogue.Context) -> string {
    editor := attendant_context_editor(ctx)
    if editor == nil do return "Le islands are tranquil, which never means nobody is occupied."
    gerta := ctx.resident_index == int(story.Resident.Gerta)
    switch editor.story_state.romance {
    case .Unintroduced:
        if gerta do return "Niko lights les ovens before the gulls.\nRecently he watches la east lamp between two trays."
        return "Iva prepares la lighthouse lamp very early.\nDue flashes before alba, regular as una promise."
    case .First_Letter:
        if gerta do return "Niko has farina on his sleeves, mais zero on la cardamom box.\nMake of that what you will."
        return "Iva received posta from west island.\nThe lighthouse is no brighter, although elle insists."
    case .Corresponding:
        if gerta do return "Les regatta awnings are going up.\nNiko inspects la blue one enough to call it maintenance."
        return "Le letters cross la bay faster than fishing boats.\nIva seals them very well, avant you ask."
    case .Invitation:
        if editor.story_state.repair == .Repaired {
            if gerta do return "Bojan's aeroplano is healthy again.\nHe cleaned la passenger seat, donc this flight matters."
            return "Iva can attend la regatta, now that Bojan's wing is repaired.\nElle checked il meteo three times."
        }
        if gerta do return "Bojan's canvas wing needs honest work.\nLa dishonest explanation, he already supplied."
        return "Iva must be somewhere beyond il mare.\nBojan's aeroplano still carries daylight through una wing."
    case .Meeting:
        if gerta do return "Iva arrived safe and sana.\nNiko calls the extra pane an accounting error."
        return "Iva says la view under the blue awning on west island\nis quasi beautiful enough to replace her lamp."
    case .Together:
        if gerta do return "Niko und Iva still send packages across la bay.\nApparently, meeting someone only improves la posta."
        return "Pane goes east, lamp glass goes west.\nSolo the courier does not know what la dinner note says."
    }
    return ""
}

attendant_local_news_warm_text :: proc(ctx: ^dialogue.Context) -> string {
    if ctx == nil do return ""
    return story.airfield_news_warm_text(story.Resident(ctx.resident_index))
}

attendant_local_news_discreet_text :: proc(ctx: ^dialogue.Context) -> string {
    if ctx == nil do return ""
    return story.airfield_news_discreet_text(story.Resident(ctx.resident_index))
}

attendant_weather_text :: proc(ctx: ^dialogue.Context) -> string {
    editor := attendant_context_editor(ctx)
    if editor == nil do return "Inspect il mare before believing any forecast."
    weather := editor.atmosphere.weather
    wind_speed := f32(math.sqrt(f64(weather.wind[0] * weather.wind[0] + weather.wind[1] * weather.wind[1])))
    gerta := ctx.resident_index == int(story.Resident.Gerta)
    if weather.precipitation > .55 || weather.severity > .72 {
        if gerta do return "Un hard front crosses la bay.\nStay below les clouds et leave your pride on the apron."
        return "La tempesta rain approaches.\nLe lighthouse works; that does not mean you must test it."
    }
    if wind_speed > 7 || weather.cloud_cover > .48 {
        if gerta do return "Il vento is alive above the west ridge.\nGive space to les cliffs et expect a crosswind on return."
        return "Broken clouds und firm vento over la bay.\nFlyable, if you let l'aria have the last word."
    }
    if editor.atmosphere.world_minutes < 6 * 60 || editor.atmosphere.world_minutes > 19 * 60 {
        if gerta do return "Night aria is clear; les runway lights earn their money.\nAttention to fog over il mare oscuro."
        return "La night is calm.\nKeep Iva's lamp on the left when flying east."
    }
    if gerta do return "Clear enough to see east island from the west apron.\nLa bay is very cooperative today."
    return "Light vento und open mare.\nBuen day for flight, although les gulls take the credit."
}

marta_menu_set_result :: proc(ctx: ^dialogue.Context, result: dialogue_session.Airfield_Result) {
    if ctx == nil || ctx.data == nil do return
    editor := cast(^Editor)ctx.data
    _ = dialogue_session.set_airfield(&editor.dialogue_session, result)
}

marta_menu_paint :: proc(ctx: ^dialogue.Context) { marta_menu_set_result(ctx, .Paint_Aircraft) }
marta_menu_close :: proc(ctx: ^dialogue.Context) { marta_menu_set_result(ctx, .Close) }
record_airfield_weather_reading :: proc(ctx: ^dialogue.Context) {
    if editor := attendant_context_editor(ctx); editor != nil {
        _ = story.complete_weather_reading(&editor.story_state)
    }
}

can_accept_marta_magneto :: proc(ctx: ^dialogue.Context) -> bool {
    editor := attendant_context_editor(ctx)
    return(
        editor != nil &&
        ctx.resident_index == int(story.Resident.Marta) &&
        editor.story_state.airfield_errand == .Not_Offered \
    )
}

can_handoff_gerta_magneto :: proc(ctx: ^dialogue.Context) -> bool {
    editor := attendant_context_editor(ctx)
    return(
        editor != nil &&
        ctx.resident_index == int(story.Resident.Gerta) &&
        editor.story_state.airfield_errand == .Westbound \
    )
}

can_return_marta_magneto :: proc(ctx: ^dialogue.Context) -> bool {
    editor := attendant_context_editor(ctx)
    return(
        editor != nil &&
        ctx.resident_index == int(story.Resident.Marta) &&
        editor.story_state.airfield_errand == .Eastbound \
    )
}

can_revisit_magneto :: proc(ctx: ^dialogue.Context) -> bool {
    editor := attendant_context_editor(ctx)
    return editor != nil && editor.story_state.airfield_errand == .Completed
}

accept_marta_magneto :: proc(ctx: ^dialogue.Context) {
    if editor := attendant_context_editor(ctx); editor != nil {
        _ = story.accept_airfield_errand(&editor.story_state)
    }
}

handoff_gerta_magneto :: proc(ctx: ^dialogue.Context) {
    if editor := attendant_context_editor(ctx); editor != nil {
        _ = story.handoff_broken_magneto(&editor.story_state)
    }
}

return_marta_magneto :: proc(ctx: ^dialogue.Context) {
    if editor := attendant_context_editor(ctx); editor != nil {
        _ = story.return_replacement_magneto(&editor.story_state)
    }
}

dialogue_session_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.attendant_dialogue = {}
    editor.attendant_dialogue_open = false
    editor.attendant_dialogue_focus = 0
    dialogue_session.clear(&editor.dialogue_session)
    editor.attendant_dialogue_vehicle_target = {}
    editor.attendant_dialogue_vehicle_choices = {}
    editor.attendant_dialogue_vehicle_choice_count = 0
}

open_attendant_dialogue :: proc(editor: ^Editor, resident: story.Resident = .Marta) {
    if editor == nil || (resident != .Marta && resident != .Gerta) do return
    attendant_dialogue_definition_release(editor)
    menu_choices := make([]dialogue.Choice, 9)
    menu_choices[0] = dialogue.choice(
        "I can bring the broken magneto to Gerta.",
        4,
        condition = can_accept_marta_magneto,
        effect = accept_marta_magneto,
    )
    menu_choices[1] = dialogue.choice(
        "Give Gerta the broken magneto.",
        5,
        condition = can_handoff_gerta_magneto,
        effect = handoff_gerta_magneto,
    )
    menu_choices[2] = dialogue.choice(
        "Give Marta the replacement magneto.",
        6,
        condition = can_return_marta_magneto,
        effect = return_marta_magneto,
    )
    menu_choices[3] = dialogue.choice("How is the replacement magneto behaving?", 7, condition = can_revisit_magneto)
    menu_choices[4] = dialogue.choice("Paint an aeroplane", dialogue.no_next_node, effect = marta_menu_paint)
    menu_choices[5] = dialogue.choice("Choose an aeroplane", 1)
    menu_choices[6] = dialogue.choice("Any local news?", 2)
    menu_choices[7] = dialogue.choice("How is the weather?", 3, effect = record_airfield_weather_reading)
    menu_choices[8] = dialogue.choice("Nothing, grazie.", dialogue.no_next_node, effect = marta_menu_close)

    editor.attendant_dialogue_vehicle_choice_count = 0
    airfield_aircraft_count := 0
    for slot in editor.aircraft.slots[:editor.aircraft.count] {
        if slot.kind != .Rondine do airfield_aircraft_count += 1
    }
    aircraft_choices := make([]dialogue.Choice, airfield_aircraft_count + 1)
    for slot in editor.aircraft.slots[:editor.aircraft.count] {
        if slot.kind == .Rondine do continue
        index := editor.attendant_dialogue_vehicle_choice_count
        aircraft_choices[index] = dialogue.choice(slot.name, dialogue.no_next_node)
        editor.attendant_dialogue_vehicle_choices[index] = slot.kind
        editor.attendant_dialogue_vehicle_choice_count += 1
    }
    aircraft_choices[airfield_aircraft_count] = dialogue.choice("Back", 0)
    local_news_choices := make([]dialogue.Choice, 2)
    local_news_choices[0] = dialogue.choice("They seem to be finding their way.", 10)
    local_news_choices[1] = dialogue.choice("These islands notice everything.", 11)
    weather_back_choices := make([]dialogue.Choice, 1)
    weather_back_choices[0] = dialogue.choice("Grazie. Anything else?", 0)
    local_news_warm_close_choices := make([]dialogue.Choice, 1)
    local_news_warm_close_choices[0] = dialogue.choice("Anything else before I go?", 0)
    local_news_discreet_close_choices := make([]dialogue.Choice, 1)
    local_news_discreet_close_choices[0] = dialogue.choice("Anything else before I go?", 0)
    magneto_accept_choices := make([]dialogue.Choice, 2)
    magneto_accept_choices[0] = dialogue.choice("I'll protect the oilcloth and magneto.", 16)
    magneto_accept_choices[1] = dialogue.choice("Does Gerta inspect couriers too?", 17)
    magneto_accept_careful_close_choices := make([]dialogue.Choice, 1)
    magneto_accept_careful_close_choices[0] = dialogue.choice("West island, then.")
    magneto_accept_inspection_close_choices := make([]dialogue.Choice, 1)
    magneto_accept_inspection_close_choices[0] = dialogue.choice("I'll arrive with dry socks.")
    magneto_handoff_choices := make([]dialogue.Choice, 2)
    magneto_handoff_choices[0] = dialogue.choice("The crack is finer than it looked.", 12)
    magneto_handoff_choices[1] = dialogue.choice("Marta kept it going a long time.", 13)
    magneto_return_choices := make([]dialogue.Choice, 2)
    magneto_return_choices[0] = dialogue.choice("The replacement stayed dry.", 14)
    magneto_return_choices[1] = dialogue.choice("Gerta tied the knot twice.", 15)
    magneto_handoff_crack_close_choices := make([]dialogue.Choice, 1)
    magneto_handoff_crack_close_choices[0] = dialogue.choice("I'll take the replacement magneto east.")
    magneto_handoff_marta_close_choices := make([]dialogue.Choice, 1)
    magneto_handoff_marta_close_choices[0] = dialogue.choice("I'll take the replacement magneto east.")
    magneto_return_dry_close_choices := make([]dialogue.Choice, 1)
    magneto_return_dry_close_choices[0] = dialogue.choice("Let's hear it start.")
    magneto_return_knot_close_choices := make([]dialogue.Choice, 1)
    magneto_return_knot_close_choices[0] = dialogue.choice("Let's hear it start.")
    magneto_memory_choices := make([]dialogue.Choice, 2)
    magneto_memory_choices[0] = dialogue.choice("Marta was right about the old magneto.", 8)
    magneto_memory_choices[1] = dialogue.choice("Gerta was right to replace the magneto.", 9)
    magneto_marta_close_choices := make([]dialogue.Choice, 1)
    magneto_marta_close_choices[0] = dialogue.choice("I'll preserve the diplomatic version.")
    magneto_gerta_close_choices := make([]dialogue.Choice, 1)
    magneto_gerta_close_choices[0] = dialogue.choice("I'll preserve the diplomatic version.")

    nodes := make([]dialogue.Node, 18)
    speaker := resident == .Gerta ? gerta_speaker : attendant_speaker
    menu_text := resident == .Gerta ? gerta_menu_text : attendant_menu_text
    nodes[0] = dialogue.node("services", menu_text, menu_choices, speaker)
    nodes[1] = dialogue.node("aircraft", attendant_aircraft_text, aircraft_choices, speaker)
    nodes[2] = dialogue.node("local-news", attendant_local_news_text, local_news_choices, speaker)
    nodes[3] = dialogue.node("weather", attendant_weather_text, weather_back_choices, speaker)
    nodes[4] = dialogue.node("magneto-accepted", attendant_magneto_accept_text, magneto_accept_choices, speaker)
    nodes[5] = dialogue.node("magneto-handoff", gerta_magneto_handoff_text, magneto_handoff_choices, speaker)
    nodes[6] = dialogue.node("magneto-returned", attendant_magneto_return_text, magneto_return_choices, speaker)
    nodes[7] = dialogue.node("magneto-memory", attendant_magneto_memory_text, magneto_memory_choices, speaker)
    nodes[8] = dialogue.node(
        "magneto-favor-marta",
        attendant_magneto_favor_marta_text,
        magneto_marta_close_choices,
        speaker,
    )
    nodes[9] = dialogue.node(
        "magneto-favor-gerta",
        attendant_magneto_favor_gerta_text,
        magneto_gerta_close_choices,
        speaker,
    )
    nodes[10] = dialogue.node(
        "local-news-warm",
        attendant_local_news_warm_text,
        local_news_warm_close_choices,
        speaker,
    )
    nodes[11] = dialogue.node(
        "local-news-discreet",
        attendant_local_news_discreet_text,
        local_news_discreet_close_choices,
        speaker,
    )
    nodes[12] = dialogue.node(
        "magneto-handoff-crack",
        attendant_magneto_handoff_crack_text,
        magneto_handoff_crack_close_choices,
        speaker,
    )
    nodes[13] = dialogue.node(
        "magneto-handoff-marta",
        attendant_magneto_handoff_marta_text,
        magneto_handoff_marta_close_choices,
        speaker,
    )
    nodes[14] = dialogue.node(
        "magneto-return-dry",
        attendant_magneto_return_dry_text,
        magneto_return_dry_close_choices,
        speaker,
    )
    nodes[15] = dialogue.node(
        "magneto-return-knot",
        attendant_magneto_return_knot_text,
        magneto_return_knot_close_choices,
        speaker,
    )
    nodes[16] = dialogue.node(
        "magneto-accept-careful",
        attendant_magneto_accept_careful_text,
        magneto_accept_careful_close_choices,
        speaker,
    )
    nodes[17] = dialogue.node(
        "magneto-accept-inspection",
        attendant_magneto_accept_inspection_text,
        magneto_accept_inspection_close_choices,
        speaker,
    )
    definition := new(dialogue.Definition)
    definition^ = {
        id         = resident == .Gerta ? "gerta_services" : "marta_services",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(
        definition,
        {data = rawptr(editor), location_id = "airfield", resident_index = int(resident)},
    )
    if opened {
        story.acknowledge_resident_action(&editor.story_state, resident)
        dialogue_session.begin(&editor.dialogue_session, .Airfield_Services)
        editor.dialogue_resident = resident
        editor.attendant_dialogue = conversation
        editor.attendant_dialogue_open = true
        editor.attendant_dialogue_focus = 0
        dialogue_view_reset(editor)
        game_input.reset_menu_repeat(&editor.runtime_input)
        set_pointer_locked(false)
        _ = sdl.ShowCursor()
    }
}

attendant_dialogue_definition_release :: proc(editor: ^Editor) {
    if editor == nil do return
    if definition := editor.attendant_dialogue.definition; definition != nil {
        switch editor.dialogue_session.kind {
        case .Airfield_Services:
            // Airfield definitions own one distinct choice slice per node.
            for &node in definition.nodes do delete(node.choices)
            delete(definition.nodes)
            free(definition)
        case .Marina_Dockmaster:
            // Marina definitions own one distinct choice slice per node.
            for &node in definition.nodes do delete(node.choices)
            delete(definition.nodes)
            free(definition)
        case .None, .Story:
        // Story definitions and their choice slices belong to story.Catalog.
        }
    }
    dialogue_session_reset(editor)
}

open_story_dialogue :: proc(editor: ^Editor, resident: story.Resident) -> bool {
    if editor == nil || resident == .Marta || resident == .Gerta do return false
    if resident == .Toma || resident == .Lena {
        _ = player_mail_collect(editor)
    }
    attendant_dialogue_definition_release(editor)
    definition: ^dialogue.Definition
    switch resident {
    case .Niko:
        definition = &editor.story_catalog.niko
    case .Iva:
        definition = &editor.story_catalog.iva
    case .Bojan:
        definition = &editor.story_catalog.bojan
    case .Zora:
        definition = &editor.story_catalog.zora
    case .Vesna:
        definition = &editor.story_catalog.vesna
    case .Petar:
        definition = &editor.story_catalog.petar
    case .Anica:
        definition = &editor.story_catalog.anica
    case .Toma:
        definition = &editor.story_catalog.toma
    case .Lena:
        definition = &editor.story_catalog.lena
    case .Mirna:
        definition = &editor.story_catalog.mirna
    case .Marta, .Gerta:
        return false
    }
    conversation, opened := dialogue.open(definition, {
        data           = rawptr(&editor.story_state),
        location_id    = resident == .Vesna || resident == .Petar || resident == .Anica ? "clinic" : (resident == .Iva || resident == .Zora || resident == .Mirna ? "east_island" : "west_island"),
        resident_index = int(resident),
    })
    if !opened do return false
    story.acknowledge_resident_action(&editor.story_state, resident)
    dialogue_session.begin(&editor.dialogue_session, .Story)
    editor.attendant_dialogue = conversation
    editor.attendant_dialogue_open = true
    editor.attendant_dialogue_focus = 0
    editor.dialogue_resident = resident
    dialogue_view_reset(editor)
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    return true
}

attendant_dialogue_panel :: proc(editor: ^Editor, width, height: i32) -> canvas2d.Rectangle {
    choice_count := editor == nil ? 0 : dialogue.available_count(&editor.attendant_dialogue)
    return dialogue_tv_layout(width, height, choice_count).conversation
}

tarot_layout_draw :: proc(editor: ^Editor, panel: canvas2d.Rectangle) {
    if editor == nil || editor.dialogue_resident != .Zora do return
    current := dialogue.current(&editor.attendant_dialogue)
    if current == nil || current.id != "zora-reading" do return
    layout := &editor.story_state.tarot_layout
    if layout.count == 0 do return
    columns := layout.count <= 3 ? layout.count : 5
    card_width := layout.count <= 3 ? f32(126) : f32(100)
    art_height := card_width * 158 / 108
    label_height := layout.count <= 3 ? f32(46) : f32(40)
    gap := f32(10)
    card_height := art_height + label_height
    board_width := f32(columns) * card_width + f32(columns - 1) * gap + 24
    rows := (layout.count + columns - 1) / columns
    board_height := f32(rows) * card_height + f32(rows - 1) * gap + 42
    board := canvas2d.Rectangle {
        x      = panel.x + (panel.width - board_width) * .5,
        y      = max(f32(18), panel.y - board_height - 12),
        width  = board_width,
        height = board_height,
    }
    canvas2d.DrawRectangleRounded(board, .06, 8, {24, 18, 42, 244})
    canvas2d.DrawRectangleRoundedLinesEx(board, .06, 8, 1, {185, 145, 77, 255})
    title := fmt.ctprintf("%s", tarot.spread_name(layout.spread))
    title_size := canvas2d.MeasureTextEx(canvas2d.Font{}, title, 14, 1)
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        title,
        {board.x + (board.width - title_size.x) * .5, board.y + 10},
        14,
        1,
        {245, 220, 151, 255},
    )
    for placement, index in layout.placements[:layout.count] {
        column, row := index % columns, index / columns
        bounds := canvas2d.Rectangle {
            x      = board.x + 12 + f32(column) * (card_width + gap),
            y      = board.y + 32 + f32(row) * (card_height + gap),
            width  = card_width,
            height = card_height,
        }
        art_bounds := canvas2d.Rectangle{bounds.x, bounds.y, bounds.width, art_height}
        reversed := placement.orientation == .Reversed
        if editor.tarot_atlas.ready {
            card_id := int(placement.card)
            atlas_row, atlas_column := 0, 0
            if card_id < 14 {
                atlas_column = card_id
            } else if card_id < 22 {
                atlas_row = 1
                atlas_column = card_id - 14
            } else {
                minor := card_id - 22
                atlas_row = 2 + minor / 14
                atlas_column = minor % 14
            }
            source := canvas2d.Rectangle {
                x      = f32(atlas_column * 108),
                y      = f32(atlas_row * 158),
                width  = 108,
                height = 158,
            }
            if reversed {
                source.x += source.width
                source.y += source.height
                source.width = -source.width
                source.height = -source.height
            }
            canvas2d.DrawTexturePro(editor.tarot_atlas, source, art_bounds, {255, 255, 255, 255})
        } else {
            canvas2d.DrawRectangleRounded(art_bounds, .08, 6, {240, 226, 186, 255})
        }
        position_label := fmt.ctprintf("%s%s", placement.position, reversed ? " · REVERSED" : "")
        available_width := bounds.width - 8
        position_font_size := layout.count <= 3 ? f32(11) : f32(9)
        position_measured := canvas2d.MeasureTextEx(canvas2d.Font{}, position_label, position_font_size, .5)
        if position_measured.x > available_width {
            position_font_size *= available_width / position_measured.x
        }
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            position_label,
            {bounds.x + 4, bounds.y + art_height + 5},
            position_font_size,
            .5,
            {181, 190, 183, 255},
        )
        card_label := fmt.ctprintf("%s", tarot.card_name(placement.card))
        card_font_size := layout.count <= 3 ? f32(13) : f32(10)
        measured := canvas2d.MeasureTextEx(canvas2d.Font{}, card_label, card_font_size, .5)
        if measured.x > available_width {
            card_font_size *= available_width / measured.x
            card_font_size = max(card_font_size, layout.count <= 3 ? f32(10) : f32(8))
        }
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            card_label,
            {bounds.x + 4, bounds.y + art_height + 23},
            card_font_size,
            .5,
            {245, 220, 151, 255},
        )
    }
}
