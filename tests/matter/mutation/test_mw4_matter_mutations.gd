extends SceneTree

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const BatchScript = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const SampleScript = preload("res://scripts/simulation/matter/contracts/matter_sample.gd")
const LedgerScript = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")
const SnapshotScript = preload("res://scripts/simulation/matter/contracts/matter_brick_snapshot.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const CellGridScript = preload("res://scripts/simulation/matter/spatial/matter_cell_grid.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const MaterializerScript = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const StoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const SweptShapeScript = preload("res://scripts/simulation/matter/mutation/matter_swept_shape.gd")
const KernelScript = preload("res://scripts/simulation/matter/mutation/matter_excavation_kernel.gd")
const JournalScript = preload("res://scripts/simulation/matter/mutation/matter_mutation_journal.gd")
const ReceiverScript = preload("res://scripts/simulation/matter/mutation/matter_material_receiver.gd")
const ServiceScript = preload("res://scripts/simulation/matter/mutation/matter_excavation_service.gd")
const ContinuousQueryScript = preload("res://scripts/simulation/matter/query/matter_continuous_query_service.gd")
const FailingJournalScript = preload("res://tests/matter/mutation/failing_matter_mutation_journal.gd")
const MesherScript = preload("res://scripts/world/matter/meshing/matter_tetrahedral_mesher.gd")
const MeshDataScript = preload("res://scripts/world/matter/meshing/matter_brick_mesh_data.gd")
const StreamerScript = preload("res://scripts/world/matter/lab/matter_local_mesh_streamer.gd")

const JSON_SAFE_ENERGY_BUDGET_J: float = 9000000000000000.0
const UNSAFE_INTEGER_ENERGY_BUDGET_J: float = 9007199254740992.0

var failures: Array[String] = []
var assertions: int = 0
var manifest: Dictionary = {}
var material_catalog: Dictionary = {}
var generator_profile: Dictionary = {}
var feature_catalog: Dictionary = {}
var body: Dictionary = {}
var grid_profile: Dictionary = {}
var _single_cell_fixture_cache: Dictionary = {}
var _cross_tunnel_context: Dictionary = {}
var _suite_started_usec: int = 0


func _init() -> void:
	_suite_started_usec = Time.get_ticks_usec()
	print("MW4 matter mutations: START")
	_load_fixture()
	_run_stage("manifest", Callable(self, "_test_manifest"))
	_run_stage("swept-shape", Callable(self, "_test_swept_shape_and_target_planning"))
	_run_stage("receiver-journal", Callable(self, "_test_batch_receiver_and_journal_contracts"))
	_run_stage("atomic-store", Callable(self, "_test_atomic_sparse_store"))
	_run_stage("single-cell", Callable(self, "_test_single_cell_excavation_and_replay"))
	_run_stage("cross-brick", Callable(self, "_test_cross_brick_persistent_tunnel"))
	_run_stage("rejections", Callable(self, "_test_stale_revision_and_failed_transactions"))
	_run_stage("rollback", Callable(self, "_test_post_commit_rollback"))
	_run_stage("streamer", Callable(self, "_test_streamer_persistent_snapshot_projection"))
	_finish()


func _run_stage(label: String, test_case: Callable) -> void:
	var started_usec: int = Time.get_ticks_usec()
	print("MW4 stage %s: START" % label)
	test_case.call()
	print("MW4 stage %s: DONE (%.3f s)" % [
		label, float(Time.get_ticks_usec() - started_usec) / 1000000.0,
	])


func _load_fixture() -> void:
	material_catalog = MaterialCatalogScript.default_catalog()
	generator_profile = GeneratorScript.default_profile()
	feature_catalog = GeneratorScript.default_feature_catalog(generator_profile)
	body = GeneratorScript.default_body_definition(
		generator_profile, material_catalog, feature_catalog
	)
	grid_profile = GridProfileScript.create({
		"body_id": body.get("body_id", ""),
		"body_frame_id": body.get("body_frame_id", ""),
		"root_half_extent_m": float(generator_profile.get("reference_radius_m", 1000.0)) \
			* float(generator_profile.get("root_bounds_radius_ratio", 1.45)),
	})
	var path: String = "res://config/matter/mw4-matter-mutations.v1.json"
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		manifest = parsed


func _test_manifest() -> void:
	_assert(not manifest.is_empty(), "MW4 manifest is missing or invalid")
	if manifest.is_empty():
		return
	_assert(
		String(manifest.get("schema", "")) == "planet_simulator.mw4_matter_mutations_manifest.v1",
		"MW4 manifest schema changed"
	)
	_assert(String(manifest.get("checkpoint", "")) == "v17.4.0-simulation-mw4-matter-mutations", "MW4 checkpoint changed")
	_assert(String(manifest.get("base_checkpoint", "")) == "v17.3.0-simulation-mw3-local-meshing", "MW4 base changed")
	_assert(String(manifest.get("base_delivery", "")) == "fix2", "MW4 base delivery changed")
	_assert(String(manifest.get("recommended_branch", "")) == "feature/mw4-matter-mutations", "MW4 branch changed")
	_assert(bool(manifest.get("canonical_matter_changed", false)), "MW4 canonical matter flag missing")
	_assert(bool(manifest.get("transactional_excavation_added", false)), "MW4 excavation flag missing")
	_assert(bool(manifest.get("local_persistent_mutations_added", false)), "MW4 persistence flag missing")
	_assert(not bool(manifest.get("disk_persistence_added", true)), "MW4 unexpectedly adds disk persistence")
	_assert(not bool(manifest.get("network_authority_added", true)), "MW4 unexpectedly adds network authority")
	_assert(String(manifest.get("mutation", {}).get("shape", "")) == "SWEPT_CAPSULE", "MW4 swept shape changed")
	_assert(String(manifest.get("mutation", {}).get("boolean_operation", "")) == "SDF_DIFFERENCE_MAX_A_NEGATIVE_B", "MW4 SDF operation changed")
	_assert(String(manifest.get("mutation", {}).get("acceptance_policy", "")) == "FULL_OR_REJECT", "MW4 acceptance policy changed")
	_assert(String(manifest.get("mutation", {}).get("sdf_storage_policy", "")) == "ONE_SAMPLE_NARROW_BAND_AROUND_TOOL_BOUNDARY", "MW4 SDF storage policy changed")
	_assert(String(manifest.get("lab_scene", "")) == "res://scenes/labs/matter_asteroid_excavation_lab.tscn", "MW4 lab scene changed")


func _test_swept_shape_and_target_planning() -> void:
	var shape: Dictionary = RequestScript.create_shape(
		"CAPSULE", [-140.0, 0.0, 0.0], [140.0, 0.0, 0.0], 18.0
	)
	_assert_ok(RequestScript.validate_shape(shape), "MW4 capsule shape rejected")
	_assert(SweptShapeScript.signed_distance_m(shape, Vector3.ZERO) < 0.0, "Capsule center is not inside")
	_assert(SweptShapeScript.signed_distance_m(shape, Vector3(0.0, 40.0, 0.0)) > 0.0, "Capsule exterior is not outside")
	var bounds: Dictionary = SweptShapeScript.bounds_m(shape)
	_assert(not bounds.is_empty(), "Capsule bounds are empty")
	_assert(float(bounds["minimum_m"][0]) == -158.0, "Capsule minimum X changed")
	_assert(float(bounds["maximum_m"][0]) == 158.0, "Capsule maximum X changed")
	var targets: Array = SweptShapeScript.affected_brick_addresses(grid_profile, shape, 5)
	_assert(targets.size() >= 4, "High-speed capsule did not cross multiple bricks")
	var previous_id: String = ""
	for address in targets:
		_assert_ok(BrickLayoutScript.validate_brick_address(grid_profile, address), "Planned brick address rejected")
		var address_id: String = String(address["address_id"])
		_assert(previous_id.is_empty() or address_id > previous_id, "Planned brick addresses are not sorted unique")
		previous_id = address_id
	var replay: Array = SweptShapeScript.affected_brick_addresses(grid_profile, shape, 5)
	_assert(replay == targets, "Swept target planning is non-deterministic")
	var expected_revision_by_address: Dictionary = {}
	for target_address in targets:
		expected_revision_by_address[String(target_address["address_id"])] = 0
	var unsafe_energy_request: Dictionary = RequestScript.create({
		"operation_id": "matter-operation/unsafe-energy-budget",
		"body_id": body["body_id"],
		"actor_id": "actor/test-miner",
		"tool_id": "tool/test-drill",
		"operation_type": "EXCAVATE",
		"target_bricks": targets,
		"expected_revision_by_address": expected_revision_by_address,
		"shape": shape,
		"source_container_id": "",
		"destination_container_id": "container/mw4-json-safe",
		"requested_mass_kg": 0.0,
		"energy_budget_j": UNSAFE_INTEGER_ENERGY_BUDGET_J,
		"client_tick": 0,
	})
	var unsafe_energy_validation: Dictionary = RequestScript.validate(unsafe_energy_request)
	_assert(not bool(unsafe_energy_validation.get("success", false)), "Unsafe integer-valued energy budget was accepted")
	_assert(String(unsafe_energy_validation.get("error_code", "")) == "NON_CANONICAL_JSON_VALUE", "Unsafe energy budget error changed")
	_assert(String(unsafe_energy_validation.get("details", {}).get("error", "")).contains("$.matter_mutation_request.energy_budget_j"), "Unsafe energy budget path changed")
	var root_bounds: Dictionary = CellGridScript.bounds_validated(
		grid_profile, CellGridScript.root_address(grid_profile)
	)
	var spacing_m: float = float(root_bounds["edge_length_m"]) / float(1 << 5) \
		/ float(grid_profile["brick_interior_resolution"])
	var aligned_radius_m: float = 10.0
	var aligned_center_x_m: float = -(aligned_radius_m + spacing_m * 2.0)
	var aligned_shape: Dictionary = RequestScript.create_shape(
		"SPHERE",
		[aligned_center_x_m, 0.0, 0.0],
		[aligned_center_x_m, 0.0, 0.0],
		aligned_radius_m
	)
	var aligned_targets: Array = SweptShapeScript.affected_brick_addresses(
		grid_profile, aligned_shape, 5
	)
	var aligned_ids: Array = []
	for aligned_address in aligned_targets:
		aligned_ids.append(String(aligned_address["address_id"]))
	var negative_cell: Dictionary = CellGridScript.address_for_position(
		grid_profile, Vector3(-0.001, 1.0, 1.0), 5
	)
	var positive_cell: Dictionary = CellGridScript.address_for_position(
		grid_profile, Vector3(0.001, 1.0, 1.0), 5
	)
	_assert(aligned_ids.has(String(BrickLayoutScript.brick_address(
		grid_profile, negative_cell
	)["address_id"])), "Aligned target lost negative ghost owner")
	_assert(aligned_ids.has(String(BrickLayoutScript.brick_address(
		grid_profile, positive_cell
	)["address_id"])), "Aligned target lost positive ghost owner")
	var kernel_cell: Dictionary = CellGridScript.address_for_position(
		grid_profile, Vector3(20.0, 20.0, 20.0), 5
	)
	var kernel_snapshot: Dictionary = MaterializerScript.materialize(
		body, material_catalog, generator_profile, feature_catalog, grid_profile, kernel_cell, 0
	)
	var local_shape: Dictionary = RequestScript.create_shape(
		"CAPSULE", [0.0, 0.0, 0.0], [0.0, 30.0, 0.0], 10.0
	)
	var kernel_result: Dictionary = KernelScript.apply_excavation(
		kernel_snapshot, grid_profile, local_shape
	)
	_assert_ok(kernel_result, "Narrow-band kernel fixture failed")
	var kernel_after: Dictionary = kernel_result["details"]["snapshot"]
	var near_index: int = BrickLayoutScript.flat_index(grid_profile, 1, 1, 1)
	var far_index: int = BrickLayoutScript.flat_index(grid_profile, 9, 9, 9)
	_assert(float(SnapshotScript.sample_at_validated(kernel_after, near_index)["occupancy_ratio"]) == 0.0, "Kernel did not excavate tool interior")
	_assert(SnapshotScript.sample_at_validated(kernel_after, far_index) == SnapshotScript.sample_at_validated(
		kernel_snapshot, far_index
	), "Kernel rewrote SDF outside mutation narrow band")


func _test_batch_receiver_and_journal_contracts() -> void:
	var composition: Dictionary = CompositionScript.from_weights({
		"matter/basalt": 0.75,
		"matter/iron-nickel-ore": 0.25,
	})
	var batch: Dictionary = BatchScript.create({
		"batch_id": "matter-batch/test-batch",
		"container_id": "container/mw4-test",
		"source_body_id": body["body_id"],
		"source_operation_id": "matter-operation/test-batch",
		"total_mass_kg": 100.0,
		"bulk_volume_m3": 0.04,
		"composition": composition,
		"temperature_k": 220.0,
	})
	_assert_ok(BatchScript.validate(batch), "Material batch contract rejected")
	var receiver = ReceiverScript.new()
	_assert_ok(receiver.configure("container/mw4-test", 1000.0, 10.0), "Material receiver configuration failed")
	_assert_ok(receiver.reserve("matter-operation/test-batch", 100.0, 0.04), "Material receiver reservation failed")
	_assert_ok(receiver.commit_reserved(batch), "Material receiver commit failed")
	_assert(receiver.batch_count() == 1, "Material receiver batch count changed")
	_assert(absf(receiver.total_mass_kg() - 100.0) < 0.000001, "Material receiver mass changed")
	_assert(receiver.get_batch("matter-batch/test-batch") == batch, "Material receiver batch round-trip failed")
	_assert_ok(receiver.rollback_batch("matter-batch/test-batch", "matter-operation/test-batch"), "Material receiver rollback failed")
	_assert(receiver.batch_count() == 0, "Material receiver rollback retained batch")
	var service_bundle: Dictionary = _new_service(1.0e15, 1.0e12)
	var service = service_bundle["service"]
	var request: Dictionary = service.create_excavation_request(
		"matter-operation/journal-contract",
		"actor/test",
		"tool/drill",
		Vector3(-30.0, 0.0, 0.0),
		Vector3(30.0, 0.0, 0.0),
		12.0,
		JSON_SAFE_ENERGY_BUDGET_J
	)
	_assert_ok(RequestScript.validate(request), "Journal fixture request rejected")
	var journal = JournalScript.new()
	var miss: Dictionary = journal.resolve(request)
	_assert_ok(miss, "Mutation journal miss failed")
	_assert(String(miss["details"]["status"]) == "MISS", "Mutation journal initial status changed")


func _test_atomic_sparse_store() -> void:
	var store = StoreScript.new()
	_assert_ok(store.configure(body, grid_profile), "Atomic store configuration failed")
	var left_cell: Dictionary = CellGridScript.address_for_position(grid_profile, Vector3(-30.0, 0.0, 0.0), 5)
	var right_cell: Dictionary = CellGridScript.address_for_position(grid_profile, Vector3(30.0, 0.0, 0.0), 5)
	var left_base: Dictionary = MaterializerScript.materialize(
		body, material_catalog, generator_profile, feature_catalog, grid_profile, left_cell, 0
	)
	var right_base: Dictionary = MaterializerScript.materialize(
		body, material_catalog, generator_profile, feature_catalog, grid_profile, right_cell, 0
	)
	_assert(
		SnapshotScript.sample_at(left_base, 0) == SnapshotScript.sample_at_validated(left_base, 0),
		"Validated snapshot sample accessor changed canonical output"
	)
	var invalid_ratio_snapshot: Dictionary = left_base.duplicate(true)
	invalid_ratio_snapshot["geometry_channel"]["occupancy_ratio"][0] = 2.0
	invalid_ratio_snapshot["checksum"] = MatterUtilsScript.compute_checksum(invalid_ratio_snapshot)
	_assert(
		not bool(SnapshotScript.validate(invalid_ratio_snapshot).get("success", false)),
		"Columnar snapshot validation accepted an invalid sample ratio"
	)
	var left_next: Dictionary = _clone_snapshot_with_revision(left_base, 1)
	var right_next: Dictionary = _clone_snapshot_with_revision(right_base, 1)
	var expected: Dictionary = {
		String(left_next["address"]["address_id"]): 0,
		String(right_next["address"]["address_id"]): 0,
	}
	_assert_ok(store.put_many_atomic([left_next, right_next], expected), "Atomic two-brick write failed")
	_assert(store.size() == 2, "Atomic store size changed")
	_assert(store.revision(left_next["address"]) == 1, "Atomic left revision changed")
	_assert(store.revision(right_next["address"]) == 1, "Atomic right revision changed")
	var before_hash: String = store.content_hash()
	var stale_expected: Dictionary = expected.duplicate(true)
	stale_expected[String(right_next["address"]["address_id"])] = 1
	var failed: Dictionary = store.put_many_atomic([
		_clone_snapshot_with_revision(left_base, 2),
		_clone_snapshot_with_revision(right_base, 2),
	], stale_expected)
	_assert(not bool(failed.get("success", false)), "Atomic mixed-revision write unexpectedly succeeded")
	_assert(store.content_hash() == before_hash, "Failed atomic write changed store")
	var mismatched_previous: Dictionary = {
		String(left_next["address"]["address_id"]): right_base,
		String(right_next["address"]["address_id"]): left_base,
	}
	var committed: Dictionary = {
		String(left_next["address"]["address_id"]): 1,
		String(right_next["address"]["address_id"]): 1,
	}
	var mismatched_rollback: Dictionary = store.rollback_many_atomic(
		mismatched_previous, committed
	)
	_assert(not bool(mismatched_rollback.get("success", false)), "Rollback accepted mismatched snapshot keys")
	_assert(store.content_hash() == before_hash, "Rejected rollback changed store")
	var previous: Dictionary = {
		String(left_next["address"]["address_id"]): {},
		String(right_next["address"]["address_id"]): {},
	}
	_assert_ok(store.rollback_many_atomic(previous, committed), "Atomic rollback failed")
	_assert(store.size() == 0, "Atomic rollback retained snapshots")


func _test_single_cell_excavation_and_replay() -> void:
	var fixture: Dictionary = _single_cell_surface_fixture()
	_assert(not fixture.is_empty(), "Could not find single-cell surface drill fixture")
	if fixture.is_empty():
		return
	var bundle: Dictionary = _new_service(1.0e15, 1.0e12)
	var service = bundle["service"]
	var request: Dictionary = service.create_excavation_request(
		"matter-operation/single-cell-dig",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"],
		fixture["end_m"],
		float(fixture["radius_m"]),
		JSON_SAFE_ENERGY_BUDGET_J,
		1
	)
	_assert_ok(RequestScript.validate(request), "Single-cell excavation request rejected")
	_assert(request["target_bricks"].size() == 1, "Single-cell fixture targets multiple bricks")
	var store_hash_before: String = service.snapshot_store().content_hash()
	var result: Dictionary = service.execute(request)
	_assert_ok(ResultScript.validate(result), "Single-cell excavation result rejected")
	_assert(String(result["status"]) == "COMMITTED", "Single-cell excavation was not committed")
	_assert(result["changed_bricks"].size() == 1, "Single-cell excavation changed unexpected brick count")
	_assert(float(result["removed_mass_kg"]) > 0.0, "Single-cell excavation removed no mass")
	_assert(float(result["consumed_energy_j"]) > 0.0, "Single-cell excavation consumed no energy")
	_assert(bool(result["mass_ledger"]["closed"]), "Single-cell mass ledger is open")
	_assert(service.snapshot_store().content_hash() != store_hash_before, "Committed excavation did not change store")
	_assert(service.material_receiver().batch_count() == 1, "Committed excavation did not create batch")
	var batch_id: String = String(result["created_aggregate_ids"][0])
	var batch: Dictionary = service.material_receiver().get_batch(batch_id)
	_assert_ok(BatchScript.validate(batch), "Committed material batch rejected")
	_assert(absf(float(batch["total_mass_kg"]) - float(result["removed_mass_kg"])) < 0.001, "Batch mass differs from removed mass")
	_assert(batch["composition"] == result["extracted_composition"], "Batch composition differs from result")
	var receiver_hash: String = service.material_receiver().content_hash()
	var store_hash: String = service.snapshot_store().content_hash()
	var replay: Dictionary = service.execute(request)
	_assert(replay == result, "Exact operation replay changed result")
	_assert(service.snapshot_store().content_hash() == store_hash, "Exact replay changed snapshots")
	_assert(service.material_receiver().content_hash() == receiver_hash, "Exact replay duplicated batch")
	var conflicting: Dictionary = service.create_excavation_request(
		"matter-operation/single-cell-dig",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"],
		fixture["end_m"] + Vector3(5.0, 0.0, 0.0),
		float(fixture["radius_m"]),
		JSON_SAFE_ENERGY_BUDGET_J,
		2
	)
	var conflict_result: Dictionary = service.execute(conflicting)
	_assert_ok(ResultScript.validate(conflict_result), "Fingerprint conflict result rejected")
	_assert(String(conflict_result["status"]) == "REJECTED", "Fingerprint conflict committed")
	_assert(String(conflict_result["error_code"]) == "MATTER_OPERATION_FINGERPRINT_CONFLICT", "Fingerprint conflict error changed")
	_assert(service.snapshot_store().content_hash() == store_hash, "Fingerprint conflict changed snapshots")


func _test_cross_brick_persistent_tunnel() -> void:
	var bundle: Dictionary = _new_service(9000000000000000.0, 1.0e13)
	var service = bundle["service"]
	var root_bounds: Dictionary = CellGridScript.bounds_validated(
		grid_profile, CellGridScript.root_address(grid_profile)
	)
	var cell_edge_m: float = float(root_bounds["edge_length_m"]) / float(1 << 5)
	var center_m := Vector3(cell_edge_m * 0.5, 0.0, cell_edge_m * 0.5)
	var start_m: Vector3 = center_m + Vector3(0.0, -100.0, 0.0)
	var end_m: Vector3 = center_m + Vector3(0.0, 100.0, 0.0)
	var radius_m: float = 18.0
	var request: Dictionary = service.create_excavation_request(
		"matter-operation/cross-brick-tunnel",
		"actor/test-miner",
		"tool/high-speed-drill",
		start_m,
		end_m,
		radius_m,
		JSON_SAFE_ENERGY_BUDGET_J,
		3
	)
	_assert_ok(RequestScript.validate(request), "Cross-brick request rejected")
	_assert(request["target_bricks"].size() == 4, "Cross-brick fixture no longer targets four bricks")
	var result: Dictionary = service.execute(request)
	_assert_ok(ResultScript.validate(result), "Cross-brick result rejected")
	_assert(String(result["status"]) == "COMMITTED", "Cross-brick tunnel was not committed")
	_assert(result["changed_bricks"].size() >= 2, "Cross-brick tunnel changed too few target bricks")
	_assert(float(result["removed_mass_kg"]) > 1000.0, "Cross-brick tunnel removed implausibly little mass")
	_assert(absf(float(result["mass_ledger"]["input_total_kg"]) - float(result["removed_mass_kg"])) < 0.001, "Ledger input differs from removed mass")
	_assert(absf(float(result["mass_ledger"]["output_total_kg"]) - float(result["removed_mass_kg"])) < 0.001, "Ledger output differs from removed mass")
	var query = ContinuousQueryScript.new()
	_assert_ok(query.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		service.snapshot_store()
	), "Continuous query configuration failed")
	var original_center: Dictionary = GeneratorScript.sample_validated(
		material_catalog, generator_profile, feature_catalog, center_m
	)
	_assert(float(original_center["occupancy_ratio"]) > 0.0, "Procedural tunnel center is not occupied")
	var mutated_center: Dictionary = query.sample(center_m, 5)
	_assert_ok(SampleScript.validate(mutated_center), "Mutated center sample rejected")
	_assert(float(mutated_center["occupancy_ratio"]) == 0.0, "Persistent tunnel center is not vacuum")
	_assert(float(mutated_center["signed_distance_m"]) >= 0.0, "Persistent tunnel center has negative SDF")
	var wall_sample: Dictionary = query.sample(center_m + Vector3(25.0, 0.0, 0.0), 5)
	_assert_ok(SampleScript.validate(wall_sample), "Interpolated tunnel wall sample rejected")
	_assert(float(wall_sample["occupancy_ratio"]) > 0.0, "Tunnel wall sample is not occupied")
	_assert(not wall_sample["flags"].has("matter-state/vacuum"), "Occupied tunnel wall retained vacuum flag")
	var ray: Dictionary = query.raycast(center_m, Vector3.RIGHT, 80.0, 5, 0.5, 0.25, 128)
	_assert_ok(ray, "Tunnel cavity raycast failed")
	_assert(bool(ray["details"].get("hit", false)), "Tunnel cavity raycast missed wall")
	_assert(float(ray["details"].get("distance_m", 0.0)) > 10.0, "Tunnel raycast distance is invalid")
	_assert(float(ray["details"].get("distance_m", 0.0)) < 30.0, "Tunnel raycast exceeded expected wall range")
	for changed in result["changed_bricks"]:
		var address: Dictionary = changed["address"]
		_assert(service.snapshot_store().has(address), "Changed snapshot is missing from persistent store")
		_assert(service.snapshot_store().revision(address) == int(changed["new_revision"]), "Changed snapshot revision mismatch")
	var store_hash: String = service.snapshot_store().content_hash()
	var repeat_request: Dictionary = service.create_excavation_request(
		"matter-operation/cross-brick-tunnel-repeat",
		"actor/test-miner",
		"tool/high-speed-drill",
		start_m,
		end_m,
		radius_m,
		JSON_SAFE_ENERGY_BUDGET_J,
		4
	)
	var repeat_result: Dictionary = service.execute(repeat_request)
	_assert_ok(ResultScript.validate(repeat_result), "Repeated tunnel result rejected")
	_assert(String(repeat_result["status"]) == "REJECTED", "Identical second dig unexpectedly committed")
	_assert(String(repeat_result["error_code"]) == "MATTER_MUTATION_NO_EFFECT", "Repeated tunnel rejection changed")
	_assert(service.snapshot_store().content_hash() == store_hash, "No-effect dig changed persistent store")
	_cross_tunnel_context = {
		"service": service,
		"result": result.duplicate(true),
		"center_m": center_m,
	}


func _test_stale_revision_and_failed_transactions() -> void:
	var fixture: Dictionary = _single_cell_surface_fixture()
	_assert(not fixture.is_empty(), "Failed-transaction fixture missing")
	if fixture.is_empty():
		return
	var bundle: Dictionary = _new_service(1.0e15, 1.0e12)
	var service = bundle["service"]
	var stale_request: Dictionary = service.create_excavation_request(
		"matter-operation/stale-request",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"], fixture["end_m"], float(fixture["radius_m"]), JSON_SAFE_ENERGY_BUDGET_J
	)
	var commit_request: Dictionary = service.create_excavation_request(
		"matter-operation/stale-preceding-commit",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"], fixture["end_m"], float(fixture["radius_m"]), JSON_SAFE_ENERGY_BUDGET_J
	)
	var commit_result: Dictionary = service.execute(commit_request)
	_assert(String(commit_result.get("status", "")) == "COMMITTED", "Stale fixture preceding commit failed")
	var hash_after_commit: String = service.snapshot_store().content_hash()
	var receiver_after_commit: String = service.material_receiver().content_hash()
	var stale_result: Dictionary = service.execute(stale_request)
	_assert_ok(ResultScript.validate(stale_result), "Stale revision result rejected")
	_assert(String(stale_result["status"]) == "REJECTED", "Stale request committed")
	_assert(String(stale_result["error_code"]) == "MATTER_MUTATION_STALE_REVISION", "Stale revision error changed")
	_assert(service.snapshot_store().content_hash() == hash_after_commit, "Stale request changed snapshots")
	_assert(service.material_receiver().content_hash() == receiver_after_commit, "Stale request changed receiver")
	var energy_bundle: Dictionary = _new_service(1.0e15, 1.0e12)
	var low_energy_service = energy_bundle["service"]
	var low_energy_request: Dictionary = low_energy_service.create_excavation_request(
		"matter-operation/low-energy",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"], fixture["end_m"], float(fixture["radius_m"]), 1.0
	)
	var low_store_hash: String = low_energy_service.snapshot_store().content_hash()
	var low_receiver_hash: String = low_energy_service.material_receiver().content_hash()
	var low_energy_result: Dictionary = low_energy_service.execute(low_energy_request)
	_assert_ok(ResultScript.validate(low_energy_result), "Low-energy result rejected")
	_assert(String(low_energy_result["error_code"]) == "MATTER_MUTATION_INSUFFICIENT_ENERGY", "Low-energy error changed")
	_assert(low_energy_service.snapshot_store().content_hash() == low_store_hash, "Low-energy request changed snapshots")
	_assert(low_energy_service.material_receiver().content_hash() == low_receiver_hash, "Low-energy request changed receiver")
	_assert(low_energy_service.material_receiver().reservation_count() == 0, "Low-energy request leaked reservation")
	var full_bundle: Dictionary = _new_service(1.0, 0.001)
	var full_service = full_bundle["service"]
	var full_request: Dictionary = full_service.create_excavation_request(
		"matter-operation/full-container",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"], fixture["end_m"], float(fixture["radius_m"]), JSON_SAFE_ENERGY_BUDGET_J
	)
	var full_store_hash: String = full_service.snapshot_store().content_hash()
	var full_result: Dictionary = full_service.execute(full_request)
	_assert_ok(ResultScript.validate(full_result), "Full-container result rejected")
	_assert(String(full_result["status"]) == "REJECTED", "Full container request committed")
	_assert(String(full_result["error_code"]).begins_with("MATTER_RECEIVER_"), "Full container error changed")
	_assert(full_service.snapshot_store().content_hash() == full_store_hash, "Full container changed snapshots")
	_assert(full_service.material_receiver().batch_count() == 0, "Full container created a batch")
	_assert(full_service.material_receiver().reservation_count() == 0, "Full container leaked reservation")


func _test_post_commit_rollback() -> void:
	var fixture: Dictionary = _single_cell_surface_fixture()
	_assert(not fixture.is_empty(), "Post-commit rollback fixture missing")
	if fixture.is_empty():
		return
	var failing_journal = FailingJournalScript.new()
	var service = ServiceScript.new()
	var configuration: Dictionary = service.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		5,
		"container/mw4-rollback",
		1.0e15,
		1.0e12,
		null,
		null,
		failing_journal
	)
	_assert_ok(configuration, "Rollback service configuration failed")
	var request: Dictionary = service.create_excavation_request(
		"matter-operation/injected-journal-failure",
		"actor/test-miner",
		"tool/test-drill",
		fixture["start_m"],
		fixture["end_m"],
		float(fixture["radius_m"]),
		JSON_SAFE_ENERGY_BUDGET_J
	)
	_assert_ok(RequestScript.validate(request), "Rollback request rejected")
	var store_hash_before: String = service.snapshot_store().content_hash()
	var receiver_hash_before: String = service.material_receiver().content_hash()
	var result: Dictionary = service.execute(request)
	_assert_ok(ResultScript.validate(result), "Rollback result rejected")
	_assert(String(result["status"]) == "REJECTED", "Injected journal failure committed")
	_assert(String(result["error_code"]) == "MATTER_MUTATION_JOURNAL_COMMIT_FAILED", "Journal rollback error changed")
	_assert(service.snapshot_store().content_hash() == store_hash_before, "Journal failure retained snapshots")
	_assert(service.material_receiver().content_hash() == receiver_hash_before, "Journal failure retained material batch")
	_assert(service.material_receiver().batch_count() == 0, "Journal failure retained receiver batch")
	_assert(service.material_receiver().reservation_count() == 0, "Journal failure retained receiver reservation")


func _test_streamer_persistent_snapshot_projection() -> void:
	_assert(not _cross_tunnel_context.is_empty(), "Cross-brick context missing for streamer test")
	if _cross_tunnel_context.is_empty():
		return
	var service = _cross_tunnel_context["service"]
	var result: Dictionary = _cross_tunnel_context["result"]
	var center_m: Vector3 = _cross_tunnel_context["center_m"]
	var host := Node3D.new()
	var observer := Node3D.new()
	var streamer = StreamerScript.new()
	host.add_child(observer)
	host.add_child(streamer)
	get_root().add_child(host)
	observer.position = center_m
	streamer.cell_level = 5
	streamer.load_radius_cells = 0
	streamer.max_builds_per_frame = 1
	streamer.build_collision = false
	var configuration: Dictionary = streamer.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		observer,
		service.snapshot_store()
	)
	_assert_ok(configuration, "Persistent streamer configuration failed")
	var addresses: Array = []
	for changed in result["changed_bricks"]:
		addresses.append(changed["address"])
	var invalidation: Dictionary = streamer.invalidate_brick_addresses(addresses)
	_assert_ok(invalidation, "Persistent streamer invalidation failed")
	_assert(invalidation["details"]["invalidated_cell_ids"].size() == addresses.size(), "Streamer invalidation lost cells")
	_assert(int(streamer.stats()["desired_count"]) == 1, "Focused streamer fixture materializes more than one cell")
	var built_any: bool = false
	for _iteration in range(4):
		if streamer.build_next_pending():
			built_any = true
		if int(streamer.stats()["pending_count"]) == 0:
			break
	_assert(built_any, "Persistent streamer built no pending bricks")
	_assert(int(streamer.stats()["failed_brick_count"]) == 0, "Persistent streamer has failed bricks")
	var center_cell: Dictionary = CellGridScript.address_for_position(grid_profile, center_m, 5)
	var center_address: Dictionary = BrickLayoutScript.brick_address(grid_profile, center_cell)
	_assert(service.snapshot_store().has(center_address), "Center tunnel snapshot is missing")
	var stored_snapshot: Dictionary = service.snapshot_store().get_snapshot(center_address)
	var procedural_snapshot: Dictionary = MaterializerScript.materialize(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		center_cell,
		0
	)
	var stored_mesh: Dictionary = MesherScript.build_mesh_data(stored_snapshot, grid_profile)
	var procedural_mesh: Dictionary = MesherScript.build_mesh_data(procedural_snapshot, grid_profile)
	_assert_ok(MeshDataScript.validate(stored_mesh), "Stored mutation mesh rejected")
	_assert_ok(MeshDataScript.validate(procedural_mesh), "Procedural comparison mesh rejected")
	_assert(String(stored_mesh["content_hash"]) != String(procedural_mesh["content_hash"]), "Persistent mutation did not change center mesh projection")
	host.queue_free()


func _new_service(maximum_mass_kg: float, maximum_volume_m3: float) -> Dictionary:
	var service = ServiceScript.new()
	var configuration: Dictionary = service.configure(
		body,
		material_catalog,
		generator_profile,
		feature_catalog,
		grid_profile,
		5,
		"container/mw4-lab",
		maximum_mass_kg,
		maximum_volume_m3
	)
	_assert_ok(configuration, "MW4 service configuration failed")
	return {"service": service}


func _single_cell_surface_fixture() -> Dictionary:
	if not _single_cell_fixture_cache.is_empty():
		return _single_cell_fixture_cache.duplicate(true)
	for y_step in range(-4, 5):
		for z_step in range(-4, 5):
			var direction := Vector3(1.0, float(y_step) * 0.035, float(z_step) * 0.035).normalized()
			var radius_m: float = GeneratorScript.surface_radius_validated(
				generator_profile, feature_catalog, direction
			)
			var surface_m: Vector3 = direction * radius_m
			var start_m: Vector3 = surface_m + direction * 7.0
			var end_m: Vector3 = surface_m - direction * 14.0
			var shape: Dictionary = RequestScript.create_shape(
				"CAPSULE", _array(start_m), _array(end_m), 6.0
			)
			var targets: Array = SweptShapeScript.affected_brick_addresses(
				grid_profile, shape, 5
			)
			if targets.size() == 1:
				_single_cell_fixture_cache = {
					"start_m": start_m,
					"end_m": end_m,
					"radius_m": 6.0,
					"address": targets[0],
				}
				return _single_cell_fixture_cache.duplicate(true)
	return {}


func _clone_snapshot_with_revision(snapshot: Dictionary, revision: int) -> Dictionary:
	if not bool(SnapshotScript.validate(snapshot).get("success", false)):
		return {}
	var samples: Array = []
	for index in range(int(snapshot["sample_count"])):
		samples.append(SnapshotScript.sample_payload_at_validated(snapshot, index))
	return SnapshotScript.create(
		"matter-snapshot/%s/revision/%d" % [
			String(snapshot["address"]["address_id"]).sha256_text(), revision,
		],
		snapshot["address"],
		String(snapshot["body_definition_hash"]),
		String(snapshot["generator_version"]),
		int(snapshot["generator_seed"]),
		revision,
		samples
	)


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [
		message, String(result.get("error_code", "UNKNOWN"))
	])


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	var elapsed_s: float = float(Time.get_ticks_usec() - _suite_started_usec) / 1000000.0
	if failures.is_empty():
		print("MW4 matter mutations: PASS (%d assertions / %.3f s)" % [assertions, elapsed_s])
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("MW4 matter mutations: FAIL (%d failures / %d assertions / %.3f s)" % [
		failures.size(), assertions, elapsed_s
	])
	quit(1)


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
