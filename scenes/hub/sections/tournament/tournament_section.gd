extends Control

## League table + club inspector.
##
## The table alone filled about a third of a widescreen window and the club
## panel sat empty until something was clicked. The left column now stacks the
## standings over a league-wide top-rated list, the right panel opens on the
## player's own club and shows its full squad.


const STANDINGS_COLUMNS := [
	{"title": "#",    "expand": false, "min_width": 34, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Club", "expand": true},
	{"title": "PJ",   "expand": false, "min_width": 32, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "G",    "expand": false, "min_width": 32, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "E",    "expand": false, "min_width": 32, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "P",    "expand": false, "min_width": 32, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "DG",   "expand": false, "min_width": 40, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Pts",  "expand": false, "min_width": 40, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

const TOP_PLAYER_COLUMNS := [
	{"title": "Nombre", "expand": true},
	{"title": "Club", "expand": true},
	{"title": "Pos",  "expand": false, "min_width": 48, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "OVR",  "expand": false, "min_width": 48, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

const SQUAD_COLUMNS := [
	{"title": "Nombre", "expand": true},
	{"title": "Pos",  "expand": false, "min_width": 48, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Edad", "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "OVR",  "expand": false, "min_width": 48, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

const TOP_PLAYER_COUNT := 25

@onready var standings_tree      : Tree         = $HBox/LeftColumn/StandingsPanel/VBox/StandingsTree
@onready var top_players_tree    : Tree         = $HBox/LeftColumn/TopPlayersPanel/VBox/TopPlayersTree
@onready var club_logo           : TextureRect  = $HBox/DetailPanel/VBox/HeaderRow/ClubLogo
@onready var club_name_label     : Label        = $HBox/DetailPanel/VBox/HeaderRow/Info/ClubName
@onready var club_division_label : Label        = $HBox/DetailPanel/VBox/HeaderRow/Info/ClubDivision
@onready var primary_swatch      : ColorRect    = $HBox/DetailPanel/VBox/HeaderRow/Info/ColorsRow/PrimaryColor
@onready var secondary_swatch    : ColorRect    = $HBox/DetailPanel/VBox/HeaderRow/Info/ColorsRow/SecondaryColor
@onready var stats_grid          : GridContainer = $HBox/DetailPanel/VBox/StatsGrid
@onready var squad_tree          : Tree         = $HBox/DetailPanel/VBox/SquadTree

func _ready() -> void:
	TreeStyle.setup_columns(standings_tree, STANDINGS_COLUMNS)
	TreeStyle.setup_columns(top_players_tree, TOP_PLAYER_COLUMNS)
	TreeStyle.setup_columns(squad_tree, SQUAD_COLUMNS)
	_populate()

func refresh() -> void:
	_populate()

# ── league table ──────────────────────────────────────────────────────────────

func _populate() -> void:
	var player_id := GameState.player_club.id
	var table := Standings.for_division(GameState.player_club.division)

	standings_tree.clear()
	var root := standings_tree.create_item()
	var own_item : TreeItem = null

	for i in table.size():
		var club : ClubResource = table[i]
		var item := standings_tree.create_item(root)
		item.set_text(0, str(i + 1))
		item.set_text(1, club.display_name)
		item.set_text(2, str(club.matches_played))
		item.set_text(3, str(club.wins))
		item.set_text(4, str(club.draws))
		item.set_text(5, str(club.losses))
		item.set_text(6, "%+d" % (club.goals_for - club.goals_against))
		item.set_text(7, str(club.tournament_points))
		item.set_metadata(0, club)
		TreeStyle.align_row(item, STANDINGS_COLUMNS)
		if club.id == player_id:
			TreeStyle.tint_row(item, HubPalette.HIGHLIGHT)
			own_item = item

	_populate_top_players()

	# Open on the player's own club instead of an empty panel.
	if own_item != null:
		standings_tree.set_selected(own_item, 1)
		_show_club_details(own_item.get_metadata(0))
	elif root.get_child_count() > 0:
		_show_club_details(root.get_first_child().get_metadata(0))

func _populate_top_players() -> void:
	top_players_tree.clear()
	var root := top_players_tree.create_item()

	var division := GameState.player_club.division
	var entries : Array = []
	for club : ClubResource in DataLoader.clubs.values():
		if club.division != division:
			continue
		for p : PlayerResource in club.players:
			entries.append({"player": p, "club": club})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["player"].overall() > b["player"].overall())

	var player_id := GameState.player_club.id
	for i in mini(TOP_PLAYER_COUNT, entries.size()):
		var p : PlayerResource = entries[i]["player"]
		var club : ClubResource = entries[i]["club"]
		var item := top_players_tree.create_item(root)
		item.set_text(0, p.full_name)
		item.set_text(1, club.display_name)
		item.set_text(2, Positions.label(p.role))
		item.set_text(3, str(p.overall()))
		item.set_metadata(0, club)
		TreeStyle.align_row(item, TOP_PLAYER_COLUMNS)
		TreeStyle.tint_row(item, QualityStyle.COLORS[p.quality])
		if club.id == player_id:
			item.set_custom_color(1, HubPalette.HIGHLIGHT)

# ── club inspector ────────────────────────────────────────────────────────────

func _on_club_selected() -> void:
	var selected := standings_tree.get_selected()
	if selected != null:
		_show_club_details(selected.get_metadata(0) as ClubResource)

func _on_top_player_selected() -> void:
	var selected := top_players_tree.get_selected()
	if selected != null:
		_show_club_details(selected.get_metadata(0) as ClubResource)

func _show_club_details(club: ClubResource) -> void:
	if club == null:
		return
	club_name_label.text     = club.display_name
	club_division_label.text = tr("División %s   ·   %d jugadores") % [club.division, club.players.size()]
	primary_swatch.color     = club.primary_color
	secondary_swatch.color   = club.secondary_color
	ClubLogo.apply(club_logo, club)

	var is_player : bool = club.id == GameState.player_club.id
	club_name_label.add_theme_color_override("font_color",
		HubPalette.HIGHLIGHT if is_player else Color.WHITE)

	_build_stats(club)
	_build_squad(club)

func _build_stats(club: ClubResource) -> void:
	for child in stats_grid.get_children():
		stats_grid.remove_child(child)
		child.queue_free()

	var stats := [
		["Posición",      "#%d" % Standings.position_of(club)],
		["Puntos",        str(club.tournament_points)],
		["Jugados",       str(club.matches_played)],
		["Récord",        Standings.record_string(club)],
		["Goles a Favor", str(club.goals_for)],
		["En Contra",     str(club.goals_against)],
		["Dif. de Goles", "%+d" % (club.goals_for - club.goals_against)],
		["OVR Plantel",   str(club.get_squad_overall())],
	]
	for stat in stats:
		var key := Label.new()
		key.text = stat[0]
		key.add_theme_color_override("font_color", HubPalette.MUTED)
		stats_grid.add_child(key)

		var value := Label.new()
		value.text = stat[1]
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_child(value)

func _build_squad(club: ClubResource) -> void:
	squad_tree.clear()
	var root := squad_tree.create_item()
	var squad := club.players.duplicate()
	squad.sort_custom(func(a: PlayerResource, b: PlayerResource) -> bool:
		return a.overall() > b.overall())
	for p : PlayerResource in squad:
		var item := squad_tree.create_item(root)
		item.set_text(0, p.full_name)
		item.set_text(1, Positions.label(p.role))
		item.set_text(2, str(p.age))
		item.set_text(3, str(p.overall()))
		TreeStyle.align_row(item, SQUAD_COLUMNS)
		TreeStyle.tint_row(item, QualityStyle.COLORS[p.quality])
