extends Control

## Hire, upgrade or let go the club staff. Same card-per-item pattern
## as stadium_panel.gd's building upgrades, reading tiers from StaffData
## instead of a local const since ClubResource.get_staff_upkeep_cost() also
## needs that table.

const PIP_EMPTY := Color(0.10, 0.16, 0.21, 1.0)
const CARD_BG     := Color(0.05, 0.13, 0.17, 1.0)
const CARD_BORDER := Color(0.0, 0.0, 0.0, 0.45)

@onready var card_row : HBoxContainer = $VBox/CardRow

var _card_buttons : Dictionary = {}
var _card_dismiss : Dictionary = {}
var _card_pips    : Dictionary = {}
var _card_levels  : Dictionary = {}
var _card_upkeep  : Dictionary = {}
## Only populated for the "academy" card — shows current prospects vs. cap,
## since that's the only upgrade whose "level" also gates a live pool size.
var _card_pool    : Dictionary = {}
var _card_effects : Dictionary = {}

## What each hire unlocks — the cards used to show only a name and a price.
const STAFF_BLURBS := {
	"trainer": "Desbloquea Entrenamiento: sesiones que suben un stat de un jugador +6% para siempre.",
	"scout":   "Desbloquea Contrataciones: cada mes el ojeador te trae candidatos para fichar.",
	"academy": "Desbloquea Juveniles: pibes del barrio que se suman al club y crecen en la academia.",
	"butcher": "Desbloquea el Laboratorio: sacrificá jugadores y armá uno nuevo con sus órganos.",
}


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

		var blurb := Label.new()
		blurb.text = tr(STAFF_BLURBS.get(key, ""))
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(blurb)

		var level_label := Label.new()
		level_label.add_theme_color_override("font_color", HubPalette.MUTED)
		card.add_child(level_label)
		_card_levels[key] = level_label

		var upkeep_label := Label.new()
		upkeep_label.add_theme_color_override("font_color", HubPalette.MUTED)
		card.add_child(upkeep_label)
		_card_upkeep[key] = upkeep_label

		if key == "academy":
			var pool_label := Label.new()
			pool_label.add_theme_color_override("font_color", HubPalette.MUTED)
			card.add_child(pool_label)
			_card_pool[key] = pool_label

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

		var effect_label := Label.new()
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_label.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
		card.add_child(effect_label)
		_card_effects[key] = effect_label

		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_buy_pressed.bind(key))
		card.add_child(btn)
		_card_buttons[key] = btn

		var dismiss := Button.new()
		dismiss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dismiss.theme_type_variation = &"GhostButton"
		dismiss.pressed.connect(_on_dismiss_pressed.bind(key))
		card.add_child(dismiss)
		_card_dismiss[key] = dismiss


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
			var weekly : int = data["levels"][cur_lvl - 1]["weekly"]
			upkeep.text = tr("$%s / semana") % MoneyFormat.format(weekly)
		else:
			upkeep.text = ""

		var dismiss : Button = _card_dismiss[key]
		dismiss.visible = cur_lvl > 0
		if cur_lvl > 0:
			dismiss.text = tr("DESPEDIR") if cur_lvl == 1 else tr("BAJAR A NIVEL %d") % (cur_lvl - 1)

		if key == "academy" and _card_pool.has(key):
			_card_pool[key].text = (tr("Juveniles: %d / %d") % [club.youth_players.size(), GameState.get_youth_academy_cap()]) if cur_lvl > 0 else ""

		var pips : Array = _card_pips[key]
		for i in pips.size():
			pips[i].color = HubPalette.HIGHLIGHT if i < cur_lvl else PIP_EMPTY
		_card_effects[key].text = _effect_text(key, data, cur_lvl)

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


## Current → next level in numbers, plus the upkeep the next level costs.
func _effect_text(key: String, data: Dictionary, cur_lvl: int) -> String:
	var levels : Array = data["levels"]
	if cur_lvl >= levels.size():
		return tr("Nivel máximo")
	var stat_key := ""
	var label := ""
	match key:
		"trainer":
			stat_key = "max_sessions"
			label = "Sesiones por jugador"
		"scout":
			stat_key = "pool_size"
			label = "Candidatos por mes"
		"academy":
			stat_key = "pool_size"
			label = "Cupo de juveniles"
	var next : Dictionary = levels[cur_lvl]
	var upkeep := tr("Sueldo: $%s / semana") % MoneyFormat.format(next["weekly"])
	if stat_key == "":
		return upkeep
	var now_value : int = levels[cur_lvl - 1][stat_key] if cur_lvl > 0 else 0
	return "%s: %d → %d\n%s" % [tr(label), now_value, next[stat_key], upkeep]


func _on_buy_pressed(key: String) -> void:
	# A coroutine — the academy's first-hire branch awaits its guaranteed
	# sign-up event before this returns. Godot handles a signal-connected
	# coroutine transparently, no change needed at the connection site.
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
	AudioManager.play_purchase()
	GameState.save_upgrades()

	if key == "scout" and was_unhired:
		GameState.refresh_scout_pool()
		GameState.save_staff()
	elif key == "academy" and was_unhired:
		await YouthSignupFlow.run_first_signup(club)

	_populate()


## Lets a hire go one level, after a confirmation that spells out the
## severance (StaffData.DISMISS_SEVERANCE_WEEKS of their weekly upkeep) and
## what the club loses. Nothing of the original hiring price comes back.
func _on_dismiss_pressed(key: String) -> void:
	var club := GameState.player_club
	var cur_lvl : int = club.upgrades.get(key, 0)
	if cur_lvl <= 0:
		return
	var data : Dictionary = StaffData.STAFF[key]
	var severance : int = data["levels"][cur_lvl - 1]["weekly"] * StaffData.DISMISS_SEVERANCE_WEEKS
	var saves : int = data["levels"][cur_lvl - 1]["weekly"] - (data["levels"][cur_lvl - 2]["weekly"] if cur_lvl > 1 else 0)
	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Despedir personal")
	dialog.dialog_text = tr("%s baja al nivel %d.\n\nIndemnización: $%s (%d semanas de sueldo).\nAhorro: $%s por semana.\nPara volver a subirlo hay que pagar el precio completo.") % [
		tr(data["label"]), cur_lvl - 1, MoneyFormat.format(severance), StaffData.DISMISS_SEVERANCE_WEEKS, MoneyFormat.format(saves)]
	dialog.ok_button_text = tr("Despedir")
	dialog.cancel_button_text = tr("Cancelar")
	dialog.confirmed.connect(func():
		_dismiss(key, severance)
		dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()


func _dismiss(key: String, severance: int) -> void:
	var club := GameState.player_club
	var cur_lvl : int = club.upgrades.get(key, 0)
	if cur_lvl <= 0:
		return
	club.budget -= severance
	club.upgrades[key] = cur_lvl - 1
	GameState.budget_changed.emit()
	AudioManager.play_purchase()
	GameState.post_news("Despido: %s" % tr(StaffData.STAFF[key]["label"]),
		"Bajó al nivel %d. Pagamos $%s de indemnización." % [cur_lvl - 1, MoneyFormat.format(severance)], "info")
	GameState.save_upgrades()
	GameState.save_staff()
	_populate()
