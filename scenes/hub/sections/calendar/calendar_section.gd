extends Control

## Division calendar plus a match-preview panel.
##
## The old screen listed only the six fixtures of the player's own club in a
## full-width table, so ~85% of a widescreen window was empty. It now lists the
## whole division grouped by matchday (the player's own games highlighted) and
## drives a detail column with both crests, the table comparison, key players
## and the head-to-head history.

const COL_DATE  := 0
const COL_HOME  := 1
const COL_SCORE := 2
const COL_AWAY  := 3

const COLUMNS := [
	{"title": "Fecha",     "expand": false, "min_width": 110},
	{"title": "Local",     "expand": true,  "align": HORIZONTAL_ALIGNMENT_RIGHT},
	{"title": "",          "expand": false, "min_width": 90, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Visitante", "expand": true},
]

const COMPARE_ROWS := [
	{"label": "Posición",     "key": "position"},
	{"label": "Puntos",       "key": "points"},
	{"label": "Récord",       "key": "record"},
	{"label": "OVR Plantel",  "key": "overall"},
	{"label": "Goles",        "key": "goals"},
]

const KEY_PLAYER_COUNT := 11

@onready var fixtures_tree : Tree          = $HBox/FixturesPanel/VBox/FixturesTree
@onready var phase_grid    : GridContainer = $HBox/FixturesPanel/VBox/PhaseGrid
@onready var phase_note    : Label         = $HBox/FixturesPanel/VBox/TitleRow/PhaseNote
@onready var detail_title  : Label         = $HBox/DetailPanel/VBox/Title
@onready var home_logo     : TextureRect   = $HBox/DetailPanel/VBox/CrestRow/HomeSide/Logo
@onready var home_name     : Label         = $HBox/DetailPanel/VBox/CrestRow/HomeSide/Name
@onready var away_logo     : TextureRect   = $HBox/DetailPanel/VBox/CrestRow/AwaySide/Logo
@onready var away_name     : Label         = $HBox/DetailPanel/VBox/CrestRow/AwaySide/Name
@onready var kickoff_label : Label         = $HBox/DetailPanel/VBox/Kickoff
@onready var score_label   : Label         = $HBox/DetailPanel/VBox/Scoreline
@onready var compare_grid  : GridContainer = $HBox/DetailPanel/VBox/CompareGrid
@onready var home_players  : VBoxContainer = $HBox/DetailPanel/VBox/SquadsScroll/SquadsRow/HomePlayers
@onready var away_players  : VBoxContainer = $HBox/DetailPanel/VBox/SquadsScroll/SquadsRow/AwayPlayers
@onready var h2h_list      : VBoxContainer = $HBox/DetailPanel/VBox/H2HScroll/H2HList

func _ready() -> void:
	TreeStyle.setup_columns(fixtures_tree, COLUMNS)
	_populate()

func refresh() -> void:
	_populate()

# ── fixture list ──────────────────────────────────────────────────────────────

func _populate() -> void:
	_populate_phase_grid()
	fixtures_tree.clear()
	var root := fixtures_tree.create_item()

	var player_id := GameState.player_club.id
	var division  := GameState.player_club.division

	var by_matchday : Dictionary = {}
	for f in SeasonManager.fixtures:
		if f["division"] != division:
			continue
		by_matchday.get_or_add(f["matchday"], []).append(f)

	var matchdays := by_matchday.keys()
	matchdays.sort()

	var focus : TreeItem = null       # player's next unplayed fixture
	var fallback : TreeItem = null    # last player fixture, once the season is over

	for matchday in matchdays:
		var fixtures : Array = by_matchday[matchday]
		var header := fixtures_tree.create_item(root)
		# The date column is too narrow for "Día N de M · <phase>" (it used
		# to truncate to "DIA 3 DE 7 · PR..."), so the day counter stays there
		# and the phase moves into the wide Local column next to the label.
		var first : Dictionary = fixtures[0]
		header.set_text(COL_DATE, tr("Día %d de %d") % [first.get("phase_day", 1), first.get("phase_length", 1)])
		var phase_name := tr(SeasonManager.phase_label_key(SeasonManager.phase_for_fixture(first)))
		header.set_text(COL_HOME, tr("Amistosos de Pretemporada") if matchday == -1 \
			else "%s  ·  %s" % [tr("Fecha %d") % (matchday + 1), phase_name])
		for col in COLUMNS.size():
			header.set_selectable(col, false)
		TreeStyle.tint_row(header, HubPalette.MUTED)

		for f in fixtures:
			var item := _add_fixture_row(header, f)
			if f["home_id"] != player_id and f["away_id"] != player_id:
				continue
			fallback = item
			# Skip a fixture whose day passed unplayed — it can never be played.
			if not f["played"] and focus == null \
					and GameState.days_until(f["day"], f["month"], f["year"]) >= 0:
				focus = item

	var selected := focus if focus != null else fallback
	if selected != null:
		fixtures_tree.set_selected(selected, COL_HOME)
		fixtures_tree.scroll_to_item(selected, true)
		_show_fixture(selected.get_metadata(0))
	else:
		_show_empty()

func _add_fixture_row(parent: TreeItem, f: Dictionary) -> TreeItem:
	var player_id := GameState.player_club.id
	var home := DataLoader.get_club(f["home_id"])
	var away := DataLoader.get_club(f["away_id"])

	var item := fixtures_tree.create_item(parent)
	item.set_text(COL_HOME, home.display_name if home != null else f["home_id"])
	item.set_text(COL_AWAY, away.display_name if away != null else f["away_id"])
	item.set_text(COL_SCORE, "%d - %d" % [f["home_score"], f["away_score"]] if f["played"] else "vs")
	item.set_metadata(0, f)
	TreeStyle.align_row(item, COLUMNS)

	if f["home_id"] == player_id or f["away_id"] == player_id:
		TreeStyle.tint_row(item, HubPalette.HIGHLIGHT)
	elif not f["played"]:
		item.set_custom_color(COL_SCORE, HubPalette.MUTED)
	return item

# ── phase grid ────────────────────────────────────────────────────────────────

const CELL_BG        := Color(0.05, 0.13, 0.17, 0.9)
const CELL_BG_PAST   := Color(0.05, 0.13, 0.17, 0.45)
const CELL_BG_MATCH  := Color(0.1, 0.24, 0.3, 1.0)

## FM-style calendar grid for the phase in progress: one cell per "Día", seven
## to a row, the player's own fixtures marked with the opponent's crest, venue
## and (once played) the result. The game deliberately has no real dates, so
## this follows the phase counter rather than a month.
func _populate_phase_grid() -> void:
	_clear(phase_grid)
	var phase := SeasonManager.phase
	var length := SeasonManager.phase_length
	var today := SeasonManager.phase_day
	var window_open := phase == SeasonManager.Phase.PRE_SEASON or phase == SeasonManager.Phase.MID_SEASON_BREAK
	phase_note.text = "%s  ·  %s" % [tr(SeasonManager.phase_label_key(phase)),
		tr("Mercado abierto") if window_open else tr("Mercado cerrado")]
	phase_note.add_theme_color_override("font_color", HubPalette.WIN if window_open else HubPalette.MUTED)

	var player_id := GameState.player_club.id
	var by_day : Dictionary = {}
	for f in SeasonManager.fixtures:
		if not f.has("phase_day") or SeasonManager.phase_for_fixture(f) != phase:
			continue
		if f["home_id"] == player_id or f["away_id"] == player_id:
			by_day[int(f["phase_day"])] = f

	for day in range(1, length + 1):
		phase_grid.add_child(_day_cell(day, today, by_day.get(day, {})))

func _day_cell(day: int, today: int, f: Dictionary) -> Control:
	var style := StyleBoxFlat.new()
	style.bg_color = CELL_BG_MATCH if not f.is_empty() else (CELL_BG_PAST if day < today else CELL_BG)
	style.set_content_margin_all(4)
	style.set_corner_radius_all(2)
	if day == today:
		style.set_border_width_all(2)
		style.border_color = HubPalette.HIGHLIGHT

	var cell := PanelContainer.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(0, 40)
	cell.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(row)

	var day_label := Label.new()
	day_label.text = str(day)
	day_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	day_label.size_flags_vertical = Control.SIZE_FILL
	day_label.add_theme_color_override("font_color",
		HubPalette.HIGHLIGHT if day == today else (HubPalette.MUTED if day < today else Color.WHITE))
	row.add_child(day_label)

	if f.is_empty():
		return cell

	var player_id := GameState.player_club.id
	var is_home : bool = f["home_id"] == player_id
	var opponent := DataLoader.get_club(f["away_id"] if is_home else f["home_id"])
	var crest := TextureRect.new()
	crest.custom_minimum_size = Vector2(24, 24)
	crest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	crest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if opponent != null:
		ClubLogo.apply(crest, opponent)
	row.add_child(crest)

	var info := Label.new()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if f["played"]:
		var own : int = f["home_score"] if is_home else f["away_score"]
		var opp : int = f["away_score"] if is_home else f["home_score"]
		info.text = "%d-%d" % [own, opp]
		info.add_theme_color_override("font_color", HubPalette.result_color(own, opp))
	else:
		info.text = tr("L") if is_home else tr("V")
		info.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
	row.add_child(info)

	var competition := tr("Amistoso") if f["type"] == "friendly" else tr("Fecha %d") % (int(f["matchday"]) + 1)
	cell.tooltip_text = "%s  ·  %s %s" % [competition, tr("vs"),
		opponent.display_name if opponent != null else "?"]
	cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cell.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_select_fixture(f))
	return cell

## Selects [param f]'s row in the fixture list (scrolling to it) and shows it.
func _select_fixture(f: Dictionary) -> void:
	var root := fixtures_tree.get_root()
	if root != null:
		for header in root.get_children():
			for item in header.get_children():
				if item.get_metadata(0) == f:
					fixtures_tree.set_selected(item, COL_HOME)
					fixtures_tree.scroll_to_item(item, true)
	_show_fixture(f)

func _on_fixture_selected() -> void:
	var item := fixtures_tree.get_selected()
	if item == null:
		return
	var f = item.get_metadata(0)
	if f is Dictionary:
		_show_fixture(f)

# ── detail panel ──────────────────────────────────────────────────────────────

func _show_empty() -> void:
	detail_title.text = "SIN PARTIDOS"
	kickoff_label.text = ""
	score_label.text = ""
	_clear(compare_grid)
	_clear(h2h_list)
	_clear(home_players)
	_clear(away_players)

func _show_fixture(f: Dictionary) -> void:
	var home := DataLoader.get_club(f["home_id"])
	var away := DataLoader.get_club(f["away_id"])
	var player_id := GameState.player_club.id
	var is_home_side : bool = f["home_id"] == player_id
	var involves_player : bool = is_home_side or f["away_id"] == player_id

	if f["played"]:
		detail_title.text = "RESULTADO"
	else:
		detail_title.text = "PRÓXIMO PARTIDO" if involves_player else "PARTIDO"

	ClubLogo.apply(home_logo, home)
	ClubLogo.apply(away_logo, away)
	home_name.text = home.display_name if home != null else "?"
	away_name.text = away.display_name if away != null else "?"

	kickoff_label.text = SeasonManager.fixture_date_string(f)

	if f["played"]:
		score_label.text = "%d  -  %d" % [f["home_score"], f["away_score"]]
		var own : int = f["home_score"] if is_home_side else f["away_score"]
		var opp : int = f["away_score"] if is_home_side else f["home_score"]
		score_label.add_theme_color_override("font_color",
			HubPalette.result_color(own, opp) if involves_player else Color.WHITE)
	elif involves_player:
		score_label.text = "LOCAL" if is_home_side else "VISITANTE"
		score_label.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
	else:
		score_label.text = "PRÓXIMO"
		score_label.add_theme_color_override("font_color", HubPalette.MUTED)

	_build_compare(home, away)
	_build_key_players(home_players, home)
	_build_key_players(away_players, away)
	_build_head_to_head(home, away)

func _build_compare(home: ClubResource, away: ClubResource) -> void:
	_clear(compare_grid)
	_add_compare_row("LOCAL", "", "VISITANTE", HubPalette.MUTED)
	for row in COMPARE_ROWS:
		_add_compare_row(_compare_value(home, row["key"]), row["label"],
						 _compare_value(away, row["key"]), Color.WHITE)

func _compare_value(club: ClubResource, key: String) -> String:
	if club == null:
		return "-"
	match key:
		"position":
			return "#%d" % Standings.position_of(club)
		"points":
			return str(club.tournament_points)
		"record":
			return Standings.record_string(club)
		"overall":
			return str(club.get_squad_overall())
		"goals":
			return "%d:%d" % [club.goals_for, club.goals_against]
	return "-"

func _add_compare_row(left: String, middle: String, right: String, color: Color) -> void:
	compare_grid.add_child(_grid_label(left, HORIZONTAL_ALIGNMENT_LEFT, color, 70))
	compare_grid.add_child(_grid_label(middle, HORIZONTAL_ALIGNMENT_CENTER, HubPalette.MUTED, 130))
	compare_grid.add_child(_grid_label(right, HORIZONTAL_ALIGNMENT_RIGHT, color, 70))

func _grid_label(text: String, align: int, color: Color, min_width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = align
	label.custom_minimum_size.x = min_width
	label.add_theme_color_override("font_color", color)
	return label

func _build_key_players(container: VBoxContainer, club: ClubResource) -> void:
	_clear(container)
	if club == null:
		return
	var squad := club.players.duplicate()
	squad.sort_custom(func(a: PlayerResource, b: PlayerResource) -> bool:
		return a.overall() > b.overall())
	for i in mini(KEY_PLAYER_COUNT, squad.size()):
		var p : PlayerResource = squad[i]
		var row := Label.new()
		row.text = "%d  %s" % [p.overall(), p.full_name]
		row.add_theme_color_override("font_color", QualityStyle.COLORS[p.quality])
		row.clip_text = true
		container.add_child(row)

func _build_head_to_head(home: ClubResource, away: ClubResource) -> void:
	_clear(h2h_list)
	if home == null or away == null:
		return
	var any := false
	for f in SeasonManager.fixtures:
		if not f["played"]:
			continue
		var same_pair : bool = (f["home_id"] == home.id and f["away_id"] == away.id) or (f["home_id"] == away.id and f["away_id"] == home.id)
		if not same_pair:
			continue
		var host := DataLoader.get_club(f["home_id"])
		var row := Label.new()
		row.text = "%s   %s  %d - %d" % [
			_date_string(f),
			host.display_name if host != null else f["home_id"],
			f["home_score"], f["away_score"]]
		h2h_list.add_child(row)
		any = true
	if not any:
		var row := Label.new()
		row.text = "Sin enfrentamientos previos"
		row.add_theme_color_override("font_color", HubPalette.MUTED)
		h2h_list.add_child(row)

# ── helpers ───────────────────────────────────────────────────────────────────

func _date_string(f: Dictionary) -> String:
	return SeasonManager.fixture_date_string(f)

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
