extends RefCounted

## SM1.1 production owner-port map.
##
## SM0 is a capability donor only. This map binds each handoff concern to the
## already-canonical P6/product owner and proves that SM1 introduces no private
## Item Graph, Construction, persistence, replay or player-identity truth.

const P6OwnershipMap = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

const SCHEMA := "distributed_world_simulator.v0_sm1_owner_port_map.v1"
const ACTION_ADAPT := "ADAPT_TO_CURRENT_OWNER"
const ACTION_PORT_SEMANTICS := "PORT_SEMANTICS_ONLY"
const ACTION_TEST_DONOR := "TEST_DONOR_ONLY"
const ACTION_DROP_SYNTHETIC := "DROP_SYNTHETIC_OWNER"
const FORBIDDEN_ACTION := "COPY_AS_NEW_CANONICAL_OWNER"

const PORTS: Array = [
	{
		"concern": "logical_player_identity",
		"p6_domain_id": "p6-domain/player-identity-bindings",
		"owner_field": "canonical_owner",
		"expected_owner": "networked-gameplay/player-ownership",
		"component": "scripts/runtime/networked_gameplay/p6/p6_identity_registry.gd",
		"mapping_action": ACTION_ADAPT,
		"canonical_truth_created": false,
	},
	{
		"concern": "operation_replay",
		"p6_domain_id": "p6-domain/interaction-operation-ledger",
		"owner_field": "canonical_owner",
		"expected_owner": "replay/m6-durable-replay",
		"component": "scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd",
		"mapping_action": ACTION_ADAPT,
		"canonical_truth_created": false,
	},
	{
		"concern": "item_graph",
		"p6_domain_id": "p6-domain/item-inventory",
		"owner_field": "canonical_owner",
		"expected_owner": "item/m4-canonical-item-graph",
		"component": "canonical M4 Item Graph",
		"mapping_action": ACTION_ADAPT,
		"canonical_truth_created": false,
	},
	{
		"concern": "construction",
		"p6_domain_id": "p6-domain/construction-builds",
		"owner_field": "canonical_owner",
		"expected_owner": "construction/p4-authority",
		"component": "accepted P4 Construction authority",
		"mapping_action": ACTION_ADAPT,
		"canonical_truth_created": false,
	},
	{
		"concern": "persistence",
		"p6_domain_id": "p6-domain/outpost-world-state",
		"owner_field": "persistence_owner",
		"expected_owner": "persistence/authoritative-recovery",
		"component": "existing authoritative recovery pipeline",
		"mapping_action": ACTION_ADAPT,
		"canonical_truth_created": false,
	},
	{
		"concern": "warm_target",
		"p6_domain_id": "",
		"owner_field": "",
		"expected_owner": "READ_MODEL_ONLY",
		"component": "scripts/runtime/networked_gameplay/p6/p6_shadow_authority.gd",
		"mapping_action": ACTION_PORT_SEMANTICS,
		"canonical_truth_created": false,
	},
	{
		"concern": "mutation_admission",
		"p6_domain_id": "",
		"owner_field": "",
		"expected_owner": "EXISTING_AUTHORITY_ADMISSION",
		"component": "scripts/runtime/networked_gameplay/p6/p6_mutation_admission.gd",
		"mapping_action": ACTION_PORT_SEMANTICS,
		"canonical_truth_created": false,
	},
	{
		"concern": "client_route",
		"p6_domain_id": "",
		"owner_field": "",
		"expected_owner": "EDGE_GATEWAY",
		"component": "accepted Edge Gateway route",
		"mapping_action": ACTION_PORT_SEMANTICS,
		"canonical_truth_created": false,
	},
	{
		"concern": "sm0_runtime_objects",
		"p6_domain_id": "",
		"owner_field": "",
		"expected_owner": "NONE",
		"component": "historical SM0 runtime implementation",
		"mapping_action": ACTION_TEST_DONOR,
		"canonical_truth_created": false,
	},
]


static func snapshot() -> Dictionary:
	return {
		"schema": SCHEMA,
		"sm0_role": "CAPABILITY_DONOR_ONLY_NOT_PRODUCT_BASE",
		"ports": PORTS.duplicate(true),
		"private_canonical_truth": false,
	}


static func validate() -> Dictionary:
	if not P6OwnershipMap.no_private_truth():
		return _failure("P6_OWNER_MAP_PRIVATE_TRUTH")
	if not P6OwnershipMap.single_persistence_owner():
		return _failure("P6_MULTIPLE_PERSISTENCE_OWNERS")
	if not P6OwnershipMap.gateway_only_transport():
		return _failure("P6_NON_GATEWAY_TRANSPORT")

	var seen: Dictionary = {}
	for raw_port in PORTS:
		if not raw_port is Dictionary:
			return _failure("SM1_PORT_ENTRY_INVALID")
		var port := Dictionary(raw_port)
		var concern := String(port.get("concern", ""))
		if concern.is_empty() or seen.has(concern):
			return _failure("SM1_PORT_CONCERN_INVALID", {"concern": concern})
		seen[concern] = true
		if bool(port.get("canonical_truth_created", true)):
			return _failure("SM1_PRIVATE_CANONICAL_TRUTH_FORBIDDEN", {"concern": concern})
		if String(port.get("mapping_action", "")) == FORBIDDEN_ACTION:
			return _failure("SM0_WHOLESALE_OWNER_COPY_FORBIDDEN", {"concern": concern})

		var domain_id := String(port.get("p6_domain_id", ""))
		if domain_id.is_empty():
			continue
		var domain := P6OwnershipMap.find_domain(domain_id)
		if domain.is_empty():
			return _failure("P6_DOMAIN_NOT_FOUND", {"concern": concern, "domain_id": domain_id})
		var owner_field := String(port.get("owner_field", ""))
		var expected_owner := String(port.get("expected_owner", ""))
		if String(domain.get(owner_field, "")) != expected_owner:
			return _failure("SM1_OWNER_BINDING_MISMATCH", {
				"concern": concern,
				"domain_id": domain_id,
				"expected_owner": expected_owner,
				"actual_owner": String(domain.get(owner_field, "")),
			})

	return {
		"success": true,
		"details": {
			"schema": SCHEMA,
			"port_count": PORTS.size(),
			"private_canonical_truth": false,
			"single_persistence_owner": true,
			"gateway_only_transport": true,
			"result": "SM0_DONOR_TO_P6_OWNER_MAP_PASS",
		},
	}


static func find_port(concern: String) -> Dictionary:
	for raw_port in PORTS:
		var port := Dictionary(raw_port)
		if String(port.get("concern", "")) == concern:
			return port.duplicate(true)
	return {}


static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details.duplicate(true)}
