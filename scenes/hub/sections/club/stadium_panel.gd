extends Control

const UPGRADES := {
	"building": {
		"label": "Edificio",
		"levels": [
			{"cost": 100_000,   "requires": {}},
			{"cost": 1_000_000, "requires": {}},
			{"cost": 5_000_000, "requires": {}},
		],
	},
	"food_sales": {
		"label": "Venta de Comida",
		"levels": [
			{"cost":  10_000, "requires": {}},
			{"cost": 100_000, "requires": {"building": 1}},
			{"cost": 500_000, "requires": {"building": 1}},
		],
	},
	"merchandise_sales": {
		"label": "Venta de Merchandising",
		"levels": [
			{"cost":  10_000, "requires": {}},
			{"cost": 100_000, "requires": {"building": 1}},
			{"cost": 500_000, "requires": {"building": 1}},
		],
	},
	"tribune": {
		"label": "Tribuna",
		"levels": [
			{"cost":  10_000, "requires": {}},
			{"cost":  30_000, "requires": {}},
			{"cost": 100_000, "requires": {"building": 1}},
		],
	},
}

## Unfilled level pip.
const PIP_EMPTY := Color(0.10, 0.16, 0.21, 1.0)

## Upgrade card backing, so each card reads as a block instead of loose labels
## floating in the wide bottom panel.
const CARD_BG     := Color(0.05, 0.13, 0.17, 1.0)
const CARD_BORDER := Color(0.0, 0.0, 0.0, 0.45)

@onready var upgrade_row : HBoxContainer = $VBox/ActionsPanel/ActionsLayout/UpgradeRow

var _capacity_label : Label = null

# Nodes inside the SubViewports — resolved after _ready
var _food_stand   : AnimatedSprite2D = null
var _mantero      : AnimatedSprite2D = null
var _exp_middle   : Sprite2D         = null
var _exp_right    : Sprite2D         = null
var _talent_scout : AnimatedSprite2D = null
var _trainer      : AnimatedSprite2D = null

var _card_buttons : Dictionary = {}
var _card_pips    : Dictionary = {}
var _card_levels  : Dictionary = {}


func _ready() -> void:
	# Grab expansion nodes from inside the SubViewports
	var club_root    := $VBox/ArtRow/ClubAspect/ClubFrame/ClubViewportContainer/ClubViewport/Club
	var tribune_root := $VBox/ArtRow/TribuneAspect/TribuneFrame/TribuneViewportContainer/TribuneViewport/Tribune
	_food_stand   = club_root.get_node("FoodStand")
	_mantero      = club_root.get_node("Mantero")
	_exp_middle   = tribune_root.get_node("ExpansionMiddle")
	_exp_right    = tribune_root.get_node("ExpansionRight")
	_talent_scout = club_root.get_node("TalentScout")
	_trainer      = tribune_root.get_node("Trainer")
	_build_cards()
	refresh()


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	return sb


func _build_cards() -> void:
	for key in UPGRADES:
		var data : Dictionary = UPGRADES[key]

		# One card per upgrade, side by side: the old single narrow column was
		# sized for the 640×480 viewport and left the wide panel mostly empty.
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _card_style())
		upgrade_row.add_child(panel)

		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override("separation", 8)
		panel.add_child(card)

		# Header row: name on left, capacity on right (tribune only)
		var header_row := HBoxContainer.new()
		card.add_child(header_row)

		var name_label := Label.new()
		name_label.text = tr(data["label"]).to_upper()
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_row.add_child(name_label)

		if key == "tribune":
			_capacity_label = Label.new()
			_capacity_label.size_flags_horizontal = Control.SIZE_SHRINK_END
			header_row.add_child(_capacity_label)

		card.add_child(HSeparator.new())

		var level_label := Label.new()
		level_label.add_theme_color_override("font_color", HubPalette.MUTED)
		card.add_child(level_label)
		_card_levels[key] = level_label

		# One pip per level — reads the progress at a glance and gives the card
		# something to fill the height with.
		var pips_row := HBoxContainer.new()
		pips_row.add_theme_constant_override("separation", 4)
		card.add_child(pips_row)
		var pips : Array[ColorRect] = []
		for _i in data["levels"].size():
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(0, 14)
			pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pips_row.add_child(pip)
			pips.append(pip)
		_card_pips[key] = pips

		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_buy_pressed.bind(key))
		card.add_child(btn)
		_card_buttons[key] = btn

## Public so club_section.gd's duck-typed refresh contract (has_method("refresh"))
## picks this panel back up whenever the Stadium tab is reshown.
func refresh() -> void:
	var club := GameState.player_club

	# Capacity
	var tribune_lvl : int = club.upgrades.get("tribune", 0)
	if _capacity_label:
		_capacity_label.text = tr("Capacidad: %d") % club.get_stadium_capacity()

	# Visibility of expansion assets
	if _food_stand:
		_food_stand.visible = club.upgrades.get("food_sales", 0) >= 1
	if _mantero:
		_mantero.visible = club.upgrades.get("merchandise_sales", 0) >= 1
	if _exp_middle:
		_exp_middle.visible = tribune_lvl >= 1
	if _exp_right:
		_exp_right.visible = tribune_lvl >= 2
	if _talent_scout:
		_talent_scout.visible = club.upgrades.get("scout", 0) >= 1
	if _trainer:
		_trainer.visible = club.upgrades.get("trainer", 0) >= 1

	# Upgrade cards
	for key in UPGRADES:
		var data      : Dictionary = UPGRADES[key]
		var max_lvl   : int        = data["levels"].size()
		var cur_lvl   : int        = club.upgrades.get(key, 0)
		var lvl_label : Label      = _card_levels[key]
		var btn       : Button     = _card_buttons[key]

		lvl_label.text = tr("Nivel %d / %d") % [cur_lvl, max_lvl]

		var pips : Array = _card_pips[key]
		for i in pips.size():
			pips[i].color = HubPalette.HIGHLIGHT if i < cur_lvl else PIP_EMPTY

		if cur_lvl >= max_lvl:
			btn.text     = "MÁX"
			btn.disabled = true
			continue

		var next_data : Dictionary = data["levels"][cur_lvl]
		var cost      : int        = next_data["cost"]
		var reqs      : Dictionary = next_data["requires"]

		var req_label := ""
		var reqs_met  := true
		for req_key in reqs:
			var need : int = reqs[req_key]
			var have : int = club.upgrades.get(req_key, 0)
			if have < need:
				reqs_met  = false
				req_label = tr("Necesita %s Nvl %d") % [tr(UPGRADES[req_key]["label"]), need]
				break

		if not reqs_met:
			btn.text     = req_label
			btn.disabled = true
		elif club.budget < cost:
			btn.text     = tr("Nvl %d  $%s") % [cur_lvl + 1, MoneyFormat.format(cost)]
			btn.disabled = true
		else:
			btn.text     = tr("→ Nvl %d  $%s") % [cur_lvl + 1, MoneyFormat.format(cost)]
			btn.disabled = false


func _on_buy_pressed(key: String) -> void:
	var club    := GameState.player_club
	var cur_lvl : int = club.upgrades.get(key, 0)
	var data    : Dictionary = UPGRADES[key]

	if cur_lvl >= data["levels"].size():
		return

	var cost : int = data["levels"][cur_lvl]["cost"]
	if club.budget < cost:
		return

	club.budget        -= cost
	club.upgrades[key]  = cur_lvl + 1
	GameState.budget_changed.emit()
	GameState.save_upgrades()
	refresh()
