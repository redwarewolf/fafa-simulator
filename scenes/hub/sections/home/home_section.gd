extends Control

## FM-style Home / Inbox. Left: the club's news feed (GameState.inbox) with the
## selected message's full text. Right: the next fixture, a five-row slice of
## the table around the player's club plus recent form, the budget trend, and
## a to-do list of things that need the manager's attention. The to-do rows
## are shortcuts — they emit `navigate` and the Hub switches tab (or, for
## "play", runs the same flow as Próxima Fecha).

signal navigate(target: String)

const INBOX_COLUMNS := [
	{"title": "Tipo",   "expand": false, "min_width": 84, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Fecha",  "expand": false, "min_width": 190},
	{"title": "Asunto", "expand": true},
]

const TABLE_COLUMNS := [
	{"title": "#",    "expand": false, "min_width": 34, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Club", "expand": true},
	{"title": "PJ",   "expand": false, "min_width": 36, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "DG",   "expand": false, "min_width": 40, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Pts",  "expand": false, "min_width": 40, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

const TABLE_ROWS := 5
const FORM_COUNT := 5

## Message category → [tag, colour] for the inbox's Tipo column.
const KIND_TAGS := {
	"result": ["PARTIDO", Color(1.0, 0.85, 0.2)],
	"event":  ["PLANTEL", Color(1.0, 0.6, 0.35)],
	"youth":  ["JUVENIL", Color(0.4, 0.9, 0.4)],
	"season": ["TORNEO",  Color(0.45, 0.75, 1.0)],
	"info":   ["CLUB",    Color(0.62, 0.72, 0.78)],
	"debt":   ["DEUDA",   Color(0.9, 0.4, 0.4)],
}

@onready var unread_label : Label       = $HBox/InboxPanel/VBox/TitleRow/UnreadLabel
@onready var inbox_tree   : Tree        = $HBox/InboxPanel/VBox/InboxTree
@onready var subject      : Label       = $HBox/InboxPanel/VBox/Subject
@onready var meta         : Label       = $HBox/InboxPanel/VBox/Meta
@onready var body         : Label       = $HBox/InboxPanel/VBox/BodyScroll/Body

@onready var home_logo  : TextureRect = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/HomeSide/Logo
@onready var home_name  : Label       = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/HomeSide/Name
@onready var away_logo  : TextureRect = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/AwaySide/Logo
@onready var away_name  : Label       = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/AwaySide/Name
@onready var vs_label   : Label       = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/Center/Vs
@onready var when_label : Label       = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/Center/When
@onready var kind_label : Label       = $HBox/RightColumn/NextMatchPanel/VBox/CrestRow/Center/Kind

@onready var form_title : Label         = $HBox/RightColumn/TablePanel/VBox/TitleRow/FormTitle
@onready var form_row   : HBoxContainer = $HBox/RightColumn/TablePanel/VBox/TitleRow/FormRow
@onready var table_tree : Tree          = $HBox/RightColumn/TablePanel/VBox/TableTree

@onready var budget_label : Label   = $HBox/RightColumn/FinancePanel/VBox/TitleRow/Budget
@onready var delta_label  : Label   = $HBox/RightColumn/FinancePanel/VBox/TitleRow/Delta
@onready var chart        : Control = $HBox/RightColumn/FinancePanel/VBox/Chart

@onready var todo_list : VBoxContainer = $HBox/RightColumn/TodoPanel/VBox/TodoList

func _ready() -> void:
	TreeStyle.setup_columns(inbox_tree, INBOX_COLUMNS)
	TreeStyle.setup_columns(table_tree, TABLE_COLUMNS)
	meta.add_theme_color_override("font_color", HubPalette.MUTED)
	unread_label.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
	form_title.add_theme_color_override("font_color", HubPalette.MUTED)
	kind_label.add_theme_color_override("font_color", HubPalette.MUTED)
	when_label.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
	# No refresh() here: opening the newest message marks it read, so the
	# feed is only populated once the Hub actually shows this tab (it calls
	# refresh() on every _show_section()).

func refresh() -> void:
	if GameState.player_club == null:
		return
	_populate_inbox()
	_populate_next_match()
	_populate_table()
	_populate_form()
	_populate_finances()
	_populate_todo()

# ── inbox ─────────────────────────────────────────────────────────────────────

func _populate_inbox() -> void:
	inbox_tree.clear()
	var root := inbox_tree.create_item()
	for i in GameState.inbox.size():
		var item := inbox_tree.create_item(root)
		item.set_metadata(0, i)
		_style_message_row(item, GameState.inbox[i])
	_update_unread_label()

	if root.get_child_count() == 0:
		subject.text = tr("Sin mensajes")
		meta.text = ""
		body.text = tr("Acá te van a llegar los resultados, las novedades del plantel y los avisos del torneo.")
		return
	# Open on the newest message, like FM's inbox.
	var first := root.get_first_child()
	inbox_tree.set_selected(first, 2)
	_show_message(0)

func _style_message_row(item: TreeItem, msg: Dictionary) -> void:
	var tag : Array = KIND_TAGS.get(msg.get("kind", "info"), KIND_TAGS["info"])
	var unread : bool = not msg.get("read", false)
	item.set_text(0, tr(tag[0]))
	item.set_custom_color(0, tag[1])
	item.set_text(1, msg.get("date", ""))
	item.set_custom_color(1, HubPalette.MUTED)
	item.set_text(2, ("•  " if unread else "") + msg.get("title", ""))
	item.set_custom_color(2, Color.WHITE if unread else HubPalette.MUTED)
	TreeStyle.align_row(item, INBOX_COLUMNS)

func _on_message_selected() -> void:
	var item := inbox_tree.get_selected()
	if item == null:
		return
	_show_message(int(item.get_metadata(0)))

func _show_message(index: int) -> void:
	if index < 0 or index >= GameState.inbox.size():
		return
	var msg : Dictionary = GameState.inbox[index]
	subject.text = msg.get("title", "")
	var tag : Array = KIND_TAGS.get(msg.get("kind", "info"), KIND_TAGS["info"])
	meta.text = "%s  ·  %s" % [tr(tag[0]), msg.get("date", "")]
	body.text = msg.get("body", "")
	GameState.mark_news_read(index)
	var item := inbox_tree.get_selected()
	if item != null:
		_style_message_row(item, msg)
	_update_unread_label()

func _update_unread_label() -> void:
	var unread := GameState.unread_news_count()
	unread_label.text = tr("%d sin leer") % unread if unread > 0 else ""

# ── next match ────────────────────────────────────────────────────────────────

func _populate_next_match() -> void:
	var f := SeasonManager.next_player_fixture()
	var home := DataLoader.get_club(f["home_id"]) if not f.is_empty() else null
	var away := DataLoader.get_club(f["away_id"]) if not f.is_empty() else null
	var has_match := home != null and away != null
	home_logo.visible = has_match
	away_logo.visible = has_match
	vs_label.visible = has_match
	if not has_match:
		home_name.text = ""
		away_name.text = ""
		when_label.text = tr("Sin partidos programados")
		kind_label.text = ""
		return

	var player_id := GameState.player_club.id
	ClubLogo.apply(home_logo, home)
	ClubLogo.apply(away_logo, away)
	home_name.text = home.display_name
	away_name.text = away.display_name
	home_name.add_theme_color_override("font_color", HubPalette.HIGHLIGHT if home.id == player_id else Color.WHITE)
	away_name.add_theme_color_override("font_color", HubPalette.HIGHLIGHT if away.id == player_id else Color.WHITE)

	var days := GameState.days_until(f["day"], f["month"], f["year"])
	if days <= 0:
		when_label.text = tr("HOY")
	elif days == 1:
		when_label.text = tr("MAÑANA")
	else:
		when_label.text = tr("EN %d DÍAS") % days
	var competition := tr("Amistoso") if f["type"] == "friendly" else tr("Fecha %d") % (int(f["matchday"]) + 1)
	var venue := tr("Local") if home.id == player_id else tr("Visitante")
	kind_label.text = "%s  ·  %s" % [competition, venue]

# ── table + form ──────────────────────────────────────────────────────────────

func _populate_table() -> void:
	table_tree.clear()
	var root := table_tree.create_item()
	var table := Standings.for_division(GameState.player_club.division)
	var own_index := 0
	for i in table.size():
		if table[i].id == GameState.player_club.id:
			own_index = i
	var start := clampi(own_index - TABLE_ROWS / 2, 0, maxi(0, table.size() - TABLE_ROWS))
	for i in range(start, mini(start + TABLE_ROWS, table.size())):
		var club : ClubResource = table[i]
		var item := table_tree.create_item(root)
		item.set_text(0, str(i + 1))
		item.set_text(1, club.display_name)
		item.set_text(2, str(club.matches_played))
		item.set_text(3, "%+d" % (club.goals_for - club.goals_against))
		item.set_text(4, str(club.tournament_points))
		TreeStyle.align_row(item, TABLE_COLUMNS)
		if i == own_index:
			TreeStyle.tint_row(item, HubPalette.HIGHLIGHT)
		if i == 0:
			# Only first place goes up — mark the promotion spot.
			item.set_custom_bg_color(0, Color(0.3, 0.75, 0.35, 0.45))

func _populate_form() -> void:
	for child in form_row.get_children():
		form_row.remove_child(child)
		child.queue_free()
	var player_id := GameState.player_club.id
	var played := SeasonManager.player_fixtures().filter(func(f: Dictionary) -> bool: return f["played"])
	var recent := played.slice(maxi(0, played.size() - FORM_COUNT))
	form_title.visible = not recent.is_empty()
	for f in recent:
		var is_home : bool = f["home_id"] == player_id
		var own : int = f["home_score"] if is_home else f["away_score"]
		var opp : int = f["away_score"] if is_home else f["home_score"]
		var letter := "G" if own > opp else ("P" if own < opp else "E")
		var opponent := DataLoader.get_club(f["away_id"] if is_home else f["home_id"])
		form_row.add_child(_form_chip(tr(letter), HubPalette.result_color(own, opp),
			"%s %d-%d" % [opponent.display_name if opponent != null else "?", own, opp]))

func _form_chip(text: String, color: Color, tooltip: String) -> Control:
	var chip := Label.new()
	chip.text = text
	chip.tooltip_text = tooltip
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.custom_minimum_size = Vector2(20, 18)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_theme_color_override("font_color", Color(0.05, 0.12, 0.15))
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	chip.add_theme_stylebox_override("normal", style)
	return chip

# ── finances ──────────────────────────────────────────────────────────────────

func _populate_finances() -> void:
	var budget := GameState.player_club.budget
	budget_label.text = MoneyFormat.dollars(budget)
	budget_label.add_theme_color_override("font_color", HubPalette.LOSS if budget < 0 else Color.WHITE)
	var values : Array = GameState.budget_history.duplicate()
	values.append(budget)
	chart.set_values(values)
	if GameState.budget_history.is_empty():
		delta_label.text = ""
		return
	var delta : int = budget - int(GameState.budget_history.back())
	delta_label.text = "%s$%s" % ["+" if delta >= 0 else "-", MoneyFormat.format(absi(delta))]
	delta_label.add_theme_color_override("font_color", HubPalette.WIN if delta >= 0 else HubPalette.LOSS)
	delta_label.tooltip_text = tr("Cambio desde ayer")

# ── to-do ─────────────────────────────────────────────────────────────────────

func _populate_todo() -> void:
	for child in todo_list.get_children():
		todo_list.remove_child(child)
		child.queue_free()
	var club := GameState.player_club

	if not SeasonManager.pending_player_fixture.is_empty():
		_add_todo(tr("Hoy hay partido — jugalo o simulalo"), "play")

	var tactic = GameState.get_active_tactic()
	if tactic != null:
		var empty := 0
		for slot in tactic.slots:
			if not slot.is_assigned():
				empty += 1
		if empty > 0:
			_add_todo(tr("%d puestos vacíos en la táctica") % empty, "squad")

	var unavailable := club.players.filter(func(p: PlayerResource) -> bool: return p.unavailable_matches > 0)
	if not unavailable.is_empty():
		_add_todo(tr("%d jugadores no disponibles") % unavailable.size(), "squad")

	if SeasonManager.phase == SeasonManager.Phase.PRE_SEASON \
			or SeasonManager.phase == SeasonManager.Phase.MID_SEASON_BREAK:
		var left := maxi(0, SeasonManager.phase_length - SeasonManager.phase_day)
		if left == 0:
			_add_todo(tr("Mercado de pases abierto — último día"), "market")
		else:
			_add_todo(tr("Mercado de pases abierto — quedan %d días") % left, "market")

	if club.scout_unseen > 0:
		_add_todo(tr("El ojeador encontró %d jugadores nuevos") % club.scout_unseen, "club")
	if club.youth_unseen > 0:
		_add_todo(tr("%d juveniles nuevos en la Academia") % club.youth_unseen, "youth")
	if club.budget < 0:
		_add_todo(tr("Presupuesto en rojo — revisá los gastos"), "club")
	if GameState.debt_arrears > 0:
		_add_todo(tr("Cuota atrasada con Tapir: $%s — juntá la plata antes del próximo pago") % MoneyFormat.format(GameState.debt_arrears), "club")

	if todo_list.get_child_count() == 0:
		var done := Label.new()
		done.text = tr("Todo en orden.")
		done.add_theme_color_override("font_color", HubPalette.MUTED)
		todo_list.add_child(done)

func _add_todo(text: String, target: String) -> void:
	var btn := Button.new()
	btn.text = "> " + text
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.theme_type_variation = &"GhostButton"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void: navigate.emit(target))
	todo_list.add_child(btn)
