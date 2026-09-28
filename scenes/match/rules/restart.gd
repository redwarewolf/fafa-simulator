class_name Restart
extends RefCounted

## Set-piece restart kinds and their rule-level properties. MatchWorld runs
## every restart through one RESTART state (see MatchWorld.award_restart);
## what differs per kind lives here. See docs/match-engine-v2.md Phase 2.

enum Kind { FREE_KICK, OFFSIDE, THROW_IN, CORNER, GOAL_KICK }

## HUD toast per kind (tr() keys — see utils/locale_en.gd).
const LABELS := {
	Kind.FREE_KICK: "¡FALTA!",
	Kind.OFFSIDE: "¡FUERA DE JUEGO!",
	Kind.THROW_IN: "SAQUE DE BANDA",
	Kind.CORNER: "¡CÓRNER!",
	Kind.GOAL_KICK: "SAQUE DE META",
}

## Short machine names for analytics output.
const KEYS := {
	Kind.FREE_KICK: "free_kick", Kind.OFFSIDE: "offside", Kind.THROW_IN: "throw_in",
	Kind.CORNER: "corner", Kind.GOAL_KICK: "goal_kick",
}

## Law 11: no offside offence directly from a throw-in, corner or goal kick.
static func offside_exempt(kind: int) -> bool:
	return kind in [Kind.THROW_IN, Kind.CORNER, Kind.GOAL_KICK]

## Opponents inside this radius of the spot are moved back to it (Law 13/17:
## 9.15m for free kicks and corners; 2m for throw-ins). Pixel values
## follow the pitch scale (~20px per metre along the length) — the free-kick
## value matches MatchWorld's original MIN_FOUL_RETREAT_DISTANCE.
static func retreat_distance(kind: int) -> float:
	match kind:
		Kind.THROW_IN:
			return 50.0
		Kind.GOAL_KICK:
			return 0.0  # handled as "clear the penalty area" instead
		_:
			return 110.0

## Whether the taker is teleported next to the spot (quick restart, since
## match time is compressed ~15x) rather than having to run to it. A fouled
## player is already at the spot.
static func teleports_taker(kind: int) -> bool:
	return kind != Kind.FREE_KICK
