extends TestCase

## Substitutions.best_replacement(): the AI side's bench pick.

func _res(name: String, role: Positions.Role, ovr: int) -> PlayerResource:
	return PlayerResource.new(name, 0 as Player.SkinColor, 0 as Player.HairColor, role, 25,
		PlayerResource.Quality.COMMON, ovr, ovr, ovr, ovr, ovr, ovr)

func _pick(out_role: Positions.Role, bench: Array[PlayerResource]) -> PlayerResource:
	var outgoing := Player.new()
	outgoing.role = out_role
	var pick := Substitutions.best_replacement(outgoing, bench)
	outgoing.free()
	return pick

func test_prefers_same_position_over_better_player() -> void:
	var st := _res("ST", Positions.Role.ST, 40)
	var cb := _res("CB", Positions.Role.CB, 80)
	assert_eq(_pick(Positions.Role.ST, [cb, st] as Array[PlayerResource]), st)

func test_best_overall_within_position() -> void:
	var a := _res("A", Positions.Role.ST, 40)
	var b := _res("B", Positions.Role.ST, 60)
	assert_eq(_pick(Positions.Role.ST, [a, b] as Array[PlayerResource]), b)

func test_falls_back_to_outfield_never_keeper() -> void:
	var gk := _res("GK", Positions.Role.GK, 90)
	var cb := _res("CB", Positions.Role.CB, 30)
	assert_eq(_pick(Positions.Role.ST, [gk, cb] as Array[PlayerResource]), cb)
	assert_eq(_pick(Positions.Role.ST, [gk] as Array[PlayerResource]), null)
