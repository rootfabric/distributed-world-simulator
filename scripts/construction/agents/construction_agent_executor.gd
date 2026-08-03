extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Work=preload("res://scripts/construction/agents/construction_agent_work_item.gd")
const Step=preload("res://scripts/construction/agents/construction_agent_step.gd")
const Factory=preload("res://scripts/construction/agents/construction_agent_command_factory.gd")
var _queue;var _reservations;var _services:Dictionary={}
func setup(queue,reservation_store,services:Dictionary)->Dictionary:
 if queue==null or not queue.has_method("record_step_result") or reservation_store==null or not reservation_store.has_method("acquire_batch"):return P.failure("CONSTRUCTION_AGENT_EXECUTOR_STORES_REQUIRED")
 for name in ["fabrication","logistics","build_registry","authority_cluster","verifier"]:
  if not services.has(name) or services[name]==null:return P.failure("CONSTRUCTION_AGENT_EXECUTOR_SERVICE_REQUIRED",{"service":name})
 _queue=queue;_reservations=reservation_store;_services=services.duplicate();return P.success()
func execute_next(work_item_id:String,goal:Dictionary,current_tick:int)->Dictionary:
 var item:Dictionary=_queue.get_work_item(work_item_id);if item.is_empty():return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_NOT_FOUND")
 var checked=Work.validate(item);if not bool(checked.success):return checked
 if String(item.status)=="COMPLETE":return P.success({"replay":true,"complete":true,"work_item":item})
 if String(item.status) in ["FAILED","CANCELLED"]:return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_TERMINAL")
 if String(item.status)=="BLOCKED":return P.failure("CONSTRUCTION_AGENT_WORK_ITEM_BLOCKED",{"reason":String(item.blocked_reason),"status":"RETRYABLE"})
 var step:Dictionary=item.plan.steps[int(item.current_step_index)];var result:Dictionary
 match String(step.kind):
  Step.RESERVE:
   result=_reservations.acquire_batch(String(step.operation_id),String(goal.agent_id),String(goal.goal_id),Array(step.payload.requests),current_tick,current_tick+int(step.payload.lease_ticks))
  Step.FABRICATE:
   result=_services.fabrication.fabricate(Dictionary(step.payload),String(step.operation_id))
  Step.DELIVER:
   result=_services.logistics.deliver(Dictionary(step.payload),String(step.operation_id))
  Step.REGISTER:
   result=_services.build_registry.register_plan(Dictionary(step.payload.build_plan),Dictionary(step.payload.instantiation),String(step.operation_id))
  Step.BUILD:
   var command_result=Factory.build_stage(goal,step);if not bool(command_result.success):result=command_result
   else:result=_services.authority_cluster.submit(String(goal.execution_context.entry_server_id),Dictionary(command_result.command))
  Step.REPAIR:
   var repair_command = Factory.repair(goal, step)
   if not bool(repair_command.get("success", false)):
    result = repair_command
   else:
    result = _services.authority_cluster.submit(String(goal.execution_context.entry_server_id), Dictionary(repair_command.command))
  Step.SALVAGE:
   var salvage_command = Factory.salvage(goal, step)
   if not bool(salvage_command.get("success", false)):
    result = salvage_command
   else:
    result = _services.authority_cluster.submit(String(goal.execution_context.entry_server_id), Dictionary(salvage_command.command))
  Step.VERIFY:
   result=_services.verifier.verify(Dictionary(step.payload),String(step.operation_id))
  _:
   result=P.failure("UNSUPPORTED_CONSTRUCTION_AGENT_STEP_KIND")
 var recorded=_queue.record_step_result(work_item_id,step,result);if not bool(recorded.success):return recorded
 return P.success({"work_item":recorded.work_item,"step":step,"step_result":result,"complete":String(recorded.work_item.status)=="COMPLETE"}) if bool(result.get("success",false)) else P.failure(String(result.get("error_code","CONSTRUCTION_AGENT_STEP_FAILED")),{"work_item":recorded.work_item,"step":step,"cause":result,"status":String(result.get("status","RETRYABLE"))})
func run_until_blocked(work_item_id:String,goal:Dictionary,current_tick:int,maximum_steps:int=64)->Dictionary:
 var results:Array=[]
 for i in range(maximum_steps):
  var item=_queue.get_work_item(work_item_id)
  if String(item.get("status",""))=="COMPLETE":return P.success({"complete":true,"results":results,"work_item":item})
  var result=execute_next(work_item_id,goal,current_tick+i);results.append(result.duplicate(true))
  if not bool(result.get("success",false)):return P.failure("CONSTRUCTION_AGENT_EXECUTION_BLOCKED",{"cause":result,"results":results,"work_item":_queue.get_work_item(work_item_id),"status":"RETRYABLE"})
 return P.failure("CONSTRUCTION_AGENT_EXECUTION_STEP_LIMIT",{"results":results})
