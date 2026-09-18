extends Control

## Browse the youth academy's current prospect pool. Locked until the
## "academy" staff upgrade is hired. The pool is generated/topped up by
## GameState.refresh_youth_pool() (on first hire and once per year at
## SeasonManager.start_pre_season()) — this screen only reads/mutates
## GameState.player_club.youth_players.
##
## Unlike the scouted-player pool (hiring_panel.gd), promoting or releasing a
## prospect is free — there's no purchase, just a roster decision.

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

@onready var locked_message  : Label        = $LockedMessage
@onready var hbox            : HBoxContainer = $HBox
@onready var pool_tree       : Tree         = $HBox/PoolPanel/VBox/PoolTree
@onready var player_card     : Control      = $HBox/MidPanel/VBox/PlayerCard
@onready var promote_button  : Button       = $HBox/MidPanel/VBox/PromoteButton
@onready var release_button  : Button       = $HBox/MidPanel/VBox/ReleaseButton

var _selected_player : PlayerResource = null


func _ready() -> void:
	TreeStyle.setup_columns(pool_tree, POOL_COLUMNS)
	refresh()


func refresh() -> void:
	var club := GameState.player_club
	var hired : bool = club.upgrades.get("academy", 0) > 0
	locked_message.visible = not hired
	hbox.visible = hired
	if not hired:
		return

	_clear_selection()
	_populate_pool_tree()
	GameState.mark_youth_seen()


func _populate_pool_tree() -> void:
	pool_tree.clear()
	var root := pool_tree.create_item()

	for p : PlayerResource in GameState.player_club.youth_players:
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
	player_card.setup(p, GameState.player_club.team_key)
	promote_button.disabled = false
	release_button.disabled = false


func _on_promote_pressed() -> void:
	if _selected_player == null:
		return
	var club := GameState.player_club
	club.youth_players.erase(_selected_player)
	club.players.append(_selected_player)
	GameState.save_staff()
	refresh()


func _on_release_pressed() -> void:
	if _selected_player == null:
		return
	GameState.player_club.youth_players.erase(_selected_player)
	GameState.save_staff()
	refresh()


func _clear_selection() -> void:
	_selected_player = null
	player_card.clear()
	promote_button.disabled = true
	release_button.disabled = true
