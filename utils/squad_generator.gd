class_name SquadGenerator

## Assembles a balanced 11-player squad for a brand-new club, reusing
## PlayerFactory for name/stat/quality rolling. PlayerFactory alone only rolls
## one candidate with a fully random role — this fills a fixed set of role
## slots (1 GK + balanced lines), matching the convention every existing club
## JSON already follows (exactly 11 players, exactly 1 GK).

## A few hand-picked 11-role layouts (mirroring the tactic templates already
## offered in GameState._init_default_tactics: 4-4-2 / 4-3-3 / 3-5-2) so
## repeated squad generation doesn't always produce the same shape.
const ROLE_MANIFESTS : Array[Array] = [
	# 4-4-2
	[Positions.Role.GK, Positions.Role.LB, Positions.Role.CB, Positions.Role.CB, Positions.Role.RB,
	 Positions.Role.LM, Positions.Role.CM, Positions.Role.CM, Positions.Role.RM,
	 Positions.Role.ST, Positions.Role.ST],
	# 4-3-3
	[Positions.Role.GK, Positions.Role.LB, Positions.Role.CB, Positions.Role.CB, Positions.Role.RB,
	 Positions.Role.CDM, Positions.Role.CM, Positions.Role.CAM,
	 Positions.Role.LW, Positions.Role.ST, Positions.Role.RW],
	# 3-5-2
	[Positions.Role.GK, Positions.Role.CB, Positions.Role.CB, Positions.Role.CB,
	 Positions.Role.LM, Positions.Role.CDM, Positions.Role.CM, Positions.Role.RM, Positions.Role.CAM,
	 Positions.Role.ST, Positions.Role.ST],
]

## quality_odds: weights per PlayerResource.Quality tier, forwarded to
## PlayerFactory.generate_player() for every slot (see ClubFactory for the
## division-based tables this is normally called with).
static func generate_squad(quality_odds: Array) -> Array[PlayerResource]:
	var manifest : Array = ROLE_MANIFESTS.pick_random()
	var squad : Array[PlayerResource] = []
	for role in manifest:
		squad.append(PlayerFactory.generate_player(quality_odds, role))
	return squad
