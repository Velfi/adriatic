package main

import architecture "../packages/architecture"
import boats "../packages/boats"
import kiosks "../packages/kiosks"
import marina "../packages/marina"

PLAYER_COLLISION_RADIUS :: f32(.24)

player_resolve_world_collision :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    position := marina.Vec2{editor.player.position.x, editor.player.position.z}
    collided := false

    for structure in editor.project.structures[:editor.project.structure_count] {
        corrected, hit := architecture.resolve_structure_circle(
            structure,
            {position.x, position.z},
            PLAYER_COLLISION_RADIUS,
        )
        if hit {
            position = {corrected.x, corrected.y}
            collided = true
        }
    }
    city_position, city_hit := architecture.resolve_city_circle(
        &editor.architecture_city_plan,
        {position.x, position.z},
        PLAYER_COLLISION_RADIUS,
    )
    if city_hit {
        position = {city_position.x, city_position.y}
        collided = true
    }

    if editor.in_map && editor.libellula_visible {
        kiosk_positions := [2]kiosks.Vec2 {
            {editor.attendant_position.x, editor.attendant_position.z},
            {editor.gerta_position.x, editor.gerta_position.z},
        }
        for kiosk_position in kiosk_positions {
            corrected, hit := kiosks.resolve_circle(kiosk_position, {position.x, position.z}, PLAYER_COLLISION_RADIUS)
            if hit {
                position = {corrected.x, corrected.y}
                collided = true
            }
        }
    }

    if lab_scene_is_active(editor, "markov-marina") {
        corrected, hit := marina.resolve_circle(&markov_marina_plan, position, PLAYER_COLLISION_RADIUS)
        position, collided = corrected, collided || hit
    } else {
        for index in 0 ..< editor.default_marina_count {
            corrected, hit := marina.resolve_circle(&editor.default_marinas[index], position, PLAYER_COLLISION_RADIUS)
            position, collided = corrected, collided || hit
        }
        if editor.marina_authored {
            corrected, hit := marina.resolve_circle(&editor.marina_authored_plan, position, PLAYER_COLLISION_RADIUS)
            position, collided = corrected, collided || hit
        }
    }

    for &agent in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        corrected, hit := boats.resolve_circle(&agent, {position.x, position.z}, PLAYER_COLLISION_RADIUS)
        if hit {
            position = {corrected.x, corrected.y}
            collided = true
        }
    }

    if collided {
        editor.player.position.x = position.x
        editor.player.position.z = position.z
        // Stop the inward movement for this frame. The controller immediately
        // rebuilds velocity from input, while position projection permits
        // natural sliding on subsequent frames.
        editor.player.velocity.x = 0
        editor.player.velocity.z = 0
    }
    return collided
}
