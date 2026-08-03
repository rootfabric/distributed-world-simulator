extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Recipe = preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const ProjectionScript = preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const BuildPlan = preload("res://scripts/construction/build/construction_build_plan.gd")
const Instantiation = preload("res://scripts/construction/composites/construction_composite_instantiation.gd")
const DamageRequest = preload("res://scripts/construction/damage/construction_damage_request.gd")
const RepairPlan = preload("res://scripts/construction/damage/construction_repair_plan.gd")

const SCHEMA = "planet_simulator.construction_agent_step.v1"
const FIELDS: Array[String] = [
 "schema", "step_id", "sequence_index", "kind", "dependency_step_ids",
 "required_agent_capabilities", "required_tool_ids", "workspace_ids",
 "payload", "estimated_cost", "operation_id", "checksum",
]
const RESERVE = "RESERVE_RESOURCES"
const FABRICATE = "FABRICATE_ITEM"
const DELIVER = "DELIVER_ITEMS"
const REGISTER = "REGISTER_BUILD_PLAN"
const BUILD = "BUILD_STAGE"
const VERIFY = "VERIFY_OUTCOME"
const REPAIR = "REPAIR_CONSTRUCT"
const SALVAGE = "SALVAGE_CONSTRUCT"
const KINDS = [RESERVE, FABRICATE, DELIVER, REGISTER, BUILD, VERIFY, REPAIR, SALVAGE]

const RESERVE_FIELDS: Array[String] = ["requests", "lease_ticks"]
const FABRICATE_FIELDS: Array[String] = ["recipe", "output_projection", "binding", "machine_construct_ids"]
const FABRICATION_BINDING_FIELDS: Array[String] = [
 "recipe_id", "recipe_version", "recipe_checksum", "product_key",
 "output_item_id", "output_quantity", "input_requirements",
]
const DELIVER_FIELDS: Array[String] = ["item_instance_ids", "target_relation"]
const REGISTER_FIELDS: Array[String] = ["build_plan", "instantiation"]
const BUILD_FIELDS: Array[String] = [
 "build_plan_id", "stage_index", "command_sequence_offset",
 "expected_construct_checksum", "options",
]
const VERIFY_FIELDS: Array[String] = ["construct_id", "required_outcomes"]
const REPAIR_FIELDS: Array[String] = ["plan_id", "repair_plan", "failure_mode", "command_sequence_offset"]
const SALVAGE_FIELDS: Array[String] = ["plan_id", "request", "failure_mode", "command_sequence_offset"]

static func create(
 step_id: String,
 index: int,
 kind: String,
 dependencies: Array,
 payload: Dictionary,
 operation_id: String,
 required_agent_capabilities: Array = [],
 required_tool_ids: Array = [],
 workspace_ids: Array = [],
 estimated_cost: float = 0.0
) -> Dictionary:
 var value := {
  "schema": SCHEMA,
  "step_id": step_id,
  "sequence_index": index,
  "kind": kind,
  "dependency_step_ids": P.sorted_strings(dependencies),
  "required_agent_capabilities": P.sorted_strings(required_agent_capabilities),
  "required_tool_ids": P.sorted_strings(required_tool_ids),
  "workspace_ids": P.sorted_strings(workspace_ids),
  "payload": payload.duplicate(true),
  "estimated_cost": P.metric(estimated_cost),
  "operation_id": operation_id,
  "checksum": "",
 }
 value["checksum"] = compute_checksum(value)
 return value

static func validate(value: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(value, FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if value.get("schema") != SCHEMA:
  return P.failure("UNSUPPORTED_CONSTRUCTION_AGENT_STEP_SCHEMA")
 if not P.path_id(String(value.get("step_id", "")), "agent-step/") \
 or not P.path_id(String(value.get("operation_id", "")), "operation/"):
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_IDENTITY")
 if not Utils.is_json_integer(value.get("sequence_index")) or int(value["sequence_index"]) < 0:
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_SEQUENCE")
 if not KINDS.has(String(value.get("kind", ""))):
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_KIND")
 for spec in [["dependency_step_ids", "agent-step/"], ["required_tool_ids", ""], ["workspace_ids", ""]]:
  checked = _sorted_ids(value.get(String(spec[0])), String(spec[1]))
  if not bool(checked.get("success", false)):
   return checked
 checked = _upper(value.get("required_agent_capabilities"))
 if not bool(checked.get("success", false)):
  return checked
 if typeof(value.get("payload")) != TYPE_DICTIONARY \
 or not bool(Utils.canonicalize(value["payload"]).get("success", false)):
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_PAYLOAD")
 checked = _validate_payload(String(value["kind"]), value["payload"])
 if not bool(checked.get("success", false)):
  return checked
 if not P.non_negative_number(value.get("estimated_cost")):
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_COST")
 if String(value.get("checksum", "")) != compute_checksum(value):
  return P.failure("CONSTRUCTION_AGENT_STEP_CHECKSUM_MISMATCH")
 return P.success()

static func _validate_payload(kind: String, payload: Dictionary) -> Dictionary:
 match kind:
  RESERVE:
   return _validate_reserve(payload)
  FABRICATE:
   return _validate_fabricate(payload)
  DELIVER:
   return _validate_deliver(payload)
  REGISTER:
   return _validate_register(payload)
  BUILD:
   return _validate_build(payload)
  VERIFY:
   return _validate_verify(payload)
  REPAIR:
   return _validate_repair(payload)
  SALVAGE:
   return _validate_salvage(payload)
  _:
   return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_KIND")

static func _validate_reserve(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, RESERVE_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("requests")) != TYPE_ARRAY or Array(payload["requests"]).is_empty():
  return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_REQUESTS")
 var previous := ""
 var seen := {}
 for request in payload["requests"]:
  if typeof(request) != TYPE_DICTIONARY:
   return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_REQUEST")
  checked = Utils.validate_exact_fields(request, ["resource_kind", "resource_id", "quantity", "exclusive"])
  if not bool(checked.get("success", false)):
   return checked
  var kind := String(request.get("resource_kind", ""))
  var resource_id := String(request.get("resource_id", ""))
  var key := "%s|%s" % [kind, resource_id]
  if not kind in ["ITEM", "TOOL", "WORKSPACE", "BUDGET"] or resource_id.is_empty() or seen.has(key) or (not previous.is_empty() and key < previous):
   return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_RESERVATION_REQUESTS")
  if not P.positive_number(request.get("quantity")) or typeof(request.get("exclusive")) != TYPE_BOOL:
   return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_REQUEST")
  seen[key] = true
  previous = key
 if not Utils.is_json_integer(payload.get("lease_ticks")) or int(payload["lease_ticks"]) < 1:
  return P.failure("INVALID_CONSTRUCTION_AGENT_RESERVATION_LEASE")
 return P.success()

static func _validate_fabricate(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, FABRICATE_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("recipe")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_FABRICATION_RECIPE")
 checked = Recipe.validate(payload["recipe"])
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("output_projection")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_FABRICATION_OUTPUT")
 checked = ProjectionScript.validate(payload["output_projection"])
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("binding")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_FABRICATION_BINDING")
 checked = Utils.validate_exact_fields(payload["binding"], FABRICATION_BINDING_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 var binding: Dictionary = payload["binding"]
 var recipe: Dictionary = payload["recipe"]
 var output: Dictionary = payload["output_projection"]
 if String(binding.get("recipe_id", "")) != String(recipe.get("recipe_id", "")) \
 or int(binding.get("recipe_version", -1)) != int(recipe.get("recipe_version", -2)) \
 or String(binding.get("recipe_checksum", "")) != String(recipe.get("checksum", "")):
  return P.failure("CONSTRUCTION_AGENT_FABRICATION_BINDING_RECIPE_MISMATCH")
 if String(binding.get("output_item_id", "")) != String(output.get("item_instance_id", "")) \
 or int(binding.get("output_quantity", -1)) != int(output.get("quantity", -2)):
  return P.failure("CONSTRUCTION_AGENT_FABRICATION_BINDING_OUTPUT_MISMATCH")
 if Utils.canonical_json(binding.get("input_requirements")) != Utils.canonical_json(recipe.get("input_requirements")):
  return P.failure("CONSTRUCTION_AGENT_FABRICATION_BINDING_INPUT_MISMATCH")
 var product_found := false
 for product in recipe["output_products"]:
  if String(product.get("product_key", "")) != String(binding.get("product_key", "")):
   continue
  product_found = true
  if String(product.get("definition_id", "")) != String(output.get("definition_id", "")):
   return P.failure("CONSTRUCTION_AGENT_FABRICATION_PRODUCT_MISMATCH")
  break
 if not product_found:
  return P.failure("CONSTRUCTION_AGENT_FABRICATION_PRODUCT_NOT_FOUND")
 checked = _sorted_ids(payload.get("machine_construct_ids"), "construct/")
 if not bool(checked.get("success", false)):
  return checked
 return P.success()

static func _validate_deliver(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, DELIVER_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 checked = _sorted_ids(payload.get("item_instance_ids"), "item/")
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("target_relation")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_DELIVERY_RELATION")
 checked = ProjectionScript.validate_relation(payload["target_relation"])
 if not bool(checked.get("success", false)):
  return checked
 return P.success()

static func _validate_register(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, REGISTER_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("build_plan")) != TYPE_DICTIONARY \
 or typeof(payload.get("instantiation")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_REGISTRATION_PAYLOAD")
 checked = BuildPlan.validate(payload["build_plan"])
 if not bool(checked.get("success", false)):
  return checked
 checked = Instantiation.validate(payload["instantiation"])
 if not bool(checked.get("success", false)):
  return checked
 if String(payload["instantiation"].get("build_plan_checksum", "")) != String(payload["build_plan"].get("checksum", "")):
  return P.failure("CONSTRUCTION_AGENT_REGISTRATION_ARTIFACT_MISMATCH")
 return P.success()

static func _validate_build(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, BUILD_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if not P.path_id(String(payload.get("build_plan_id", "")), "build-plan/"):
  return P.failure("INVALID_CONSTRUCTION_AGENT_BUILD_PLAN_ID")
 for field in ["stage_index", "command_sequence_offset"]:
  if not Utils.is_json_integer(payload.get(field)) or int(payload[field]) < 0:
   return P.failure("INVALID_CONSTRUCTION_AGENT_BUILD_STAGE_INDEX")
 var expected := String(payload.get("expected_construct_checksum", ""))
 if not expected.is_empty() and (expected.length() != 64 or expected != expected.to_lower()):
  return P.failure("INVALID_CONSTRUCTION_AGENT_BUILD_PRECONDITION")
 if typeof(payload.get("options")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_BUILD_OPTIONS")
 return P.success()

static func _validate_verify(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, VERIFY_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if not P.path_id(String(payload.get("construct_id", "")), "construct/"):
  return P.failure("INVALID_CONSTRUCTION_AGENT_VERIFY_CONSTRUCT")
 return _upper(payload.get("required_outcomes"))

static func _validate_repair(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, REPAIR_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if not P.path_id(String(payload.get("plan_id", "")), "damage-plan/"):
  return P.failure("INVALID_CONSTRUCTION_AGENT_REPAIR_PLAN_ID")
 if typeof(payload.get("repair_plan")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_REPAIR_PLAN")
 checked = RepairPlan.validate(payload["repair_plan"])
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("failure_mode")) != TYPE_STRING:
  return P.failure("INVALID_CONSTRUCTION_AGENT_REPAIR_FAILURE_MODE")
 if not Utils.is_json_integer(payload.get("command_sequence_offset")) or int(payload["command_sequence_offset"]) < 0:
  return P.failure("INVALID_CONSTRUCTION_AGENT_REPAIR_SEQUENCE")
 return P.success()

static func _validate_salvage(payload: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(payload, SALVAGE_FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if not P.path_id(String(payload.get("plan_id", "")), "damage-plan/"):
  return P.failure("INVALID_CONSTRUCTION_AGENT_SALVAGE_PLAN_ID")
 if typeof(payload.get("request")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_SALVAGE_REQUEST")
 checked = DamageRequest.validate(payload["request"])
 if not bool(checked.get("success", false)):
  return checked
 if typeof(payload.get("failure_mode")) != TYPE_STRING:
  return P.failure("INVALID_CONSTRUCTION_AGENT_SALVAGE_FAILURE_MODE")
 if not Utils.is_json_integer(payload.get("command_sequence_offset")) or int(payload["command_sequence_offset"]) < 0:
  return P.failure("INVALID_CONSTRUCTION_AGENT_SALVAGE_SEQUENCE")
 return P.success()

static func _upper(raw) -> Dictionary:
 if typeof(raw) != TYPE_ARRAY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_CAPABILITIES")
 var previous := ""
 var seen := {}
 for value in raw:
  var text := String(value)
  if not P.upper_kind(text) or seen.has(text) or (not previous.is_empty() and text < previous):
   return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_STEP_CAPABILITIES")
  seen[text] = true
  previous = text
 return P.success()

static func _sorted_ids(raw, prefix: String) -> Dictionary:
 if typeof(raw) != TYPE_ARRAY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_RESOURCE_LIST")
 var previous := ""
 var seen := {}
 for value in raw:
  var text := String(value)
  if text.is_empty() or seen.has(text) or (not previous.is_empty() and text < previous):
   return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_STEP_RESOURCE_LIST")
  if not prefix.is_empty() and not P.path_id(text, prefix):
   return P.failure("INVALID_CONSTRUCTION_AGENT_STEP_RESOURCE_ID")
  seen[text] = true
  previous = text
 return P.success()

static func compute_checksum(value: Dictionary) -> String:
 var payload := value.duplicate(true)
 payload["checksum"] = ""
 return Utils.payload_hash(payload)
