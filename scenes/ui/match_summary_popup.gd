class_name MatchSummaryPopup
extends CanvasLayer

## Post-match popup shown after a played OR simulated player match — score,
## scorers, and (when [param data] carries "show_finance": true) the full
## revenue/cost breakdown for that date: gate revenue, merch/food passive
## income, squad wages, staff upkeep, and the net total. Styled like
## PauseMenu, reused by both world.gd (a played match's GAMEOVER) and hub.gd
## (a simulated one) instead of each building its own summary UI.

signal continue_pressed

@onready var title_label   : Label         = $PanelRoot/Margin/Main/TitleLabel
@onready var score_label   : Label         = $PanelRoot/Margin/Main/ScoreLabel
@onready var simulated_tag : Label         = %SimulatedTag
@onready var rows          : VBoxContainer = $PanelRoot/Margin/Main/Scroll/Rows
@onready var net_label     : Label         = $PanelRoot/Margin/Main/NetLabel

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

## [param data] keys: own_name, opp_name, own_score, opp_score, scorers
## (Array of {player, team, time_str}), simulated (bool), show_finance (bool —
## when false, only the score/scorers show, e.g. the Hub's dev Test Match with
## no season fixture behind it), fans_delta, fans_now, ticket_revenue,
## attendance, merch_revenue, food_revenue, wage_cost, staff_cost.
func show_result(data: Dictionary) -> void:
	_clear_rows()

	var own_score : int = data.get("own_score", 0)
	var opp_score : int = data.get("opp_score", 0)
	if own_score > opp_score:
		title_label.text = tr("¡GANASTE!")
		title_label.add_theme_color_override("font_color", HubPalette.WIN)
	elif own_score < opp_score:
		title_label.text = tr("PERDISTE")
		title_label.add_theme_color_override("font_color", HubPalette.LOSS)
	else:
		title_label.text = tr("EMPATE")
		title_label.add_theme_color_override("font_color", HubPalette.DRAW)
	score_label.text = "%s   %d - %d   %s" % [data.get("own_name", ""), own_score, opp_score, data.get("opp_name", "")]
	simulated_tag.visible = data.get("simulated", false)

	var scorers : Array = data.get("scorers", [])
	if not scorers.is_empty():
		_add_header(tr("GOLEADORES"))
		for s in scorers:
			_add_row("%s   %s (%s)" % [s["time_str"], s["player"], s["team"]], "")
		_add_separator()

	if data.has("position_after"):
		var before : int = data.get("position_before", 0)
		var after : int = data["position_after"]
		var moved := before - after
		var arrow := ""
		var color := HubPalette.MUTED
		if moved > 0:
			arrow = tr("  (sube %d)") % moved
			color = HubPalette.WIN
		elif moved < 0:
			arrow = tr("  (baja %d)") % -moved
			color = HubPalette.LOSS
		_add_header(tr("TABLA"))
		var row := Label.new()
		row.text = tr("Posición: #%d → #%d") % [before, after] + arrow
		row.add_theme_color_override("font_color", color)
		rows.add_child(row)
		_add_separator()

	var others : Array = data.get("other_results", [])
	if not others.is_empty():
		_add_header(tr("OTROS RESULTADOS DE LA FECHA"))
		for line in others:
			_add_row(line, "")
		_add_separator()

	var stats : Array = data.get("stats", [])
	if not stats.is_empty():
		_add_header(tr("ESTADÍSTICAS"))
		for row in stats:
			_add_stat_row(tr(row[0]), row[1], row[2])
		_add_separator()

	if data.get("show_finance", false):
		_build_finance_rows(data)

	visible = true
	get_tree().paused = true

func _build_finance_rows(data: Dictionary) -> void:
	_add_header(tr("INGRESOS"))
	var fans_delta : int = data.get("fans_delta", 0)
	_add_row(tr("Hinchas"), "%s%d  (%s)" % [
		"+" if fans_delta >= 0 else "", fans_delta, MoneyFormat.format(data.get("fans_now", 0))])

	var ticket_revenue : int = data.get("ticket_revenue", 0)
	if ticket_revenue > 0:
		_add_row(tr("Entradas (%s asistentes)") % MoneyFormat.format(data.get("attendance", 0)),
			"+$%s" % MoneyFormat.format(ticket_revenue))

	var merch_revenue : int = data.get("merch_revenue", 0)
	if merch_revenue > 0:
		_add_row(tr("Merchandising"), "+$%s" % MoneyFormat.format(merch_revenue))

	var food_revenue : int = data.get("food_revenue", 0)
	if food_revenue > 0:
		_add_row(tr("Comida y Bebida"), "+$%s" % MoneyFormat.format(food_revenue))

	_add_separator()
	_add_header(tr("GASTOS"))
	var wage_cost : int = data.get("wage_cost", 0)
	_add_row(tr("Sueldos del plantel"), "-$%s" % MoneyFormat.format(wage_cost))
	var staff_cost : int = data.get("staff_cost", 0)
	if staff_cost > 0:
		_add_row(tr("Personal contratado"), "-$%s" % MoneyFormat.format(staff_cost))

	var net := ticket_revenue + merch_revenue + food_revenue - wage_cost - staff_cost
	net_label.visible = true
	net_label.text = tr("NETO: %s$%s") % ["+" if net >= 0 else "-", MoneyFormat.format(abs(net))]
	net_label.add_theme_color_override("font_color", HubPalette.WIN if net >= 0 else HubPalette.LOSS)

func _add_header(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", HubPalette.MUTED)
	rows.add_child(label)

func _add_row(left: String, right: String) -> void:
	var row := HBoxContainer.new()
	var left_label := Label.new()
	left_label.text = left
	left_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(left_label)
	if right != "":
		var right_label := Label.new()
		right_label.text = right
		row.add_child(right_label)
	rows.add_child(row)

## Own value | stat name | opponent value, like a TV stats graphic.
func _add_stat_row(label: String, own: String, opp: String) -> void:
	var row := HBoxContainer.new()
	for spec in [[own, HORIZONTAL_ALIGNMENT_LEFT, Color.WHITE],
			[label, HORIZONTAL_ALIGNMENT_CENTER, HubPalette.MUTED],
			[opp, HORIZONTAL_ALIGNMENT_RIGHT, Color.WHITE]]:
		var l := Label.new()
		l.text = spec[0]
		l.horizontal_alignment = spec[1]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_color_override("font_color", spec[2])
		row.add_child(l)
	rows.add_child(row)

func _add_separator() -> void:
	rows.add_child(HSeparator.new())

func _clear_rows() -> void:
	net_label.visible = false
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()

func _on_continue_pressed() -> void:
	visible = false
	get_tree().paused = false
	continue_pressed.emit()
