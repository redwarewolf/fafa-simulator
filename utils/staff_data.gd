class_name StaffData

## Single source of truth for hireable staff tiers. Costs/levels for the
## Stadium's own upgrades live inline in stadium_panel.gd since nothing else
## reads them; staff levels are read from both staff_panel.gd (the buy UI)
## and ClubResource.get_staff_upkeep_cost() (the automatic per-date deduction
## in GameState), so the table needs a home outside of any one node.

const STAFF := {
	"trainer": {
		"label": "Centro de Entrenamiento",
		"levels": [
			{"cost": 50_000,  "monthly": 2_000,  "max_sessions": 1},
			{"cost": 150_000, "monthly": 5_000,  "max_sessions": 2},
			{"cost": 400_000, "monthly": 10_000, "max_sessions": 3},
		],
	},
	"scout": {
		"label": "Ojeador",
		"levels": [
			{"cost": 50_000,  "monthly": 2_000,  "pool_size": 3},
			{"cost": 150_000, "monthly": 5_000,  "pool_size": 4},
			{"cost": 400_000, "monthly": 10_000, "pool_size": 6},
		],
	},
	"academy": {
		"label": "Academia Juvenil",
		"levels": [
			{"cost": 80_000,  "monthly": 3_000,  "pool_size": 3},
			{"cost": 200_000, "monthly": 6_000,  "pool_size": 5},
			{"cost": 500_000, "monthly": 12_000, "pool_size": 8},
		],
	},
}
