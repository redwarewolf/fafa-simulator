class_name Hungarian
extends RefCounted

## Minimum-cost assignment (Kuhn–Munkres, the O(n²·m) potentials form) for
## a rectangular cost matrix with n rows ≤ m columns: every row (player) gets
## exactly one distinct column (job), minimising the total cost. This is what
## lets the coordinators hand out press/cover/mark/zone jobs as ONE team
## decision — no two players on the same job, no job left to whoever happens
## to be nearest first (the greedy nearest-distance marking v1 used can leave
## a far worse total when two defenders are both nearest the same attacker).
##
## [param cost] is an Array of n PackedFloat32Array rows of length m.
## Returns a PackedInt32Array of length n: column assigned to each row.

static func solve(cost: Array) -> PackedInt32Array:
	var n := cost.size()
	var result := PackedInt32Array()
	result.resize(n)
	if n == 0:
		return result
	var m : int = cost[0].size()
	assert(m >= n, "Hungarian.solve needs at least as many columns as rows")
	# A NaN or infinite cost makes the potentials comparisons never settle —
	# the augmenting loop below would spin forever. Sanitise first.
	for r in n:
		var row : PackedFloat32Array = cost[r]
		for c in m:
			if is_nan(row[c]) or is_inf(row[c]):
				push_error("Hungarian.solve: non-finite cost at [%d,%d]" % [r, c])
				row[c] = 1.0e6
		cost[r] = row
	# 1-indexed arrays as in the classic formulation; column 0 is a sentinel.
	var u := PackedFloat64Array()
	u.resize(n + 1)
	var v := PackedFloat64Array()
	v.resize(m + 1)
	var p := PackedInt32Array()  # p[j] = row matched to column j (0 = none)
	p.resize(m + 1)
	var way := PackedInt32Array()
	way.resize(m + 1)
	for i in range(1, n + 1):
		p[0] = i
		var j0 := 0
		var minv := PackedFloat64Array()
		minv.resize(m + 1)
		minv.fill(INF)
		var used := PackedByteArray()
		used.resize(m + 1)
		used.fill(0)
		var guard := 0
		while true:
			guard += 1
			if guard > m + 2:
				push_error("Hungarian.solve: augmenting path did not terminate")
				break
			used[j0] = 1
			var i0 := p[j0]
			var delta := INF
			var j1 := 0
			var row : PackedFloat32Array = cost[i0 - 1]
			for j in range(1, m + 1):
				if used[j] == 0:
					var cur := row[j - 1] - u[i0] - v[j]
					if cur < minv[j]:
						minv[j] = cur
						way[j] = j0
					if minv[j] < delta:
						delta = minv[j]
						j1 = j
			for j in range(m + 1):
				if used[j] == 1:
					u[p[j]] += delta
					v[j] -= delta
				else:
					minv[j] -= delta
			j0 = j1
			if p[j0] == 0:
				break
		while true:
			var j1 := way[j0]
			p[j0] = p[j1]
			j0 = j1
			if j0 == 0:
				break
	for j in range(1, m + 1):
		if p[j] != 0:
			result[p[j] - 1] = j - 1
	return result

static func total_cost(cost: Array, assignment: PackedInt32Array) -> float:
	var total := 0.0
	for i in assignment.size():
		total += cost[i][assignment[i]]
	return total
