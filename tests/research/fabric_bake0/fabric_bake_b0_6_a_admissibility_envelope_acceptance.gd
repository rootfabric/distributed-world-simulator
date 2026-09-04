extends SceneTree

const Envelope = preload("res://scripts/research/fabric_bake0/adaptive_physical_fidelity_envelope_v1.gd")

var assertions := 0
var failures: Array = []

func _initialize() -> void:
	var all_safe := _compile(_base_candidates())
	_check_ok(all_safe, "all-safe envelope")
	var e := _envelope(all_safe)
	_check(e["admissible_fidelities"] == Envelope.LEVELS, "all levels admissible", e["admissible_fidelities"])
	_check(e["minimum_safe_fidelity"] == "DORMANT", "all-safe minimum is DORMANT", e["minimum_safe_fidelity"])
	_check(not e.has("selected_fidelity"), "envelope never selects scheduler fidelity")
	_check(not e.has("allocated_budget"), "envelope never allocates runtime budget")
	_check(String(e["current_fidelity"]) == "DYNAMIC_ROM", "current fidelity reported")
	_check(Envelope.validate_envelope(e)["success"], "compiled envelope validates")

	var causal := _base_candidates()
	causal[4]["causal_dependencies"] = ["dependency/live-load"]
	var causal_result := _compile(causal)
	_check_ok(causal_result, "dormant causal dependency envelope")
	var causal_e := _envelope(causal_result)
	_check(causal_e["minimum_safe_fidelity"] == "HYBRID_BAKE", "causal dependency blocks DORMANT")
	_check(causal_e["admissible_fidelities"] == ["FULL_FABRIC", "STRUCTURAL_BAKE", "DYNAMIC_ROM", "HYBRID_BAKE"], "causal dependency preserves higher levels")
	_check(_row(causal_e, "DORMANT")["rejection_reasons"].has("CAUSAL_DEPENDENCY_ACTIVE"), "DORMANT causal rejection visible")

	var guard := _base_candidates()
	guard[3]["pending_refinement_guards"] = ["guard/high-stress"]
	var guard_result := _compile(guard)
	_check_ok(guard_result, "pending guard envelope")
	var guard_e := _envelope(guard_result)
	_check(guard_e["minimum_safe_fidelity"] == "DYNAMIC_ROM", "HYBRID pending guard stops demotion at DYNAMIC")
	_check(not bool(_row(guard_e, "HYBRID_BAKE")["raw_safe"]), "HYBRID raw unsafe")
	_check(bool(_row(guard_e, "DORMANT")["raw_safe"]), "DORMANT can be independently raw-safe")
	_check(not bool(_row(guard_e, "DORMANT")["effective_safe"]), "DORMANT blocked by unsafe barrier")
	_check(_row(guard_e, "DORMANT")["rejection_reasons"].has("CHEAPER_THAN_UNSAFE_BARRIER"), "monotonic cheaper barrier is explicit")

	var error_case := _base_candidates()
	error_case[2]["error_bound"] = 0.051
	error_case[2]["allowed_error_bound"] = 0.050
	var error_result := _compile(error_case)
	_check_ok(error_result, "error-bound envelope")
	var error_e := _envelope(error_result)
	_check(error_e["minimum_safe_fidelity"] == "STRUCTURAL_BAKE", "ROM error closes ROM and cheaper")
	_check(_row(error_e, "DYNAMIC_ROM")["rejection_reasons"].has("ERROR_BOUND_EXCEEDED"), "ROM error reason visible")
	_check(not bool(_row(error_e, "HYBRID_BAKE")["effective_safe"]), "HYBRID blocked after ROM error")
	_check(not bool(_row(error_e, "DORMANT")["effective_safe"]), "DORMANT blocked after ROM error")

	var reconstruction := _base_candidates()
	reconstruction[1]["reconstruction_ready"] = false
	var reconstruction_result := _compile(reconstruction)
	_check_ok(reconstruction_result, "reconstruction envelope")
	var reconstruction_e := _envelope(reconstruction_result)
	_check(reconstruction_e["admissible_fidelities"] == ["FULL_FABRIC"], "L1 reconstruction loss falls back to FULL only")
	_check(reconstruction_e["minimum_safe_fidelity"] == "FULL_FABRIC", "FULL fail-safe is minimum after L1 loss")
	_check(_row(reconstruction_e, "STRUCTURAL_BAKE")["rejection_reasons"].has("RECONSTRUCTION_NOT_READY"), "reconstruction reason visible")

	var stale_full := _base_candidates()
	stale_full[0]["source_fresh"] = false
	var stale_result := _compile(stale_full)
	_check(not bool(stale_result.get("success", false)), "stale FULL fails closed")
	_check(String(stale_result.get("error_code")) == "NO_SAFE_PHYSICAL_FIDELITY", "stale FULL exact error", stale_result)

	var unavailable_full := _base_candidates()
	unavailable_full[0]["available"] = false
	var unavailable_result := _compile(unavailable_full)
	_check(not bool(unavailable_result.get("success", false)), "unavailable FULL fails closed")
	_check(String(unavailable_result.get("error_code")) == "NO_SAFE_PHYSICAL_FIDELITY", "unavailable FULL exact error", unavailable_result)

	var cheap_unsafe := _base_candidates()
	cheap_unsafe[2]["error_bound"] = 0.09
	cheap_unsafe[2]["estimated_cost"] = 0.000001
	cheap_unsafe[3]["estimated_cost"] = 999999.0
	var cheap_result := _compile(cheap_unsafe)
	_check_ok(cheap_result, "cost-independence unsafe envelope")
	var cheap_e := _envelope(cheap_result)
	_check(cheap_e["minimum_safe_fidelity"] == "STRUCTURAL_BAKE", "cheap unsafe ROM cannot buy admissibility")
	_check(not bool(_row(cheap_e, "DYNAMIC_ROM")["effective_safe"]), "cheap unsafe ROM remains rejected")

	var cost_a := _base_candidates()
	var cost_b := _base_candidates()
	for index in range(cost_b.size()):
		cost_b[index]["estimated_cost"] = 1000000.0 - float(index * 177777)
	var cost_result_a := _compile(cost_a)
	var cost_result_b := _compile(cost_b)
	_check_ok(cost_result_a, "cost profile A")
	_check_ok(cost_result_b, "cost profile B")
	var cost_ea := _envelope(cost_result_a)
	var cost_eb := _envelope(cost_result_b)
	_check(cost_ea["admissible_fidelities"] == cost_eb["admissible_fidelities"], "cost changes do not change safe set")
	_check(cost_ea["minimum_safe_fidelity"] == cost_eb["minimum_safe_fidelity"], "cost changes do not change minimum safe fidelity")
	_check(cost_ea["safety_hash"] == cost_eb["safety_hash"], "cost changes preserve safety hash")
	_check(cost_ea["checksum"] != cost_eb["checksum"], "cost remains observable in full envelope checksum")

	var missing := _base_candidates()
	missing.pop_back()
	var missing_result := Envelope.compile("DYNAMIC_ROM", missing)
	_check(not bool(missing_result.get("success", false)), "missing fidelity rejected")
	_check(String(missing_result.get("error_code")) == "ADAPTIVE_FIDELITY_COMPLETE_LEVEL_SET_REQUIRED", "missing fidelity exact error", missing_result)

	var misordered := _base_candidates()
	var tmp = misordered[1]
	misordered[1] = misordered[2]
	misordered[2] = tmp
	var misordered_result := Envelope.compile("DYNAMIC_ROM", misordered)
	_check(not bool(misordered_result.get("success", false)), "misordered fidelity rejected")
	_check(String(misordered_result.get("error_code")) == "ADAPTIVE_FIDELITY_LEVEL_ORDER_MISMATCH", "misordered fidelity exact error", misordered_result)

	var duplicate_id := _base_candidates()
	duplicate_id[3]["fidelity_id"] = "DYNAMIC_ROM"
	var duplicate_result := Envelope.compile("DYNAMIC_ROM", duplicate_id)
	_check(not bool(duplicate_result.get("success", false)), "duplicate fidelity identity rejected")
	_check(String(duplicate_result.get("error_code")) == "ADAPTIVE_FIDELITY_LEVEL_ORDER_MISMATCH", "duplicate fidelity exact error", duplicate_result)

	var invalid_current := Envelope.compile("CHEAPEST", _base_candidates())
	_check(not bool(invalid_current.get("success", false)), "unknown current fidelity rejected")
	_check(String(invalid_current.get("error_code")) == "INVALID_CURRENT_PHYSICAL_FIDELITY", "unknown current fidelity exact error", invalid_current)

	print("B06A_SAFETY_HASH=%s" % String(e["safety_hash"]))
	print("B06A_ENVELOPE_CHECKSUM=%s" % String(e["checksum"]))
	_finish()

func _base_candidates() -> Array:
	var output: Array = []
	for index in range(Envelope.LEVELS.size()):
		output.append({
			"fidelity_id": Envelope.LEVELS[index],
			"available": true,
			"source_fresh": true,
			"reconstruction_ready": true,
			"passive_stable": true,
			"error_bound": 0.0 if index == 0 else 0.01 + 0.002 * index,
			"allowed_error_bound": 0.05,
			"validity_margin": 1.0 - 0.1 * index,
			"guard_margin": 0.8 - 0.1 * index,
			"pending_refinement_guards": [],
			"causal_dependencies": [],
			"dormancy_certified": true,
			"estimated_cost": 100.0 / float(index + 1),
		})
	return output

func _compile(candidates: Array) -> Dictionary:
	return Envelope.compile("DYNAMIC_ROM", candidates)

func _envelope(result: Dictionary) -> Dictionary:
	return result.get("details", {}).get("envelope", {})

func _row(envelope: Dictionary, fidelity_id: String) -> Dictionary:
	for raw_row in envelope["raw_admissibility"]:
		if String(raw_row["fidelity_id"]) == fidelity_id:
			return raw_row
	return {}

func _check_ok(result: Dictionary, message: String) -> void:
	_check(bool(result.get("success", false)), message, result)

func _check(condition: bool, message: String, details = null) -> void:
	assertions += 1
	if not condition:
		failures.append("%s :: %s" % [message, str(details)])

func _finish() -> void:
	if failures.is_empty():
		print("FABRIC B0.6-A Physical Fidelity Admissibility Envelope: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error("B0.6-A ASSERTION FAILED: %s" % failure)
	print("FABRIC B0.6-A Physical Fidelity Admissibility Envelope: FAIL (%d/%d failed)" % [failures.size(), assertions])
	quit(1)
