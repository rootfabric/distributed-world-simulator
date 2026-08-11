extends SceneTree

const Probes = preload("res://scripts/research/ecology/plant_seed_lifecycle_probes_v1.gd")

const EXPECTED_LIFECYCLE_HASH := "88d8b3f53a5233d675eb75f1fe94c017b4f435ca91c34ce145d9b93f3c72d6d1"
const EXPECTED_OFFSPRING_BATCH_HASH := "48d1ba23151ad5cf02f4d0de2ebbf9559da99612c852c6ec97029254159ee5ce"

var assertions := 0
var failures: Array[String] = []

func _init() -> void:
	var run := Probes.reference_run()
	_check(not run.is_empty(), "reference run exists")
	var lifecycle_hash := String(run.get("lifecycle_hash", ""))
	var batch_hash := String(run.get("final_state", {}).get("offspring_batch_hash", ""))
	_check(lifecycle_hash.length() == 64, "lifecycle hash shape")
	_check(batch_hash.length() == 64, "offspring batch hash shape")
	if EXPECTED_LIFECYCLE_HASH != "PENDING":
		_check(lifecycle_hash == EXPECTED_LIFECYCLE_HASH, "exact lifecycle hash")
	if EXPECTED_OFFSPRING_BATCH_HASH != "PENDING":
		_check(batch_hash == EXPECTED_OFFSPRING_BATCH_HASH, "exact offspring batch hash")
	print("ECO.PH4 Restart Replay: %s (%d assertions) lifecycle=%s batch=%s" % ["PASS" if failures.is_empty() else "FAIL", assertions, lifecycle_hash, batch_hash])
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			push_error("ECO.PH4 RESTART FAIL: %s" % failure)
		quit(1)

func _check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)
