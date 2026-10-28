extends SceneTree

const System = preload("res://scripts/research/fabric_bake0/fabric_composition_r3_general_system_v1.gd")

var assertions := 0
var failures: Array[String] = []

func _check(ok: bool, label: String, detail = null) -> void:
	assertions += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label, " ", detail)

func _model(node_a: String = "a", node_b: String = "b") -> Dictionary:
	return {
		"mobile_index": {"a": 0, "b": 1},
		"mobile_nodes": ["a", "b"],
		"mobile_masses_kg": [1.0, 1.0],
		"coupler_node_id": "a",
		"boundary_voltages_v": {"source": 1.0, "return": 0.0},
		"source_port_id": "source",
		"controls": {"coupling_n_per_a": 1.0, "guard_fraction": 0.8},
		"mechanical_model": {"elements": [{
			"element_id": "spring/ab",
			"node_a": node_a,
			"node_b": node_b,
			"stiffness_n_per_m": 10.0,
			"damping_ns_per_m": 2.0,
			"capacity_n": 100.0,
			"active": true,
		}]},
		"electrical_model": {
			"nodes": [{"node_id": "source"}, {"node_id": "return"}],
			"elements": [{"element_id": "resistor", "node_a": "source", "node_b": "return", "resistance_ohm": 1.0, "active": true}],
		},
		"axis": [1.0, 0.0, 0.0],
		"max_step_s": 0.01,
	}

func _state() -> Dictionary:
	return {
		"time": 0.25,
		"mode": "LIVE",
		"states": {
			"x_0": {"value": 0.3},
			"x_1": {"value": 0.1},
			"v_0": {"value": 0.4},
			"v_1": {"value": -0.1},
			"source_work": {"value": 0.0},
			"external_work": {"value": 0.0},
			"joule_heat": {"value": 0.0},
			"damper_heat": {"value": 0.0},
		},
	}

func _initialize() -> void:
	var forward := System.observe(_model(), _state(), "FULL")
	_check(not forward.has("error_code"), "G2-B signed effort fixture observes", forward)
	if not forward.has("error_code"):
		var expected := 10.0 * (0.3 - 0.1) + 2.0 * (0.4 - (-0.1))
		_check(absf(float(forward.mechanical_observables.efforts_n["spring/ab"]) - expected) < 1.0e-12, "G2-B effort is k*(q_a-q_b)+c*(v_a-v_b)", forward.mechanical_observables.efforts_n)
		_check(absf(float(forward.supports[0].effort_n) - expected) < 1.0e-12, "G2-B support readback uses declared signed effort", forward.supports[0])
		_check(expected > 0.0, "G2-B fixture exercises positive declared direction", expected)
	var reversed := System.observe(_model("b", "a"), _state(), "FULL")
	_check(not reversed.has("error_code"), "G2-B reversed endpoint fixture observes", reversed)
	if not reversed.has("error_code"):
		_check(absf(float(reversed.mechanical_observables.efforts_n["spring/ab"]) + 3.0) < 1.0e-12, "G2-B endpoint reversal flips signed effort only", reversed.mechanical_observables.efforts_n)
	print("G2_SIGNED_EFFORT_ASSERTIONS=", assertions, " FAILURES=", failures.size())
	if failures.is_empty():
		print("FABRIC-HOLDOUT-R4-G2-SIGNED-EFFORT: PASS")
		quit(0)
	else:
		print("G2_SIGNED_EFFORT_FAILURES=", JSON.stringify(failures))
		print("FABRIC-HOLDOUT-R4-G2-SIGNED-EFFORT: FAIL")
		quit(1)
