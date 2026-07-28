package tests

import plazas "../packages/plazas"
import "core:testing"

plaza_fingerprint :: proc(plan: ^plazas.Plan) -> u64 {
    hash := u64(1469598103934665603)
    for piece in plan.paving[:plan.paving_count] {
        hash = (hash ~ u64(transmute(u32)piece.x)) * 1099511628211
        hash = (hash ~ u64(transmute(u32)piece.z)) * 1099511628211
        hash = (hash ~ u64(transmute(u32)piece.rotation)) * 1099511628211
        hash = (hash ~ u64(piece.kind)) * 1099511628211
    }
    return hash
}

@(test)
ornate_plaza_is_valid_deterministic_and_seeded :: proc(t: ^testing.T) {
    a := plazas.generate(0x504c415a, 28, 18)
    b := plazas.generate(0x504c415a, 28, 18)
    c := plazas.generate(7123, 28, 18)
    testing.expect(t, plazas.validate(&a))
    testing.expect(t, plazas.validate(&b))
    testing.expect(t, plazas.validate(&c))
    testing.expect(t, plaza_fingerprint(&a) == plaza_fingerprint(&b))
    testing.expect(t, plaza_fingerprint(&a) != plaza_fingerprint(&c))
}

@(test)
ornate_plaza_scales_to_its_circulation_footprint :: proc(t: ^testing.T) {
    compact := plazas.generate(41, 12, 9)
    civic := plazas.generate(41, 36, 24)
    testing.expect(t, plazas.validate(&compact))
    testing.expect(t, plazas.validate(&civic))
    testing.expect(t, compact.width == 12 && compact.length == 9)
    testing.expect(t, civic.width == 36 && civic.length == 24)
    testing.expect(t, civic.paving[5].width > compact.paving[5].width)
}
