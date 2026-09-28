extends Node

## Headless unit-test runner for the engine-v2 maths modules.
##   <godot_console.exe> --path . --headless res://tests/run_tests.tscn
## Runs every tests/*_test.gd (each extends TestCase), calls each test_*
## method, prints failures and exits with code 1 if any test failed.

const TEST_DIR := "res://tests"

func _ready() -> void:
	var total := 0
	var failed := 0
	var files := DirAccess.get_files_at(TEST_DIR)
	for file in files:
		if not file.ends_with("_test.gd"):
			continue
		var script : GDScript = load("%s/%s" % [TEST_DIR, file])
		var inst : TestCase = script.new()
		for m in inst.get_method_list():
			var name : String = m["name"]
			if not name.begins_with("test_"):
				continue
			total += 1
			inst._current = "%s::%s" % [file, name]
			var before := inst.failures.size()
			inst.call(name)
			if inst.failures.size() > before:
				failed += 1
		for f in inst.failures:
			print("FAIL  ", f)
	print("\n%d tests, %d failed" % [total, failed])
	get_tree().quit(1 if failed > 0 else 0)
