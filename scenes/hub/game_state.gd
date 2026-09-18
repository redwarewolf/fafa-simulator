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

func _ready() -> void:
	TranslationServer.add_translation(LocaleENClass.build())
	_load_locale()
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
	_save_locale()

func _load_locale() -> void:
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

func _save_locale() -> void:
	var file := FileAccess.open(SETTINGS_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % SETTINGS_SAVE_PATH)
		return
	file.store_string(JSON.stringify({"locale": locale}, "\t"))
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
	return tutorials_seen.get(key, false)

func mark_tutorial_seen(key: String) -> void:
	if tutorials_seen.get(key, false):
		return
	tutorials_seen[key] = true
	save_career()

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

const MONTH_NAMES := [
	"", "enero", "febrero", "marzo", "abril", "mayo", "junio",
	"julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"
]

func get_date_string() -> String:
	return format_date(day, month, year)

## Locale-aware date formatting — Spanish and English don't just use different
## month names, they order day/month/year differently ("1 de marzo de 2026"
## vs "March 1, 2026"), so this branches on locale directly rather than
## routing through a %-template tr() key, whose positional args can't be
## reordered by a translation alone. Shared by every screen that prints a
## fixture/calendar date (see calendar_section.gd) so the two never drift.
func format_date(p_day: int, p_month: int, p_year: int, include_year: bool = true) -> String:
	var month_name := tr(MONTH_NAMES[p_month])
	if locale == "en":
		return ("%s %d, %d" % [month_name, p_day, p_year]) if include_year else ("%s %d" % [month_name, p_day])
	return ("%d de %s de %d" % [p_day, month_name, p_year]) if include_year else ("%d de %s" % [p_day, month_name])

func advance_day() -> void:
	day += 1
	var days_in_month := _days_in_month(month, year)
	if day > days_in_month:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
		_on_month_start()
	_tick_costs()
	_tick_passive_income()

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
	_init_default_tactics()
	SeasonManager.start_pre_season()

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
	SeasonManager.phase_dates_remaining = int(data.get("phase_dates_remaining", 0))

	tutorials_seen = data.get("tutorials_seen", {})

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
		"phase_dates_remaining": SeasonManager.phase_dates_remaining,
		"tutorials_seen": tutorials_seen,
	}
	var file := FileAccess.open(CAREER_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		printerr("GameState: could not open %s for writing" % CAREER_SAVE_PATH)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

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
## deducted here too — that now happens every date advance, see _tick_costs().
func _on_month_start() -> void:
	refresh_scout_pool()
	save_staff()

func refresh_scout_pool() -> void:
	var scout_lvl : int = player_club.upgrades.get("scout", 0)
	if scout_lvl <= 0:
		return
	var pool_size : int = StaffData.STAFF["scout"]["levels"][scout_lvl - 1]["pool_size"]
	player_club.scouted_players.clear()
	var odds : Array = PlayerFactory.QUALITY_ODDS[clampi(scout_lvl - 1, 0, PlayerFactory.QUALITY_ODDS.size() - 1)]
	for i in pool_size:
		player_club.scouted_players.append(PlayerFactory.generate_player(odds))
	player_club.scouted_pool_month = month
	player_club.scouted_pool_year = year
	player_club.scout_unseen = pool_size
	pool_badges_changed.emit()

## Tops up the youth academy pool to its current level's capacity — unlike
## refresh_scout_pool(), existing prospects are kept (they persist across
## years until they graduate or are released), only empty slots are filled.
## Called once on first hire and once per year from SeasonManager.start_pre_season().
func refresh_youth_pool() -> void:
	var academy_lvl : int = player_club.upgrades.get("academy", 0)
	if academy_lvl <= 0:
		return
	var pool_size : int = StaffData.STAFF["academy"]["levels"][academy_lvl - 1]["pool_size"]
	var before : int = player_club.youth_players.size()
	while player_club.youth_players.size() < pool_size:
		player_club.youth_players.append(YouthAcademy.generate_youth_player())
	var added : int = player_club.youth_players.size() - before
	if added > 0:
		player_club.youth_unseen += added
		pool_badges_changed.emit()
	save_staff()

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

## Wages + hired-staff upkeep, deducted on every calendar day-advance ("Next
## Date" press) — see ClubResource.get_wage_cost()/get_staff_upkeep_cost().
func _tick_costs() -> void:
	if player_club == null:
		return
	var cost := player_club.get_staff_upkeep_cost() + player_club.get_wage_cost()
	if cost > 0:
		player_club.budget -= cost
		budget_changed.emit()
		save_upgrades()

## Passive income from the "merchandise_sales"/"food_sales" upgrades, rolled
## on every calendar day-advance regardless of whether a match was played.
func _tick_passive_income() -> void:
	if player_club == null:
		return
	var income := FanEconomy.roll_merchandise_revenue(player_club) + FanEconomy.roll_food_revenue(player_club)
	if income > 0:
		player_club.budget += income
		budget_changed.emit()

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
