extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Goal=preload("res://scripts/construction/agents/construction_agent_goal.gd")
const Work=preload("res://scripts/construction/agents/construction_agent_work_item.gd")
const Plan=preload("res://scripts/construction/agents/construction_agent_plan.gd")
const Queue=preload("res://scripts/construction/agents/construction_agent_work_queue.gd")
const Reservations=preload("res://scripts/construction/agents/construction_agent_reservation_store.gd")
const SCHEMA="planet_simulator.construction_agent_automation_api.v1"
const FIELDS:Array[String]=["schema","generation","goals","plans","queue","reservations","terminal_goal_submissions","checksum"]
var _planner;var _executor;var _queue;var _reservations;var _goals:Dictionary={};var _plans:Dictionary={};var _operations:Dictionary={};var _generation:=0
func setup(planner,executor,queue=null,reservations=null)->Dictionary:
 if planner==null or not planner.has_method("compile") or executor==null or not executor.has_method("execute_next"):return P.failure("CONSTRUCTION_AGENT_AUTOMATION_COMPONENT_REQUIRED")
 _planner=planner;_executor=executor;_queue=queue if queue!=null else Queue.new();_reservations=reservations if reservations!=null else Reservations.new()
 if _queue.has_method("setup"):_queue.setup()
 return P.success()
func submit_goal(operation_id:String,goal:Dictionary,definition:Dictionary,inventory:Array,recipes:Array,options:Dictionary={})->Dictionary:
 var checksum=Utils.payload_hash({"operation_id":operation_id,"goal":goal,"definition_checksum":String(definition.get("checksum","")),"inventory_fingerprints":_inventory_fingerprints(inventory),"recipe_checksums":_recipe_checksums(recipes),"options":options})
 if _operations.has(operation_id):
  var old:Dictionary=_operations[operation_id];if String(old.checksum)!=checksum:return P.failure("CONSTRUCTION_AGENT_GOAL_SUBMISSION_OPERATION_ID_CONFLICT")
  var replay=Dictionary(old.result).duplicate(true);replay.replay=true;return replay
 var checked=Goal.validate(goal);if not bool(checked.success):return checked
 var planned=_planner.compile(goal,definition,inventory,recipes,options);if not bool(planned.success):return planned
 var plan:Dictionary=planned.plan;var work=Work.create("agent-work/%s"%String(goal.goal_id).trim_prefix("agent-goal/").replace("/",":"),String(goal.agent_id),plan);var enqueued=_queue.enqueue(work);if not bool(enqueued.success):return enqueued
 _goals[String(goal.goal_id)]=goal.duplicate(true);_plans[String(plan.plan_id)]=plan.duplicate(true);_generation+=1
 var result=P.success({"replay":false,"goal":goal.duplicate(true),"bom":planned.bom,"plan":plan,"work_item":enqueued.work_item,"blocked":bool(planned.blocked)})
 _operations[operation_id]={"operation_id":operation_id,"checksum":checksum,"result":result.duplicate(true)};return result
func execute_next(work_item_id:String,current_tick:int)->Dictionary:
 var item=_queue.get_work_item(work_item_id);if item.is_empty():return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_NOT_FOUND")
 var goal=Dictionary(_goals.get(String(item.goal_id),{}));if goal.is_empty():return P.failure("CONSTRUCTION_AGENT_GOAL_NOT_FOUND")
 return _executor.execute_next(work_item_id,goal,current_tick)
func run_until_blocked(work_item_id:String,current_tick:int,maximum_steps:int=64)->Dictionary:
 var item=_queue.get_work_item(work_item_id);if item.is_empty():return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_NOT_FOUND")
 var goal=Dictionary(_goals.get(String(item.goal_id),{}));return _executor.run_until_blocked(work_item_id,goal,current_tick,maximum_steps)
func get_queue():return _queue
func get_reservation_store():return _reservations
func export_state()->Dictionary:
 var goals: Array = []
 var ids := _goals.keys()
 ids.sort()
 for id in ids:
  goals.append(_goals[id].duplicate(true))
 var plans: Array = []
 ids = _plans.keys()
 ids.sort()
 for id in ids:
  plans.append(_plans[id].duplicate(true))
 var ops: Array = []
 ids = _operations.keys()
 ids.sort()
 for id in ids:
  ops.append(_operations[id].duplicate(true))
 var v={"schema":SCHEMA,"generation":_generation,"goals":goals,"plans":plans,"queue":_queue.to_dict(),"reservations":_reservations.to_dict(),"terminal_goal_submissions":ops,"checksum":""};v.checksum=compute_checksum(v);return v
func load_state(v:Dictionary)->Dictionary:
 var checked=validate_state(v);if not bool(checked.success):return checked
 var q=_queue.load_dict(v.queue);if not bool(q.success):return q
 var r=_reservations.load_dict(v.reservations);if not bool(r.success):return r
 _goals.clear()
 for row in v.goals:
  _goals[String(row.goal_id)] = row.duplicate(true)
 _plans.clear()
 for row in v.plans:
  _plans[String(row.plan_id)] = row.duplicate(true)
 _operations.clear()
 for row in v.terminal_goal_submissions:
  _operations[String(row.operation_id)] = row.duplicate(true)
 _generation=int(v.generation);return P.success()
static func validate_state(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not Utils.is_json_integer(v.get("generation")) or int(v.generation)<0:return P.failure("INVALID_CONSTRUCTION_AGENT_AUTOMATION_STATE")
 if typeof(v.get("goals"))!=TYPE_ARRAY or typeof(v.get("plans"))!=TYPE_ARRAY or typeof(v.get("terminal_goal_submissions"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_AUTOMATION_COLLECTIONS")
 var goal_ids:Dictionary={};var previous:=""
 for goal in v.goals:
  x = Goal.validate(goal)
  if not bool(x.success): return x
  var goal_id:=String(goal.goal_id);if goal_ids.has(goal_id) or (not previous.is_empty() and goal_id<previous):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_AUTOMATION_GOALS")
  goal_ids[goal_id]=String(goal.checksum);previous=goal_id
 var plan_ids:Dictionary={};previous=""
 for plan in v.plans:
  x=Plan.validate(plan);if not bool(x.success):return x
  var plan_id:=String(plan.plan_id);if plan_ids.has(plan_id) or (not previous.is_empty() and plan_id<previous):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_AUTOMATION_PLANS")
  if not goal_ids.has(String(plan.goal_id)) or String(goal_ids[String(plan.goal_id)])!=String(plan.goal_checksum):return P.failure("CONSTRUCTION_AGENT_AUTOMATION_PLAN_GOAL_MISMATCH")
  plan_ids[plan_id]=true;previous=plan_id
 x=Queue.validate_state(v.queue);if not bool(x.success):return x
 for work_item in v.queue.work_items:
  if not plan_ids.has(String(work_item.plan.plan_id)):return P.failure("CONSTRUCTION_AGENT_AUTOMATION_QUEUE_PLAN_MISSING")
 x=Reservations.validate_state(v.reservations);if not bool(x.success):return x
 previous="";var operation_ids:Dictionary={}
 for operation in v.terminal_goal_submissions:
  if typeof(operation)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_AUTOMATION_TERMINAL_OPERATION")
  x=Utils.validate_exact_fields(operation,["operation_id","checksum","result"]);if not bool(x.success):return x
  var operation_id:=String(operation.operation_id);if not P.path_id(operation_id,"operation/") or operation_ids.has(operation_id) or (not previous.is_empty() and operation_id<previous):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_AUTOMATION_TERMINAL_OPERATIONS")
  if String(operation.checksum).length()!=64 or typeof(operation.result)!=TYPE_DICTIONARY or not bool(Utils.canonicalize(operation.result).get("success",false)):return P.failure("INVALID_CONSTRUCTION_AGENT_AUTOMATION_TERMINAL_OPERATION")
  operation_ids[operation_id]=true;previous=operation_id
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_AUTOMATION_STATE_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
static func _inventory_fingerprints(values: Array) -> Array:
 var result: Array = []
 for value in values:
  result.append(Utils.payload_hash(value))
 result.sort()
 return result
static func _recipe_checksums(values: Array) -> Array:
 var result: Array = []
 for value in values:
  result.append(String(value.get("checksum", "")))
 result.sort()
 return result
