extends RefCounted

## SM1.7.11 authority-tuple gate for canonical world mutations.
##
## This object owns no Item Graph, Construction, outpost, persistence or replay
## state. It only composes the SM1 one-writer authority tuple with the existing
## P6 ownership map. After authorization the caller must invoke the already
## canonical domain owner directly.

const P6OwnershipMap = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")
const ItemRelations = preload("res://scripts/items/domain/item_relations.gd")

const SCHEMA := "planet_simulator.sm1_canonical_mutation_gate.v1"

var _coordinator = null
var _counters := {
	"requests": 0,
	"authorized": 0,
	"fenced": 0,
	"invalid_domains": 0,
	"by_domain": {},
	"world_entity_reconciliations": 0,
}


func configure(coordinator) -> Dictionary:
	if coordinator == null or not coordinator.has_method("authorize_write") or not coordinator.has_method("snapshot"):
		return _failure("SM1_TRANSFER_COORDINATOR_REQUIRED")
	_coordinator = coordinator
	return _success({
		"private_canonical_truth": false,
		"persistence_owner": P6OwnershipMap.EXISTING_PERSISTENCE_OWNER_ID,
	})


func authorize(authority_id: String, authority_epoch: int, domain_id: String, operation_id: String) -> Dictionary:
	_counters["requests"] = int(_counters["requests"]) + 1
	if _coordinator == null:
		return _failure("SM1_CANONICAL_MUTATION_GATE_NOT_CONFIGURED")
	if operation_id.is_empty():
		return _failure("SM1_CANONICAL_MUTATION_OPERATION_ID_REQUIRED")
	var domain := P6OwnershipMap.find_domain(domain_id)
	if domain.is_empty():
		_counters["invalid_domains"] = int(_counters["invalid_domains"]) + 1
		return _failure("SM1_CANONICAL_MUTATION_DOMAIN_UNDECLARED", {"domain_id": domain_id})
	if String(domain.get("transport_path", "")) != P6OwnershipMap.TRANSPORT_GATEWAY_ONLY \
			or String(domain.get("write_authority", "")) != P6OwnershipMap.WRITE_AUTHORITY_SERVER_ONLY:
		_counters["invalid_domains"] = int(_counters["invalid_domains"]) + 1
		return _failure("SM1_CANONICAL_MUTATION_DOMAIN_POLICY_INVALID", {"domain_id": domain_id})

	var authority: Dictionary = _coordinator.authorize_write(authority_id, authority_epoch)
	if not bool(authority.get("success", false)):
		_counters["fenced"] = int(_counters["fenced"]) + 1
		return _failure("SM1_CANONICAL_MUTATION_AUTHORITY_FENCED", {
			"domain_id": domain_id,
			"operation_id": operation_id,
			"authority_id": authority_id,
			"authority_epoch": authority_epoch,
			"cause": authority,
		})

	_counters["authorized"] = int(_counters["authorized"]) + 1
	var by_domain: Dictionary = Dictionary(_counters["by_domain"])
	by_domain[domain_id] = int(by_domain.get(domain_id, 0)) + 1
	return _success({
		"operation_id": operation_id,
		"domain_id": domain_id,
		"authority_id": authority_id,
		"authority_epoch": authority_epoch,
		"canonical_owner": String(domain.get("canonical_owner", "")),
		"persistence_owner": String(domain.get("persistence_owner", "")),
		"private_canonical_truth": false,
		"apply_at_existing_owner_only": true,
	})


func reconcile_item_world_entities(domain: Dictionary) -> Dictionary:
	if not domain.has("items") or not domain.has("world_entities"):
		return _failure("SM1_CANONICAL_ITEM_WORLD_ENTITY_OWNER_REQUIRED")
	# Construction transactions are canonical P4 mutations over the M4 item
	# registry. They can create/delete WORLD roots without flowing through the
	# presentation controller signals that normally maintain WorldEntityStore.
	# Reconcile only through that existing canonical store: remove stale
	# bindings, then let its own migration path materialize missing WORLD roots.
	for aggregate in domain.world_entities.all_entities().duplicate():
		var item = domain.items.get_item(String(aggregate.item_instance_id))
		if item == null or ItemRelations.kind_of(item.relation) != ItemRelations.WORLD:
			domain.world_entities.remove_entity(String(aggregate.entity_id))
	var migrated: Dictionary = domain.world_entities.migrate_legacy_item_relations(domain.items)
	if not bool(migrated.get("success", false)):
		return _failure("SM1_CANONICAL_WORLD_ENTITY_MIGRATION_FAILED", {"cause": migrated})
	var validated: Dictionary = domain.world_entities.validate_item_bindings(domain.items)
	if not bool(validated.get("success", false)):
		return _failure("SM1_CANONICAL_WORLD_ENTITY_BINDING_INVALID", {"cause": validated})
	_counters["world_entity_reconciliations"] = int(_counters["world_entity_reconciliations"]) + 1
	return _success({
		"canonical_owner": "item/m4-canonical-item-graph",
		"migrated_relation_count": int(migrated.get("migrated_relation_count", 0)),
		"entity_count": int(validated.get("entity_count", 0)),
		"private_canonical_truth": false,
	})


func get_report() -> Dictionary:
	return {
		"schema": SCHEMA,
		"configured": _coordinator != null,
		"counters": _counters.duplicate(true),
		"private_item_graph": false,
		"private_construction_truth": false,
		"private_outpost_truth": false,
		"private_persistence_owner": false,
		"private_replay_owner": false,
		"policy": "ACTIVE_AUTHORITY_TUPLE_THEN_EXISTING_CANONICAL_OWNER",
	}


func _success(details: Dictionary) -> Dictionary:
	return {"success": true, "error_code": "", "details": details.duplicate(true)}


func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
