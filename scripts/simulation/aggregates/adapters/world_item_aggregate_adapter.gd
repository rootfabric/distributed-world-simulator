extends RefCounted

const WorldEntityAggregateScript = preload("res://scripts/simulation/entities/world_entity_aggregate.gd")
const TypeReferenceScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const SpatialScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")
const SnapshotScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const DeltaScript = preload("res://scripts/network/contracts/aggregate_delta_envelope.gd")

const AGGREGATE_KIND: String = "WORLD_ITEM"
const STATE_SCHEMA: String = "planet_simulator.world_item_aggregate_state.v1"
const PACKAGE_HASH: String = "2d0e1978c9a00c8406cc4519fcabc3f4098d0c8d738d851ad1a74d56ef5c65e8"


func get_aggregate_kind() -> String:
	return AGGREGATE_KIND


func supports_aggregate(value) -> bool:
	return value != null and value.get_script() == WorldEntityAggregateScript and bool(value.validate().get("success", false))


func validate_snapshot(snapshot: Dictionary) -> Dictionary:
	var envelope_validation: Dictionary = SnapshotScript.validate(snapshot)
	if not bool(envelope_validation.get("success", false)):
		return envelope_validation
	var descriptor: Dictionary = snapshot["descriptor"]
	var identity: Dictionary = descriptor["identity"]
	if String(identity["aggregate_kind"]) != AGGREGATE_KIND or String(identity["state_schema"]) != STATE_SCHEMA:
		return _failure("WORLD_ITEM_AGGREGATE_IDENTITY_MISMATCH")
	var state: Dictionary = snapshot["state"]
	var exact: Dictionary = preload("res://scripts/network/contracts/network_contract_utils.gd").validate_exact_fields(
		state,
		["entity_type", "item_instance_id", "physics_state", "domain_components", "lifecycle_state", "created_at_utc", "updated_at_utc"]
	)
	if not bool(exact.get("success", false)):
		return exact
	var scope: Dictionary = descriptor["spatial_scope"]
	if String(scope["scope_kind"]) != SpatialScopeScript.KIND_POINT:
		return _failure("WORLD_ITEM_REQUIRES_POINT_SCOPE")
	var legacy_snapshot: Dictionary = {
		"schema": WorldEntityAggregateScript.SCHEMA,
		"entity_id": String(identity["aggregate_id"]),
		"entity_type": state.get("entity_type"),
		"item_instance_id": state.get("item_instance_id"),
		"spatial_ref": scope.get("scope_data", {}).get("spatial_ref", {}),
		"partition_address": descriptor.get("partition_address", {}),
		"physics_state": state.get("physics_state", {}),
		"domain_components": state.get("domain_components", {}),
		"authority_owner_id": descriptor["authority"].get("authority_owner_id"),
		"authority_epoch": descriptor["authority"].get("authority_epoch"),
		"state_revision": descriptor["authority"].get("state_revision"),
		"last_simulation_tick": descriptor["authority"].get("server_tick"),
		"lifecycle_state": state.get("lifecycle_state"),
		"created_at_utc": state.get("created_at_utc"),
		"updated_at_utc": state.get("updated_at_utc"),
	}
	return WorldEntityAggregateScript.new().validate_snapshot_payload(legacy_snapshot)


func validate_delta(delta: Dictionary) -> Dictionary:
	var validation: Dictionary = DeltaScript.validate(delta)
	if not bool(validation.get("success", false)):
		return validation
	if String(delta["aggregate_kind"]) != AGGREGATE_KIND or String(delta["state_schema"]) != STATE_SCHEMA:
		return _failure("WORLD_ITEM_AGGREGATE_DELTA_IDENTITY_MISMATCH")
	var allowed: Array[String] = ["entity_type", "item_instance_id", "physics_state", "domain_components", "lifecycle_state", "created_at_utc", "updated_at_utc"]
	for path_value in delta["changed_fields"].keys():
		if not allowed.has(String(path_value).split(".", true)[0]):
			return _failure("WORLD_ITEM_AGGREGATE_DELTA_FIELD_REJECTED")
	for path_value in delta["removed_fields"]:
		if not allowed.has(String(path_value).split(".", true)[0]):
			return _failure("WORLD_ITEM_AGGREGATE_DELTA_FIELD_REJECTED")
	return {"success": true, "error_code": "", "message": ""}


func export_snapshot(value, snapshot_id: String) -> Dictionary:
	if not supports_aggregate(value) or snapshot_id.strip_edges().is_empty():
		return {}
	var type_reference: Dictionary = TypeReferenceScript.create(
		"core:world-item",
		"1.0.0",
		PACKAGE_HASH,
		STATE_SCHEMA
	)
	var identity: Dictionary = IdentityScript.create(
		String(value.entity_id),
		AGGREGATE_KIND,
		STATE_SCHEMA,
		type_reference
	)
	var authority: Dictionary = AuthorityScript.create(
		String(value.authority_owner_id),
		int(value.authority_epoch),
		int(value.state_revision),
		int(value.last_simulation_tick)
	)
	var scope: Dictionary = SpatialScopeScript.create(
		SpatialScopeScript.KIND_POINT,
		{"spatial_ref": Dictionary(value.spatial_ref).duplicate(true)}
	)
	var descriptor: Dictionary = DescriptorScript.create(
		identity,
		authority,
		scope,
		Dictionary(value.partition_address).duplicate(true)
	)
	return SnapshotScript.create(snapshot_id, descriptor, _state_from_aggregate(value))


func export_delta(base_snapshot: Dictionary, value, delta_id: String) -> Dictionary:
	if not supports_aggregate(value):
		return {}
	var base_validation: Dictionary = SnapshotScript.validate(base_snapshot)
	if not bool(base_validation.get("success", false)):
		return {}
	var identity: Dictionary = base_snapshot["descriptor"]["identity"]
	var authority: Dictionary = base_snapshot["descriptor"]["authority"]
	if String(identity["aggregate_kind"]) != AGGREGATE_KIND or String(identity["aggregate_id"]) != String(value.entity_id):
		return {}
	var next_state: Dictionary = _state_from_aggregate(value)
	var changed: Dictionary = {}
	var removed: Array = []
	var previous_state: Dictionary = base_snapshot["state"]
	for key in next_state.keys():
		if not previous_state.has(key) or previous_state[key] != next_state[key]:
			changed[String(key)] = next_state[key]
	for key in previous_state.keys():
		if not next_state.has(key):
			removed.append(String(key))
	return DeltaScript.create(
		delta_id,
		String(value.entity_id),
		AGGREGATE_KIND,
		STATE_SCHEMA,
		String(value.authority_owner_id),
		int(value.authority_epoch),
		int(authority["state_revision"]),
		int(value.state_revision),
		int(value.last_simulation_tick),
		changed,
		removed
	)


func _state_from_aggregate(value) -> Dictionary:
	return {
		"entity_type": String(value.entity_type),
		"item_instance_id": String(value.item_instance_id),
		"physics_state": Dictionary(value.physics_state).duplicate(true),
		"domain_components": Dictionary(value.domain_components).duplicate(true),
		"lifecycle_state": String(value.lifecycle_state),
		"created_at_utc": String(value.created_at_utc),
		"updated_at_utc": String(value.updated_at_utc),
	}


func _failure(code: String) -> Dictionary:
	return {"success": false, "error_code": code, "message": code}
