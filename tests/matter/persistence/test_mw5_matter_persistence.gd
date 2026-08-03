extends SceneTree

const AtomicJsonScript = preload("res://scripts/testing/process_harness/atomic_json_file.gd")
const FixtureScript = preload("res://tests/matter/persistence/mw5_test_fixture.gd")
const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const CodecScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_codec.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const LedgerScript = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")
const CheckpointScript = preload("res://scripts/simulation/matter/persistence/matter_persistence_checkpoint.gd")
const QueryScript = preload("res://scripts/simulation/matter/query/matter_continuous_query_service.gd")
const ProfileScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_profile.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const ServiceScript = preload("res://scripts/simulation/matter/mutation/matter_excavation_service.gd")
const RepositoryScript = preload("res://scripts/simulation/matter/persistence/matter_state_repository.gd")
const CoordinatorScript = preload("res://scripts/simulation/matter/persistence/matter_state_coordinator.gd")

const WORKER_SCRIPT: String = "res://tools/matter/mw5_persistence_worker.gd"
const PROCESS_TIMEOUT_MS: int = 60000
const FLOAT_ROUNDTRIP_PROBE: float = 2026174.8885708766

var assertions: int = 0
var failures: Array[String] = []
var manifest: Dictionary = {}
var _root_path: String = ""
var _suite_started_usec: int = 0


func _init() -> void:
	_suite_started_usec = Time.get_ticks_usec()
	_root_path = ProjectSettings.globalize_path("user://mw5-persistence-%d" % Time.get_ticks_usec())
	_remove_tree(_root_path)
	DirAccess.make_dir_recursive_absolute(_root_path)
	print("MW5 matter persistence: START")
	_load_manifest()
	_run_stage("manifest", Callable(self, "_test_manifest"))
	_run_stage("binary64-transport", Callable(self, "_test_binary64_transport"))
	_run_stage("checkpoint-roundtrip", Callable(self, "_test_checkpoint_roundtrip_and_replay"))
	_run_stage("atomic-repository", Callable(self, "_test_atomic_repository_and_fallback"))
	_run_stage("identity-rejection", Callable(self, "_test_incompatible_generator_rejected"))
	_run_stage("process-restart", Callable(self, "_test_real_process_restart"))
	_remove_tree(_root_path)
	_finish()


func _run_stage(label: String, test_case: Callable) -> void:
	var started_usec: int = Time.get_ticks_usec()
	print("MW5 stage %s: START" % label)
	test_case.call()
	print("MW5 stage %s: DONE (%.3f s)" % [
		label, float(Time.get_ticks_usec() - started_usec) / 1000000.0,
	])


func _load_manifest() -> void:
	var path: String = "res://config/matter/mw5-matter-persistence.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest() -> void:
	_assert(not manifest.is_empty(), "MW5 manifest is missing")
	if manifest.is_empty():
		return
	_assert(String(manifest.get("schema", "")) == "planet_simulator.mw5_matter_persistence_manifest.v1", "MW5 manifest schema changed")
	_assert(String(manifest.get("checkpoint", "")) == "v17.5.0-simulation-mw5-matter-persistence", "MW5 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.4.0-simulation-mw4-matter-mutations", "MW5 base changed")
	_assert(String(manifest.get("base_delivery", "")) == "fix3", "MW5 base delivery changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw5-matter-persistence", "MW5 branch changed")
	_assert(bool(manifest.get("disk_persistence_added", false)), "MW5 disk persistence flag missing")
	_assert(bool(manifest.get("process_restart_recovery_added", false)), "MW5 process recovery flag missing")
	_assert(not bool(manifest.get("network_authority_added", true)), "MW5 unexpectedly adds network authority")
	_assert(String(manifest.get("repository", {}).get("active_file", "")) == "matter-state.json", "MW5 active file changed")
	_assert(String(manifest.get("repository", {}).get("previous_file", "")) == "matter-state.previous.json", "MW5 previous file changed")
	_assert(bool(manifest.get("repository", {}).get("repairs_active_from_previous", false)), "MW5 previous recovery repair flag missing")
	_assert(bool(manifest.get("recovery", {}).get("component_restore_is_compensated", false)), "MW5 restore rollback flag missing")
	_assert(bool(manifest.get("laboratory", {}).get("saves_after_committed_excavation", false)), "MW5 laboratory autosave flag missing")
	_assert(
		String(manifest.get("transport", {}).get("schema", "")) \
			== CodecScript.TRANSPORT_SCHEMA,
		"MW5 persistence transport schema changed"
	)
	_assert(
		String(manifest.get("transport", {}).get("float_encoding", "")) \
			== CodecScript.TRANSPORT_FLOAT_ENCODING,
		"MW5 binary64 transport encoding changed"
	)
	_assert(
		bool(manifest.get("transport", {}).get("exact_binary64_roundtrip", false)),
		"MW5 exact binary64 transport flag missing"
	)


func _test_binary64_transport() -> void:
	var probe: Dictionary = {
		"schema": "planet_simulator.matter_persistence_float_probe.v1",
		"fractional_value": FLOAT_ROUNDTRIP_PROBE,
		"integer_valued_float": 1.0,
		"float_array": [FLOAT_ROUNDTRIP_PROBE, 1.0],
		"checksum": "",
	}
	probe["checksum"] = MatterUtilsScript.compute_checksum(probe)
	var encoded: String = CodecScript.encode_persistence_json(probe)
	_assert(not encoded.is_empty(), "MW5 binary64 probe encoding failed")
	_assert(encoded.contains(CodecScript.FLOAT_TAG_KEY), "MW5 persistence bytes do not contain float bit tags")
	_assert(not encoded.contains("2026174.888570876"), "MW5 persistence leaked an unstable decimal float")
	var decoded: Dictionary = CodecScript.decode_persistence_json(encoded)
	_assert(not decoded.is_empty(), "MW5 binary64 probe decoding failed")
	if decoded.is_empty():
		return
	_assert(typeof(decoded.get("fractional_value")) == TYPE_FLOAT, "MW5 fractional float Variant type changed")
	_assert(typeof(decoded.get("integer_valued_float")) == TYPE_FLOAT, "MW5 integer-valued float Variant type changed")
	_assert(float(decoded["fractional_value"]) == FLOAT_ROUNDTRIP_PROBE, "MW5 binary64 probe changed after persistence")
	_assert(float(decoded["integer_valued_float"]) == 1.0, "MW5 integer-valued float changed after persistence")
	_assert(typeof(decoded.get("float_array")) == TYPE_ARRAY, "MW5 packed float array type changed")
	_assert(float(decoded["float_array"][0]) == FLOAT_ROUNDTRIP_PROBE, "MW5 packed float array fractional value changed")
	_assert(typeof(decoded["float_array"][1]) == TYPE_FLOAT, "MW5 packed float array lost TYPE_FLOAT")
	_assert(String(decoded.get("checksum", "")) == String(probe["checksum"]), "MW5 binary64 probe checksum changed")
	_assert(MatterUtilsScript.compute_checksum(decoded) == String(probe["checksum"]), "MW5 decoded binary64 probe checksum is invalid")
	var parsed = JSON.parse_string(encoded)
	_assert(typeof(parsed) == TYPE_DICTIONARY, "MW5 binary64 transport envelope JSON failed")
	if typeof(parsed) == TYPE_DICTIONARY:
		var parsed_payload: Dictionary = Dictionary(Dictionary(parsed)["payload"])
		_assert(
			String(parsed_payload["fractional_value"][CodecScript.FLOAT_TAG_KEY]) \
				== "886179e3beea3e41",
			"MW5 binary64 probe little-endian bit pattern changed"
		)
		_assert(
			String(parsed_payload["integer_valued_float"][CodecScript.FLOAT_TAG_KEY]) \
				== "000000000000f03f",
			"MW5 integer-valued float bit pattern changed"
		)
		_assert(
			String(parsed_payload["float_array"][CodecScript.FLOAT_ARRAY_TAG_KEY]) \
				== "886179e3beea3e41000000000000f03f",
			"MW5 packed float array bit pattern changed"
		)
		var corrupted: Dictionary = Dictionary(parsed).duplicate(true)
		var float_tag: Dictionary = corrupted["payload"]["fractional_value"]
		var bits: String = String(float_tag[CodecScript.FLOAT_TAG_KEY])
		float_tag[CodecScript.FLOAT_TAG_KEY] = ("0" if bits.substr(0, 1) != "0" else "1") + bits.substr(1)
		_assert(
			CodecScript.decode_persistence_json(MatterUtilsScript.canonical_json(corrupted)).is_empty(),
			"MW5 transport accepted a modified float tag with a stale envelope checksum"
		)
		corrupted["checksum"] = ""
		corrupted["checksum"] = MatterUtilsScript.compute_checksum(corrupted)
		_assert(
			CodecScript.decode_persistence_json(MatterUtilsScript.canonical_json(corrupted)).is_empty(),
			"MW5 transport accepted modified float bits after envelope checksum repair"
		)
		var untagged: Dictionary = Dictionary(parsed).duplicate(true)
		untagged["payload"]["fractional_value"] = 0.5
		untagged["checksum"] = ""
		untagged["checksum"] = MatterUtilsScript.compute_checksum(untagged)
		_assert(
			CodecScript.decode_persistence_json(MatterUtilsScript.canonical_json(untagged)).is_empty(),
			"MW5 transport accepted an untagged fractional JSON number"
		)


func _test_checkpoint_roundtrip_and_replay() -> void:
	var repository_root: String = _root_path.path_join("roundtrip")
	var first: Dictionary = FixtureScript.create_context(repository_root)
	_assert(bool(first.get("success", false)), "MW5 first context failed")
	if not bool(first.get("success", false)):
		return
	var fixture: Dictionary = FixtureScript.single_cell_fixture(
		first["generator_profile"], first["feature_catalog"], first["grid_profile"]
	)
	_assert(not fixture.is_empty(), "MW5 fixture missing")
	if fixture.is_empty():
		return
	var request: Dictionary = FixtureScript.create_request(
		first["service"], fixture, "matter-operation/mw5-roundtrip"
	)
	var result: Dictionary = first["service"].execute(request)
	_assert(String(result.get("status", "")) == "COMMITTED", "MW5 seed mutation failed")
	if String(result.get("status", "")) != "COMMITTED":
		return
	var witness: Dictionary = FixtureScript.find_excavation_witness(first, result)
	_assert(not witness.is_empty(), "MW5 committed mutation produced no positive tunnel witness")
	_assert(
		float(witness.get("signed_distance_m", -1.0)) > 0.0,
		"MW5 tunnel witness was not vacuum before persistence"
	)
	if witness.is_empty() or float(witness.get("signed_distance_m", -1.0)) <= 0.0:
		return
	_assert_codec_json_roundtrip(first["service"], request, result)
	var store_hash: String = first["service"].snapshot_store().content_hash()
	var receiver_hash: String = first["service"].material_receiver().content_hash()
	var journal_hash: String = first["service"].mutation_journal().content_hash()
	var saved: Dictionary = first["coordinator"].save_next(700)
	_assert_ok(saved, "MW5 checkpoint save failed")
	if not bool(saved.get("success", false)):
		return
	var checkpoint: Dictionary = saved["details"]["checkpoint"]
	_assert_ok(CheckpointScript.validate(checkpoint), "MW5 checkpoint rejected")
	_assert(int(checkpoint["generation"]) == 1, "MW5 first generation changed")
	_assert(FileAccess.file_exists(first["repository"].active_path()), "MW5 active checkpoint missing")
	var active_file := FileAccess.open(first["repository"].active_path(), FileAccess.READ)
	_assert(active_file != null, "MW5 active checkpoint could not be read")
	if active_file != null:
		var active_bytes: PackedByteArray = active_file.get_buffer(active_file.get_length())
		active_file.close()
		var canonical_bytes: PackedByteArray = CodecScript.encode_persistence_json(
			checkpoint
		).to_utf8_buffer()
		_assert(
			active_bytes == canonical_bytes,
			"MW5 repository raw bytes diverged from canonical persistence bytes"
		)
	var second: Dictionary = FixtureScript.create_context(repository_root)
	_assert(bool(second.get("success", false)), "MW5 second context failed")
	if not bool(second.get("success", false)):
		return
	var restored: Dictionary = second["coordinator"].restore_latest()
	_assert_ok(restored, "MW5 restore failed")
	_assert(String(restored.get("details", {}).get("source", "")) == "ACTIVE", "MW5 restore source changed")
	_assert(second["service"].snapshot_store().content_hash() == store_hash, "MW5 store hash changed after restart")
	_assert(second["service"].material_receiver().content_hash() == receiver_hash, "MW5 receiver hash changed after restart")
	_assert(second["service"].mutation_journal().content_hash() == journal_hash, "MW5 journal hash changed after restart")
	_assert(second["service"].material_receiver().reservation_count() == 0, "MW5 restored a transient reservation")
	var replay_request: Dictionary = CodecScript.rehydrate_request(request)
	_assert(not replay_request.is_empty(), "MW5 request rehydrate failed")
	var before_store_hash: String = second["service"].snapshot_store().content_hash()
	var before_receiver_hash: String = second["service"].material_receiver().content_hash()
	var before_journal_hash: String = second["service"].mutation_journal().content_hash()
	var replay: Dictionary = second["service"].execute(replay_request)
	_assert(String(replay.get("checksum", "")) == String(result.get("checksum", "")), "MW5 replay result changed")
	_assert(second["service"].snapshot_store().content_hash() == before_store_hash, "MW5 replay mutated store twice")
	_assert(second["service"].material_receiver().content_hash() == before_receiver_hash, "MW5 replay duplicated batch")
	_assert(second["service"].mutation_journal().content_hash() == before_journal_hash, "MW5 replay duplicated journal")
	var query = QueryScript.new()
	_assert_ok(query.configure(
		second["body"], second["material_catalog"], second["generator_profile"],
		second["feature_catalog"], second["grid_profile"], second["service"].snapshot_store()
	), "MW5 restored query configuration failed")
	var witness_sample: Dictionary = query.sample(witness["position_m"], FixtureScript.CELL_LEVEL)
	_assert(not witness_sample.is_empty(), "MW5 restored tunnel witness sample missing")
	var restored_witness_sdf_m: float = float(witness_sample.get("signed_distance_m", -1.0))
	_assert(
		restored_witness_sdf_m == float(witness["signed_distance_m"]),
		"MW5 tunnel witness SDF changed after restore"
	)
	_assert(restored_witness_sdf_m > 0.0, "MW5 confirmed tunnel witness did not survive restart")
	var saved_second: Dictionary = second["coordinator"].save_next(701)
	_assert_ok(saved_second, "MW5 second generation save failed")
	_assert(int(saved_second.get("details", {}).get("generation", 0)) == 2, "MW5 second generation changed")
	_assert(FileAccess.file_exists(second["repository"].previous_path()), "MW5 previous checkpoint missing")


func _test_atomic_repository_and_fallback() -> void:
	var repository_root: String = _root_path.path_join("repository")
	var context: Dictionary = FixtureScript.create_context(repository_root)
	_assert(bool(context.get("success", false)), "MW5 repository context failed")
	if not bool(context.get("success", false)):
		return
	var fixture: Dictionary = FixtureScript.single_cell_fixture(
		context["generator_profile"], context["feature_catalog"], context["grid_profile"]
	)
	var request: Dictionary = FixtureScript.create_request(
		context["service"], fixture, "matter-operation/mw5-repository"
	)
	_assert(String(context["service"].execute(request).get("status", "")) == "COMMITTED", "MW5 repository mutation failed")
	var first_save: Dictionary = context["coordinator"].save_next(800)
	_assert_ok(first_save, "MW5 repository first save failed")
	var second_save: Dictionary = context["coordinator"].save_next(801)
	_assert_ok(second_save, "MW5 repository second save failed")
	if not bool(second_save.get("success", false)):
		return
	var generation_three: Dictionary = context["coordinator"].create_checkpoint(
		3, 802, String(second_save["details"]["checkpoint"]["checksum"])
	)
	_assert(not generation_three.is_empty(), "MW5 generation three build failed")
	var prepared: Dictionary = context["repository"].prepare(generation_three)
	_assert_ok(prepared, "MW5 pending checkpoint prepare failed")
	_assert(context["repository"].list_pending_files().size() == 1, "MW5 pending checkpoint count changed")
	var loaded_active: Dictionary = context["repository"].load_committed()
	_assert_ok(loaded_active, "MW5 active load with pending failed")
	if not bool(loaded_active.get("success", false)):
		return
	_assert(int(loaded_active["details"]["checkpoint"]["generation"]) == 2, "MW5 uncommitted pending became authoritative")
	_assert(loaded_active["details"]["pending_files"].size() == 1, "MW5 pending diagnostic missing")
	_write_text(context["repository"].active_path(), "{broken")
	var fallback: Dictionary = context["repository"].load_committed()
	_assert_ok(fallback, "MW5 previous fallback failed")
	if not bool(fallback.get("success", false)):
		return
	_assert(String(fallback.get("details", {}).get("source", "")) == "PREVIOUS_RECOVERY", "MW5 previous fallback source changed")
	_assert(int(fallback["details"]["checkpoint"]["generation"]) == 1, "MW5 previous fallback generation changed")
	var recovered_context: Dictionary = FixtureScript.create_context(repository_root)
	_assert(bool(recovered_context.get("success", false)), "MW5 fallback recovery context failed")
	if not bool(recovered_context.get("success", false)):
		return
	var repaired_restore: Dictionary = recovered_context["coordinator"].restore_latest()
	_assert_ok(repaired_restore, "MW5 previous checkpoint repair failed")
	if not bool(repaired_restore.get("success", false)):
		return
	_assert(String(repaired_restore["details"].get("source", "")) == "PREVIOUS_RECOVERY", "MW5 repaired restore source changed")
	var repaired_active: Dictionary = recovered_context["repository"].load_committed()
	_assert_ok(repaired_active, "MW5 repaired active checkpoint missing")
	if not bool(repaired_active.get("success", false)):
		return
	_assert(String(repaired_active["details"].get("source", "")) == "ACTIVE", "MW5 previous recovery did not repair active")
	_assert(int(repaired_active["details"]["checkpoint"]["generation"]) == 1, "MW5 repaired active generation changed")
	var resumed_save: Dictionary = recovered_context["coordinator"].save_next(803)
	_assert_ok(resumed_save, "MW5 save after previous recovery failed")
	_assert(int(resumed_save.get("details", {}).get("generation", 0)) == 2, "MW5 generation chain did not resume after recovery")
	_assert_ok(recovered_context["repository"].cleanup_pending_files(), "MW5 pending cleanup failed")
	_assert(context["repository"].list_pending_files().is_empty(), "MW5 pending cleanup incomplete")


func _test_incompatible_generator_rejected() -> void:
	var repository_root: String = _root_path.path_join("incompatible")
	var source: Dictionary = FixtureScript.create_context(repository_root)
	_assert(bool(source.get("success", false)), "MW5 incompatible source context failed")
	if not bool(source.get("success", false)):
		return
	var fixture: Dictionary = FixtureScript.single_cell_fixture(
		source["generator_profile"], source["feature_catalog"], source["grid_profile"]
	)
	var request: Dictionary = FixtureScript.create_request(
		source["service"], fixture, "matter-operation/mw5-incompatible"
	)
	_assert(String(source["service"].execute(request).get("status", "")) == "COMMITTED", "MW5 incompatible seed mutation failed")
	_assert_ok(source["coordinator"].save_next(900), "MW5 incompatible checkpoint save failed")
	var alternate_profile_data: Dictionary = source["generator_profile"].duplicate(true)
	alternate_profile_data["generator_seed"] = int(alternate_profile_data["generator_seed"]) + 1
	alternate_profile_data.erase("checksum")
	var alternate_profile: Dictionary = ProfileScript.create(alternate_profile_data)
	var alternate_catalog: Dictionary = GeneratorScript.default_feature_catalog(alternate_profile)
	var material_catalog: Dictionary = MaterialCatalogScript.default_catalog()
	var alternate_body: Dictionary = GeneratorScript.default_body_definition(
		alternate_profile, material_catalog, alternate_catalog
	)
	var alternate_grid: Dictionary = GridProfileScript.create({
		"body_id": alternate_body["body_id"],
		"body_frame_id": alternate_body["body_frame_id"],
		"root_half_extent_m": float(alternate_profile["reference_radius_m"]) \
			* float(alternate_profile["root_bounds_radius_ratio"]),
	})
	var service = ServiceScript.new()
	_assert_ok(service.configure(
		alternate_body, material_catalog, alternate_profile, alternate_catalog,
		alternate_grid, FixtureScript.CELL_LEVEL, FixtureScript.CONTAINER_ID,
		FixtureScript.MAXIMUM_MASS_KG, FixtureScript.MAXIMUM_VOLUME_M3
	), "MW5 alternate service configuration failed")
	var repository = RepositoryScript.new()
	_assert_ok(repository.configure(repository_root), "MW5 alternate repository configuration failed")
	var coordinator = CoordinatorScript.new()
	_assert_ok(coordinator.configure(
		alternate_body, alternate_grid, FixtureScript.CELL_LEVEL,
		service.snapshot_store(), service.material_receiver(), service.mutation_journal(), repository
	), "MW5 alternate coordinator configuration failed")
	var restored: Dictionary = coordinator.restore_latest()
	_assert(not bool(restored.get("success", false)), "MW5 incompatible generator was restored")
	_assert(String(restored.get("error_code", "")) in [
		"MATTER_RESTORE_BODY_DEFINITION_MISMATCH", "MATTER_RESTORE_GENERATOR_MISMATCH"
	], "MW5 incompatible generator error changed")
	_assert(service.snapshot_store().size() == 0, "MW5 incompatible restore mutated store")
	_assert(service.material_receiver().batch_count() == 0, "MW5 incompatible restore mutated receiver")
	_assert(service.mutation_journal().size() == 0, "MW5 incompatible restore mutated journal")


func _test_real_process_restart() -> void:
	var scenario_root: String = _root_path.path_join("process")
	DirAccess.make_dir_recursive_absolute(scenario_root)
	var repository_root: String = scenario_root.path_join("repository")
	var context_file: String = scenario_root.path_join("context.json")
	var result_file: String = scenario_root.path_join("result.json")
	var seed_pid: int = _spawn_worker("seed", repository_root, context_file, "")
	_assert(seed_pid > 0, "MW5 seed worker did not start")
	var seed_exit: int = _wait_for_exit(seed_pid, PROCESS_TIMEOUT_MS)
	_assert(seed_exit == 0, "MW5 seed worker failed: %d" % seed_exit)
	_assert(FileAccess.file_exists(repository_root.path_join("matter-state.json")), "MW5 process checkpoint missing")
	_assert(FileAccess.file_exists(context_file), "MW5 process context missing")
	var context_result: Dictionary = AtomicJsonScript.read_dictionary(context_file)
	_assert(bool(context_result.get("success", false)), "MW5 process context could not be read")
	if bool(context_result.get("success", false)):
		var process_context: Dictionary = context_result["value"]
		_assert(not process_context.has("center_m"), "MW5 process context leaked decimal center coordinates")
		_assert(not process_context.has("center_transport"), "MW5 process context retained the unproven center transport")
		_assert(
			typeof(process_context.get("witness_transport")) == TYPE_STRING,
			"MW5 process context witness transport missing"
		)
		var decoded_witness: Dictionary = CodecScript.decode_persistence_json(
			String(process_context.get("witness_transport", ""))
		)
		_assert(
			String(decoded_witness.get("schema", "")) \
				== "planet_simulator.mw5_process_witness.v1",
			"MW5 process witness schema changed"
		)
		_assert(
			typeof(decoded_witness.get("position_m")) == TYPE_ARRAY \
				and decoded_witness["position_m"].size() == 3,
			"MW5 process witness position did not decode as three components"
		)
		if typeof(decoded_witness.get("position_m")) == TYPE_ARRAY \
				and decoded_witness["position_m"].size() == 3:
			for component in decoded_witness["position_m"]:
				_assert(typeof(component) == TYPE_FLOAT, "MW5 process witness component lost TYPE_FLOAT")
		_assert(
			typeof(decoded_witness.get("signed_distance_m")) == TYPE_FLOAT \
				and float(decoded_witness.get("signed_distance_m", -1.0)) > 0.0,
			"MW5 process witness was not proven vacuum before restart"
		)
	var recover_pid: int = _spawn_worker("recover", repository_root, context_file, result_file)
	_assert(recover_pid > 0, "MW5 recovery worker did not start")
	var recover_exit: int = _wait_for_exit(recover_pid, PROCESS_TIMEOUT_MS)
	_assert(recover_exit == 0, "MW5 recovery worker failed: %d" % recover_exit)
	var report_result: Dictionary = AtomicJsonScript.read_dictionary(result_file)
	_assert(bool(report_result.get("success", false)), "MW5 recovery report missing")
	if not bool(report_result.get("success", false)):
		return
	var report: Dictionary = report_result["value"]
	_assert(bool(report.get("passed", false)), "MW5 process recovery report failed")
	_assert(String(report.get("source", "")) == "ACTIVE", "MW5 process recovery source changed")
	_assert(int(report.get("generation", 0)) == 1, "MW5 process generation changed")
	_assert(String(report.get("replay_checksum", "")) == String(report.get("expected_result_checksum", "")), "MW5 process replay checksum changed")
	_assert(String(report.get("store_hash_before", "")) == String(report.get("store_hash_after", "")), "MW5 process replay changed store")
	_assert(String(report.get("receiver_hash_before", "")) == String(report.get("receiver_hash_after", "")), "MW5 process replay changed receiver")
	_assert(String(report.get("journal_hash_before", "")) == String(report.get("journal_hash_after", "")), "MW5 process replay changed journal")
	_assert(bool(report.get("witness_sdf_equal", false)), "MW5 process witness SDF changed after restart")
	_assert(bool(report.get("witness_is_vacuum", false)), "MW5 confirmed process witness did not survive restart")


func _assert_codec_json_roundtrip(service, request: Dictionary, result: Dictionary) -> void:
	var raw_request: Dictionary = _json_round_trip(request)
	var raw_result: Dictionary = _json_round_trip(result)
	var raw_composition: Dictionary = _json_round_trip(result["extracted_composition"])
	var raw_ledger: Dictionary = _json_round_trip(result["mass_ledger"])
	var address_id: String = String(result["changed_bricks"][0]["address"]["address_id"])
	var snapshot: Dictionary = service.snapshot_store().get_snapshot_by_address_id(address_id)
	var raw_snapshot: Dictionary = _json_round_trip(snapshot)
	var batch_id: String = String(result["created_aggregate_ids"][0])
	var batch: Dictionary = service.material_receiver().get_batch(batch_id)
	var raw_batch: Dictionary = _json_round_trip(batch)
	_assert(
		String(CodecScript.rehydrate_request(raw_request).get("checksum", "")) == String(request["checksum"]),
		"MW5 JSON-decoded request rehydrate failed"
	)
	var typed_result: Dictionary = CodecScript.rehydrate_result(raw_result)
	_assert(
		String(typed_result.get("checksum", "")) == String(result["checksum"]),
		"MW5 JSON-decoded result rehydrate failed"
	)
	_assert(
		bool(ResultScript.validate(typed_result).get("success", false)),
		"MW5 reconstructed result checksum validation failed"
	)
	_assert(
		String(CodecScript.rehydrate_composition(raw_composition).get("checksum", "")) \
			== String(result["extracted_composition"]["checksum"]),
		"MW5 JSON-decoded composition rehydrate failed"
	)
	var typed_ledger: Dictionary = CodecScript.rehydrate_ledger(raw_ledger)
	_assert(
		String(typed_ledger.get("checksum", "")) \
			== String(result["mass_ledger"]["checksum"]),
		"MW5 JSON-decoded ledger rehydrate failed"
	)
	_assert(
		bool(LedgerScript.validate(typed_ledger).get("success", false)),
		"MW5 reconstructed ledger checksum validation failed"
	)
	_assert(
		float(raw_ledger.get("input_total_kg", -1.0)) \
			== float(result["mass_ledger"]["input_total_kg"]),
		"MW5 ledger input total changed at the binary64 transport boundary"
	)
	_assert_snapshot_canonical_roundtrip(snapshot, raw_snapshot)
	_assert(
		String(CodecScript.rehydrate_batch(raw_batch).get("checksum", "")) == String(batch["checksum"]),
		"MW5 JSON-decoded batch rehydrate failed"
	)
	var corrupted_request: Dictionary = raw_request.duplicate(true)
	corrupted_request["energy_budget_j"] = float(corrupted_request["energy_budget_j"]) - 1024.0
	_assert(
		CodecScript.rehydrate_request(corrupted_request).is_empty(),
		"MW5 codec accepted a raw payload with a stale checksum"
	)


func _assert_snapshot_canonical_roundtrip(snapshot: Dictionary, raw_snapshot: Dictionary) -> void:
	var encoded: String = CodecScript.encode_persistence_json(snapshot)
	_assert(not encoded.is_empty(), "MW5 snapshot canonical persistence encoding failed")
	_assert(not raw_snapshot.is_empty(), "MW5 snapshot canonical JSON decode failed")
	if raw_snapshot.is_empty():
		return
	_assert(
		String(raw_snapshot.get("checksum", "")) == String(snapshot["checksum"]),
		"MW5 canonical JSON decode did not preserve the persisted snapshot checksum"
	)
	var rehydrated: Dictionary = CodecScript.rehydrate_snapshot(raw_snapshot)
	_assert(
		String(rehydrated.get("checksum", "")) == String(snapshot["checksum"]),
		"MW5 canonical JSON-decoded snapshot rehydrate failed"
	)
	_assert(
		bool(SnapshotScript.validate(rehydrated).get("success", false)),
		"MW5 reconstructed snapshot checksum validation failed"
	)
	_assert(
		CodecScript.encode_persistence_json(rehydrated) == encoded,
		"MW5 snapshot persistence representation changed after rehydrate"
	)


func _json_round_trip(value: Dictionary) -> Dictionary:
	var encoded: String = CodecScript.encode_persistence_json(value)
	return CodecScript.decode_persistence_json(encoded) if not encoded.is_empty() else {}


func _spawn_worker(phase: String, repository_root: String, context_file: String, result_file: String) -> int:
	var arguments: Array[String] = [
		"--headless",
		"--path", ProjectSettings.globalize_path("res://"),
		"--script", WORKER_SCRIPT,
		"--",
		"--phase=%s" % phase,
		"--repository-root=%s" % repository_root,
		"--context-file=%s" % context_file,
		"--result-file=%s" % result_file,
	]
	return OS.create_process(OS.get_executable_path(), arguments, false)


func _wait_for_exit(pid: int, timeout_ms: int) -> int:
	if pid <= 0:
		return -999
	var started_msec: int = Time.get_ticks_msec()
	while OS.is_process_running(pid):
		if Time.get_ticks_msec() - started_msec > timeout_ms:
			OS.kill(pid)
			return -998
		OS.delay_msec(20)
	return OS.get_process_exit_code(pid)


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.flush()
	file.close()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [
		message, String(result.get("error_code", "UNKNOWN")),
	])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.include_hidden = true
	for file_name in directory.get_files():
		DirAccess.remove_absolute(path.path_join(file_name))
	for directory_name in directory.get_directories():
		_remove_tree(path.path_join(directory_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	var elapsed_s: float = float(Time.get_ticks_usec() - _suite_started_usec) / 1000000.0
	if failures.is_empty():
		print("MW5 matter persistence: PASS (%d assertions / %.3f s)" % [assertions, elapsed_s])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MW5 matter persistence: FAIL (%d failures / %d assertions / %.3f s)" % [
		failures.size(), assertions, elapsed_s,
	])
	quit(1)
