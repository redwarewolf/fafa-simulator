extends Control

@onready var club_portrait   : TextureRect = $Header/HeaderLayout/ClubSection/ClubPortrait
@onready var club_name_label : Label = $Header/HeaderLayout/ClubSection/ClubName
@onready var date_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/Date
@onready var budget_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Budget
@onready var fans_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Fans
@onready var budget_delta_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/BudgetDelta
@onready var capacity_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Capacity
@onready var division_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Division
@onready var content : Control = $Content
@onready var music : AudioStreamPlayer = $Music
@onready var button_sound : AudioStreamPlayer = $ButtonSound
@onready var header : Control = $Header
@onready var dialogue_box : DialogueBox = $DialogueBox
@onready var club_nav_button : Button = $Header/HeaderLayout/NavSection/ClubButton
@onready var youth_nav_button : Button = $Header/HeaderLayout/NavSection/YouthButton
@onready var match_preview_popup : MatchPreviewPopup = $MatchPreviewPopup
@onready var match_summary_popup : MatchSummaryPopup = $MatchSummaryPopup
@onready var next_day_button : Button = $Header/HeaderLayout/InfoSection/NextDayButton
@onready var home_nav_button : Button = $Header/HeaderLayout/NavSection/HomeButton
@onready var nav_buttons : Dictionary = {
	"home": home_nav_button,
	"squad": $Header/HeaderLayout/NavSection/SquadButton,
	"market": $Header/HeaderLayout/NavSection/MarketButton,
	"club": club_nav_button,
	"calendar": $Header/HeaderLayout/NavSection/CalendarButton,
	"tournament": $Header/HeaderLayout/NavSection/TournamentButton,
	"youth": youth_nav_button,
	"lab": $Header/HeaderLayout/NavSection/LabButton,
}

## Musica de fondo del Hub. Apagada mientras trabajamos en la UI.
@export var music_enabled : bool = false

const MUSIC_TRACK := "res://assets/art/sound/music/main-menu-soundtrack.mp3"
const BUTTON_SOUND_TRACK := "res://assets/music/ui-button-sound.mp3"

const LANDLORD_TOP := preload("res://assets/art/characters/tapir-top.png")
const LANDLORD_BOTTOM := preload("res://assets/art/characters/tapir-bottom.png")

const HOME_NAV_LABEL := "Inicio"
const CLUB_NAV_LABEL := "Club"
const YOUTH_NAV_LABEL := "Juveniles"

const SECTIONS := {
	"home": preload("res://scenes/hub/sections/home/home_section.tscn"),
	"squad": preload("res://scenes/hub/sections/squad/squad_section.tscn"),
	"market": preload("res://scenes/hub/sections/market/market_section.tscn"),
	"club": preload("res://scenes/hub/sections/club/club_section.tscn"),
	"calendar": preload("res://scenes/hub/sections/calendar/calendar_section.tscn"),
	"tournament": preload("res://scenes/hub/sections/tournament/tournament_section.tscn"),
	"youth": preload("res://scenes/hub/sections/youth/youth_section.tscn"),
	"lab": preload("res://scenes/hub/sections/lab/lab_section.tscn"),
}

## Pepito Perinola's one-shot walkthrough for each tab, keyed the same as
## SECTIONS — played via ClubTrainer the first time that tab is shown on a
## given save (see _maybe_play_tab_tutorial()/GameState.tutorials_seen).
## "squad" plays right after the first-boot debt speech since squad is the
## Hub's default tab; the rest play the first time their nav button is clicked.
const TAB_TUTORIALS := {
	"home": [
		"Esta es la pantalla de Inicio. En el Buzón te llegan los resultados, las novedades del plantel y los avisos del torneo — nada se pierde.",
		"A la derecha tenés el próximo partido, cómo vas en la tabla, la plata y una lista de pendientes. Tocá cualquier pendiente y te llevo directo a donde hay que resolverlo.",
	],
	"squad": [
		"Mirá, esta es la pantalla del Plantel. Acá armás tu equipo: arrastrá jugadores a la cancha para ubicarlos en cada posición de la formación.",
		"Si querés probar otro esquema, tocá 'Tácticas' y armate una formación nueva. Andá probando, que esto se aprende jugando.",
	],
	"market": [
		"Este es el Mercado. Acá podés fichar jugadores nuevos o vender a los que te sobran.",
		"Contratá un ojeador para que te traiga candidatos — sin ojeador, no hay refuerzos.",
	],
	"club": [
		"Esta es la sección Club: acá ves las finanzas, contratás personal y mejorás el estadio.",
		"Fijate bien los gastos — entre sueldos y personal, la plata se va rápido.",
	],
	"calendar": [
		"Este es el Calendario. Acá seguís el fixture y avanzás los días hasta el próximo partido.",
	],
	"tournament": [
		"Esta es la Tabla de posiciones. Fijate cómo vas contra el resto de los equipos de la división.",
	],
	"youth": [
		"Esta es la Academia Juvenil. Acá aparecen las promesas que va formando el club — subilas al primer equipo cuando quieras.",
		"Pero no tengas tanto apuro: cada año que un pibe se queda en la Academia sin subir, gana un +3% permanente en TODOS sus atributos, para siempre. Cuanto más lo dejes madurar ahí, mejor te llega al primer equipo.",
	],
	"lab": [
		"Bienvenido al Laboratorio. Acá el Carnicero saca 1 o 2 stats de un jugador — el resto, se pierde para siempre.",
		"Con esos 'órganos' después armás un jugador nuevo, bien verde. No preguntes de dónde salió el resto del cuerpo.",
	],
}

var _section_instances : Dictionary = {}
var _active_section : String = ""
## True while a Próxima Fecha press is still resolving (day advance, narrated
## events, youth sign-ups) — keeps the Space shortcut from stacking a second
## advance on top of the first.
var _advancing := false

func _ready() -> void:
	# Hub is normally only ever reached via Main Menu -> Team Creation/Load
	# Game, both of which set GameState.player_club first. This fallback keeps
	# directly running hub.tscn from the editor (F6) working for ad-hoc
	# testing. There's no static fallback club anymore (Division E is fully
	# procedural), so it generates a throwaway one — deliberately NOT via
	# GameState.start_new_career(), which would overwrite the player's real
	# save files with this scratch data.
	if GameState.player_club == null:
		var dev_clubs := ClubFactory.generate_ai_clubs("E", 8, [], [])
		for club in dev_clubs:
			DataLoader.clubs[club.id] = club
		GameState.player_club = dev_clubs[0]
		SeasonManager.start_pre_season()
		GameState.ensure_default_tactics()
	add_to_group("hub")  # LockedHint's "go hire it" buttons call open_club_panel()
	_preload_sections()
	_update_header()
	# First boot opens on the Squad tab — the intro's squad walkthrough talks
	# about the screen behind it. From then on the Hub opens on Home, like FM.
	_show_section("home" if GameState.has_seen_tutorial("squad") else "squad")
	_section_instances["home"].navigate.connect(_on_home_navigate)
	GameState.budget_changed.connect(_update_header)
	GameState.pool_badges_changed.connect(_update_nav_badges)
	GameState.inbox_changed.connect(_update_nav_badges)
	SeasonManager.season_ended.connect(_on_season_ended)
	match_preview_popup.play_pressed.connect(_on_match_preview_play)
	match_preview_popup.simulate_pressed.connect(_on_match_preview_simulate)
	_update_nav_badges()
	_start_music()
	_connect_button_sounds()
	_run_intro_sequence()

## First-boot-only sequence: Grandi Tapir's debt speech, then Pepito
## Perinola's Squad tutorial (squad is the tab already showing at this point —
## see _show_section("squad") above). Each half is gated independently on
## GameState.tutorials_seen so re-entering the Hub on the same save skips
## whichever part already played (e.g. a save from partway through a career
## still gets the squad tutorial once, without replaying the debt speech).
func _run_intro_sequence() -> void:
	if not GameState.has_seen_tutorial("intro"):
		_play_intro_dialogue()
		await dialogue_box.finished
		GameState.mark_tutorial_seen("intro")
	await _maybe_play_tab_tutorial("squad")

func _play_intro_dialogue() -> void:
	dialogue_box.say([
		DialogueLine.new("Grandi Tapir", LANDLORD_TOP, LANDLORD_BOTTOM,
			"Bueno, así está la cosa. Vas a tener que ir ganando los partidos para poder pagar tu deuda conmigo. Cuantos mas partidos ganes, el club tendrá mas bolu... fanáticos que compren remeritas pedorras. Con eso me vas a pagar a mi y al equipo."),
		DialogueLine.new("Grandi Tapir", LANDLORD_TOP, LANDLORD_BOTTOM,
			"Ahora metele pata que este club no se hace solo."),
	])

## Plays Pepito Perinola's one-shot walkthrough for [param key] (see
## TAB_TUTORIALS) if that tab hasn't shown one yet on this save. No-op if the
## tab has no tutorial defined or it already played.
func _maybe_play_tab_tutorial(key: String) -> void:
	if GameState.has_seen_tutorial(key):
		return
	var lines : Array = TAB_TUTORIALS.get(key, [])
	if lines.is_empty():
		return
	var typed_lines : Array[String] = []
	typed_lines.assign(lines)
	ClubTrainer.say_lines(typed_lines)
	await ClubTrainer.finished
	GameState.mark_tutorial_seen(key)

func _on_season_ended(promoted: bool, new_division: String, position: int) -> void:
	var line : String
	if promoted:
		line = "Terminaste 1° en la tabla — subís a Division %s. Nuevo año, nuevos rivales." % new_division
	elif position == 1:
		line = "Terminaste 1° en la tabla, pero ya estás en la división más alta. ¡Arrancamos otra temporada!"
	else:
		line = "Terminaste #%d en la tabla. A preparar el año que viene." % position
	dialogue_box.say([
		DialogueLine.new("Grandi Tapir", LANDLORD_TOP, LANDLORD_BOTTOM, line),
	])
	_update_header()

func _start_music() -> void:
	if not music_enabled:
		return
	music.stream = load(MUSIC_TRACK)
	music.play()

func _connect_button_sounds() -> void:
	button_sound.stream = load(BUTTON_SOUND_TRACK)
	for button in _find_buttons(header):
		button.pressed.connect(_play_button_sound)

func _find_buttons(node: Node) -> Array:
	var result : Array = []
	for child in node.get_children():
		if child is BaseButton:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result

func _play_button_sound() -> void:
	button_sound.play()

func _preload_sections() -> void:
	for key in SECTIONS:
		var instance : Control = SECTIONS[key].instantiate()
		instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Use process_mode = DISABLED + hide instead of just hide.
		# Bare visible=false keeps the node in the scene tree and its canvas
		# items remain partially active, which causes stale-pixel ghost artifacts
		# when scrollable children (Tree, ScrollContainer) are later shown.
		instance.process_mode = Node.PROCESS_MODE_DISABLED
		instance.visible = false
		content.add_child(instance)
		_section_instances[key] = instance

func _update_header() -> void:
	club_name_label.text = GameState.player_club.display_name
	division_label.text = tr("División %s") % GameState.player_club.division
	budget_label.text = "$%s" % MoneyFormat.format(GameState.player_club.budget)
	fans_label.text = tr("%s hinchas") % MoneyFormat.format(GameState.player_club.fans)
	capacity_label.text = tr("Capacidad: %s") % MoneyFormat.format(GameState.player_club.get_stadium_capacity())
	date_label.text = SeasonManager.current_phase_date_string()
	_apply_club_logo(club_portrait, GameState.player_club)
	_update_budget_delta()
	_update_next_day_button()
	for pair in [[fans_label, "Más hinchas = más entradas, comida y merchandising"],
			[capacity_label, "Máximo de hinchas por partido de local — ampliá la Tribuna en Club > Estadio"],
			[division_label, "Salí 1° de la tabla para ascender"]]:
		pair[0].mouse_filter = Control.MOUSE_FILTER_PASS
		pair[0].tooltip_text = tr(pair[1])

## "+$847" / "-$743" next to the budget — today's movement vs yesterday's
## close (GameState.budget_history), the header's answer to FM's finance ticker.
func _update_budget_delta() -> void:
	if GameState.budget_history.is_empty():
		budget_delta_label.text = ""
		return
	var delta : int = GameState.player_club.budget - int(GameState.budget_history.back())
	budget_delta_label.text = "%s$%s" % ["+" if delta >= 0 else "-", MoneyFormat.format(absi(delta))]
	budget_delta_label.add_theme_color_override("font_color", HubPalette.WIN if delta >= 0 else HubPalette.LOSS)
	budget_delta_label.tooltip_text = tr("Cambio desde ayer")

## The one primary action on the Hub (FM's "Continue"): labelled for what it
## will actually do next — open today's match, or advance to the next day.
func _update_next_day_button() -> void:
	var match_today := not SeasonManager.pending_player_fixture.is_empty()
	next_day_button.text = tr("Jugar Partido") if match_today else tr("Próxima Fecha")
	next_day_button.text += "  >"
	next_day_button.tooltip_text = tr("Atajo: Espacio")

func _apply_club_logo(target: TextureRect, club: ClubResource) -> void:
	ClubLogo.apply(target, club)

## New-candidate counters on the Club (scout) and Youth (academy) nav buttons —
## driven by GameState.pool_badges_changed, so they update the moment a pool
## refreshes and clear the moment the player opens the panel that owns it.
func _update_nav_badges() -> void:
	var club := GameState.player_club
	home_nav_button.text = _nav_label(HOME_NAV_LABEL, GameState.unread_news_count())
	club_nav_button.text = _nav_label(CLUB_NAV_LABEL, club.scout_unseen)
	youth_nav_button.text = _nav_label(YOUTH_NAV_LABEL, club.youth_unseen)

func _nav_label(base: String, unseen: int) -> String:
	var label := tr(base)
	return "%s (%d)" % [label, unseen] if unseen > 0 else label

func _show_section(key: String) -> void:
	if not _section_instances.has(key):
		return
	if _active_section != "":
		_section_instances[_active_section].visible = false
		_section_instances[_active_section].process_mode = Node.PROCESS_MODE_DISABLED
	_active_section = key
	_section_instances[key].process_mode = Node.PROCESS_MODE_INHERIT
	_section_instances[key].visible = true
	# set_pressed_no_signal() skips the ButtonGroup's own release of the old
	# tab, so a code-driven switch (e.g. open_club_panel()) clears it here.
	for k in nav_buttons:
		nav_buttons[k].set_pressed_no_signal(k == key)
	if _section_instances[key].has_method("refresh"):
		_section_instances[key].refresh()

func _on_nav_pressed(section: String) -> void:
	_show_section(section)
	await _maybe_play_tab_tutorial(section)
	# Club has its own sub-tabs (Stadium/Staff/Training/...) — each gets its
	# own one-shot tutorial the first time it's clicked (see club_section.gd),
	# except Stadium, which is already showing by default and never receives
	# a click of its own, so it's chained here right after the Club-tab intro.
	if section == "club":
		var club_section : Control = _section_instances["club"]
		if club_section.has_method("maybe_play_default_sub_tutorial"):
			club_section.maybe_play_default_sub_tutorial()

## Jumps to a Club sub-panel (e.g. "staff") from anywhere in the Hub — used
## by the locked Youth/Lab/Training/Hiring screens' call-to-action button.
## Skips _on_nav_pressed()'s Club/Stadium tutorials on purpose: the target
## sub-panel plays its own, and two narrations at once would stomp each other.
func open_club_panel(key: String) -> void:
	_show_section("club")
	_section_instances["club"].open_panel(key)

## A Home to-do row was clicked: "play" runs the Próxima Fecha flow (opens
## today's match preview); anything else is a section key to switch to.
func _on_home_navigate(target: String) -> void:
	if target == "play":
		_on_next_day_pressed()
	else:
		_on_nav_pressed(target)

func _on_next_day_pressed() -> void:
	if _advancing:
		return
	_advancing = true
	await _advance_day()
	_advancing = false

## Space = Próxima Fecha, like FM's Continue. Handled in _input (before GUI
## focus) so a previously clicked button — e.g. Comprar in the Market — can't
## swallow it and fire again. Stands down whenever anything else owns the
## screen: a narrated dialogue, a popup, the pause menu, or a text field.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE):
		return
	if _advancing or get_tree().paused or next_day_button.disabled:
		return
	if dialogue_box.visible or ClubTrainer.get_node("DialogueBox").visible:
		return
	if match_preview_popup.visible or match_summary_popup.visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	get_viewport().set_input_as_handled()
	_on_next_day_pressed()

func _advance_day() -> void:
	if not SeasonManager.pending_player_fixture.is_empty():
		_show_match_preview()
		return
	GameState.advance_day()
	SeasonManager.resolve_day()
	_update_header()
	GameState.save_career()
	if not SeasonManager.pending_player_fixture.is_empty():
		# Refresh first so the screen behind the popup (e.g. Home's next-match
		# card and to-do list) already reflects match day.
		if _active_section != "" and _section_instances[_active_section].has_method("refresh"):
			_section_instances[_active_section].refresh()
		_show_match_preview()
		return
	# Sequenced, not parallel — both flows narrate through the same shared
	# ClubTrainer dialogue box, and a second say()/say_with_choice() call
	# while one is already showing would stomp it. _maybe_narrate_hub_event()
	# awaits its own line to completion before this moves on.
	await _maybe_narrate_hub_event()
	await YouthSignupFlow.run_daily_signup(GameState.player_club)
	_update_header()
	_update_nav_badges()
	if _active_section != "" and _section_instances[_active_section].has_method("refresh"):
		_section_instances[_active_section].refresh()
	GameState.save_career()

## Shows the Jugar/Simular popup for today's scheduled fixture instead of
## routing straight into World — see MatchPreviewPopup / SeasonManager.
## get_pending_match_preview(). Falls back to the old direct-to-World route
## if the fixture's clubs can't be resolved (data integrity edge case only),
## so a bad fixture can't soft-lock the Hub behind an empty popup.
func _show_match_preview() -> void:
	var preview := SeasonManager.get_pending_match_preview()
	if preview.is_empty():
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
		return
	match_preview_popup.show_for_fixture(preview)

func _on_match_preview_play() -> void:
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")

## Resolves the pending match instantly (SeasonManager.simulate_pending_player_match())
## and shows the same MatchSummaryPopup a played match's GAMEOVER screen uses.
## Reads the fixture's clubs from get_pending_match_preview() BEFORE simulating —
## simulate_pending_player_match() clears pending_player_fixture as part of
## resolving it, same as a played match does.
func _on_match_preview_simulate() -> void:
	var preview := SeasonManager.get_pending_match_preview()
	var result := SeasonManager.simulate_pending_player_match()
	GameState.save_career()
	if preview.is_empty() or result.is_empty():
		_after_match_day()
		return
	var is_own_home : bool = preview.get("is_own_home", true)
	var home : ClubResource = preview["home"]
	var away : ClubResource = preview["away"]
	var own_name := home.display_name if is_own_home else away.display_name
	var opp_name := away.display_name if is_own_home else home.display_name
	var own_score : int = result["home_score"] if is_own_home else result["away_score"]
	var opp_score : int = result["away_score"] if is_own_home else result["home_score"]
	var data := MatchSummaryData.build(own_name, opp_name, own_score, opp_score, result["scorers"], true, result)
	match_summary_popup.continue_pressed.connect(_after_match_day, CONNECT_ONE_SHOT)
	match_summary_popup.show_result(data)

## Tail shared by both the "Simular" flow and (via a fresh Hub scene reload)
## a played match — refreshes the header/badges/active section and saves,
## same as the ordinary non-match "Next Date" flow's tail. Deliberately skips
## _maybe_narrate_hub_event()/YouthSignupFlow — match days already skip those
## for a played match too (see the early-return branches above).
func _after_match_day() -> void:
	_update_header()
	_update_nav_badges()
	if _active_section != "" and _section_instances[_active_section].has_method("refresh"):
		_section_instances[_active_section].refresh()
	GameState.save_career()

## Rolled only on days that don't send the player straight into a match —
## see the early returns above. Applying the event's effect (inside
## maybe_trigger_hub_event) happens synchronously, before the dialogue is
## even shown; awaiting ClubTrainer.finished here just makes sure this
## flow's dialogue is fully done before _on_next_day_pressed() moves on to
## roll the (separate) youth sign-up event on the same shared dialogue box.
func _maybe_narrate_hub_event() -> void:
	var line := RandomEvents.maybe_trigger_hub_event(GameState.player_club)
	if line.is_empty():
		return
	GameState.post_news("Novedad del plantel", line, "event")
	ClubTrainer.say(line)
	await ClubTrainer.finished

## Picks the player's own club plus a random other real club (if any exist)
## so the test match shows correct crests/rosters instead of the scene's
## hardcoded legacy team keys — see GameState.test_match_teams.
func _on_test_match_pressed() -> void:
	GameState.test_match_teams = []
	var player_club := GameState.player_club
	if player_club != null and DataLoader != null:
		var opponents : Array = DataLoader.clubs.values().filter(
			func(c: ClubResource) -> bool: return c.id != player_club.id)
		if not opponents.is_empty():
			var opponent : ClubResource = opponents.pick_random()
			GameState.test_match_teams = [player_club.team_key, opponent.team_key]
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")
