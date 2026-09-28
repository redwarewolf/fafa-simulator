class_name Job
extends RefCounted

## One player's current instruction from their team's coordinators (Phase 5).
## A job says WHAT to do and roughly WHERE; the PlayerBrain turns it into an
## exact target and movement every frame.

enum Kind {
	ZONE,          ## hold a shape slot (refined off the ball by OffBallPositioner in possession)
	PRESS,         ## close down the carrier (engage) or shadow goal-side (contain)
	COVER,         ## second defender: goal-side cover behind the presser
	MARK,          ## track a dangerous opponent goal-side
	LANE_CUT,      ## stand in the carrier's most valuable passing lane
	CHASE,         ## win the loose ball at its predicted intercept point
	INTERCEPT,     ## cut out a pass in flight
	RECEIVE,       ## move onto a pass played to me
	SUPPORT,       ## offer the carrier a short passing angle
	RUN,           ## run in behind / on the shoulder of the last defender
	REST_DEFENCE,  ## stay behind the ball in possession to stop counters
	SET_PIECE,     ## a fixed set-piece post: box spot on a corner, zonal/near-post cover, a wall
}

const NAMES := {
	Kind.ZONE: "zone", Kind.PRESS: "press", Kind.COVER: "cover", Kind.MARK: "mark",
	Kind.LANE_CUT: "lane_cut", Kind.CHASE: "chase", Kind.INTERCEPT: "intercept",
	Kind.RECEIVE: "receive", Kind.SUPPORT: "support", Kind.RUN: "run",
	Kind.REST_DEFENCE: "rest_defence", Kind.SET_PIECE: "set_piece",
}

var kind : int = Kind.ZONE
## Where to be (or the anchor to search around).
var point := Vector2.ZERO
## The opponent pressed/marked, or the pass receiver/runner concerned.
var subject : Player = null
## PRESS only: true = go and win it, false = contain/jockey at a distance.
var engage := false
## 0 = free to roam for a better spot, 1 = hold the point exactly.
var rigidity := 0.5

static func make(p_kind: int, p_point: Vector2, p_subject: Player = null, p_rigidity: float = 0.5) -> Job:
	var j := Job.new()
	j.kind = p_kind
	j.point = p_point
	j.subject = p_subject
	j.rigidity = p_rigidity
	return j

## Same job as last time (same kind and subject) — for assignment stickiness.
func same_role_as(other: Job) -> bool:
	return other != null and other.kind == kind and other.subject == subject
