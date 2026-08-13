extends SceneTree

const Experiment = preload("res://scripts/research/ecology/plant_world_save_restart_experiment_v1.gd")
const Persistence = preload("res://scripts/research/ecology/plant_world_persistence_v1.gd")
const Biogeography = preload("res://scripts/research/ecology/plant_long_horizon_biogeography_v1.gd")
const P2_7 = preload("res://scripts/research/ecology/plant_lineage_divergence_experiment_v1.gd")

func _init() -> void:
	var parent := P2_7.run()
	_require(not parent.is_empty(), "P2_7_PARENT_EMPTY")
	_require(String(parent.get("aggregate_hash", "")) == Experiment.ACCEPTED_P2_7_HASH, "P2_7_PARENT_HASH_MISMATCH")
	print("ECO.EVO1-P2.8 stage=P2_7_PARENT_OK hash=%s" % String(parent.get("aggregate_hash", "")))

	var fixture := Experiment._fixture(parent)
	_require(not fixture.is_empty(), "FIXTURE_EMPTY")
	print("ECO.EVO1-P2.8 stage=FIXTURE_OK")

	var baseline := Biogeography.simulate(
		fixture["initial_patch_states"],
		fixture["strategies"],
		Experiment.YEARS,
		fixture["source_patch_ids"],
		fixture["transport_schedule"],
		fixture["disturbance_schedule"]
	)
	_require(not baseline.is_empty(), "P2_6_BASELINE_EMPTY")
	var expected_result_hash := String(baseline.get("result_hash", ""))
	var expected_state_hash := Persistence.value_hash(baseline.get("final_states", {}))
	var expected_diagnostics_hash := Persistence.value_hash(parent)
	_require(expected_result_hash.length() == 64, "P2_6_BASELINE_HASH_INVALID")
	_require(expected_state_hash.length() == 64, "P2_6_FINAL_STATE_HASH_INVALID")
	_require(expected_diagnostics_hash.length() == 64, "P2_7_DIAGNOSTICS_HASH_INVALID")
	print("ECO.EVO1-P2.8 stage=BASELINE_OK result=%s state=%s diagnostics=%s" % [expected_result_hash, expected_state_hash, expected_diagnostics_hash])

	var uninterrupted := Persistence.create_world(
		fixture["initial_patch_states"], fixture["strategies"], Experiment.YEARS,
		fixture["source_patch_ids"], fixture["transport_schedule"], fixture["disturbance_schedule"], parent
	)
	_require(not uninterrupted.is_empty(), "CREATE_WORLD_UNINTERRUPTED_EMPTY")
	_require(Persistence.validate_world(uninterrupted), "CREATE_WORLD_UNINTERRUPTED_INVALID")
	print("ECO.EVO1-P2.8 stage=CREATE_WORLD_OK world=%s" % Persistence.world_hash(uninterrupted))

	uninterrupted = Persistence.advance_to(uninterrupted, Experiment.YEARS)
	_require(not uninterrupted.is_empty(), "ADVANCE_UNINTERRUPTED_TO_30_EMPTY")
	var uninterrupted_result := Persistence.to_biogeography_result(uninterrupted)
	_require(not uninterrupted_result.is_empty(), "UNINTERRUPTED_RESULT_EMPTY")
	var uninterrupted_hash := String(uninterrupted_result.get("result_hash", ""))
	print("ECO.EVO1-P2.8 stage=UNINTERRUPTED_OK baseline=%s stateful=%s" % [expected_result_hash, uninterrupted_hash])
	_require(uninterrupted_hash == expected_result_hash, "UNINTERRUPTED_P2_6_HASH_MISMATCH")

	var evidence_context := {
		"accepted_p2_7_aggregate_hash": Experiment.ACCEPTED_P2_7_HASH,
		"expected_p2_6_result_hash": expected_result_hash,
		"expected_final_state_hash": expected_state_hash,
		"expected_lineage_diagnostics_hash": expected_diagnostics_hash,
		"cut_a_year": Experiment.CUT_A_YEAR,
		"cut_b_year": Experiment.CUT_B_YEAR,
		"total_years": Experiment.YEARS,
	}
	var restarted := Persistence.create_world(
		fixture["initial_patch_states"], fixture["strategies"], Experiment.YEARS,
		fixture["source_patch_ids"], fixture["transport_schedule"], fixture["disturbance_schedule"], parent
	)
	_require(not restarted.is_empty(), "CREATE_WORLD_RESTART_EMPTY")
	restarted = Persistence.advance_to(restarted, Experiment.CUT_A_YEAR)
	_require(not restarted.is_empty(), "ADVANCE_TO_CUT_A_EMPTY")
	print("ECO.EVO1-P2.8 stage=CUT_A_STATE_OK year=%d world=%s" % [int(restarted.get("current_year", -1)), Persistence.world_hash(restarted)])

	var checkpoint_a := Persistence.serialize_checkpoint(restarted, evidence_context)
	if checkpoint_a.is_empty():
		_audit_value(restarted, "world")
		_audit_value(evidence_context, "evidence")
		_fail("SERIALIZE_CHECKPOINT_A_EMPTY")
	print("ECO.EVO1-P2.8 stage=SERIALIZE_A_OK bytes=%d" % checkpoint_a.to_utf8_buffer().size())
	var checkpoint_a_document := Persistence.deserialize_checkpoint(checkpoint_a)
	if checkpoint_a_document.is_empty():
		_debug_decode(checkpoint_a, restarted, evidence_context, "A")
		_fail("DESERIALIZE_CHECKPOINT_A_EMPTY")
	print("ECO.EVO1-P2.8 stage=DESERIALIZE_A_OK checkpoint=%s" % String(checkpoint_a_document.get("checkpoint_hash", "")))

	var after_a: Dictionary = checkpoint_a_document["world"]
	after_a = Persistence.advance_to(after_a, Experiment.CUT_B_YEAR)
	_require(not after_a.is_empty(), "ADVANCE_TO_CUT_B_EMPTY")
	print("ECO.EVO1-P2.8 stage=CUT_B_STATE_OK year=%d world=%s" % [int(after_a.get("current_year", -1)), Persistence.world_hash(after_a)])
	var checkpoint_b := Persistence.serialize_checkpoint(after_a, evidence_context)
	if checkpoint_b.is_empty():
		_audit_value(after_a, "world_b")
		_fail("SERIALIZE_CHECKPOINT_B_EMPTY")
	var checkpoint_b_document := Persistence.deserialize_checkpoint(checkpoint_b)
	if checkpoint_b_document.is_empty():
		_debug_decode(checkpoint_b, after_a, evidence_context, "B")
		_fail("DESERIALIZE_CHECKPOINT_B_EMPTY")
	print("ECO.EVO1-P2.8 stage=DESERIALIZE_B_OK checkpoint=%s" % String(checkpoint_b_document.get("checkpoint_hash", "")))

	var after_b: Dictionary = checkpoint_b_document["world"]
	after_b = Persistence.advance_to(after_b, Experiment.YEARS)
	_require(not after_b.is_empty(), "ADVANCE_AFTER_CUT_B_TO_30_EMPTY")
	var restarted_result := Persistence.to_biogeography_result(after_b)
	_require(not restarted_result.is_empty(), "RESTARTED_RESULT_EMPTY")
	var restarted_hash := String(restarted_result.get("result_hash", ""))
	print("ECO.EVO1-P2.8 stage=RESTARTED_OK baseline=%s resumed=%s" % [expected_result_hash, restarted_hash])
	_require(restarted_hash == expected_result_hash, "RESTARTED_P2_6_HASH_MISMATCH")
	_require(Persistence.value_hash(restarted_result.get("final_states", {})) == expected_state_hash, "RESTARTED_FINAL_STATE_HASH_MISMATCH")
	_require(Persistence.value_hash(after_b.get("lineage_diagnostics", {})) == expected_diagnostics_hash, "RESTARTED_DIAGNOSTICS_HASH_MISMATCH")

	print("ECO.EVO1-P2.8 Failure Stage Probe: PASS baseline=%s resumed=%s" % [expected_result_hash, restarted_hash])
	quit(0)

func _require(condition: bool, stage: String) -> void:
	if not condition:
		_fail(stage)

func _fail(stage: String) -> void:
	push_error("ECO.EVO1-P2.8 FAILURE_STAGE=" + stage)
	quit(1)

func _debug_decode(text: String, original_world: Dictionary, evidence: Dictionary, label: String) -> void:
	var parsed = JSON.parse_string(text)
	print("ECO.EVO1-P2.8 debug_%s parsed_type=%d" % [label, typeof(parsed)])
	var decoded = Persistence._decode_value(parsed) if typeof(parsed) == TYPE_DICTIONARY else null
	print("ECO.EVO1-P2.8 debug_%s decoded_type=%d" % [label, typeof(decoded)])
	if typeof(decoded) != TYPE_DICTIONARY:
		return
	var document: Dictionary = decoded
	var restored_world: Dictionary = document.get("world", {})
	var restored_evidence: Dictionary = document.get("evidence_context", {})
	print("ECO.EVO1-P2.8 debug_%s validate_world=%s" % [label, str(Persistence.validate_world(restored_world))])
	print("ECO.EVO1-P2.8 debug_%s world_hash stored=%s original=%s restored=%s" % [label, String(document.get("world_hash", "")), Persistence.world_hash(original_world), Persistence.world_hash(restored_world)])
	print("ECO.EVO1-P2.8 debug_%s evidence_hash stored=%s original=%s restored=%s" % [label, String(document.get("evidence_hash", "")), Persistence.value_hash(evidence), Persistence.value_hash(restored_evidence)])
	print("ECO.EVO1-P2.8 debug_%s checkpoint_stored=%s recomputed=%s" % [label, String(document.get("checkpoint_hash", "")), Persistence._checkpoint_hash(document)])

func _audit_value(value, path: String) -> void:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_RECT2, TYPE_PACKED_STRING_ARRAY:
			return
		TYPE_ARRAY:
			var array: Array = value
			for index in range(array.size()):
				_audit_value(array[index], "%s[%d]" % [path, index])
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			for key in dictionary.keys():
				if typeof(key) not in [TYPE_STRING, TYPE_STRING_NAME]:
					print("ECO.EVO1-P2.8 unsupported_key path=%s type=%d value=%s" % [path, typeof(key), str(key)])
				_audit_value(dictionary[key], path + "." + String(key))
		_:
			print("ECO.EVO1-P2.8 unsupported_value path=%s type=%d value=%s" % [path, typeof(value), str(value)])
