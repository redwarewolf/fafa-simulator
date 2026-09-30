extends Control

## One Finances screen, like FM's, in place of the separate Gastos / Ingresos
## sub-tabs: the budget with its day-over-day change and trend chart on top,
## yesterday's actual ledger next to it, then the existing income cards
## (earnings_panel) and wage/staff breakdown (costs_panel) below.

@onready var budget_label : Label         = $VBox/OverviewPanel/HBox/Summary/Budget
@onready var delta_label  : Label         = $VBox/OverviewPanel/HBox/Summary/Delta
@onready var ledger       : VBoxContainer = $VBox/OverviewPanel/HBox/Ledger
@onready var debt_box     : VBoxContainer = $VBox/OverviewPanel/HBox/Debt
@onready var chart        : Control       = $VBox/OverviewPanel/HBox/Chart
@onready var earnings     : Control       = $VBox/EarningsFrame/EarningsPanel
@onready var costs        : Control       = $VBox/CostsPanel

func _ready() -> void:
	delta_label.tooltip_text = tr("Cambio desde ayer")
	refresh()

func refresh() -> void:
	var club := GameState.player_club
	if club == null:
		return
	budget_label.text = MoneyFormat.dollars(club.budget)
	budget_label.add_theme_color_override("font_color", HubPalette.LOSS if club.budget < 0 else Color.WHITE)

	if GameState.budget_history.is_empty():
		delta_label.text = ""
	else:
		var delta : int = club.budget - int(GameState.budget_history.back())
		delta_label.text = tr("%s$%s desde ayer") % ["+" if delta >= 0 else "-", MoneyFormat.format(absi(delta))]
		delta_label.add_theme_color_override("font_color", HubPalette.WIN if delta >= 0 else HubPalette.LOSS)

	var values : Array = GameState.budget_history.duplicate()
	values.append(club.budget)
	chart.set_values(values)

	_build_ledger()
	earnings.refresh()
	costs.refresh()

## The latest weekly payday (GameState.last_payday_ledger) and what's left
## of Tapir's loan. Match-day gate money isn't in the ledger; the post-match
## summary and the Inbox cover it.
func _build_ledger() -> void:
	for child in ledger.get_children():
		ledger.remove_child(child)
		child.queue_free()
	var week := GameState.last_payday_ledger
	var days := GameState.days_until_payday()
	_ledger_line(tr("ÚLTIMO PAGO SEMANAL"), "", HubPalette.MUTED)
	for row in [["merchandise_revenue", "Merchandising"], ["food_revenue", "Comida y Bebida"],
			["sponsor_revenue", "Sponsor"], ["tv_revenue", "Derechos de TV"]]:
		_ledger_line(tr(row[1]), "+$%s" % MoneyFormat.format(week.get(row[0], 0)), HubPalette.WIN)
	for row in [["wage_cost", "Sueldos del plantel"], ["staff_upkeep_cost", "Personal contratado"],
			["debt_payment", "Cuota de la deuda"], ["barra_cost", "La barra"], ["afa_fine", "Multas de la AFA"]]:
		_ledger_line(tr(row[1]), "-$%s" % MoneyFormat.format(week.get(row[0], 0)), HubPalette.LOSS)
	_ledger_line(tr("Próximo pago: mañana") if days == 1 else tr("Próximo pago en %d días") % days, "", HubPalette.MUTED)
	_build_debt()

func _build_debt() -> void:
	for child in debt_box.get_children():
		debt_box.remove_child(child)
		child.queue_free()
	var owed := GameState.debt + GameState.debt_arrears
	_ledger_line(tr("DEUDA CON GRANDI TAPIR"), "", HubPalette.MUTED, debt_box)
	if owed <= 0:
		_ledger_line(tr("Saldada. No le debemos nada."), "", HubPalette.WIN, debt_box)
		return
	_ledger_line(tr("Resta pagar"), "$%s" % MoneyFormat.format(owed), Color.WHITE, debt_box)
	_ledger_line(tr("Cuota semanal"), "$%s" % MoneyFormat.format(mini(GameState.debt, ClubDebt.WEEKLY_PAYMENT)), Color.WHITE, debt_box)
	if GameState.debt_arrears > 0:
		_ledger_line(tr("Atrasado (con recargo)"), "$%s" % MoneyFormat.format(GameState.debt_arrears), HubPalette.LOSS, debt_box)
	var pay := Button.new()
	pay.text = tr("SALDAR TODO  $%s") % MoneyFormat.format(owed)
	pay.disabled = GameState.player_club.budget < owed
	pay.tooltip_text = tr("Pagarle a Tapir todo lo que queda de una vez")
	pay.pressed.connect(_on_pay_off_pressed)
	debt_box.add_child(pay)

func _on_pay_off_pressed() -> void:
	if not GameState.pay_off_debt():
		return
	AudioManager.play_purchase()
	refresh()
	get_tree().call_group("hub", "play_tapir_lines")

func _ledger_line(left: String, right: String, color: Color, box: VBoxContainer = null) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = left
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color", HubPalette.MUTED if right != "" else color)
	row.add_child(l)
	if right != "":
		var r := Label.new()
		r.text = right
		r.add_theme_color_override("font_color", color)
		row.add_child(r)
	(box if box != null else ledger).add_child(row)
