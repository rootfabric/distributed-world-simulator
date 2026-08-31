extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/structural_aggregate_descriptor_v1.gd")
const Reconstruction = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const GuardField = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_field_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")

const SCHEMA := "planet_simulator.fabric_bake_structural_topology_rebake_transaction.v1"
const FIELDS: Array[String] = [
	"schema", "transaction_id", "previous_source_frontier_hash", "current_source_frontier_hash",
	"construct_id", "parent_structural_descriptor_hash", "parent_reconstruction_mapping_hash",
	"parent_guard_field_hash", "local_unbake_plan_hash", "event", "invalidated_pieces",
	"rebaked_components", "canonical_part_count", "previous_bond_count", "current_bond_count",
	"minimum_rebake_component_parts", "continuity_tolerance", "conservation_tolerance",
	"transition_version", "checksum",
]
const EVENT_FIELDS: Array[String] = [
	"event_id", "event_type", "bond_id", "target_region_id", "event_tick", "event_sequence", "event_hash",
]
const INVALIDATION_FIELDS: Array[String] = [
	"piece_id", "piece_kind", "descriptor_hash", "predecessor_frontier_hash",
	"current_frontier_hash", "reason",
]
const COMPONENT_FIELDS: Array[String] = [
	"component_id", "part_ids", "bond_ids", "anchor_ids", "descriptor", "reconstruction_mapping",
	"guard_field", "physical_bake_artifact", "predecessor_piece_ids",
]
const PIECE_KINDS: Array[String] = ["PARENT_AGGREGATE", "LOCAL_RESIDUAL"]

static func create(
	transaction_id: String, previous_source_frontier_hash: String, current_source_frontier_hash: String,
	construct_id: String, parent_structural_descriptor_hash: String, parent_reconstruction_mapping_hash: String,
	parent_guard_field_hash: String, local_unbake_plan_hash: String, event: Dictionary,
	invalidated_pieces: Array, rebaked_components: Array, canonical_part_count: int,
	previous_bond_count: int, current_bond_count: int, minimum_rebake_component_parts: int,
	continuity_tolerance: float, conservation_tolerance: float, transition_version: String
) -> Dictionary:
	var value: Dictionary = {
		"schema": SCHEMA,
		"transaction_id": transaction_id,
		"previous_source_frontier_hash": previous_source_frontier_hash,
		"current_source_frontier_hash": current_source_frontier_hash,
		"construct_id": construct_id,
		"parent_structural_descriptor_hash": parent_structural_descriptor_hash,
		"parent_reconstruction_mapping_hash": parent_reconstruction_mapping_hash,
		"parent_guard_field_hash": parent_guard_field_hash,
		"local_unbake_plan_hash": local_unbake_plan_hash,
		"event": event.duplicate(true),
		"invalidated_pieces": Utils.sorted_dicts(invalidated_pieces, "piece_id"),
		"rebaked_components": Utils.sorted_dicts(rebaked_components, "component_id"),
		"canonical_part_count": canonical_part_count,
		"previous_bond_count": previous_bond_count,
		"current_bond_count": current_bond_count,
		"minimum_rebake_component_parts": minimum_rebake_component_parts,
		"continuity_tolerance": continuity_tolerance,
		"conservation_tolerance": conservation_tolerance,
		"transition_version": transition_version,
		"checksum": "",
	}
	value["checksum"] = Utils.compute_checksum(value)
	return value if bool(validate(value).get("success", false)) else {}

static func validate(value: Dictionary) -> Dictionary:
	var checked := Utils.validate_exact_fields(value, FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	if value.get("schema") != SCHEMA:
		return Utils.failure("UNSUPPORTED_STRUCTURAL_TOPOLOGY_REBAKE_TRANSACTION_SCHEMA")
	for field in ["transaction_id", "construct_id"]:
		if not Utils.is_canonical_id(value.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_ID", {"field": field})
	for field in [
		"previous_source_frontier_hash", "current_source_frontier_hash", "parent_structural_descriptor_hash",
		"parent_reconstruction_mapping_hash", "parent_guard_field_hash", "local_unbake_plan_hash",
	]:
		if not Utils.is_lower_hex_64(value.get(field)):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_HASH", {"field": field})
	if String(value["previous_source_frontier_hash"]) == String(value["current_source_frontier_hash"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_REQUIRES_SOURCE_REVISION")
	for field in ["canonical_part_count", "previous_bond_count", "current_bond_count", "minimum_rebake_component_parts"]:
		if not Utils.is_json_integer(value.get(field)) or int(value[field]) < 1:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COUNT", {"field": field})
	if int(value["current_bond_count"]) != int(value["previous_bond_count"]) - 1:
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BOND_COUNT_DELTA_INVALID")
	if int(value["minimum_rebake_component_parts"]) < 100:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_MINIMUM")
	if not Utils.is_positive_number(value.get("continuity_tolerance")) or not Utils.is_positive_number(value.get("conservation_tolerance")):
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_TOLERANCE")
	if typeof(value.get("transition_version")) != TYPE_STRING or String(value["transition_version"]).strip_edges().is_empty():
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_VERSION")

	if typeof(value.get("event")) != TYPE_DICTIONARY:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_EVENT")
	var event: Dictionary = value["event"]
	checked = Utils.validate_exact_fields(event, EVENT_FIELDS)
	if not bool(checked.get("success", false)):
		return checked
	for field in ["event_id", "bond_id", "target_region_id"]:
		if not Utils.is_canonical_id(event.get(field), 2):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_EVENT_ID", {"field": field})
	if String(event.get("event_type", "")) != "BOND_BREAK":
		return Utils.failure("UNSUPPORTED_STRUCTURAL_TOPOLOGY_EVENT")
	if not Utils.is_json_integer(event.get("event_tick")) or int(event["event_tick"]) < 0:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_EVENT_TICK")
	if not Utils.is_json_integer(event.get("event_sequence")) or int(event["event_sequence"]) < 1:
		return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_EVENT_SEQUENCE")
	if not Utils.is_lower_hex_64(event.get("event_hash")) or String(event["event_hash"]) != event_hash(event):
		return Utils.failure("STRUCTURAL_TOPOLOGY_EVENT_HASH_MISMATCH")

	if typeof(value.get("invalidated_pieces")) != TYPE_ARRAY or value["invalidated_pieces"].is_empty():
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATION_SET_EMPTY")
	var previous_piece := ""
	var invalidated_ids: Dictionary = {}
	for index in range(value["invalidated_pieces"].size()):
		var raw = value["invalidated_pieces"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATION", {"index": index})
		var invalidation: Dictionary = raw
		checked = Utils.validate_exact_fields(invalidation, INVALIDATION_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var piece_id := String(invalidation.get("piece_id", ""))
		if not Utils.is_canonical_id(piece_id, 2) or invalidated_ids.has(piece_id):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_PIECE_ID", {"piece_id": piece_id})
		if index > 0 and piece_id <= previous_piece:
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATIONS_NOT_SORTED_UNIQUE")
		previous_piece = piece_id
		invalidated_ids[piece_id] = true
		if not PIECE_KINDS.has(String(invalidation.get("piece_kind", ""))):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_PIECE_KIND", {"piece_id": piece_id})
		if not Utils.is_lower_hex_64(invalidation.get("descriptor_hash")):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATED_HASH", {"piece_id": piece_id})
		if String(invalidation.get("predecessor_frontier_hash", "")) != String(value["previous_source_frontier_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATION_PREDECESSOR_MISMATCH", {"piece_id": piece_id})
		if String(invalidation.get("current_frontier_hash", "")) != String(value["current_source_frontier_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATION_CURRENT_MISMATCH", {"piece_id": piece_id})
		if String(invalidation.get("reason", "")) != "TOPOLOGY_EVENT":
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_INVALIDATION_REASON", {"piece_id": piece_id})

	if typeof(value.get("rebaked_components")) != TYPE_ARRAY or value["rebaked_components"].size() < 2:
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_REQUIRES_SPLIT_COMPONENTS")
	var covered_parts: Dictionary = {}
	var covered_bonds: Dictionary = {}
	var previous_component := ""
	for index in range(value["rebaked_components"].size()):
		var raw = value["rebaked_components"][index]
		if typeof(raw) != TYPE_DICTIONARY:
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT", {"index": index})
		var component: Dictionary = raw
		checked = Utils.validate_exact_fields(component, COMPONENT_FIELDS)
		if not bool(checked.get("success", false)):
			return checked
		var component_id := String(component.get("component_id", ""))
		if not Utils.is_canonical_id(component_id, 2):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_ID", {"component_id": component_id})
		if index > 0 and component_id <= previous_component:
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_COMPONENTS_NOT_SORTED_UNIQUE")
		previous_component = component_id
		checked = Utils.validate_sorted_unique_strings(component.get("part_ids"))
		if not bool(checked.get("success", false)) or component["part_ids"].size() < int(value["minimum_rebake_component_parts"]):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_PARTS", {"component_id": component_id})
		checked = Utils.validate_sorted_unique_strings(component.get("bond_ids"), true)
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_BONDS", {"component_id": component_id})
		checked = Utils.validate_sorted_unique_strings(component.get("anchor_ids"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_ANCHORS", {"component_id": component_id})
		checked = Utils.validate_sorted_unique_strings(component.get("predecessor_piece_ids"))
		if not bool(checked.get("success", false)):
			return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_LINEAGE", {"component_id": component_id})
		for part_id in component["part_ids"]:
			var key := String(part_id)
			if covered_parts.has(key):
				return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_DUPLICATE_PART_COVERAGE", {"part_id": key})
			covered_parts[key] = component_id
		for bond_id in component["bond_ids"]:
			var key := String(bond_id)
			if key == String(event["bond_id"]):
				return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BROKEN_BOND_RETAINED")
			if covered_bonds.has(key):
				return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_DUPLICATE_BOND_COVERAGE", {"bond_id": key})
			covered_bonds[key] = component_id
		for field in ["descriptor", "reconstruction_mapping", "guard_field", "physical_bake_artifact"]:
			if typeof(component.get(field)) != TYPE_DICTIONARY or component[field].is_empty():
				return Utils.failure("INVALID_STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_ARTIFACT", {"component_id": component_id, "field": field})
		checked = Descriptor.validate(component["descriptor"])
		if not bool(checked.get("success", false)):
			return checked
		checked = Reconstruction.validate(component["reconstruction_mapping"])
		if not bool(checked.get("success", false)):
			return checked
		checked = GuardField.validate(component["guard_field"])
		if not bool(checked.get("success", false)):
			return checked
		checked = Artifact.validate(component["physical_bake_artifact"])
		if not bool(checked.get("success", false)):
			return checked
		var descriptor: Dictionary = component["descriptor"]
		var mapping: Dictionary = component["reconstruction_mapping"]
		var guard_field: Dictionary = component["guard_field"]
		var artifact: Dictionary = component["physical_bake_artifact"]
		if String(descriptor["source_frontier_hash"]) != String(value["current_source_frontier_hash"]) or String(mapping["source_frontier_hash"]) != String(value["current_source_frontier_hash"]) or String(guard_field["source_frontier_hash"]) != String(value["current_source_frontier_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_FRONTIER_MISMATCH", {"component_id": component_id})
		if String(descriptor["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_MAPPING_MISMATCH", {"component_id": component_id})
		if String(guard_field["structural_descriptor_hash"]) != String(descriptor["checksum"]) or String(guard_field["reconstruction_mapping_hash"]) != String(mapping["checksum"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_COMPONENT_GUARD_MISMATCH", {"component_id": component_id})
		if String(artifact["source_binding"]["frontier_hash"]) != String(value["current_source_frontier_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_ARTIFACT_FRONTIER_MISMATCH", {"component_id": component_id})
		if String(artifact["reduced_model_descriptor_hash"]) != String(descriptor["checksum"]) or String(artifact["reduced_state_schema_hash"]) != String(descriptor["reduced_state_schema_hash"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_ARTIFACT_MODEL_MISMATCH", {"component_id": component_id})
		if JSON.stringify(artifact["refinement_guards"]) != JSON.stringify(guard_field["region_guards"]):
			return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_ARTIFACT_GUARD_MISMATCH", {"component_id": component_id})
	if covered_parts.size() != int(value["canonical_part_count"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_PART_COVERAGE_MISMATCH", {"covered": covered_parts.size()})
	if covered_bonds.size() != int(value["current_bond_count"]):
		return Utils.failure("STRUCTURAL_TOPOLOGY_REBAKE_BOND_COVERAGE_MISMATCH", {"covered": covered_bonds.size()})
	return Utils.validate_checksum(value)

static func event_hash(event: Dictionary) -> String:
	var payload := event.duplicate(true)
	payload.erase("event_hash")
	return Utils.canonical_hash(payload)
