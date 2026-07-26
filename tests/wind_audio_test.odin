package tests

import wind_audio "../packages/wind_audio"
import "core:math"
import "core:testing"

@(test)
wind_synth_is_deterministic_and_stereo :: proc(t: ^testing.T) {
    a := wind_audio.new_synth(42)
    b := wind_audio.new_synth(42)
    wind_audio.set_strength(&a, 1)
    wind_audio.set_strength(&b, 1)
    a_samples: [4096]f32
    b_samples: [4096]f32
    wind_audio.render(&a, a_samples[:])
    wind_audio.render(&b, b_samples[:])
    testing.expect(t, a_samples == b_samples)

    stereo_difference := f32(0)
    for frame in 0 ..< len(a_samples) / 2 {
        stereo_difference += f32(math.abs(f64(a_samples[frame * 2] - a_samples[frame * 2 + 1])))
    }
    testing.expect(t, stereo_difference > .01)
}

@(test)
wind_synth_strength_controls_output_and_stays_bounded :: proc(t: ^testing.T) {
    silent := wind_audio.new_synth(7)
    loud := wind_audio.new_synth(7)
    wind_audio.set_strength(&loud, 1)
    silent_samples: [8192]f32
    loud_samples: [8192]f32
    wind_audio.render(&silent, silent_samples[:])
    wind_audio.render(&loud, loud_samples[:])

    silent_energy, loud_energy := f64(0), f64(0)
    for index in 0 ..< len(loud_samples) {
        silent_energy += f64(silent_samples[index] * silent_samples[index])
        loud_energy += f64(loud_samples[index] * loud_samples[index])
        testing.expect(t, loud_samples[index] >= -.9 && loud_samples[index] <= .9)
    }
    testing.expect(t, silent_energy == 0)
    testing.expect(t, loud_energy > .01)
}
