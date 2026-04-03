class_name TacticResource
extends Resource

const TacticSlotClass = preload("res://resources/tactic_slot.gd")

## A saved tactic: display name, base formation template, and one slot per player.
## slots are ordered to match the FORMATIONS positions array in field_overlay.gd

@export var tactic_name : String = ""
@export var template    : String = ""          # key into field_overlay.FORMATIONS
@export var slots       : Array  = []          # Array of TacticSlot

func _init(p_name: String = "", p_template: String = "") -> void:
	tactic_name = p_name
	template    = p_template

## Build slots from a raw Array[Vector2] of formation positions.
## Called once when the tactic is first created from a preset template.
func init_slots_from_positions(positions: Array) -> void:
	slots.clear()
	for pos in positions:
		slots.append(TacticSlotClass.new(pos))

## Return the position for slot i (falls back to Vector2.ZERO).
func get_position(i: int) -> Vector2:
	if i >= 0 and i < slots.size():
		return slots[i].position
	return Vector2.ZERO

## Assign a player to a slot. Pass null to clear.
func assign_player(slot_index: int, p: PlayerResource) -> void:
	if slot_index >= 0 and slot_index < slots.size():
		slots[slot_index].player = p

## Return the player in a slot, or null if unassigned.
func get_player(slot_index: int) -> PlayerResource:
	if slot_index >= 0 and slot_index < slots.size():
		return slots[slot_index].player
	return null

## Return the slot index that has this player assigned, or -1.
func find_slot_for_player(p: PlayerResource) -> int:
	for i in slots.size():
		if slots[i].player == p:
			return i
	return -1

## Returns all assigned players as an Array[PlayerResource].
func get_assigned_players() -> Array:
	var out : Array = []
	for s in slots:
		if s.is_assigned():
			out.append(s.player)
	return out
