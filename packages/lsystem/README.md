# L-system plants

`lsystem` is a renderer-independent plant generator. It has two stages:

1. `expand` rewrites a grammar into a deterministic, seeded word.
2. `interpret` turns that word into tapered branch segments and oriented leaf
   attachment points.

The package owns no meshes, materials, or Adriatic presentation policy. A
renderer can turn each `Segment` into a stem and each `Leaf` into a card,
cluster, flower, fruit, or other species-specific feature.

```odin
alternatives := [1]lsystem.Alternative{{text = "F[+FL][-FL]F"}}
rules := [1]lsystem.Rule{{symbol = 'F', alternatives = alternatives[:]}}

word := lsystem.expand(
    {axiom = "F", rules = rules[:]},
    {iterations = 4, seed = 27, max_symbols = 100_000},
)
defer lsystem.destroy_word(&word)

plant := lsystem.interpret(
    word.word[:],
    {step = .35, angle = math.to_radians(24), radius = .06, radius_scale = .76},
)
defer lsystem.destroy_plant(&plant.plant)
```

The turtle alphabet is:

- `F`: draw forward; `f`: move forward
- `+` / `-`: yaw
- `&` / `^`: pitch
- `\` / `/`: roll
- `|`: turn 180 degrees
- `[` / `]`: push and restore branch state
- `L`: emit an oriented foliage attachment

Other symbols are intentionally ignored by the interpreter, so grammars can
use nonterminal symbols freely. Zero-valued configuration fields select
practical defaults. Always check the result error before consuming output.
