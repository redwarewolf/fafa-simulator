extends Control

## Hire/upgrade the Club Trainer and Talent Scout. Same card-per-item pattern
## as stadium_panel.gd's building upgrades, reading tiers from StaffData
## instead of a local const since ClubResource.get_staff_upkeep_cost() also
## needs that table.

const PIP_EMPTY := Color(0.10, 0.16, 0.21, 1.0)
const CARD_BG     := Color(0.05, 0.13, 0.17, 1.0)
const CARD_BORDER := Color(0.0, 0.0, 0.0, 0.45)

@onready var card_row : HBoxContainer = $VBox/CardRow

var _card_buttons : Dictionary = {}
var _card_pips    : Dictionary = {}
var _card_levels  : Dictionary = {}
var _card_upkeep  : Dictionary = {}


func _ready() -> void:
	_build_cards()
	refresh()


func refresh() -> void:
	_populate()


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	return sb


func _build_cards() -> void:
	for key in StaffData.STAFF:
		var data : Dictionary = StaffData.STAFF[key]

		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", _card_style())
		card_row.add_child(panel)

		var card := VBoxContainer.new()
		card.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_theme_constant_override("separation", 8)
		panel.add_child(card)

		var name_label := Label.new()
		name_label.text = tr(data["label"]).to_upper()
		card.add_child(name_label)

		card.add_child(HSeparator.new())

		var level_label := Label.new()
		level_label.add_theme_color_override("font_color", HubPalette.MUTED)
		card.add_child(level_label)
		_card_levels[key] = level_label

		var upkeep_label := Label.new()
		upkeep_label.add_theme_color_override("font_color", HubPalette.MUTED)
		card.add_child(upkeep_label)
		_card_upkeep[key] = upkeep_label

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


func _populate() -> void:
	var club := GameState.player_club

	for key in StaffData.STAFF:
		var data      : Dictionary = StaffData.STAFF[key]
		var max_lvl   : int        = data["levels"].size()
		var cur_lvl   : int        = club.upgrades.get(key, 0)
		var lvl_label : Label      = _card_levels[key]
		var upkeep    : Label      = _card_upkeep[key]
		var btn       : Button     = _card_buttons[key]

		lvl_label.text = (tr("Sin contratar") if cur_lvl == 0 else tr("Nivel %d / %d") % [cur_lvl, max_lvl])
		if cur_lvl > 0:
			var monthly : int = data["levels"][cur_lvl - 1]["monthly"]
			upkeep.text = tr("$%s / fecha") % MoneyFormat.format(monthly)
		else:
			upkeep.text = ""

		var pips : Array = _card_pips[key]
		for i in pips.size():
			pips[i].color = HubPalette.HIGHLIGHT if i < cur_lvl else PIP_EMPTY

		if cur_lvl >= max_lvl:
			btn.text     = "MÁX"
			btn.disabled = true
			continue

		var next_data : Dictionary = data["levels"][cur_lvl]
		var cost      : int        = next_data["cost"]
		var verb      := tr("CONTRATAR") if cur_lvl == 0 else tr("MEJORAR — Nvl %d") % (cur_lvl + 1)

		if club.budget < cost:
			btn.text     = "%s  $%s" % [verb, MoneyFormat.format(cost)]
			btn.disabled = true
		else:
			btn.text     = "%s  $%s" % [verb, MoneyFormat.format(cost)]
			btn.disabled = false


func _on_buy_pressed(key: String) -> void:
	var club    := GameState.player_club
	var cur_lvl : int = club.upgrades.get(key, 0)
	var data    : Dictionary = StaffData.STAFF[key]

	if cur_lvl >= data["levels"].size():
		return

	var cost : int = data["levels"][cur_lvl]["cost"]
	if club.budget < cost:
		return

	var was_unhired := cur_lvl == 0
	club.budget        -= cost
	club.upgrades[key]  = cur_lvl + 1
	GameState.budget_changed.emit()
	GameState.save_upgrades()

	if key == "scout" and was_unhired:
		GameState.refresh_scout_pool()
		GameState.save_staff()
	elif key == "academy" and was_unhired:
		GameState.refresh_youth_pool()

	_populate()
