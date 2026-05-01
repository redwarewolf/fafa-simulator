extends Control

# Normalized bounds of the playable left half within the full 2350×1225 field image.
# These were measured from the field background art and must stay in sync with
# ActorsContainer.FIELD_LEFT/RIGHT/TOP/BOTTOM and the FORMATIONS dictionaries.
const ZONE_X0 := 0.016
const ZONE_X1 := 0.500
const ZONE_Y0 := 0.182
const ZONE_Y1 := 0.881

const GK_X0   := 0.030
const GK_X1   := 0.145
const GK_Y0   := 0.371
const GK_Y1   := 0.677

# Full field image aspect ratio (2350×1225)
const FIELD_ASPECT := 2350.0 / 1225.0

# Formation positions in half-field normalized space:
#   x=0 → goal line,  x=1 → halfway line
#   y=0 → top touchline, y=1 → bottom touchline
const FORMATIONS : Dictionary = {
	"4-3-3": [
		Vector2(0.06, 0.50),                                                                   # GK
		Vector2(0.26, 0.12), Vector2(0.26, 0.37), Vector2(0.26, 0.63), Vector2(0.26, 0.88),  # DEF
		Vector2(0.55, 0.22), Vector2(0.55, 0.50), Vector2(0.55, 0.78),                        # MID
		Vector2(0.82, 0.12), Vector2(0.82, 0.50), Vector2(0.82, 0.88),                        # FWD
	],
	"4-4-2": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.12), Vector2(0.26, 0.37), Vector2(0.26, 0.63), Vector2(0.26, 0.88),
		Vector2(0.55, 0.12), Vector2(0.55, 0.37), Vector2(0.55, 0.63), Vector2(0.55, 0.88),
		Vector2(0.82, 0.33), Vector2(0.82, 0.67),
	],
	"3-5-2": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.20), Vector2(0.26, 0.50), Vector2(0.26, 0.80),
		Vector2(0.52, 0.08), Vector2(0.52, 0.30), Vector2(0.52, 0.50), Vector2(0.52, 0.70), Vector2(0.52, 0.92),
		Vector2(0.82, 0.33), Vector2(0.82, 0.67),
	],
	"4-2-3-1": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.12), Vector2(0.26, 0.37), Vector2(0.26, 0.63), Vector2(0.26, 0.88),
		Vector2(0.46, 0.33), Vector2(0.46, 0.67),
		Vector2(0.67, 0.12), Vector2(0.67, 0.50), Vector2(0.67, 0.88),
		Vector2(0.84, 0.50),
	],
	"5-3-2": [
		Vector2(0.06, 0.50),
		Vector2(0.22, 0.08), Vector2(0.22, 0.29), Vector2(0.22, 0.50), Vector2(0.22, 0.71), Vector2(0.22, 0.92),
		Vector2(0.55, 0.22), Vector2(0.55, 0.50), Vector2(0.55, 0.78),
		Vector2(0.82, 0.33), Vector2(0.82, 0.67),
	],
	"3-4-3": [
		Vector2(0.06, 0.50),
		Vector2(0.26, 0.20), Vector2(0.26, 0.50), Vector2(0.26, 0.80),
		Vector2(0.55, 0.12), Vector2(0.55, 0.37), Vector2(0.55, 0.63), Vector2(0.55, 0.88),
		Vector2(0.82, 0.12), Vector2(0.82, 0.50), Vector2(0.82, 0.88),
	],
}

# ── visual constants ──────────────────────────────────────────────────────────

const SLOT_RADIUS   := 7.0    # portrait circle radius
const OUTLINE_EXTRA := 2.0    # ring around the circle
const DOT_RADIUS    := 7.0    # same as SLOT_RADIUS — fills the whole inner disc
const DOT_COLOR     := Color(1.0, 1.0, 1.0, 0.92)
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.72)
const DRAG_COLOR    := Color(1.0, 0.85, 0.2, 1.0)
const LOCK_COLOR    := Color(0.6, 0.6, 0.6, 0.70)
const SELECT_COLOR  := Color(0.3, 0.8, 1.0, 1.0)
const DROP_COLOR    := Color(0.2, 1.0, 0.4, 1.0)

const DEFAULT_PORTRAIT : Texture2D = preload("res://assets/art/characters/player_portrait_default.png")

# ── state ─────────────────────────────────────────────────────────────────────

var _tactic        : Resource = null  # TacticResource
var _drag_index    : int      = -1
var _hover_index   : int      = -1   # slot highlighted during a roster-drag hover
var _locked        : bool     = false
var _selected_slot : int      = -1
var _tooltip_slot  : int      = -1   # slot the mouse is currently resting on

@onready var _hover_timer   : Timer        = $HoverTimer
@onready var _slot_tooltip  : PanelContainer = $SlotTooltip
@onready var _tooltip_label : Label        = $SlotTooltip/TooltipLabel

# Emitted when a slot is clicked
signal slot_clicked(slot_index: int)
# Emitted when a player is confirmed dropped onto a slot
signal player_dropped(slot_index: int, player: PlayerResource)

# ── lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_hover_timer.timeout.connect(_on_hover_timer_timeout)

func _hide_tooltip() -> void:
	_slot_tooltip.visible = false
	_hover_timer.stop()
	_tooltip_slot = -1

func _on_hover_timer_timeout() -> void:
	if _tooltip_slot < 0 or _tactic == null:
		return
	var slot = _tactic.slots[_tooltip_slot]
	if not slot.is_assigned():
		return
	_tooltip_label.text = slot.player.full_name
	# Position tooltip near the slot centre, offset so it doesn't overlap
	var field  := _field_rect()
	var centre := _norm_to_px(slot.position, field)
	var tip_pos := centre + Vector2(SLOT_RADIUS + 6.0, -(SLOT_RADIUS + 6.0))
	# Clamp so it stays inside the control
	_slot_tooltip.visible = true
	_slot_tooltip.reset_size()
	await get_tree().process_frame  # let PanelContainer measure itself
	var tip_size := _slot_tooltip.size
	tip_pos.x = clampf(tip_pos.x, 0.0, size.x - tip_size.x)
	tip_pos.y = clampf(tip_pos.y, 0.0, size.y - tip_size.y)
	_slot_tooltip.position = tip_pos

# ── public API ────────────────────────────────────────────────────────────────

func set_tactic(tactic: Resource) -> void:
	_tactic = tactic
	_drag_index = -1
	_selected_slot = -1
	queue_redraw()

func set_locked(locked: bool) -> void:
	_locked = locked
	_drag_index = -1
	queue_redraw()

func set_selected_slot(index: int) -> void:
	_selected_slot = index
	queue_redraw()

## Called by squad_section while a roster row is being dragged over this control.
func notify_drag_hover(pos: Vector2) -> void:
	var field := _field_rect()
	_hover_index = _slot_at(pos, field)
	queue_redraw()

## Called by squad_section when a roster drag exits or is cancelled.
func notify_drag_exit() -> void:
	_hover_index = -1
	queue_redraw()

## Called by squad_section when a player is dropped at pos.
## Returns true if the drop landed on a valid slot.
func try_drop_player(player: PlayerResource, pos: Vector2) -> bool:
	var field := _field_rect()
	var idx := _slot_at(pos, field)
	_hover_index = -1
	if idx < 0 or _tactic == null:
		queue_redraw()
		return false
	# If the player is already in another slot, clear it first
	var old_idx : int = _tactic.find_slot_for_player(player)
	if old_idx >= 0 and old_idx != idx:
		_tactic.slots[old_idx].clear()
	_tactic.assign_player(idx, player)
	_selected_slot = idx
	queue_redraw()
	player_dropped.emit(idx, player)
	return true

# ── coordinate helpers ────────────────────────────────────────────────────────

func _field_rect() -> Rect2:
	var cw := size.x
	var ch := size.y
	if ch == 0.0:
		return Rect2()
	var fw : float
	var fh : float
	if cw / ch < FIELD_ASPECT:
		fw = cw
		fh = cw / FIELD_ASPECT
	else:
		fh = ch
		fw = ch * FIELD_ASPECT
	return Rect2((cw - fw) * 0.5, (ch - fh) * 0.5, fw, fh)

func _norm_to_px(norm: Vector2, field: Rect2) -> Vector2:
	var fx := ZONE_X0 + norm.x * (ZONE_X1 - ZONE_X0)
	var fy := ZONE_Y0 + norm.y * (ZONE_Y1 - ZONE_Y0)
	return Vector2(field.position.x + fx * field.size.x,
				   field.position.y + fy * field.size.y)

func _px_to_norm(px: Vector2, field: Rect2) -> Vector2:
	var fx := (px.x - field.position.x) / field.size.x
	var fy := (px.y - field.position.y) / field.size.y
	return Vector2(
		clampf((fx - ZONE_X0) / (ZONE_X1 - ZONE_X0), 0.0, 1.0),
		clampf((fy - ZONE_Y0) / (ZONE_Y1 - ZONE_Y0), 0.0, 1.0))

## Return the slot index whose circle contains px, or -1.
func _slot_at(px: Vector2, field: Rect2) -> int:
	if _tactic == null:
		return -1
	for i in _tactic.slots.size():
		var centre := _norm_to_px(_tactic.slots[i].position, field)
		if px.distance_to(centre) <= SLOT_RADIUS + OUTLINE_EXTRA + 4.0:
			return i
	return -1

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _tactic == null or _tactic.slots.is_empty():
		return
	var field := _field_rect()
	for i in _tactic.slots.size():
		var slot   = _tactic.slots[i]
		var centre := _norm_to_px(slot.position, field)
		_draw_slot(i, slot, centre)

func _draw_slot(i: int, slot, centre: Vector2) -> void:
	var r := SLOT_RADIUS

	# Glow ring — colour depends on state
	var ring_col : Color
	if i == _hover_index:
		ring_col = DROP_COLOR
	elif i == _selected_slot:
		ring_col = SELECT_COLOR
	elif _locked:
		ring_col = LOCK_COLOR
	elif i == _drag_index:
		ring_col = DRAG_COLOR
	else:
		ring_col = OUTLINE_COLOR
	draw_circle(centre, r + OUTLINE_EXTRA, ring_col)

	if slot.is_assigned():
		# Draw portrait clipped to a circle using a polygon with UV mapping.
		# We build a fan of triangles that approximates the circle,
		# with UVs mapped so only the circular area of the texture shows.
		var portrait : Texture2D = DEFAULT_PORTRAIT
		const SEGMENTS := 24
		var points  := PackedVector2Array()
		var uvs     := PackedVector2Array()
		var colors  := PackedColorArray()
		# Centre point
		points.append(centre)
		uvs.append(Vector2(0.5, 0.5))
		colors.append(Color.WHITE)
		for s in range(SEGMENTS + 1):
			var angle := (float(s) / float(SEGMENTS)) * TAU
			var dir   := Vector2(cos(angle), sin(angle))
			points.append(centre + dir * r)
			uvs.append(Vector2(0.5 + dir.x * 0.5, 0.5 + dir.y * 0.5))
			colors.append(Color.WHITE)
		draw_polygon(points, colors, uvs, portrait)
	else:
		# Empty slot: outer ring already drawn, just fill the inner disc white
		draw_circle(centre, r, DOT_COLOR)

# ── drag (slot reposition) + tooltip hover ────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if _tactic == null:
		return
	var field := _field_rect()

	if event is InputEventMouseMotion:
		# Hide tooltip and restart hover timer whenever mouse moves
		_hide_tooltip()
		if _drag_index >= 0 and not _locked:
			# Dragging a slot
			_tactic.slots[_drag_index].position = _px_to_norm(event.position, field)
			get_viewport().set_input_as_handled()
			queue_redraw()
		else:
			# Check if we are hovering over a filled slot
			var idx := _slot_at(event.position, field)
			if idx >= 0 and _tactic.slots[idx].is_assigned():
				_tooltip_slot = idx
				_hover_timer.start()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_hide_tooltip()
		if event.pressed:
			if _locked:
				return
			var idx := _slot_at(event.position, field)
			if idx >= 0:
				_drag_index = idx
				_selected_slot = idx
				get_viewport().set_input_as_handled()
				queue_redraw()
				slot_clicked.emit(idx)
		else:
			if _drag_index >= 0:
				_drag_index = -1
				get_viewport().set_input_as_handled()
				queue_redraw()

# ── Godot drop target ─────────────────────────────────────────────────────────

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("type") != "player":
		notify_drag_exit()
		return false
	notify_drag_hover(at_position)
	return true

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or data.get("type") != "player":
		return
	var player := data["player"] as PlayerResource
	try_drop_player(player, at_position)
