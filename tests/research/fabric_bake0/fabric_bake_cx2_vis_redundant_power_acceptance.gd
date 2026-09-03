extends SceneTree

const Observation = preload("res://scripts/research/fabric_bake0/cx2_vis_redundant_power_observation_v1.gd")
const Complex1A = preload("res://tests/research/fabric_bake0/fabric_bake_complex1a_fixture.gd")

var _checks := 0

func _initialize() -> void:
	var result := Observation.build()
	_check(bool(result.get("success", false)))
	_check(String(result.get("schema", "")) == Observation.SCHEMA)
	_check(int(result["scale"]) == 2000)
	_check(result["parts"].size() == 2000)
	_check(String(result["support_a"]) != String(result["support_b"]))
	_check(String(result["support_a"]) == "bond/b0-2-1007")
	_check(String(result["event_a"]) == "topology-event/complex0-2000-break")
	_check(String(result["duplicate_event_error"]) == "COMPLEX1A_STRUCTURAL_EVENT_ALREADY_APPLIED")
	_check(not String(result["checksum"]).is_empty())

	var stages: Array = result["stages"]
	_check(stages.size() == 4)
	_check(String(stages[0]["name"]) == "BOTH_PATHS")
	_check(Array(stages[0]["active_functional_bond_ids"]) == ["wire/path-a", "wire/path-b"])
	_check(bool(stages[0]["lamp"]["on"]))

	_check(String(stages[1]["name"]) == "BREAK_A")
	_check(Array(stages[1]["active_functional_bond_ids"]) == ["wire/path-b"])
	_check(bool(stages[1]["lamp"]["on"]))
	_check(absf(float(stages[1]["lamp"]["voltage"]) - Complex1A.SOURCE_VOLTAGE) <= Complex1A.EPSILON)

	_check(String(stages[2]["name"]) == "BREAK_B")
	_check(Array(stages[2]["active_functional_bond_ids"]) == ["wire/path-a"])
	_check(bool(stages[2]["lamp"]["on"]))
	_check(absf(float(stages[2]["lamp"]["voltage"]) - Complex1A.SOURCE_VOLTAGE) <= Complex1A.EPSILON)

	_check(String(stages[3]["name"]) == "BREAK_A_PLUS_B")
	_check(Array(stages[3]["active_functional_bond_ids"]).is_empty())
	_check(not bool(stages[3]["lamp"]["on"]))
	_check(absf(float(stages[3]["lamp"]["voltage"])) <= Complex1A.EPSILON)
	_check(absf(float(stages[3]["lamp"]["current"])) <= Complex1A.EPSILON)
	_check(absf(float(stages[3]["lamp"]["absorbed_power"])) <= Complex1A.EPSILON)

	var reverse: Dictionary = result["reverse_order"]
	_check(Array(reverse["active_functional_bond_ids"]).is_empty())
	_check(not bool(reverse["lamp"]["on"]))
	_check(String(reverse["network_hash"]) == String(stages[3]["network_hash"]))
	_check(reverse["lamp"] == stages[3]["lamp"])

	var unrelated: Dictionary = result["unrelated"]
	_check(Array(unrelated["active_functional_bond_ids"]) == ["wire/path-a", "wire/path-b"])
	_check(bool(unrelated["lamp"]["on"]))

	for stage in stages:
		_check(float(stage["max_balance_residual"]) <= Complex1A.EPSILON)
		_check(float(stage["max_power_residual"]) <= Complex1A.EPSILON)

	var packed := load("res://scenes/labs/fabric/cx2_redundant_power_paths.tscn")
	_check(packed is PackedScene)
	var scene := (packed as PackedScene).instantiate()
	_check(scene != null)
	_check(String(scene.name) == "CX2VISRedundantPowerPaths")
	scene.free()

	print("FABRIC CX2-VIS Redundant Power Acceptance: PASS (%d assertions) A->ON B->ON A+B->OFF" % _checks)
	quit(0)

func _check(condition: bool) -> void:
	assert(condition)
	_checks += 1
