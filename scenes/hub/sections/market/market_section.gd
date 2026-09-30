extends Control

const MIN_SQUAD_SIZE := 6
const SELL_MULTIPLIER := 0.4  ## selling nets 40% of market value

const SELL_COL_NAME  := 0
const SELL_COL_POS   := 1
const SELL_COL_OVR   := 2
const SELL_COL_VALUE := 3

const BUY_COL_NAME  := 0
const BUY_COL_POS   := 1
const BUY_COL_OVR   := 2
const BUY_COL_CLUB  := 3
const BUY_COL_VALUE := 4

const SELL_COLUMNS := [
	{"title": "Nombre", "expand": true},
	{"title": "Pos",   "expand": false, "min_width": 46, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "OVR",   "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Valor", "expand": false, "min_width": 84, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]

const BUY_COLUMNS := [
	{"title": "Nombre", "expand": true, "ratio": 1.2},
	{"title": "Pos",   "expand": false, "min_width": 46, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "OVR",   "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Club",  "expand": true},
	{"title": "Valor", "expand": false, "min_width": 84, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]

@onready var sell_tree     : Tree   = $HBox/SellPanel/VBox/SellTree
@onready var buy_tree      : Tree   = $HBox/RightPanel/VBox/BuyTree
@onready var player_card   : Control = $HBox/MidPanel/VBox/PlayerCard
@onready var budget_label  : Label  = $HBox/MidPanel/VBox/BudgetLabel
@onready var action_button : Button = $HBox/MidPanel/VBox/ActionButton

var _selected_player : PlayerResource = null
var _selected_mode   : String = ""  # "sell" or "buy"
var _selected_source_club : ClubResource = null  # buy only — club to remove the player from

@onready var filter_row : VBoxContainer = $HBox/RightPanel/VBox/FilterRow
@onready var compare_box : VBoxContainer = $HBox/MidPanel/VBox/CompareBox

## FM-style search filters over the buy list (see _build_filters()).
const GROUP_FILTERS := [
	["Todas las posiciones", -1],
	["Arqueros", Positions.Group.GOALIE],
	["Defensores", Positions.Group.DEFENSE],
	["Mediocampistas", Positions.Group.MIDFIELD],
	["Delanteros", Positions.Group.OFFENSE],
]
var _filter_text := ""
var _filter_group := -1
var _filter_min_quality := 0
var _filter_affordable := false
var _buy_sort_col := BUY_COL_VALUE
var _buy_sort_asc := false
var _count_label : Label = null


func _ready() -> void:
	TreeStyle.setup_columns(sell_tree, SELL_COLUMNS)
	TreeStyle.setup_columns(buy_tree, BUY_COLUMNS)
	_build_filters()

	_populate()


func refresh() -> void:
	_populate()


func _populate() -> void:
	_clear_selection()
	budget_label.text = tr("Presupuesto: $%s") % MoneyFormat.format(GameState.player_club.budget)
	# Say up front whether the window is open, not only once a row is clicked.
	budget_label.text += "   ·   " + (tr("MERCADO ABIERTO") if _window_open() else tr("MERCADO CERRADO"))
	budget_label.add_theme_color_override("font_color", Color.WHITE if _window_open() else HubPalette.LOSS)
	_populate_sell_tree()
	_populate_buy_tree()


func _sell_price(p: PlayerResource) -> int:
	return maxi(0, roundi(PlayerValue.estimate(p) * SELL_MULTIPLIER))


func _populate_sell_tree() -> void:
	sell_tree.clear()
	var root := sell_tree.create_item()

	var squad := GameState.player_club.players.duplicate()
	squad.sort_custom(func(a: PlayerResource, b: PlayerResource) -> bool:
		return _sell_price(a) > _sell_price(b))

	for p : PlayerResource in squad:
		var item := sell_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_text(SELL_COL_NAME,  p.full_name)
		item.set_text(SELL_COL_OVR,   str(p.overall()))
		item.set_text(SELL_COL_VALUE, "$%s" % MoneyFormat.format(_sell_price(p)))
		for col in [SELL_COL_NAME, SELL_COL_OVR, SELL_COL_VALUE]:
			item.set_custom_color(col, qcolor)
		_set_pos_badge(item, SELL_COL_POS, p)
		TreeStyle.align_row(item, SELL_COLUMNS)
		item.set_metadata(0, p)


func _populate_buy_tree() -> void:
	buy_tree.clear()
	var root := buy_tree.create_item()

	var listings : Array = []
	for club : ClubResource in DataLoader.clubs.values():
		if club.id == GameState.player_club.id:
			continue
		for p in club.players:
			listings.append({"player": p, "club": club})

	var budget : int = GameState.player_club.budget
	listings = listings.filter(func(e: Dictionary) -> bool:
		var p : PlayerResource = e["player"]
		if _filter_text != "" and not p.full_name.to_lower().contains(_filter_text):
			return false
		if _filter_group >= 0 and Positions.group(p.role) != _filter_group:
			return false
		if p.quality < _filter_min_quality:
			return false
		if _filter_affordable and PlayerValue.estimate(p) > budget:
			return false
		return true)
	listings.sort_custom(_compare_listings)
	if _count_label != null:
		_count_label.text = tr("%d jugadores") % listings.size()

	for entry in listings:
		var p : PlayerResource = entry["player"]
		var club : ClubResource = entry["club"]
		var item := buy_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_text(BUY_COL_NAME,  p.full_name)
		item.set_text(BUY_COL_OVR,   str(p.overall()))
		item.set_text(BUY_COL_CLUB,  club.display_name)
		item.set_text(BUY_COL_VALUE, "$%s" % MoneyFormat.format(PlayerValue.estimate(p)))
		for col in [BUY_COL_NAME, BUY_COL_OVR, BUY_COL_CLUB, BUY_COL_VALUE]:
			item.set_custom_color(col, qcolor)
		_set_pos_badge(item, BUY_COL_POS, p)
		TreeStyle.align_row(item, BUY_COLUMNS)
		item.set_metadata(0, p)
		item.set_metadata(1, club)


func _compare_listings(a: Dictionary, b: Dictionary) -> bool:
	var pa : PlayerResource = a["player"]
	var pb : PlayerResource = b["player"]
	var ka : Variant
	var kb : Variant
	match _buy_sort_col:
		BUY_COL_NAME:
			ka = pa.full_name
			kb = pb.full_name
		BUY_COL_POS:
			ka = pa.role
			kb = pb.role
		BUY_COL_OVR:
			ka = pa.overall()
			kb = pb.overall()
		BUY_COL_CLUB:
			ka = a["club"].display_name
			kb = b["club"].display_name
		_:
			ka = PlayerValue.estimate(pa)
			kb = PlayerValue.estimate(pb)
	if ka == kb:
		return PlayerValue.estimate(pa) > PlayerValue.estimate(pb)
	return ka < kb if _buy_sort_asc else ka > kb

func _on_buy_tree_column_title_clicked(column: int, _mouse_button_index: int) -> void:
	if _buy_sort_col == column:
		_buy_sort_asc = not _buy_sort_asc
	else:
		_buy_sort_col = column
		# Text reads best A→Z; numbers best high → low.
		_buy_sort_asc = column in [BUY_COL_NAME, BUY_COL_POS, BUY_COL_CLUB]
	_populate_buy_tree()

## Two rows (search + count, then dropdowns + checkbox) so the filters never
## widen the buy panel past its share of the screen.
func _build_filters() -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	filter_row.add_child(top)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	filter_row.add_child(bottom)

	var search := LineEdit.new()
	search.placeholder_text = tr("Buscar nombre...")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.clear_button_enabled = true
	search.text_changed.connect(func(t: String) -> void:
		_filter_text = t.strip_edges().to_lower()
		_populate_buy_tree())
	top.add_child(search)

	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", HubPalette.MUTED)
	top.add_child(_count_label)

	var group := _filter_dropdown(bottom)
	for entry in GROUP_FILTERS:
		group.add_item(tr(entry[0]))
	group.item_selected.connect(func(i: int) -> void:
		_filter_group = GROUP_FILTERS[i][1]
		_populate_buy_tree())

	var quality := _filter_dropdown(bottom)
	for i in QualityStyle.NAMES.size():
		quality.add_item(tr("%s o mejor") % tr(QualityStyle.NAMES[i]) if i > 0 else tr("Toda calidad"))
	quality.item_selected.connect(func(i: int) -> void:
		_filter_min_quality = i
		_populate_buy_tree())

	var affordable := CheckBox.new()
	affordable.text = tr("Solo alcanzables")
	affordable.tooltip_text = tr("Ocultar jugadores que valen más que tu presupuesto")
	affordable.toggled.connect(func(on: bool) -> void:
		_filter_affordable = on
		_populate_buy_tree())
	bottom.add_child(affordable)

func _filter_dropdown(parent: Control) -> OptionButton:
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	option.clip_text = true
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size.x = 60
	parent.add_child(option)
	return option

## Position badge in the same line colours as the Squad roster and pitch.
func _set_pos_badge(item: TreeItem, col: int, p: PlayerResource) -> void:
	item.set_text(col, Positions.label(p.role))
	item.set_custom_bg_color(col, Positions.color(p.role))
	item.set_custom_color(col, Positions.ink_on(p.role))


func _on_sell_tree_item_selected() -> void:
	var item := sell_tree.get_selected()
	if item == null:
		return
	var p := item.get_metadata(0) as PlayerResource

	_selected_player = p
	_selected_mode = "sell"
	_clear_comparison()
	_selected_source_club = null
	player_card.setup(p, GameState.player_club.team_key)

	if not _window_open():
		action_button.text = "MERCADO DE PASES CERRADO"
		action_button.disabled = true
		return

	var can_sell := GameState.player_club.players.size() > MIN_SQUAD_SIZE
	if can_sell:
		action_button.text = tr("VENDER — $%s") % MoneyFormat.format(_sell_price(p))
	else:
		action_button.text = "PLANTEL MUY CHICO"
	action_button.disabled = not can_sell


func _on_buy_tree_item_selected() -> void:
	var item := buy_tree.get_selected()
	if item == null:
		return
	var p := item.get_metadata(0) as PlayerResource
	var club := item.get_metadata(1) as ClubResource

	_selected_player = p
	_selected_mode = "buy"
	_selected_source_club = club
	player_card.setup(p, club.team_key)
	_show_comparison(p)

	if not _window_open():
		action_button.text = "MERCADO DE PASES CERRADO"
		action_button.disabled = true
		return

	var price := PlayerValue.estimate(p)
	var can_buy := GameState.player_club.budget >= price
	if can_buy:
		action_button.text = tr("COMPRAR — $%s") % MoneyFormat.format(price)
	else:
		action_button.text = "PRESUPUESTO INSUFICIENTE"
	action_button.disabled = not can_buy


## FM-style "compare with": the target's six stats against the best player
## you already have in the same line (keeper/defence/midfield/attack), with
## the difference coloured — is this signing actually an upgrade?
func _show_comparison(target: PlayerResource) -> void:
	_clear_comparison()
	var group := Positions.group(target.role)
	var own : PlayerResource = null
	for p : PlayerResource in GameState.player_club.players:
		if Positions.group(p.role) == group and (own == null or p.overall() > own.overall()):
			own = p
	var title := Label.new()
	compare_box.add_child(title)
	if own == null:
		title.text = tr("No tenés jugadores en esa línea")
		title.add_theme_color_override("font_color", HubPalette.MUTED)
		return
	title.text = tr("COMPARADO CON %s (%s, OVR %d)") % [own.full_name, Positions.label(own.role), own.overall()]
	title.add_theme_color_override("font_color", HubPalette.MUTED)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	compare_box.add_child(grid)
	for header in ["", tr("Él"), tr("Tuyo"), "+/-"]:
		_compare_cell(grid, header, HubPalette.MUTED)
	for key in ["pac", "sho", "pas", "dri", "def", "phy", "ovr"]:
		var theirs : int = target.overall() if key == "ovr" else target.get_effective_stat(key)
		var mine : int = own.overall() if key == "ovr" else own.get_effective_stat(key)
		var diff := theirs - mine
		_compare_cell(grid, key.to_upper(), HubPalette.MUTED)
		_compare_cell(grid, str(theirs), Color.WHITE)
		_compare_cell(grid, str(mine), Color.WHITE)
		_compare_cell(grid, "%+d" % diff if diff != 0 else "=",
			HubPalette.WIN if diff > 0 else (HubPalette.LOSS if diff < 0 else HubPalette.MUTED))

func _compare_cell(grid: GridContainer, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", color)
	grid.add_child(l)

func _clear_comparison() -> void:
	for child in compare_box.get_children():
		compare_box.remove_child(child)
		child.queue_free()

func _on_action_pressed() -> void:
	if _selected_player == null:
		return
	if _selected_mode == "sell":
		_sell_selected()
	elif _selected_mode == "buy":
		_buy_selected()


func _window_open() -> bool:
	return SeasonManager.phase == SeasonManager.Phase.PRE_SEASON \
		or SeasonManager.phase == SeasonManager.Phase.MID_SEASON_BREAK


func _sell_selected() -> void:
	if not _window_open():
		return
	var p := _selected_player
	var club := GameState.player_club
	if club.players.size() <= MIN_SQUAD_SIZE:
		return

	club.players.erase(p)
	_clear_from_tactics(p)
	club.budget += _sell_price(p)
	GameState.budget_changed.emit()
	_populate()


func _buy_selected() -> void:
	if not _window_open():
		return
	var p := _selected_player
	var source := _selected_source_club
	var club := GameState.player_club
	var price := PlayerValue.estimate(p)
	if club.budget < price or source == null:
		return

	source.players.erase(p)
	# AI clubs have no transfer market of their own to replace who they sell —
	# backfill with a fresh same-role player so their squad never shrinks below
	# what they need to field a team. Mirrors the retirement backfill in
	# season_manager.gd's _age_and_retire_players().
	source.players.append(PlayerFactory.generate_player(ClubFactory.ai_odds_for(source.division), p.role))
	club.players.append(p)
	club.budget -= price
	GameState.budget_changed.emit()
	_populate()


func _clear_from_tactics(p: PlayerResource) -> void:
	GameState.clear_player_from_tactics(p)


func _clear_selection() -> void:
	_selected_player = null
	_selected_mode = ""
	_selected_source_club = null
	player_card.clear()
	_clear_comparison()
	action_button.disabled = true
	action_button.text = "SELECCIONÁ UN JUGADOR"
