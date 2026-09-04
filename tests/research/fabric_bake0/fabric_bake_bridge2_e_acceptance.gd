extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Replay = preload("res://scripts/research/fabric_bake0/mixed_representation_replay_certificate_v1.gd")

var _checks := 0
var _failed := false

func _initialize() -> void:
	var ia := _load_capsule("BRIDGE2_E_INVALIDATION_A")
	var ib := _load_capsule("BRIDGE2_E_INVALIDATION_B")
	var ra := _load_capsule("BRIDGE2_E_RECOVERY_A")
	var rb := _load_capsule("BRIDGE2_E_RECOVERY_B")
	_require(not ia.is_empty() and not ib.is_empty() and not ra.is_empty() and not rb.is_empty(), "all four independent capsules loaded")
	if _failed: _finish(); return

	_require(bool(Replay.validate_invalidation(ia).get("success", false)), "invalidation A validates")
	_require(bool(Replay.validate_invalidation(ib).get("success", false)), "invalidation B validates")
	_require(bool(Replay.validate_recovery(ra).get("success", false)), "recovery A validates")
	_require(bool(Replay.validate_recovery(rb).get("success", false)), "recovery B validates")

	var ca_result := Replay.compose(ia, ra)
	var cb_result := Replay.compose(ib, rb)
	_require(bool(ca_result.get("success", false)), "run A composes into full replay certificate", ca_result)
	_require(bool(cb_result.get("success", false)), "run B composes into full replay certificate", cb_result)
	if _failed: _finish(); return
	var ca: Dictionary = ca_result["details"]["certificate"]
	var cb: Dictionary = cb_result["details"]["certificate"]
	_require(bool(Replay.validate_certificate(ca).get("success", false)), "certificate A validates")
	_require(bool(Replay.validate_certificate(cb).get("success", false)), "certificate B validates")

	_require(String(ia["capsule_hash"]) == String(ib["capsule_hash"]), "independent invalidation capsule identity deterministic")
	_require(String(ra["capsule_hash"]) == String(rb["capsule_hash"]), "independent recovery capsule identity deterministic")
	_require(String(ia["event_id"]) == String(ib["event_id"]), "event id deterministic")
	_require(int(ia["event_sequence"]) == int(ib["event_sequence"]), "event sequence deterministic")
	_require(String(ia["event_hash"]) == String(ib["event_hash"]), "event hash deterministic")
	_require(String(ia["route_hash"]) == String(ib["route_hash"]), "route identity deterministic")
	_require(String(ia["commit_hash"]) == String(ib["commit_hash"]), "commit identity deterministic")
	_require(String(ia["previous_source_frontier_hash"]) == String(ib["previous_source_frontier_hash"]), "previous frontier deterministic")
	_require(String(ia["current_source_frontier_hash"]) == String(ib["current_source_frontier_hash"]), "current frontier deterministic")
	_require(String(ia["ordering_trace_hash"]) == String(ib["ordering_trace_hash"]), "invalidation ordering trace deterministic")
	_require(ia["stale_records"] == ib["stale_records"], "stale set and rejection causes deterministic")
	_require(ia["invalidation_hashes"] == ib["invalidation_hashes"], "invalidation identities deterministic")
	_require(String(ia["transaction_checksum"]) == String(ib["transaction_checksum"]), "B0.2-E transaction deterministic")
	_require(ia["split_records"] == ib["split_records"], "split component/artifact identities deterministic")
	_require(ia["split_state_records"] == ib["split_state_records"], "post-split reduced states deterministic")
	_require(String(ia["final_structural_state_hash"]) == String(ib["final_structural_state_hash"]), "post-split structural state deterministic")
	_require(String(ra["fresh_ownership_contract_hash"]) == String(rb["fresh_ownership_contract_hash"]), "fresh ownership rebind deterministic")
	_require(ra["recovery_records"] == rb["recovery_records"], "recovery actions and fresh identity sets deterministic")
	_require(String(ra["fresh_full_model_hash"]) == String(rb["fresh_full_model_hash"]), "fresh FULL identity deterministic")
	_require(ra["fresh_structural_artifact_hashes"] == rb["fresh_structural_artifact_hashes"], "fresh structural artifacts deterministic")
	_require(String(ra["fresh_dynamic_artifact_hash"]) == String(rb["fresh_dynamic_artifact_hash"]), "fresh ROM artifact deterministic")
	_require(String(ra["fresh_dynamic_session_hash"]) == String(rb["fresh_dynamic_session_hash"]), "fresh ROM session deterministic")
	_require(String(ra["fresh_hybrid_package_hash"]) == String(rb["fresh_hybrid_package_hash"]), "fresh hybrid package deterministic")
	_require(String(ra["fresh_hybrid_session_hash"]) == String(rb["fresh_hybrid_session_hash"]), "fresh hybrid session deterministic")
	_require(String(ra["final_recovery_state_hash"]) == String(rb["final_recovery_state_hash"]), "final recovery state deterministic")
	_require(String(ca["final_mixed_state_hash"]) == String(cb["final_mixed_state_hash"]), "final mixed state deterministic")
	_require(String(ca["certificate_hash"]) == String(cb["certificate_hash"]), "full replay certificate deterministic")
	var compared := Replay.compare_replays(ca, cb)
	_require(bool(compared.get("success", false)), "full field-by-field replay comparison passes", compared)

	var tampered_i := ia.duplicate(true)
	tampered_i["route_hash"] = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	_rehash_capsule(tampered_i)
	var tampered_ca_result := Replay.compose(tampered_i, ra)
	_require(bool(tampered_ca_result.get("success", false)), "route-tampered capsule still composes as structurally valid")
	if bool(tampered_ca_result.get("success", false)):
		var mismatch := Replay.compare_replays(ca, tampered_ca_result["details"]["certificate"])
		_require(not bool(mismatch.get("success", false)), "route nondeterminism is rejected")
		_require(String(mismatch.get("error_code", "")) == "BRIDGE2_E_REPLAY_MISMATCH", "route mismatch rejection code exact")
		_require(String(mismatch.get("details", {}).get("field", "")) == "route_hash", "route mismatch field exact")

	var tampered_split := ia.duplicate(true)
	tampered_split["split_records"][0]["physical_artifact_hash"] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
	_rehash_split_record(tampered_split["split_records"][0])
	_rehash_capsule(tampered_split)
	var bad_link := Replay.compose(tampered_split, ra)
	_require(not bool(bad_link.get("success", false)), "fresh structural artifact drift breaks replay linkage")
	_require(String(bad_link.get("error_code", "")) == "BRIDGE2_E_STRUCTURAL_RECOVERY_LINK_MISMATCH", "structural linkage rejection exact")

	var tampered_r := ra.duplicate(true)
	tampered_r["fresh_execution_signature_hash"] = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
	tampered_r["final_recovery_state_hash"] = U.canonical_hash({
		"ownership": tampered_r["fresh_ownership_contract_hash"],
		"recovery_records": tampered_r["recovery_records"],
		"fresh_execution_signature_hash": tampered_r["fresh_execution_signature_hash"],
	})
	_rehash_capsule(tampered_r)
	var tampered_cb := Replay.compose(ia, tampered_r)
	_require(bool(tampered_cb.get("success", false)), "execution-drift capsule composes as structurally valid")
	if bool(tampered_cb.get("success", false)):
		var mismatch2 := Replay.compare_replays(ca, tampered_cb["details"]["certificate"])
		_require(not bool(mismatch2.get("success", false)), "fresh execution identity drift rejected")
		_require(String(mismatch2.get("error_code", "")) == "BRIDGE2_E_REPLAY_MISMATCH", "execution mismatch rejection code exact")

	_finish(ca)

func _load_capsule(env_name: String) -> Dictionary:
	var path := OS.get_environment(env_name)
	if path.is_empty() or not FileAccess.file_exists(path):
		printerr("BRIDGE-2-E missing capsule file env=%s path=%s" % [env_name, path])
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func _rehash_split_record(v: Dictionary) -> void:
	var p := v.duplicate(true)
	p.erase("split_hash")
	v["split_hash"] = U.canonical_hash(p)

func _rehash_capsule(v: Dictionary) -> void:
	var p := v.duplicate(true)
	p.erase("capsule_hash")
	p.erase("checksum")
	v["capsule_hash"] = U.canonical_hash(p)
	v["checksum"] = U.compute_checksum(v)

func _require(condition: bool, label: String, details = null) -> void:
	if condition:
		_checks += 1
		return
	_failed = true
	printerr("FABRIC-BAKE BRIDGE-2-E FAILURE: %s details=%s" % [label, str(details)])

func _finish(certificate: Dictionary = {}) -> void:
	if _failed:
		printerr("FABRIC-BAKE BRIDGE-2-E Deterministic Mixed Replay Acceptance: FAIL (%d successful assertions)" % _checks)
		quit(1)
		return
	print("FABRIC-BAKE BRIDGE-2-E Deterministic Mixed Replay Acceptance: PASS (%d assertions) certificate=%s final=%s" % [
		_checks, String(certificate.get("certificate_hash", "")), String(certificate.get("final_mixed_state_hash", ""))
	])
	quit(0)
