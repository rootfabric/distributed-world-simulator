extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const DynamicTypeScript = preload("res://scripts/simulation/aggregates/dynamic_type_reference.gd")
const IdentityScript = preload("res://scripts/simulation/aggregates/aggregate_identity.gd")
const AuthorityScript = preload("res://scripts/simulation/aggregates/aggregate_authority_state.gd")
const SpatialScopeScript = preload("res://scripts/simulation/aggregates/aggregate_spatial_scope.gd")
const DescriptorScript = preload("res://scripts/simulation/aggregates/aggregate_descriptor.gd")
const SnapshotEnvelopeScript = preload("res://scripts/network/contracts/aggregate_snapshot_envelope.gd")
const PreconditionScript = preload("res://scripts/simulation/transactions/aggregate_precondition.gd")
const OperationScript = preload("res://scripts/simulation/transactions/aggregate_mutation_operation.gd")
const BatchScript = preload("res://scripts/simulation/transactions/mutation_batch.gd")

const ITEM_GRAPH_AGGREGATE_ID: String = "aggregate/construction/item-graph"
const ITEM_GRAPH_KIND: String = "ITEM_GRAPH"
const ITEM_GRAPH_STATE_SCHEMA: String = "planet_simulator.construction_item_graph_state.v1"
const LEDGER_AGGREGATE_ID: String = "aggregate/construction/operation-ledger"
const LEDGER_KIND: String = "ITEM_OPERATION_LEDGER"
const LEDGER_STATE_SCHEMA: String = "planet_simulator.construction_operation_ledger_state.v1"
const CONSTRUCT_KIND: String = "CONSTRUCT"
const PACKAGE_ID: String = "planet-simulator:construction"
const PACKAGE_VERSION: String = "1.0.0"
const PACKAGE_HASH: String = "c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0c2b0"


static func build_bootstrap_snapshots(
	item_graph_state: Dictionary,
	ledger_state: Dictionary,
	construct_store_state: Dictionary,
	authority_owner_id: String,
	authority_epoch: int,
	item_graph_revision: int,
	ledger_revision: int,
	server_tick: int,
	construct_authority_revisions: Dictionary = {}
) -> Dictionary:
	if authority_owner_id.is_empty() or authority_epoch < 1 or item_graph_revision < 0 or ledger_revision < 0 or server_tick < 0:
		return _failure("INVALID_C2B_M0_BOOTSTRAP_AUTHORITY")
	var snapshots: Array = [
		_snapshot(
			ITEM_GRAPH_AGGREGATE_ID, ITEM_GRAPH_KIND, ITEM_GRAPH_STATE_SCHEMA,
			item_graph_revision, server_tick, authority_owner_id, authority_epoch, item_graph_state
		),
		_snapshot(
			LEDGER_AGGREGATE_ID, LEDGER_KIND, LEDGER_STATE_SCHEMA,
			ledger_revision, server_tick, authority_owner_id, authority_epoch, ledger_state
		),
	]
	for construct_snapshot in construct_store_state.get("constructs", []):
		var construct_id: String = String(construct_snapshot.get("construct_id", ""))
		snapshots.append(_snapshot(
			aggregate_id_for_construct(construct_id),
			CONSTRUCT_KIND,
			"planet_simulator.construct_snapshot.v1",
			int(construct_authority_revisions.get(construct_id, 0)),
			server_tick,
			authority_owner_id,
			authority_epoch,
			construct_snapshot
		))
	snapshots.sort_custom(func(left, right):
		return String(left["descriptor"]["identity"]["aggregate_id"]) < String(right["descriptor"]["identity"]["aggregate_id"])
	)
	return _success({"snapshots": snapshots})


static func build_batch(
	plan: Dictionary,
	before_item_graph_state: Dictionary,
	after_item_graph_state: Dictionary,
	before_ledger_state: Dictionary,
	after_ledger_state: Dictionary,
	authority_owner_id: String,
	authority_epoch: int,
	item_graph_revision: int,
	ledger_revision: int,
	server_tick: int,
	construct_authority_revision: int = -1
) -> Dictionary:
	var plan_validation: Dictionary = PlanScript.validate(plan)
	if not bool(plan_validation.get("success", false)):
		return plan_validation
	if authority_owner_id.is_empty() or authority_epoch < 1 or item_graph_revision < 0 or ledger_revision < 0 or server_tick < 0:
		return _failure("INVALID_C2B_M0_TRANSLATION_AUTHORITY")
	var construct_mutation: Dictionary = plan["construct_mutation"]
	var construct_id: String = String(construct_mutation["construct_id"])
	var construct_aggregate_id: String = aggregate_id_for_construct(construct_id)
	var rows: Array = []
	rows.append(_update_row(
		ITEM_GRAPH_AGGREGATE_ID,
		ITEM_GRAPH_KIND,
		ITEM_GRAPH_STATE_SCHEMA,
		item_graph_revision,
		before_item_graph_state,
		after_item_graph_state,
		authority_owner_id,
		authority_epoch,
		server_tick
	))
	rows.append(_update_row(
		LEDGER_AGGREGATE_ID,
		LEDGER_KIND,
		LEDGER_STATE_SCHEMA,
		ledger_revision,
		before_ledger_state,
		after_ledger_state,
		authority_owner_id,
		authority_epoch,
		server_tick
	))
	var construct_row: Dictionary = _construct_row(
		construct_aggregate_id,
		construct_mutation,
		authority_owner_id,
		authority_epoch,
		server_tick,
		construct_authority_revision
	)
	if not bool(construct_row.get("success", false)):
		return construct_row
	rows.append(construct_row["row"])
	rows.sort_custom(func(left, right):
		return String(left["aggregate_id"]) < String(right["aggregate_id"])
	)
	var preconditions: Array = []
	var operations: Array = []
	for row in rows:
		preconditions.append(row["precondition"])
		operations.append(row["operation"])
	var batch_id: String = batch_id_for_plan(plan)
	var batch: Dictionary = BatchScript.create(
		batch_id,
		String(plan["operation_id"]),
		authority_owner_id,
		authority_epoch,
		server_tick,
		preconditions,
		operations,
		[]
	)
	var validation: Dictionary = BatchScript.validate(batch)
	if not bool(validation.get("success", false)):
		return _failure("C2B_M0_BATCH_REJECTED", {"cause": validation})
	return _success({
		"batch": batch,
		"batch_id": batch_id,
		"construct_aggregate_id": construct_aggregate_id,
	})


static func batch_id_for_plan(plan: Dictionary) -> String:
	return "batch/construction/%s" % String(plan.get("checksum", "")).substr(0, 24)


static func aggregate_id_for_construct(construct_id: String) -> String:
	var suffix: String = construct_id.trim_prefix("construct/").replace("/", ":")
	return "aggregate/construction/construct:%s" % suffix


static func _update_row(
	aggregate_id: String,
	aggregate_kind: String,
	state_schema: String,
	current_revision: int,
	before_state: Dictionary,
	after_state: Dictionary,
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int
) -> Dictionary:
	var snapshot: Dictionary = _snapshot(
		aggregate_id,
		aggregate_kind,
		state_schema,
		current_revision + 1,
		server_tick,
		authority_owner_id,
		authority_epoch,
		after_state
	)
	return {
		"aggregate_id": aggregate_id,
		"precondition": PreconditionScript.create(
			aggregate_id,
			aggregate_kind,
			state_schema,
			true,
			authority_owner_id,
			authority_epoch,
			current_revision
		),
		"operation": OperationScript.create(
			OperationScript.OP_UPDATE,
			aggregate_id,
			aggregate_kind,
			state_schema,
			snapshot
		),
		"before_state_hash": UtilsScript.payload_hash(before_state),
	}


static func _construct_row(
	aggregate_id: String,
	mutation: Dictionary,
	authority_owner_id: String,
	authority_epoch: int,
	server_tick: int,
	construct_authority_revision: int
) -> Dictionary:
	var operation_kind: String = String(mutation["operation_kind"])
	var state_schema: String = "planet_simulator.construct_snapshot.v1"
	match operation_kind:
		ConstructMutationScript.OP_CREATE:
			var snapshot: Dictionary = _snapshot(
				aggregate_id,
				CONSTRUCT_KIND,
				state_schema,
				0,
				server_tick,
				authority_owner_id,
				authority_epoch,
				mutation["after_snapshot"]
			)
			return _success({"row": {
				"aggregate_id": aggregate_id,
				"precondition": PreconditionScript.create(
					aggregate_id,
					CONSTRUCT_KIND,
					state_schema,
					false,
					"",
					0,
					-1
				),
				"operation": OperationScript.create(
					OperationScript.OP_CREATE,
					aggregate_id,
					CONSTRUCT_KIND,
					state_schema,
					snapshot
				),
			}})
		ConstructMutationScript.OP_UPDATE:
			if construct_authority_revision < 0:
				return _failure("C2B_CONSTRUCT_AUTHORITY_REVISION_REQUIRED")
			var before_revision: int = construct_authority_revision
			var snapshot: Dictionary = _snapshot(
				aggregate_id,
				CONSTRUCT_KIND,
				state_schema,
				before_revision + 1,
				server_tick,
				authority_owner_id,
				authority_epoch,
				mutation["after_snapshot"]
			)
			return _success({"row": {
				"aggregate_id": aggregate_id,
				"precondition": PreconditionScript.create(
					aggregate_id,
					CONSTRUCT_KIND,
					state_schema,
					true,
					authority_owner_id,
					authority_epoch,
					before_revision
				),
				"operation": OperationScript.create(
					OperationScript.OP_UPDATE,
					aggregate_id,
					CONSTRUCT_KIND,
					state_schema,
					snapshot
				),
			}})
		ConstructMutationScript.OP_DELETE:
			if construct_authority_revision < 0:
				return _failure("C2B_CONSTRUCT_AUTHORITY_REVISION_REQUIRED")
			var before_revision: int = construct_authority_revision
			return _success({"row": {
				"aggregate_id": aggregate_id,
				"precondition": PreconditionScript.create(
					aggregate_id,
					CONSTRUCT_KIND,
					state_schema,
					true,
					authority_owner_id,
					authority_epoch,
					before_revision
				),
				"operation": OperationScript.create(
					OperationScript.OP_DELETE,
					aggregate_id,
					CONSTRUCT_KIND,
					state_schema,
					{}
				),
			}})
	return _failure("C2B_CONSTRUCT_MUTATION_UNSUPPORTED")


static func _snapshot(
	aggregate_id: String,
	aggregate_kind: String,
	state_schema: String,
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
		state_schema
	)
	var identity: Dictionary = IdentityScript.create(
		aggregate_id,
		aggregate_kind,
		state_schema,
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
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	return result
