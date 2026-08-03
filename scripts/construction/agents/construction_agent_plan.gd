extends RefCounted

const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Goal = preload("res://scripts/construction/agents/construction_agent_goal.gd")
const Bom = preload("res://scripts/construction/agents/construction_agent_bom.gd")
const Step = preload("res://scripts/construction/agents/construction_agent_step.gd")
const BuildPlan = preload("res://scripts/construction/build/construction_build_plan.gd")
const Instantiation = preload("res://scripts/construction/composites/construction_composite_instantiation.gd")

const SCHEMA = "planet_simulator.construction_agent_plan.v1"
const FIELDS: Array[String] = [
 "schema", "plan_id", "goal_id", "goal_kind", "goal_checksum", "bom",
 "build_plan", "instantiation", "steps", "estimated_cost", "status", "checksum",
]
const STATUSES = ["PLANNED", "BLOCKED"]

static func create(
 plan_id: String,
 goal: Dictionary,
 bom: Dictionary,
 build_plan: Dictionary,
 instantiation: Dictionary,
 steps: Array
) -> Dictionary:
 var estimated_cost := 0.0
 for step in steps:
  estimated_cost += float(step.get("estimated_cost", 0.0))
 var sorted_steps: Array = steps.duplicate(true)
 sorted_steps.sort_custom(func(a, b):
  var left_index := int(a.get("sequence_index", -1))
  var right_index := int(b.get("sequence_index", -1))
  if left_index != right_index:
   return left_index < right_index
  return String(a.get("step_id", "")) < String(b.get("step_id", ""))
 )
 var value := {
  "schema": SCHEMA,
  "plan_id": plan_id,
  "goal_id": String(goal.get("goal_id", "")),
  "goal_kind": String(goal.get("goal_kind", "")),
  "goal_checksum": String(goal.get("checksum", "")),
  "bom": bom.duplicate(true),
  "build_plan": build_plan.duplicate(true),
  "instantiation": instantiation.duplicate(true),
  "steps": sorted_steps,
  "estimated_cost": P.metric(maxf(estimated_cost, float(bom.get("total_estimated_cost", 0.0)))),
  "status": "PLANNED" if bool(bom.get("ready_for_execution", false)) else "BLOCKED",
  "checksum": "",
 }
 value["checksum"] = compute_checksum(value)
 return value

static func validate(value: Dictionary) -> Dictionary:
 var checked := Utils.validate_exact_fields(value, FIELDS)
 if not bool(checked.get("success", false)):
  return checked
 if value.get("schema") != SCHEMA:
  return P.failure("UNSUPPORTED_CONSTRUCTION_AGENT_PLAN_SCHEMA")
 if not P.path_id(String(value.get("plan_id", "")), "agent-plan/") \
 or not P.path_id(String(value.get("goal_id", "")), "agent-goal/") \
 or String(value.get("goal_checksum", "")).length() != 64:
  return P.failure("INVALID_CONSTRUCTION_AGENT_PLAN_IDENTITY")
 if not Goal.GOAL_KINDS.has(String(value.get("goal_kind", ""))):
  return P.failure("INVALID_CONSTRUCTION_AGENT_PLAN_GOAL_KIND")
 if typeof(value.get("bom")) != TYPE_DICTIONARY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_PLAN_BOM")
 checked = Bom.validate(value["bom"])
 if not bool(checked.get("success", false)):
  return checked
 if String(value["bom"].get("goal_id", "")) != String(value["goal_id"]) \
 or String(value["bom"].get("goal_checksum", "")) != String(value["goal_checksum"]):
  return P.failure("CONSTRUCTION_AGENT_PLAN_BOM_MISMATCH")
 if not STATUSES.has(String(value.get("status", ""))):
  return P.failure("INVALID_CONSTRUCTION_AGENT_PLAN_STATUS")
 var is_build := String(value["goal_kind"]) == Goal.BUILD_COMPOSITE
 if String(value["status"]) == "PLANNED" and is_build:
  checked = BuildPlan.validate(value["build_plan"])
  if not bool(checked.get("success", false)):
   return checked
  checked = Instantiation.validate(value["instantiation"])
  if not bool(checked.get("success", false)):
   return checked
 elif not Dictionary(value.get("build_plan", {})).is_empty() \
 or not Dictionary(value.get("instantiation", {})).is_empty():
  return P.failure("NON_BUILD_CONSTRUCTION_AGENT_PLAN_HAS_BUILD_ARTIFACTS")
 if typeof(value.get("steps")) != TYPE_ARRAY:
  return P.failure("INVALID_CONSTRUCTION_AGENT_PLAN_STEPS")
 var previous_index := -1
 var previous_id := ""
 var seen := {}
 var cost := 0.0
 for row in value["steps"]:
  if typeof(row) != TYPE_DICTIONARY:
   return P.failure("INVALID_CONSTRUCTION_AGENT_PLAN_STEP")
  checked = Step.validate(row)
  if not bool(checked.get("success", false)):
   return checked
  if int(row.get("sequence_index", -1)) != previous_index + 1:
   return P.failure("CONSTRUCTION_AGENT_PLAN_STEP_SEQUENCE_GAP")
  for dependency in row.get("dependency_step_ids", []):
   if not seen.has(String(dependency)):
    return P.failure("CONSTRUCTION_AGENT_PLAN_FORWARD_DEPENDENCY")
  if not previous_id.is_empty() and not Array(row.get("dependency_step_ids", [])).has(previous_id):
   return P.failure("CONSTRUCTION_AGENT_PLAN_STEP_CHAIN_BROKEN")
  seen[String(row["step_id"])] = true
  previous_id = String(row["step_id"])
  previous_index = int(row["sequence_index"])
  cost += float(row["estimated_cost"])
 if String(value["status"]) == "PLANNED" and Array(value["steps"]).is_empty():
  return P.failure("CONSTRUCTION_AGENT_PLAN_STEPS_REQUIRED")
 if String(value["status"]) == "BLOCKED" and not Array(value["steps"]).is_empty():
  return P.failure("BLOCKED_CONSTRUCTION_AGENT_PLAN_HAS_STEPS")
 if not P.nearly_equal(
  float(value.get("estimated_cost", -1)),
  P.metric(maxf(cost, float(value["bom"].get("total_estimated_cost", 0.0))))
 ):
  return P.failure("CONSTRUCTION_AGENT_PLAN_COST_MISMATCH")
 if String(value.get("checksum", "")) != compute_checksum(value):
  return P.failure("CONSTRUCTION_AGENT_PLAN_CHECKSUM_MISMATCH")
 return P.success()

static func compute_checksum(value: Dictionary) -> String:
 var payload := value.duplicate(true)
 payload["checksum"] = ""
 return Utils.payload_hash(payload)
