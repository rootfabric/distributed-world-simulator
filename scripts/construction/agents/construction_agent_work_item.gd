extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Plan=preload("res://scripts/construction/agents/construction_agent_plan.gd")
const SCHEMA="planet_simulator.construction_agent_work_item.v1"
const FIELDS:Array[String]=["schema","work_item_id","agent_id","goal_id","plan","status","current_step_index","completed_step_ids","blocked_reason","receipts","generation","checksum"]
const STATUSES=["QUEUED","RUNNING","BLOCKED","COMPLETE","FAILED","CANCELLED"]
static func create(work_item_id:String,agent_id:String,plan:Dictionary)->Dictionary:
 var v={"schema":SCHEMA,"work_item_id":work_item_id,"agent_id":agent_id,"goal_id":String(plan.get("goal_id","")),"plan":plan.duplicate(true),"status":"QUEUED" if String(plan.get("status",""))=="PLANNED" else "BLOCKED","current_step_index":0,"completed_step_ids":[],"blocked_reason":"" if String(plan.get("status",""))=="PLANNED" else "PLAN_BLOCKED","receipts":[],"generation":0,"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not P.path_id(String(v.get("work_item_id","")),"agent-work/") or not P.path_id(String(v.get("agent_id","")),"agent/") or not P.path_id(String(v.get("goal_id","")),"agent-goal/"):return P.failure("INVALID_CONSTRUCTION_AGENT_WORK_ITEM_IDENTITY")
 if typeof(v.get("plan"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_WORK_ITEM_PLAN")
 x=Plan.validate(v.plan);if not bool(x.success):return x
 if String(v.plan.goal_id)!=String(v.goal_id):return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_PLAN_MISMATCH")
 if not STATUSES.has(String(v.get("status",""))) or not Utils.is_json_integer(v.get("current_step_index")) or int(v.current_step_index)<0 or int(v.current_step_index)>Array(v.plan.steps).size():return P.failure("INVALID_CONSTRUCTION_AGENT_WORK_ITEM_PROGRESS")
 if not Utils.is_json_integer(v.get("generation")) or int(v.generation)<0 or typeof(v.get("blocked_reason"))!=TYPE_STRING:return P.failure("INVALID_CONSTRUCTION_AGENT_WORK_ITEM_STATE")
 var expected:Array=[];for i in range(int(v.current_step_index)):expected.append(String(v.plan.steps[i].step_id))
 if Array(v.get("completed_step_ids",[]))!=expected:return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_COMPLETION_MISMATCH")
 if typeof(v.get("receipts"))!=TYPE_ARRAY or v.receipts.size()!=expected.size():return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_RECEIPT_MISMATCH")
 for i in range(v.receipts.size()):
  var r=v.receipts[i];if typeof(r)!=TYPE_DICTIONARY or String(r.get("step_id",""))!=expected[i] or String(r.get("step_checksum",""))!=String(v.plan.steps[i].checksum) or typeof(r.get("result"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_WORK_ITEM_RECEIPT")
 if String(v.status)=="COMPLETE" and int(v.current_step_index)!=v.plan.steps.size():return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_COMPLETE_TOO_EARLY")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_CHECKSUM_MISMATCH")
 return P.success()
static func with_updates(v: Dictionary, updates: Dictionary) -> Dictionary:
 var n := v.duplicate(true)
 for k in updates:
  n[k] = updates[k]
 n.checksum = compute_checksum(n)
 return n
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
