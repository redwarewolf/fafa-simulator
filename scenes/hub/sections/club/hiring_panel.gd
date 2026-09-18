extends Control

## Browse and hire the Talent Scout's current candidate pool. Locked until a
## scout is hired. The pool itself is generated/refreshed by
## GameState.refresh_scout_pool() (on first hire and on every month rollover)
## — this panel only reads GameState.player_club.scouted_players.

const COL_NAME    := 0
const COL_ROLE    := 1
const COL_AGE     := 2
const COL_QUALITY := 3

const POOL_COLUMNS : Array = [
	{"title": "Nombre",  "expand": true,  "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"title": "Pos",     "expand": false, "min_width": 46, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Edad",    "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Calidad", "expand": false, "min_width": 90, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

@onready var locked_message : Label   = $LockedMessage
@onready var hbox           : HBoxContainer = $HBox
@onready var pool_tree      : Tree    = $HBox/PoolPanel/VBox/PoolTree
@onready var player_card    : Control = $HBox/MidPanel/VBox/PlayerCard
@onready var budget_label   : Label   = $HBox/MidPanel/VBox/BudgetLabel
@onready var action_button  : Button  = $HBox/MidPanel/VBox/ActionButton

var _selected_player : PlayerResource = null


func _ready() -> void:
	TreeStyle.setup_columns(pool_tree, POOL_COLUMNS)
	refresh()


func refresh() -> void:
	var club := GameState.player_club
	var hired : bool = club.upgrades.get("scout", 0) > 0
	locked_message.visible = not hired
	hbox.visible = hired
	if not hired:
		return

	_clear_selection()
	budget_label.text = tr("Presupuesto: $%s") % MoneyFormat.format(club.budget)
	_populate_pool_tree()
	GameState.mark_scout_seen()


func _populate_pool_tree() -> void:
	pool_tree.clear()
	var root := pool_tree.create_item()

	for p : PlayerResource in GameState.player_club.scouted_players:
		var item := pool_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_text(COL_NAME,    p.full_name)
		item.set_text(COL_ROLE,    Positions.label(p.role))
		item.set_text(COL_AGE,     str(p.age))
		item.set_text(COL_QUALITY, tr(QualityStyle.NAMES[p.quality]))
		for col in [COL_NAME, COL_ROLE, COL_AGE, COL_QUALITY]:
			item.set_custom_color(col, qcolor)
		TreeStyle.align_row(item, POOL_COLUMNS)
		item.set_metadata(0, p)


func _on_pool_tree_item_selected() -> void:
	var item := pool_tree.get_selected()
	if item == null:
		return
	var p := item.get_metadata(0) as PlayerResource

	_selected_player = p
	player_card.setup(p)

	var price := PlayerValue.estimate(p)
	var can_hire := GameState.player_club.budget >= price
	if can_hire:
		action_button.text = tr("FICHAR — $%s") % MoneyFormat.format(price)
	else:
		action_button.text = "PRESUPUESTO INSUFICIENTE"
	action_button.disabled = not can_hire


func _on_action_pressed() -> void:
	if _selected_player == null:
		return
	var p := _selected_player
	var club := GameState.player_club
	var price := PlayerValue.estimate(p)
	if club.budget < price:
		return

	club.scouted_players.erase(p)
	club.players.append(p)
	club.budget -= price
	GameState.budget_changed.emit()
	GameState.save_upgrades()
	GameState.save_staff()
	refresh()


func _clear_selection() -> void:
	_selected_player = null
	player_card.clear()
	action_button.disabled = true
	action_button.text = "SELECCIONÁ UN JUGADOR"
