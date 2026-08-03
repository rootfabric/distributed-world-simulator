extends SceneTree

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const FixtureScript = preload("res://tests/matter/persistence/mw5_test_fixture.gd")
const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const QueryScript = preload("res://scripts/simulation/matter/query/matter_continuous_query_service.gd")

const PROCESS_WITNESS_SCHEMA: String = "planet_simulator.mw5_process_witness.v1"

var _options: Dictionary = {}


func _init() -> void:
	_options = _parse_options(OS.get_cmdline_user_args())
	var phase: String = String(_options.get("phase", ""))
	if phase == "seed":
		_seed()
	elif phase == "recover":
		_recover()
	else:
		quit(2)


func _seed() -> void:
	var context: Dictionary = FixtureScript.create_context(String(_options.get("repository_root", "")))
	if not bool(context.get("success", false)):
		_fail("SEED_CONTEXT_FAILED", context)
		return
	var fixture: Dictionary = FixtureScript.single_cell_fixture(
		context["generator_profile"], context["feature_catalog"], context["grid_profile"]
	)
	if fixture.is_empty():
		_fail("SEED_FIXTURE_MISSING")
		return
	var request: Dictionary = FixtureScript.create_request(
		context["service"], fixture, "matter-operation/mw5-process-restart"
	)
	var result: Dictionary = context["service"].execute(request)
	if String(result.get("status", "")) != "COMMITTED":
		_fail("SEED_MUTATION_FAILED", result)
		return
	var witness: Dictionary = FixtureScript.find_excavation_witness(context, result)
	if witness.is_empty() or float(witness.get("signed_distance_m", -1.0)) <= 0.0:
		_fail("SEED_TUNNEL_WITNESS_MISSING")
		return
	var saved: Dictionary = context["coordinator"].save_next(501)
	if not bool(saved.get("success", false)):
		_fail("SEED_SAVE_FAILED", saved)
		return
	var request_transport: String = CodecScript.encode_persistence_json(request)
	if request_transport.is_empty():
		_fail("SEED_REQUEST_TRANSPORT_FAILED")
		return
	var witness_payload: Dictionary = {
		"schema": PROCESS_WITNESS_SCHEMA,
		"position_m": _array(witness["position_m"]),
		"signed_distance_m": float(witness["signed_distance_m"]),
		"checksum": "",
	}
	witness_payload["checksum"] = MatterUtilsScript.compute_checksum(witness_payload)
	var witness_transport: String = CodecScript.encode_persistence_json(witness_payload)
	if witness_transport.is_empty():
		_fail("SEED_WITNESS_TRANSPORT_FAILED")
		return
	var payload: Dictionary = {
		"request_transport": request_transport,
		"witness_transport": witness_transport,
		"result_checksum": String(result["checksum"]),
		"checkpoint_checksum": String(saved["details"]["checkpoint"]["checksum"]),
		"store_hash": context["service"].snapshot_store().content_hash(),
		"receiver_hash": context["service"].material_receiver().content_hash(),
		"journal_hash": context["service"].mutation_journal().content_hash(),
	}
	var written: Dictionary = AtomicJsonScript.write_dictionary(
		String(_options.get("context_file", "")), payload, false
	)
	quit(0 if bool(written.get("success", false)) else 3)


func _recover() -> void:
	var context_read: Dictionary = AtomicJsonScript.read_dictionary(
		String(_options.get("context_file", ""))
	)
	if not bool(context_read.get("success", false)):
		_fail("RECOVERY_CONTEXT_MISSING", context_read)
		return
	var expected: Dictionary = context_read["value"]
	var context: Dictionary = FixtureScript.create_context(String(_options.get("repository_root", "")))
	if not bool(context.get("success", false)):
		_fail("RECOVERY_CONTEXT_FAILED", context)
		return
	var restored: Dictionary = context["coordinator"].restore_latest()
	if not bool(restored.get("success", false)):
		_fail("RECOVERY_RESTORE_FAILED", restored)
		return
	var decoded_request: Dictionary = CodecScript.decode_persistence_json(
		String(expected.get("request_transport", ""))
	)
	var request: Dictionary = CodecScript.rehydrate_request(decoded_request)
	if request.is_empty():
		_fail("RECOVERY_REQUEST_REHYDRATE_FAILED")
		return
	var store_hash_before: String = context["service"].snapshot_store().content_hash()
	var receiver_hash_before: String = context["service"].material_receiver().content_hash()
	var journal_hash_before: String = context["service"].mutation_journal().content_hash()
	var batch_count_before: int = context["service"].material_receiver().batch_count()
	var journal_size_before: int = context["service"].mutation_journal().size()
	var replay: Dictionary = context["service"].execute(request)
	var query = QueryScript.new()
	var query_configuration: Dictionary = query.configure(
		context["body"],
		context["material_catalog"],
		context["generator_profile"],
		context["feature_catalog"],
		context["grid_profile"],
		context["service"].snapshot_store()
	)
	var decoded_witness: Dictionary = CodecScript.decode_persistence_json(
		String(expected.get("witness_transport", ""))
	)
	if String(decoded_witness.get("schema", "")) != PROCESS_WITNESS_SCHEMA \
			or typeof(decoded_witness.get("position_m")) != TYPE_ARRAY \
			or decoded_witness["position_m"].size() != 3 \
			or typeof(decoded_witness.get("signed_distance_m")) != TYPE_FLOAT \
			or float(decoded_witness.get("signed_distance_m", -1.0)) <= 0.0:
		_fail("RECOVERY_WITNESS_TRANSPORT_INVALID")
		return
	var witness_position_m: Vector3 = _vector3(decoded_witness["position_m"])
	var witness_sdf_before_m: float = float(decoded_witness["signed_distance_m"])
	var witness_sample: Dictionary = query.sample(witness_position_m, FixtureScript.CELL_LEVEL) \
		if bool(query_configuration.get("success", false)) else {}
	var witness_sdf_after_m: float = float(witness_sample.get("signed_distance_m", -1.0))
	var witness_sdf_equal: bool = not witness_sample.is_empty() \
		and witness_sdf_after_m == witness_sdf_before_m
	var witness_is_vacuum: bool = witness_sdf_equal and witness_sdf_after_m > 0.0
	var passed: bool = \
		String(restored["details"].get("source", "")) == "ACTIVE" \
		and String(replay.get("checksum", "")) == String(expected["result_checksum"]) \
		and context["service"].snapshot_store().content_hash() == store_hash_before \
		and context["service"].material_receiver().content_hash() == receiver_hash_before \
		and context["service"].mutation_journal().content_hash() == journal_hash_before \
		and context["service"].material_receiver().batch_count() == batch_count_before \
		and context["service"].mutation_journal().size() == journal_size_before \
		and witness_sdf_equal \
		and witness_is_vacuum
	var report: Dictionary = {
		"passed": passed,
		"source": restored["details"].get("source", ""),
		"generation": int(restored["details"]["checkpoint"]["generation"]),
		"replay_checksum": replay.get("checksum", ""),
		"expected_result_checksum": expected["result_checksum"],
		"store_hash_before": store_hash_before,
		"store_hash_after": context["service"].snapshot_store().content_hash(),
		"receiver_hash_before": receiver_hash_before,
		"receiver_hash_after": context["service"].material_receiver().content_hash(),
		"journal_hash_before": journal_hash_before,
		"journal_hash_after": context["service"].mutation_journal().content_hash(),
		"batch_count": context["service"].material_receiver().batch_count(),
		"journal_size": context["service"].mutation_journal().size(),
		"witness_sdf_equal": witness_sdf_equal,
		"witness_is_vacuum": witness_is_vacuum,
		"witness_sdf_before_m": witness_sdf_before_m,
		"witness_sdf_after_m": witness_sdf_after_m,
	}
	var written: Dictionary = AtomicJsonScript.write_dictionary(
		String(_options.get("result_file", "")), report, false
	)
	quit(0 if passed and bool(written.get("success", false)) else 4)


func _fail(code: String, details: Dictionary = {}) -> void:
	if not String(_options.get("result_file", "")).is_empty():
		AtomicJsonScript.write_dictionary(String(_options["result_file"]), {
			"passed": false,
			"error_code": code,
			"details": details,
		}, false)
	quit(5)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for argument in arguments:
		var text: String = String(argument)
		if not text.begins_with("--") or not text.contains("="):
			continue
		var separator: int = text.find("=")
		result[text.substr(2, separator - 2).replace("-", "_")] = text.substr(separator + 1)
	return result


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


static func _vector3(value) -> Vector3:
	if typeof(value) != TYPE_ARRAY or value.size() != 3:
		return Vector3.ZERO
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
