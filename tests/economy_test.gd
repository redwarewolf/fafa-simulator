extends TestCase

## Tapir's debt (ClubDebt) and the economy helpers. Works on a throwaway club
## with an empty squad, so seizures only ever take upgrade levels — taking a
## player would rewrite the tactics save (GameState.clear_player_from_tactics).
## GameState's debt fields are restored after every test.

func _club(budget: int, upgrades: Dictionary = {}) -> ClubResource:
	var club := ClubResource.new("test", "Test", "test", "E")
	club.budget = budget
	club.upgrades = upgrades
	return club

func _with_debt(debt: int, arrears: int, strikes: int, body: Callable) -> void:
	var saved := [GameState.debt, GameState.debt_arrears, GameState.debt_strikes, GameState.inbox.duplicate()]
	GameState.debt = debt
	GameState.debt_arrears = arrears
	GameState.debt_strikes = strikes
	body.call()
	GameState.debt = saved[0]
	GameState.debt_arrears = saved[1]
	GameState.debt_strikes = saved[2]
	GameState.inbox = saved[3]

func test_instalment_paid_when_affordable() -> void:
	_with_debt(10000, 0, 0, func():
		var club := _club(5000)
		var lines : Array[String] = []
		var paid := ClubDebt.collect(club, lines)
		assert_eq(paid, ClubDebt.WEEKLY_PAYMENT)
		assert_eq(club.budget, 5000 - ClubDebt.WEEKLY_PAYMENT)
		assert_eq(GameState.debt, 10000 - ClubDebt.WEEKLY_PAYMENT)
		assert_true(lines.is_empty(), "no lines on an ordinary payday"))

func test_missed_payment_becomes_arrears_with_fee() -> void:
	_with_debt(10000, 0, 0, func():
		var club := _club(1000)
		var lines : Array[String] = []
		assert_eq(ClubDebt.collect(club, lines), 0)
		assert_eq(club.budget, 1000, "nothing taken from the budget")
		assert_eq(GameState.debt_arrears, roundi(ClubDebt.WEEKLY_PAYMENT * (1.0 + ClubDebt.LATE_FEE)))
		assert_eq(GameState.debt_strikes, 1)
		assert_eq(lines.size(), 1, "Tapir warns once"))

func test_second_miss_seizes_the_cheapest_asset_worth_the_arrears() -> void:
	_with_debt(10000, 3300, 1, func():
		# Tribune level 2 cost $30k, food level 1 $10k: both cover the arrears.
		var club := _club(0, {"tribune": 2, "food_sales": 1})
		var lines : Array[String] = []
		ClubDebt.collect(club, lines)
		assert_eq(club.upgrades["food_sales"], 0, "the cheaper food stall goes")
		assert_eq(club.upgrades["tribune"], 2, "the pricier tribune level stays")
		assert_eq(GameState.debt_arrears, 0)
		assert_eq(GameState.debt_strikes, 0)
		assert_eq(lines.size(), 1))

func test_catching_up_clears_arrears() -> void:
	_with_debt(10000, 3300, 1, func():
		var club := _club(20000)
		var lines : Array[String] = []
		assert_eq(ClubDebt.collect(club, lines), 3300 + ClubDebt.WEEKLY_PAYMENT)
		assert_eq(GameState.debt_arrears, 0)
		assert_eq(GameState.debt_strikes, 0))

func test_last_instalment_clears_the_debt() -> void:
	_with_debt(1000, 0, 0, func():
		var club := _club(5000)
		var lines : Array[String] = []
		assert_eq(ClubDebt.collect(club, lines), 1000)
		assert_eq(GameState.debt, 0)
		assert_eq(lines.size(), 1, "Tapir marks the debt paid off"))

func test_building_is_not_seizable_while_an_upgrade_needs_it() -> void:
	var club := _club(0, {"building": 1, "merchandise_sales": 2})
	var keys : Array = []
	for a in ClubDebt.seizable_assets(club):
		keys.append(a.get("key", ""))
	assert_true(not keys.has("building"), "merch level 2 requires the Edificio")
	assert_true(keys.has("merchandise_sales"))

func test_prize_table_is_clamped_to_positions() -> void:
	assert_eq(FanEconomy.prize_for("E", 1), FanEconomy.PRIZE_BY_POSITION["E"][0])
	assert_eq(FanEconomy.prize_for("E", 99), FanEconomy.PRIZE_BY_POSITION["E"][7])
