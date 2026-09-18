class_name GeometryUtils
extends RefCounted

## Small shared 2D geometry helpers used by more than one AI scoring class
## (OnBallUtility's pass-lane check, CandidatePointScorer's goal-lane check) —
## kept here once instead of letting forked copies drift apart.

static func distance_point_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)
