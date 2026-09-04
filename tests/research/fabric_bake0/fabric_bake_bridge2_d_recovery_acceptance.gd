extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Ordering = preload("res://scripts/research/fabric_bake0/mixed_representation_invalidation_ordering_v1.gd")
const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_bridge2_d_rebind_fixture.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var b := Fixture.build()
	_require(bool(b.get("success", false)), "recovery fixture builds", b)
	if _failed: _finish(); return
	var t: Dictionary = b["trace"]
	_require(bool(Ordering.validate_recovery(t).get("success", false)), "recovery trace validates")
	_require(String(t["event_id"]) == String(b["broken"]["event"]["event_id"]), "event identity exact")
	_require(String(t["current_source_frontier_hash"]) == String(b["broken"]["current_frontier"]["frontier_hash"]), "current frontier exact")
	_require(String(t["old_ownership_contract_hash"]) == String(b["old_subject"]["contract"]["contract_hash"]), "old ownership exact")
	_require(String(t["fresh_ownership_contract_hash"]) == String(b["fresh_ownership"]["contract_hash"]), "fresh ownership exact")
	_require(String(t["old_ownership_contract_hash"]) != String(t["fresh_ownership_contract_hash"]), "ownership rebind advances identity")

	for i in range(Ordering.RECOVERY_PHASES.size()):
		var p: Dictionary = t["phase_records"][i]
		_require(int(p["phase_index"]) == i + Ordering.INVALIDATION_PHASES.size(), "recovery phase index exact")
		_require(String(p["phase_kind"]) == Ordering.RECOVERY_PHASES[i], "recovery phase kind exact")
		_require(U.is_lower_hex_64(p["proof_hash"]), "recovery proof canonical")
		_require(not String(p["proof_hash"]).is_empty(), "recovery proof nonempty")

	var records := {}
	for r in t["recovery_records"]:
		records[String(r["representation_kind"])] = r
	for kind in ["FULL", "STRUCTURAL_BAKE", "CONTACT_BAKE", "DYNAMIC_ROM", "HYBRID_BAKE"]:
		_require(records.has(kind), "%s recovery record present" % kind)
		if records.has(kind):
			var r: Dictionary = records[kind]
			_require(U.is_lower_hex_64(r["recovery_hash"]), "%s recovery hash canonical" % kind)
			_require(not String(r["recovery_action"]).is_empty(), "%s recovery action explicit" % kind)
			_require(Ordering.FRESH_STATES.has(String(r["fresh_execution_state"])), "%s fresh state allowed" % kind)
			_require(r["fresh_identity_hashes"] == Array(r["fresh_identity_hashes"]).duplicate(true), "%s identities materialized" % kind)

	_require(String(records["FULL"]["fresh_execution_state"]) == "FRESH_EXECUTABLE", "FULL fresh execution resumes")
	_require(records["FULL"]["fresh_identity_hashes"].size() == 1, "FULL has one fresh identity")
	_require(String(records["STRUCTURAL_BAKE"]["fresh_execution_state"]) == "SPLIT_FRESH_EXECUTABLE", "structural split artifacts executable")
	_require(records["STRUCTURAL_BAKE"]["fresh_identity_hashes"].size() == 2, "structural recovery has two artifacts")
	_require(String(records["CONTACT_BAKE"]["fresh_execution_state"]) == "DEFERRED_REDERIVE", "contact stays fail-closed until attachment mapping")
	_require(records["CONTACT_BAKE"]["fresh_identity_hashes"].is_empty(), "contact does not invent post-split artifact")
	_require(String(records["DYNAMIC_ROM"]["fresh_execution_state"]) == "ACTIVE", "fresh ROM active")
	_require(records["DYNAMIC_ROM"]["fresh_identity_hashes"].size() == 1, "fresh ROM has one artifact")
	_require(String(records["HYBRID_BAKE"]["fresh_execution_state"]) == "ACTIVE", "fresh hybrid active")
	_require(records["HYBRID_BAKE"]["fresh_identity_hashes"].size() == 1, "fresh hybrid has one package")

	_require(int(b["topology_runtime"]["diagnostics"]["executable_physical_bake_artifact_count"]) == 2, "two structural split artifacts remain executable")
	_require(bool(b["rebound"]["dynamic_step"].get("success", false)), "fresh ROM step succeeds")
	_require(String(b["rebound"]["dynamic_step"].get("details", {}).get("physical_artifact_id", "")) == "bake/bridge2-d-dynamic-current", "fresh ROM artifact identity exact")
	_require(String(b["rebound"]["hybrid_resolution"].get("details", {}).get("action", "")) == "LAZY_COMPILED", "hybrid mode lazily recompiled")
	_require(String(b["rebound"]["hybrid_step"].get("details", {}).get("status", "")) == "B0_5_A_FLOW_ACCEPTED", "fresh hybrid execution resumes")

	var no_rebind := t.duplicate(true)
	no_rebind["fresh_ownership_contract_hash"] = no_rebind["old_ownership_contract_hash"]
	_rehash(no_rebind)
	var no_rebind_check := Ordering.validate_recovery(no_rebind)
	_require(not bool(no_rebind_check.get("success", false)), "recovery without ownership rebind rejected")
	_require(String(no_rebind_check.get("error_code", "")) == "BRIDGE2_D_OWNERSHIP_REBIND_REQUIRED", "ownership rebind rejection exact")

	var fake_contact := t.duplicate(true)
	for r in fake_contact["recovery_records"]:
		if String(r["representation_kind"]) == "CONTACT_BAKE":
			r["fresh_identity_hashes"] = ["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
			r["fresh_execution_state"] = "ACTIVE"
			r["recovery_hash"] = U.canonical_hash(_without(r, ["recovery_hash"]))
			break
	_rehash(fake_contact)
	var contact_check := Ordering.validate_recovery(fake_contact)
	_require(not bool(contact_check.get("success", false)), "contact cannot invent post-split attachment")
	_require(String(contact_check.get("error_code", "")) == "BRIDGE2_D_CONTACT_RECOVERY_CONTRACT_MISMATCH", "contact fail-closed rejection exact")

	_finish(t)

func _without(v: Dictionary, fields: Array) -> Dictionary:
	var p := v.duplicate(true)
	for f in fields: p.erase(f)
	return p

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
	printerr("FABRIC-BAKE BRIDGE-2-D RECOVERY FAILURE: %s details=%s" % [label, str(details)])

func _finish(trace: Dictionary = {}) -> void:
	if _failed:
		printerr("FABRIC-BAKE BRIDGE-2-D Recovery Ordering Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC-BAKE BRIDGE-2-D Recovery Ordering Acceptance: PASS (%d assertions) trace=%s" % [_checks, String(trace.get("trace_hash", ""))])
	quit(0)
