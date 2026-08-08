package main

import plant_assets "../packages/plant_assets"
import plants "../packages/plants"
import "core:math"
import "core:testing"

Plant_Asset_Header :: plant_assets.Plant_Asset_Header
plant_asset_compile :: plant_assets.plant_asset_compile
plant_asset_destroy :: plant_assets.plant_asset_destroy
plant_asset_serialize :: plant_assets.plant_asset_serialize
plant_asset_validate_bytes :: plant_assets.plant_asset_validate_bytes
plant_asset_generated_result :: plant_assets.plant_asset_generated_result

@(test)
plant_asset_round_trip_validates_all_lod_payloads :: proc(t: ^testing.T) {
    asset, compiled := plant_asset_compile(
        {species = .Olive, seed = 42, maturity_step = GENERATED_PLANT_MATURITY_STEPS, habit = .Free_Standing},
    )
    testing.expect(t, compiled)
    if !compiled do return
    defer plant_asset_destroy(&asset)
    bytes := plant_asset_serialize(&asset)
    defer delete(bytes)
    testing.expect(t, plant_asset_validate_bytes(bytes[:]))
    testing.expect(t, asset.header.impostor_azimuths == 8)
    testing.expect(t, asset.header.impostor_elevations == 3)
    testing.expect(t, asset.header.bark_material_ref != 0)
    testing.expect(t, asset.header.organ_material_ref != 0)
    testing.expect(t, asset.header.collision_radius > 0)
    testing.expect(t, asset.header.collision_height > 0)
    testing.expect_value(t, asset.header.impostor_width, u16(plant_assets.PLANT_IMPOSTOR_ATLAS_WIDTH))
    testing.expect_value(t, asset.header.impostor_height, u16(plant_assets.PLANT_IMPOSTOR_ATLAS_HEIGHT))
    testing.expect_value(
        t,
        len(asset.impostor_color),
        plant_assets.PLANT_IMPOSTOR_ATLAS_WIDTH * plant_assets.PLANT_IMPOSTOR_ATLAS_HEIGHT * 4,
    )
    opaque_pixels := 0
    for alpha := 3; alpha < len(asset.impostor_color); alpha += 4 {
        if asset.impostor_color[alpha] > 0 do opaque_pixels += 1
    }
    testing.expect(t, opaque_pixels > 0)
    for lod, lod_index in asset.lods {
        if lod_index == plant_assets.PLANT_ASSET_LOD_COUNT - 1 {
            testing.expect_value(t, len(lod.segments), 0)
            testing.expect_value(t, len(lod.vertices), 0)
            testing.expect_value(t, len(lod.indices), 0)
        } else {
            testing.expect(t, len(lod.segments) > 0)
            testing.expect(t, len(lod.vertices) > 0)
            testing.expect(t, len(lod.indices) > 0)
        }
    }
    restored, restored_ok := plant_asset_generated_result(bytes[:], .Medium)
    testing.expect(t, restored_ok)
    if restored_ok {
        defer plants.destroy(&restored)
        source := &asset.lods[2]
        testing.expect(t, len(restored.plant.segments) == len(source.segments))
        testing.expect(t, len(restored.plant.attachments) == len(source.organs))
        testing.expect(t, len(restored.plant.graph.internodes) == len(source.segments))
        testing.expect(t, restored.plant.segment_ids[0] == source.segments[0].stable_id)
    }
}

@(test)
plant_asset_request_compiles_the_site_context_named_by_its_key :: proc(t: ^testing.T) {
    ordinary := plant_assets.Plant_Asset_Request {
        species       = .Olive,
        seed          = 44,
        maturity_step = GENERATED_PLANT_MATURITY_STEPS,
        habit         = .Free_Standing,
    }
    dry := ordinary
    dry.site = {
        valid            = true,
        aridity          = .9,
        exposure         = .8,
        slope            = .4,
        elevation_meters = 320,
        coast_distance_m = 900,
        substrate        = .Rock,
    }
    testing.expect(t, plant_assets.plant_asset_source_key(ordinary) != plant_assets.plant_asset_source_key(dry))
    asset, compiled := plant_asset_compile(dry)
    testing.expect(t, compiled)
    if compiled {
        defer plant_asset_destroy(&asset)
        testing.expect_value(
            t,
            plants.site_context_signature(asset.header.request.site),
            plants.site_context_signature(dry.site),
        )
    }
}

@(test)
plant_asset_rejects_corrupt_and_unknown_versions :: proc(t: ^testing.T) {
    asset, compiled := plant_asset_compile({
        species       = plants.Species.Rosemary,
        seed          = 91,
        maturity_step = GENERATED_PLANT_MATURITY_STEPS,
        habit         = .Free_Standing,
    })
    testing.expect(t, compiled)
    if !compiled do return
    defer plant_asset_destroy(&asset)
    bytes := plant_asset_serialize(&asset)
    defer delete(bytes)
    bytes[len(bytes) - 1] ~= 0x5a
    testing.expect(t, !plant_asset_validate_bytes(bytes[:]))
    bytes[len(bytes) - 1] ~= 0x5a
    header := (^Plant_Asset_Header)(raw_data(bytes))
    header.format_version += 1
    testing.expect(t, !plant_asset_validate_bytes(bytes[:]))
}

@(test)
plant_asset_manifest_is_unique_and_excludes_support_topology :: proc(t: ^testing.T) {
    testing.expect(t, plant_assets.plant_asset_manifest_valid())
    manifest := plant_assets.plant_asset_manifest_requests(context.temp_allocator)
    testing.expect_value(t, len(manifest), 107)

    residence_count, airport_count := 0, 0
    for request in manifest {
        for bounded_seed in 0 ..< 32 {
            for side in ([2]int{-1, 1}) {
                seed := u64(bounded_seed) ~ u64(side + 1) << 8 ~ 0x5245535f504f54
                if request.seed == seed do residence_count += 1
            }
        }
        for sign_key in ([2]u64{0x100, 0x200}) {
            for planter_index in 0 ..< 4 {
                seed := u64(0xa17c_ade0) ~ u64(planter_index) ~ sign_key
                if request.seed == seed do airport_count += 1
            }
        }
    }
    testing.expect_value(t, residence_count, 64)
    testing.expect_value(t, airport_count, 8)
}

@(test)
plant_asset_manifest_entry_loads_graph_and_compiled_mesh :: proc(t: ^testing.T) {
    manifest := plant_assets.PLANT_ASSET_MANIFEST
    request := manifest[0]
    result, mesh, loaded := plant_assets.plant_asset_try_load(request, .Near)
    testing.expect(t, loaded)
    if !loaded do return
    defer plants.destroy(&result)
    defer plant_assets.plant_asset_mesh_destroy(&mesh)
    testing.expect(t, len(result.plant.graph.internodes) == len(result.plant.segments))
    testing.expect(t, len(mesh.vertices) > 0)
    testing.expect(t, len(mesh.indices) > 0)
}

@(test)
plant_asset_complete_manifest_loads_every_compiled_variant :: proc(t: ^testing.T) {
    for request in plant_assets.PLANT_ASSET_MANIFEST {
        result, mesh, loaded := plant_assets.plant_asset_try_load(request, .Near)
        testing.expect(t, loaded)
        if loaded {
            testing.expect(t, len(result.plant.graph.internodes) > 0)
            testing.expect_value(t, len(result.plant.graph.internodes), len(result.plant.segments))
            testing.expect(t, len(mesh.vertices) > 0 && len(mesh.indices) > 0)
        }
        plants.destroy(&result)
        plant_assets.plant_asset_mesh_destroy(&mesh)
    }
}

@(test)
plant_asset_native_graph_round_trip_preserves_semantics :: proc(t: ^testing.T) {
    request := plant_assets.PLANT_ASSET_MANIFEST[6] // Oleander
    result, mesh, loaded := plant_assets.plant_asset_try_load(request, .Near)
    testing.expect(t, loaded)
    if !loaded do return
    defer plants.destroy(&result)
    defer plant_assets.plant_asset_mesh_destroy(&mesh)
    has_renewal, has_flowering, has_flower := false, false, false
    for axis in result.plant.graph.axes {
        has_renewal = has_renewal || axis.role == .Renewal_Cane
        has_flowering = has_flowering || axis.role == .Flowering_Shoot
    }
    for organ in result.plant.graph.organs do has_flower = has_flower || organ.kind == .Flower
    testing.expect(t, has_renewal)
    testing.expect(t, has_flowering)
    testing.expect(t, has_flower)
    testing.expect_value(t, len(result.plant.graph.internodes), len(result.plant.segment_ids))
}

@(test)
plant_impostor_selection_wraps_and_uses_aerial_band :: proc(t: ^testing.T) {
    near_wrap := plant_assets.plant_impostor_select(math.TAU - .01, 0)
    testing.expect_value(t, near_wrap.first, 15)
    testing.expect_value(t, near_wrap.second, 8)
    testing.expect(t, near_wrap.blend > .9)
    aerial := plant_assets.plant_impostor_select(.4, 50 * math.PI / 180)
    testing.expect(t, aerial.first >= 16 && aerial.first < 24)
    testing.expect(t, aerial.second >= 16 && aerial.second < 24)
}
