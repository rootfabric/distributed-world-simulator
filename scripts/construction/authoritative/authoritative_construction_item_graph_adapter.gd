extends RefCounted

const UtilsScript = preload("res://scripts/network/contracts/network_contract_utils.gd")
const ItemRegistryScript = preload("res://scripts/items/services/item_registry.gd")
const ContainerRegistryScript = preload("res://scripts/containers/container_registry.gd")
const RelationshipValidatorScript = preload("res://scripts/items/services/item_relationship_validator.gd")
const MassServiceScript = preload("res://scripts/items/services/item_mass_service.gd")
const OperationLedgerScript = preload("res://scripts/items/services/item_operation_ledger.gd")
const RelationsScript = preload("res://scripts/items/domain/item_relations.gd")
const PlanScript = preload("res://scripts/construction/item_graph/construction_item_transaction_plan.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const ItemMutationScript = preload("res://scripts/construction/item_graph/construction_item_mutation.gd")
const ConstructMutationScript = preload("res://scripts/construction/item_graph/construction_construct_mutation.gd")
const ConstructStoreScript = preload("res://scripts/construction/authoritative/construction_construct_store.gd")
const StateScript = preload("res://scripts/construction/authoritative/construction_authoritative_state.gd")
const M0TranslatorScript = preload("res://scripts/construction/authoritative/construction_m0_batch_translator.gd")

const STATUS_SUCCEEDED: String = "SUCCEEDED"
const STATUS_REJECTED: String = "REJECTED"
const STATUS_RETRYABLE: String = "RETRYABLE"
const FAILURE_BEFORE_COMMIT: String = "BEFORE_COMMIT"
const FAILURE_AFTER_M0: String = "AFTER_M0_COMMIT"
const FAILURE_M0_AFTER_PREPARE: String = "M0_AFTER_PREPARE"
const FAILURE_M0_AFTER_COMMIT: String = "M0_AFTER_COMMIT"
const FAILURE_AFTER_ITEMS: String = "AFTER_ITEMS_COMMIT"
const FAILURE_AFTER_CONTAINERS: String = "AFTER_CONTAINERS_COMMIT"
const FAILURE_AFTER_CONSTRUCTS: String = "AFTER_CONSTRUCTS_COMMIT"
const FAILURE_AFTER_LEDGER: String = "AFTER_LEDGER_COMMIT"
const SUPPORTED_FAILURE_MODES: Array[String] = [
	"",
	FAILURE_BEFORE_COMMIT,
	FAILURE_AFTER_M0,
	FAILURE_M0_AFTER_PREPARE,
	FAILURE_M0_AFTER_COMMIT,
	FAILURE_AFTER_ITEMS,
	FAILURE_AFTER_CONTAINERS,
	FAILURE_AFTER_CONSTRUCTS,
	FAILURE_AFTER_LEDGER,
]

var _items
var _containers
var _validator
var _mass
var _operations
var _constructs
var _m0_bridge
var _authority_owner_id: String = "authority/construction"
var _authority_epoch: int = 1
var _item_graph_revision: int = 0
var _ledger_revision: int = 0
var _server_tick: int = 0
var _construct_authority_revisions: Dictionary = {}
var _configured: bool = false
var _last_m0_batch: Dictionary = {}


func setup(
	item_registry,
	container_registry,
	relationship_validator,
	mass_service,
	operation_ledger,
	construct_store = null,
	m0_bridge = null,
	authority_owner_id: String = "authority/construction",
	authority_epoch: int = 1,
	item_graph_revision: int = 0,
	ledger_revision: int = 0,
	server_tick: int = 0,
	construct_authority_revisions: Dictionary = {}
) -> Dictionary:
	if item_registry == null or not item_registry.has_method("to_dict") or not item_registry.has_method("load_dict"):
		return _failure("PRODUCTION_ITEM_REGISTRY_REQUIRED")
	if container_registry == null or not container_registry.has_method("to_dict") or not container_registry.has_method("replace_from"):
		return _failure("PRODUCTION_CONTAINER_REGISTRY_REQUIRED")
	if relationship_validator == null or not relationship_validator.has_method("validate_graph") or not relationship_validator.has_method("validate_reparent"):
		return _failure("PRODUCTION_ITEM_RELATIONSHIP_VALIDATOR_REQUIRED")
	if mass_service == null or not mass_service.has_method("container_mass_kg") or not mass_service.has_method("container_direct_volume_l"):
		return _failure("PRODUCTION_ITEM_MASS_SERVICE_REQUIRED")
	if operation_ledger == null or not operation_ledger.has_method("resolve") or not operation_ledger.has_method("remember_terminal") or not operation_ledger.has_method("replace_from"):
		return _failure("PRODUCTION_ITEM_OPERATION_LEDGER_REQUIRED")
	if m0_bridge == null or not m0_bridge.has_method("bootstrap") or not m0_bridge.has_method("execute_batch") or not m0_bridge.has_method("get_committed_state"):
		return _failure("CONSTRUCTION_M0_TRANSACTION_BRIDGE_REQUIRED")
	if authority_owner_id.is_empty() or authority_epoch < 1 or item_graph_revision < 0 or ledger_revision < 0 or server_tick < 0:
		return _failure("INVALID_CONSTRUCTION_AUTHORITY_CONFIGURATION")
	_items = item_registry
	_containers = container_registry
	_validator = relationship_validator
	_mass = mass_service
	_operations = operation_ledger
	_constructs = construct_store if construct_store != null else ConstructStoreScript.new()
	_m0_bridge = m0_bridge
	_authority_owner_id = authority_owner_id
	_authority_epoch = authority_epoch
	_item_graph_revision = item_graph_revision
	_ledger_revision = ledger_revision
	_server_tick = server_tick
	_construct_authority_revisions = construct_authority_revisions.duplicate(true)
	for snapshot in _constructs.to_dict().get("constructs", []):
		var construct_id: String = String(snapshot.get("construct_id", ""))
		if not _construct_authority_revisions.has(construct_id):
			_construct_authority_revisions[construct_id] = 0
	_configured = true
	var current_validation: Dictionary = _validate_live_state()
	if not bool(current_validation.get("success", false)):
		_configured = false
		return current_validation
	var bootstrap_payload: Dictionary = M0TranslatorScript.build_bootstrap_snapshots(
		_item_graph_state(_items, _containers),
		_ledger_state(_operations),
		_constructs.to_dict(),
		_authority_owner_id,
		_authority_epoch,
		_item_graph_revision,
		_ledger_revision,
		_server_tick,
		_construct_authority_revisions
	)
	if not bool(bootstrap_payload.get("success", false)):
		_configured = false
		return bootstrap_payload
	var bootstrapped: Dictionary = _m0_bridge.bootstrap(bootstrap_payload["snapshots"])
	if not bool(bootstrapped.get("success", false)):
		_configured = false
		return _failure("CONSTRUCTION_M0_BOOTSTRAP_FAILED", {"cause": bootstrapped})
	var synchronized: Dictionary = _synchronize_from_m0()
	if not bool(synchronized.get("success", false)):
		_configured = false
		return synchronized
	return _success({"m0_bootstrap": bootstrapped, "m0_synchronized": synchronized})


func apply_plan(plan: Dictionary, failure_mode: String = "") -> Dictionary:
	if not _configured:
		return _failure("AUTHORITATIVE_CONSTRUCTION_ADAPTER_NOT_CONFIGURED", {}, STATUS_REJECTED)
	if not SUPPORTED_FAILURE_MODES.has(failure_mode):
		return _failure("UNKNOWN_AUTHORITATIVE_CONSTRUCTION_FAILURE_MODE", {}, STATUS_REJECTED)
	var plan_validation: Dictionary = PlanScript.validate(plan)
	if not bool(plan_validation.get("success", false)):
		return _with_status(plan_validation, STATUS_REJECTED)
	var operation_id: String = String(plan["operation_id"])
	var command_type: String = String(plan["command_type"])
	var plan_checksum: String = String(plan["checksum"])
	var construct_mutation: Dictionary = plan["construct_mutation"]
	var construct_id: String = String(construct_mutation["construct_id"])
	var expected_revision: int = -1
	if not Dictionary(construct_mutation["before_snapshot"]).is_empty():
		expected_revision = int(construct_mutation["before_snapshot"]["state_revision"])
	var resolved: Dictionary = _operations.resolve(
		operation_id,
		command_type,
		plan_checksum,
		construct_id,
		expected_revision
	)
	if bool(resolved.get("found", false)):
		return Dictionary(resolved.get("result", {})).duplicate(true)
	var candidate_result: Dictionary = _build_candidate(plan)
	if not bool(candidate_result.get("success", false)):
		return _finish_failure(plan, candidate_result, expected_revision)
	var candidate_items = candidate_result["items"]
	var candidate_containers = candidate_result["containers"]
	var candidate_constructs = candidate_result["constructs"]
	var affected_item_ids: Array = candidate_result["affected_item_ids"]
	var next_construct_revision: int = -1
	if not Dictionary(construct_mutation["after_snapshot"]).is_empty():
		next_construct_revision = int(construct_mutation["after_snapshot"]["state_revision"])
	var next_tick: int = _server_tick + 1
	var batch_id: String = M0TranslatorScript.batch_id_for_plan(plan)
	var base_result: Dictionary = {
		"success": true,
		"error_code": "",
		"message": "",
		"plan_id": String(plan["plan_id"]),
		"plan_checksum": plan_checksum,
		"construct_id": construct_id,
		"construct_revision": next_construct_revision,
		"affected_item_ids": affected_item_ids,
		"item_graph_revision": _item_graph_revision + 1,
		"ledger_revision": _ledger_revision + 1,
		"server_tick": next_tick,
		"authority_epoch": _authority_epoch,
		"m0_batch_id": batch_id,
	}
	var candidate_ledger = OperationLedgerScript.new(int(_operations.maximum_entries))
	var ledger_load: Dictionary = candidate_ledger.load_dict(_operations.to_dict())
	if not bool(ledger_load.get("success", false)):
		return _failure("AUTHORITATIVE_LEDGER_CLONE_FAILED", {"cause": ledger_load}, STATUS_RETRYABLE)
	var stored_result: Dictionary = candidate_ledger.remember_terminal(
		operation_id,
		command_type,
		plan_checksum,
		construct_id,
		expected_revision,
		next_construct_revision,
		OperationLedgerScript.STATUS_SUCCEEDED,
		base_result
	)
	var before_item_graph_state: Dictionary = _item_graph_state(_items, _containers)
	var after_item_graph_state: Dictionary = _item_graph_state(candidate_items, candidate_containers)
	var before_ledger_state: Dictionary = _ledger_state(_operations)
	var after_ledger_state: Dictionary = _ledger_state(candidate_ledger)
	var translated: Dictionary = M0TranslatorScript.build_batch(
		plan,
		before_item_graph_state,
		after_item_graph_state,
		before_ledger_state,
		after_ledger_state,
		_authority_owner_id,
		_authority_epoch,
		_item_graph_revision,
		_ledger_revision,
		next_tick,
		int(_construct_authority_revisions.get(construct_id, -1))
	)
	if not bool(translated.get("success", false)):
		return _failure("AUTHORITATIVE_M0_TRANSLATION_FAILED", {"cause": translated}, STATUS_REJECTED)
	if failure_mode == FAILURE_BEFORE_COMMIT:
		return _failure("INJECTED_AUTHORITATIVE_CONSTRUCTION_COMMIT_FAILURE", {}, STATUS_RETRYABLE)
	var m0_options: Dictionary = {}
	if failure_mode == FAILURE_M0_AFTER_PREPARE:
		m0_options["fault_point"] = "AFTER_PREPARE"
	elif failure_mode == FAILURE_M0_AFTER_COMMIT:
		m0_options["fault_point"] = "AFTER_COMMIT"
	var m0_result: Dictionary = _m0_bridge.execute_batch(translated["batch"], m0_options)
	if not bool(m0_result.get("success", false)):
		var m0_code: String = String(m0_result.get("error_code", "CONSTRUCTION_M0_EXECUTION_FAILED"))
		var m0_status: String = STATUS_RETRYABLE if m0_code in ["FAULT_INJECTED_AFTER_PREPARE", "FAULT_INJECTED_AFTER_COMMIT", "TRANSACTION_COORDINATOR_BUSY"] else STATUS_REJECTED
		return _failure(m0_code, {"cause": m0_result}, m0_status)
	if failure_mode == FAILURE_AFTER_M0:
		return _failure("INJECTED_FAILURE_AFTER_M0_COMMIT", {}, STATUS_RETRYABLE)
	var committed: Dictionary = _commit_candidate(
		candidate_items,
		candidate_containers,
		candidate_constructs,
		candidate_ledger,
		failure_mode
	)
	if not bool(committed.get("success", false)):
		return committed
	match String(construct_mutation["operation_kind"]):
		ConstructMutationScript.OP_CREATE:
			_construct_authority_revisions[construct_id] = 0
		ConstructMutationScript.OP_UPDATE:
			_construct_authority_revisions[construct_id] = int(_construct_authority_revisions.get(construct_id, -1)) + 1
		ConstructMutationScript.OP_DELETE:
			_construct_authority_revisions.erase(construct_id)
	_item_graph_revision += 1
	_ledger_revision += 1
	_server_tick = next_tick
	_last_m0_batch = Dictionary(translated["batch"]).duplicate(true)
	return stored_result


func get_item_projection(item_instance_id: String) -> Dictionary:
	if not _configured:
		return {}
	var item = _items.get_item(item_instance_id)
	if item == null:
		return {}
	var result: Dictionary = ProjectionScript.from_item_instance_dict(item.to_dict())
	return Dictionary(result.get("projection", {})).duplicate(true) if bool(result.get("success", false)) else {}


func get_construct_snapshot(construct_id: String) -> Dictionary:
	return _constructs.get_snapshot(construct_id) if _configured else {}


func get_last_m0_batch() -> Dictionary:
	return _last_m0_batch.duplicate(true)


func get_authority_report() -> Dictionary:
	return {
		"authority_owner_id": _authority_owner_id,
		"authority_epoch": _authority_epoch,
		"item_graph_revision": _item_graph_revision,
		"ledger_revision": _ledger_revision,
		"server_tick": _server_tick,
		"construct_authority_revisions": _construct_authority_revisions.duplicate(true),
		"construct_count": _constructs.size() if _configured else 0,
		"operation_count": _operations.size() if _configured else 0,
	}


func export_state() -> Dictionary:
	if not _configured:
		return {}
	return StateScript.create(
		_authority_owner_id,
		_authority_epoch,
		_item_graph_revision,
		_ledger_revision,
		_server_tick,
		_construct_authority_revisions,
		_items.to_dict(),
		_containers.to_dict(),
		_constructs.to_dict(),
		_operations.to_dict()
	)


func load_state(state: Dictionary) -> Dictionary:
	if not _configured:
		return _failure("AUTHORITATIVE_CONSTRUCTION_ADAPTER_NOT_CONFIGURED")
	var state_validation: Dictionary = StateScript.validate(state)
	if not bool(state_validation.get("success", false)):
		return state_validation
	var synchronized: Dictionary = _synchronize_from_m0()
	if not bool(synchronized.get("success", false)):
		return synchronized
	if UtilsScript.canonical_json(export_state()) != UtilsScript.canonical_json(state):
		return _failure("AUTHORITATIVE_PERSISTED_STATE_M0_MISMATCH")
	return _success({"replay": true})


func _synchronize_from_m0() -> Dictionary:
	var committed: Dictionary = _m0_bridge.get_committed_state()
	if not bool(committed.get("success", false)):
		return _failure("CONSTRUCTION_M0_STATE_UNAVAILABLE", {"cause": committed})
	var state: Dictionary = Dictionary(committed.get("details", {}).get("state", {}))
	var aggregates_value = state.get("aggregates_by_id", {})
	if not aggregates_value is Dictionary:
		return _failure("CONSTRUCTION_M0_AGGREGATE_STATE_INVALID")
	var aggregates: Dictionary = aggregates_value
	if not aggregates.has(M0TranslatorScript.ITEM_GRAPH_AGGREGATE_ID) or not aggregates.has(M0TranslatorScript.LEDGER_AGGREGATE_ID):
		return _failure("CONSTRUCTION_M0_CORE_AGGREGATE_MISSING")
	var item_envelope: Dictionary = aggregates[M0TranslatorScript.ITEM_GRAPH_AGGREGATE_ID]
	var ledger_envelope: Dictionary = aggregates[M0TranslatorScript.LEDGER_AGGREGATE_ID]
	var item_state: Dictionary = item_envelope.get("state", {})
	var ledger_state: Dictionary = ledger_envelope.get("state", {})
	var candidate_items = ItemRegistryScript.new()
	var item_load: Dictionary = candidate_items.load_dict(Dictionary(item_state.get("item_registry", {})))
	if not bool(item_load.get("success", false)):
		return _failure("CONSTRUCTION_M0_ITEM_REGISTRY_REJECTED", {"cause": item_load})
	var candidate_containers = ContainerRegistryScript.new()
	var container_load: Dictionary = candidate_containers.load_dict(Dictionary(item_state.get("container_registry", {})))
	if not bool(container_load.get("success", false)):
		return _failure("CONSTRUCTION_M0_CONTAINER_REGISTRY_REJECTED", {"cause": container_load})
	var candidate_ledger = OperationLedgerScript.new(int(Dictionary(ledger_state.get("operation_ledger", {})).get("maximum_entries", 2048)))
	var ledger_load: Dictionary = candidate_ledger.load_dict(Dictionary(ledger_state.get("operation_ledger", {})))
	if not bool(ledger_load.get("success", false)):
		return _failure("CONSTRUCTION_M0_OPERATION_LEDGER_REJECTED", {"cause": ledger_load})
	var construct_rows: Array = []
	var construct_revisions: Dictionary = {}
	var maximum_tick: int = 0
	var resolved_owner: String = ""
	var resolved_epoch: int = 0
	for aggregate_id in aggregates.keys():
		var envelope: Dictionary = aggregates[aggregate_id]
		var identity: Dictionary = envelope.get("descriptor", {}).get("identity", {})
		var authority: Dictionary = envelope.get("descriptor", {}).get("authority", {})
		var owner: String = String(authority.get("authority_owner_id", ""))
		var epoch: int = int(authority.get("authority_epoch", 0))
		if resolved_owner.is_empty():
			resolved_owner = owner
			resolved_epoch = epoch
		elif owner != resolved_owner or epoch != resolved_epoch:
			return _failure("CONSTRUCTION_M0_AUTHORITY_SPLIT_BRAIN")
		maximum_tick = maxi(maximum_tick, int(authority.get("server_tick", 0)))
		if String(identity.get("aggregate_kind", "")) == M0TranslatorScript.CONSTRUCT_KIND:
			var construct_snapshot: Dictionary = envelope.get("state", {})
			construct_rows.append(construct_snapshot.duplicate(true))
			construct_revisions[String(construct_snapshot.get("construct_id", ""))] = int(authority.get("state_revision", 0))
	construct_rows.sort_custom(func(left, right): return String(left.get("construct_id", "")) < String(right.get("construct_id", "")))
	var construct_state: Dictionary = {"schema": ConstructStoreScript.SCHEMA, "constructs": construct_rows, "checksum": ""}
	construct_state["checksum"] = ConstructStoreScript.compute_checksum(construct_state)
	var candidate_constructs = ConstructStoreScript.new()
	var construct_load: Dictionary = candidate_constructs.load_dict(construct_state)
	if not bool(construct_load.get("success", false)):
		return construct_load
	var candidate_validation: Dictionary = _validate_candidate(candidate_items, candidate_containers, candidate_constructs)
	if not bool(candidate_validation.get("success", false)):
		return candidate_validation
	var replaced: Dictionary = _replace_live(candidate_items, candidate_containers, candidate_constructs, candidate_ledger)
	if not bool(replaced.get("success", false)):
		return replaced
	_authority_owner_id = resolved_owner
	_authority_epoch = resolved_epoch
	_item_graph_revision = int(item_envelope.get("descriptor", {}).get("authority", {}).get("state_revision", 0))
	_ledger_revision = int(ledger_envelope.get("descriptor", {}).get("authority", {}).get("state_revision", 0))
	_server_tick = maximum_tick
	_construct_authority_revisions = construct_revisions
	return _success({"generation": int(state.get("generation", 0)), "construct_count": construct_rows.size()})


func _build_candidate(plan: Dictionary) -> Dictionary:
	var item_state: Dictionary = _items.to_dict().duplicate(true)
	var container_state: Dictionary = _containers.to_dict().duplicate(true)
	var item_rows_result: Dictionary = _rows_by_id(item_state.get("items", []), "instance_id")
	if not bool(item_rows_result.get("success", false)):
		return item_rows_result
	var item_rows: Dictionary = item_rows_result["rows"]
	var container_rows_result: Dictionary = _rows_by_id(container_state.get("containers", []), "container_id")
	if not bool(container_rows_result.get("success", false)):
		return container_rows_result
	var container_rows: Dictionary = container_rows_result["rows"]
	var touched_containers: Dictionary = {}
	var affected_item_ids: Array[String] = []
	for mutation in plan["item_mutations"]:
		var precondition: Dictionary = _validate_item_precondition(item_rows, mutation)
		if not bool(precondition.get("success", false)):
			return precondition
		var membership: Dictionary = _apply_container_membership(container_rows, mutation, touched_containers)
		if not bool(membership.get("success", false)):
			return membership
		var apply_item: Dictionary = _apply_item_row(item_rows, mutation)
		if not bool(apply_item.get("success", false)):
			return apply_item
		affected_item_ids.append(String(mutation["item_instance_id"]))
	for container_id in touched_containers:
		var row: Dictionary = container_rows[container_id]
		row["revision"] = int(row.get("revision", 0)) + 1
		container_rows[container_id] = row
	item_state["items"] = _sorted_rows(item_rows)
	container_state["containers"] = _sorted_rows(container_rows)
	var candidate_items = ItemRegistryScript.new()
	var item_load: Dictionary = candidate_items.load_dict(item_state)
	if not bool(item_load.get("success", false)):
		return _failure("AUTHORITATIVE_ITEM_MUTATIONS_REJECTED", {"cause": item_load})
	var candidate_containers = ContainerRegistryScript.new()
	var container_load: Dictionary = candidate_containers.load_dict(container_state)
	if not bool(container_load.get("success", false)):
		return _failure("AUTHORITATIVE_CONTAINER_MUTATIONS_REJECTED", {"cause": container_load})
	var candidate_constructs = ConstructStoreScript.new()
	var construct_load: Dictionary = candidate_constructs.load_dict(_constructs.to_dict())
	if not bool(construct_load.get("success", false)):
		return construct_load
	var construct_apply: Dictionary = candidate_constructs.apply_mutation(plan["construct_mutation"])
	if not bool(construct_apply.get("success", false)):
		return construct_apply
	var candidate_validation: Dictionary = _validate_candidate(candidate_items, candidate_containers, candidate_constructs, affected_item_ids)
	if not bool(candidate_validation.get("success", false)):
		return candidate_validation
	affected_item_ids.sort()
	return _success({
		"items": candidate_items,
		"containers": candidate_containers,
		"constructs": candidate_constructs,
		"affected_item_ids": affected_item_ids,
	})


func _validate_item_precondition(item_rows: Dictionary, mutation: Dictionary) -> Dictionary:
	var item_id: String = String(mutation["item_instance_id"])
	var before: Dictionary = mutation["before_projection"]
	if before.is_empty():
		if item_rows.has(item_id):
			return _failure("AUTHORITATIVE_ITEM_EXPECTED_ABSENT", {"item_instance_id": item_id})
		return _success()
	if not item_rows.has(item_id):
		return _failure("AUTHORITATIVE_ITEM_PRECONDITION_MISSING", {"item_instance_id": item_id})
	var projected: Dictionary = ProjectionScript.from_item_instance_dict(item_rows[item_id])
	if not bool(projected.get("success", false)):
		return projected
	if Dictionary(projected["projection"]) != before:
		return _failure("AUTHORITATIVE_ITEM_PRECONDITION_MISMATCH", {"item_instance_id": item_id})
	return _success()


func _apply_item_row(item_rows: Dictionary, mutation: Dictionary) -> Dictionary:
	var item_id: String = String(mutation["item_instance_id"])
	match String(mutation["operation_kind"]):
		ItemMutationScript.OP_CREATE, ItemMutationScript.OP_UPDATE:
			var converted: Dictionary = ProjectionScript.to_item_instance_dict(mutation["after_projection"])
			if not bool(converted.get("success", false)):
				return converted
			item_rows[item_id] = Dictionary(converted["item"]).duplicate(true)
		ItemMutationScript.OP_DELETE:
			item_rows.erase(item_id)
		_:
			return _failure("AUTHORITATIVE_ITEM_OPERATION_UNSUPPORTED")
	return _success()


func _apply_container_membership(container_rows: Dictionary, mutation: Dictionary, touched: Dictionary) -> Dictionary:
	var item_id: String = String(mutation["item_instance_id"])
	var before: Dictionary = mutation["before_projection"]
	var after: Dictionary = mutation["after_projection"]
	var before_relation: Dictionary = before.get("relation", {}) if not before.is_empty() else {}
	var after_relation: Dictionary = after.get("relation", {}) if not after.is_empty() else {}
	var before_kind: String = String(before_relation.get("kind", ""))
	var after_kind: String = String(after_relation.get("kind", ""))
	var same_container: bool = (
		before_kind == ProjectionScript.CONTAINER
		and after_kind == ProjectionScript.CONTAINER
		and String(before_relation.get("container_id", "")) == String(after_relation.get("container_id", ""))
		and int(before_relation.get("slot_index", -1)) == int(after_relation.get("slot_index", -1))
	)
	if before_kind == ProjectionScript.CONTAINER and not same_container:
		var remove_result: Dictionary = _remove_membership(container_rows, String(before_relation.get("container_id", "")), item_id)
		if not bool(remove_result.get("success", false)):
			return remove_result
		touched[String(before_relation.get("container_id", ""))] = true
	if after_kind == ProjectionScript.CONTAINER and not same_container:
		var add_result: Dictionary = _add_membership(
			container_rows,
			String(after_relation.get("container_id", "")),
			item_id,
			int(after_relation.get("slot_index", -1))
		)
		if not bool(add_result.get("success", false)):
			return add_result
		touched[String(after_relation.get("container_id", ""))] = true
	if same_container and before != after:
		touched[String(after_relation.get("container_id", ""))] = true
	return _success()


func _remove_membership(container_rows: Dictionary, container_id: String, item_id: String) -> Dictionary:
	if not container_rows.has(container_id):
		return _failure("AUTHORITATIVE_SOURCE_CONTAINER_NOT_FOUND", {"container_id": container_id})
	var row: Dictionary = container_rows[container_id]
	var ids: Array = row.get("item_ids", []).duplicate()
	if not ids.has(item_id):
		return _failure("AUTHORITATIVE_CONTAINER_MEMBERSHIP_MISSING", {"container_id": container_id, "item_instance_id": item_id})
	ids.erase(item_id)
	row["item_ids"] = ids
	var assignments: Dictionary = Dictionary(row.get("slot_assignments", {})).duplicate(true)
	for slot_key in assignments.keys():
		if String(assignments[slot_key]) == item_id:
			assignments.erase(slot_key)
	row["slot_assignments"] = assignments
	container_rows[container_id] = row
	return _success()


func _add_membership(container_rows: Dictionary, container_id: String, item_id: String, slot_index: int) -> Dictionary:
	if not container_rows.has(container_id):
		return _failure("AUTHORITATIVE_TARGET_CONTAINER_NOT_FOUND", {"container_id": container_id, "retryable": true})
	var row: Dictionary = container_rows[container_id]
	var ids: Array = row.get("item_ids", []).duplicate()
	if ids.has(item_id):
		return _failure("AUTHORITATIVE_DUPLICATE_CONTAINER_MEMBERSHIP", {"container_id": container_id, "item_instance_id": item_id})
	var storage_mode: String = String(row.get("storage_mode", "BULK"))
	if storage_mode == "SLOTS":
		var slot_count: int = int(row.get("slot_count", 0))
		if slot_index < 0:
			return _failure("AUTHORITATIVE_SLOT_INDEX_REQUIRED", {"container_id": container_id})
		if slot_index >= slot_count:
			return _failure("AUTHORITATIVE_SLOT_OUT_OF_RANGE", {"container_id": container_id, "slot_index": slot_index})
		var assignments: Dictionary = Dictionary(row.get("slot_assignments", {})).duplicate(true)
		var key: String = str(slot_index)
		if assignments.has(key) and String(assignments[key]) != item_id:
			return _failure("AUTHORITATIVE_SLOT_OCCUPIED", {"container_id": container_id, "slot_index": slot_index})
		assignments[key] = item_id
		row["slot_assignments"] = assignments
	else:
		var slot_count: int = int(row.get("slot_count", 0))
		if slot_count > 0 and ids.size() >= slot_count:
			return _failure("AUTHORITATIVE_CONTAINER_FULL", {"container_id": container_id})
	ids.append(item_id)
	ids.sort()
	row["item_ids"] = ids
	container_rows[container_id] = row
	return _success()


func _validate_candidate(candidate_items, candidate_containers, candidate_constructs, changed_item_ids: Array = []) -> Dictionary:
	var validator = RelationshipValidatorScript.new()
	validator.setup(candidate_items, candidate_containers)
	for item_id in changed_item_ids:
		var item = candidate_items.get_item(String(item_id))
		if item == null:
			continue
		var reparent: Dictionary = validator.validate_reparent(String(item_id), item.relation)
		if not bool(reparent.get("success", false)):
			return _failure("AUTHORITATIVE_ITEM_RELATION_REJECTED", {"item_instance_id": item_id, "cause": reparent})
	var graph_validation: Dictionary = validator.validate_graph()
	if not bool(graph_validation.get("success", false)):
		return _failure("AUTHORITATIVE_ITEM_GRAPH_REJECTED", {"cause": graph_validation})
	var mass = MassServiceScript.new()
	mass.setup(candidate_items, candidate_containers)
	for container in candidate_containers.all_containers():
		var mass_kg: float = float(mass.container_mass_kg(String(container.container_id)))
		var volume_l: float = float(mass.container_direct_volume_l(String(container.container_id)))
		if not is_inf(float(container.maximum_mass_kg)) and mass_kg > float(container.maximum_mass_kg) + 0.000001:
			return _failure("AUTHORITATIVE_CONTAINER_MASS_EXCEEDED", {"container_id": container.container_id})
		if not is_inf(float(container.maximum_volume_l)) and volume_l > float(container.maximum_volume_l) + 0.000001:
			return _failure("AUTHORITATIVE_CONTAINER_VOLUME_EXCEEDED", {"container_id": container.container_id})
	return _validate_construct_bindings(candidate_items, candidate_constructs)


func _validate_construct_bindings(candidate_items, candidate_constructs) -> Dictionary:
	var attached_by_construct: Dictionary = {}
	for item in candidate_items.all_items():
		if RelationsScript.kind_of(item.relation) != RelationsScript.ATTACHMENT:
			continue
		var construct_id: String = String(item.relation.get("assembly_id", ""))
		if not attached_by_construct.has(construct_id):
			attached_by_construct[construct_id] = []
		attached_by_construct[construct_id].append(String(item.instance_id))
	var store_state: Dictionary = candidate_constructs.to_dict()
	for snapshot in store_state["constructs"]:
		var construct_id: String = String(snapshot["construct_id"])
		var root_item_id: String = String(snapshot["root_item_instance_id"])
		var root = candidate_items.get_item(root_item_id)
		if root == null:
			return _failure("AUTHORITATIVE_CONSTRUCT_ROOT_MISSING", {"construct_id": construct_id})
		var root_component = root.components.get("construction_root", {})
		if not root_component is Dictionary or String(Dictionary(root_component).get("construct_id", "")) != construct_id:
			return _failure("AUTHORITATIVE_CONSTRUCT_ROOT_COMPONENT_MISMATCH", {"construct_id": construct_id})
		var declared: Dictionary = {}
		for part in snapshot["parts"]:
			var item_id: String = String(part["item_instance_id"])
			if declared.has(item_id):
				return _failure("AUTHORITATIVE_CONSTRUCT_REUSES_ITEM", {"item_instance_id": item_id})
			declared[item_id] = true
			var item = candidate_items.get_item(item_id)
			if item == null:
				return _failure("AUTHORITATIVE_CONSTRUCT_PART_MISSING", {"item_instance_id": item_id})
			var relation: Dictionary = item.relation
			if (
				RelationsScript.kind_of(relation) != RelationsScript.ATTACHMENT
				or String(relation.get("assembly_id", "")) != construct_id
				or String(relation.get("parent_item_id", "")) != root_item_id
				or String(relation.get("socket_id", "")) != String(part["part_id"])
			):
				return _failure("AUTHORITATIVE_CONSTRUCT_PART_BINDING_MISMATCH", {"item_instance_id": item_id})
		for attached_item_id in attached_by_construct.get(construct_id, []):
			if not declared.has(attached_item_id):
				return _failure("AUTHORITATIVE_UNDECLARED_ATTACHED_ITEM", {"item_instance_id": attached_item_id})
	for construct_id in attached_by_construct:
		if not candidate_constructs.has_construct(String(construct_id)):
			return _failure("AUTHORITATIVE_ATTACHMENT_TARGET_CONSTRUCT_MISSING", {"construct_id": construct_id})
	return _success()


func _commit_candidate(candidate_items, candidate_containers, candidate_constructs, candidate_ledger, failure_mode: String) -> Dictionary:
	var backup: Dictionary = export_state()
	var item_load: Dictionary = _items.load_dict(candidate_items.to_dict())
	if not bool(item_load.get("success", false)):
		return _failure("AUTHORITATIVE_ITEM_COMMIT_FAILED", {"cause": item_load}, STATUS_RETRYABLE)
	if failure_mode == FAILURE_AFTER_ITEMS:
		_restore_from_state(backup)
		return _failure("INJECTED_FAILURE_AFTER_ITEM_COMMIT", {}, STATUS_RETRYABLE)
	_containers.replace_from(candidate_containers)
	if failure_mode == FAILURE_AFTER_CONTAINERS:
		_restore_from_state(backup)
		return _failure("INJECTED_FAILURE_AFTER_CONTAINER_COMMIT", {}, STATUS_RETRYABLE)
	_constructs.replace_from(candidate_constructs)
	if failure_mode == FAILURE_AFTER_CONSTRUCTS:
		_restore_from_state(backup)
		return _failure("INJECTED_FAILURE_AFTER_CONSTRUCT_COMMIT", {}, STATUS_RETRYABLE)
	_operations.replace_from(candidate_ledger)
	if failure_mode == FAILURE_AFTER_LEDGER:
		_restore_from_state(backup)
		return _failure("INJECTED_FAILURE_AFTER_LEDGER_COMMIT", {}, STATUS_RETRYABLE)
	return _success()


func _replace_live(candidate_items, candidate_containers, candidate_constructs, candidate_ledger) -> Dictionary:
	var item_load: Dictionary = _items.load_dict(candidate_items.to_dict())
	if not bool(item_load.get("success", false)):
		return _failure("AUTHORITATIVE_ITEM_REPLACE_FAILED", {"cause": item_load})
	_containers.replace_from(candidate_containers)
	_constructs.replace_from(candidate_constructs)
	_operations.replace_from(candidate_ledger)
	return _success()


func _restore_from_state(state: Dictionary) -> Dictionary:
	var items_result: Dictionary = _items.load_dict(state["item_registry"])
	var containers_result: Dictionary = _containers.load_dict(state["container_registry"])
	var constructs_result: Dictionary = _constructs.load_dict(state["construct_store"])
	var ledger_result: Dictionary = _operations.load_dict(state["operation_ledger"])
	if not bool(items_result.get("success", false)) or not bool(containers_result.get("success", false)) or not bool(constructs_result.get("success", false)) or not bool(ledger_result.get("success", false)):
		return _failure("AUTHORITATIVE_ROLLBACK_FAILED")
	return _success()


func _finish_failure(plan: Dictionary, failure: Dictionary, expected_revision: int) -> Dictionary:
	var retryable: bool = bool(failure.get("retryable", false)) or String(failure.get("error_code", "")) in [
		"AUTHORITATIVE_TARGET_CONTAINER_NOT_FOUND",
		"AUTHORITATIVE_SOURCE_CONTAINER_NOT_FOUND",
	]
	if retryable:
		return _with_status(failure, STATUS_RETRYABLE)
	var construct_mutation: Dictionary = plan["construct_mutation"]
	var construct_id: String = String(construct_mutation["construct_id"])
	var result_revision: int = -1
	var current: Dictionary = _constructs.get_snapshot(construct_id)
	if not current.is_empty():
		result_revision = int(current["state_revision"])
	return _operations.remember_terminal(
		String(plan["operation_id"]),
		String(plan["command_type"]),
		String(plan["checksum"]),
		construct_id,
		expected_revision,
		result_revision,
		OperationLedgerScript.STATUS_REJECTED,
		failure
	)


func _validate_live_state() -> Dictionary:
	return _validate_candidate(_items, _containers, _constructs)


func _item_graph_state(items, containers) -> Dictionary:
	var state: Dictionary = {
		"schema": M0TranslatorScript.ITEM_GRAPH_STATE_SCHEMA,
		"item_registry": items.to_dict(),
		"container_registry": containers.to_dict(),
		"checksum": "",
	}
	state["checksum"] = _section_checksum(state)
	return state


func _ledger_state(ledger) -> Dictionary:
	var state: Dictionary = {
		"schema": M0TranslatorScript.LEDGER_STATE_SCHEMA,
		"operation_ledger": ledger.to_dict(),
		"checksum": "",
	}
	state["checksum"] = _section_checksum(state)
	return state


func _section_checksum(state: Dictionary) -> String:
	var payload: Dictionary = state.duplicate(true)
	payload["checksum"] = ""
	return UtilsScript.payload_hash(payload)


func _rows_by_id(rows_value, id_field: String) -> Dictionary:
	if not rows_value is Array:
		return _failure("AUTHORITATIVE_STATE_ROWS_INVALID", {"id_field": id_field})
	var rows: Dictionary = {}
	for raw in rows_value:
		if not raw is Dictionary:
			return _failure("AUTHORITATIVE_STATE_ROW_INVALID", {"id_field": id_field})
		var row: Dictionary = raw
		var id: String = String(row.get(id_field, ""))
		if id.is_empty() or rows.has(id):
			return _failure("AUTHORITATIVE_STATE_ROW_ID_INVALID", {"id_field": id_field, "id": id})
		rows[id] = row.duplicate(true)
	return _success({"rows": rows})


func _sorted_rows(rows: Dictionary) -> Array:
	var ids: Array = rows.keys()
	ids.sort()
	var result: Array = []
	for id in ids:
		result.append(Dictionary(rows[id]).duplicate(true))
	return result


func _with_status(result: Dictionary, status: String) -> Dictionary:
	var output: Dictionary = result.duplicate(true)
	output["status"] = status
	return output


func _success(details: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"success": true, "error_code": "", "message": ""}
	for key in details:
		result[key] = details[key]
	return result


func _failure(code: String, details: Dictionary = {}, status: String = "") -> Dictionary:
	var result: Dictionary = {"success": false, "error_code": code, "message": code}
	for key in details:
		result[key] = details[key]
	if not status.is_empty():
		result["status"] = status
	return result
