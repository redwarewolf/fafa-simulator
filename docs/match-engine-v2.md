# FAFA Simulator — Match Engine v2: Design & Status

_Living document. Update the Status line under each phase as work lands. Supersedes `docs/ai-overhaul.md` (Rounds 1–2), which stays as history._

## Why v2

Rounds 1–2 improved individual decisions inside an architecture that caps how good the AI can get:

- **Coarse positioning.** Off-ball targets snap to 18 `FieldZones` polygon centres plus fixed offsets. There's no continuous space model.
- **No team phase model.** Nothing classifies settled attack/defence or transitions, and there's no hysteresis.
- **Thin coordination.** There's one presser, one cover and greedy marking. Nobody is assigned to lane-cut, jockey, intercept, rest defence or attacking runs.
- **Ad-hoc on-ball scoring.** Actions are scored by summing pixel values. There are no success probabilities, no value model and no passes into space.
- **Wall-clock timing.** `Time.get_ticks_msec()` is used everywhere. The AI degrades at high speed, there's no determinism and there's no headless testing.
- **Missing rules.** There's no offside and no throw-ins, corners or goal kicks.

## Architecture

Tactical Brain (per team) → Coordinators (defence / attack / set pieces) → Player Brain (per player) → Execution (locomotion, states, ball physics). Every layer reads a shared 10 Hz `MatchContext`, which holds the pitch-control grid, xT grid, pass/shot models and ball predictor.

Research basis:
- Spearman 2018: time-to-intercept pitch control and pass probability.
- Fernández & Bornn 2018: pitch-control ellipses.
- Singh 2019: Expected Threat.
- Fernández et al. 2019/2021: EPV.
- Reis & Lau, RoboCup: SBSP formation-as-function-of-ball.
- Hungarian assignment for role coordination.
- Analytic goalkeeper (RL deferred).

Full plan: see the phase list below. The code lives in `scenes/match/`. The old AI stays selectable (`MatchConfig.AI_VERSION`) until v2 wins the A/B, then gets deleted.

## Decisions (user, 2026-09-28)
- Add offside and all restarts (throw-in, corner, goal kick).
- Mental attributes are derived at match time from existing stats. No save, generation or UI changes.
- Goalkeeper is analytic first; RL maybe later.
- "Simular" keeps the Poisson model (`utils/match_odds.gd`) for now.

## Phases & status

| # | Phase | Status |
|---|-------|--------|
| 0 | Checkpoint commit + this doc | in progress |
| 1 | Deterministic clock, seeded RNG, stats, headless batch harness | pending |
| 2 | Rules: offside, throw-ins, corners, goal kicks | pending |
| 3 | World model: ball predictor, pitch-control grid, xT, pass/shot models, MatchContext | pending |
| 4 | Tactical Brain: phase classification + hysteresis, live team shape, instructions | pending |
| 5 | Coordinators: defensive / attacking / set-piece role assignment (Hungarian) | pending |
| 6 | Player Brain: mental attributes, grid off-ball positioning, EPV on-ball decisions, receiving | pending |
| 7 | Execution: accel/turn-limited locomotion, tackle model, touch dribbling | pending |
| 8 | Analytic goalkeeper | pending |
| 9 | Performance budget / scheduler | pending |
| 10 | Calibration, A/B vs v1, delete v1 | pending |

## Verification (every phase)
1. `godot --headless --script res://tests/run_tests.gd` runs the maths unit tests.
2. `godot --headless --script res://tools/batch_match.gd -- --matches 50 --seed 1 ...` checks determinism, then metrics against `tools/targets.json` and the v1 baseline.
3. A headless rescan for script errors.
4. A visual check through the `run-fafa-simulator` skill with the debug overlays.
5. Record the results here and commit per phase.

## Findings log
_(empty)_
