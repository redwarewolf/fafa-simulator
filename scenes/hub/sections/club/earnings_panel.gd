extends Control

## Read-only breakdown of everything that can add to the budget — passive
## upgrade income (merchandise/food, rolled every "Next Date") and matchday
## gate revenue (rolled only on home fixtures — see SeasonManager.
## report_player_match_result()). Mirrors the actual rolls in
## GameState._tick_passive_income() / FanEconomy.

const CARD_BG     := Color(0.05, 0.13, 0.17, 1.0)
const CARD_BORDER := Color(0.0, 0.0, 0.0, 0.45)

@onready var card_row   : HBoxContainer = $VBox/CardRow
@onready var fans_label : Label         = $VBox/FansLabel


func _ready() -> void:
	fans_label.add_theme_color_override("font_color", HubPalette.MUTED)
	refresh()


func refresh() -> void:
	for child in card_row.get_children():
		child.queue_free()

	var club := GameState.player_club
	fans_label.text = tr("%s hinchas  ·  Capacidad del estadio %d") % [MoneyFormat.format(club.fans), club.get_stadium_capacity()]

	_ticket_card(club)
	_upgrade_income_card(club, "merchandise_sales", "Venta de Merchandising",
		FanEconomy.MERCH_RATE_MIN, FanEconomy.MERCH_RATE_MAX, FanEconomy.MERCH_PRICE_BY_LEVEL)
	_upgrade_income_card(club, "food_sales", "Venta de Comida",
		FanEconomy.FOOD_RATE_MIN, FanEconomy.FOOD_RATE_MAX, FanEconomy.FOOD_PRICE_BY_LEVEL)


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.border_color = CARD_BORDER
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	return sb


## Creates a card panel under card_row and returns its body container so
## callers can append rows to it.
func _new_card(title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _card_style())
	card_row.add_child(panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	panel.add_child(body)

	var name_label := Label.new()
	name_label.text = tr(title).to_upper()
	body.add_child(name_label)
	body.add_child(HSeparator.new())
	return body


func _add_row(body: VBoxContainer, text: String, muted: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	if muted:
		label.add_theme_color_override("font_color", HubPalette.MUTED)
	body.add_child(label)


func _ticket_card(club: ClubResource) -> void:
	var body := _new_card("Venta de Entradas")
	var price : int = FanEconomy.TICKET_PRICE_PER_DIVISION.get(club.division, FanEconomy.TICKET_PRICE_PER_DIVISION["E"])
	_add_row(body, tr("Precio de entrada: $%s (División %s)") % [MoneyFormat.format(price), club.division])

	var capacity := club.get_stadium_capacity()
	var lo_att := mini(int(round(club.fans * FanEconomy.ATTENDANCE_RATE_MIN)), capacity)
	var hi_att := mini(int(round(club.fans * FanEconomy.ATTENDANCE_RATE_MAX)), capacity)
	_add_row(body, tr("Asistencia esperada: %d – %d") % [lo_att, hi_att])
	_add_row(body, tr("Ingreso estimado: $%s – $%s") % [MoneyFormat.format(lo_att * price), MoneyFormat.format(hi_att * price)])
	_add_row(body, "Solo en tus partidos de local (liga o amistoso).", true)


func _upgrade_income_card(club: ClubResource, key: String, label: String,
		rate_min: float, rate_max: float, price_by_level: Dictionary) -> void:
	var body := _new_card(label)
	var lvl : int = club.upgrades.get(key, 0)
	if lvl <= 0:
		_add_row(body, "Todavía no está construido.", true)
		return

	var price : int = price_by_level.get(lvl, price_by_level[1])
	_add_row(body, tr("Nivel %d  ·  $%s / unidad") % [lvl, price])
	var lo := int(round(club.fans * rate_min))
	var hi := int(round(club.fans * rate_max))
	_add_row(body, tr("Compradores esperados: %d – %d") % [lo, hi])
	_add_row(body, tr("Ingreso estimado por fecha: $%s – $%s") % [MoneyFormat.format(lo * price), MoneyFormat.format(hi * price)])
