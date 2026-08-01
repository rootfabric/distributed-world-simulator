extends SceneTree

const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const F=preload("res://tests/construction/fixtures/c19_agent_automation_fixture.gd")
const Goal=preload("res://scripts/construction/agents/construction_agent_goal.gd")
const Line=preload("res://scripts/construction/agents/construction_agent_bom_line.gd")
const Bom=preload("res://scripts/construction/agents/construction_agent_bom.gd")
const Step=preload("res://scripts/construction/agents/construction_agent_step.gd")
const Plan=preload("res://scripts/construction/agents/construction_agent_plan.gd")
const Reservation=preload("res://scripts/construction/agents/construction_agent_reservation.gd")
const ReservationStore=preload("res://scripts/construction/agents/construction_agent_reservation_store.gd")
const Work=preload("res://scripts/construction/agents/construction_agent_work_item.gd")
const Queue=preload("res://scripts/construction/agents/construction_agent_work_queue.gd")
const Planner=preload("res://scripts/construction/agents/construction_agent_planner.gd")
const Factory=preload("res://scripts/construction/agents/construction_agent_command_factory.gd")
const Api=preload("res://scripts/construction/agents/construction_agent_automation_api.gd")
var assertions:=0;var failures:Array[String]=[]
func _init()->void:
 _test_goal();_test_planner_and_bom();_test_repair_and_salvage_plans();_test_reservation_contracts();_test_work_queue_contracts();_test_command_factory();_test_api_state();_finish()
func _test_goal()->void:
 var goal=F.goal();_ok(Goal.validate(goal),"goal");_assert(String(goal.checksum).length()==64,"goal checksum");_assert(goal.required_outcomes==["SUPPORT_SURFACE"],"goal outcomes");_assert(goal.required_agent_capabilities==["FASTEN","INSPECT","OPERATE_FABRICATION_CELL"],"goal capabilities sorted")
 var extra=goal.duplicate(true);extra["unexpected"]=true;_err(Goal.validate(extra),"UNEXPECTED_FIELD","goal extra")
 var stale=goal.duplicate(true);stale.definition_checksum="0".repeat(64);stale.checksum=Goal.compute_checksum(stale);_ok(Goal.validate(stale),"goal permits pinned checksum")
 var bad=goal.duplicate(true);bad.execution_context.authority_epoch=0;bad.checksum=Goal.compute_checksum(bad);_err(Goal.validate(bad),"INVALID_CONSTRUCTION_AGENT_EXECUTION_CONTEXT_COUNTER","authority epoch")
 bad=goal.duplicate(true);bad.required_agent_capabilities=["INSPECT","FASTEN","OPERATE_FABRICATION_CELL"];bad.checksum=Goal.compute_checksum(bad);_err(Goal.validate(bad),"NON_CANONICAL_CONSTRUCTION_AGENT_GOAL_LIST","capability order")
 bad=goal.duplicate(true);bad.budget_limit=-1;bad.checksum=Goal.compute_checksum(bad);_err(Goal.validate(bad),"INVALID_CONSTRUCTION_AGENT_GOAL_BUDGET","negative budget")
func _test_planner_and_bom()->void:
 var result=Planner.compile(F.goal(),F.definition(),F.inventory(),[F.recipe()],{"machine_construct_ids":["construct/fabrication/cell-a"]});_ok(result,"planner");var bom:Dictionary=result.bom;var plan:Dictionary=result.plan
 _ok(Bom.validate(bom),"bom");_ok(Plan.validate(plan),"plan");_assert(bool(bom.ready_for_execution),"bom ready");_assert(bom.lines.size()>=7,"bom lines");_assert(plan.steps.size()>=7,"plan steps");_assert(String(plan.build_plan.checksum).length()==64,"real build plan");_assert(String(plan.instantiation.checksum).length()==64,"real instantiation")
 var fabricated:=0
 for line in bom.lines:
  _ok(Line.validate(line),"line")
  if String(line.acquisition_mode)=="FABRICATE":fabricated+=1;_assert(line.fabrication_bindings.size()==1,"fabrication binding")
 _assert(fabricated==1,"one missing beam fabricated")
 for i in range(plan.steps.size()):
  _ok(Step.validate(plan.steps[i]),"step");_assert(int(plan.steps[i].sequence_index)==i,"step index")
 _assert(String(plan.steps[0].kind)==Step.RESERVE,"reserve first");_assert(String(plan.steps[-1].kind)==Step.VERIFY,"verify last")
 var tamper=plan.duplicate(true);tamper.steps[1].payload["recipe"]["work_units"]=999;tamper.steps[1].checksum=Step.compute_checksum(tamper.steps[1]);tamper.checksum=Plan.compute_checksum(tamper);_err(Plan.validate(tamper),"CONSTRUCTION_FABRICATION_RECIPE_CHECKSUM_MISMATCH","nested recipe tamper")
 var no_recipe=Planner.compile(F.goal(),F.definition(),F.inventory(),[],{"allow_procurement":false});_ok(no_recipe,"blocked planner");_assert(bool(no_recipe.blocked) and String(no_recipe.plan.status)=="BLOCKED","blocked plan")
 var budget=Planner.compile(F.goal(1.0),F.definition(),F.inventory(),[F.recipe()]);_err(budget,"CONSTRUCTION_AGENT_GOAL_BUDGET_EXCEEDED","budget")
 var mismatch=F.goal();mismatch.definition_checksum="f".repeat(64);mismatch.checksum=Goal.compute_checksum(mismatch);_err(Planner.compile(mismatch,F.definition(),F.inventory(),[F.recipe()]),"CONSTRUCTION_AGENT_GOAL_DEFINITION_PRECONDITION_MISMATCH","definition precondition")

func _test_repair_and_salvage_plans()->void:
 var repair=Planner.compile(F.repair_goal(),{},F.repair_inventory(),[],{"repair_plan":F.repair_plan(),"allow_procurement":false});_ok(repair,"repair planner");_assert(not bool(repair.blocked),"repair executable");_assert(String(repair.plan.goal_kind)==Goal.REPAIR_CONSTRUCT,"repair goal kind");_assert(repair.plan.build_plan.is_empty() and repair.plan.instantiation.is_empty(),"repair has no build artifacts");_assert(repair.bom.lines.size()==6,"repair exact item BOM")
 var repair_step:Dictionary={}
 for step in repair.plan.steps:
  if String(step.kind)==Step.REPAIR:repair_step=step;break
 _assert(not repair_step.is_empty(),"repair step generated");_ok(Step.validate(repair_step),"repair step validates")
 var repair_missing=Planner.compile(F.repair_goal(),{},F.repair_inventory().slice(0,5),[],{"repair_plan":F.repair_plan(),"allow_procurement":false});_ok(repair_missing,"repair missing planner");_assert(bool(repair_missing.blocked),"repair missing blocked")
 var salvage=Planner.compile(F.salvage_goal(),{},[],[],{"damage_request":F.damage_request()});_ok(salvage,"salvage planner");_assert(not bool(salvage.blocked),"salvage executable");_assert(salvage.bom.lines.is_empty(),"salvage empty BOM valid");_assert(String(salvage.plan.goal_kind)==Goal.SALVAGE_CONSTRUCT,"salvage goal kind")
 var salvage_step:Dictionary={}
 for step in salvage.plan.steps:
  if String(step.kind)==Step.SALVAGE:salvage_step=step;break
 _assert(not salvage_step.is_empty(),"salvage step generated");_ok(Step.validate(salvage_step),"salvage step validates")
 var repair_command=Factory.repair(F.repair_goal(),repair_step);_ok(repair_command,"repair command");_assert(String(repair_command.command.command.action)=="APPLY_REPAIR","repair action")
 var salvage_command=Factory.salvage(F.salvage_goal(),salvage_step);_ok(salvage_command,"salvage command");_assert(String(salvage_command.command.command.action)=="APPLY_DAMAGE","salvage action")

func _test_reservation_contracts()->void:
 var reservation=Reservation.create("agent-reservation/test/0","operation/test/reserve","agent/test","agent-goal/test","TOOL","tool/test",1.0,true,1,10);_ok(Reservation.validate(reservation),"reservation")
 var bad=reservation.duplicate(true);bad.quantity=0;bad.checksum=Reservation.compute_checksum(bad);_err(Reservation.validate(bad),"INVALID_CONSTRUCTION_AGENT_RESERVATION_QUANTITY","reservation quantity")
 var store=ReservationStore.new();_ok(store.setup({"item/a":2.0,"tool/a":1.0}),"reservation store")
 var requests=[{"resource_kind":"ITEM","resource_id":"item/a","quantity":2.0,"exclusive":false},{"resource_kind":"TOOL","resource_id":"tool/a","quantity":1.0,"exclusive":true}]
 var acquired=store.acquire_batch("operation/reserve/a","agent/a","agent-goal/a",requests,0,10);_ok(acquired,"acquire");_assert(acquired.reservations.size()==2,"reservation count");var generation=store.get_generation()
 var replay=store.acquire_batch("operation/reserve/a","agent/a","agent-goal/a",requests,0,10);_ok(replay,"acquire replay");_assert(bool(replay.replay) and store.get_generation()==generation,"reservation replay generation")
 _err(store.acquire_batch("operation/reserve/a","agent/a","agent-goal/a",[{"resource_kind":"ITEM","resource_id":"item/a","quantity":1.0,"exclusive":false}],0,10),"CONSTRUCTION_AGENT_RESERVATION_OPERATION_ID_CONFLICT","reservation conflict")
 _err(store.acquire_batch("operation/reserve/b","agent/b","agent-goal/b",[{"resource_kind":"TOOL","resource_id":"tool/a","quantity":1.0,"exclusive":true}],1,11),"CONSTRUCTION_AGENT_RESOURCE_CONTENTION","exclusive contention")
 _ok(store.expire(10),"expire");_ok(store.acquire_batch("operation/reserve/b-after-expiry","agent/b","agent-goal/b",[{"resource_kind":"TOOL","resource_id":"tool/a","quantity":1.0,"exclusive":true}],10,20),"acquire after expiry")
 var state=store.to_dict();_ok(ReservationStore.validate_state(state),"reservation state");var tamper=state.duplicate(true);tamper.capacities[0].quantity=99;_err(ReservationStore.validate_state(tamper),"CONSTRUCTION_AGENT_RESERVATION_STORE_CHECKSUM_MISMATCH","reservation state tamper")
func _test_work_queue_contracts()->void:
 var planned=Planner.compile(F.goal(),F.definition(),F.inventory(),[F.recipe()]);var work=Work.create("agent-work/test",F.AGENT,planned.plan);_ok(Work.validate(work),"work")
 var queue=Queue.new();queue.setup();_ok(queue.enqueue(work),"enqueue");var replay=queue.enqueue(work);_ok(replay,"enqueue replay");_assert(bool(replay.replay),"queue replay")
 var first=planned.plan.steps[0];var recorded=queue.record_step_result("agent-work/test",first,{"success":true,"error_code":"","message":"","receipt":"ok"});_ok(recorded,"record step");_assert(int(recorded.work_item.current_step_index)==1,"step advanced")
 var bad=recorded.work_item.duplicate(true);bad.completed_step_ids=[];bad.checksum=Work.compute_checksum(bad);_err(Work.validate(bad),"CONSTRUCTION_AGENT_WORK_ITEM_COMPLETION_MISMATCH","completion tamper")
 var state=queue.to_dict();_ok(Queue.validate_state(state),"queue state")
func _test_command_factory()->void:
 var planned=Planner.compile(F.goal(),F.definition(),F.inventory(),[F.recipe()]);var build_step:Dictionary={}
 for step in planned.plan.steps:
  if String(step.kind)==Step.BUILD:build_step=step;break
 var result=Factory.build_stage(F.goal(),build_step);_ok(result,"command factory");_assert(String(result.command.expected_owner_server_id)==F.OWNER,"routed owner");_assert(String(result.command.command.client_id)=="client/c19/builder-alpha","inner client");_assert(String(result.command.command.payload.operation_id)==String(build_step.operation_id),"operation id")
func _test_api_state()->void:
 var queue=Queue.new();queue.setup();var reservations=ReservationStore.new();reservations.setup(F.capacities());var api=Api.new();var dummy=RefCounted.new()
 var state={"schema":Api.SCHEMA,"generation":0,"goals":[],"plans":[],"queue":queue.to_dict(),"reservations":reservations.to_dict(),"terminal_goal_submissions":[],"checksum":""};state.checksum=Api.compute_checksum(state);_ok(Api.validate_state(state),"api state")
 var tamper=state.duplicate(true);tamper.generation=1;_err(Api.validate_state(tamper),"CONSTRUCTION_AGENT_AUTOMATION_STATE_CHECKSUM_MISMATCH","api state tamper")
 _assert(not Utils.canonical_json(state).is_empty(),"api state json")
func _ok(r:Dictionary,m:String)->void:_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r:Dictionary,c:String,m:String)->void:_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v:bool,m:String)->void:assertions+=1;if not v:failures.append(m)
func _finish()->void:
 if failures.is_empty():print("C19 agent automation contracts: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C19 agent automation contracts: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
