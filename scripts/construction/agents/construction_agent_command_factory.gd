extends RefCounted

const P = preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Command = preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Routed = preload("res://scripts/construction/distributed/construction_distributed_command.gd")
const Grant = preload("res://scripts/construction/multiplayer/construction_multiplayer_permission_grant.gd")

static func build_stage(goal: Dictionary, step: Dictionary) -> Dictionary:
 var payload: Dictionary = step["payload"]
 return _create(
  goal,
  step,
  Grant.ACTION_BUILD,
  "stage-%d" % int(payload["stage_index"]),
  int(payload.get("command_sequence_offset", 0)),
  {
   "build_plan_id": String(payload["build_plan_id"]),
   "stage_index": int(payload["stage_index"]),
   "operation_id": String(step["operation_id"]),
   "provided_capabilities": Array(step["required_agent_capabilities"]).duplicate(),
   "options": Dictionary(payload.get("options", {})).duplicate(true),
  }
 )

static func repair(goal: Dictionary, step: Dictionary) -> Dictionary:
 var payload: Dictionary = step["payload"]
 return _create(
  goal,
  step,
  Grant.ACTION_REPAIR,
  "repair",
  int(payload.get("command_sequence_offset", 0)),
  {
   "plan_id": String(payload["plan_id"]),
   "operation_id": String(step["operation_id"]),
   "repair_plan": Dictionary(payload["repair_plan"]).duplicate(true),
   "failure_mode": String(payload.get("failure_mode", "")),
  }
 )

static func salvage(goal: Dictionary, step: Dictionary) -> Dictionary:
 var payload: Dictionary = step["payload"]
 return _create(
  goal,
  step,
  Grant.ACTION_DAMAGE,
  "salvage",
  int(payload.get("command_sequence_offset", 0)),
  {
   "plan_id": String(payload["plan_id"]),
   "operation_id": String(step["operation_id"]),
   "request": Dictionary(payload["request"]).duplicate(true),
   "failure_mode": String(payload.get("failure_mode", "")),
  }
 )

static func _create(
 goal: Dictionary,
 step: Dictionary,
 action: String,
 command_suffix: String,
 sequence_offset: int,
 domain_payload: Dictionary
) -> Dictionary:
 var context: Dictionary = goal["execution_context"]
 var goal_key := String(goal["goal_id"]).trim_prefix("agent-goal/").replace("/", ":")
 var inner := Command.create(
  "multiplayer-command/agent/%s/%s" % [goal_key, command_suffix],
  String(context["client_id"]),
  String(context["session_id"]),
  int(context["session_epoch"]),
  int(context["start_sequence"]) + sequence_offset,
  action,
  String(goal["target_construct_id"]),
  String(step["payload"].get("expected_construct_checksum", "")),
  int(context["expected_server_generation"]),
  int(context["permission_epoch"]),
  domain_payload,
  {"agent_id": String(goal["agent_id"]), "goal_id": String(goal["goal_id"])}
 )
 var checked := Command.validate(inner)
 if not bool(checked.get("success", false)):
  return checked
 var routed := Routed.create(
  "authority-route/agent/%s/%s" % [goal_key, command_suffix],
  String(context["entry_server_id"]),
  String(context["expected_owner_server_id"]),
  int(context["authority_epoch"]),
  inner,
  {"agent_id": String(goal["agent_id"]), "goal_id": String(goal["goal_id"])}
 )
 checked = Routed.validate(routed)
 if not bool(checked.get("success", false)):
  return checked
 return P.success({"command": routed})
