class_name AIProfile
extends RefCounted

## Cumulative per-section CPU timing for the match AI (frame-budget work,
## docs/match-engine-v2.md Phase 9). Sections wrap themselves:
##     var t0 := AIProfile.begin()
##     ...
##     AIProfile.end("team_brain", t0)
## and the batch harness prints/reset()s the totals per match. Negligible cost
## (two Time.get_ticks_usec() calls) so it stays on.

static var _usec := {}
static var _calls := {}

static func begin() -> int:
	return Time.get_ticks_usec()

static func end(section: String, t0: int) -> void:
	_usec[section] = _usec.get(section, 0) + (Time.get_ticks_usec() - t0)
	_calls[section] = _calls.get(section, 0) + 1

static func reset() -> void:
	_usec.clear()
	_calls.clear()
	_counts.clear()
	_sums.clear()

# ─── Decision telemetry (counts and value sums, not timings) ────────────────

static var _counts := {}
static var _sums := {}

static func count(key: String, value: float = 0.0) -> void:
	_counts[key] = _counts.get(key, 0) + 1
	_sums[key] = _sums.get(key, 0.0) + value

## {key: {"n": count, "mean": mean of the values passed}}
static func counters() -> Dictionary:
	var out := {}
	for k in _counts:
		out[k] = {"n": _counts[k], "mean": _sums[k] / maxi(_counts[k], 1)}
	return out

## {section: {"ms": total ms, "calls": n, "us_per_call": mean}}
static func report() -> Dictionary:
	var out := {}
	for k in _usec:
		out[k] = {"ms": _usec[k] / 1000.0, "calls": _calls[k], "us_per_call": float(_usec[k]) / maxi(_calls[k], 1)}
	return out
