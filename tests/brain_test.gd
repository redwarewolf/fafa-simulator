extends TestCase

## Engine-v2 brain building blocks (Phases 4-6).

func _rows(data: Array) -> Array:
	var out := []
	for r in data:
		out.append(PackedFloat32Array(r))
	return out

## Brute-force optimum over all injective row→column maps, for checking.
func _brute(cost: Array) -> float:
	var n := cost.size()
	var m : int = cost[0].size()
	var best := [INF]
	var used := []
	used.resize(m)
	used.fill(false)
	_brute_rec(cost, 0, n, m, used, 0.0, best)
	return best[0]

## No branch-and-bound pruning: costs can be negative, so a partial sum
## already above the best total can still end up below it.
func _brute_rec(cost: Array, i: int, n: int, m: int, used: Array, acc: float, best: Array) -> void:
	if i == n:
		best[0] = minf(best[0], acc)
		return
	for j in m:
		if not used[j]:
			used[j] = true
			_brute_rec(cost, i + 1, n, m, used, acc + cost[i][j], best)
			used[j] = false

func test_hungarian_square_known_answer() -> void:
	var cost := _rows([[4, 1, 3], [2, 0, 5], [3, 2, 2]])
	var a := Hungarian.solve(cost)
	assert_near(Hungarian.total_cost(cost, a), 5.0, 0.0001, "classic 3x3 optimum")

func test_hungarian_assignment_is_injective() -> void:
	var cost := _rows([[1, 1, 1, 1], [1, 1, 1, 1], [1, 1, 1, 1]])
	var a := Hungarian.solve(cost)
	var seen := {}
	for j in a:
		assert_true(not seen.has(j), "column %d used twice" % j)
		seen[j] = true

func test_hungarian_matches_brute_force_on_random_rectangles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for trial in 30:
		var n := rng.randi_range(1, 6)
		var m := rng.randi_range(n, 8)
		var data := []
		for i in n:
			var row := []
			for j in m:
				row.append(rng.randf_range(-5.0, 10.0))
			data.append(row)
		var cost := _rows(data)
		var a := Hungarian.solve(cost)
		assert_near(Hungarian.total_cost(cost, a), _brute(cost), 0.001, "trial %d (%dx%d)" % [trial, n, m])

## The reason greedy marking fails: both defenders' nearest attacker is A.
func test_hungarian_beats_greedy() -> void:
	# rows = defenders, cols = attackers A, B
	var cost := _rows([[1.0, 2.0], [1.1, 9.0]])
	var a := Hungarian.solve(cost)
	assert_eq(a[0], 1, "defender 0 takes B")
	assert_eq(a[1], 0, "defender 1 takes A")
