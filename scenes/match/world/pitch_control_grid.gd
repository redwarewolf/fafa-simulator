class_name PitchControlGrid
extends RefCounted

## Live pitch-control surface: for every cell, the probability the LEFT team
## would get there first (right team = 1 - that). Per cell, each team's best
## time-to-reach (PitchControl.time_to_reach's model: reaction delay, top
## speed, current velocity) goes through the pass model's arrival logistic —
## the "simplified" pitch control of Spearman 2018 / Fernández & Bornn 2018.
##
## Laid out in pitch-absolute normalised space (so cells follow the
## perspective trapezoid), COLS along the length × ROWS across. Refreshing
## every cell every frame is wasteful in GDScript, so update_rows() refreshes
## a slice of rows per call; MatchContext spreads a full pass over
## FRAMES_PER_REFRESH frames (20 Hz at 60 fps), as the reference engine does.

const COLS := 24
const ROWS := 10

var control_left := PackedFloat32Array()
var centres := PackedVector2Array()
var _next_row := 0

func _init() -> void:
	control_left.resize(COLS * ROWS)
	control_left.fill(0.5)
	centres.resize(COLS * ROWS)
	for r in ROWS:
		for c in COLS:
			centres[r * COLS + c] = PitchSpace.from_absolute_normalised(Vector2((c + 0.5) / COLS, (r + 0.5) / ROWS))

## Refreshes [param count] rows (wrapping), using flattened per-player data
## so the inner loop avoids per-call overhead. [param left]/[param right] are
## the two teams' Player arrays.
func update_rows(count: int, left: Array, right: Array) -> void:
	var lp := _pack(left)
	var rp := _pack(right)
	for n in count:
		var r := _next_row
		_next_row = (_next_row + 1) % ROWS
		for c in COLS:
			var i := r * COLS + c
			var p := centres[i]
			control_left[i] = PassModel.p_first(_best_time(p, lp), _best_time(p, rp))

## Every row at once — tests, the debug overlay's first frame.
func update_all(left: Array, right: Array) -> void:
	update_rows(ROWS, left, right)

## [pos, vel, speed, accel, vmax] per movable, active player.
static func _pack(team: Array) -> Array:
	var out := []
	for p: Player in team:
		if p.process_mode == Node.PROCESS_MODE_DISABLED:
			continue
		# Position and velocity in iso space (true distance — see
		# PitchSpace.ISO_Y); _best_time's cell point is converted likewise.
		out.append([PitchSpace.iso(p.position), PitchSpace.iso(p.velocity), maxf(p.speed, 1.0), p.max_accel, maxf(p.speed, 1.0) * Locomotion.SPRINT_MULTIPLIER])
	return out

## Inlined PitchControl.time_to_reach over a packed team. For engine-v2
## players the kinematic formula (PitchControl.kinematic_time) is inlined, and
## a player whose best-case time (straight at top speed) can't beat the
## current best is skipped — the grid is the single hottest loop in the AI.
static func _best_time(point: Vector2, packed: Array) -> float:
	var best := 99.0
	var point_iso := PitchSpace.iso(point)
	for d in packed:
		var to_point : Vector2 = point_iso - d[0]
		var dist := to_point.length()
		var t := PitchControl.REACTION_TIME
		var accel : float = d[3]
		if dist >= 1.0 and accel > 0.0:
			var vmax : float = d[4]
			if t + dist / vmax >= best:
				continue
			var vel_k : Vector2 = d[1]
			var v0 := vel_k.dot(to_point) / dist
			if v0 < 0.0:
				t += -v0 / (accel * Player.BRAKE_FACTOR)
				v0 = 0.0
			v0 = minf(v0, vmax)
			var t_acc := (vmax - v0) / accel
			var d_acc := (v0 + vmax) * 0.5 * t_acc
			if dist <= d_acc:
				t += (-v0 + sqrt(v0 * v0 + 2.0 * accel * dist)) / accel
			else:
				t += t_acc + (dist - d_acc) / vmax
		elif dist >= 1.0:
			var speed : float = d[2]
			var vel : Vector2 = d[1]
			var cur := vel.length()
			var align := vel.dot(to_point) / (cur * dist) if cur > 1.0 else 0.0
			var eff := clampf(speed + align * cur * PitchControl.VELOCITY_BIAS_WEIGHT,
				speed * PitchControl.MIN_EFFECTIVE_SPEED_FACTOR, speed * PitchControl.MAX_EFFECTIVE_SPEED_FACTOR)
			t += dist / eff
		if t < best:
			best = t
	return best

## Left-team control at world point [param p] (bilinear over cell centres).
func left_control_at(p: Vector2) -> float:
	var n := PitchSpace.absolute_normalised(p)
	var fx := clampf(n.x * COLS - 0.5, 0.0, COLS - 1.001)
	var fy := clampf(n.y * ROWS - 0.5, 0.0, ROWS - 1.001)
	var c := int(fx)
	var r := int(fy)
	var tx := fx - c
	var ty := fy - r
	var a := lerpf(control_left[r * COLS + c], control_left[r * COLS + c + 1], tx)
	var b := lerpf(control_left[(r + 1) * COLS + c], control_left[(r + 1) * COLS + c + 1], tx)
	return lerpf(a, b, ty)

## Control for the side given by [param is_left_team].
func control_at(p: Vector2, is_left_team: bool) -> float:
	var l := left_control_at(p)
	return l if is_left_team else 1.0 - l
