extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const BatchScript = preload("res://scripts/simulation/matter/contracts/matter_material_batch.gd")

var _configured: bool = false
var _container_id: String = ""
var _maximum_mass_kg: float = 0.0
var _maximum_volume_m3: float = 0.0
var _batches_by_id: Dictionary = {}
var _reserved_by_operation_id: Dictionary = {}


func configure(container_id: String, maximum_mass_kg: float, maximum_volume_m3: float) -> Dictionary:
	var normalized_id: String = container_id.strip_edges().to_lower()
	if not MatterUtilsScript.is_canonical_id(normalized_id, 2) \
		or not MatterUtilsScript.is_positive_number(maximum_mass_kg) \
		or not MatterUtilsScript.is_positive_number(maximum_volume_m3):
		return MatterUtilsScript.failure("INVALID_MATTER_RECEIVER_CONFIGURATION")
	_container_id = normalized_id
	_maximum_mass_kg = maximum_mass_kg
	_maximum_volume_m3 = maximum_volume_m3
	_batches_by_id.clear()
	_reserved_by_operation_id.clear()
	_configured = true
	return MatterUtilsScript.success()


func reserve(operation_id: String, mass_kg: float, volume_m3: float) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_RECEIVER_NOT_CONFIGURED")
	var normalized_operation_id: String = operation_id.strip_edges().to_lower()
	if not MatterUtilsScript.is_canonical_id(normalized_operation_id, 2) \
		or not MatterUtilsScript.is_positive_number(mass_kg) \
		or not MatterUtilsScript.is_positive_number(volume_m3):
		return MatterUtilsScript.failure("INVALID_MATTER_RECEIVER_RESERVATION")
	if _reserved_by_operation_id.has(normalized_operation_id):
		var existing: Dictionary = _reserved_by_operation_id[normalized_operation_id]
		if MatterUtilsScript.approximately_equal(float(existing["mass_kg"]), mass_kg) \
			and MatterUtilsScript.approximately_equal(float(existing["volume_m3"]), volume_m3):
			return MatterUtilsScript.success({"status": "IDEMPOTENT"})
		return MatterUtilsScript.failure("MATTER_RECEIVER_RESERVATION_CONFLICT")
	if total_mass_kg() + reserved_mass_kg() + mass_kg > _maximum_mass_kg \
		+ MatterUtilsScript.DEFAULT_FLOAT_TOLERANCE:
		return MatterUtilsScript.failure("MATTER_RECEIVER_MASS_CAPACITY_EXCEEDED")
	if total_volume_m3() + reserved_volume_m3() + volume_m3 > _maximum_volume_m3 \
		+ MatterUtilsScript.DEFAULT_FLOAT_TOLERANCE:
		return MatterUtilsScript.failure("MATTER_RECEIVER_VOLUME_CAPACITY_EXCEEDED")
	_reserved_by_operation_id[normalized_operation_id] = {
		"mass_kg": mass_kg,
		"volume_m3": volume_m3,
	}
	return MatterUtilsScript.success({"status": "RESERVED"})


func commit_reserved(batch: Dictionary) -> Dictionary:
	if not _configured or not bool(BatchScript.validate(batch).get("success", false)):
		return MatterUtilsScript.failure("INVALID_MATTER_RECEIVER_BATCH")
	if String(batch["container_id"]) != _container_id:
		return MatterUtilsScript.failure("MATTER_RECEIVER_CONTAINER_MISMATCH")
	var operation_id: String = String(batch["source_operation_id"])
	if not _reserved_by_operation_id.has(operation_id):
		return MatterUtilsScript.failure("MATTER_RECEIVER_RESERVATION_MISSING")
	var reservation: Dictionary = _reserved_by_operation_id[operation_id]
	if not MatterUtilsScript.approximately_equal(
		float(reservation["mass_kg"]), float(batch["total_mass_kg"])
	) or not MatterUtilsScript.approximately_equal(
		float(reservation["volume_m3"]), float(batch["bulk_volume_m3"])
	):
		return MatterUtilsScript.failure("MATTER_RECEIVER_RESERVATION_BATCH_MISMATCH")
	var batch_id: String = String(batch["batch_id"])
	if _batches_by_id.has(batch_id):
		if _batches_by_id[batch_id] == batch:
			_reserved_by_operation_id.erase(operation_id)
			return MatterUtilsScript.success({"status": "IDEMPOTENT"})
		return MatterUtilsScript.failure("MATTER_RECEIVER_BATCH_CONFLICT")
	_batches_by_id[batch_id] = batch.duplicate(true)
	_reserved_by_operation_id.erase(operation_id)
	return MatterUtilsScript.success({"status": "COMMITTED"})


func release_reservation(operation_id: String) -> void:
	_reserved_by_operation_id.erase(operation_id.strip_edges().to_lower())


func rollback_batch(batch_id: String, operation_id: String) -> Dictionary:
	if not _configured:
		return MatterUtilsScript.failure("MATTER_RECEIVER_NOT_CONFIGURED")
	var normalized_batch_id: String = batch_id.strip_edges().to_lower()
	var normalized_operation_id: String = operation_id.strip_edges().to_lower()
	if not _batches_by_id.has(normalized_batch_id):
		return MatterUtilsScript.success({"status": "ABSENT"})
	var batch: Dictionary = _batches_by_id[normalized_batch_id]
	if String(batch["source_operation_id"]) != normalized_operation_id:
		return MatterUtilsScript.failure("MATTER_RECEIVER_ROLLBACK_OPERATION_MISMATCH")
	_batches_by_id.erase(normalized_batch_id)
	return MatterUtilsScript.success({"status": "ROLLED_BACK"})


func container_id() -> String:
	return _container_id


func batch_count() -> int:
	return _batches_by_id.size()


func reservation_count() -> int:
	return _reserved_by_operation_id.size()


func total_mass_kg() -> float:
	var total: float = 0.0
	for batch in _batches_by_id.values():
		total += float(batch["total_mass_kg"])
	return total


func total_volume_m3() -> float:
	var total: float = 0.0
	for batch in _batches_by_id.values():
		total += float(batch["bulk_volume_m3"])
	return total


func reserved_mass_kg() -> float:
	var total: float = 0.0
	for reservation in _reserved_by_operation_id.values():
		total += float(reservation["mass_kg"])
	return total


func reserved_volume_m3() -> float:
	var total: float = 0.0
	for reservation in _reserved_by_operation_id.values():
		total += float(reservation["volume_m3"])
	return total


func get_batch(batch_id: String) -> Dictionary:
	return Dictionary(_batches_by_id.get(batch_id.strip_edges().to_lower(), {})).duplicate(true)


func content_hash() -> String:
	if not _configured:
		return ""
	var batch_ids: Array = _batches_by_id.keys()
	batch_ids.sort()
	var entries: Array = []
	for batch_id in batch_ids:
		entries.append({
			"batch_id": String(batch_id),
			"checksum": String(_batches_by_id[batch_id]["checksum"]),
		})
	var operation_ids: Array = _reserved_by_operation_id.keys()
	operation_ids.sort()
	var reservations: Array = []
	for operation_id in operation_ids:
		var reservation: Dictionary = _reserved_by_operation_id[operation_id]
		reservations.append({
			"operation_id": String(operation_id),
			"mass_kg": float(reservation["mass_kg"]),
			"volume_m3": float(reservation["volume_m3"]),
		})
	return MatterUtilsScript.payload_hash({
		"container_id": _container_id,
		"maximum_mass_kg": _maximum_mass_kg,
		"maximum_volume_m3": _maximum_volume_m3,
		"entries": entries,
		"reservations": reservations,
	})
