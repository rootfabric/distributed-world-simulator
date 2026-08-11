extends SceneTree
const Field = preload("res://scripts/research/ecology/plant_regional_population_field_v1.gd")
const EXPECTED_RESULT_HASH := "cbd2f4a65f2a06f8ee9feeea0d9eae90d37cd0ede15df1bd808ef52773089b56"
const EXPECTED_NEUTRAL_HASH := "b4d18ef35a2a77104fa18c8a3f3004a6f5898d572e57917429cc955cc7e2c5e6"
const EXPECTED_ALT_HASH := "ca81e0cfea0b05850470276fef10c880d3832613df9ff7f35d3c7395bd32589b"
var assertions := 0
var failures: Array[String] = []
func _init() -> void:
	var result := Field.run()
	var neutral := Field.run(Field.DEFAULT_GRID_SIZE, Field.DEFAULT_GENERATIONS, Field.DEFAULT_POPULATION_SIZE, Field.DEFAULT_OFFSPRING_PER_PARENT, Field.DEFAULT_LINEAGE_SEED, true)
	var alternate := Field.run(Field.DEFAULT_GRID_SIZE, Field.DEFAULT_GENERATIONS, Field.DEFAULT_POPULATION_SIZE, Field.DEFAULT_OFFSPRING_PER_PARENT, Field.ALT_LINEAGE_SEED, false)
	_check(not result.is_empty(), "default restart result")
	_check(not neutral.is_empty(), "neutral restart result")
	_check(not alternate.is_empty(), "alternate restart result")
	_check(String(result.get("result_hash", "")) == EXPECTED_RESULT_HASH, "default restart hash")
	_check(String(neutral.get("result_hash", "")) == EXPECTED_NEUTRAL_HASH, "neutral restart hash")
	_check(String(alternate.get("result_hash", "")) == EXPECTED_ALT_HASH, "alternate restart hash")
	if failures.is_empty():
		print("ECO.P1B-S3 Restart Replay: PASS (%d assertions) result=%s neutral=%s alt=%s" % [assertions, EXPECTED_RESULT_HASH, EXPECTED_NEUTRAL_HASH, EXPECTED_ALT_HASH])
		quit(0)
		return
	for failure in failures: push_error("ECO.P1B-S3 restart FAIL: %s" % failure)
	quit(1)
func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition: failures.append(label)
