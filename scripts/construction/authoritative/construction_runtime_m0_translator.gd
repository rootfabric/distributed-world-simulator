extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const RuntimePersistenceScript = preload("res://scripts/construction/behavior/construction_runtime_persistence_state.gd")
const DynamicTypeScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const SpatialScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")
const SnapshotEnvelopeScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")

const RUNTIME_KIND: String = "CONSTRUCTION_RUNTIME"
const PACKAGE_ID: String = "planet-simulator:construction"
const PACKAGE_VERSION: String = "1.0.0"
const PACKAGE_HASH: String = "c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0"


static func aggregate_id_for_construct(construct_id: String) -> String:
	var suffix: String = construct_id.trim_prefix("construct/").replace("/", ":")
	return "aggregate/construction/runtime:%s" % suffix


static func build_checkpoint_batch(
	operation_id: String,
	state: Dictionary,
	authority_owner_id: String,
	authority_epoch: int,
	current_revision: int,
	server_tick: int
) -> Dictionary:
	var state_validation: Dictionary = RuntimePersistenceScript.validate(state)
	if not bool(state_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_M0_STATE_INVALID", {"cause": state_validation})
	if authority_owner_id.strip_edges().is_empty() or authority_epoch < 1 or current_revision < -1 or server_tick < 0:
		return _failure("INVALID_CONSTRUCTION_RUNTIME_M0_AUTHORITY")
	var aggregate_id: String = aggregate_id_for_construct(String(state["construct_id"]))
	var next_revision: int = 0 if current_revision < 0 else current_revision + 1
	var snapshot: Dictionary = _snapshot(
		aggregate_id,
		next_revision,
		server_tick,
		authority_owner_id,
		authority_epoch,
		state
	)
	var snapshot_validation: Dictionary = SnapshotEnvelopeScript.validate(snapshot)
	if not bool(snapshot_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_M0_SNAPSHOT_INVALID", {"cause": snapshot_validation})
	var operation_kind: String = OperationScript.OP_CREATE if current_revision < 0 else OperationScript.OP_UPDATE
	var precondition: Dictionary
	if current_revision < 0:
		precondition = PreconditionScript.create(
			aggregate_id,
			RUNTIME_KIND,
			RuntimePersistenceScript.SCHEMA,
			false,
			"",
			0,
			-1
		)
	else:
		precondition = PreconditionScript.create(
			aggregate_id,
			RUNTIME_KIND,
			RuntimePersistenceScript.SCHEMA,
			true,
			authority_owner_id,
			authority_epoch,
			current_revision
		)
	var mutation: Dictionary = OperationScript.create(
		operation_kind,
		aggregate_id,
		RUNTIME_KIND,
		RuntimePersistenceScript.SCHEMA,
		snapshot
	)
	var batch_seed: Dictionary = {
		"operation_id": operation_id,
		"aggregate_id": aggregate_id,
		"state_checksum": String(state["checksum"]),
		"revision": next_revision,
	}
	var batch_id: String = "batch/construction/runtime/%s" % UtilsScript.payload_hash(batch_seed).substr(0, 24)
	var batch: Dictionary = BatchScript.create(
		batch_id,
		operation_id,
		authority_owner_id,
		authority_epoch,
		server_tick,
		[precondition],
		[mutation],
		[]
	)
	var batch_validation: Dictionary = BatchScript.validate(batch)
	if not bool(batch_validation.get("success", false)):
		return _failure("CONSTRUCTION_RUNTIME_M0_BATCH_INVALID", {"cause": batch_validation})
	return _success({
		"batch": batch,
		"batch_id": batch_id,
		"aggregate_id": aggregate_id,
		"result_revision": next_revision,
	})


static func _snapshot(
	aggregate_id: String,
	revision: int,
	server_tick: int,
	authority_owner_id: String,
	authority_epoch: int,
	state: Dictionary
) -> Dictionary:
	var type_ref: Dictionary = DynamicTypeScript.create(
		PACKAGE_ID,
		PACKAGE_VERSION,
		PACKAGE_HASH,
		RuntimePersistenceScript.SCHEMA
	)
	var identity: Dictionary = IdentityScript.create(
		aggregate_id,
		RUNTIME_KIND,
		RuntimePersistenceScript.SCHEMA,
		type_ref
	)
	var authority: Dictionary = AuthorityScript.create(
		authority_owner_id,
		authority_epoch,
		revision,
		server_tick
	)
	var scope: Dictionary = SpatialScopeScript.create(SpatialScopeScript.KIND_NONE, {})
	var descriptor: Dictionary = DescriptorScript.create(identity, authority, scope, {})
	var snapshot_id: String = "snapshot/%s/r%d/t%d" % [
		aggregate_id.trim_prefix("aggregate/").replace("/", ":"),
		revision,
		server_tick,
	]
	return SnapshotEnvelopeScript.create(snapshot_id, descriptor, state)


static func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


static func _failure(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "message": code, "details": details.duplicate(true)}
