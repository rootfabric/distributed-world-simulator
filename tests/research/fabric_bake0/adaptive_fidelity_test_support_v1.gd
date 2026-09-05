extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")
const Selector = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_selector_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
var assertions := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	assertions += 1
	if not condition:
		failures.append(label)

func unpack(result: Dictionary, key: String) -> Dictionary:
	check(result.get("success", false), key + " succeeds: " + str(result.get("error_code", "")))
	return result.get("details", {}).get(key, {})

func candidates(maximum: int = 4) -> Array:
	var rows: Array = []
	for index in range(5):
		rows.append({"fidelity_id": Envelope.LEVELS[index], "available": index <= maximum,
			"source_fresh": true, "reconstruction_ready": true, "passive_stable": true,
			"error_bound": 0.01, "allowed_error_bound": 0.05, "validity_margin": 1.0,
			"guard_margin": 1.0, "pending_refinement_guards": [], "causal_dependencies": [],
			"dormancy_certified": true, "estimated_cost": 100.0 / (index + 1)})
	return rows

func source(index: int = 0, revision: int = 1, dependency: String = "stable", epoch: int = 1) -> Dictionary:
	return SourceRevision.create("CONSTRUCTION", "source/object-%05d" % index, epoch,
		revision, ("source-%d-%d" % [index, revision]).sha256_text(), dependency.sha256_text())

func envelope(current: String, rows: Array) -> Dictionary:
	return unpack(Envelope.compile(current, rows), "envelope")

func decision(env: Dictionary, policy: String = "CHEAPEST_SAFE") -> Dictionary:
	return unpack(Selector.select(env, env["current_fidelity"], policy), "decision")

func reverse_keys(value):
	if typeof(value) == TYPE_DICTIONARY:
		var keys: Array = value.keys()
		keys.reverse()
		var result := {}
		for key in keys:
			result[key] = reverse_keys(value[key])
		return result
	if typeof(value) == TYPE_ARRAY:
		var result: Array = []
		for item in value:
			result.append(reverse_keys(item))
		return result
	return value

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + ": PASS (%d assertions)" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print(label + ": FAIL (%d/%d failed)" % [failures.size(), assertions])
		quit(1)
