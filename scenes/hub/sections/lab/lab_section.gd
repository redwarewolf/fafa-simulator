extends Control

## Sacrifice squad players for their organs, then stitch harvested organs into
## a new "zombie" player. Locked until the "butcher" staff upgrade is hired —
## same lock pattern as youth_section.gd for the academy pool.
##
## Left half (Sacrificar): pick a squad player; the middle preview shows their
## card plus up to 2 stat checkboxes and the Sacrifice button — the rest of
## that player is lost. Right half (Ensamblar): socket harvested organs into
## up to 6 stat slots (unfilled slots default to 1) and build a new
## PlayerResource from the result — age comes out as the average donor age
## across all 6 slots, with unfilled slots counting as age 1 too.

const MAX_HARVEST_STATS := 2
const MIN_SQUAD_SIZE := 6  ## mirrors market_section.gd's sell-flow guard

const STAT_KEYS   := ["pac", "sho", "pas", "dri", "def", "phy"]
const STAT_LABELS := {"pac": "PAC", "sho": "SHO", "pas": "PAS", "dri": "DRI", "def": "DEF", "phy": "PHY"}

const SQUAD_COL_NAME    := 0
const SQUAD_COL_ROLE    := 1
const SQUAD_COL_AGE     := 2
const SQUAD_COL_QUALITY := 3

const SQUAD_COLUMNS : Array = [
	{"title": "Nombre",  "expand": true,  "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"title": "Pos",     "expand": false, "min_width": 46, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Edad",    "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Calidad", "expand": false, "min_width": 90, "align": HORIZONTAL_ALIGNMENT_CENTER},
]

const ORGAN_COL_STAT  := 0
const ORGAN_COL_VALUE := 1
const ORGAN_COL_DONOR := 2

const ORGAN_COLUMNS : Array = [
	{"title": "Stat",     "expand": false, "min_width": 50, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Valor",    "expand": false, "min_width": 50, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Donante",  "expand": true,  "align": HORIZONTAL_ALIGNMENT_LEFT},
]

const NO_ORGAN_ID := -1

@onready var locked_message : Label         = $LockedMessage
@onready var hbox           : HBoxContainer = $HBox

@onready var squad_tree      : Tree   = $HBox/SacrificePanel/VBox/SquadTree

@onready var preview_card : Control = $HBox/PreviewPanel/VBox/PlayerCard
@onready var stat_checks     : Dictionary = {
	"pac": $HBox/PreviewPanel/VBox/StatsGrid/PacCheck,
	"sho": $HBox/PreviewPanel/VBox/StatsGrid/ShoCheck,
	"pas": $HBox/PreviewPanel/VBox/StatsGrid/PasCheck,
	"dri": $HBox/PreviewPanel/VBox/StatsGrid/DriCheck,
	"def": $HBox/PreviewPanel/VBox/StatsGrid/DefCheck,
	"phy": $HBox/PreviewPanel/VBox/StatsGrid/PhyCheck,
}
@onready var sacrifice_button : Button = $HBox/PreviewPanel/VBox/SacrificeButton

@onready var organs_tree : Tree = $HBox/AssemblePanel/VBox/OrgansTree
@onready var slot_options : Dictionary = {
	"pac": $HBox/AssemblePanel/VBox/SlotsGrid/PacSlot,
	"sho": $HBox/AssemblePanel/VBox/SlotsGrid/ShoSlot,
	"pas": $HBox/AssemblePanel/VBox/SlotsGrid/PasSlot,
	"dri": $HBox/AssemblePanel/VBox/SlotsGrid/DriSlot,
	"def": $HBox/AssemblePanel/VBox/SlotsGrid/DefSlot,
	"phy": $HBox/AssemblePanel/VBox/SlotsGrid/PhySlot,
}
@onready var name_edit      : LineEdit   = $HBox/AssemblePanel/VBox/NameRow/NameEdit
@onready var role_option    : OptionButton = $HBox/AssemblePanel/VBox/RoleRow/RoleOption
@onready var assemble_button : Button    = $HBox/AssemblePanel/VBox/AssembleButton

var _selected_donor : PlayerResource = null


func _ready() -> void:
	TreeStyle.setup_columns(squad_tree, SQUAD_COLUMNS)
	TreeStyle.setup_columns(organs_tree, ORGAN_COLUMNS)
	organs_tree.hide_root = true

	for key in STAT_KEYS:
		(stat_checks[key] as CheckBox).toggled.connect(_on_stat_check_toggled.bind(key))

	for role in Positions.DATA.keys():
		role_option.add_item(Positions.label(role), role)

	for key in STAT_KEYS:
		(slot_options[key] as OptionButton).item_selected.connect(_on_slot_selected.bind(key))
	role_option.item_selected.connect(func(_index: int) -> void: _update_zombie_preview())
	name_edit.text_changed.connect(func(_text: String) -> void: _update_zombie_preview())

	refresh()


func refresh() -> void:
	var club := GameState.player_club
	var hired : bool = club.upgrades.get("butcher", 0) > 0
	locked_message.visible = not hired
	hbox.visible = hired
	if not hired:
		return

	_clear_donor_selection()
	_populate_squad_tree()
	_populate_organs_tree()
	_populate_slot_options()
	_update_zombie_preview()


func _populate_squad_tree() -> void:
	squad_tree.clear()
	var root := squad_tree.create_item()
	for p : PlayerResource in GameState.player_club.players:
		var item := squad_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_text(SQUAD_COL_NAME,    p.full_name)
		item.set_text(SQUAD_COL_ROLE,    Positions.label(p.role))
		item.set_text(SQUAD_COL_AGE,     str(p.age))
		item.set_text(SQUAD_COL_QUALITY, tr(QualityStyle.NAMES[p.quality]))
		TreeStyle.tint_row(item, qcolor)
		TreeStyle.align_row(item, SQUAD_COLUMNS)
		item.set_metadata(0, p)


func _populate_organs_tree() -> void:
	organs_tree.clear()
	var root := organs_tree.create_item()
	for organ : Dictionary in GameState.player_club.organs:
		var item := organs_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[int(organ["donor_quality"])]
		item.set_text(ORGAN_COL_STAT,  STAT_LABELS[organ["stat"]])
		item.set_text(ORGAN_COL_VALUE, str(organ["value"]))
		item.set_text(ORGAN_COL_DONOR, organ["donor_name"])
		TreeStyle.tint_row(item, qcolor)
		TreeStyle.align_row(item, ORGAN_COLUMNS)


## Rebuilds every slot's OptionButton from the current organ inventory,
## trying to keep whatever was previously socketed in that slot selected.
func _populate_slot_options() -> void:
	for key in STAT_KEYS:
		var opt := slot_options[key] as OptionButton
		var previous_id := _selected_organ_id(opt)
		opt.clear()
		opt.add_item(tr("— (carne podrida)"), NO_ORGAN_ID)
		var restore_index := 0
		for organ : Dictionary in GameState.player_club.organs:
			if organ["stat"] != key:
				continue
			var organ_id : int = organ["id"]
			var label := "%d  (%s)" % [int(organ["value"]), organ["donor_name"]]
			opt.add_item(label, organ_id)
			if organ_id == previous_id:
				restore_index = opt.item_count - 1
		opt.select(restore_index)


func _selected_organ_id(opt: OptionButton) -> int:
	if opt.item_count == 0:
		return NO_ORGAN_ID
	return opt.get_item_id(opt.selected)


func _on_squad_tree_item_selected() -> void:
	var item := squad_tree.get_selected()
	if item == null:
		return
	_selected_donor = item.get_metadata(0) as PlayerResource
	preview_card.setup(_selected_donor, GameState.player_club.team_key)
	for key in STAT_KEYS:
		(stat_checks[key] as CheckBox).button_pressed = false
	_update_sacrifice_button()


func _on_stat_check_toggled(_pressed: bool, _stat_key: String) -> void:
	var checked_count := 0
	for key in STAT_KEYS:
		if (stat_checks[key] as CheckBox).button_pressed:
			checked_count += 1
	for key in STAT_KEYS:
		var box := stat_checks[key] as CheckBox
		if not box.button_pressed:
			box.disabled = checked_count >= MAX_HARVEST_STATS
	_update_sacrifice_button()


func _update_sacrifice_button() -> void:
	var checked_count := 0
	for key in STAT_KEYS:
		if (stat_checks[key] as CheckBox).button_pressed:
			checked_count += 1
	var club := GameState.player_club
	if _selected_donor == null or checked_count == 0:
		sacrifice_button.disabled = true
		sacrifice_button.text = tr("ELEGÍ UN JUGADOR Y AL MENOS 1 STAT")
	elif club.players.size() <= MIN_SQUAD_SIZE:
		sacrifice_button.disabled = true
		sacrifice_button.text = tr("PLANTEL MUY CHICO")
	else:
		sacrifice_button.disabled = false
		sacrifice_button.text = tr("SACRIFICAR")


func _on_sacrifice_pressed() -> void:
	var club := GameState.player_club
	if _selected_donor == null or club.players.size() <= MIN_SQUAD_SIZE:
		return
	var chosen_stats : Array = []
	for key in STAT_KEYS:
		if (stat_checks[key] as CheckBox).button_pressed:
			chosen_stats.append(key)
	if chosen_stats.is_empty():
		return

	var organs := ZombieFactory.harvest(_selected_donor, chosen_stats)
	club.organs.append_array(organs)
	club.players.erase(_selected_donor)
	GameState.clear_player_from_tactics(_selected_donor)
	GameState.save_staff()
	refresh()


## Builds a throwaway PlayerResource from the current slot picks (without
## touching club.organs/players) so the middle panel shows what assembling
## right now would produce.
func _update_zombie_preview() -> void:
	var organs_by_stat := _current_organs_by_stat()
	var preview_name : String = name_edit.text if name_edit.text.strip_edges() != "" else tr("Zombie sin nombre")
	var role : Positions.Role = role_option.get_selected_id() as Positions.Role
	var preview := ZombieFactory.assemble(preview_name, role, organs_by_stat)
	preview_card.setup(preview, GameState.player_club.team_key)


func _current_organs_by_stat() -> Dictionary:
	var organs_by_stat := {}
	for key in STAT_KEYS:
		var opt := slot_options[key] as OptionButton
		var organ_id := _selected_organ_id(opt)
		if organ_id == NO_ORGAN_ID:
			continue
		for organ : Dictionary in GameState.player_club.organs:
			if int(organ["id"]) == organ_id:
				organs_by_stat[key] = organ
				break
	return organs_by_stat


func _on_slot_selected(_index: int, _stat_key: String) -> void:
	_update_zombie_preview()


func _on_assemble_pressed() -> void:
	var club := GameState.player_club
	var organs_by_stat := _current_organs_by_stat()
	var zombie_name : String = name_edit.text.strip_edges()
	if zombie_name == "":
		zombie_name = tr("Zombie sin nombre")
	var role : Positions.Role = role_option.get_selected_id() as Positions.Role

	var zombie := ZombieFactory.assemble(zombie_name, role, organs_by_stat)
	for key in organs_by_stat:
		var organ : Dictionary = organs_by_stat[key]
		for i in club.organs.size():
			if int(club.organs[i]["id"]) == int(organ["id"]):
				club.organs.remove_at(i)
				break
	club.players.append(zombie)
	name_edit.text = ""
	GameState.save_staff()
	refresh()


func _clear_donor_selection() -> void:
	_selected_donor = null
	preview_card.clear()
	for key in STAT_KEYS:
		var box := stat_checks[key] as CheckBox
		box.button_pressed = false
		box.disabled = false
	_update_sacrifice_button()
