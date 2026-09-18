# FAFA Simulator — Match AI Overhaul: Design & Roadmap

_Living document — update the Status line under each phase as work lands. This is the persistent record across sessions; the source-of-truth plan this was written from is this file itself from here on._

## Context

FAFA Simulator is a simulation-first football management game: matches are fully AI-vs-AI simulations the player watches, not something the player directly controls. The goal is match AI as close to "perfect/best possible" as research supports, but the actual success bar is **fun and legible to watch**, not benchmark realism — arcade/sim design research backs this directly: "players aren't rejecting realism entirely; they're rejecting realism that gets in the way of fun." Every design choice below is judged against that bar, not against how closely it mimics a real match engine.

A checkpoint commit (`c8c61f0`) was pushed to `origin/main` before this work started, so we can always roll back.

Research covered: EA Sports FC's role-based "FC IQ" off-ball system, RoboCup 2D simulation league formation/strategy research, football-analytics pitch-control/Voronoi space models, expected-pass-completion (xPass) models, Football Manager's per-slice match engine, Craig Reynolds' steering behaviors (esp. Interpose), GOAP/utility-AI hybrid practice, real tactical patterns (overlap/underlap/third-man runs, offside trap/defensive line coordination), and arcade-vs-sim game-feel design philosophy.

## What "full redesign from first principles" means here

Reading the actual current implementation (`scenes/characters/ai/*.gd`, `team_tactical_state.gd`, `locomotion.gd`, `field_zones.gd`, `formations.gd`) in full confirms it is **already** a deliberately-built utility-AI + candidate-point-scoring + shared-team-state system, with detailed rationale comments explaining exactly why each design choice was made (e.g. candidate scoring explicitly replacing a steering-vector-sum approach because sums can't express "go to that specific pocket"; man-marking already leads targets by velocity; pressing already has commitment hysteresis to stop flip-flopping). This **is** what a first-principles derivation from the research converges on independently — it's not a coincidence, it's the same reasoning RoboCup teams and utility-AI practitioners converged on.

So "first principles redesign" here means: **derive the target architecture from the research fresh, without being anchored to "patch known gaps" — and where the current code already matches what that derivation produces, extend it in place rather than rewriting working, well-reasoned code for its own sake.** The actual gaps get new architecture, described below.

## Target architecture (layers)

1. **Locomotion** (`locomotion.gd`) — unchanged. Steering to a target point is a solved problem here.
2. **Role AI on-ball decisions** (`on_ball_utility.gd`) — kept, extended with a pitch-control-informed pass score (Phase 1).
3. **Role AI off-ball positioning** (`candidate_point_scorer.gd`, `role_ai.gd` + subclasses) — kept, extended with anticipatory space scoring (Phase 1) and generalized attacking-run triggers (Phase 3).
4. **Team Tactical Brain** (`team_tactical_state.gd`, extended) — new responsibilities: coordinated defensive line, multi-presser coordination, tactical presets (Phase 2). This is the layer with the real gaps today.
5. **Match Context / space model** (new: `scenes/characters/ai/pitch_control.gd`) — a new *shared per-tick primitive*, not a new decision-maker. Everything above reads from it; it decides nothing itself.
6. **Player personality/traits** (new, data-only) — Phase 4.
7. **Validation harness** (new) — debug overlay extension + scripted scenarios, built first (Phase 0) so every later phase is checked against something better than "eyeballing a full match."

## Roadmap

Each phase is independently shippable and playtestable before starting the next. Validate every phase with all three methods: play-test via the `run-fafa-simulator` skill, debug overlays/metrics, and scripted mini-scenarios.

### Phase 0 — Validation harness ✅ DONE (2026-09-18)
- `utils/debug_draw.gd`: added `SHOW_PITCH_CONTROL` toggle + a `rect_filled()` primitive (filled world-space quads, for a heatmap) — empty until Phase 1 populates it.
- `scenes/world/scenario_debug.gd`: a dev-only scripted-scenario library (`2v1_break`, `corner_defense`, `goal_kick_buildup` so far) that teleports a handful of already-spawned players + the ball into a named layout and freezes everyone else (`PROCESS_MODE_DISABLED`, the same mechanism `MatchWorld` already uses for kickoff/foul restarts), then lets the normal `AIBehavior`/`RoleAI`/`TeamTacticalState` loop take over unmodified.
- Trigger mechanism: `MatchWorld._poll_scenario_trigger()` polls `user://scenario_trigger.txt` every 0.5s (only while `DebugDraw.ENABLED`) — **not** a keybind. A `run-fafa-simulator`-driven `PostMessage`'d `WM_KEYDOWN` was tried first and confirmed **not** to reach Godot's window (likely gated on real OS focus, unlike the mouse clicks that skill already uses successfully) — a file poll sidesteps that entirely and is what any external driver should use to trigger a scenario going forward.
- **Verified working** (2026-09-18, via `run-fafa-simulator` + reading `godot.log`): triggering `2v1_break` mid-match repositioned exactly the 4 scripted players and produced an immediate breakaway goal — a good sign the AI converts clean chances. Caveat for future use: a scenario can resolve in well under a second (it drops players into a live decision point, not a paused diagram) and a goal immediately triggers the normal `SCORED → RESET → KICKOFF` cycle, which re-enables everyone and undoes the scenario layout — so screenshot/observe immediately after triggering, or watch behavior that doesn't end in an instant shot. A "pause after N seconds" option would help here and is a reasonable future addition, not required for Phase 0's goal of "can we isolate a situation at all."

### Phase 1 — Shared space model + anticipatory scoring ✅ DONE (2026-09-18)
- `scenes/characters/ai/pitch_control.gd`: new `PitchControl` utility — `time_to_reach(point, player)` estimates seconds to reach a point from a player's current position **and velocity** (a player already sprinting toward a point gets there sooner than one standing still or moving away, at equal distance); `control(point, team_a, team_b)` and `opponent_reach_time(point, opponents)` build on that per-player estimate. Deliberately called per-candidate-point, not integrated as a continuous field.
- `CandidatePointScorer.opponent_reach_space()`: same 0..`SPACE_SATURATION_RADIUS` scale as the old flat-distance `nearest_opponent_distance()`, but time-to-reach-based — wired into both the attacking space term and the defending-candidate pressure term in `score_off_ball_candidate()`, so off-ball positioning (attacking runs and covering positioning alike) now anticipates where space is opening rather than only reacting to current opponent positions. `nearest_opponent_distance()` itself is untouched and still used by `GoalieAI`'s contested-radius reject, which is intentionally a static "how far right now" check, not an anticipatory one.
- `OnBallUtility._receiver_openness_penalty()`: swapped to `opponent_reach_space()` too — a receiver being closed down by a sprinting defender now scores as more tightly marked than raw distance alone would show. (A fuller xPass-style probability model replacing the whole pass-scoring shape, rather than just its space input, is still a possible future refinement if playtesting shows this isn't enough — not needed yet.)
- `DebugDraw.SHOW_PITCH_CONTROL` populated: `ActorsContainer._draw_pitch_control_debug()` tints a coarse grid blue/red by team-control advantage every frame while the toggle is on.
- **Verified** (2026-09-18, via `run-fafa-simulator`): heatmap screenshot showed a clean blue/red split matching each team's actual half with a contested green seam at the halfway line — pitch control tracks real space correctly. A few seconds of normal play afterward showed no script errors and a sensible-looking kickoff shape, confirming the on-ball/off-ball wiring didn't regress normal behavior.

### Phase 2 — Team Tactical Brain: coordinated line + multi-presser + presets ✅ DONE (2026-09-18)
- `scenes/characters/ai/tactic_preset.gd`: new `TacticPreset` — `mentality` (-1..+1) and `press_intensity` (0..1), derived automatically from a roster's OFFENSE-vs-DEFENSE role-group counts (no tactics-board UI work in this scope). Cached once per `TeamTacticalState` per match.
- Coordinated shared shape: `TeamTacticalState._recompute_line_bias()` computes one `team_line_bias` value per team per tick (mentality baseline + reactive push-up/drop-off from ball depth), written onto every `Player` and read by `RoleAI._ball_depth_base_position()` on top of each role's own `depth_offset()`. Same-role players already agreed on a band from that formula alone (deterministic off the same ball depth) — this is specifically the team-wide shift that formula couldn't express: holding a higher or deeper line as a unit.
- Multi-presser coordination: `TeamTacticalState._recompute_cover_presser()` designates the next-closest teammate (after the primary presser) as `is_cover_presser`, with a `cover_shadow_point` roughly midway between the ball carrier and the opponents' most dangerous other option (nearest-to-own-goal), instead of also converging on the ball — `AIBehavior.perform_ai_movement()` steers there via `Locomotion.compute_velocity()` when set. The midpoint is a first-approximation interpose point, not a predicted-interception model — flagged as a tuning candidate for Phase 6 if it doesn't read well enough in practice.
- `press_intensity` also feeds `_recompute_pressing()`'s takeover margin — a more attacking-shaped side contests the ball a bit more eagerly.
- Debug: `SHOW_PRESSING_LINES` draws the cover presser's shadow line in orange; `SHOW_INTENT_LINES` recognizes a `"cover"` intent kind with the same color.
- Explicitly out of scope: an actual offside rule (`referee.gd` is purely decorative today, no offside enforcement exists) — that's a rules/referee feature, not AI, and needs its own scoping.
- **Verified** (2026-09-18, via `run-fafa-simulator`): three screenshots across live play all show the orange cover-shadow line/cross rendering in a plausible position near the ball contest, alongside the existing red primary-press line and green role-target lines rendering normally. No script errors in `godot.log` across the whole session.

### Phase 3 — Attacking patterns & off-ball intelligence
Status: not started.
- Generalize `ForwardAI`'s existing run-trigger logic (`_off_ball_base_position` override) so fullbacks/wingers can trigger overlaps and central midfielders can trigger underlaps/third-man runs — kept emergent from candidate scoring, not scripted set patterns.
- "Don't cluster" bias: when two attackers already occupy similar depth/lane, bias the trailing one toward a third-man pocket instead of duplicating the run.
- Validate: `goal_kick_buildup` scripted scenario, full-match eye test.

### Phase 4 — Player personality/role traits (data-only, low risk)
Status: not started.
- Small named-trait system layered onto individual players (Poacher / Playmaker / Box-to-Box / Target Man / Wide Outlet, or similar), adjusting `RoleAI.role_weights()` and off-ball base-point bias per player, not just per position group.

### Phase 5 — Fatigue/stamina polish (confirm scope before starting)
Status: not started.
- Check whether a stamina/fatigue stat already exists anywhere in the Player/match-stat model before designing this — if not, this touches the broader stat model, not just AI, and should be re-scoped with the user first.
- If in scope: fatigue accumulator decaying speed/aggression over 90 minutes; formalize the already-implicit "calm" (holding shape) vs "active" (pressing/marking/urgent recovery) mode split.

### Phase 6 — Tuning & final polish
Status: not started.
- Full-match playtesting across multiple formations/tactics, constant tuning, cleanup of standing debug output (e.g. `GoalieAI.DEBUG_LOG_DISTRIBUTION` is currently hardcoded `true`).

## Verification approach (applies to every phase)

1. **Play-test** via the `run-fafa-simulator` skill — run/watch simulated matches after each phase, eye-test for purposeful-looking movement, sensible marking, no obviously dumb moments.
2. **Debug overlays** — extend `utils/debug_draw.gd`'s existing toggles (pressing/marking/intent lines, role ranges, GK distribution, and now pitch-control) rather than building a separate metrics system from scratch.
3. **Scripted scenarios** — `scenes/world/scenario_debug.gd`'s named mini-situations, triggered by writing a scenario name to `user://scenario_trigger.txt` while `DebugDraw.ENABLED` is `true`, to sanity-check specific behaviors in isolation before trusting them in a full match.
