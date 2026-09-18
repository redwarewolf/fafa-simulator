extends Control

# Normalized bounds of the playable area within the 2350×1225 field image.
# These were measured from the field background art and must stay in sync with
# ActorsContainer.FIELD_LEFT/RIGHT/TOP/BOTTOM and the FORMATIONS dictionaries.
const ZONE_X0 := 0.016
const ZONE_X1 := 0.984
const ZONE_Y0 := 0.182
const ZONE_Y1 := 0.881

## Window of the pitch art the overlay draws. Anchors reach both halves now, so
## the whole image is shown and the window is the identity — kept as a Rect2
## because the mapping below still goes through it, and cropping back to a
## portion of the pitch stays a one-line change.
const CROP := Rect2(0.0, 0.0, 1.0, 1.0)


# Aspect ratio of the cropped window, in pixels of the source art.
const FIELD_ASPECT := (2350.0 * CROP.size.x) / (1225.0 * CROP.size.y)

# ── visual constants ──────────────────────────────────────────────────────────

# Slot circles are sized from the drawn pitch, not in absolute pixels: the old
# fixed 7 px radius was tuned for the 640×480 viewport and shrank to a speck
# once the window moved to 1280×720.
const SLOT_RADIUS_RATIO := 0.048  # radius as a fraction of the pitch height
const SLOT_RADIUS_MIN   := 7.0    # floor, for very small containers
const OUTLINE_RATIO     := 0.28   # ring thickness, relative to the radius
const PICK_SLACK_RATIO  := 0.45   # extra click tolerance, relative to the radius
const EMPTY_FILL    := Color(0.06, 0.11, 0.13, 0.55)  ## unassigned slot
const EMPTY_INK     := Color(1.0, 1.0, 1.0, 0.75)
const NAME_COLOR    := Color(1.0, 1.0, 1.0, 1.0)
const NAME_OUTLINE  := Color(0.05, 0.10, 0.12, 1.0)
const WARN_COLOR    := Color(1.0, 0.30, 0.30, 1.0)   ## out of position
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.72)
const DRAG_COLOR    := Color(1.0, 0.85, 0.2, 1.0)
const LOCK_COLOR    := Color(0.6, 0.6, 0.6, 0.70)
const PINNED_COLOR  := Color(0.95, 0.79, 0.20, 0.95)  ## keeper — selectable, not movable
const SELECT_COLOR  := Color(0.3, 0.8, 1.0, 1.0)
const DROP_COLOR    := Color(0.2, 1.0, 0.4, 1.0)


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
	var r := _slot_radius(field)
	var tip_pos := centre + Vector2(r + 6.0, -(r + 6.0))
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
	if player.unavailable_matches > 0:
		# Suspended by a random event — squad_section already refuses to start
		# this drag, this is just the authoritative backstop.
		queue_redraw()
		return false
	# Moving between slots is a SWAP, not a copy. The slot we came from takes
	# whoever was standing on the target — null when the target was empty, which
	# is how "leave the old spot vacant" falls out of the same two lines instead
	# of needing a case of its own. A player dragged in from the roster holds no
	# slot yet, so the one they displace simply drops out of the lineup.
	var old_idx : int = _tactic.find_slot_for_player(player)
	var displaced : PlayerResource = _tactic.get_player(idx)
	_tactic.assign_player(idx, player)
	if old_idx >= 0 and old_idx != idx:
		_tactic.assign_player(old_idx, displaced)
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

## Slot circle radius for the currently drawn pitch.
func _slot_radius(field: Rect2) -> float:
	return maxf(SLOT_RADIUS_MIN, field.size.y * SLOT_RADIUS_RATIO)

func _norm_to_px(norm: Vector2, field: Rect2) -> Vector2:
	var fx := ZONE_X0 + norm.x * (ZONE_X1 - ZONE_X0)
	var fy := ZONE_Y0 + norm.y * (ZONE_Y1 - ZONE_Y0)
	var cx := (fx - CROP.position.x) / CROP.size.x
	var cy := (fy - CROP.position.y) / CROP.size.y
	return Vector2(field.position.x + cx * field.size.x,
				   field.position.y + cy * field.size.y)

func _px_to_norm(px: Vector2, field: Rect2) -> Vector2:
	var fx := CROP.position.x + (px.x - field.position.x) / field.size.x * CROP.size.x
	var fy := CROP.position.y + (px.y - field.position.y) / field.size.y * CROP.size.y
	return Vector2(
		clampf((fx - ZONE_X0) / (ZONE_X1 - ZONE_X0), 0.0, 1.0),
		clampf((fy - ZONE_Y0) / (ZONE_Y1 - ZONE_Y0), 0.0, 1.0))

## Return the slot index whose circle contains px, or -1.
func _slot_at(px: Vector2, field: Rect2) -> int:
	if _tactic == null:
		return -1
	var pick := _slot_radius(field) * (1.0 + OUTLINE_RATIO + PICK_SLACK_RATIO)
	for i in _tactic.slots.size():
		var centre := _norm_to_px(_tactic.slots[i].position, field)
		if px.distance_to(centre) <= pick:
			return i
	return -1

# ── drawing ───────────────────────────────────────────────────────────────────

func _draw() -> void:
	if _tactic == null or _tactic.slots.is_empty():
		return
	var field  := _field_rect()
	var radius := _slot_radius(field)
	for i in _tactic.slots.size():
		var slot   = _tactic.slots[i]
		var centre := _norm_to_px(slot.position, field)
		_draw_slot(i, slot, centre, radius)

func _draw_slot(i: int, slot, centre: Vector2, r: float) -> void:

	# Glow ring — colour depends on state
	var ring_col : Color
	if i == _hover_index:
		ring_col = DROP_COLOR
	elif i == _selected_slot:
		ring_col = SELECT_COLOR
	elif i == Formations.GOALKEEPER_SLOT:
		ring_col = PINNED_COLOR
	elif _locked:
		ring_col = LOCK_COLOR
	elif i == _drag_index:
		ring_col = DRAG_COLOR
	else:
		ring_col = OUTLINE_COLOR
	draw_circle(centre, r * (1.0 + OUTLINE_RATIO), ring_col)

	# The disc is coloured by the SLOT's position, so the formation reads as
	# lines at a glance. Every slot used to draw the same default portrait, which
	# meant eleven identical circles carrying no information at all.
	var line_color : Color = Positions.color(slot.role)

	if not slot.is_assigned():
		draw_circle(centre, r, EMPTY_FILL)
		_draw_centred(centre, Positions.label(slot.role), r * 0.62, EMPTY_INK)
		return

	draw_circle(centre, r, line_color)
	_draw_centred(centre, str(slot.player.overall()), r * 0.78, Positions.ink_on(slot.role))
	_draw_name(centre, r, _surname(slot.player.full_name))

	# A player filling a slot their position doesn't cover gets called out here,
	# not left for the manager to notice at kickoff.
	if Positions.aptitude(slot.player.role, slot.role) == Positions.Aptitude.OUT_OF_POSITION:
		draw_arc(centre, r * (1.0 + OUTLINE_RATIO) + 2.0, 0.0, TAU, 28, WARN_COLOR, maxf(2.0, r * 0.12))
		_draw_warn_badge(centre, r)

## Everything after the first token — the disc has room for a surname, not a
## full name. Dropping the first word rather than keeping the last one is what
## makes "R. DE PAUL" and "Alexis Mac Allister" come out whole instead of as
## "PAUL" and "ALLISTER".
func _surname(full_name: String) -> String:
	var parts := full_name.strip_edges().split(" ", false)
	if parts.size() < 2:
		return full_name
	return " ".join(parts.slice(1))

## Text centred on the disc.
func _draw_centred(centre: Vector2, text: String, size: float, color: Color) -> void:
	var font := get_theme_default_font()
	var font_size := int(maxf(8.0, size))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, centre + Vector2(-width * 0.5, font_size * 0.36), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

## Surname under the disc, outlined so it stays readable over both grass tones.
func _draw_name(centre: Vector2, r: float, text: String) -> void:
	var font := get_theme_default_font()
	var font_size := int(maxf(7.0, r * 0.5))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var at := centre + Vector2(-width * 0.5, r + font_size + 2.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		int(maxf(2.0, r * 0.14)), NAME_OUTLINE)
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, NAME_COLOR)

## Exclamation badge for a player filling a slot they cannot cover.
func _draw_warn_badge(centre: Vector2, r: float) -> void:
	var at := centre + Vector2(-r * 0.78, -r * 0.78)
	var s  := maxf(6.0, r * 0.52)
	draw_circle(at, s * 0.95, WARN_COLOR)
	_draw_centred(at, "!", s * 1.1, Color.WHITE)

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
				# The keeper can be selected and can have a player dropped on them,
				# but the slot never moves: GoalieAI reads its goal line off
				# the spawn point, so dragging it forward strands the keeper.
				if idx != Formations.GOALKEEPER_SLOT:
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
