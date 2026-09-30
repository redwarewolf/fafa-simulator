extends Control

## Club > La Barra: Barroni Flaquito, how the barra feels about you
## (relación, poder), and three tabs — see BarraBrava for the rules:
##   APORTES   what you give them every week (charged on payday)
##   NEGOCIOS  their businesses around the club, switched on and off here
##   APRIETES  sending them to "talk" to a player of yours who wants out
##   BENEFICIOS  what a good relationship unlocks (BarraBrava.PERKS)

@onready var portrait : TextureRect = $HBox/Portrait
@onready var vbox : VBoxContainer = $HBox/Scroll/VBox

const TABS := ["aportes", "negocios", "aprietes", "beneficios"]
const TAB_LABELS := ["APORTES", "NEGOCIOS", "APRIETES", "BENEFICIOS"]
## Tab strip colours: the sheet behind the open tab, and the closed tabs.
const SHEET_BG  := Color(0.04, 0.11, 0.14, 0.8)
const TAB_IDLE  := Color(0.06, 0.16, 0.2, 0.4)
const TAB_HOVER := Color(0.15, 0.33, 0.4, 0.7)

var _relacion_bar : ProgressBar = null
var _relacion_label : Label = null
var _poder_bar : ProgressBar = null
var _poder_label : Label = null
var _tab_boxes := {}
var _tab_buttons := {}
var _tab := "aportes"
# Aportes
var _entradas_buttons : Array[Button] = []
var _colab_buttons : Array[Button] = []
var _micros_buttons : Array[Button] = []
var _puestos_label : Label = null
var _summary_label : Label = null
var _trend_label : Label = null
# Negocios: key → {"status": Label, "button": Button}
var _negocio_rows := {}
# Aprietes
var _apriete_list : VBoxContainer = null
var _apriete_result : Label = null

func _ready() -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = BarraBrava.PORTRAIT
	atlas.region = BarraBrava.PORTRAIT_REGION
	portrait.texture = atlas
	_build()
	refresh()

func _build() -> void:
	var title := Label.new()
	title.text = tr("LA BARRA")
	vbox.add_child(title)
	var who := Label.new()
	who.text = tr("%s, capo de la barra") % BarraBrava.LEADER
	who.add_theme_color_override("font_color", HubPalette.MUTED)
	vbox.add_child(who)
	vbox.add_child(HSeparator.new())

	var rel := _meter(vbox, tr("RELACIÓN"), tr("Qué tan contentos están con vos. Pierde un poco cada semana: siempre quieren más. Ganar ayuda; una racha de derrotas la hunde."))
	_relacion_bar = rel[0]
	_relacion_label = rel[1]
	var pod := _meter(vbox, tr("PODER"), tr("Cuánto pueden hacer, para bien o para mal. Crece con los hinchas y con todo lo que les das."))
	_poder_bar = pod[0]
	_poder_label = pod[1]

	# Folder-style tabs sitting on a dark sheet: the pressed tab shares the
	# sheet's colour so it reads as attached to its content, unlike the
	# choice-row toggles inside each tab.
	var tabs := VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	vbox.add_child(tabs)
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 3)
	tabs.add_child(tab_row)
	var sheet := PanelContainer.new()
	sheet.add_theme_stylebox_override("panel", _sheet_style())
	tabs.add_child(sheet)
	var sheet_box := VBoxContainer.new()
	sheet.add_child(sheet_box)
	var group := ButtonGroup.new()
	for i in TABS.size():
		var btn := Button.new()
		btn.text = tr(TAB_LABELS[i])
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 14)
		btn.add_theme_color_override("font_color", HubPalette.MUTED)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_stylebox_override("normal", _tab_style(TAB_IDLE, false))
		btn.add_theme_stylebox_override("hover", _tab_style(TAB_HOVER, false))
		btn.add_theme_stylebox_override("pressed", _tab_style(SHEET_BG, true))
		btn.add_theme_stylebox_override("hover_pressed", _tab_style(SHEET_BG, true))
		btn.pressed.connect(_show_tab.bind(TABS[i]))
		tab_row.add_child(btn)
		_tab_buttons[TABS[i]] = btn
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		sheet_box.add_child(box)
		_tab_boxes[TABS[i]] = box

	_build_aportes(_tab_boxes["aportes"])
	_build_negocios(_tab_boxes["negocios"])
	_build_aprietes(_tab_boxes["aprietes"])
	_build_beneficios(_tab_boxes["beneficios"])
	_show_tab(_tab)

func _show_tab(key: String) -> void:
	_tab = key
	for k in _tab_boxes:
		_tab_boxes[k].visible = k == key
	_tab_buttons[key].set_pressed_no_signal(true)

# ── Aportes ───────────────────────────────────────────────────────────────────

func _build_aportes(box: VBoxContainer) -> void:
	_entradas_buttons = _choice_row(box, tr("Entradas de favor"),
		tr("Parte de la gente de cada partido de local entra gratis. Se cobra menos de entradas."),
		["Ninguna", "10% de la cancha", "25% de la cancha"], _on_entradas)
	_colab_buttons = _choice_row(box, tr("Colaboración"),
		tr("Plata en mano cada semana. Los pone contentos... y más fuertes."),
		["Nada", "", "", ""], _on_colab)
	_micros_buttons = _choice_row(box, tr("Micros para las visitas"),
		tr("Les pagás el viaje para seguir al equipo afuera."),
		["No", ""], _on_micros)

	_puestos_label = Label.new()
	_puestos_label.add_theme_color_override("font_color", HubPalette.MUTED)
	box.add_child(_puestos_label)

	box.add_child(HSeparator.new())
	_summary_label = Label.new()
	box.add_child(_summary_label)
	_trend_label = Label.new()
	_trend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_trend_label)

# ── Negocios ──────────────────────────────────────────────────────────────────

func _build_negocios(box: VBoxContainer) -> void:
	var info := Label.new()
	info.text = tr("Sus negocios alrededor del club. Te dejan plata o los ponen contentos, pero los hacen más fuertes y la AFA mira. Cuanto más tiempo anda uno, más les duele que se lo cortes.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	box.add_child(info)
	for key in BarraBrava.NEGOCIOS:
		var n : Dictionary = BarraBrava.NEGOCIOS[key]
		box.add_child(HSeparator.new())
		var head := HBoxContainer.new()
		box.add_child(head)
		var name_label := Label.new()
		name_label.text = tr(n["label"])
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(name_label)
		var status := Label.new()
		head.add_child(status)
		var blurb := Label.new()
		blurb.text = tr(n["blurb"])
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.add_theme_color_override("font_color", HubPalette.MUTED)
		box.add_child(blurb)
		var effects := Label.new()
		effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effects.add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
		box.add_child(effects)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_negocio_pressed.bind(key))
		box.add_child(btn)
		_negocio_rows[key] = {"status": status, "effects": effects, "button": btn}

## What [param key] does, in numbers, at [param division].
func _negocio_effects(key: String, division: String) -> String:
	var n : Dictionary = BarraBrava.NEGOCIOS[key]
	var parts : Array[String] = []
	match key:
		"trapitos":
			parts.append(tr("+$%s por espectador de local") % MoneyFormat.format(BarraBrava.cost(n["per_fan_e"], division)))
			parts.append(tr("algunos hinchas no vuelven"))
		"reventa":
			parts.append(tr("+%d%% sobre las entradas de local") % roundi(n["gate_bonus"] * 100.0))
			parts.append(tr("hinchas calientes con los precios"))
		"choripaneros":
			parts.append(tr("+$%s por semana") % MoneyFormat.format(BarraBrava.cost(n["weekly_cut_e"], division)))
			parts.append(tr("perdés lo que venda tu puesto de comida"))
		"merch_trucho":
			parts.append(tr("tu merchandising vende %d%% menos") % roundi((1.0 - n["merch_share"]) * 100.0))
		"seguridad":
			parts.append(tr("−$%s por semana") % MoneyFormat.format(BarraBrava.cost(n["weekly_cost_e"], division)))
			parts.append(tr("de local casi no hay incidentes"))
	parts.append(tr("relación +%d por semana") % roundi(n["relacion"]))
	parts.append(tr("más poder"))
	if n.has("heat_match") or n.has("heat_week"):
		parts.append(tr("la AFA mira"))
	return "  ·  ".join(parts)

func _on_negocio_pressed(key: String) -> void:
	var s := GameState.barra
	var on := not BarraBrava.negocio_active(s, key)
	var lost := BarraBrava.set_negocio(s, key, on)
	if lost > 0.0:
		var lines : Array[DialogueLine] = [BarraBrava.line(BarraBrava.CUT_LINES[randi() % BarraBrava.CUT_LINES.size()])]
		ClubTrainer.speak(lines)
	_changed()

# ── Aprietes ──────────────────────────────────────────────────────────────────

func _build_aprietes(box: VBoxContainer) -> void:
	var info := Label.new()
	info.text = tr("Mandás a la barra a \"hablar\" con un jugador tuyo que quiere irse. Se le pasan las ganas... y juega asustado un par de partidos. Cuesta plata, suma calor con la AFA y se puede filtrar.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	box.add_child(info)
	var rival := Label.new()
	rival.text = tr("Para que visiten a la figura de un rival, elegilo antes del partido, en \"Por debajo de la mesa\".")
	rival.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rival.add_theme_color_override("font_color", HubPalette.MUTED)
	box.add_child(rival)
	box.add_child(HSeparator.new())
	_apriete_list = VBoxContainer.new()
	_apriete_list.add_theme_constant_override("separation", 4)
	box.add_child(_apriete_list)
	_apriete_result = Label.new()
	_apriete_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_apriete_result)

func _refresh_aprietes() -> void:
	for child in _apriete_list.get_children():
		_apriete_list.remove_child(child)
		child.queue_free()
	var s := GameState.barra
	var club := GameState.player_club
	if not BarraBrava.can_apriete(s):
		_apriete_line(tr("La barra todavía no tiene poder para esto (necesita %d).") % roundi(BarraBrava.APRIETE_MIN_POWER), HubPalette.MUTED)
		return
	var targets := BarraBrava.apriete_targets(club)
	if targets.is_empty():
		_apriete_line(tr("Nadie en el plantel quiere irse."), HubPalette.MUTED)
		return
	var price := BarraBrava.cost(BarraBrava.APRIETE_COST_E, club.division)
	for p : PlayerResource in targets:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s  %s  (%s)" % [Positions.label(p.role), p.full_name, PlayerMorale.label(p)]
		l.add_theme_color_override("font_color", PlayerMorale.color(p))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var btn := Button.new()
		btn.text = tr("APRETAR  $%s") % MoneyFormat.format(price)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_apriete.bind(p))
		row.add_child(btn)
		_apriete_list.add_child(row)

func _apriete_line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	_apriete_list.add_child(l)

func _on_apriete(p: PlayerResource) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var leaked := BarraBrava.apriete(GameState.barra, GameState.player_club, p, rng)
	if leaked:
		_apriete_result.text = tr("%s ya no se quiere ir... pero se filtró. Mirá el buzón.") % p.full_name
		_apriete_result.add_theme_color_override("font_color", HubPalette.LOSS)
	else:
		_apriete_result.text = tr("Listo. %s ya no se quiere ir. Nadie vio nada.") % p.full_name
		_apriete_result.add_theme_color_override("font_color", HubPalette.WIN)
	_changed()

# ── Beneficios ────────────────────────────────────────────────────────────────

## key → {"name": Label, "status": Label}
var _perk_rows := {}

func _build_beneficios(box: VBoxContainer) -> void:
	var info := Label.new()
	info.text = tr("Lo que te da tener a la barra de tu lado. Se ganan por relación y se pierden si baja.")
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	box.add_child(info)
	for band in [BarraBrava.Band.CONTENTOS, BarraBrava.Band.INCONDICIONALES]:
		box.add_child(HSeparator.new())
		var head := Label.new()
		head.text = "%s  (%d+)" % [tr(BarraBrava.BANDS[band]).to_upper(), roundi(BarraBrava.BAND_MIN[band])]
		head.add_theme_color_override("font_color", BarraBrava.BAND_COLORS[band])
		box.add_child(head)
		for key in BarraBrava.PERKS:
			var perk : Dictionary = BarraBrava.PERKS[key]
			if perk["band"] != band:
				continue
			var row := HBoxContainer.new()
			box.add_child(row)
			var name_label := Label.new()
			name_label.text = tr(perk["label"])
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_label)
			var status := Label.new()
			row.add_child(status)
			var desc := Label.new()
			desc.text = tr(perk["desc"])
			desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			desc.add_theme_color_override("font_color", HubPalette.MUTED)
			box.add_child(desc)
			_perk_rows[key] = {"name": name_label, "status": status}

func _refresh_beneficios() -> void:
	var s := GameState.barra
	for key in _perk_rows:
		var row : Dictionary = _perk_rows[key]
		var on := BarraBrava.has_perk(s, key)
		if not on:
			row["status"].text = tr("BLOQUEADO")
			row["status"].add_theme_color_override("font_color", HubPalette.MUTED)
		elif key in BarraBrava.ONCE_A_SEASON and BarraBrava.perk_used(s, key):
			row["status"].text = tr("USADO ESTA TEMPORADA")
			row["status"].add_theme_color_override("font_color", HubPalette.HIGHLIGHT)
		else:
			row["status"].text = tr("ACTIVO")
			row["status"].add_theme_color_override("font_color", HubPalette.WIN)
		row["name"].add_theme_color_override("font_color", Color.WHITE if on else HubPalette.MUTED)

# ── Shared ────────────────────────────────────────────────────────────────────

## A folder tab: rounded on top, flush at the bottom. The open one gets a gold
## top edge and the sheet's colour so it runs straight into its content.
func _tab_style(bg: Color, open: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	if open:
		sb.border_width_top = 3
		sb.border_color = HubPalette.HIGHLIGHT
	return sb

func _sheet_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SHEET_BG
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 16
	return sb

## A labelled 0-100 bar with an explanation underneath. Returns [bar, value label].
func _meter(parent: Control, heading: String, blurb: String) -> Array:
	var row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = heading
	name_label.custom_minimum_size.x = 110
	row.add_child(name_label)
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var value := Label.new()
	value.custom_minimum_size.x = 170
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	parent.add_child(row)
	var info := Label.new()
	info.text = blurb
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	parent.add_child(info)
	return [bar, value]

## A heading, a blurb and one toggle button per option (index-matched).
func _choice_row(parent: Control, heading: String, blurb: String, labels: Array, on_pick: Callable) -> Array[Button]:
	var name_label := Label.new()
	name_label.text = heading
	parent.add_child(name_label)
	var info := Label.new()
	info.text = blurb
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	parent.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	var group := ButtonGroup.new()
	var buttons : Array[Button] = []
	for i in labels.size():
		var btn := Button.new()
		btn.text = tr(labels[i])
		btn.toggle_mode = true
		btn.button_group = group
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(on_pick.bind(i))
		row.add_child(btn)
		buttons.append(btn)
	return buttons

func refresh() -> void:
	if _relacion_bar == null or GameState.player_club == null:
		return
	var s := GameState.barra
	var division := GameState.player_club.division
	var b := BarraBrava.band(s["relacion"])
	_relacion_bar.value = s["relacion"]
	_relacion_bar.modulate = BarraBrava.BAND_COLORS[b]
	_relacion_label.text = "%s (%d)" % [BarraBrava.band_label(s["relacion"]), roundi(s["relacion"])]
	_relacion_label.add_theme_color_override("font_color", BarraBrava.BAND_COLORS[b])
	_poder_bar.value = s["poder"]
	_poder_label.text = str(roundi(s["poder"]))

	for i in _colab_buttons.size():
		if i > 0:
			_colab_buttons[i].text = "$%s" % MoneyFormat.format(BarraBrava.cost(BarraBrava.COLAB_COST_E[i], division))
	_micros_buttons[1].text = tr("Sí, $%s") % MoneyFormat.format(BarraBrava.cost(BarraBrava.MICROS_COST_E, division))
	_entradas_buttons[s["entradas"]].set_pressed_no_signal(true)
	_colab_buttons[s["colaboracion"]].set_pressed_no_signal(true)
	_micros_buttons[1 if s["micros"] else 0].set_pressed_no_signal(true)

	var puestos : int = s["puestos"]
	_puestos_label.visible = puestos > 0
	_puestos_label.text = tr("Gente de la barra en el club: %d ($%s por semana, no se puede sacar)") % [
		puestos, MoneyFormat.format(puestos * BarraBrava.cost(BarraBrava.PUESTO_COST_E, division))]

	_summary_label.text = tr("Costo semanal: $%s") % MoneyFormat.format(BarraBrava.weekly_cost(s, division))
	var trend := roundi(BarraBrava.weekly_relacion(s))
	if trend > 0:
		_trend_label.text = tr("Así, la relación sube unos %d por semana (sin contar los resultados).") % trend
		_trend_label.add_theme_color_override("font_color", HubPalette.WIN)
	elif trend < 0:
		_trend_label.text = tr("Así, la relación baja unos %d por semana (sin contar los resultados).") % -trend
		_trend_label.add_theme_color_override("font_color", HubPalette.LOSS)
	else:
		_trend_label.text = tr("Así, la relación se mantiene (sin contar los resultados).")
		_trend_label.add_theme_color_override("font_color", HubPalette.MUTED)

	for key in _negocio_rows:
		var row : Dictionary = _negocio_rows[key]
		var active := BarraBrava.negocio_active(s, key)
		var weeks : int = s["negocios"].get(key, 0)
		row["effects"].text = _negocio_effects(key, division)
		if not active:
			row["status"].text = tr("APAGADO")
		elif weeks == 0:
			row["status"].text = tr("ACTIVO · recién arrancado")
		elif weeks == 1:
			row["status"].text = tr("ACTIVO · hace 1 semana")
		else:
			row["status"].text = tr("ACTIVO · hace %d semanas") % weeks
		row["status"].add_theme_color_override("font_color", HubPalette.WIN if active else HubPalette.MUTED)
		var lost := minf(weeks * BarraBrava.DEPENDENCE_PER_WEEK, BarraBrava.DEPENDENCE_MAX)
		if not active:
			row["button"].text = tr("ACTIVAR")
		elif lost >= 1.0:
			row["button"].text = tr("CORTAR  (relación −%d)") % roundi(lost)
		else:
			row["button"].text = tr("CORTAR")

	_refresh_aprietes()
	_refresh_beneficios()

func _on_entradas(level: int) -> void:
	GameState.barra["entradas"] = level
	_changed()

func _on_colab(level: int) -> void:
	GameState.barra["colaboracion"] = level
	_changed()

func _on_micros(on: int) -> void:
	GameState.barra["micros"] = on == 1
	_changed()

func _changed() -> void:
	GameState.save_career()
	refresh()
