extends Node

signal budget_changed
## Emitted whenever scout_unseen/youth_unseen change — new candidates arrived
## or the player opened the pool that owns them. Nav badges listen to this.
signal pool_badges_changed

const TacticResourceClass = preload("res://resources/tactic_resource.gd")
const TacticSlotClass     = preload("res://resources/tactic_slot.gd")
const LocaleENClass       = preload("res://utils/locale_en.gd")

## Flip to true while debugging to stop reading/writing user:// save files —
## every run then starts from the default club state instead of whatever
## was last saved to disk.
const DEBUG_DISABLE_PERSISTENCE := false

const TACTICS_SAVE_PATH   := "user://tactics.json"
## 1 — bare array; slot x was half-field (1.0 = halfway line) and slots had no role.
## 2 — {version, active, tactics}; slot x is full-field and every slot names a position.
const TACTICS_SAVE_VERSION := 2
const UPGRADES_SAVE_PATH  := "user://upgrades.json"
const STAFF_SAVE_PATH     := "user://staff.json"
const CAREER_SAVE_PATH    := "user://career.json"
const CAREER_SAVE_VERSION := 1
const SETTINGS_SAVE_PATH  := "user://settings.json"
const DEFAULT_LOCALE      := "es"

## App-wide preference, independent of any career save — persists across
## "New Game"/"Load Game" the same way the OS remembers a display resolution.
var locale : String = DEFAULT_LOCALE

## Dev/debugging convenience — when true, every tutorial (Grandi Tapir's
## debt speech and every Pepito Perinola tab/sub-tab walkthrough) is treated
## as already seen instead of being replayed. Also app-wide, not per-save;
## see settings_screen.gd's "Desactivar Tutorial" checkbox.
var tutorials_disabled : bool = false

## Settings-screen volume sliders, linear 0-1, applied to the Master/Music/SFX
## buses by AudioManager. App-wide, like locale.
var master_volume : float = 1.0
var music_volume : float = 0.7
var sfx_volume : float = 1.0

func _ready() -> void:
	TranslationServer.add_translation(LocaleENClass.build())
	_load_settings()
	TranslationServer.set_locale(locale)

## Switches the UI language and persists the choice. Callers should reload
## the current scene right after (see settings_screen.gd) — dynamic labels
## built from tr()-wrapped templates only re-render when the code that built
## them runs again, not automatically on locale change.
func set_locale(new_locale: String) -> void:
	if new_locale == locale:
		return
	locale = new_locale
	TranslationServer.set_locale(locale)
	_save_settings()

func set_tutorials_disabled(disabled: bool) -> void:
	if disabled == tutorials_disabled:
		return
	tutorials_disabled = disabled
	_save_settings()

## [param bus]: "master", "music" or "sfx".
func set_volume(bus: String, value: float) -> void:
	value = clampf(value, 0.0, 1.0)
	match bus:
		"master": master_volume = value
		"music": music_volume = value
		"sfx": sfx_volume = value
		_: return
	AudioManager.apply_volumes()
	_save_settings()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_SAVE_PATH):
		return
	var file := FileAccess.open(SETTINGS_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		return
	file.close()
	var data : Dictionary = json.data
	locale = data.get("locale", DEFAULT_LOCALE)
	tutorials_disabled = data.get("tutorials_disabled", false)
	master_volume = float(data.get("master_volume", master_volume))
	music_volume = float(data.get("music_volume", music_volume))
	sfx_volume = float(data.get("sfx_volume", sfx_volume))

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % SETTINGS_SAVE_PATH)
		return
	file.store_string(JSON.stringify({"locale": locale, "tutorials_disabled": tutorials_disabled,
		"master_volume": master_volume, "music_volume": music_volume, "sfx_volume": sfx_volume}, "\t"))
	file.close()

# Club
var player_club : ClubResource = null  ## The club the player manages

## Transient, never persisted — [home_team_key, away_team_key] set by the
## Hub's dev "Test Match" shortcut so ActorsContainer spawns two real
## DataLoader clubs (correct crests, rosters, stats) instead of falling
## back to the scene's hardcoded legacy team keys, which predate the
## procedural club system and resolve to no ClubResource at all (both
## sides then landed on the SAME fallback tactic/roster and ClubLogo
## rendered the default portrait for both). Deliberately NOT routed
## through SeasonManager.pending_player_fixture — that would make a dev
## test match record a real season result. See docs/ai-overhaul.md Phase 6.
var test_match_teams : Array = []

# Calendar
var day : int = 1
var month : int = 3
var year : int = 2026

# Tactics – Array of TacticResource
var tactics : Array = []
var active_tactic_index : int = 0

## One-shot tutorial/intro dialogues (Grandi Tapir's debt speech, Pepito
## Perinola's per-tab walkthroughs) — keyed by an arbitrary id ("intro",
## "squad", "market", ...) so each plays at most once per save. Persisted in
## career.json; reset to empty by start_new_career() for a fresh save.
var tutorials_seen : Dictionary = {}

func has_seen_tutorial(key: String) -> bool:
	if tutorials_disabled:
		return true
	return tutorials_seen.get(key, false)

func mark_tutorial_seen(key: String) -> void:
	if tutorials_seen.get(key, false):
		return
	tutorials_seen[key] = true
	save_career()

# ── Inbox (Buzón) ─────────────────────────────────────────────────────────────

## Emitted whenever a message is posted or read — the Home screen and the
## "Inicio" nav badge listen to this.
signal inbox_changed

const INBOX_MAX := 80
const BUDGET_HISTORY_MAX := 60

## FM-style news feed: everything that happened to the club, newest first.
## Each entry is {date, title, body, kind, read}; kind is one of
## "result", "event", "youth", "season", "info" (drives the Home screen's
## colour tag). Persisted in career.json; before this existed, narrated
## events vanished the moment their dialogue box closed.
var inbox : Array = []

## Closing budget of each past day, oldest first — the Home screen's finance
## chart. Appended at the start of advance_day(), so it already includes that
## day's match revenue; the live budget is drawn as the final point.
var budget_history : Array = []

func post_news(title: String, body: String, kind: String = "info") -> void:
	inbox.push_front({
		"date": SeasonManager.current_phase_date_string(),
		"title": title,
		"body": body,
		"kind": kind,
		"read": false,
	})
	if inbox.size() > INBOX_MAX:
		inbox.resize(INBOX_MAX)
	inbox_changed.emit()

func mark_news_read(index: int) -> void:
	if index < 0 or index >= inbox.size() or inbox[index].get("read", false):
		return
	inbox[index]["read"] = true
	inbox_changed.emit()

func unread_news_count() -> int:
	return inbox.filter(func(m: Dictionary) -> bool: return not m.get("read", false)).size()

## player_club stays null until Main Menu -> Team Creation (start_new_career)
## or Load Game (load_career) sets it — Hub is never the first scene anymore,
## so there's nothing to load at autoload-init time.

func _init_default_tactics() -> void:
	tactics.clear()
	for tmpl in ["4-3-3", "4-4-2", "3-5-2"]:
		tactics.append(_make_tactic(tmpl, tmpl))

func _make_tactic(p_name: String, p_template: String) -> Resource:
	var t : Resource = TacticResourceClass.new(p_name, p_template)
	t.init_slots_from_positions(Formations.positions_for(p_template), Formations.roles_for(p_template))
	if player_club != null:
		_auto_fill_tactic(t, player_club.players)
	return t

## Greedily gives each slot the best-fitting unused player from [param players]
## (NATURAL aptitude before SECONDARY before out-of-position) so a freshly
## built tactic already shows a sensible starting XI instead of an empty pitch.
## Shared with TacticBuilder, which AI clubs use to build their own tactics.
func _auto_fill_tactic(t: Resource, players: Array) -> void:
	TacticBuilder.auto_fill(t, players)

func get_active_tactic() -> Resource:
	return tactics[active_tactic_index]

func set_active_tactic(index: int) -> void:
	active_tactic_index = clampi(index, 0, tactics.size() - 1)
	save_tactics()

func add_tactic(tactic_name: String, template: String) -> void:
	tactics.append(_make_tactic(tactic_name, template))
	save_tactics()

func rename_tactic(index: int, new_name: String) -> void:
	if index >= 0 and index < tactics.size():
		tactics[index].tactic_name = new_name
	save_tactics()

func remove_tactic(index: int) -> void:
	if tactics.size() <= 1:
		return  # always keep at least one tactic
	tactics.remove_at(index)
	active_tactic_index = clampi(active_tactic_index, 0, tactics.size() - 1)
	save_tactics()

func advance_day() -> void:
	if player_club != null:
		budget_history.append(player_club.budget)
		if budget_history.size() > BUDGET_HISTORY_MAX:
			budget_history.pop_front()
	day += 1
	var days_in_month := _days_in_month(month, year)
	if day > days_in_month:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		_on_month_start()
	career_day += 1
	payday_today = career_day % PAY_PERIOD_DAYS == 0
	if payday_today:
		_run_payday()

## Returns [day, month, year] resulting from adding `days` days to the given date.
func advance_date(d: int, m: int, y: int, days: int) -> Array:
	for i in days:
		d += 1
		var days_in_month := _days_in_month(m, y)
		if d > days_in_month:
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
	return [d, m, y]

## Calendar days from today until the given date (0 = today, -1 = already
## past). Capped at a year — only ever used for "in N days" labels.
func days_until(d: int, m: int, y: int) -> int:
	if [y, m, d] < [year, month, day]:
		return -1
	var cur := [day, month, year]
	for i in 366:
		if cur[0] == d and cur[1] == m and cur[2] == y:
			return i
		cur = advance_date(cur[0], cur[1], cur[2], 1)
	return 366

func _days_in_month(m: int, y: int) -> int:
	match m:
		2:
			return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31

# ── Career lifecycle ──────────────────────────────────────────────────────────

## Called by Team Creation once the player's club + 7 generated AI clubs
## exist. Registers all of them as Division E (replacing whatever static
## clubs were there), resets the calendar/tactics, builds a fresh season
## schedule, and writes an immediate save.
func start_new_career(club: ClubResource, ai_clubs: Array[ClubResource]) -> void:
	var all_clubs : Array[ClubResource] = [club]
	all_clubs.append_array(ai_clubs)
	replace_division("E", all_clubs)

	player_club = club
	day = 1
	month = 3
	year = 2026
	tutorials_seen.clear()
	inbox.clear()
	budget_history.clear()
	career_day = 0
	payday_today = false
	last_payday_ledger = _empty_ledger()
	debt = ClubDebt.STARTING_DEBT
	debt_arrears = 0
	debt_strikes = 0
	barra = BarraBrava.new_state()
	afa = ClubHeat.new_state()
	tapir_lines.clear()
	_init_default_tactics()
	SeasonManager.start_pre_season()
	post_news("Bienvenido a %s" % club.display_name,
		"La comisión directiva te dio las llaves del club. Arrancamos en la División %s debiéndole $%s a Grandi Tapir, que se cobra $%s por semana, y con un plantel que hay que poner a punto.\n\nAcá en el Buzón te van a llegar los resultados, las novedades del plantel y los avisos del torneo." % [club.division, MoneyFormat.format(ClubDebt.STARTING_DEBT), MoneyFormat.format(ClubDebt.WEEKLY_PAYMENT)],
		"info")

	if not DEBUG_DISABLE_PERSISTENCE:
		save_tactics()
		save_upgrades()
		save_staff()
	save_career()

## Called by Main Menu's Load Game. Returns false (leaving GameState
## untouched) if career.json is missing or unreadable, so the caller can show
## an error instead of proceeding into a broken Hub.
func load_career() -> bool:
	if not FileAccess.file_exists(CAREER_SAVE_PATH):
		return false
	var file := FileAccess.open(CAREER_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		printerr("GameState: failed to parse %s" % CAREER_SAVE_PATH)
		return false
	file.close()
	var data : Dictionary = json.data

	var clubs : Array[ClubResource] = []
	for cd : Dictionary in data.get("division_e_clubs", []):
		clubs.append(ClubResource.from_dict(cd))
	var player_id : String = data.get("player_club_id", "")
	if clubs.is_empty() or player_id.is_empty():
		return false
	# Old saves only ever held Division E, but a promoted club's roster is
	# saved under whichever division it's currently in — from_dict() already
	# carries the right division per club, so just replace that division.
	replace_division(clubs[0].division, clubs)

	var club := DataLoader.get_club(player_id)
	if club == null:
		return false
	player_club = club

	var cal : Dictionary = data.get("calendar", {})
	day = int(cal.get("day", 1))
	month = int(cal.get("month", 3))
	year = int(cal.get("year", 2026))

	SeasonManager.phase = SeasonManager.phase_from_name(data.get("phase", ""))
	if data.has("phase_day"):
		SeasonManager.phase_day = int(data.get("phase_day", 1))
		SeasonManager.phase_length = int(data.get("phase_length", SeasonManager.PRE_SEASON_LENGTH + 1))
	elif data.has("phase_dates_remaining"):
		# Migrates a save from before the phase_day/phase_length counter existed.
		# FIRST_HALF/SECOND_HALF just keep the phase-start defaults set by
		# _start_first_half()/_start_second_half() — phase_dates_remaining was
		# already meaningless there.
		var legacy_remaining : int = int(data["phase_dates_remaining"])
		match SeasonManager.phase:
			SeasonManager.Phase.PRE_SEASON:
				SeasonManager.phase_length = SeasonManager.PRE_SEASON_LENGTH + 1
				SeasonManager.phase_day = SeasonManager.PRE_SEASON_LENGTH - legacy_remaining + 1
			SeasonManager.Phase.MID_SEASON_BREAK:
				SeasonManager.phase_length = SeasonManager.MID_SEASON_BREAK_LENGTH + 1
				SeasonManager.phase_day = SeasonManager.MID_SEASON_BREAK_LENGTH - legacy_remaining + 1

	tutorials_seen = data.get("tutorials_seen", {})
	inbox = data.get("inbox", [])
	budget_history = data.get("budget_history", [])
	# JSON hands numbers back as floats; the ledger's readers expect ints.
	var saved_ledger : Dictionary = data.get("last_payday_ledger", {})
	last_payday_ledger = _empty_ledger()
	for k in last_payday_ledger:
		last_payday_ledger[k] = int(saved_ledger.get(k, 0))
	career_day = int(data.get("career_day", 0))
	payday_today = false
	# Saves from before the weekly economy still owe Tapir the full loan —
	# the intro always said so; now it's real.
	debt = int(data.get("debt", ClubDebt.STARTING_DEBT))
	debt_arrears = int(data.get("debt_arrears", 0))
	debt_strikes = int(data.get("debt_strikes", 0))
	barra = BarraBrava.from_save(data.get("barra", {}))
	afa = ClubHeat.from_save(data.get("afa", {}))
	tapir_lines.clear()

	var fixtures_data : Array[Dictionary] = []
	for f : Dictionary in data.get("fixtures", []):
		fixtures_data.append(f)
	SeasonManager.load_fixtures(fixtures_data)

	if DEBUG_DISABLE_PERSISTENCE:
		_init_default_tactics()
	else:
		if not _load_tactics():
			_init_default_tactics()
		_load_upgrades()
		_load_staff()
	return true

## Snapshots the current career (calendar, every Division E club including
## generated AI opponents, and the fixture list) to disk. Called after every
## day advance and every player match result — see hub.gd/world.gd.
func save_career() -> void:
	if DEBUG_DISABLE_PERSISTENCE or player_club == null:
		return
	# Key name predates promotion (division was always "E"); it now holds
	# whichever division the player's club currently plays in.
	var division_e_data : Array = []
	for club in DataLoader.get_clubs_in_division(player_club.division):
		division_e_data.append(club.to_dict())
	var payload := {
		"version": CAREER_SAVE_VERSION,
		"calendar": {"day": day, "month": month, "year": year},
		"player_club_id": player_club.id,
		"division_e_clubs": division_e_data,
		"fixtures": SeasonManager.fixtures,
		"phase": SeasonManager.phase_name(SeasonManager.phase),
		"phase_day": SeasonManager.phase_day,
		"phase_length": SeasonManager.phase_length,
		"tutorials_seen": tutorials_seen,
		"inbox": inbox,
		"budget_history": budget_history,
		"last_payday_ledger": last_payday_ledger,
		"career_day": career_day,
		"debt": debt,
		"debt_arrears": debt_arrears,
		"debt_strikes": debt_strikes,
		"barra": barra,
		"afa": afa,
	}
	var file := FileAccess.open(CAREER_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % CAREER_SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	# load_career() takes the budget from upgrades.json (_load_upgrades), so
	# keep it in step — gate money, prizes and events don't save it themselves.
	save_upgrades()

## Replaces whatever's currently registered under `division` in
## DataLoader.clubs with exactly the given set — required because
## SeasonManager, Standings, and the Tournament/Market sections all read
## clubs from DataLoader.clubs, not from GameState directly. Passing an empty
## array just clears a division (used when a club leaves it via promotion).
func replace_division(division: String, clubs: Array[ClubResource]) -> void:
	for existing_id in DataLoader.clubs.keys().duplicate():
		if DataLoader.clubs[existing_id].division == division:
			DataLoader.clubs.erase(existing_id)
	for club in clubs:
		DataLoader.clubs[club.id] = club

## Ensures a default tactic set exists without discarding one already loaded —
## used by the dev-safety-net in hub.gd for direct scene runs.
func ensure_default_tactics() -> void:
	if tactics.is_empty():
		_init_default_tactics()

# ── Tactic persistence ────────────────────────────────────────────────────────

## Serialize all tactics to JSON and write to disk.
func save_tactics() -> void:
	if DEBUG_DISABLE_PERSISTENCE:
		return
	var data : Array = []
	for t in tactics:
		var slots_arr : Array = []
		for s in t.slots:
			var entry : Dictionary = {
				"pos_x": s.position.x,
				"pos_y": s.position.y,
				"role": Positions.key(s.role),
				"player": null
			}
			if s.player != null:
				entry["player"] = {
					"full_name": s.player.full_name,
					"skin_color": s.player.skin_color,
					"hair_color": s.player.hair_color,
					"role": Positions.key(s.player.role),
					"age": s.player.age,
					"quality": s.player.quality,
					"pac": s.player.pac,
					"sho": s.player.sho,
					"pas": s.player.pas,
					"dri": s.player.dri,
					"def": s.player.def,
					"phy": s.player.phy,
					"body_type": s.player.body_type,
					"special_type": s.player.special_type,
					"portrait_frame": s.player.portrait_frame,
				}
			slots_arr.append(entry)
		data.append({
			"tactic_name": t.tactic_name,
			"template": t.template,
			"slots": slots_arr,
		})
	var payload := {
		"version": TACTICS_SAVE_VERSION,
		"active": active_tactic_index,
		"tactics": data,
	}
	var json_text := JSON.stringify(payload, "\t")
	var file := FileAccess.open(TACTICS_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % TACTICS_SAVE_PATH)
		return
	file.store_string(json_text)
	file.close()

## Load tactics from disk. Returns true on success, false if no save file exists.
func _load_tactics() -> bool:
	if not FileAccess.file_exists(TACTICS_SAVE_PATH):
		return false
	var file := FileAccess.open(TACTICS_SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		printerr("GameState: failed to parse %s" % TACTICS_SAVE_PATH)
		return false
	file.close()
	# v1 was a bare array of tactics; v2 wraps them so the format can move again.
	var parsed = json.data
	var version := 1
	var entries : Array = []
	var saved_active := 0
	if parsed is Array:
		entries = parsed
	elif parsed is Dictionary:
		version = int(parsed.get("version", 1))
		entries = parsed.get("tactics", [])
		saved_active = int(parsed.get("active", 0))
	if entries.is_empty():
		return false
	tactics.clear()
	for td in entries:
		var t : Resource = TacticResourceClass.new(td["tactic_name"], td["template"])
		var template_roles : Array = Formations.roles_for(td["template"])
		var slots_data : Array = td["slots"]
		for i in slots_data.size():
			var sd : Dictionary = slots_data[i]
			var pos := Vector2(sd["pos_x"], sd["pos_y"])
			if version < 2:
				# v1 anchors were half-field: x=1.0 meant the halfway line. Halving
				# keeps the shape the player drew, now expressed on the full pitch.
				pos.x *= 0.5
			# A v1 slot names no position, so fall back to what the template asks
			# for at that index.
			var role : Positions.Role = template_roles[i] if i < template_roles.size() else Positions.Role.CM
			if sd.has("role"):
				role = Positions.parse(sd["role"])
			var slot : Resource = TacticSlotClass.new(pos, role)
			if sd["player"] != null:
				var pd : Dictionary = sd["player"]
				# Link the club's OWN PlayerResource, don't rebuild a copy. Slot
				# identity is by reference — find_slot_for_player() and the market's
				# _clear_from_tactics() both compare instances — so a copy here left
				# the squad screen unable to tell that the player it was moving
				# already held a slot, and they ended up drawn in two places at once.
				# Linking the live instance also retires the re-sync this used to
				# need: the copy drifted from the club file every time a field was
				# added (hair_color) or changed meaning (role).
				var live : Array = player_club.players.filter(
					func(p: PlayerResource) -> bool: return p.full_name == pd["full_name"]
				)
				if live.size() > 0:
					slot.player = live[0]
				else:
					# Off the roster by now (sold, or a save from another club) —
					# keep the serialized copy so the shape still reads.
					slot.player = PlayerResource.new(
						pd["full_name"],
						pd["skin_color"] as Player.SkinColor,
						pd.get("hair_color", 0) as Player.HairColor,
						Positions.parse(pd["role"]),
						pd["age"],
						pd["quality"] as PlayerResource.Quality,
						pd["pac"], pd["sho"], pd["pas"],
						pd["dri"], pd["def"], pd["phy"],
						pd.get("body_type", "default"),
						pd.get("special_type", ""),
						int(pd.get("portrait_frame", -1))
					)
			t.slots.append(slot)
		tactics.append(t)
	# set_active_tactic() has always called save_tactics(), but v1 never wrote the
	# index, so the chosen tactic silently reset to the first one on every launch.
	active_tactic_index = clampi(saved_active, 0, tactics.size() - 1)
	return true

# ── Upgrade persistence ───────────────────────────────────────────────────────

func save_upgrades() -> void:
	if DEBUG_DISABLE_PERSISTENCE:
		return
	var data := {
		"upgrades": player_club.upgrades,
		"budget":   player_club.budget,
	}
	var file := FileAccess.open(UPGRADES_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % UPGRADES_SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _load_upgrades() -> void:
	if not FileAccess.file_exists(UPGRADES_SAVE_PATH):
		return
	var file := FileAccess.open(UPGRADES_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		printerr("GameState: failed to parse %s" % UPGRADES_SAVE_PATH)
		return
	file.close()
	var data : Dictionary = json.data
	player_club.upgrades = data.get("upgrades", {})
	player_club.budget   = data.get("budget",   player_club.budget)

# ── Staff (trainer/scout) ─────────────────────────────────────────────────────

## Rolls a fresh scout candidate pool sized to the scout's current level, if
## one is hired. Called on every calendar month rollover, and once
## immediately after a first-time scout hire so the player doesn't have to
## wait until next month to see any candidates. Wages/staff upkeep used to be
## deducted here once — that now happens every payday, see _run_payday().
func _on_month_start() -> void:
	refresh_scout_pool()
	save_staff()

## Chance any single scouted slot turns up a youth-academy-age kid (see
## YouthAcademy) instead of an ordinary adult find — the scout finds both,
## mixed into the one pool (see hiring_panel.gd, which routes a purchased
## kid to the academy instead of the senior roster via
## PlayerResource.is_youth_prospect).
const SCOUT_KID_FIND_CHANCE := 0.2

func refresh_scout_pool() -> void:
	var scout_lvl : int = player_club.upgrades.get("scout", 0)
	if scout_lvl <= 0:
		return
	var pool_size : int = StaffData.STAFF["scout"]["levels"][scout_lvl - 1]["pool_size"]
	player_club.scouted_players.clear()
	var odds : Array = PlayerFactory.QUALITY_ODDS[clampi(scout_lvl - 1, 0, PlayerFactory.QUALITY_ODDS.size() - 1)]
	for i in pool_size:
		if randf() < SCOUT_KID_FIND_CHANCE:
			player_club.scouted_players.append(YouthAcademy.generate_youth_player(odds))
		else:
			player_club.scouted_players.append(PlayerFactory.generate_player(odds, -1, true))
	player_club.scouted_pool_month = month
	player_club.scouted_pool_year = year
	player_club.scout_unseen = pool_size
	pool_badges_changed.emit()

## Current youth-academy capacity from StaffData, 0 if not hired. Prospects
## no longer auto-fill to this — they only arrive one at a time through
## narrated sign-up events (see YouthEvents/YouthSignupFlow), which use this
## as the "are we full" gate.
func get_youth_academy_cap() -> int:
	var academy_lvl : int = player_club.upgrades.get("academy", 0)
	if academy_lvl <= 0:
		return 0
	return StaffData.STAFF["academy"]["levels"][academy_lvl - 1]["pool_size"]

## Clears the scout-pool badge — called when the player opens the Hiring panel.
func mark_scout_seen() -> void:
	if player_club.scout_unseen == 0:
		return
	player_club.scout_unseen = 0
	save_staff()
	pool_badges_changed.emit()

## Clears the youth-academy badge — called when the player opens the Youth screen.
func mark_youth_seen() -> void:
	if player_club.youth_unseen == 0:
		return
	player_club.youth_unseen = 0
	save_staff()
	pool_badges_changed.emit()

## Unassigns a player from every tactic slot that holds them — used when a
## player leaves the roster (sold, or retired) so no tactic keeps a dangling
## reference. Shared by market_section.gd's sell flow and SeasonManager's
## season-end retirement pass.
func clear_player_from_tactics(p: PlayerResource) -> void:
	for t in tactics:
		for slot in t.slots:
			if slot.player == p:
				slot.clear()
	save_tactics()

# ── Weekly payday ─────────────────────────────────────────────────────────────

## Wages, staff upkeep, stand income, sponsor and TV money, and Tapir's debt
## instalment all settle together every PAY_PERIOD_DAYS "Next Date" presses.
const PAY_PERIOD_DAYS := 7

## Days advanced since the career began — drives the payday cycle.
var career_day : int = 0
## True for the day advance that just ran a payday — the match summary only
## shows the weekly ledger when that payday landed on the match day.
var payday_today : bool = false

## Grandi Tapir's loan (see ClubDebt): principal still to repay, overdue
## instalments (incl. late fees), and consecutive missed paydays.
var debt : int = 0
var debt_arrears : int = 0
var debt_strikes : int = 0

## La barra brava — relación, poder, what you give them and Barroni's visits.
## See BarraBrava for the keys and rules. Saved in career.json.
var barra : Dictionary = BarraBrava.new_state()

## Heat, AFA sanctions and this match's bribes — see ClubHeat. Saved in career.json.
var afa : Dictionary = ClubHeat.new_state()

## Tapir's lines from the latest payday, waiting for the Hub to narrate them
## (transient — every one is also posted to the Inbox).
var tapir_lines : Array[String] = []

## The latest payday's breakdown — read by the Finances screen and, on a
## payday match day, the match summary. Keys: wage_cost, staff_upkeep_cost,
## merchandise_revenue, food_revenue, sponsor_revenue, tv_revenue,
## debt_payment.
var last_payday_ledger : Dictionary = _empty_ledger()

static func _empty_ledger() -> Dictionary:
	return {"wage_cost": 0, "staff_upkeep_cost": 0, "merchandise_revenue": 0, "food_revenue": 0,
		"sponsor_revenue": 0, "tv_revenue": 0, "debt_payment": 0, "barra_cost": 0, "afa_fine": 0, "barra_income": 0}

## "Next Date" presses until the next payday (1-7).
func days_until_payday() -> int:
	return PAY_PERIOD_DAYS - career_day % PAY_PERIOD_DAYS

func _run_payday() -> void:
	if player_club == null:
		return
	var ledger := _empty_ledger()
	ledger["merchandise_revenue"] = FanEconomy.roll_merchandise_revenue(player_club)
	ledger["food_revenue"] = FanEconomy.roll_food_revenue(player_club)
	ledger["sponsor_revenue"] = FanEconomy.sponsor_revenue(player_club)
	ledger["tv_revenue"] = FanEconomy.tv_revenue(player_club)
	ledger["wage_cost"] = player_club.get_wage_cost()
	ledger["staff_upkeep_cost"] = player_club.get_staff_upkeep_cost()
	# The barra's businesses take the food stalls and part of the merch.
	var business := BarraBrava.adjust_payday(barra, ledger, player_club.division)
	ledger["barra_income"] = business["income"]
	player_club.budget += ledger["merchandise_revenue"] + ledger["food_revenue"] \
		+ ledger["sponsor_revenue"] + ledger["tv_revenue"] + ledger["barra_income"] \
		- ledger["wage_cost"] - ledger["staff_upkeep_cost"] - business["cost"]
	ledger["barra_cost"] = BarraBrava.weekly(barra, player_club) + business["cost"]
	ledger["afa_fine"] = ClubHeat.weekly(afa, player_club, barra)
	# Income lands first, so the week's earnings can cover Tapir's instalment.
	ledger["debt_payment"] = ClubDebt.collect(player_club, tapir_lines)
	last_payday_ledger = ledger
	# Wages the budget couldn't cover are "late" as far as the squad knows.
	if player_club.budget < 0 and ledger["wage_cost"] > 0:
		PlayerMorale.unpaid_wages(player_club)
		post_news("Sueldos atrasados",
			"El club cerró la semana en rojo y los jugadores cobraron tarde. El plantel está molesto (ánimo %d)." % roundi(PlayerMorale.UNPAID_WAGES),
			"event")
	budget_changed.emit()
	save_upgrades()
	save_staff()

## Pays off everything still owed to Tapir in one go. False if the budget
## can't cover it.
func pay_off_debt() -> bool:
	var total := debt + debt_arrears
	if total <= 0 or player_club == null or player_club.budget < total:
		return false
	player_club.budget -= total
	debt = 0
	debt_arrears = 0
	debt_strikes = 0
	post_news("Deuda saldada", "Le pagaste a Grandi Tapir los $%s que quedaban. El club ya no le debe nada." % MoneyFormat.format(total), "debt")
	tapir_lines.append("¿Todo junto? Mirá vos... Se terminó la deuda. Un placer hacer negocios con vos.")
	budget_changed.emit()
	save_upgrades()
	save_career()
	return true

func save_staff() -> void:
	if DEBUG_DISABLE_PERSISTENCE:
		return
	var scouted : Array = []
	for p : PlayerResource in player_club.scouted_players:
		scouted.append(p.to_dict())
	var youth : Array = []
	for p : PlayerResource in player_club.youth_players:
		youth.append(p.to_dict())
	var data := {
		"scouted_players": scouted,
		"pool_month": player_club.scouted_pool_month,
		"pool_year":  player_club.scouted_pool_year,
		"youth_players": youth,
		"scout_unseen": player_club.scout_unseen,
		"youth_unseen": player_club.youth_unseen,
		"organs": player_club.organs,
	}
	var file := FileAccess.open(STAFF_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % STAFF_SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func _load_staff() -> void:
	if not FileAccess.file_exists(STAFF_SAVE_PATH):
		return
	var file := FileAccess.open(STAFF_SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close()
		printerr("GameState: failed to parse %s" % STAFF_SAVE_PATH)
		return
	file.close()
	var data : Dictionary = json.data

	player_club.scouted_players.clear()
	for pd : Dictionary in data.get("scouted_players", []):
		player_club.scouted_players.append(PlayerResource.from_dict(pd))
	player_club.scouted_pool_month = int(data.get("pool_month", 0))
	player_club.scouted_pool_year  = int(data.get("pool_year", 0))

	player_club.youth_players.clear()
	for pd : Dictionary in data.get("youth_players", []):
		player_club.youth_players.append(PlayerResource.from_dict(pd))
	player_club.scout_unseen = int(data.get("scout_unseen", 0))
	player_club.youth_unseen = int(data.get("youth_unseen", 0))

	player_club.organs.clear()
	for od : Dictionary in data.get("organs", []):
		player_club.organs.append({
			"id": int(od["id"]),
			"stat": String(od["stat"]),
			"value": int(od["value"]),
			"donor_name": String(od["donor_name"]),
			"donor_quality": int(od["donor_quality"]),
			"donor_age": int(od["donor_age"]),
		})
