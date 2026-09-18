extends Control

const MIN_SQUAD_SIZE := 6
const SELL_MULTIPLIER := 0.4  ## selling nets 40% of market value

const SELL_COL_NAME  := 0
const SELL_COL_VALUE := 1

const BUY_COL_NAME  := 0
const BUY_COL_CLUB  := 1
const BUY_COL_VALUE := 2

@onready var sell_tree     : Tree   = $HBox/SellPanel/VBox/SellTree
@onready var buy_tree      : Tree   = $HBox/RightPanel/VBox/BuyTree
@onready var player_card   : Control = $HBox/MidPanel/VBox/PlayerCard
@onready var budget_label  : Label  = $HBox/MidPanel/VBox/BudgetLabel
@onready var action_button : Button = $HBox/MidPanel/VBox/ActionButton

var _selected_player : PlayerResource = null
var _selected_mode   : String = ""  # "sell" or "buy"
var _selected_source_club : ClubResource = null  # buy only — club to remove the player from


func _ready() -> void:
	sell_tree.set_column_title(SELL_COL_NAME,  tr("Nombre"))
	sell_tree.set_column_title(SELL_COL_VALUE, tr("Valor"))
	sell_tree.set_column_expand(SELL_COL_NAME, true)
	sell_tree.set_column_expand(SELL_COL_VALUE, false)
	sell_tree.set_column_custom_minimum_width(SELL_COL_VALUE, 90)

	buy_tree.set_column_title(BUY_COL_NAME,  tr("Nombre"))
	buy_tree.set_column_title(BUY_COL_CLUB,  tr("Club"))
	buy_tree.set_column_title(BUY_COL_VALUE, tr("Valor"))
	buy_tree.set_column_expand(BUY_COL_NAME, true)
	buy_tree.set_column_expand(BUY_COL_CLUB, true)
	buy_tree.set_column_expand(BUY_COL_VALUE, false)
	buy_tree.set_column_custom_minimum_width(BUY_COL_VALUE, 80)

	_populate()


func refresh() -> void:
	_populate()


func _populate() -> void:
	_clear_selection()
	budget_label.text = tr("Presupuesto: $%s") % MoneyFormat.format(GameState.player_club.budget)
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
		item.set_text(SELL_COL_NAME,  "%s  (%s)" % [p.full_name, Positions.label(p.role)])
		item.set_text(SELL_COL_VALUE, "$%s" % MoneyFormat.format(_sell_price(p)))
		item.set_text_alignment(SELL_COL_VALUE, HORIZONTAL_ALIGNMENT_RIGHT)
		for col in [SELL_COL_NAME, SELL_COL_VALUE]:
			item.set_custom_color(col, qcolor)
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

	listings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return PlayerValue.estimate(a["player"]) > PlayerValue.estimate(b["player"]))

	for entry in listings:
		var p : PlayerResource = entry["player"]
		var club : ClubResource = entry["club"]
		var item := buy_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_text(BUY_COL_NAME,  p.full_name)
		item.set_text(BUY_COL_CLUB,  club.display_name)
		item.set_text(BUY_COL_VALUE, "$%s" % MoneyFormat.format(PlayerValue.estimate(p)))
		item.set_text_alignment(BUY_COL_VALUE, HORIZONTAL_ALIGNMENT_RIGHT)
		for col in [BUY_COL_NAME, BUY_COL_CLUB, BUY_COL_VALUE]:
			item.set_custom_color(col, qcolor)
		item.set_metadata(0, p)
		item.set_metadata(1, club)


func _on_sell_tree_item_selected() -> void:
	var item := sell_tree.get_selected()
	if item == null:
		return
	var p := item.get_metadata(0) as PlayerResource

	_selected_player = p
	_selected_mode = "sell"
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
	action_button.disabled = true
	action_button.text = "SELECCIONÁ UN JUGADOR"
