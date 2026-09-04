extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Ordering = preload("res://scripts/research/fabric_bake0/mixed_representation_invalidation_ordering_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_d_fixture.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var b := Fixture.build()
	_require(bool(b.get("success", false)), "fixture builds", b)
	if _failed: _finish(); return
	var t: Dictionary = b["trace"]
	_require(bool(Ordering.validate_invalidation(t).get("success", false)), "trace validates")
	_require(String(t["event_id"]) == String(b["commit"]["event_id"]), "event identity preserved")
	_require(String(t["previous_source_frontier_hash"]) == String(b["commit"]["previous_source_frontier_hash"]), "previous frontier exact")
	_require(String(t["current_source_frontier_hash"]) == String(b["commit"]["current_source_frontier_hash"]), "current frontier exact")
	_require(String(t["route_hash"]) == String(b["route"]["route_hash"]), "route identity exact")
	_require(String(t["commit_hash"]) == String(b["commit"]["commit_hash"]), "commit identity exact")
	_require(String(t["old_subject_hash"]) == String(b["mixed"]["subject"]["subject_hash"]), "old subject exact")
	_require(String(t["old_ownership_contract_hash"]) == String(b["mixed"]["ownership"]["contract_hash"]), "old ownership exact")
	_require(String(t["ordering_qualification"]) == Ordering.QUALIFICATION, "ordering qualification exact")

	for i in range(Ordering.INVALIDATION_PHASES.size()):
		var p: Dictionary = t["phase_records"][i]
		_require(int(p["phase_index"]) == i, "phase index %d exact" % i)
		_require(String(p["phase_kind"]) == Ordering.INVALIDATION_PHASES[i], "phase kind %d exact" % i)
		_require(U.is_lower_hex_64(p["proof_hash"]), "phase proof %d canonical hash" % i)
		_require(not String(p["proof_hash"]).is_empty(), "phase proof %d nonempty" % i)

	_require(String(b["guard_result"]["status"]) == "STRUCTURAL_REFINEMENT_REQUIRED", "guard triggers before break")
	_require(String(b["local_transition"]["status"]) == "STRUCTURAL_BOUNDED_LOCAL_UNBAKE_READY", "local FULL refinement ready before canonical mutation")
	_require(String(b["commit"]["commit_state"]) == "COMMITTED", "canonical commit confirmed")
	_require(String(b["commit"]["ledger_append_event_id"]) == String(t["event_id"]), "canonical event appended exactly once")

	for name in ["structural_invalidation", "contact_invalidation", "dynamic_invalidation"]:
		var inv: Dictionary = b[name]
		_require(String(inv["state_after"]) == "STALE", "%s marks stale" % name)
		_require(String(inv["reason"]) == "SOURCE_REVISION", "%s reason source revision" % name)
		_require(String(inv["previous_source_frontier_hash"]) == String(t["previous_source_frontier_hash"]), "%s previous frontier exact" % name)
		_require(String(inv["current_source_frontier_hash"]) == String(t["current_source_frontier_hash"]), "%s current frontier exact" % name)
		_require(U.is_lower_hex_64(inv["checksum"]), "%s checksum canonical" % name)
		_require(not String(inv["checksum"]).is_empty(), "%s checksum nonempty" % name)

	_require(String(b["structural_stale"].get("error_code", "")) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "old structural execution forbidden")
	_require(String(b["contact_stale"].get("code", "")) == "B0_3_EXECUTION_FORBIDDEN", "old contact execution forbidden")
	_require(String(b["contact_stale"].get("b0_3_gate", {}).get("error_code", "")) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "contact own gate proves stale")
	_require(String(b["dynamic_stale"].get("error_code", "")) == "DYNAMIC_ROM_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "old dynamic ROM execution forbidden")
	_require(String(b["dynamic_stale"].get("details", {}).get("cause", b["dynamic_stale"].get("cause", ""))) == "STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "dynamic stale cause exact")
	_require(String(b["hybrid_stale"].get("error_code", "")) == "B0_5_A_MODE_EXECUTION_FAILED", "old hybrid execution forbidden")
	_require(String(b["hybrid_stale"].get("details", {}).get("cause", b["hybrid_stale"].get("cause", ""))) == "DYNAMIC_ROM_PHYSICAL_BAKE_EXECUTION_FORBIDDEN", "hybrid stale cause chains to ROM")
	_require(String(b["stale_mode_resolution"].get("details", {}).get("action", "")) == "FALLBACK", "stale hybrid cache falls back")
	_require(String(b["stale_mode_resolution"].get("details", {}).get("fallback", "")) == "FULL", "stale hybrid fallback is FULL")
	_require(String(b["stale_mode_resolution"].get("details", {}).get("reason", "")) == "SOURCE_FRONTIER_CHANGED", "stale hybrid reason exact")

	var tx: Dictionary = b["transaction"]
	var diag: Dictionary = b["topology_runtime"]["diagnostics"]
	_require(tx["rebaked_components"].size() == 2, "topology split produces two rebaked components")
	_require(int(diag["split_component_count"]) == 2, "runtime split component count exact")
	_require(int(diag["invalidated_reduced_piece_count"]) == 3, "runtime invalidates old reduced pieces")
	_require(int(diag["executable_physical_bake_artifact_count"]) == 2, "two fresh structural artifacts executable")
	_require(bool(diag["physical_bake_artifact_emitted"]), "fresh structural artifacts emitted")
	_require(float(diag["post_split_reduction_ratio"]) == 250.0, "post-split reduction ratio exact")
	_require(float(diag["max_state_handoff_error"]) <= 1.0e-8, "state handoff within contract")
	_require(int(diag["duplicate_event_count"]) == 0, "no duplicate event")
	_require(bool(diag["b0_2_complete"]), "B0.2-E split/rebake complete")

	var swapped := t.duplicate(true)
	var tmp = swapped["phase_records"][2]
	swapped["phase_records"][2] = swapped["phase_records"][3]
	swapped["phase_records"][3] = tmp
	_rehash(swapped)
	var swapped_check := Ordering.validate_invalidation(swapped)
	_require(not bool(swapped_check.get("success", false)), "commit/invalidation phase swap rejected")
	_require(String(swapped_check.get("error_code", "")) == "BRIDGE2_D_PHASE_INDEX_OUT_OF_ORDER", "phase swap rejection code exact")

	var same_frontier := t.duplicate(true)
	same_frontier["current_source_frontier_hash"] = same_frontier["previous_source_frontier_hash"]
	_rehash(same_frontier)
	var same_check := Ordering.validate_invalidation(same_frontier)
	_require(not bool(same_check.get("success", false)), "no-frontier-advance trace rejected")
	_require(String(same_check.get("error_code", "")) == "BRIDGE2_D_FRONTIER_MUST_ADVANCE", "frontier advance rejection exact")

	var bad_proof := t.duplicate(true)
	bad_proof["phase_records"][5]["proof_hash"] = "not-a-hash"
	_rehash(bad_proof)
	var proof_check := Ordering.validate_invalidation(bad_proof)
	_require(not bool(proof_check.get("success", false)), "invalid stale-rejection proof rejected")
	_require(String(proof_check.get("error_code", "")) == "BRIDGE2_D_INVALID_PHASE_PROOF", "bad proof rejection code exact")

	_finish(t)

func _rehash(v: Dictionary) -> void:
	var p := v.duplicate(true)
	p.erase("trace_hash")
	p.erase("checksum")
	v["trace_hash"] = U.canonical_hash(p)
	v["checksum"] = U.compute_checksum(v)

func _require(condition: bool, label: String, details = null) -> void:
	if condition:
		_checks += 1
		return
	_failed = true
	printerr("FABRIC-BAKE BRIDGE-2-D FAILURE: %s details=%s" % [label, str(details)])

func _finish(trace: Dictionary = {}) -> void:
	if _failed:
		printerr("FABRIC-BAKE BRIDGE-2-D Invalidation Ordering Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC-BAKE BRIDGE-2-D Invalidation Ordering Acceptance: PASS (%d assertions) trace=%s" % [_checks, String(trace.get("trace_hash", ""))])
	quit(0)
