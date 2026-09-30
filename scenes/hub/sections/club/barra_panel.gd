extends Control

## Club > La Barra: Barroni Flaquito, how the barra feels about you
## (relación, poder) and what you give them every week — see BarraBrava for
## the rules. Changes take effect on the next payday.

@onready var portrait : TextureRect = $HBox/Portrait
@onready var vbox : VBoxContainer = $HBox/Scroll/VBox

var _relacion_bar : ProgressBar = null
var _relacion_label : Label = null
var _poder_bar : ProgressBar = null
var _poder_label : Label = null
var _entradas_buttons : Array[Button] = []
var _colab_buttons : Array[Button] = []
var _micros_buttons : Array[Button] = []
var _puestos_label : Label = null
var _summary_label : Label = null
var _trend_label : Label = null

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

	var rel := _meter(tr("RELACIÓN"), tr("Qué tan contentos están con vos. Pierde un poco cada semana: siempre quieren más. Ganar ayuda; una racha de derrotas la hunde."))
	_relacion_bar = rel[0]
	_relacion_label = rel[1]
	var pod := _meter(tr("PODER"), tr("Cuánto pueden hacer, para bien o para mal. Crece con los hinchas y con todo lo que les das."))
	_poder_bar = pod[0]
	_poder_label = pod[1]

	vbox.add_child(HSeparator.new())
	var aportes := Label.new()
	aportes.text = tr("APORTES SEMANALES")
	aportes.add_theme_color_override("font_color", HubPalette.MUTED)
	vbox.add_child(aportes)

	_entradas_buttons = _choice_row(tr("Entradas de favor"),
		tr("Parte de la gente de cada partido de local entra gratis. Se cobra menos de entradas."),
		["Ninguna", "10% de la cancha", "25% de la cancha"], _on_entradas)
	_colab_buttons = _choice_row(tr("Colaboración"),
		tr("Plata en mano cada semana. Los pone contentos... y más fuertes."),
		["Nada", "", "", ""], _on_colab)
	_micros_buttons = _choice_row(tr("Micros para las visitas"),
		tr("Les pagás el viaje para seguir al equipo afuera."),
		["No", ""], _on_micros)

	_puestos_label = Label.new()
	_puestos_label.add_theme_color_override("font_color", HubPalette.MUTED)
	vbox.add_child(_puestos_label)

	vbox.add_child(HSeparator.new())
	_summary_label = Label.new()
	vbox.add_child(_summary_label)
	_trend_label = Label.new()
	_trend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_trend_label)

## A labelled 0-100 bar with an explanation underneath. Returns [bar, value label].
func _meter(heading: String, blurb: String) -> Array:
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
	vbox.add_child(row)
	var info := Label.new()
	info.text = blurb
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	vbox.add_child(info)
	return [bar, value]

## A heading, a blurb and one toggle button per option (index-matched).
func _choice_row(heading: String, blurb: String, labels: Array, on_pick: Callable) -> Array[Button]:
	var name_label := Label.new()
	name_label.text = heading
	vbox.add_child(name_label)
	var info := Label.new()
	info.text = blurb
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", HubPalette.MUTED)
	vbox.add_child(info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	vbox.add_child(row)
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
