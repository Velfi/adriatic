<!-- Bootstrap flight-design draft — created during prototype planning. Expand or replace before Production. -->

# Ace Flight Model

Status: draft  
Purpose: parallel airborne-movement prototype for comparison with current fixed-wing model  
Date: 2026-07-28

## Summary

Ace is a maneuver-first arcade flight model. It should make ordinary control
feel competent, committed control feel expressive, and risky combinations feel
spectacular. It is not a simplified aerodynamic simulation. It is an authored
movement model whose rules are legible to players and whose controls are legible
to designers.

Current fixed-wing model remains intact as a baseline. Ace runs behind a model
selector, consumes the same pilot commands, and writes the same body state. Both
models retain the existing Postale ground-contact, takeoff, landing, damage,
occupancy, and presentation integration during the first prototype.

Ace separates three concerns:

1. **Flight motion** turns pilot intent into attitude, velocity, and position.
2. **Maneuver recognition** identifies what the aircraft actually performed.
3. **Style direction** rewards risk, execution, variety, and flow.

Style never awards points from input alone. A maneuver must appear in actual
motion and end in controlled flight.

The dependency direction is:

```text
flight motion → telemetry → maneuver recognition → style scoring
```

Reverse dependencies are forbidden. Rank and score may not change movement,
damage, or control authority.

## Draft assumptions

For the pre-engine-swap prototype, this document assumes:

- a single-player prototype;
- the existing pitch, roll, yaw, and throttle vocabulary;
- existing normalized `flight.Control_Command` as temporary joystick-shaped
  model input;
- deterministic product packages when given identical initial state,
  identical fixed `dt`, and an identical command sequence;
- Postale as the only prototype aircraft;
- an engine-neutral airborne comparison scenario;
- no combat;
- no mechanical reward from style;
- engine input mapping, player-facing checkpoint controls, and cross-frame-rate
  determinism deferred until the engine swap.

These are temporary prototype constraints, not permanent product decisions.

## Validation question

Can a designer-authored movement model make a first-time player perform
recognizable aerobatic maneuvers quickly while still giving an experienced
player enough control, risk, and expressive variation to build deliberate
high-style sequences?

Ace succeeds only if it beats the current model on that question. Easier flight
alone is insufficient. Automatic spectacle is also insufficient.

## Core fantasy

> Player feels like a daring ace who reads the sky, commits to dangerous lines,
> improvises connected maneuvers, and recovers with intent.

Player should feel responsible for the feat. Assistance may strengthen clear
intent, preserve readable motion, and make recovery possible. Assistance must
not secretly perform whole maneuvers.

## Design pillars

### Immediate competence

Neutral flight is calm. Basic turns are readable. Takeoff and recovery do not
require knowledge of aerodynamics. Aircraft does what player believes the stick
asked it to do.

### Expressive commitment

Small input produces precise correction. Strong sustained input opens full
rotation, high angle, slip, and stall behavior. Assistance yields as commitment
increases.

### Risk with recovery

Low altitude, low energy, narrow gaps, inverted flight, and aggressive
transitions create score. Failure should usually produce a dramatic recovery
problem before it produces a crash.

### Style through variation

Repeated safe tricks decay in value. Chaining different maneuvers through clean
exits builds rank. Best play looks improvised, not farmed.

### Consistent fiction

Ace may ignore aerodynamic derivation, but not cause and effect. Dives build
energy. Climbs and hard turns spend it. Momentum does not teleport. Bad exits
create bad next entries. Players must be able to form useful intuition.

## Non-goals

First prototype does not attempt:

- measured aircraft performance;
- force or moment simulation;
- aerodynamic coefficient authoring;
- combat, targeting, weapons, or enemy AI;
- aircraft progression or unlock economies;
- multiplayer;
- production save compatibility for Ace runtime state;
- replacement of current takeoff, landing, damage, or ground physics;
- per-aircraft handling identities beyond one Postale preset.

## Engine-swap backlog

The pre-engine-swap milestones do not include:

- keyboard, mouse, controller, and joystick adapter redesign;
- analog throttle redesign;
- engine-integrated input recording or replay;
- player-facing checkpoint capture and restore controls;
- cross-frame-rate end-to-end determinism;
- production model-selection UI;
- rendered ghosts and comparison trails;
- final telemetry and score HUD, camera behavior, VFX, audio, rumble, or
  accessibility treatment.

## Prototype loop

1. Restore an explicit airborne comparison state in the test harness, or use a
   direct debug reset in the current application.
2. Approach a short route of gates and terrain opportunities.
3. Perform maneuvers to follow the route and increase style rank.
4. Connect maneuvers through controlled exits.
5. Finish with a low pass and landing.
6. Review logs or score breakdown, restore equivalent state, and retry with
   either model.

One run should take roughly two to three minutes. A polished one-action
player-facing checkpoint flow is deferred until the engine swap.

## Model overview

Ace models four player-facing ideas:

- **Attitude:** where aircraft nose, wings, and belly point.
- **Track:** direction aircraft is actually moving.
- **Pace:** current movement speed.
- **Energy:** stored capacity for climbing, turning, and recovering.

Attitude and track are deliberately separate. Aircraft can point away from its
motion, creating drift, knife-edge flight, stall turns, and expressive exits.
Air grip determines how strongly track follows attitude.

Internal update:

```text
normalized flight.Control_Command
    ↓
target angular rates ─────────────┐
    ↓                            │
attitude                         │
    ↓                            │
desired track ← air grip ← energy│
    ↓                            │
track and pace ← climb/turn costs┘
    ↓
velocity and position
    ↓
maneuver signals
```

Postale owns device handling and shared command smoothing. Ace begins at the
normalized `flight.Control_Command` boundary.

Existing `Body_State` remains authoritative for position, velocity,
orientation, and angular velocity. Ace runtime stores only authored motion state
that cannot be reconstructed reliably from a single frame, such as energy, edge
phase and timing, local angular-rate response, and recovery state. Maneuver
recognition accumulates rotation separately from shared body motion; recognition
progress never belongs to flight runtime.

## Pilot controls

Ace keeps present control vocabulary:

- **Pitch:** asks nose to rotate up or down.
- **Roll:** asks aircraft to rotate around forward axis.
- **Yaw:** asks nose and track to carve laterally.
- **Throttle:** asks pace and energy to build or fall.

Controls command angular rates, not torque. Rate response still has weight:
target rate changes immediately enough to feel responsive, while actual rate
approaches target through authored engage and release curves.

Input magnitude has three useful bands:

- **Correction:** small input; precise line adjustment and strong stabilization.
- **Command:** medium input; ordinary turning and positioning.
- **Commitment:** large sustained input; assistance yields and full maneuver
  authority becomes available.

Thresholds must blend continuously. Crossing one must never cause a visible
snap.

## Designer-facing knobs

Designer UI should expose normalized sliders, named for visible behavior.
Implementation may derive rates, angles, accelerations, and curve constants
from them. Those derived values remain diagnostic, not primary authoring
controls.

### Tempo

| Knob | Player-visible effect |
| --- | --- |
| **Pace** | Typical travel speed and amount of world crossed during a maneuver. |
| **Punch** | How quickly throttle or recovery produces useful speed. |
| **Coast** | How long speed persists without throttle. |
| **Brake** | How strongly throttle-down sheds speed in air. |

### Control character

| Knob | Player-visible effect |
| --- | --- |
| **Roll snap** | Maximum roll tempo and aggression of roll entry. |
| **Pull strength** | Tightness and speed of pitch-driven arcs. |
| **Rudder bite** | Strength of yaw carving, slips, and hammerheads. |
| **Weight** | Delay between requested and achieved angular rate. |
| **Settle** | How quickly rotation stops after release. |

### Flight path

| Knob | Player-visible effect |
| --- | --- |
| **Air grip** | How eagerly movement direction follows nose direction. |
| **Drift** | How long old momentum remains visible during reorientation. |
| **Turn hold** | How much pace survives a sustained hard turn. |
| **Climb generosity** | How much height can be gained before energy becomes scarce. |
| **Dive payoff** | How quickly a dive restores energy and pace. |

### Edge behavior

| Knob | Player-visible effect |
| --- | --- |
| **Hang time** | Duration of controllable low-energy flight before a break. |
| **Break drama** | Severity of nose drop, roll-off, and track divergence at the edge. |
| **Recovery punch** | Speed and authority returned after correct recovery input. |
| **Low-speed authority** | Remaining pitch, roll, and yaw control while energy is scarce. |

### Assistance

| Knob | Player-visible effect |
| --- | --- |
| **Steadiness** | Neutral-input resistance to wobble and accidental divergence. |
| **Line hold** | Help maintaining current heading and altitude during small corrections. |
| **Commitment** | How early assistance yields to strong intentional input. |
| **Exit catch** | Brief stabilization available after a completed maneuver. |

Prototype should begin with no more than twelve visible knobs at once. Advanced
knobs may live under folded sections. Presets should be meaningful aircraft
characters, not difficulty levels.

## Energy and pace

Energy is a normalized authored resource, not joules. It represents useful
speed, altitude potential, control margin, and dramatic momentum.

Energy changes from:

- throttle;
- diving or climbing;
- turn intensity;
- sideslip and inverted hold;
- stall or spin state;
- recovery;
- damage modifiers already owned by Postale.

Starting rule:

```text
energy change =
    throttle gain
  + dive gain
  - climb cost
  - turn cost
  - slip cost
  - edge-state cost
```

Exact terms use smooth curves. No individual frame may add or remove enough
energy to create a visible discontinuity.

Pace follows an energy-dependent target rather than integrating thrust and
drag. Throttle chooses where inside the available pace range player wants to
be. Dives may temporarily exceed normal full-throttle pace. Hard climbs and
turns pull pace below it.

Low energy must remain playable, not mushy:

- roll stays readable;
- yaw becomes more important;
- pitch loses sustained pull before it loses all response;
- warning presentation begins before control loss;
- correct recovery input produces a clear result.

## Attitude and track

Pitch, roll, and yaw produce target local angular rates. Each axis has:

- an input curve;
- a maximum rate;
- an engage response;
- a release response;
- an energy response curve;
- optional coupling into another axis.

Track follows desired flight direction through air grip. Desired direction is
primarily nose-forward, modified by:

- current track momentum;
- gravity;
- rudder carve;
- banked-turn contribution;
- stall phase;
- recovery phase.

This is airplane drifting. High grip creates a clean racing line. Lower grip
creates broad expressive slides. Neither may allow instant changes of travel
direction.

Bank should help turn track even without yaw input. Yaw should tighten or skew
that line. Pitch should bend track vertically when energy supports it. These
couplings make coordinated flight accessible while preserving room for
deliberate uncoordinated tricks.

## Edge and stall states

Ace replaces a continuous aerodynamic stall curve with readable authored
states:

```text
Free → Warning → Hang → Break → Recovery → Free
```

### Free

Normal authority. Energy and intent determine maneuver strength.

### Warning

Energy is low while player continues demanding climb or turn. Camera, sound,
control vibration, and trails may warn player. Motion remains fully recoverable.

### Hang

Aircraft briefly remains controllable at very low pace. Yaw and roll can set up
a hammerhead, stall turn, or spin. Continued demand advances toward Break.
Reducing demand or diving begins Recovery.

### Break

Track grip falls, nose begins to drop, and optional roll-off appears. Break
direction should be influenced by recent yaw and roll so player can shape it.
Randomness is forbidden.

### Recovery

Correct nose-down or energy-building intent restores grip and pace with a
strong readable response. Assistance may catch excessive residual rotation,
but only after player initiates recovery.

Edge behavior should invite tricks. It must not become a punishment zone that
style-focused players learn to avoid.

## Inverted and knife-edge flight

Ace must support short authored holds outside ordinary upright flight.

- Inverted flight spends energy faster but remains controllable.
- Knife-edge flight receives partial support when speed and yaw commitment are
  sufficient.
- Neither hold should be indefinite at neutral input.
- Strong line control and low altitude make holds valuable.
- Exit quality matters more than raw hold duration after an upper scoring cap.

This support is intentional. Hiding it behind fake lift multipliers would make
tuning harder without making behavior more honest.

## Maneuver recognition

Recognizer observes body motion, track, energy, height, and environment
proximity. It may inspect pilot intent to resolve ambiguity, but input cannot
complete a maneuver.

Every maneuver uses the same lifecycle:

```text
Idle → Primed → Committed → Recovering → Completed
                        ↘ Failed
```

- **Primed:** entry conditions exist.
- **Committed:** enough motion has occurred that recognizer owns a candidate.
- **Recovering:** main gesture finished; recognizer waits for controlled exit.
- **Completed:** exit conditions met inside time window.
- **Failed:** timeout, collision, contradictory motion, or uncontrolled exit.

Recognizer tracks cumulative rotation around local axes instead of comparing
only start and end orientation. Full rotations otherwise disappear
mathematically.

### Initial maneuver vocabulary

| Maneuver | Recognition sketch | Quality signals |
| --- | --- | --- |
| **Aileron roll** | Roughly one full roll with limited pitch-loop displacement. | Exit heading, altitude retention, roll continuity. |
| **Loop** | Roughly one full pitch rotation with limited lateral divergence. | Round path, sufficient apex control, exit heading. |
| **Immelmann** | Climbing half-loop followed by roll to upright on opposite heading. | Transition timing, apex energy, clean level exit. |
| **Split-S** | Roll to inverted followed by descending half-loop. | Deliberate entry, dive control, exit altitude margin. |
| **Knife-edge** | Near-vertical bank held while track and height remain controlled. | Hold stability, low altitude, narrow path. |
| **Hammerhead** | Steep climb into Hang, strong yaw reversal, controlled dive exit. | Low apex pace, yaw precision, recovery line. |
| **Inverted low pass** | Sustained inverted flight below authored risk height. | Height consistency, duration, terrain clearance. |
| **Gap thread** | Aircraft passes through authored spatial gate without collision. | Clearance, speed, attitude, preceding and following moves. |

Recognition tolerances belong to maneuver definitions. They should be broad
enough to recognize expressive variations but narrow enough that ordinary
navigation does not trigger tricks.

### Variants

One recognizer may produce named variants from measured execution:

- fast, slow, or snap roll;
- inside or outside loop;
- climbing or descending roll;
- left or right knife-edge;
- low, close, inverted, or damaged variants.

Variants add flavor and scoring context without multiplying core state
machines.

## Style direction

Style score answers: “How boldly and deliberately did player connect actual
flight maneuvers?”

Base event score:

```text
awarded score =
    maneuver value
  × execution
  × risk
  × variety
  × flow
```

### Execution

Measures completion, control, and exit:

- required rotation or hold completed;
- path stayed inside maneuver tolerance;
- aircraft exited into controllable flight;
- correction chatter remained low;
- intended heading, attitude, or altitude was recovered.

Execution must not demand geometric perfection. Slight asymmetry can look
better than sterile autopilot motion.

### Risk

Risk comes from world and state:

- low terrain clearance;
- close obstacle clearance;
- narrow gate;
- high pace;
- low energy;
- inverted or knife-edge attitude;
- damaged aircraft;
- short recovery margin before ground.

Risk is sampled across the maneuver, not only at completion. Teleporting near an
obstacle at the last frame cannot inflate score.

### Variety

Recent maneuver history reduces repeated value:

- first repeat receives a mild penalty;
- continued repetition approaches negligible value;
- a meaningfully different maneuver restores variety;
- left/right variants count as related, not wholly distinct;
- environmental context can partially refresh a repeated maneuver.

Endless safe rolls must be a bad scoring strategy.

### Flow

Flow rewards useful exits and quick deliberate transitions:

- next maneuver begins inside a transition window;
- previous exit state is used rather than fully reset;
- route continues forward;
- player avoids long neutral dead time;
- transition does not rely on collision or emergency reset.

Flow should not require constant stick movement. A brief composed pause can be
part of a sequence.

### Pending and banked score

Maneuver value remains pending during Recovering. It banks only when controlled
exit succeeds. Collision, reset, or uncontrolled fall loses pending value and
breaks combo.

Already banked run score remains. Prototype should punish failed commitment,
not erase every earlier success.

### Style rank

Rank rises from varied completed maneuvers and falls during passive flight,
repetition, or failure. Draft names:

1. **Composed**
2. **Daring**
3. **Audacious**
4. **Ace**
5. **Legendary**

Names are placeholders. Rank should drive feedback intensity during prototype,
not aircraft power. Mechanical rank bonuses would corrupt comparison between
movement feel and reward feel.

## Anti-cheese rules

Scoring must explicitly reject:

- repeated unloaded rolls at safe altitude;
- oscillating across detector thresholds;
- holding one pose forever;
- farming one permanent proximity volume;
- triggering maneuver completion after reset or teleport;
- using ground collision to finish rotation;
- collecting entry risk without surviving exit;
- duplicate recognition of one physical rotation.

Deterministic event logs should make every rejected or awarded maneuver
explainable.

## Debug feedback requirements

First prototype needs inspectable data, not final presentation. Logs or current
debug tooling should expose:

- energy;
- current edge state;
- active maneuver candidate;
- completion or failure label;
- pending score;
- style rank and decay;
- breakdown of execution, risk, variety, and flow;
- sampled track and attitude/track separation;
- current model label.

Final HUD, camera, rendered trails, VFX, audio, rumble, and accessibility
treatment remain in the engine-swap backlog. None should later hide poor motion.

## Parallel comparison

### Model selection

Add explicit model selection:

```text
Current_Aero
Ace_Arcade
```

`Current_Aero` remains default until prototype verdict. Formal comparison
restores equivalent state before each run. Arbitrary mid-flight switching is
not required.

### Comparison state

Postale value state and player-facing checkpoint controls are separate
concerns. An engine-neutral comparison scenario captures only product state
required by its test, such as:

- body state;
- Postale ground and damage state;
- throttle and smoothed controls;
- initial runtime state for each model;
- explicit fixed ground or environment samples required by that scenario.

Restore must produce identical initial conditions.

World time belongs in a pure scenario only when the scenario explicitly
supplies it as model input. Camera state, engine checkpoint controls, and the
engine input recorder remain in the engine-swap backlog.

### Command sequence

Each formal comparison scenario stores an ordered fixed-step array of normalized
`flight.Control_Command` values and one fixed `dt`. The same array drives both
models from equivalent initial state. Engine-integrated timestamp recording and
replay remain deferred options.

### Comparison evidence

Useful pre-engine-swap evidence:

- per-step path and telemetry samples;
- side-by-side compact event and telemetry logs;
- end-of-run motion and recovery metrics;
- end-of-run maneuver and style breakdown.

Rendered trails, ghost aircraft, and polished comparison controls remain in the
engine-swap backlog.

Markov Wreck may be used as an optional manual playtest route. No flight,
comparison, recognition, or style package may depend on it.

### Comparison criteria

| Question | Evidence |
| --- | --- |
| Which model makes intended maneuver easier to start? | Time and failed entries before first completion. |
| Which model makes line easier to predict? | Gate misses, exit-heading error, player report. |
| Which model leaves more expressive variation? | Distinct successful paths and maneuver variants. |
| Which model makes mistakes recoverable but meaningful? | Recovery rate, altitude lost, player report. |
| Which model better communicates cause and effect? | Player prediction before retry. |
| Which model creates stronger urge to retry? | Immediate voluntary retries and stated reason. |

Raw score cannot decide winner. Model with higher automatic success may feel
less authored by player.

## Technical shape

Suggested product-owned files:

- `packages/flight/ace_wing.odin` — Ace motion and telemetry;
- `packages/air_style/runtime.odin` — maneuver recognition and scoring;
- `packages/air_style/definitions.odin` — maneuver and style tuning;
- `packages/postale/runtime.odin` — model selection and shared product policy;
- `src/tweaks.odin` — designer controls and diagnostics;
- `tests/ace_flight_test.odin` — deterministic movement scenarios;
- `tests/air_style_test.odin` — recognizer, score, repetition, and flow tests.

Do not move Ace into `zelda-engine`. Its movement rules, aircraft fantasy, and
style policy are Adriatic product design.

Draft data boundary:

```odin
Ace_Tuning :: struct {
    pace, punch, coast, brake:                         f32,
    roll_snap, pull_strength, rudder_bite:             f32,
    weight, settle:                                    f32,
    air_grip, drift, turn_hold:                        f32,
    climb_generosity, dive_payoff:                     f32,
    hang_time, break_drama, recovery_punch:            f32,
    low_speed_authority:                               f32,
    steadiness, line_hold, commitment, exit_catch:     f32,
}

Ace_Runtime :: struct {
    energy:                  f32,
    edge_state:              Edge_State,
    edge_seconds:            f32,
    local_rate:              Vec3,
}

Ace_Telemetry :: struct {
    pace, energy:            f32,
    track_grip:              f32,
    edge_state:              Edge_State,
    attitude_track_angle:    f32,
}
```

Names and grouping matter more than exact structure in this draft.

## Determinism and tests

Motion, recognition, and scoring packages must be deterministic when stepped
from identical initial state with identical fixed `dt` and command sequences.
This does not claim engine-loop or cross-frame-rate determinism.

### Movement tests

- centered controls settle without changing heading rapidly;
- full roll input completes a predictable rotation at cruise energy;
- one loop is possible from default comparison-scenario energy;
- diving restores more energy than level flight;
- sustained hard pull spends more energy than gentle turning;
- low energy reaches Warning, Hang, Break, and Recovery in order;
- correct recovery returns to Free without teleporting track or pace;
- identical initial state, fixed `dt`, and command array produce identical
  state.

### Recognition tests

- one full roll creates one aileron-roll completion;
- partial roll creates no completion;
- loop is not misclassified as roll;
- Immelmann and Split-S resolve from ordered component gestures;
- knife-edge hold requires actual track control;
- reset cancels active candidate;
- collision cannot complete a maneuver.

### Style tests

- distinct three-move chain beats three repeats;
- tighter safe clearance raises risk;
- uncontrolled exit loses pending score;
- clean recovery banks pending score;
- idle flight decays rank but not banked run score;
- one physical maneuver cannot emit duplicate awards;
- same event stream always creates same score.

Scenario thresholds should use broad gameplay envelopes. Tests must protect
rules, not freeze every tuning value.

## Starting playtest targets

These are hypotheses, not production promises:

- first recognizable roll within two attempts;
- first recognizable loop within five attempts;
- recovery from ordinary stall mistake succeeds more often than it crashes;
- three-move varied chain is possible inside one minute;
- repeated roll value falls below one third by fourth immediate repeat;
- at least one tester voluntarily retries route immediately;
- tester can predict whether next climb will leave enough energy to recover.

## Risks

### Hidden autopilot

If motion looks good regardless of timing, player becomes spectator. Measure
input timing and exit variation. Reduce assistance during Commitment.

### Airplane-shaped car

Air grip and authored pace can erase altitude and energy thinking. Preserve
climb cost, dive payoff, gravity, momentum lag, and meaningful recovery.

### Unreadable drift

Too much track lag makes controls feel broken. Show track marker and trail while
tuning. Drift must be chosen, not permanent.

### Detector becomes game

Players may perform ugly motions that satisfy thresholds. Score path quality
and exit control, inspect logs, and keep recognition tolerant but scoring
graduated.

### Style overwhelms flight

HUD noise and score optimization can replace joy of movement. Prototype
breakdown may be verbose; final presentation should become quieter.

### Tuning explosion

Normalized designer knobs can still interact badly. Keep one default preset,
cap visible knobs, and derive technical curves from a small number of traits.

### Invalid A/B result

Different spawn state, route, or feedback can bias comparison. Restore
equivalent comparison state and keep manual-playtest presentation equivalent
until motion comparison is complete.

## Open decisions

- How long may inverted and knife-edge support persist before energy forces an
  exit?
- Should yaw always carve track, or only when bank, energy, or commitment
  crosses a threshold?
- Should style rank names remain verbal or use compact letter grades?
- Does damage multiply difficulty, risk score, or both?
- Which world objects define risk proximity and gap-thread volumes?

Recommended prototype answers:

- allow short but not indefinite authored holds;
- let yaw carve continuously with energy-dependent strength;
- use verbal rank names during prototyping;
- let damage raise risk only after scoring proves robust;
- use explicit authored gates before general geometry proximity.

## Prototype verdict

Milestone 5 judges motion only. Choose:

- **Proceed:** Ace motion is clearly better than current motion and preserves
  player agency. Only then begin maneuver recognition.
- **Revise:** Named motion or Postale-integration failures remain. Return to
  Milestone 2 or Milestone 3.
- **Stop:** Ace motion does not beat current motion. Preserve comparison
  evidence and do not build maneuver recognition or style scoring.

Recognition or scoring success may not affect the Milestone 5 verdict.

No hybridization before verdict. Mixing Ace assists into current aerodynamics
too early would destroy comparison and leave another pile of mystery knobs.
