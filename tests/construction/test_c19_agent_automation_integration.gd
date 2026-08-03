extends SceneTree

const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const F=preload("res://tests/construction/fixtures/c19_agent_automation_fixture.gd")
const Planner=preload("res://scripts/construction/agents/construction_agent_planner.gd")
const Queue=preload("res://scripts/construction/agents/construction_agent_work_queue.gd")
const Reservations=preload("res://scripts/construction/agents/construction_agent_reservation_store.gd")
const Executor=preload("res://scripts/construction/agents/construction_agent_executor.gd")
const Api=preload("res://scripts/construction/agents/construction_agent_automation_api.gd")
const Persistence=preload("res://scripts/construction/agents/construction_agent_persistence.gd")
var assertions:=0;var failures:Array[String]=[]
var queue;var reservations;var executor;var api;var fabrication;var logistics;var registry;var verifier;var authority:Dictionary
func _init()->void:
 _setup();_test_end_to_end();_test_repair_and_salvage_execution();_test_multi_agent_contention();_test_persistence_and_replay();_finish()
func _setup()->void:
 queue=Queue.new();queue.setup();reservations=Reservations.new();reservations.setup(F.capacities());authority=F.authority_cluster();fabrication=F.FakeFabrication.new();logistics=F.FakeLogistics.new();registry=F.FakeBuildRegistry.new();verifier=F.FakeVerifier.new(authority.owner_gateway)
 executor=Executor.new();_ok(executor.setup(queue,reservations,{"fabrication":fabrication,"logistics":logistics,"build_registry":registry,"authority_cluster":authority.cluster,"verifier":verifier}),"executor setup")
 api=Api.new();_ok(api.setup(F.PlannerAdapter.new(),executor,queue,reservations),"api setup")
func _test_end_to_end()->void:
 var submitted=api.submit_goal("operation/c19/submit",F.goal(),F.definition(),F.inventory(),[F.recipe()],{"machine_construct_ids":["construct/fabrication/cell-a"]});_ok(submitted,"submit goal");_assert(not bool(submitted.blocked),"goal executable");_assert(String(submitted.work_item.status)=="QUEUED","work queued");_assert(submitted.bom.lines.size()>=7,"bom generated");_assert(submitted.plan.steps.size()>=7,"automation steps generated")
 var submit_generation=api.get_queue().get_generation();var replay=api.submit_goal("operation/c19/submit",F.goal(),F.definition(),F.inventory(),[F.recipe()],{"machine_construct_ids":["construct/fabrication/cell-a"]});_ok(replay,"submit replay");_assert(bool(replay.replay) and api.get_queue().get_generation()==submit_generation,"submit exact replay")
 var work_id=String(submitted.work_item.work_item_id);var result=api.run_until_blocked(work_id,0,32);_ok(result,"run complete");_assert(bool(result.complete),"automation complete");var item=api.get_queue().get_work_item(work_id);_assert(String(item.status)=="COMPLETE","work complete");_assert(int(item.current_step_index)==item.plan.steps.size(),"all steps complete")
 _assert(fabrication.calls==1,"one fabrication job");_assert(fabrication.outputs.size()==1,"one fabricated output");_assert(logistics.calls==1,"one delivery");_assert(registry.calls==1,"one build plan registration");_assert(authority.owner_gateway.commit_count==3,"three authoritative build stages");_assert(authority.entry_gateway.commit_count==0,"entry server no local commit");_assert(verifier.calls==1,"one outcome verification")
 var exported=authority.owner_gateway.export_construct_state(F.TARGET);_ok(exported,"owner state");_assert(int(exported.state.revision)==3,"owner revision");_assert(exported.state.payload.commands.size()==3,"three routed commands")
 var repeat=api.execute_next(work_id,100);_ok(repeat,"complete replay");_assert(bool(repeat.replay) and bool(repeat.complete),"complete replay marker");_assert(fabrication.calls==1 and authority.owner_gateway.commit_count==3,"complete replay no side effects")

func _test_repair_and_salvage_execution()->void:
 var target=String(F.repair_goal().target_construct_id)
 var repair_authority=F.authority_cluster_for(target);var repair_queue=Queue.new();repair_queue.setup();var repair_reservations=Reservations.new();repair_reservations.setup(F.repair_capacities());var repair_verifier=F.FakeVerifierAlways.new();var repair_executor=Executor.new();_ok(repair_executor.setup(repair_queue,repair_reservations,{"fabrication":F.FakeFabrication.new(),"logistics":F.FakeLogistics.new(),"build_registry":F.FakeBuildRegistry.new(),"authority_cluster":repair_authority.cluster,"verifier":repair_verifier}),"repair executor")
 var repair_api=Api.new();_ok(repair_api.setup(F.PlannerAdapter.new(),repair_executor,repair_queue,repair_reservations),"repair api");var submitted=repair_api.submit_goal("operation/c19/submit-repair",F.repair_goal(),{},F.repair_inventory(),[],{"repair_plan":F.repair_plan(),"allow_procurement":false});_ok(submitted,"submit repair");var completed=repair_api.run_until_blocked(String(submitted.work_item.work_item_id),0,16);_ok(completed,"repair execution");_assert(bool(completed.complete),"repair complete");_assert(repair_authority.owner_gateway.commit_count==1,"one repair authority commit");_assert(repair_verifier.calls==1,"repair verified")
 var salvage_authority=F.authority_cluster_for(target);var salvage_queue=Queue.new();salvage_queue.setup();var salvage_reservations=Reservations.new();salvage_reservations.setup({F.TOOL:1.0,F.WORKSPACE:1.0});var salvage_verifier=F.FakeVerifierAlways.new();var salvage_executor=Executor.new();_ok(salvage_executor.setup(salvage_queue,salvage_reservations,{"fabrication":F.FakeFabrication.new(),"logistics":F.FakeLogistics.new(),"build_registry":F.FakeBuildRegistry.new(),"authority_cluster":salvage_authority.cluster,"verifier":salvage_verifier}),"salvage executor")
 var salvage_api=Api.new();_ok(salage_setup(salvage_api,salvage_executor,salvage_queue,salvage_reservations),"salvage api");var salvage_submitted=salvage_api.submit_goal("operation/c19/submit-salvage",F.salvage_goal(),{},[],[],{"damage_request":F.damage_request()});_ok(salvage_submitted,"submit salvage");var salvage_completed=salvage_api.run_until_blocked(String(salvage_submitted.work_item.work_item_id),100,16);_ok(salvage_completed,"salvage execution");_assert(bool(salvage_completed.complete),"salvage complete");_assert(salvage_authority.owner_gateway.commit_count==1,"one salvage authority commit");_assert(salvage_verifier.calls==1,"salvage verified")
func salage_setup(api_value,executor_value,queue_value,reservation_value)->Dictionary:
 return api_value.setup(F.PlannerAdapter.new(),executor_value,queue_value,reservation_value)

func _test_multi_agent_contention()->void:
 var request=[{"resource_kind":"TOOL","resource_id":F.TOOL,"quantity":1.0,"exclusive":true},{"resource_kind":"WORKSPACE","resource_id":F.WORKSPACE,"quantity":1.0,"exclusive":true}]
 var blocked=reservations.acquire_batch("operation/c19/contender","agent/c19/builder-beta","agent-goal/c19/other",request,10,50);_err(blocked,"CONSTRUCTION_AGENT_RESOURCE_CONTENTION","contender blocked")
 _ok(reservations.expire(200),"expire primary reservations");var acquired=reservations.acquire_batch("operation/c19/contender-after-expiry","agent/c19/builder-beta","agent-goal/c19/other",request,200,250);_ok(acquired,"contender after expiry");_assert(acquired.reservations.size()==2,"contender atomic batch")
 var conflict=reservations.acquire_batch("operation/c19/contender-2","agent/c19/builder-gamma","agent-goal/c19/third",[{"resource_kind":"ITEM","resource_id":"definition-stock/raw_lumber","quantity":999.0,"exclusive":false},{"resource_kind":"TOOL","resource_id":F.TOOL,"quantity":1.0,"exclusive":true}],201,260);_err(conflict,"CONSTRUCTION_AGENT_RESOURCE_CAPACITY_EXCEEDED","atomic capacity failure");_assert(reservations.list_reservations().filter(func(r):return String(r.operation_id)=="operation/c19/contender-2").is_empty(),"no partial reservation")
func _test_persistence_and_replay()->void:
 var storage=F.MemoryStore.new();_ok(Persistence.save(storage,api),"save api");var state=api.export_state();_ok(Api.validate_state(state),"export api")
 var queue2=Queue.new();queue2.setup();var reservations2=Reservations.new();reservations2.setup({});var executor2=Executor.new();_ok(executor2.setup(queue2,reservations2,{"fabrication":fabrication,"logistics":logistics,"build_registry":registry,"authority_cluster":authority.cluster,"verifier":verifier}),"executor2")
 var api2=Api.new();_ok(api2.setup(F.PlannerAdapter.new(),executor2,queue2,reservations2),"api2");_ok(Persistence.load(storage,api2),"load api")
 _assert(api2.export_state()==state,"state roundtrip")
 var replay=api2.submit_goal("operation/c19/submit",F.goal(),F.definition(),F.inventory(),[F.recipe()],{"machine_construct_ids":["construct/fabrication/cell-a"]});_ok(replay,"submission replay after restart");_assert(bool(replay.replay),"restart replay marker")
 var work_id=String(replay.work_item.work_item_id);var done=api2.execute_next(work_id,300);_ok(done,"completed work after restart");_assert(bool(done.replay),"completed replay after restart")
 var tampered=state.duplicate(true);tampered.generation=int(tampered.generation)+1;_err(Api.validate_state(tampered),"CONSTRUCTION_AGENT_AUTOMATION_STATE_CHECKSUM_MISMATCH","state tamper")
func _ok(r:Dictionary,m:String)->void:_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r:Dictionary,c:String,m:String)->void:_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v:bool,m:String)->void:assertions+=1;if not v:failures.append(m)
func _finish()->void:
 if failures.is_empty():print("C19 agent automation integration: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C19 agent automation integration: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
