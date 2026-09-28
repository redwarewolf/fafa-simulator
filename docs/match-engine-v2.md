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
| 0 | Checkpoint commit + this doc | ✅ done (tag `pre-engine-v2` → `7d8802c`) |
| 1 | Deterministic clock, seeded RNG, stats, headless batch harness | ✅ done (`babab77`); pre-rules v1 baseline running |
| 2 | Rules: offside, throw-ins, corners, goal kicks | ✅ done: unit tests + 7/7 live rules probe |
| 3 | World model: ball predictor, pitch-control grid, xT, pass/shot models, MatchContext | ✅ done (`b479e90`), incl. lofted-pass physics fix |
| 4 | Tactical Brain: phase classification + hysteresis, live team shape, instructions | 🟡 first cut working (`c3510bd`), tuning |
| 5 | Coordinators: defensive / attacking / set-piece role assignment (Hungarian) | 🟡 open-play coordinators done; set-piece coordinator pending |
| 6 | Player Brain: mental attributes, grid off-ball positioning, EPV on-ball decisions, receiving | 🟡 first cut working, tuning |
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

## Phase 1 notes

What landed:
- **`MatchClock`** (autoload, `scenes/match/core/match_clock.gd`): simulation time from the scaled frame delta. It replaces every `Time.get_ticks_msec()` in match code (AI, goalie, player states, shot ball state, tactical refresh). `MatchWorld._enter_tree` resets it at match start. Pause and speed-up now scale AI timing correctly.
- **`MatchRng`** (autoload): the seeded source for anything outcome-affecting: tackle duel, foul roll, shot target, keeper clearance, kickoff team/taker, AI tick stagger. Cosmetic randomness (sounds, crowd, celebrations, referee look) stays on the global RNG on purpose, so headless and windowed runs draw identically.
- **`MatchConfig`** (static): `headless`, `match_seed`, `ai_version_left/right`, `disable_random_events`, `match_duration_override`. When headless, `MatchWorld` skips stadium setup, season bookkeeping, the save and the popup.
- **`PitchSpace`**: px ↔ team-normalised ↔ metres. The metres mapping is anisotropic (105×68m over 2197×888px) and is for analytics only.
- **`ShotModel.xg_basic`**: a distance/angle logistic, used for metrics now; Phase 3 extends it.
- **New typed `GameEvents` signals**: `possession_gained`, `pass_attempted`, `shot_taken`, `tackle_resolved`.
- **`MatchStats`**: possession, passes (completion / progressive / forward / length), shots/xG, tackles, interceptions, turnovers by third, PPDA, and shape sampled at 2 Hz (length/width in and out of possession, line height, compactness, players behind the ball, bunching index). Raw counts are exported so the harness pools rates across matches.
- **`tools/batch_match.tscn`**: the headless runner, with club/side balancing, per-version aggregation, target-band scoring against `tools/targets.json`, and JSON output.
- **`tests/run_tests.tscn`**: a minimal headless unit-test runner (`tests/*_test.gd` extend `TestCase`).

Commands (repo root, `G` = the Godot 4.7 console exe):
```
"$G" --path . --headless --editor --quit                    # rescan after adding class_name scripts
"$G" --path . --headless res://tests/run_tests.tscn         # unit tests
"$G" --path . --headless --fixed-fps 60 res://tools/batch_match.tscn -- --matches 40 --seed 1000 --a v1 --b v1 --out user://baseline_v1.json
```
`--fixed-fps 60` is required: it fixes the frame delta, which is what makes a run reproducible. Results land in `%APPDATA%/Godot/app_userdata/FAFA Simulator/`.

Verified:
- Smoke run: 2×60s matches in 9.3s wall, about 13× real time, so a full 360s match takes ~27s.
- Two runs with seed 7 gave byte-identical JSON apart from the output path.

## Phase 2 notes

What landed:
- **`PitchSpace` is a trapezoid mapping.** The goal lines are fitted to the inner edges of the end-wall collision polygons (within ~5px). `normalised()` / `absolute_normalised()` map the perspective pitch onto the unit square, so "equal depth" lines, including the offside line, are the slanted ones.
- **`Restart.Kind`** is one of FREE_KICK, OFFSIDE, THROW_IN, CORNER, GOAL_KICK, plus per-kind rules: offside exemption (Law 11), retreat distance, and whether the taker is teleported.
- **`OutOfPlay`** (pure functions):
  - `crossed()` detects the ball reaching a line MARGIN_PX (11) inside the walls. The walls remain as a physical backstop; the goal mouths are excluded, and the deepest penetration wins in the corners.
  - `decide()` applies Laws 15–17 from `Ball.last_touch`.
- **`OffsideJudge`** (a node under MatchWorld): snapshots offside positions when a pass is played, and flags an offender who is the next to gain possession, giving an indirect free kick at the reception point.
  - Throw-ins, corners and goal kicks are exempt via `exempt_next_kick`.
  - Not modelled: interfering without touching the ball, and deflection-vs-deliberate-play nuance.
- **`Ball.last_touch`** is set on possession, on tackle wins and on physical deflections (including keeper parries off GoalieHands).
- **`MatchWorld`**: FOUL is replaced by a single RESTART state.
  - `award_restart(kind, team, spot, taker)` places the ball and picks the taker (keeper for goal kicks, nearest outfielder otherwise; the fouled player takes their own free kick). It moves the taker behind the ball, then freezes everyone else and pushes opponents back.
  - For goal kicks, opponents are pushed out of the penalty area. The keeper restarts from `HOLDING_BALL`, so GoalieAI's existing distribution handles it.
  - The taker gets `restart_pass_pending`, so their first decision is a pass.
- **HUD**: one toast per kind (FALTA / FUERA DE JUEGO / SAQUE DE BANDA / CÓRNER / SAQUE DE META), with EN translations.
- **Stats**: `restarts_<kind>` per awarded side.

Verification:
- 17/17 unit tests (`tests/rules_test.gd`: offside geometry, slanted-line detection, mouth exclusion, last-touch decisions, spot safety).
- `tools/rules_probe.tscn` runs a real match scene headless and fires the ball at each line with players frozen, checking the awarded restart; it also stages offside and onside passes through the live judge. **7/7 pass.**
- The first probe run caught that my first line constants were ~10px outside the real wall edges, so the ball bounced before registering. Fixed by fitting the collision polygons.

Observation: in two 90s v1 smoke matches no throw-ins or corners happened at all. A position probe showed the ball never came within 5% of any line; in one match it stayed between 50% and 66% of the pitch length for 90 seconds, with one pass. That's the v1 AI stuck in a midfield scrum, not a rules bug. It's a useful baseline data point for v2.

## Phase 3 notes

What landed (`scenes/match/world/`):
- **`BallPredictor`** replays the engine's own ball arithmetic step by step: the freeform air/ground friction switch, the per-tick (un-delta-scaled) height integration and bounce, and the shot's friction-free first second. A closed form would drift on exactly those quirks.
  - `tools/ball_probe.tscn` compares it with the real ball in a match scene: within ~10px along whole paths.
  - API: `for_pass`, `for_ball`, `earliest_intercept`, `first_to_ball`.
- **`PassModel.evaluate(from, to, passer, receiver|null, …)`** is a Spearman-style race.
  - Interception en route: max over path samples of P(fastest opponent reaches that point before the ball).
  - Reception at the target: receiver, or the fastest teammate for a pass into space, against the fastest opponent.
  - It uses the logistic `1/(1+exp(-π/(√3·0.45)·Δt))`.
- **`PitchControlGrid`**: 24×10 cells in trapezoid-normalised space, best time-to-reach per team through the same logistic.
  - Refreshed a third of the rows per frame (20 Hz at 60 fps).
  - Measured at **0.77 ms/frame mean**, 2.7 ms max, with a concurrent batch competing for CPU.
- **`XtGrid`**: an *analytic* xT surface (a progression term plus 0.8×xG), calibrated to published landmarks and covered by tests. It will be re-fitted from harness data by value iteration in Phase 10.
- **`ShotModel.xg()`**: `xg_basic` discounted by blockers in the shot triangle and by pressure within 2m.
- **`MatchContext`** (a node under ActorsContainer): owns the grid, answers `control_at` / `xt_at` / `value_at`, and draws the debug overlays (`SHOW_PITCH_CONTROL`, `SHOW_XT`, `SHOW_BALL_PREDICTION`, `SHOW_PASS_FAN`). It's only created when a side runs v2 or an analytics overlay is on.
- The pass launch was extracted into `Ball.pass_launch()`, so the models evaluate exactly the kick the engine performs.

Tests: 26/26 (`tests/world_model_test.gd`: pass stopping/landing accuracy, shot hot phase, intercept ordering, open/blocked/marked passes, through-ball race, pitch-control symmetry, xT landmarks and mirroring).

## Phases 4–6 notes (first cut + tuning log)

Code: `scenes/match/brain/`. A side runs v2 when `MatchConfig.ai_version_left/right == "v2"`. Its keeper stays on v1's GoalieAI until Phase 8.
- **TacticalBrain**: observed owner (carrier / pass in flight / first to a loose ball) becomes the committed owner after 0.15s (carried) or 0.5s (loose). Transition windows last 4s (attack) and 5s (counter-press).
- **TeamShape**: formation anchors re-scaled into a block each tick, in the team frame.
  - Out of possession: the defensive line holds a gap behind the ball within press-dependent limits, adjusted by the ball-pressure rule.
  - In possession: the back line steps up behind the ball, and the front is pinned just onside of the opponents' last line.
- **TeamBrain coordinators**, all assigned in one Hungarian solve (travel time + affinity + slot-swap penalty − stickiness):
  - Out of possession: PRESS (engage or contain, with pressing triggers), a second PRESS in the counter-press window, COVER, MARK ×≤4 (by xT threat), LANE_CUT.
  - Loose ball: CHASE / INTERCEPT by predicted first-to-ball.
  - In possession: RECEIVE (on the ball path), SUPPORT ×2, RUN ×1–2 (on the shoulder), REST_DEFENCE ×2–4.
- **PlayerBrain**: jobs execute per frame (tracking targets recomputed every frame), thinking is staggered, there's a first-touch delay, and tackles are committed per job.
- **OnBallEvaluator**: `P·V(dest) − (1−P)·risk·V_opp(loss) + P·verticality·Δdepth`, where `V = MatchContext.possession_value` (the better of the spot's xT × security and the reachable-value potential). Options: passes to feet, into space ahead of runners, carries in 7 directions, hold, and shot (xG × role bias). Picked by softmax with a value-relative temperature.
- **MentalAttributes**: decisions → temperature, composure → first-touch delay, positioning → shape error, vision/off-ball → search radius.

Harness progression, v2 vs v1, 6 × 180s, seeds 50–55 (per side per match):

| round | change | v2 passes | v2 compl. | v2 shots | v2 xG | v1 xG | record W/D/L |
|---|---|---|---|---|---|---|---|
| 0 | first cut (+ pickup & clock fixes) | 51 | 83% | 1.2 | 0.46 | 0.25 | 1/4/1 |
| 1 | xT shot weight 0.8→0.45; higher def. line | 52 | 81% | 0.8 | 0.08 | 0.06 | 1/5/0 |
| 2 | mandatory special jobs; attack block pinned to opp. line; potential grid; relative softmax; verticality 0.02–0.07 | 29 | 63% | 2.2 | 0.29 | 0.21 | 1/4/1 |
| 3 | verticality 0.008–0.035 | 37 | 70% | 2.3 | **0.46** | **0.08** | **2/3/1** |

**Valid v1 reference** (v1 vs v1, 20 × 360s, all engine fixes applied, `baseline_v1b.json`), per side per match:
- Passes and turnovers: 38 passes at **45% completion**, 29 turnovers, 33 tackles, bunching index **2.23**.
- Shooting: 1.7 shots, 0.27 xG/shot, 0.9 / 0.65 goals.
- Direction: 87–91% of passes forward.

Against that, v2's rates are clearly better: 70% vs 45% completion, half the bunching, ~3× the shot rate per minute, and more realistic shot quality.

What each round's telemetry showed (decision counters by third, shape snapshots):
- **Round 1.** Only 2 of 116 on-ball decisions happened in the attacking third. Build-up choices were near-random, because the absolute softmax temperature exceeded the differences between options in the flat own-half xT.
- **Round 2.** The RUN job was never assigned. Its priority (−3s) was smaller than travel times, so leaving it empty was "cheaper". Specials are now effectively mandatory (−30…−120).
  - The forwards were parked at 0.52 while a deep block's line sat at ~0.85.
  - Rest-defence and receive targets were falling off the pitch; now clamped.

Open issues (next tuning rounds):
- Play is too direct: 73% of passes go forward and 43% are progressive.
- Possessions are short (1.2 passes each).
- Average pass length is 26m.
- Bunching index is 1.06.
- `ctx_usec_mean` is 1.44 ms because the potential grid adds 0.7 ms. Phase 9 will switch to a separable max-filter.
- No set-piece routines yet: restarts use the Phase 2 placeholder.
- The keeper is still v1.

## Findings log
7. **Ground passes died at the target, and most mid-range passes were lofted: ✅ CHANGED (2026-09-28).**
   - Problem: ground passes were sized to decelerate to a dead stop exactly at the receiver, so they crawled through their last metres. Every pass over 300px (~14m) was lofted, so the v2 AI played more lofted passes than ground passes (222 vs 184 per 8 matches).
   - Fix: `Ball.GROUND_PASS_ARRIVAL_SPEED` (110 px/s, still an easy first touch) and `DISTANCE_HIGH_PASS` 300 → 520px (~25m).
   - Result, v2 vs v2 (8 × 180s): ground:lofted went from 184:222 to 393:93. Forward share is 55% ✓, progressive share 16–18% ✓, average pass 23m ✓, and **28/37 metrics are in band**, the best yet.
   - Exposed next problem: sterile possession, with 8.1 passes per possession, 93% completion and ~1.3 shots per 180s. That's the chance-creation work.
6. **No first-touch difficulty: ✅ ADDED (2026-09-28).**
   - Problem: every ball within reach stuck to the player instantly, so a 40m lofted ball was as safe as a 5m roll. Once lofted passes worked (Finding #5), hoofing long from the back was the rational v2 choice: 94–96% of passes from its own third went forward, averaging 32–36m.
   - Fix: `Player.control_chance(speed, height)`. Difficulty rises with arrival speed above 160 px/s and with height above 10px; dribbling and passing skill cancel up to 75% of it. A failed touch (`BallStateFreeform._heavy_touch`) slows the ball, deflects it up to 70° and leaves the player a short cooldown before they can touch it again. It fires `GameEvents.heavy_touch`.
   - `PassModel` multiplies in the expected control at arrival (speed and height from the predicted path), with 40% of fumbles still recovered.
   - Result: lofted passes are now fumbled 14–21% of the time, and 66–74% reach the receiver. v2 vs v1 went from 0W 5D 3L to 2W 6D 0L.
5. **The recurring "long passes fall short" bug, root causes: ✅ FIXED (2026-09-28).** The user flagged it as an old, recurring bug. Git history shows the lofted-pass launch was re-derived in Nov 2025, in May 2026 and again in Finding #2. Every attempt was checked against an idealised replay, never against live play.
   - **How it was found.** `PassTracer` (`scenes/match/stats/pass_tracer.gd`, enabled with `BATCH_PASSTRACE=1`) follows every real pass from kick to whatever ends it.
   - **Cause 1: the ball was caught in mid-flight.** Ball pickup was a flat 2D area check that ignored height, so any player the ball passed *over* collected it. 28–38% of lofted passes ended that way, at 18–27px height, many within the first 40% of the flight and mostly by opponents. That was the visible symptom, and it's invisible to any launch-maths fix.
     - Fix: `Player.MAX_COLLECT_HEIGHT` (20px, about chest reach) is enforced in `BallStateFreeform._try_collect`. The overlap poll from Finding #3 re-checks every frame, so the ball becomes collectable as it comes down.
     - `BallPredictor.earliest_intercept` and `PassModel` skip samples above reach height, so the AI models agree with the engine.
   - **Cause 2: the ball hopped over the receiver.** Ground bounces kept 80% of vertical speed, so the first hop rose to 64% of the arc and skipped over a receiver standing on the landing spot. It also kept 80% of horizontal speed, so missed long balls rolled on and 19% went out of play.
     - Fix: new `Ball.GROUND_BOUNCE_VERTICAL` (0.5) and `GROUND_BOUNCE_ROLL` (0.6). Wall rebounds keep `BOUNCINESS` 0.8.
   - **Cause 3: v1 receivers didn't go to the ball.** v1 had no receive behaviour; the intended receiver kept running their role target.
     - Fix: `Ball.intended_receiver` (set on `pass_attempted`). v1's `AIBehavior` now sends that player to the predicted, height-aware meeting point. v2 already had RECEIVE.
   - **Result** (pass tracer, 4 × 180s, seeds 300–303):

     | | v1 before | v1 after | v2 before | v2 after |
     |---|---|---|---|---|
     | Lofted pass reaches the receiver | 11% | **77%** | 69% | **79%** |
     | Lofted pass won by an opponent | 48% | 14% | 7% | 11% |
     | Lofted pass goes out of play | 18% | 0% | 19% | 8% |

     v1 ground passes reaching the receiver rose from 28% to 63%. v1 overall pass completion (6 × 180s) rose from **45% to ~73%**.
   - Tests: `test_lofted_pass_flies_over_midway_defender`; `tools/ball_probe.tscn` still measures first landing at 97–98% of the target.
3. **Loose ball never collected by a player already standing on it: ✅ FIXED (2026-09-28).** Pickup only fired on `body_entered`. A player who reached a stopped ball while unable to carry it (mid-tackle or recovering), or a chaser who stopped exactly on it, never re-entered, so the ball sat dead for 50+ seconds. Found with the harness heartbeat trace. `BallStateFreeform` now also polls overlaps each physics frame. `Ball.KICK_COOLDOWN_MS` (300 ms) stops the kicker from re-collecting their own kick.
4. **Tactics frozen for a whole match after the first one in a session: ✅ FIXED (2026-09-28). A regression I introduced in Phase 1.**
   - Cause: `ActorsContainer.time_since_last_tactical_refresh` was initialised from `MatchClock.now_ms()` when the scene was *instantiated*, before `MatchWorld._enter_tree()` reset the clock to 0. After a previous match that captured value was huge, so the refresh check stayed false for as long as the previous match had lasted.
   - Effect: neither v1's TeamTacticalState nor v2's TeamBrain ever updated. This affects any second match played in a session, not just the harness.
   - It also invalidated the 40-match v1 baseline (every match after the first).
   - Found because the same seed gave 5/19 passes standalone but 0/3 as the second match of a batch. Fixed by initialising in `_ready()`, after the reset.
2. **Every lofted pass fell short at ~26–30% of its intended distance: ✅ FIXED (2026-09-28).** Found by validating BallPredictor against the real ball (`tools/ball_probe.tscn`): 350px → 90px, 600px → 180px, 900px → 264px.
   - Cause: `pass_to`'s lofted branch sized speed for air friction but set `height_velocity` via a sqrt(dt) scale. Under the engine's per-tick height integration that gave ~0.3s of airtime, so the ball landed almost at once and ground friction stopped it early.
   - Consequence: in v1, every pass over 300px, including switches, through balls and long outlets, went to nobody. That's a large hidden contributor to v1's poor completion and scrum-like play.
   - Fix: `Ball.pass_launch()` picks an airtime from distance (`loft_time`, 0.7–1.6s), sets `height_velocity = GRAVITY·T/2` from the discrete scheme, and sizes speed as `(d + ½·a_air·T²)/T`. Measured first landing is now 97–98% of the target.
   - Follow-up for Phase 7: after landing, a missed long ball rolls far past the target (the bounce keeps 80% of horizontal speed). The receiving/first-touch work should handle this, and arc heights (45–190px) should be reviewed once height starts to matter for interceptions.
   - The pre-rules v1 baseline predates this fix.
1. **The pitch is drawn in perspective** (2026-09-28). The end-line walls in `world.tscn` are slanted polygons, not vertical lines, so `ActorsContainer.FIELD_LEFT/RIGHT` are only approximations of the goal lines. Phase 2's out-of-play detection must use the real wall lines. It keeps the walls as a physical backstop and detects the ball crossing a line just inside them.
