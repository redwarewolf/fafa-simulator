extends Node

## App-wide audio: the Music/SFX buses the settings sliders control, the one
## music player that keeps playing across scene changes, and the UI sounds.
##
## Every BaseButton that enters the tree clicks automatically — the soft
## ui-navigate for ordinary buttons, the fuller ui-button-sound for
## PrimaryButton ones (a screen's main action). Override per button with
## set_meta("sfx", "navigate" | "click" | "none"). Money changing hands on
## the player's say-so plays purchase.wav instead (play_purchase()).

const MENU_MUSIC := "res://assets/music/tournament.mp3"
const HUB_MUSIC := "res://assets/music/menu.mp3"

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

const _NAVIGATE_STREAM := preload("res://assets/sfx/ui-navigate.wav")
const _CLICK_STREAM := preload("res://assets/music/ui-button-sound.mp3")
const _PURCHASE_STREAM := preload("res://assets/sfx/purchase.wav")

## A purchase is usually triggered by the very button press that also asks
## for a click; within this window the click is dropped so only the purchase
## sound plays, whichever of the two handlers runs first.
const PURCHASE_MUTES_CLICK_MS := 150

var _music : AudioStreamPlayer
var _navigate : AudioStreamPlayer
var _click : AudioStreamPlayer
var _purchase : AudioStreamPlayer
var _music_path := ""
var _purchase_ms := -100000

func _ready() -> void:
	# The pause menu freezes the tree; its buttons should still click.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(BUS_MUSIC)
	_ensure_bus(BUS_SFX)
	_music = _make_player(BUS_MUSIC, -8.0)
	_navigate = _make_player(BUS_SFX, -6.0, _NAVIGATE_STREAM)
	_click = _make_player(BUS_SFX, -10.0, _CLICK_STREAM)
	_click.pitch_scale = 0.85
	_purchase = _make_player(BUS_SFX, -4.0, _PURCHASE_STREAM)
	apply_volumes()
	get_tree().node_added.connect(_on_node_added)

func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")

func _make_player(bus: StringName, volume_db: float, stream: AudioStream = null) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = volume_db
	p.stream = stream
	add_child(p)
	return p

## Pushes GameState's saved slider values (0-1) onto the buses.
func apply_volumes() -> void:
	_set_bus_volume(&"Master", GameState.master_volume)
	_set_bus_volume(BUS_MUSIC, GameState.music_volume)
	_set_bus_volume(BUS_SFX, GameState.sfx_volume)

func _set_bus_volume(bus_name: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))

## Starts [param path] looping; a no-op if it's already the track playing,
## so moving between menu screens doesn't restart the song.
func play_music(path: String) -> void:
	if path == _music_path and _music.playing:
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_path = path
	_music.stream = stream
	_music.play()

func stop_music() -> void:
	_music_path = ""
	_music.stop()

func play_navigate() -> void:
	_play_ui(_navigate)

func play_click() -> void:
	_play_ui(_click)

## Money spent or earned by something the player just did (buying, selling,
## hiring, upgrading, a youth sign-up fee) — not the daily wage/income tick.
func play_purchase() -> void:
	_purchase_ms = Time.get_ticks_msec()
	_navigate.stop()
	_click.stop()
	_purchase.play()

func _play_ui(p: AudioStreamPlayer) -> void:
	if Time.get_ticks_msec() - _purchase_ms < PURCHASE_MUTES_CLICK_MS:
		return
	p.play()

func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(&"_sfx_hooked"):
		node.set_meta(&"_sfx_hooked", true)
		(node as BaseButton).pressed.connect(_on_button_pressed.bind(node))

func _on_button_pressed(button: BaseButton) -> void:
	var kind : String = button.get_meta(&"sfx", "")
	if kind == "":
		kind = "click" if button.theme_type_variation == &"PrimaryButton" else "navigate"
	match kind:
		"click":
			play_click()
		"navigate":
			play_navigate()
