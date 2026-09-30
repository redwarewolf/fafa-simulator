extends CanvasLayer

## Orchestrates narrated youth-academy sign-up events end to end: builds the
## event (utils/youth_events.gd), shows the kid's card via
## ClubTrainer.say_with_choice(), and — if accepted while the academy is
## already full — walks the player through freeing a slot (promoting or
## releasing an existing prospect, same semantics as
## scenes/hub/sections/youth/youth_section.gd) before the new kid actually
## joins. Autoload "YouthSignupFlow" (see project.godot), a CanvasLayer like
## ClubTrainer so its own "make room" popup can render above Hub content.
##
## Callers: scenes/hub/sections/club/staff_panel.gd (guaranteed first-hire
## event) and scenes/hub/hub.gd (daily 80% roll).

const PLAYER_CARD_SCENE : PackedScene = preload("res://scenes/ui/player_card.tscn")
## player_card.gd has no class_name, so its Layout enum isn't reachable by
## name here — 1 is PlayerCard.Layout.RADAR (0 is BARS), the layout suited to
## a wide/short box, which is what DialogueBox's right-side slot is.
const PLAYER_CARD_LAYOUT_RADAR := 1

## Internal only — resolves _run_make_room()'s await. Not meant for outside use.
signal _room_freed(freed: bool)

@onready var _make_room_panel : Control = $MakeRoomPanel
@onready var _rows_container : VBoxContainer = $MakeRoomPanel/Panel/VBox/RowsScroll/RowsContainer
@onready var _cancel_button : Button = $MakeRoomPanel/Panel/VBox/CancelButton


func _ready() -> void:
	layer = 11  # above ClubTrainer's DialogueBox (layer 10)
	_make_room_panel.visible = false
	_cancel_button.pressed.connect(func() -> void: _resolve_room(false))


## Always the guaranteed generic sign-up — called once, right after the
## academy is first hired.
func run_first_signup(club: ClubResource) -> void:
	await _run_event(club, YouthEvents.first_signup_event(club))


## Rolled once per day advanced; no-ops if the roll misses or the academy
## isn't hired (see YouthEvents.maybe_daily_signup()).
func run_daily_signup(club: ClubResource) -> void:
	var event := YouthEvents.maybe_daily_signup(club)
	if event.is_empty():
		return
	await _run_event(club, event)


func _run_event(club: ClubResource, event: Dictionary) -> void:
	var kid : PlayerResource = event["kid"]

	var card : Control = PLAYER_CARD_SCENE.instantiate()
	# `layout` must be set before the card enters a tree (PlayerCard._ready()
	# reads it once to decide BARS vs RADAR). setup() is the opposite — it
	# needs the card's own @onready node refs, which only exist AFTER
	# _ready() runs, so it's called after a throwaway add_child()/remove_child()
	# here (this CanvasLayer is already in the active tree, so _ready() fires
	# synchronously) rather than before ClubTrainer.say_with_choice() parents
	# it into the dialogue box for real.
	card.layout = PLAYER_CARD_LAYOUT_RADAR
	add_child(card)
	card.setup(kid, "")
	remove_child(card)

	var accepted : bool = await ClubTrainer.say_with_choice(event["line"], card)
	card.queue_free()

	if not accepted:
		return

	if club.youth_players.size() >= GameState.get_youth_academy_cap():
		var freed := await _run_make_room(club)
		if not freed:
			return

	kid.reserved = bool(event.get("reserved", false))
	club.youth_players.append(kid)
	var fee : int = int(event.get("fee_amount", 0))
	var fee_direction : String = event.get("fee_direction", "none")
	if fee > 0 and fee_direction == "to_us":
		club.budget += fee
		GameState.budget_changed.emit()
	elif fee > 0 and fee_direction == "to_family":
		club.budget -= fee
		GameState.budget_changed.emit()
	club.youth_unseen += 1
	GameState.post_news("Nuevo juvenil: %s" % kid.full_name,
		"%s (%s, %d años, %s) se sumó a la Academia Juvenil." % [
			kid.full_name, Positions.label(kid.role), kid.age, QualityStyle.NAMES[kid.quality]],
		"youth")
	GameState.pool_badges_changed.emit()
	GameState.save_staff()


func _run_make_room(club: ClubResource) -> bool:
	_populate_make_room_rows(club)
	_make_room_panel.visible = true
	var freed : bool = await _room_freed
	return freed


func _populate_make_room_rows(club: ClubResource) -> void:
	for c in _rows_container.get_children():
		c.queue_free()
	for p : PlayerResource in club.youth_players:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var label := Label.new()
		var reserved_tag := "  [RESERVADO]" if p.reserved else ""
		label.text = "%s  (%s, %d años)%s" % [p.full_name, Positions.label(p.role), p.age, reserved_tag]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var promote_btn := Button.new()
		promote_btn.text = "SUBIR"
		promote_btn.pressed.connect(_on_promote_pressed.bind(club, p))
		row.add_child(promote_btn)

		var release_btn := Button.new()
		release_btn.text = "LIBERAR"
		# A reserved prospect (see PlayerResource.reserved) can't be freed this
		# way until he graduates — promoting him out early is still fine.
		release_btn.disabled = p.reserved
		release_btn.pressed.connect(_on_release_pressed.bind(club, p))
		row.add_child(release_btn)

		_rows_container.add_child(row)


func _on_promote_pressed(club: ClubResource, p: PlayerResource) -> void:
	club.youth_players.erase(p)
	club.players.append(p)
	GameState.save_staff()
	_resolve_room(true)


func _on_release_pressed(club: ClubResource, p: PlayerResource) -> void:
	if p.reserved:
		return
	club.youth_players.erase(p)
	GameState.save_staff()
	_resolve_room(true)


func _resolve_room(freed: bool) -> void:
	# Hide before emitting so a second click landing this same frame on
	# another row's now-invisible button can't double-resolve the await.
	_make_room_panel.visible = false
	_room_freed.emit(freed)
