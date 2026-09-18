class_name TacticBuilder
extends RefCounted

## Builds a tactic for an AI-controlled club from its OWN roster, independent
## of whatever tactic/template the player happens to have selected. Used by
## ActorsContainer so the opponent stops literally mirroring the player's
## tactic (same slot count, same shape, same players) and instead fields a
## shape suited to its own squad.

const TacticResourceClass = preload("res://resources/tactic_resource.gd")

## Greedily gives each slot the best-fitting unused player from [param players]
## (NATURAL aptitude before SECONDARY before out-of-position). Mirrors
## GameState._auto_fill_tactic() — kept here too so AI tactics don't need a
## player-facing GameState round-trip to build.
static func auto_fill(t: Resource, players: Array) -> void:
	var available : Array = players.duplicate()
	for i in t.slots.size():
		if available.is_empty():
			break
		var slot_role : Positions.Role = t.slots[i].role
		var best_idx := 0
		var best_apt : Positions.Aptitude = Positions.aptitude(available[0].role, slot_role)
		for j in range(1, available.size()):
			var apt : Positions.Aptitude = Positions.aptitude(available[j].role, slot_role)
			if apt < best_apt:
				best_apt = apt
				best_idx = j
		t.assign_player(i, available[best_idx])
		available.remove_at(best_idx)

## Lower is a better fit: NATURAL=0, SECONDARY=1, OUT_OF_POSITION=2 per filled
## slot, plus a heavy penalty per slot a short roster left empty.
static func _fit_score(t: Resource) -> int:
	const EMPTY_SLOT_PENALTY := 5
	var score := 0
	for slot in t.slots:
		if slot.is_assigned():
			score += Positions.aptitude(slot.player.role, slot.role) as int
		else:
			score += EMPTY_SLOT_PENALTY
	return score

## Tries every formation template, auto-filling each from [param club]'s own
## players, and keeps whichever one fits that squad best — so a club heavy on
## defenders ends up in a back five instead of whatever shape the player is
## running. Ties break toward the first template checked (Formations.ALL order).
static func build_best_fit(club: ClubResource) -> Resource:
	var best_tactic : Resource = null
	var best_score := INF
	for template in Formations.ALL.keys():
		var t : Resource = TacticResourceClass.new(template, template)
		t.init_slots_from_positions(Formations.positions_for(template), Formations.roles_for(template))
		auto_fill(t, club.players)
		var score := _fit_score(t)
		if score < best_score:
			best_score = score
			best_tactic = t
	return best_tactic
