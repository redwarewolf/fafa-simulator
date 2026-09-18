extends Control

## Manual per-player training. Locked until a Training Facility is hired.
## Facility level sets the LIFETIME session cap per player (see
## StaffData.STAFF["trainer"]["levels"]); each session is instant — pick a
## player and a stat, pay, and it's permanently boosted by +6% right away
## (see PlayerResource.add_permanent_modifier()). No waiting, nothing to
## cancel, unlike the old day-ticked Club Trainer this replaced.

const COL_NAME := 0
const COL_ROLE := 1
const COL_OVR  := 2

const SQUAD_COLUMNS : Array = [
	{"title": "Nombre", "expand": true,  "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"title": "Pos",  "expand": false, "min_width": 46, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "OVR",  "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

const STAT_LABELS := {
	"pac": "PAC", "sho": "SHO", "pas": "PAS", "dri": "DRI", "def": "DEF", "phy": "PHY",
}

const SESSION_BOOST_PCT := 6.0

@onready var locked_message : Label         = $LockedMessage
@onready var hbox           : HBoxContainer = $HBox
@onready var squad_tree     : Tree          = $HBox/SquadPanel/VBox/SquadTree
@onready var player_card    : Control       = $HBox/MidPanel/VBox/PlayerCard
@onready var sessions_label : Label         = $HBox/RightPanel/VBox/SessionsLabel

@onready var _stat_buttons : Dictionary = {
	"pac": $HBox/MidPanel/VBox/StatGrid/PacButton,
	"sho": $HBox/MidPanel/VBox/StatGrid/ShoButton,
	"pas": $HBox/MidPanel/VBox/StatGrid/PasButton,
	"dri": $HBox/MidPanel/VBox/StatGrid/DriButton,
	"def": $HBox/MidPanel/VBox/StatGrid/DefButton,
	"phy": $HBox/MidPanel/VBox/StatGrid/PhyButton,
}

var _selected_player : PlayerResource = null


func _ready() -> void:
	TreeStyle.setup_columns(squad_tree, SQUAD_COLUMNS)
	refresh()


func refresh() -> void:
	var club := GameState.player_club
	var hired : bool = club.upgrades.get("trainer", 0) > 0
	locked_message.visible = not hired
	hbox.visible = hired
	if not hired:
		return

	_populate_squad_tree()

	if _selected_player == null or not club.players.has(_selected_player):
		var first := squad_tree.get_root().get_first_child() if squad_tree.get_root() else null
		_selected_player = first.get_metadata(COL_NAME) if first else null

	_update_player_card()


func _populate_squad_tree() -> void:
	squad_tree.clear()
	var root := squad_tree.create_item()
	var selected_item : TreeItem = null

	for p : PlayerResource in GameState.player_club.players:
		var item := squad_tree.create_item(root)
		item.set_text(COL_NAME, p.full_name)
		item.set_text(COL_ROLE, Positions.label(p.role))
		item.set_text(COL_OVR,  str(p.overall()))
		item.set_metadata(COL_NAME, p)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_custom_color(COL_NAME, qcolor)
		item.set_custom_color(COL_OVR,  qcolor)
		TreeStyle.align_row(item, SQUAD_COLUMNS)
		if p == _selected_player:
			selected_item = item

	if selected_item:
		squad_tree.set_selected(selected_item, COL_NAME)


func _on_squad_tree_item_selected() -> void:
	var item := squad_tree.get_selected()
	if item == null:
		return
	_selected_player = item.get_metadata(COL_NAME)
	_update_player_card()


func _update_player_card() -> void:
	if _selected_player == null:
		return
	var club := GameState.player_club
	player_card.setup(_selected_player, club.team_key)

	var max_sessions := _max_sessions(club)
	var used : int = _selected_player.training_sessions_used
	var has_free_session := used < max_sessions
	var is_special := _selected_player.special_type != ""

	sessions_label.text = tr("Sesiones usadas: %d / %d") % [used, max_sessions]

	for stat in STAT_LABELS:
		var btn : Button = _stat_buttons[stat]
		var cost := _training_cost(_selected_player)

		if is_special:
			btn.text = tr("%s — n/d") % STAT_LABELS[stat]
			btn.disabled = true
		elif not has_free_session:
			btn.text = tr("%s — sin sesiones") % STAT_LABELS[stat]
			btn.disabled = true
		elif club.budget < cost:
			btn.text = tr("Entrenar %s (+%d%%) — $%s") % [STAT_LABELS[stat], SESSION_BOOST_PCT, MoneyFormat.format(cost)]
			btn.disabled = true
		else:
			btn.text = tr("Entrenar %s (+%d%%) — $%s") % [STAT_LABELS[stat], SESSION_BOOST_PCT, MoneyFormat.format(cost)]
			btn.disabled = false


func _max_sessions(club: ClubResource) -> int:
	var trainer_lvl : int = club.upgrades.get("trainer", 0)
	return StaffData.STAFF["trainer"]["levels"][trainer_lvl - 1]["max_sessions"] if trainer_lvl > 0 else 0


func _training_cost(p: PlayerResource) -> int:
	return 500 * (p.quality + 1)


func _on_train_pressed(stat: String) -> void:
	if _selected_player == null:
		return
	if _selected_player.special_type != "":
		return
	var club := GameState.player_club
	if club.upgrades.get("trainer", 0) <= 0:
		return
	if _selected_player.training_sessions_used >= _max_sessions(club):
		return
	var cost := _training_cost(_selected_player)
	if club.budget < cost:
		return

	club.budget -= cost
	_selected_player.training_sessions_used += 1
	_selected_player.add_permanent_modifier(
		"training_%s" % stat, "Centro de Entrenamiento", stat, SESSION_BOOST_PCT)
	GameState.budget_changed.emit()
	GameState.save_upgrades()
	GameState.save_career()
	refresh()
