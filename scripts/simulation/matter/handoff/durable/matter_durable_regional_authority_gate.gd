extends RefCounted

const MatterUtils = preload("res://scripts/simulation/matter/matter_contract_utils.gd")

var _coordinator
var _legacy_authorizer := Callable()


func configure(coordinator, legacy_authorizer: Callable = Callable()) -> Dictionary:
	if coordinator == null or not coordinator.has_method("validate_write"):
		return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_COORDINATOR_REQUIRED")
	_coordinator = coordinator
	_legacy_authorizer = legacy_authorizer
	return MatterUtils.success({"legacy_authorizer_enabled": _legacy_authorizer.is_valid()})


func authorize(
	region_id: String,
	owner_id: String,
	authority_epoch: int,
	fencing_token: Dictionary,
	server_tick: int,
	request: Dictionary = {}
) -> Dictionary:
	if _coordinator == null:
		return MatterUtils.failure("MATTER_DURABLE_AUTHORITY_GATE_NOT_CONFIGURED")
	var durable: Dictionary = _coordinator.validate_write(
		region_id, owner_id, authority_epoch, fencing_token, server_tick
	)
	if not bool(durable.get("success", false)):
		return durable
	if _legacy_authorizer.is_valid():
		var legacy_result = _legacy_authorizer.call(
			region_id, owner_id, authority_epoch, request.duplicate(true)
		)
		if typeof(legacy_result) != TYPE_DICTIONARY:
			return MatterUtils.failure("MATTER_LEGACY_AUTHORITY_GATE_INVALID_RESULT")
		var legacy: Dictionary = legacy_result
		if not bool(legacy.get("success", false)):
			return legacy
	return MatterUtils.success({
		"lease": durable["details"]["lease"],
		"durable_fence_verified": true,
		"legacy_gate_verified": _legacy_authorizer.is_valid(),
	})
