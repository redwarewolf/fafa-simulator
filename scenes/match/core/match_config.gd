class_name MatchConfig
extends RefCounted

## Process-wide match settings. Normal play leaves every value at its
## default; tools/batch_match.gd overrides them before loading the match
## scene. Static vars (not an autoload) because nothing here needs to tick.

## True when running under the headless batch harness — MatchWorld skips
## stadium/crowd setup, random narrated events, the end-of-match popup and
## season bookkeeping, and hands its result to the harness instead.
static var headless := false
## Seed for MatchRng at match start; < 0 means random (normal play).
static var match_seed := -1
## Harness-only: skip RandomEvents' mid-match narrated interruptions.
static var disable_random_events := false
## Harness-only: match length override in simulation seconds; <= 0 uses
## MatchWorld.MATCH_DURATION.
static var match_duration_override := -1.0

static func reset_to_defaults() -> void:
	headless = false
	match_seed = -1
	disable_random_events = false
	match_duration_override = -1.0
