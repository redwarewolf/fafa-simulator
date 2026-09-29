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
| 4 | Tactical Brain: phase classification + hysteresis, live team shape, instructions | ✅ working; pressing still weak (PPDA ~3–4) |
| 5 | Coordinators: defensive / attacking / set-piece role assignment (Hungarian) | ✅ done, incl. set-piece coordinator |
| 6 | Player Brain: mental attributes, grid off-ball positioning, EPV on-ball decisions, receiving | ✅ working; receiving fix (Finding #10) |
| 7 | Execution: accel/turn-limited locomotion, tackle model, touch dribbling | ✅ done (parts 1–4) |
| 8 | Analytic goalkeeper | ✅ core done: positioning, sweeping, calibrated shot-stopping, catch/parry, distribution |
| 9 | Performance budget / scheduler | 🟡 ~1.5 ms/frame for all AI; no scheduler needed yet |
| 10 | Calibration, A/B vs v1, delete v1 | 🟡 v2 beat v1 33-24-7; **v1 deleted (2026-09-29)**; xT re-fit pending |

**v1 is gone.** The original AI has been deleted: RoleAI and its four subclasses, GoalieAI, CandidatePointScorer, OnBallUtility, TeamTacticalState, AIBehaviorFactory, PlayerTraits and GeometryUtils. So have the AI-version toggle (pause menu, `GameState`, `MatchConfig`) and the harness `--a/--b` version flags. Every match now runs engine v2. `AIBehavior` is a thin dispatcher to `PlayerBrain`/`GoalkeeperBrain`. The inert `FieldAreas` zone node in `world.tscn` (FieldZones) is left for a later scene cleanup.

## Verification (every phase)
1. `<godot_console> --path . --headless res://tests/run_tests.tscn` runs the maths unit tests.
2. `tools/run_parallel.sh <label> <shards> <per_shard> <duration> [seed]` (with `PARAMS="knob=v,..."` for variants) checks metrics against `tools/targets.json`. For a single process: `batch_match.tscn -- --matches N --seed S --duration 480`. Probes: `rules_probe.tscn`, `setpiece_probe.tscn`, `ball_probe.tscn`, always with `--fixed-fps 60`.
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

## Tuning round 4: chance creation (2026-09-28)

Measurement upgrades:
- **Per-possession rates** (`shots_per_possession`, `xg_per_possession`, `box_receptions_per_possession`) replace compressed-time totals as targets. 360s stands for 90 minutes but players move at real speed, so a match fits only ~1/3 of a real match's possessions. Measured per possession, v2 is already realistic: ~0.17 shots and ~0.02 xG per possession.
- **Shot creation** (`shot_share_after_pass/won/loose`, `xg_per_shot_after_*`, `shot_carry_m`): how each shooter got the ball and how far they carried it before shooting.
- **`tools/run_parallel.sh`** runs parallel shards and merges them with `batch_match --merge` (32 matches in ~3 min on 16 cores). Same seeds give identical results at scale.
- **`Tuning` knobs + `--param` / `PARAMS=`** run variants on the same code and seeds. The summary now reports the **xG difference and goal difference per match with standard errors**. At 32 matches the W/D/L record swung from 7-20-5 to 2-25-5 to 4-19-9 on small changes, so records are noise; judge by xG difference with |mean| > 2·SE.

Changes:
- **Forward (breakaway) potential** (dynamic programming over the control grid toward goal). Through balls into the space behind a high line had been valued at ~0.01, below a sideways carry. v2 vs v2 xG per side went from ~0.12 to ~0.3.
- **Tackle judgement**: commit only on good duel odds (`Player.tackle_win_chance`), stricter in our own third, looser when the carrier is about to shoot; otherwise jockey goal-side. v2 had been making 16.7 tackles per 180s at 53% success.
- **One-step shot lookahead** (`SHOT_FOLLOWUP`): carries and passes are also worth the shot that could follow from the destination. Telemetry showed v2 shooting first-time on receipt (0.6m carried, 0.08 xG/shot) while v1 drove 12m closer first (0.23 xG/shot).
  - A follow-up trace at the moment v2 chose to shoot showed its carry options only had a 52% chance of keeping the ball, so shooting was actually the right call there. The real asymmetry was defensive, which led to the next change.
- **Must-stop danger check uses geometry-only xG.** The contextual xG counted the jockeying defender as a blocker, so he suppressed his own danger signal and backed off to the penalty spot.
- **Variant evaluation, v2 vs v1, 64 × 180s each, seeds 700+** (xG diff = v2 − v1 per match, ± SE):

  | Variant | xG diff | v1 xG | v2 tackles |
  |---|---|---|---|
  | A: lookahead + tackle judgement + geometric must-stop | −0.125 ± 0.070 | 0.265 | 10.3 |
  | B: A without the shot lookahead | −0.063 ± 0.056 | 0.216 | 11.0 |
  | C: A with the contextual must-stop check | −0.022 ± 0.043 | 0.190 | 10.2 |
  | D: A without tackle judgement | **+0.027 ± 0.034** | **0.117** | 15.6 |
  | **E (adopted): no lookahead, no tackle judgement** | +0.024 ± 0.054 | 0.173 | |

  - **Neither change survived.** The earlier 32-match "improvement" from tackle judgement (5-18-9 → 7-20-5) was noise. Committing on every tackle in range concedes less than jockeying, even at ~52% duel odds.
  - Both changes are disabled by default but kept behind the `Tuning` knobs `shot_followup` and `tackle_judgement`, to re-test after the Phase 7 movement/tackle rework.
  - v2 vs v2 with E: 28/37 in band, 87% completion, 5.5 passes per possession.
  - **A-vs-A check:** this same-AI run came out +0.122 ± 0.052 (2.3 SE). That's either a ~1-in-50 fluke or SE underestimating the true noise. Until an A-vs-A calibration is run, treat differences under ~3 SE as unproven.

## Phase 8 notes: analytic goalkeeper

**Results (v2 vs v2, 64 × 180s each):**

| Configuration | on target | keeper save % | goals / xG |
|---|---|---|---|
| A: old keeper, old shot speed (140–274 px/s) | 63% | 63–69% | 1.21 / 0.90 |
| B: old keeper, realistic shot speed | 58–69% | **44–47%** | **2.9 / 2.8** |
| C: new keeper, realistic speed, old aim | 60–66% | 63% | 1.56 / 1.44 |
| **D (adopted): new keeper, realistic speed, post-aim** | 48–55% | **64–66%** | **0.84 / 1.01** |
| E, F: D + save bias 0.08 / 0.16 | 48–55% | 66–70% | 0.69–0.98 |

- **At realistic shot speed the old keeper collapses**, while the new one holds a realistic save rate.
- **Aim change:** shooters now aim 5px inside the post farther from the keeper, with 3–8° of error (by shooting power) plus 3° under pressure. The old inner-target aim put 60–66% of shots on target and goals at ~1.5× xG.
- **Save bias stays at 0.** The extra bias barely moves the numbers.
- **v1 players keep the legacy shot speed.** v1 sides still use GoalieAI, and v1 is being retired rather than re-tuned. In mixed v2-vs-v1 matches, v1's keeper saves 50% of v2's fast shots and v2's keeper saves 92% of v1's slow ones; overall goal difference is −0.05 ± 0.09. Watched matches always run both sides on the same AI.

Design:

`scenes/match/brain/goalkeeper_brain.gd` is used by v2 sides (Tuning knob `gk_v2`, default on). v1 sides keep GoalieAI.
- **Positioning:** stands on the goal-centre → ball line. Depth off the line is 12px for close danger, 42px at mid range, and up to 110px as a sweeper when the ball is deep in the other half. Clamped just outside the posts.
- **Sweeping and claiming:** rushes a loose ball or through ball when `BallPredictor` says he's 0.3s ahead of every opponent and the meeting point is in his box. He claims within 22px, up to 32px ball height (hands).
- **Shot stopping:**
  - A shot is a free ball over 150 px/s whose predicted path crosses the goal line inside the mouth.
  - After his reaction time (0.12–0.30s, from reflexes) he picks the path point he can reach with the most margin: `dive_speed·t + reach − distance`.
  - `P(save) = logistic(margin / 18px)`, minus a handling penalty on fast shots. The outcome is **rolled once**, then the dive plays out to match it.
  - A save dives to the ball with the hands collider enlarged to his reach. On contact he catches it (`CATCH_BASE` × handling, less for fast shots) or parries it away from goal and wide.
  - A miss dives just short with the hands disabled.
  - Deciding first and animating second makes goals vs xG calibratable. With the old keeper, saves were an accident of collider sizes.
- **Keeper attributes:** reflexes = 0.55·DEF + 0.25·PAC + 0.2·PHY; handling = 0.6·DEF + 0.4·PHY. These give reaction time, dive speed (170–300 px/s) and reach (14–22px).
- **Distribution:** after a 0.6–1.6s hold (quicker for better decision-makers), the best pass option from `OnBallEvaluator`.
- **Engine changes:**
  - `PlayerStateDiving` takes an explicit target, speed and duration.
  - `BallState.move_and_bounce` notifies the keeper on hand contact.
  - Each keeper gets his own copy of the hands shape (it was a shared sub-resource).
  - `GameEvents.keeper_decision` is fired for telemetry.
- **Goalkeeping telemetry** (`MatchStats`):
  - On-target is judged from the shot's velocity one frame after the strike.
  - Each shot's outcome is tracked: goal, keeper touch, or other.
  - Reported as `on_target_share`, `conversion_on_target`, `opp_keeper_save_share` and `goals_per_xg`.

## Set pieces (Phase 5, set-piece coordinator)

- **Flow (`MatchWorld`):** v2 players are no longer frozen during a RESTART; v1 players still are.
  - The ball is locked (`Ball.restart_locked_for`) so only the taker may touch it, and only after release.
  - Release happens when every box-area `SET_PIECE` post is manned (`TeamBrain.set_piece_ready`, 55px tolerance) and at least 0.8s has passed, or at the maximum wait (`Restart.setup_time`: corner 20s, free kick 8s, other restarts 3s, goal kick 0).
  - The safety timeout scales with that maximum. A flat 12s had been cutting every corner set-up short.
- **Set-piece shape lasts until the delivery (`MatchContext.set_piece_taker`).** Play resumes when the taker touches the ball, but the delivery comes a moment later; otherwise the attackers had already left the box.
- **Templates (`TeamBrain._set_piece_jobs`), assigned with everything else in the Hungarian solve:**
  - Attacking corner: near post, far post, six-yard centre, penalty spot and two edge-of-box spots, plus a short option. The strongest players (PHY) go to the box posts.
  - Defending corner: near post, three zonal six-yard spots, edge of the box, a counter outlet, and marks on up to 3 attackers in the box.
  - Free kick in range (xG ≥ 0.025): a 2–3 man wall at 9.15m on the ball–goal line.
  - Other restarts: shape plus support or marks around the placed ball, with no pressing or chasing.
  - Opponents' targets are pushed out of the retreat distance.
- **Crosses:** lofted (`force_loft`, carried through `Ball.pass_launch` → `BallPredictor` → `PassModel` → `PlayerStatePassing`) to teammates in the box, from corners and from wide attacking positions. There are no direct shots from corners or throw-ins.
- **Probe:** `tools/setpiece_probe.tscn` awards corners or free kicks repeatedly in live v2 matches and reports set-up time, delivery, box occupancy and outcome. Final corner numbers: 2.3 attackers vs 5.5 defenders in the box at the kick, 71–81% lofted deliveries, a shot after 25–70%, ~0.08 xG per corner (real ~0.035, so somewhat generous). Free kicks: a shot after 37–50%, ~0.05 xG.
- Getting there, the probe exposed:
  - the fixed set-up window was too short;
  - the shape dissolved before the delivery;
  - the 12s safety timeout was cutting set-ups short;
  - a probe measurement bug (reading the ball's lift before the kick).

## Phase 7 notes: movement

**Part 1: realistic speed, acceleration, tackle angle** (`b0beec1`), v2 players only (Tuning knob `realistic_movement`):
- **Speed and acceleration:** top speed 6.4–9.4 m/s from PAC; acceleration 3.2–5.5 m/s² from PAC/PHY, with braking 1.8× stronger.
  - Brains set a *desired* velocity; `Player.steer_velocity` reaches it within those limits, so runs curve and players can't reverse instantly.
  - `Player.pace` now holds the stat and `speed` the movement speed; v1 is unchanged.
- **Kinematic time-to-reach:** standing start vs flying start, and braking first when moving away (`PitchControl.kinematic_time`).
  - The grid's hot loop inlines it and skips players who can't beat the current best; the grid refreshes at 12 Hz.
  - Pitch control costs 0.86 ms/frame and the whole v2 AI ~1.5 ms/frame.
- **Tackle angle:** tackling from behind costs up to −0.12 on the duel odds; foul chance = 0.06 + 0.35·behind + 0.12·aggression.

**Effect (v2 vs v2, 64 × 180s):**

| per side, per 180s | old speed | realistic speed |
|---|---|---|
| goals | 0.22–0.25 | 0.52–0.58 |
| shots | 1.8 | 3.4 |
| turnovers | 4.9 | 14 |
| corners | 0.03 | 0.5 |
| W/D/L | 10/42/12 | 18/27/19 |
| pass completion | 90% | **69%** |
| passes per possession | 7.5 | **1.4** |

Keeper saves (72–74%) and goals/xG stayed calibrated.

**Re-tune:**
- **Pass-model calibration (PassTracer predicted vs actual):** the raw model was overconfident at the new tempo (0.78 predicted → 0.60 actual, 0.91 → 0.81, 0.99 → 0.91).
- **Platt scaling (0.6, −0.3) fixed the calibration but made play worse:** 64% completion, 73% forward, 48% progressive. Flattening every probability erased the difference between safe and risky passes. Disabled; kept as the `pass_cal_a/b` knobs.
- **The real lever: the price of losing the ball.** `OnBallEvaluator.RISK_SCALE` 1 → 3.5 means a midfield turnover now costs what the opponent's counter into our space is worth, not just their static xT there. Sweep:

  | variant (uncalibrated) | completion | forward | progressive | avg pass |
  |---|---|---|---|---|
  | risk ×2 | 71% | 65% | 30% | 25m |
  | **risk ×3.5 (adopted)** | 72–74% | 61–64% | 27–28% | 25m |

- **Still open:** passes per possession ~1.6, and the out-of-possession block at ~49m long (target ≤40).
- **Not done yet:** touch-based dribbling (the ball running ahead between touches).

**Part 2: defensive shape and short possessions** (all 64 × 180s, v2 vs v2):
- **Compactness:** new knobs `def_length_scale` and `counterpress_line_step`. The back line steps up behind a high counter-press. Adopted (0.75, +0.1): block length 49 → 46m, completion 76%, 28/43 metrics in band (was 24).
  - `press_trigger_shift` sweeps (−0.2 to +0.1) changed nothing measurable, so it stays at 0.
- **New telemetry: why possession ends** (`to_share_*`):

  | cause | share |
  |---|---|
  | ball out of play | 41–45% |
  | pass intercepted | 34–39% |
  | keeper | 13–15% |
  | loose | 6–8% |
  | tackled | ~1% |

- **New telemetry: why the ball went out** (`out_share_*`). Shots and carries were about 1/3 each, passes about 1/4, deflections about 5%.
- **Touchline margins:** carries must end ≥9% of the width inside the touchline (was 4%). Pass targets must be ≥8% inside (was 4%). Knobs: `carry_margin_x/y`, `pass_margin_y`.
  - Throw-ins fell from 2.2 to 1.6 per side and the carries-out share from 0.38 to 0.33. Completion rose to 76%.
- **In context:** since 180s ≈ a half, real football has *more* restarts than we do (≈10 throw-ins per side per half). Restarts are therefore not what makes possessions short. What remains is passes intercepted and the tempo of realistic movement. Ball-glued dribbling means a carrier can only lose the ball to a tackle (1%). Touch dribbling (next) will change that.

**Part 3: touch dribbling** (`BallStateCarried`, v2 carriers, knob `touch_dribble`, default on):
- **Touches:** above 25% of sprint speed the ball runs ahead of the carrier and comes back once per touch (0.65s). The distance ahead is speed × 0.32s (0 DRI) down to speed × 0.14s (100 DRI).
- **Pokes:** while the ball is more than 14px (about 0.7m) beyond the carrier's reach, any opponent within 16px gets one poke per touch. The poke uses the tackle duel odds (DEF vs DRI). It knocks the ball loose without a tackle, and the carrier can't re-collect it for 300ms.
- **Loose touches:** on each touch there's a chance the ball runs away and becomes a loose ball. The chance is 3% × speed fraction × (1.2 − DRI), and ×2.5 with a defender within 60px.
- **Shielding:** at low speed the ball sits on the far side from the nearest opponent (within 60px).
- **Lines:** a carrier near a line takes a shorter touch. The ball is pulled back until it's inside `OutOfPlay`'s detection line.
  - The first cut used a normalised margin smaller than OutOfPlay's 11px, and carries out of play went from 187 to 876 per 64 matches.
- **Telemetry:** `tel_dribble_poked`, `tel_dribble_loose_touch`, turnover cause `poked`, and the `td_touch` counter (distance to the nearest opponent at each touch).
- **A/B (64 × 180s):** neutral on every metric (turnovers 12.3–12.6 vs 12.5, completion 75–76%, goals/xG ≈ 1). Carries out of play fell 187 → 162.
  - Pokes (2) and runaway touches (5) are very rare. The nearest opponent is 6–8m away at a typical touch: carriers get the ball, hold briefly and pass, and when they run it's into space.
  - The mechanic works, but **defenders rarely get to a carrier at all** (tackles are ~1% of turnovers too). PPDA ~3 and short possessions come from passes being intercepted, not from duels. Pressing that actually closes a carrier down is the next lever.

**Part 4: pressing vs ball retention, and the receiving bug** (64 × 180s unless noted):
- **New pressure telemetry:** nearest opponent at reception and at pass release, share within 3m ("pressured"), and time on the ball.
  - Baseline: pressured at release **22%**, about the same as real football. Pressured at reception only **8%**, with the nearest opponent 12.3m away. Time on the ball before a pass 0.84s.
- **Pressing experiments** (knobs `press_on_pass`, `mark_danger_min`, `max_marks`). Press on the pass: while their pass travels, one defender runs to a spot goal-side of where the receiver will take it. More marks cover midfield receivers.
  - Pressure rose monotonically (at reception up to 17%, at release up to 34%). Every step shortened possessions further: passes per possession 1.86 → 1.49, completion −3 pts, PPDA 3.1 → 2.2, and xG against went *up*.
  - The attacking side simply couldn't keep the ball. All of these stay off by default.
- **The receiving bug (Finding #10).** PassTracer's new safe-pass breakdown showed passes rated ≥0.9 failing **11%** of the time.
  - The ball reached the end of its path and the receiver didn't collect it: only 2 were fumbles. The receiver passed **11–17px** from it, sometimes next to a stopped ball, and an opponent picked it up ~3s later.
  - Cause: pickup reach is only ~8–13px (ball `PlayerDetectionArea` r=4 vs body capsule). At realistic acceleration, a receiver sprinting to the *earliest* reachable meeting point runs through it a stride off-line or late and can't correct.
  - Fixes in the v2 brain only:
    - `BallPredictor.earliest_intercept` gained a `slack`. Receivers target the earliest point they can reach **0.5s before the ball** (knob `receive_slack`), falling back to no slack.
    - Arrival braking to CHASE/INTERCEPT/RECEIVE targets (`_arrival_cap`, knob `arrival_braking`).
    - A final approach within 45px that matches the ball's motion and closes at a stoppable speed (`_attack_ball`, knob `attack_ball`).
  - Effect on 8 traced matches: safe-pass failures 11.2% → 5.1% (≥0.97: 8.2% → 3.1%). Calibration at 0.99 predicted went from 0.90 to 0.97 actual.

  | per side | before | slack 0.3 | **slack 0.5 (adopted)** | slack 0.8 |
  |---|---|---|---|---|
  | pass completion | 75% | 78% | **80%** | 80–81% |
  | passes per possession | 1.86 | 2.17 | **2.43** | 2.46 |
  | turnovers | 12.5 | 11.4 | **10.3** | 10.7 |
  | metrics in band | 29 | 27 | **30** | 26 |

  - This is very likely the root of the old recurring "long pass bug": long passes reach the spot, and the receiver overruns them.
- **Press on the pass re-tested after the fix:** still −0.5 passes per possession and −3 pts completion for +4 pts of pressure, so it stays off.
  - The remaining gap to real football is on the ball: a pressured carrier should shield, recycle backwards or play first-time, rather than lose it.

**Step 0 diagnostics** (24 traced matches, v2 vs v2; `BATCH_PASSTRACE=1`, `dec_*` counters). They overturn that hypothesis.
- **Pressure isn't the leak.** Completion at the kick is realistic in every band:

  | band | predicted | actual |
  |---|---|---|
  | pressured (<3m) | 0.79 | 0.74 |
  | 3–6m | 0.84 | 0.78 |
  | free | 0.93 | 0.88 |

  - Real football is about 65–70% under pressure and 85–90% free.
  - Pressure arrives during the 0.2–0.3s wind-up on 31–41% of pressured or near passes.
  - Pressured carriers choose carry 45%, pass 35%, shoot 11%, hold 8%. Tackles and pokes are still about 1% of turnovers.
- **The leak is long passes into space.** Calibration by pass type:

  | pass type | n | predicted | actual | out of play |
  |---|---|---|---|---|
  | to feet, all | 787 | 0.91 | **0.90** | 3% |
  | to feet, >30m | 102 | 0.71 | 0.69 | **20%** |
  | into space, <15m | 92 | 0.88 | 0.78 | 0% |
  | into space, 15–30m | 80 | 0.83 | 0.79 | 8% |
  | into space, >30m | 109 | **0.65** | **0.32** | **27%** |
  | cross | 32 | 0.72 | 0.72 | 3% |

  - Passes to feet are well calibrated.
  - Long balls into space succeed half as often as `PassModel` thinks, and over a quarter of them run out of play. The model has no notion of the ball running out past the receiver.
- **Shots per possession stay at 0.29–0.30** (target ≤0.22). This is the other way possessions end too early.

**Step 1: rolling reception race in `PassModel`** (knob `pass_rolling_race`, default on).
- **Receiver:** meets the ball at the earliest point of its *real* path they can reach (`BallPredictor.earliest_intercept`). The old model treated the ball as waiting at the target.
- **Opponent:** races to that spot, no earlier than the ball itself gets there.
- **Out of play:** the receiver must also beat the ball crossing OutOfPlay's line.
- Unit test: a ball that rolls out before the runner rates far lower, while a pass to feet stays >0.9.
- **Traced (24 matches, same seed):**

  | | before | after |
  |---|---|---|
  | long passes into space played | 109 | 44 |
  | long passes into space, predicted → actual | 0.65 → 0.32 | 0.58 → 0.50 |
  | long passes into space going out | 27% | 7% |
  | overall calibration at 0.78 predicted | 0.62 actual | 0.78 actual |
  | overall calibration at 0.99 predicted | 0.96 actual | 0.96 actual |

- **64 × 180s vs the receiving-fix baseline (same seeds):**

  | | before | after |
  |---|---|---|
  | completion | 80% | **82.5%** |
  | passes per possession | 2.43 | **2.57** (now in band) |
  | turnovers | 10.3 | 9.5 |
  | forward share | 0.53–0.56 | unchanged |
  | goals/xG | ≈1 | 0.77–0.94 |
  | xG per side | 0.48–0.57 | 0.44–0.52 |

- **Still open:**
  - Short passes into space are overrated: 0.98 predicted → 0.78 actual (n=46).
  - Shots per possession 0.26–0.30.
  - PPDA ~3.3.

**Step 2: the "too many shots" were a keeper bug (Finding #11).**
- **Shots were well placed but too good.** Average distance 16m, but 0.18 xG per shot. 45% came straight after winning the ball in the attacking third, 0.57s after the win.
- **Half of all own-third turnovers were the goalkeeper's** (198 of 398).
- **PassTracer on keeper passes:** short passes to feet rated 0.98 completed **41%**.
  - The failures weren't interceptions. The ball stopped within 0.3s at the keeper's feet (reach ≈ 0) and he re-collected it, or a nearby opponent did.
  - Cause: the keeper's always-on hands collider stopped his own kick, and `on_ball_contact` treated it as a parry.
- **Fix:** `BallState.move_and_bounce` lets a v2 keeper's own kick pass through his body/hands during the kick cooldown. v1 is unaffected: its traced passes never end back with the passer.
- Keeper passes completed 41% → 89% (3 traced matches).
- **64 × 180s, same seeds:**

  | | before | after |
  |---|---|---|
  | completion | 82.5% | **85.5%** |
  | passes per possession | 2.57 | **3.20** |
  | turnovers per side | 9.5 | **7.9** |
  | shots per side | 2.7 | **1.9** |
  | xG per shot | 0.18 | **0.13** (in band) |
  | shots right after a win | 45% | **22%** |
  | own-third turnover share | 0.31–0.34 | **0.25–0.29** (in band) |
  | metrics in band | 30/43 | **32/43** |

- **Now open:**
  - Scoring is low: ~0.25 xG and goals per side per 180s, 40/64 draws.
  - Shots per possession 0.24 (target ≤0.22).
  - PPDA ~3.9.
  - Short passes into space are still overrated.

**Attack funnel** (MatchStats `funnel_*`: per possession, how far it got; 64 × 180s):

| per possession | v2 | real football (approx.) |
|---|---|---|
| reaches middle third | 67–71% | — |
| reaches final third | 40–41% | ~40–50% |
| reaches the box | 14–16% | ~15–20% |
| ends in a shot | 21–22% | ~10–12% |
| box possessions ending in a shot | 78–85% | lower |

- **Chance creation per possession is realistic, even generous.** xG per possession is ~0.03 vs real ~0.013, and about half of shots come from outside the box (average 19–20m).
- **Low scoring (~0.25 goals per side per 180s) is time compression, not poor attacking.**
  - A 180s half fits ~8 possessions per side against a real half's ~50: the clock is compressed ~15× while players move at realistic speed.
  - At realistic per-possession rates that gives ~1 goal per 360s match.
  - More goals needs either longer matches or a deliberate step away from per-possession realism. That is a design decision.

**Scoring decision (user):** more goals over strict realism, via two halves plus tuning.
- **Tuning alone inside 360s tops out around 1.9 goals per match** (sweep g1–g7, 64 × 180s each).
  - Shot volume is capped by possessions: even shooting at almost any chance only took shots per side per half from 1.9 to 2.4.
  - g7 reached 1.9 per match only with goals/xG 2.3 and 22m average shots.
- **Match structure:** `MATCH_DURATION` 360 → **480s**, two halves of 240s.
  - At 240s: a 2.5s `HALFTIME` pause ("ENTRETIEMPO"), a reset, and the side that didn't kick off first kicks off.
  - Ends are not swapped: pitch direction is baked into every team frame.
  - The HUD clock shows the match minute 0'–90' scaled to the 480s (`MatchWorld.game_minute`). Goal times use the same minutes in watched and simulated matches (`minute_label`).
  - Stamina drain is scaled by 360/480, so end-of-match fatigue is unchanged.
- **Goal tuning adopted (g5):** `SHOT_BIAS_SCALE` 1.6, `SHOT_ERROR_SCALE` 0.5, keeper `SAVE_BIAS` −0.1. Full 480s matches, 64 each:

  | | goals per match | draws | goals/xG | keeper save % | avg shot distance |
  |---|---|---|---|---|---|
  | halves only | 1.3 | 26 | 1.2–1.3 | 66–69% | 19m |
  | **+ g5 (adopted)** | **1.7** | 28 | 1.4–1.5 | 59–68% | 20–21m |
  | + g6 | 1.7 | 26 | 1.4–1.6 | 59–68% | 20–22m |

- **v2 is now the default for watched matches.** v2 vs v1, 64 full 480s matches:

  | per match | v2 | v1 |
  |---|---|---|
  | wins | 33 | 7 (24 draws) |
  | goals | 1.06 | 0.33 |
  | xG | 1.05 | 0.19 |
  | shots | 5.5 | 0.7 |
  | completion | 87% | 77% |

  - xG diff **+0.86 ± 0.10**, goal diff +0.73 ± 0.15.
  - `GameState.match_ai_version` defaults to "v2". Settings saved before `ai_default_rev` 2 are migrated once, since they only stored "v1" because any settings change wrote the old default.
  - The pause-menu toggle still switches back to v1.
- **Harness note:** `run_parallel.sh ... 180` now plays 180s matches *with* a half-time at 90s.

**Phase 7 part 5: movement feel** (user: turning felt slippery and top speed too high). 64 full 480s matches per row. Running load is measured by MatchStats `run_*`, sampled at 2 Hz in true m/s.

| | avg speed | >5.5 m/s | >7 m/s | >10 m/s | completion | PPDA | pressured at release | goals/match |
|---|---|---|---|---|---|---|---|---|
| start | 4.8 | 41% | 25% | 4.4% | 88% | 5 | — | 1.72 |
| 1. true distance | 3.8 | 30% | 9% | 0% | 92% | 9 | 13% | 1.28 |
| 2. gaits (first cut) | 2.5 | 7% | 1.5% | 0% | 97% | 20+ | 8% | 0.3–0.6 |
| 2. gaits + wider marking | 3.0 | 14% | 3% | 0% | 91% | 4.6 | 30% | 2.05 |
| **3. turning model** | **3.3** | **18%** | **5%** | **0%** | **92%** | **4.3** | **32%** | **2.49** |
| real football | ~2 | ~5–10% | ~1–3% | 0 | ~80–85% | 5–18 | ~20–30% | ~2.7 |

1. **True distance.** The pitch is drawn squashed vertically (0.048 m/px along, 0.079 m/px across), but movement ran in raw pixels, so moving up or down the screen was 1.62× too fast (a pace-100 player reached ~15 m/s).
   - `PitchSpace.ISO_Y` / `iso()` / `from_iso()` / `iso_len()` define an isotropic space.
   - `Player.steer_velocity`, `PitchControl.time_to_reach`, `PitchControlGrid`, arrival braking, carries and the tackle lunge all work in it.
   - Unit test: 20m across takes as long as 20m along. The ball still moves in raw pixels (not yet corrected).
2. **Gaits** (`PlayerBrain._gait_speed`, knob `gaits`):
   - Shape jobs walk under 4m off position, jog, run beyond 8m, and sprint beyond 20m in a transition.
   - Defensive jobs sprint to close gaps over 3m; markers keep pace with their runner.
   - Anyone within 20m of the ball works at full intensity. Press, chase, intercept and receive always sprint.
   - The first cut (gaits alone) showed the zonal block leaving receivers ~14m free. `press_on_pass` is now on, and marking extends to `MAX_MARKS` 6 / `MARK_DANGER_MIN` 0.003.
3. **Turning** (`Player._turn_and_run`, knob `turn_model`) replaces the linear velocity blend, which skidded sideways and backwards.
   - Direction rotates at `TURN_GRIP` × accel ÷ speed.
   - Turns over 75° brake to pivot speed first; below 30% of top speed a player turns on the spot.
   - Unit test: a full-speed reversal overruns under 6m.
4. **Animation** (`PlayerStateMoving`): idle/walk/run from real m/s (walk from 0.3, run from 2.2), with the cycle playback scaled to ground speed (walk 1.4 m/s = 1×, run 4.5 m/s = 1×, clamped 0.6–1.9×). Before, a fixed 0.6s run cycle at sprint speed looked like skating.

- **Still open:**
  - Completion (~92%) is a bit high and PPDA (~4.3) a bit low.
  - The ball's own physics still uses raw pixels, so passes across the pitch travel 1.62× faster in real terms. Use duration 480 for full matches; earlier 180s numbers are comparable as rates, not totals.

## Findings log
9. **Players move at ~40% of real speed: 🔶 OPEN (for Phase 7).** `Player.speed` is the raw PAC stat used directly as px/s (50–80), ×1.25 when sprinting. At ~21 px/m along the pitch that's ~2.4–4.8 m/s, while real sprints are 7–9 m/s. Ball speeds are realistic (passes, and shots since Finding #8). Consequences:
   - a match fits far fewer possessions than real football (an earlier note in this doc blamed time compression alone, which was wrong);
   - passes are fast relative to the players chasing them;
   - set pieces need ~18s for players to walk into position.
   - Fixing it changes the tempo of everything, so it belongs to the Phase 7 movement rework, followed by a full re-tune.
8. **Shots travelled at 7–13 m/s: ✅ CHANGED (2026-09-28).** `PlayerStateShooting.SHOT_SPEED_MIN/MAX` went from 140/274 px/s to 300/560 (~14–27 m/s; real shots are ~20–30 m/s). A keeper that actually reads the ball would save nearly every shot at the old speeds; goals had come mostly from the old keeper's clumsy physics. The old range stays available through the `shot_speed_legacy` knob for before/after comparisons.
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
