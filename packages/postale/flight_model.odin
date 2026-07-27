package postale

import flight "../flight"

Flight_Model :: enum {
    Current_Aero,
    Ace_Arcade,
}

ace_tuning_preset :: proc() -> flight.Ace_Tuning {
    tuning := flight.default_ace_tuning()
    tuning.pull_strength = 1
    tuning.air_grip = 1
    tuning.drift = 0
    tuning.turn_hold = 1
    tuning.climb_generosity = 1
    tuning.low_speed_authority = 1
    return tuning
}
