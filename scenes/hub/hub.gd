extends Control

@onready var club_portrait   : TextureRect = $Header/HeaderLayout/ClubSection/ClubPortrait
@onready var club_name_label : Label = $Header/HeaderLayout/ClubSection/ClubName
@onready var date_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/Date
@onready var budget_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Budget
@onready var fans_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Fans
@onready var capacity_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Capacity
@onready var division_label : Label = $Header/HeaderLayout/InfoSection/InfoLabels/MoneyDivision/Division
@onready var content : Control = $Content
@onready var music : AudioStreamPlayer = $Music
@onready var button_sound : AudioStreamPlayer = $ButtonSound
@onready var header : Control = $Header
@onready var dialogue_box : DialogueBox = $DialogueBox
@onready var club_nav_button : Button = $Header/HeaderLayout/NavSection/ClubButton
@onready var youth_nav_button : Button = $Header/HeaderLayout/NavSection/YouthButton

## Musica de fondo del Hub. Apagada mientras trabajamos en la UI.
@export var music_enabled : bool = false

const MUSIC_TRACK := "res://assets/art/sound/music/main-menu-soundtrack.mp3"
const BUTTON_SOUND_TRACK := "res://assets/music/ui-button-sound.mp3"

const LANDLORD_TOP := preload("res://assets/art/characters/tapir-top.png")
const LANDLORD_BOTTOM := preload("res://assets/art/characters/tapir-bottom.png")

const CLUB_NAV_LABEL := "Club"
const YOUTH_NAV_LABEL := "Juveniles"

const SECTIONS := {
	"squad": preload("res://scenes/hub/sections/squad/squad_section.tscn"),
	"market": preload("res://scenes/hub/sections/market/market_section.tscn"),
	"club": preload("res://scenes/hub/sections/club/club_section.tscn"),
	"calendar": preload("res://scenes/hub/sections/calendar/calendar_section.tscn"),
	"tournament": preload("res://scenes/hub/sections/tournament/tournament_section.tscn"),
	"youth": preload("res://scenes/hub/sections/youth/youth_section.tscn"),
}

## Pepito Perinola's one-shot walkthrough for each tab, keyed the same as
## SECTIONS — played via ClubTrainer the first time that tab is shown on a
## given save (see _maybe_play_tab_tutorial()/GameState.tutorials_seen).
## "squad" plays right after the first-boot debt speech since squad is the
## Hub's default tab; the rest play the first time their nav button is clicked.
const TAB_TUTORIALS := {
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
}

var _section_instances : Dictionary = {}
var _active_section : String = ""

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
	_preload_sections()
	_update_header()
	_show_section("squad")
	GameState.budget_changed.connect(_update_header)
	GameState.pool_badges_changed.connect(_update_nav_badges)
	SeasonManager.season_ended.connect(_on_season_ended)
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
	var phase_text := ""
	match SeasonManager.phase:
		SeasonManager.Phase.PRE_SEASON: phase_text = tr("Pretemporada")
		SeasonManager.Phase.FIRST_HALF: phase_text = tr("1ª Mitad")
		SeasonManager.Phase.MID_SEASON_BREAK: phase_text = tr("Receso de Temporada")
		SeasonManager.Phase.SECOND_HALF: phase_text = tr("2ª Mitad")
	date_label.text = "%s  ·  %s" % [GameState.get_date_string(), phase_text]
	_apply_club_logo(club_portrait, GameState.player_club)

func _apply_club_logo(target: TextureRect, club: ClubResource) -> void:
	ClubLogo.apply(target, club)

## New-candidate counters on the Club (scout) and Youth (academy) nav buttons —
## driven by GameState.pool_badges_changed, so they update the moment a pool
## refreshes and clear the moment the player opens the panel that owns it.
func _update_nav_badges() -> void:
	var club := GameState.player_club
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

func _on_next_day_pressed() -> void:
	if not SeasonManager.pending_player_fixture.is_empty():
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
		return
	GameState.advance_day()
	SeasonManager.resolve_day()
	_update_header()
	GameState.save_career()
	if not SeasonManager.pending_player_fixture.is_empty():
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
		return
	_maybe_narrate_hub_event()

## Rolled only on days that don't send the player straight into a match —
## see the early returns above. Applying the event's effect (inside
## maybe_trigger_hub_event) happens synchronously, before the dialogue is
## even shown, so re-saving here is what actually persists it — the regular
## save_career() call in _on_next_day_pressed() already ran for this date
## before this function was called.
func _maybe_narrate_hub_event() -> void:
	var line := RandomEvents.maybe_trigger_hub_event(GameState.player_club)
	if line.is_empty():
		return
	ClubTrainer.say(line)
	_update_header()
	# An event may have mutated the roster/tactics (e.g. a suspension benching
	# a player) — refresh whichever section is showing so it doesn't display
	# stale data until the player happens to switch tabs.
	if _active_section != "" and _section_instances[_active_section].has_method("refresh"):
		_section_instances[_active_section].refresh()
	GameState.save_career()

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
