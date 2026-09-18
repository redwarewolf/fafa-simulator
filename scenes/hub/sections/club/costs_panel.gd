extends Control

## Read-only breakdown of everything deducted from the budget on every "Next
## Date" press — squad wages (PlayerWage, per player) plus hired-staff upkeep
## (StaffData). Mirrors the actual deduction in GameState._tick_costs().

const COL_NAME := 0
const COL_ROLE := 1
const COL_OVR  := 2
const COL_WAGE := 3

const WAGE_COLUMNS : Array = [
	{"title": "Nombre", "expand": true,  "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"title": "Pos",  "expand": false, "min_width": 46, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "OVR",  "expand": false, "min_width": 44, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"title": "Sueldo", "expand": false, "min_width": 90, "align": HORIZONTAL_ALIGNMENT_RIGHT},
]

@onready var wages_tree       : Tree          = $HBox/WagesPanel/VBox/WagesTree
@onready var staff_list       : VBoxContainer = $HBox/SummaryPanel/VBox/StaffList
@onready var wage_total_label : Label         = $HBox/SummaryPanel/VBox/WageTotalLabel
@onready var total_label      : Label         = $HBox/SummaryPanel/VBox/TotalLabel


func _ready() -> void:
	TreeStyle.setup_columns(wages_tree, WAGE_COLUMNS)
	refresh()


func refresh() -> void:
	var club := GameState.player_club
	_populate_wages_tree(club)
	_populate_staff_list(club)

	var wage_total : int = club.get_wage_cost()
	var staff_total : int = club.get_staff_upkeep_cost()
	wage_total_label.text = tr("Sueldos del plantel: $%s") % MoneyFormat.format(wage_total)
	total_label.text = tr("TOTAL POR FECHA: $%s") % MoneyFormat.format(wage_total + staff_total)


func _populate_wages_tree(club: ClubResource) -> void:
	wages_tree.clear()
	var root := wages_tree.create_item()

	var squad := club.players.duplicate()
	squad.sort_custom(func(a: PlayerResource, b: PlayerResource) -> bool:
		return PlayerWage.estimate(a) > PlayerWage.estimate(b))

	for p : PlayerResource in squad:
		var item := wages_tree.create_item(root)
		var qcolor : Color = QualityStyle.COLORS[p.quality]
		item.set_text(COL_NAME, p.full_name)
		item.set_text(COL_ROLE, Positions.label(p.role))
		item.set_text(COL_OVR,  str(p.overall()))
		item.set_text(COL_WAGE, "$%s" % MoneyFormat.format(PlayerWage.estimate(p)))
		for col in [COL_NAME, COL_ROLE, COL_OVR, COL_WAGE]:
			item.set_custom_color(col, qcolor)
		TreeStyle.align_row(item, WAGE_COLUMNS)


func _populate_staff_list(club: ClubResource) -> void:
	for child in staff_list.get_children():
		child.queue_free()

	var any_hired := false
	for key in StaffData.STAFF:
		var lvl : int = club.upgrades.get(key, 0)
		if lvl <= 0:
			continue
		any_hired = true
		var data : Dictionary = StaffData.STAFF[key]
		var cost : int = data["levels"][lvl - 1]["monthly"]

		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = tr("%s (Nivel %d)") % [tr(data["label"]), lvl]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var cost_label := Label.new()
		cost_label.text = "$%s" % MoneyFormat.format(cost)
		row.add_child(cost_label)
		staff_list.add_child(row)

	if not any_hired:
		var label := Label.new()
		label.text = "Sin personal contratado"
		label.add_theme_color_override("font_color", HubPalette.MUTED)
		staff_list.add_child(label)
