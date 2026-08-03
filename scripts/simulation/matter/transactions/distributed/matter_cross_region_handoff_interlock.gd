extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")
const Checkpoint = preload("res://scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_checkpoint.gd")

var _transaction_state_provider = null


func configure(transaction_state_provider) -> Dictionary:
	if transaction_state_provider == null or not transaction_state_provider.has_method("checkpoint"):
		return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_STATE_PROVIDER_REQUIRED")
	_transaction_state_provider = transaction_state_provider
	return MatterUtils.success()


func validate_handoff(region_id: String) -> Dictionary:
	if not MatterUtils.is_canonical_id(region_id, 2):
		return MatterUtils.failure("INVALID_MATTER_CROSS_REGION_HANDOFF_INTERLOCK_REGION")
	var loaded: Dictionary = _load_checkpoint()
	if not bool(loaded.get("success", false)):
		return loaded
	var normalized: String = region_id.strip_edges().to_lower()
	for raw_reservation in loaded["details"]["checkpoint"]["region_reservations"]:
		var reservation: Dictionary = raw_reservation
		if String(reservation["region_id"]) == normalized:
			return MatterUtils.failure("MATTER_CROSS_REGION_TRANSACTION_RESERVES_HANDOFF_REGION", {
				"region_id": reservation["region_id"],
				"transaction_id": reservation["transaction_id"],
				"participant_checksum": reservation["participant_checksum"],
			})
	return MatterUtils.success({"region_id": normalized})


func reserved_transaction(region_id: String) -> Dictionary:
	if not MatterUtils.is_canonical_id(region_id, 2):
		return {}
	var loaded: Dictionary = _load_checkpoint()
	if not bool(loaded.get("success", false)):
		return {}
	var normalized: String = region_id.strip_edges().to_lower()
	for raw_reservation in loaded["details"]["checkpoint"]["region_reservations"]:
		var reservation: Dictionary = raw_reservation
		if String(reservation["region_id"]) == normalized:
			return reservation.duplicate(true)
	return {}


func _load_checkpoint() -> Dictionary:
	if _transaction_state_provider == null:
		return MatterUtils.failure("MATTER_CROSS_REGION_HANDOFF_INTERLOCK_NOT_CONFIGURED")
	var current = _transaction_state_provider.call("checkpoint")
	if typeof(current) != TYPE_DICTIONARY or Dictionary(current).is_empty():
		return MatterUtils.failure("MATTER_CROSS_REGION_HANDOFF_INTERLOCK_CHECKPOINT_UNAVAILABLE")
	var checkpoint_value: Dictionary = current
	var checked: Dictionary = Checkpoint.validate(checkpoint_value)
	if not bool(checked.get("success", false)):
		return MatterUtils.failure("MATTER_CROSS_REGION_HANDOFF_INTERLOCK_CHECKPOINT_INVALID", {
			"cause": checked,
		})
	return MatterUtils.success({"checkpoint": checkpoint_value.duplicate(true)})
