extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BodyScript = preload("res://scripts/simulation/matter/contracts/matter_body_definition.gd")
const RequestScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_request.gd")
const ResultScript = preload("res://scripts/simulation/matter/contracts/matter_mutation_result.gd")
const LedgerScript = preload("res://scripts/simulation/matter/contracts/matter_mass_ledger.gd")
const CompositionScript = preload("res://scripts/simulation/matter/contracts/matter_composition.gd")
const BatchScript = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")
const MaterialCatalogScript = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const GridProfileScript = preload("res://scripts/simulation/matter/spatial/matter_spatial_grid_profile.gd")
const BrickLayoutScript = preload("res://scripts/simulation/matter/spatial/matter_brick_layout.gd")
const MaterializerScript = preload("res://scripts/simulation/matter/storage/matter_brick_materializer.gd")
const SparseStoreScript = preload("res://scripts/simulation/matter/storage/matter_sparse_brick_store.gd")
const GeneratorScript = preload("res://scripts/simulation/matter/generation/fixed_seed_asteroid_generator.gd")
const SweptShapeScript = preload("res://scripts/simulation/matter/mutation/matter_swept_shape.gd")
const KernelScript = preload("res://scripts/simulation/matter/mutation/matter_excavation_kernel.gd")
const JournalScript = preload("res://scripts/simulation/matter/mutation/matter_mutation_journal.gd")
const ReceiverScript = preload("res://scripts/simulation/matter/mutation/matter_material_receiver.gd")

const MIN_COMMITTED_MASS_KG: float = 0.001
const LEDGER_TOLERANCE_KG: float = 0.001

var _configured: bool = false
var _body: Dictionary = {}
var _material_catalog: Dictionary = {}
var _generator_profile: Dictionary = {}
var _feature_catalog: Dictionary = {}
var _grid_profile: Dictionary = {}
var _cell_level: int = 0
var _store = null
var _receiver = null
var _journal = null


func configure(
	body: Dictionary,
	material_catalog: Dictionary,
	generator_profile: Dictionary,
	feature_catalog: Dictionary,
	grid_profile: Dictionary,
	cell_level: int,
	container_id: String,
	maximum_receiver_mass_kg: float,
	maximum_receiver_volume_m3: float,
	snapshot_store = null,
	material_receiver = null,
	mutation_journal = null
) -> Dictionary:
	if not bool(BodyScript.validate(body).get("success", false)) \
		or not bool(MaterialCatalogScript.validate(material_catalog).get("success", false)) \
		or not bool(GridProfileScript.validate(grid_profile).get("success", false)) \
		or not bool(GeneratorScript.validate_configuration(
			body, material_catalog, generator_profile, feature_catalog
		).get("success", false)) \
		or cell_level < 1 or cell_level > int(grid_profile.get("max_level", -1)):
		return MatterUtilsScript.failure("INVALID_MATTER_EXCAVATION_CONFIGURATION")
	if String(grid_profile["body_id"]) != String(body["body_id"]) \
		or String(grid_profile["body_frame_id"]) != String(body["body_frame_id"]):
		return MatterUtilsScript.failure("MATTER_EXCAVATION_BODY_GRID_MISMATCH")
	_body = body.duplicate(true)
	_material_catalog = material_catalog.duplicate(true)
	_generator_profile = generator_profile.duplicate(true)
	_feature_catalog = feature_catalog.duplicate(true)
	_grid_profile = grid_profile.duplicate(true)
	_cell_level = cell_level
	if snapshot_store == null:
		_store = SparseStoreScript.new()
		var store_configuration: Dictionary = _store.configure(_body, _grid_profile)
		if not bool(store_configuration.get("success", false)):
			_store = null
			return store_configuration
	else:
		if not snapshot_store.has_method("put_many_atomic") \
			or not snapshot_store.has_method("rollback_many_atomic") \
			or not snapshot_store.has_method("get_snapshot") \
			or not snapshot_store.has_method("revision") \
			or not snapshot_store.has_method("has"):
			return MatterUtilsScript.failure("INVALID_MATTER_EXCAVATION_STORE")
		_store = snapshot_store
	if material_receiver == null:
		_receiver = ReceiverScript.new()
		var receiver_configuration: Dictionary = _receiver.configure(
			container_id, maximum_receiver_mass_kg, maximum_receiver_volume_m3
		)
		if not bool(receiver_configuration.get("success", false)):
			return receiver_configuration
	else:
		if not material_receiver.has_method("reserve") \
			or not material_receiver.has_method("commit_reserved") \
			or not material_receiver.has_method("release_reservation") \
			or not material_receiver.has_method("rollback_batch") \
			or not material_receiver.has_method("container_id") \
			or String(material_receiver.container_id()) != container_id.strip_edges().to_lower():
			return MatterUtilsScript.failure("INVALID_MATTER_EXCAVATION_RECEIVER")
		_receiver = material_receiver
	if mutation_journal == null:
		_journal = JournalScript.new()
	else:
		if not mutation_journal.has_method("resolve") or not mutation_journal.has_method("record"):
			return MatterUtilsScript.failure("INVALID_MATTER_EXCAVATION_JOURNAL")
		_journal = mutation_journal
	_configured = true
	return MatterUtilsScript.success()


func create_excavation_request(
	operation_id: String,
	actor_id: String,
	tool_id: String,
	start_position_m: Vector3,
	end_position_m: Vector3,
	radius_m: float,
	energy_budget_j: float,
	client_tick: int = 0
) -> Dictionary:
	if not _configured:
		return {}
	var shape: Dictionary = RequestScript.create_shape(
		"CAPSULE",
		_array(start_position_m),
		_array(end_position_m),
		radius_m
	)
	if not bool(RequestScript.validate_shape(shape).get("success", false)):
		return {}
	var target_bricks: Array = SweptShapeScript.affected_brick_addresses(
		_grid_profile, shape, _cell_level
	)
	if target_bricks.is_empty():
		return {}
	var expected_revision_by_address: Dictionary = {}
	for address in target_bricks:
		expected_revision_by_address[String(address["address_id"])] = _store.revision(address)
	var request: Dictionary = RequestScript.create({
		"operation_id": operation_id,
		"body_id": _body["body_id"],
		"actor_id": actor_id,
		"tool_id": tool_id,
		"operation_type": "EXCAVATE",
		"target_bricks": target_bricks,
		"expected_revision_by_address": expected_revision_by_address,
		"shape": shape,
		"source_container_id": "",
		"destination_container_id": _receiver.container_id(),
		"requested_mass_kg": 0.0,
		"energy_budget_j": energy_budget_j,
		"client_tick": client_tick,
	})
	return request if bool(RequestScript.validate(request).get("success", false)) else {}


func execute(request: Dictionary) -> Dictionary:
	if not _configured or not bool(RequestScript.validate(request).get("success", false)):
		return {}
	var journal_resolution: Dictionary = _journal.resolve(request)
	if not bool(journal_resolution.get("success", false)):
		return _rejected_result(request, String(journal_resolution.get(
			"error_code", "MATTER_OPERATION_FINGERPRINT_CONFLICT"
		)), false)
	if String(journal_resolution.get("details", {}).get("status", "")) == "REPLAY":
		return Dictionary(journal_resolution["details"]["result"]).duplicate(true)
	var request_error: String = _validate_request_against_configuration(request)
	if not request_error.is_empty():
		return _rejected_result(request, request_error, true)
	var staged_snapshots: Array = []
	var previous_snapshot_by_address_id: Dictionary = {}
	var expected_revision_by_address_id: Dictionary = {}
	var committed_revision_by_address_id: Dictionary = {}
	var changed_bricks: Array = []
	var material_mass_kg: Dictionary = {}
	var removed_mass_kg: float = 0.0
	var removed_volume_m3: float = 0.0
	var mass_weighted_temperature_k: float = 0.0
	for index in range(request["target_bricks"].size()):
		var address: Dictionary = request["target_bricks"][index]
		var address_id: String = String(address["address_id"])
		var expected_revision: int = int(request["expected_revisions"][index])
		var current_revision: int = _store.revision(address)
		if current_revision != expected_revision:
			return _rejected_result(request, "MATTER_MUTATION_STALE_REVISION", true)
		var previous_snapshot: Dictionary = {}
		if _store.has(address):
			previous_snapshot = _store.get_snapshot(address)
		var source_snapshot: Dictionary = previous_snapshot
		if source_snapshot.is_empty():
			source_snapshot = MaterializerScript.materialize(
				_body,
				_material_catalog,
				_generator_profile,
				_feature_catalog,
				_grid_profile,
				address["cell_address"],
				0
			)
		if source_snapshot.is_empty() or int(source_snapshot["state_revision"]) != expected_revision:
			return _rejected_result(request, "MATTER_MUTATION_SOURCE_SNAPSHOT_FAILED", true)
		var mutation: Dictionary = KernelScript.apply_excavation(
			source_snapshot, _grid_profile, request["shape"]
		)
		if not bool(mutation.get("success", false)):
			return _rejected_result(request, String(mutation.get(
				"error_code", "MATTER_MUTATION_KERNEL_FAILED"
			)), true)
		if not bool(mutation["details"].get("changed", false)):
			continue
		var new_snapshot: Dictionary = mutation["details"]["snapshot"]
		staged_snapshots.append(new_snapshot)
		previous_snapshot_by_address_id[address_id] = previous_snapshot.duplicate(true)
		expected_revision_by_address_id[address_id] = expected_revision
		committed_revision_by_address_id[address_id] = int(new_snapshot["state_revision"])
		changed_bricks.append({
			"address": address.duplicate(true),
			"previous_revision": expected_revision,
			"new_revision": int(new_snapshot["state_revision"]),
			"snapshot_checksum": String(new_snapshot["checksum"]),
		})
		removed_mass_kg += float(mutation["details"]["removed_mass_kg"])
		removed_volume_m3 += float(mutation["details"]["removed_volume_m3"])
		mass_weighted_temperature_k += float(
			mutation["details"]["mass_weighted_temperature_k"]
		)
		_merge_material_masses(material_mass_kg, mutation["details"]["material_mass_kg"])
	if staged_snapshots.is_empty() or removed_mass_kg < MIN_COMMITTED_MASS_KG \
		or removed_volume_m3 <= 0.0 or material_mass_kg.is_empty():
		return _rejected_result(request, "MATTER_MUTATION_NO_EFFECT", true)
	var required_energy_j: float = _required_energy_j(material_mass_kg)
	if required_energy_j < 0.0:
		return _rejected_result(request, "MATTER_MUTATION_UNKNOWN_MATERIAL", true)
	if float(request["energy_budget_j"]) + MatterUtilsScript.DEFAULT_FLOAT_TOLERANCE \
		< required_energy_j:
		return _rejected_result(request, "MATTER_MUTATION_INSUFFICIENT_ENERGY", true)
	var composition: Dictionary = CompositionScript.from_weights(material_mass_kg)
	if composition.is_empty():
		return _rejected_result(request, "MATTER_MUTATION_COMPOSITION_FAILED", true)
	var batch: Dictionary = BatchScript.create({
		"batch_id": "matter-batch/%s" % String(request["operation_id"]).sha256_text(),
		"container_id": _receiver.container_id(),
		"source_body_id": _body["body_id"],
		"source_operation_id": request["operation_id"],
		"total_mass_kg": removed_mass_kg,
		"bulk_volume_m3": removed_volume_m3,
		"composition": composition,
		"temperature_k": mass_weighted_temperature_k / removed_mass_kg,
	})
	if not bool(BatchScript.validate(batch).get("success", false)):
		return _rejected_result(request, "MATTER_MUTATION_BATCH_BUILD_FAILED", true)
	var reservation: Dictionary = _receiver.reserve(
		String(request["operation_id"]), removed_mass_kg, removed_volume_m3
	)
	if not bool(reservation.get("success", false)):
		return _rejected_result(request, String(reservation.get(
			"error_code", "MATTER_RECEIVER_CAPACITY_EXCEEDED"
		)), true)
	var ledger: Dictionary = _mass_ledger(request, material_mass_kg)
	if not bool(LedgerScript.validate(ledger).get("success", false)) or not bool(ledger["closed"]):
		_receiver.release_reservation(String(request["operation_id"]))
		return _rejected_result(request, "MATTER_MUTATION_MASS_LEDGER_OPEN", true)
	var result: Dictionary = ResultScript.create({
		"operation_id": request["operation_id"],
		"status": "COMMITTED",
		"changed_bricks": changed_bricks,
		"removed_mass_kg": removed_mass_kg,
		"deposited_mass_kg": 0.0,
		"extracted_composition": composition,
		"generated_heat_j": required_energy_j * 0.05,
		"consumed_energy_j": required_energy_j,
		"created_aggregate_ids": [String(batch["batch_id"])],
		"mass_ledger": ledger,
		"error_code": "",
	})
	if not bool(ResultScript.validate(result).get("success", false)):
		_receiver.release_reservation(String(request["operation_id"]))
		return _rejected_result(request, "MATTER_MUTATION_RESULT_BUILD_FAILED", true)
	var store_commit: Dictionary = _store.put_many_atomic(
		staged_snapshots, expected_revision_by_address_id
	)
	if not bool(store_commit.get("success", false)):
		_receiver.release_reservation(String(request["operation_id"]))
		return _rejected_result(request, String(store_commit.get(
			"error_code", "MATTER_MUTATION_STORE_COMMIT_FAILED"
		)), true)
	var receiver_commit: Dictionary = _receiver.commit_reserved(batch)
	if not bool(receiver_commit.get("success", false)):
		var receiver_store_rollback: Dictionary = _store.rollback_many_atomic(
			previous_snapshot_by_address_id, committed_revision_by_address_id
		)
		_receiver.release_reservation(String(request["operation_id"]))
		if not bool(receiver_store_rollback.get("success", false)):
			return _rejected_result(request, "MATTER_MUTATION_STORE_ROLLBACK_FAILED", false)
		return _rejected_result(request, "MATTER_MUTATION_RECEIVER_COMMIT_FAILED", true)
	var journal_record: Dictionary = _journal.record(request, result)
	if not bool(journal_record.get("success", false)):
		var receiver_rollback: Dictionary = _receiver.rollback_batch(
			String(batch["batch_id"]), String(request["operation_id"])
		)
		var journal_store_rollback: Dictionary = _store.rollback_many_atomic(
			previous_snapshot_by_address_id, committed_revision_by_address_id
		)
		if not bool(receiver_rollback.get("success", false)) \
			or not bool(journal_store_rollback.get("success", false)):
			return _rejected_result(request, "MATTER_MUTATION_COMPENSATION_FAILED", false)
		return _rejected_result(request, "MATTER_MUTATION_JOURNAL_COMMIT_FAILED", false)
	return result


func snapshot_store():
	return _store


func material_receiver():
	return _receiver


func mutation_journal():
	return _journal


func cell_level() -> int:
	return _cell_level


func _validate_request_against_configuration(request: Dictionary) -> String:
	if String(request["body_id"]) != String(_body["body_id"]):
		return "MATTER_MUTATION_BODY_MISMATCH"
	if String(request["operation_type"]) != "EXCAVATE":
		return "MW4_ONLY_SUPPORTS_EXCAVATE"
	if String(request["shape"]["kind"]) != "CAPSULE":
		return "MW4_ONLY_SUPPORTS_SWEPT_CAPSULE"
	if String(request["destination_container_id"]) != _receiver.container_id():
		return "MATTER_MUTATION_DESTINATION_MISMATCH"
	var planned: Array = SweptShapeScript.affected_brick_addresses(
		_grid_profile, request["shape"], _cell_level
	)
	if planned.size() != request["target_bricks"].size():
		return "MATTER_MUTATION_TARGET_SET_MISMATCH"
	for index in range(planned.size()):
		if planned[index] != request["target_bricks"][index]:
			return "MATTER_MUTATION_TARGET_SET_MISMATCH"
	return ""


func _rejected_result(request: Dictionary, error_code: String, record_result: bool) -> Dictionary:
	var operation_id: String = String(request.get("operation_id", "matter-operation/rejected"))
	var ledger: Dictionary = LedgerScript.create(operation_id, [], [], LEDGER_TOLERANCE_KG)
	var result: Dictionary = ResultScript.create({
		"operation_id": operation_id,
		"status": "REJECTED",
		"changed_bricks": [],
		"removed_mass_kg": 0.0,
		"deposited_mass_kg": 0.0,
		"extracted_composition": CompositionScript.empty(),
		"generated_heat_j": 0.0,
		"consumed_energy_j": 0.0,
		"created_aggregate_ids": [],
		"mass_ledger": ledger,
		"error_code": error_code,
	})
	if record_result and bool(RequestScript.validate(request).get("success", false)) \
		and bool(ResultScript.validate(result).get("success", false)):
		_journal.record(request, result)
	return result


func _required_energy_j(material_mass_kg: Dictionary) -> float:
	var result: float = 0.0
	for material_id in material_mass_kg.keys():
		var material: Dictionary = MaterialCatalogScript.material_by_id(
			_material_catalog, String(material_id)
		)
		if material.is_empty():
			return -1.0
		result += float(material_mass_kg[material_id]) * float(material["mining_energy_j_kg"])
	return result


func _mass_ledger(request: Dictionary, material_mass_kg: Dictionary) -> Dictionary:
	var inputs: Array = []
	var outputs: Array = []
	var material_ids: Array = material_mass_kg.keys()
	material_ids.sort()
	for material_id in material_ids:
		var mass_kg: float = float(material_mass_kg[material_id])
		if mass_kg <= 0.0:
			continue
		inputs.append({
			"account_id": "matter-account/asteroid-body",
			"material_id": String(material_id),
			"mass_kg": mass_kg,
		})
		outputs.append({
			"account_id": String(request["destination_container_id"]),
			"material_id": String(material_id),
			"mass_kg": mass_kg,
		})
	return LedgerScript.create(String(request["operation_id"]), inputs, outputs, LEDGER_TOLERANCE_KG)


static func _merge_material_masses(target: Dictionary, source: Dictionary) -> void:
	for material_id in source.keys():
		target[material_id] = float(target.get(material_id, 0.0)) + float(source[material_id])


static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
