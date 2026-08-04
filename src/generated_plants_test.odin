package main

import plants "../packages/plants"
import third_person "../packages/third_person"
import "core:testing"

generated_plant_lod_test_reset :: proc() {
    generated_plant_lod_states = {}
}

@(test)
generated_plant_lod_selection_is_hysteretic_and_continuous :: proc(t: ^testing.T) {
    generated_plant_lod_test_reset()
    plant := third_person.Vec3{}
    seed := u64(818)

    at_seven := generated_plant_lod_selection(.Olive, seed, {7, 0, 0}, plant)
    testing.expect(t, at_seven.primary == .Hero)
    testing.expect(t, at_seven.has_secondary)
    testing.expect(t, at_seven.secondary == .Near)

    // The legacy 8 m center no longer flips the tier. The outward transition
    // is centered at 9.2 m and spans twelve metres.
    at_eight := generated_plant_lod_selection(.Olive, seed, {8, 0, 0}, plant)
    testing.expect(t, at_eight.primary == .Hero)
    testing.expect(t, at_eight.has_secondary)
    testing.expect(t, at_eight.secondary == .Near)
    testing.expect(t, at_eight.transition > 0 && at_eight.transition < 1)

    outside := generated_plant_lod_selection(.Olive, seed, {16, 0, 0}, plant)
    testing.expect(t, outside.primary == .Near)
    testing.expect(t, !outside.has_secondary)

    // Returning across 8 m retains Near until the inward band is entered.
    returning := generated_plant_lod_selection(.Olive, seed, {8, 0, 0}, plant)
    testing.expect(t, returning.primary == .Near)
    testing.expect(t, returning.has_secondary)
    testing.expect(t, returning.secondary == .Hero)
}

@(test)
generated_plant_lod_selection_settles_after_camera_cut :: proc(t: ^testing.T) {
    generated_plant_lod_test_reset()
    plant := third_person.Vec3{}
    seed := u64(919)
    _ = generated_plant_lod_selection(.Stone_Pine, seed, {2, 0, 0}, plant)
    cut := generated_plant_lod_selection(.Stone_Pine, seed, {180, 0, 0}, plant)
    testing.expect(t, cut.primary == .Distant)
    testing.expect(t, !cut.has_secondary)
}

@(test)
generated_plant_lod_state_is_independent_per_camera_key :: proc(t: ^testing.T) {
    generated_plant_lod_test_reset()
    plant := third_person.Vec3{}
    seed := u64(2026)
    near_camera := generated_plant_lod_selection(.Stone_Pine, seed, {2, 0, 0}, plant, 1)
    distant_camera := generated_plant_lod_selection(.Stone_Pine, seed, {180, 0, 0}, plant, 2)
    near_camera_again := generated_plant_lod_selection(.Stone_Pine, seed, {2, 0, 0}, plant, 1)
    testing.expect(t, near_camera.primary == .Hero)
    testing.expect(t, distant_camera.primary == .Distant)
    testing.expect(t, near_camera_again.primary == .Hero)
}

@(test)
generated_plant_lod_state_survives_home_slot_collisions :: proc(t: ^testing.T) {
    generated_plant_lod_test_reset()
    plant := third_person.Vec3{}
    first_seed := u64(1)
    home := generated_plant_lod_key(.Olive, first_seed, plant) % GENERATED_PLANT_LOD_STATE_CAPACITY
    colliding_seed := u64(2)
    for generated_plant_lod_key(.Olive, colliding_seed, plant) % GENERATED_PLANT_LOD_STATE_CAPACITY != home {
        colliding_seed += 1
    }
    _ = generated_plant_lod_selection(.Olive, first_seed, {16, 0, 0}, plant)
    _ = generated_plant_lod_selection(.Olive, colliding_seed, {180, 0, 0}, plant)
    returning := generated_plant_lod_selection(.Olive, first_seed, {8, 0, 0}, plant)
    testing.expect(t, returning.primary == .Near)
    testing.expect(t, returning.has_secondary && returning.secondary == .Hero)
}
