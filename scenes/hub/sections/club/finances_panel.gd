extends Control

## One Finances screen, like FM's, in place of the separate Gastos / Ingresos
## sub-tabs: the budget with its day-over-day change and trend chart on top,
## yesterday's actual ledger next to it, then the existing income cards
## (earnings_panel) and wage/staff breakdown (costs_panel) below.

@onready var budget_label : Label         = $VBox/OverviewPanel/HBox/Summary/Budget
@onready var delta_label  : Label         = $VBox/OverviewPanel/HBox/Summary/Delta
@onready var ledger       : VBoxContainer = $VBox/OverviewPanel/HBox/Summary/Ledger
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
	budget_label.text = "$%s" % MoneyFormat.format(club.budget)
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

## Yesterday's actual movements (GameState.last_day_ledger) — match-day gate
## money isn't in the ledger; the post-match summary and the Inbox cover it.
func _build_ledger() -> void:
	for child in ledger.get_children():
		ledger.remove_child(child)
		child.queue_free()
	var day := GameState.last_day_ledger
	_ledger_line(tr("ÚLTIMA FECHA"), "", HubPalette.MUTED)
	_ledger_line(tr("Merchandising"), "+$%s" % MoneyFormat.format(day.get("merchandise_revenue", 0)), HubPalette.WIN)
	_ledger_line(tr("Comida y Bebida"), "+$%s" % MoneyFormat.format(day.get("food_revenue", 0)), HubPalette.WIN)
	_ledger_line(tr("Sueldos del plantel"), "-$%s" % MoneyFormat.format(day.get("wage_cost", 0)), HubPalette.LOSS)
	_ledger_line(tr("Personal contratado"), "-$%s" % MoneyFormat.format(day.get("staff_upkeep_cost", 0)), HubPalette.LOSS)

func _ledger_line(left: String, right: String, color: Color) -> void:
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
	ledger.add_child(row)
