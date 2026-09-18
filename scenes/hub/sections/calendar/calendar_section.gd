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
		header.set_text(COL_DATE, _date_string(fixtures[0]))
		header.set_text(COL_HOME, "Amistosos de Pretemporada" if matchday == -1 else "Fecha %d" % (matchday + 1))
		for col in COLUMNS.size():
			header.set_selectable(col, false)
		TreeStyle.tint_row(header, HubPalette.MUTED)

		for f in fixtures:
			var item := _add_fixture_row(header, f)
			if f["home_id"] != player_id and f["away_id"] != player_id:
				continue
			fallback = item
			if not f["played"] and focus == null:
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

	kickoff_label.text = GameState.format_date(f["day"], f["month"], f["year"])

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
	return GameState.format_date(f["day"], f["month"], f["year"], false)

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
