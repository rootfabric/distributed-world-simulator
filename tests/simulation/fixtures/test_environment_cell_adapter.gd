extends RefCounted

const AggregateScript = preload("res://tests/simulation/fixtures/test_environment_cell_aggregate.gd")
const TypeReferenceScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const SpatialScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")
const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")

const PACKAGE_HASH: String = "0390956062ef23cd6f9c9bd0ee3b488c47e576b4dcedb14eef38d9dc359b8572"


func get_aggregate_kind() -> String:
	return AggregateScript.AGGREGATE_KIND


func supports_aggregate(value) -> bool:
	return value != null and value.get_script() == AggregateScript


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(validation.get("success", false)):
		return validation
	var identity: Dictionary = snapshot["descriptor"]["identity"]
	if String(identity["aggregate_kind"]) != AggregateScript.AGGREGATE_KIND or String(identity["state_schema"]) != AggregateScript.STATE_SCHEMA:
		return _failure("ENVIRONMENT_AGGREGATE_IDENTITY_MISMATCH")
	if String(snapshot["descriptor"]["spatial_scope"]["scope_kind"]) != "CELL":
		return _failure("ENVIRONMENT_AGGREGATE_REQUIRES_CELL_SCOPE")
	var state: Dictionary = snapshot["state"]
	var exact: Dictionary = UtilsScript.validate_exact_fields(state, ["temperature_k", "soil_moisture", "nutrients_by_id"])
	if not bool(exact.get("success", false)):
		return _failure("INVALID_ENVIRONMENT_AGGREGATE_STATE")
	if typeof(state["temperature_k"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(state["temperature_k"])) or float(state["temperature_k"]) <= 0.0:
		return _failure("INVALID_ENVIRONMENT_TEMPERATURE")
	if typeof(state["soil_moisture"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(state["soil_moisture"])) or float(state["soil_moisture"]) < 0.0 or float(state["soil_moisture"]) > 1.0:
		return _failure("INVALID_ENVIRONMENT_SOIL_MOISTURE")
	if typeof(state["nutrients_by_id"]) != TYPE_DICTIONARY:
		return _failure("INVALID_ENVIRONMENT_NUTRIENTS")
	for nutrient_id in state["nutrients_by_id"].keys():
		var amount = state["nutrients_by_id"][nutrient_id]
		if typeof(nutrient_id) != TYPE_STRING or String(nutrient_id).strip_edges().is_empty():
			return _failure("INVALID_ENVIRONMENT_NUTRIENT_ID")
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)) or float(amount) < 0.0:
			return _failure("INVALID_ENVIRONMENT_NUTRIENT_AMOUNT")
	return {"success": true, "error_code": "", "message": ""}


func validate_delta(delta: Dictionary) -> Dictionary:
	var validation: Dictionary = DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return validation
	if String(delta["aggregate_kind"]) != AggregateScript.AGGREGATE_KIND or String(delta["state_schema"]) != AggregateScript.STATE_SCHEMA:
		return _failure("ENVIRONMENT_AGGREGATE_DELTA_IDENTITY_MISMATCH")
	for path_value in delta["changed_fields"].keys():
		if String(path_value).split(".", true)[0] in ["item_instance_id", "physics_state", "spatial_ref"]:
			return _failure("ENVIRONMENT_AGGREGATE_FORBIDDEN_FIELD")
	return {"success": true, "error_code": "", "message": ""}


func export_snapshot(value, snapshot_id: String) -> Dictionary:
	if not supports_aggregate(value):
		return {}
	var type_reference: Dictionary = TypeReferenceScript.create(
		"core:test-environment-cell",
		"1.0.0",
		PACKAGE_HASH,
		AggregateScript.STATE_SCHEMA
	)
	var descriptor: Dictionary = DescriptorScript.create(
		IdentityScript.create(value.aggregate_id, AggregateScript.AGGREGATE_KIND, AggregateScript.STATE_SCHEMA, type_reference),
		AuthorityScript.create(value.authority_owner_id, value.authority_epoch, value.state_revision, value.server_tick),
		SpatialScopeScript.create(SpatialScopeScript.KIND_CELL, {"cell_id": value.cell_id}),
		{}
	)
	return SnapshotScript.create(snapshot_id, descriptor, value.state)


func export_delta(base_snapshot: Dictionary, value, delta_id: String) -> Dictionary:
	if not supports_aggregate(value) or not bool(SnapshotScript.validate(base_snapshot).get("success", false)):
		return {}
	var previous_state: Dictionary = base_snapshot["state"]
	var changed: Dictionary = {}
	var removed: Array = []
	for key in value.state.keys():
		if not previous_state.has(key) or previous_state[key] != value.state[key]:
			changed[String(key)] = value.state[key]
	for key in previous_state.keys():
		if not value.state.has(key):
			removed.append(String(key))
	return DeltaScript.create(
		delta_id,
		value.aggregate_id,
		AggregateScript.AGGREGATE_KIND,
		AggregateScript.STATE_SCHEMA,
		value.authority_owner_id,
		value.authority_epoch,
		int(base_snapshot["descriptor"]["authority"]["state_revision"]),
		value.state_revision,
		value.server_tick,
		changed,
		removed
	)


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
