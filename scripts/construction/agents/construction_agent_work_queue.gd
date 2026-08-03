extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Work=preload("res://scripts/construction/agents/construction_agent_work_item.gd")
const SCHEMA="planet_simulator.construction_agent_work_queue.v1"
const FIELDS:Array[String]=["schema","generation","work_items","checksum"]
var _items:Dictionary={};var _generation:=0
func setup()->Dictionary:_items.clear();_generation=0;return P.success()
func enqueue(work_item:Dictionary)->Dictionary:
 var x=Work.validate(work_item);if not bool(x.success):return x
 var id=String(work_item.work_item_id)
 if _items.has(id):
  if String(_items[id].checksum)==String(work_item.checksum):return P.success({"replay":true,"work_item":get_work_item(id)})
  return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_ID_CONFLICT")
 _items[id]=work_item.duplicate(true);_generation+=1;return P.success({"replay":false,"work_item":get_work_item(id)})
func get_work_item(id:String)->Dictionary:return Dictionary(_items.get(id,{})).duplicate(true)
func list_work_items()->Array:var a:Array=_items.values();a.sort_custom(func(x,y):var px=int(x.plan.bom.get("priority",0));return String(x.work_item_id)<String(y.work_item_id));return a.duplicate(true)
func record_step_result(id:String,step:Dictionary,result:Dictionary)->Dictionary:
 if not _items.has(id):return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_NOT_FOUND")
 var item:Dictionary=_items[id]
 var index:=int(item.current_step_index)
 if index>=item.plan.steps.size():return P.success({"replay":true,"work_item":item.duplicate(true)})
 var expected:Dictionary=item.plan.steps[index]
 if String(expected.checksum)!=String(step.get("checksum","")):return P.failure("CONSTRUCTION_AGENT_WORK_STEP_PRECONDITION_MISMATCH")
 if not bool(result.get("success",false)):
  var status="BLOCKED" if String(result.get("status","RETRYABLE"))=="RETRYABLE" else "FAILED"
  var updated=Work.with_updates(item,{"status":status,"blocked_reason":String(result.get("error_code","UNKNOWN")),"generation":int(item.generation)+1});_items[id]=updated;_generation+=1;return P.success({"work_item":updated.duplicate(true),"step_result":result.duplicate(true)})
 var completed:Array=item.completed_step_ids.duplicate();completed.append(String(step.step_id));var receipts:Array=item.receipts.duplicate(true);receipts.append({"step_id":String(step.step_id),"step_checksum":String(step.checksum),"result":result.duplicate(true)})
 var next_index=index+1;var status="COMPLETE" if next_index>=item.plan.steps.size() else "RUNNING"
 var updated=Work.with_updates(item,{"status":status,"current_step_index":next_index,"completed_step_ids":completed,"blocked_reason":"","receipts":receipts,"generation":int(item.generation)+1});_items[id]=updated;_generation+=1;return P.success({"work_item":updated.duplicate(true),"step_result":result.duplicate(true)})
func resume(id:String)->Dictionary:
 if not _items.has(id):return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_NOT_FOUND")
 var item:Dictionary=_items[id]
 if String(item.status)!="BLOCKED":return P.success({"replay":true,"work_item":item.duplicate(true)})
 var updated=Work.with_updates(item,{"status":"RUNNING","blocked_reason":"","generation":int(item.generation)+1});_items[id]=updated;_generation+=1;return P.success({"replay":false,"work_item":updated.duplicate(true)})
func get_generation()->int:return _generation
func to_dict()->Dictionary:var v={"schema":SCHEMA,"generation":_generation,"work_items":list_work_items(),"checksum":""};v.checksum=compute_checksum(v);return v
func load_dict(v:Dictionary)->Dictionary:
 var x=validate_state(v);if not bool(x.success):return x
 _items.clear();for row in v.work_items:_items[String(row.work_item_id)]=row.duplicate(true)
 _generation=int(v.generation);return P.success()
static func validate_state(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA or not Utils.is_json_integer(v.get("generation")) or int(v.generation)<0 or typeof(v.get("work_items"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_WORK_QUEUE_STATE")
 var prev:="";var seen:={}
 for row in v.work_items:
  x=Work.validate(row);if not bool(x.success):return x
  var id=String(row.work_item_id);if seen.has(id) or (not prev.is_empty() and id<prev):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_WORK_QUEUE")
  seen[id]=true;prev=id
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_WORK_QUEUE_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
