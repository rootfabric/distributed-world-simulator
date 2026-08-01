extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")

const SCHEMA := "planet_simulator.construction_agent_goal.v1"
const FIELDS: Array[String] = ["schema", "goal_id", "agent_id", "goal_kind", "composite_definition_id", "definition_version", "definition_checksum", "target_construct_id", "root_item_instance_id", "placement_relation", "parameter_values", "required_outcomes", "priority", "budget_limit", "deadline_tick", "required_agent_capabilities", "required_tool_ids", "workspace_ids", "execution_context", "metadata", "checksum"]
const BUILD_COMPOSITE := "BUILD_COMPOSITE"
const REPAIR_CONSTRUCT := "REPAIR_CONSTRUCT"
const SALVAGE_CONSTRUCT := "SALVAGE_CONSTRUCT"
const GOAL_KINDS := [BUILD_COMPOSITE, REPAIR_CONSTRUCT, SALVAGE_CONSTRUCT]
const CONTEXT_FIELDS: Array[String] = ["client_id", "session_id", "session_epoch", "permission_epoch", "start_sequence", "entry_server_id", "expected_owner_server_id", "authority_epoch", "expected_server_generation"]

static func create(goal_id: String, agent_id: String, goal_kind: String, definition: Dictionary, target_construct_id: String, root_item_instance_id: String, placement_relation: Dictionary, parameter_values: Dictionary = {}, required_outcomes: Array = [], priority: int = 100, budget_limit: float = 0.0, deadline_tick: int = -1, required_agent_capabilities: Array = [], required_tool_ids: Array = [], workspace_ids: Array = [], execution_context: Dictionary = {}, metadata: Dictionary = {}) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"goal_id": goal_id,
		"agent_id": agent_id,
		"goal_kind": goal_kind,
		"composite_definition_id": String(definition.get("composite_definition_id", "")),
		"definition_version": int(definition.get("definition_version", 0)),
		"definition_checksum": String(definition.get("checksum", "")),
		"target_construct_id": target_construct_id,
		"root_item_instance_id": root_item_instance_id,
		"placement_relation": placement_relation.duplicate(true),
		"parameter_values": parameter_values.duplicate(true),
		"required_outcomes": P.sorted_strings(required_outcomes),
		"priority": priority,
		"budget_limit": budget_limit,
		"deadline_tick": deadline_tick,
		"required_agent_capabilities": P.sorted_strings(required_agent_capabilities),
		"required_tool_ids": P.sorted_strings(required_tool_ids),
		"workspace_ids": P.sorted_strings(workspace_ids),
		"execution_context": execution_context.duplicate(true),
		"metadata": metadata.duplicate(true),
		"checksum": "",
	}
	value["checksum"] = compute_checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	var exact := Utils.validate_exact_fields(value, FIELDS)
	if not bool(exact.get("success", false)): return exact
	if value.get("schema") != SCHEMA: return P.failure("UNSUPPORTED_CONSTRUCTION_AGENT_GOAL_SCHEMA")
	if not P.path_id(String(value.get("goal_id", "")), "agent-goal/") or not P.path_id(String(value.get("agent_id", "")), "agent/"): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_IDENTITY")
	if not GOAL_KINDS.has(String(value.get("goal_kind", ""))): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_KIND")
	if not P.path_id(String(value.get("target_construct_id", "")), "construct/") or not P.path_id(String(value.get("root_item_instance_id", "")), "item/"): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_TARGET")
	if String(value["goal_kind"]) == BUILD_COMPOSITE:
		if not P.path_id(String(value.get("composite_definition_id", "")), "composite-definition/"): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_DEFINITION")
		if not Utils.is_json_integer(value.get("definition_version")) or int(value["definition_version"]) < 1 or String(value.get("definition_checksum", "")).length() != 64: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_DEFINITION")
	if typeof(value.get("placement_relation")) != TYPE_DICTIONARY: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_RELATION")
	var relation_checked := ProjectionScript.validate_relation(value["placement_relation"])
	if not bool(relation_checked.get("success", false)): return relation_checked
	if typeof(value.get("parameter_values")) != TYPE_DICTIONARY or typeof(value.get("metadata")) != TYPE_DICTIONARY: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_PAYLOAD")
	if not bool(Utils.canonicalize(value["parameter_values"]).get("success", false)) or not bool(Utils.canonicalize(value["metadata"]).get("success", false)): return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_GOAL_PAYLOAD")
	for field in ["required_outcomes", "required_agent_capabilities", "required_tool_ids", "workspace_ids"]:
		var checked := _validate_sorted_strings(value.get(field), field == "required_outcomes" or field == "required_agent_capabilities")
		if not bool(checked.get("success", false)): return checked
	if not Utils.is_json_integer(value.get("priority")) or int(value["priority"]) < 0 or int(value["priority"]) > 1000: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_PRIORITY")
	if not P.non_negative_number(value.get("budget_limit")): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_BUDGET")
	if not Utils.is_json_integer(value.get("deadline_tick")) or int(value["deadline_tick"]) < -1: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_DEADLINE")
	var context_checked := _validate_context(value.get("execution_context"))
	if not bool(context_checked.get("success", false)): return context_checked
	if String(value.get("checksum", "")) != compute_checksum(value): return P.failure("CONSTRUCTION_AGENT_GOAL_CHECKSUM_MISMATCH")
	return P.success()

static func compute_checksum(value: Dictionary) -> String:
	var payload := value.duplicate(true); payload["checksum"] = ""; return Utils.payload_hash(payload)

static func _validate_context(raw) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY: return P.failure("INVALID_CONSTRUCTION_AGENT_EXECUTION_CONTEXT")
	var context: Dictionary = raw
	var exact := Utils.validate_exact_fields(context, CONTEXT_FIELDS)
	if not bool(exact.get("success", false)): return exact
	for spec in [["client_id", "client/"], ["session_id", "session/"], ["entry_server_id", "server/"], ["expected_owner_server_id", "server/"]]:
		if not P.path_id(String(context.get(String(spec[0]), "")), String(spec[1])): return P.failure("INVALID_CONSTRUCTION_AGENT_EXECUTION_CONTEXT_ID")
	for field in ["session_epoch", "permission_epoch", "start_sequence", "authority_epoch"]:
		if not Utils.is_json_integer(context.get(field)) or int(context[field]) < 0: return P.failure("INVALID_CONSTRUCTION_AGENT_EXECUTION_CONTEXT_COUNTER")
	if int(context["authority_epoch"]) < 1: return P.failure("INVALID_CONSTRUCTION_AGENT_EXECUTION_CONTEXT_COUNTER")
	if not Utils.is_json_integer(context.get("expected_server_generation")) or int(context["expected_server_generation"]) < -1: return P.failure("INVALID_CONSTRUCTION_AGENT_EXECUTION_CONTEXT_GENERATION")
	return P.success()

static func _validate_sorted_strings(raw, upper: bool) -> Dictionary:
	if typeof(raw) != TYPE_ARRAY: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_LIST")
	var previous := ""; var seen := {}
	for item in raw:
		if typeof(item) != TYPE_STRING: return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_LIST")
		var text := String(item)
		if text.is_empty() or seen.has(text) or (not previous.is_empty() and text < previous): return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_GOAL_LIST")
		if upper and not P.upper_kind(text): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_CAPABILITY")
		if not upper and not P.path_id(text, text.split("/", true)[0] + "/"): return P.failure("INVALID_CONSTRUCTION_AGENT_GOAL_RESOURCE_ID")
		seen[text] = true; previous = text
	return P.success()
