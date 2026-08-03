extends SceneTree
const F=preload("res://tests/construction/fixtures/c20_logistics_economy_fixture.gd")
const Planner=preload("res://scripts/construction/economy/construction_economy_planner.gd")
const Ledger=preload("res://scripts/construction/economy/construction_economy_ledger.gd")
const Warehouses=preload("res://scripts/construction/economy/construction_warehouse_store.gd")
const Coordinator=preload("res://scripts/construction/economy/construction_economy_coordinator.gd")
const Persistence=preload("res://scripts/construction/economy/construction_economy_persistence.gd")
const Contract=preload("res://scripts/construction/economy/construction_contractor_contract.gd")
var assertions:=0;var failures:Array[String]=[]
var ledger;var warehouses;var coordinator;var transfer;var fabrication;var bridge;var verifier
func _init()->void:
 _setup();_test_atomic_failures();_test_procurement_delivery();_test_contractor();_test_salvage();_test_production_chain();_test_persistence();_finish()
func _setup()->void:
 ledger=Ledger.new();_ok(ledger.setup({F.BUYER:500.0,"supplier/c20/local":0.0,"supplier/c20/remote":0.0,"contractor/c20/builders":0.0}),"ledger setup")
 warehouses=Warehouses.new();_ok(warehouses.setup(F.warehouses()),"warehouses setup")
 transfer=F.TransferService.new();fabrication=F.FabricationService.new();bridge=F.AgentBridge.new();verifier=F.ContractVerifier.new()
 coordinator=Coordinator.new();_ok(coordinator.setup(ledger,warehouses,{"transfer":transfer,"fabrication":fabrication,"agent_bridge":bridge,"contract_verifier":verifier}),"coordinator setup")
 _ok(coordinator.publish_offer("operation/c20/publish-local",F.local_offer()),"publish local");_ok(coordinator.publish_offer("operation/c20/publish-remote",F.remote_offer()),"publish remote")

func _test_atomic_failures()->void:
 var planned=Planner.compile(F.goal(),F.bom(),[F.remote_offer()],[F.remote_route()],[],[],{"currency":"CREDITS","current_tick":0});_ok(planned,"atomic plan");var source_order=planned.plan.procurement_orders[0];var offer=F.remote_offer();var order=preload("res://scripts/construction/economy/construction_procurement_order.gd").create("procurement-order/c20/missing",F.BUYER,String(F.goal().goal_id),"bom-line/c20/beam",offer,1,3.0,0.0,0.0,{"kind":"CONTAINER","container_id":"container/c20/site","slot_index":-1},100)
 var missing=coordinator.place_order("operation/c20/place-missing",order,["item/c20/not-present"],0);_err(missing,"CONSTRUCTION_WAREHOUSE_ITEM_UNAVAILABLE","missing stock")
 _assert(is_equal_approx(ledger.get_balance(F.BUYER),500.0),"failed order refunds escrow")
 _assert(warehouses.get_state(F.REMOTE_WAREHOUSE).reserved_quantities.is_empty(),"failed order no stock reservation")
 var first=coordinator.publish_offer("operation/c20/offer-replay",F.remote_offer());_ok(first,"offer replay first")
 var replay=coordinator.publish_offer("operation/c20/offer-replay",F.remote_offer());_ok(replay,"offer replay second");_assert(bool(replay.replay),"offer exact replay")
 var changed=preload("res://scripts/construction/economy/construction_procurement_offer.gd").create("procurement-offer/c20/remote","supplier/c20/remote",F.REMOTE_WAREHOUSE,"wood_beam",{"grade":"structural"},1,10.0,"CREDITS",0,500,"cell/c20/remote","server/c20/remote",{"changed":true});var conflict=coordinator.publish_offer("operation/c20/offer-replay",changed);_err(conflict,"CONSTRUCTION_ECONOMY_OPERATION_ID_CONFLICT","offer operation conflict")

func _test_procurement_delivery()->void:
 var planned=Planner.compile(F.goal(),F.bom(),[F.local_offer(),F.remote_offer()],[F.local_route(),F.remote_route()],F.bids(),[],{"currency":"CREDITS","current_tick":0,"hire_contractor":true});_ok(planned,"plan");var order=planned.plan.procurement_orders[0];var route=planned.plan.routes.filter(func(r):return String(r.route_id)==String(order.metadata.route_id))[0]
 var placed=coordinator.place_order("operation/c20/place",order,[String(F.remote_item().item_instance_id)],0);_ok(placed,"place order");_assert(String(placed.order.status)=="PLACED","order placed");_assert(is_equal_approx(ledger.get_balance(F.BUYER),487.0),"buyer escrow debit");_assert(warehouses.get_state(F.REMOTE_WAREHOUSE).reserved_quantities.has(String(F.remote_item().item_instance_id)),"stock reserved");_assert(String(placed.escrow.status)=="HELD","escrow held");_assert(coordinator.get_generation()>0,"coordinator generation")
 var replay=coordinator.place_order("operation/c20/place",order,[String(F.remote_item().item_instance_id)],0);_ok(replay,"place replay");_assert(bool(replay.replay),"place replay marker");_assert(is_equal_approx(ledger.get_balance(F.BUYER),487.0),"no second debit")
 var dispatched=coordinator.dispatch_order("operation/c20/dispatch",String(order.order_id),route,[String(F.remote_item().item_instance_id)],1);_ok(dispatched,"dispatch");var shipment_id=String(dispatched.shipment.shipment_id);_assert(String(dispatched.order.status)=="IN_TRANSIT","in transit")
 var early=coordinator.advance_shipment("operation/c20/advance-early",shipment_id,2);_err(early,"CONSTRUCTION_SHIPMENT_NOT_READY","early blocked")
 var leg1=coordinator.advance_shipment("operation/c20/advance-leg1",shipment_id,4);_ok(leg1,"leg1");_assert(not bool(leg1.delivered),"not delivered first leg")
 var delivered=coordinator.advance_shipment("operation/c20/advance-final",shipment_id,6);_ok(delivered,"delivery");_assert(bool(delivered.delivered),"delivered marker");_assert(String(delivered.order.status)=="DELIVERED","order delivered");_assert(transfer.calls==1 and bridge.calls==1,"single transfer and bridge");_assert(String(delivered.agent_result.item_projections[0].item_instance_id)==String(F.remote_item().item_instance_id),"item identity preserved");_assert(Dictionary(delivered.agent_result.item_projections[0].relation)==Dictionary(delivered.order.delivery_relation),"delivery relation applied");_assert(int(delivered.shipment.current_leg_index)==2,"all route legs complete");_assert(delivered.shipment.receipts.size()==2,"two leg receipts");_assert(is_equal_approx(ledger.get_balance("supplier/c20/remote"),13.0),"supplier settled landed total")
 var delivery_replay=coordinator.advance_shipment("operation/c20/advance-final",shipment_id,6);_ok(delivery_replay,"delivery replay");_assert(bool(delivery_replay.replay),"delivery replay marker");_assert(transfer.calls==1,"no duplicate transfer")
func _test_contractor()->void:
 var planned=Planner.compile(F.goal(),F.bom(),[F.local_offer()],[F.local_route()],F.bids(),[],{"currency":"CREDITS","current_tick":0,"hire_contractor":true});_ok(planned,"contract plan");var contract=planned.plan.contractor_contracts[0]
 var awarded=coordinator.award_contract("operation/c20/award",contract);_ok(awarded,"award");_assert(is_equal_approx(ledger.get_balance(F.BUYER),467.0),"contract escrow debit")
 var completed=coordinator.complete_contract("operation/c20/contract-complete",String(contract.contract_id),20);_ok(completed,"contract complete");_assert(String(completed.contract.status)=="COMPLETE","contract status");_assert(verifier.calls==1,"contract verified");_assert(is_equal_approx(ledger.get_balance("contractor/c20/builders"),20.0),"contractor paid");_assert(completed.contract.completed_milestone_ids.size()==2,"all milestones completed");var replay=coordinator.complete_contract("operation/c20/contract-complete",String(contract.contract_id),20);_ok(replay,"contract replay");_assert(bool(replay.replay) and verifier.calls==1,"contract no duplicate")
func _test_salvage()->void:
 var listing=F.salvage_listing();_ok(coordinator.publish_salvage("operation/c20/salvage-list",listing),"list salvage")
 var bought=coordinator.buy_salvage("operation/c20/salvage-buy",String(listing.listing_id),F.BUYER,{"kind":"CONTAINER","container_id":"container/c20/site","slot_index":-1},30);_ok(bought,"buy salvage");_assert(String(bought.listing.status)=="SOLD","listing sold");_assert(String(bought.item_projections[0].item_instance_id)==String(F.salvage_item().item_instance_id),"salvage identity");_assert(is_equal_approx(ledger.get_balance("supplier/c20/remote"),20.0),"salvage seller paid");var replay=coordinator.buy_salvage("operation/c20/salvage-buy",String(listing.listing_id),F.BUYER,{"kind":"CONTAINER","container_id":"container/c20/site","slot_index":-1},30);_ok(replay,"salvage replay");_assert(bool(replay.replay),"salvage replay marker")
func _test_production_chain()->void:
 var chain=F.chain();var result=coordinator.execute_chain("operation/c20/chain",chain);_ok(result,"chain execute");_assert(fabrication.calls==2,"two fabrication cells");_assert(result.outputs.size()==2,"two chain outputs");_assert(String(result.outputs[0].item_instance_id)=="item/c20/chain-ingot","ingot identity");_assert(String(result.outputs[1].item_instance_id)=="item/c20/chain-beam","beam identity");_assert(String(result.outputs[0].definition_id)=="iron_ingot","ingot definition");_assert(String(result.outputs[1].definition_id)=="steel_beam","beam definition");_assert(result.receipts.size()==2,"chain receipts")
 var replay=coordinator.execute_chain("operation/c20/chain",chain);_ok(replay,"chain replay");_assert(bool(replay.replay) and fabrication.calls==2,"chain no duplicate")
func _test_persistence()->void:
 var storage=F.MemoryStore.new();_ok(Persistence.save(storage,coordinator,ledger,warehouses),"save")
 var ledger2=Ledger.new();ledger2.setup({});var warehouses2=Warehouses.new();warehouses2.setup([]);var coordinator2=Coordinator.new();_ok(coordinator2.setup(ledger2,warehouses2,{"transfer":transfer,"fabrication":fabrication,"agent_bridge":bridge,"contract_verifier":verifier}),"coordinator2")
 _ok(Persistence.load(storage,coordinator2,ledger2,warehouses2),"load");_assert(coordinator2.export_state()==coordinator.export_state(),"coordinator roundtrip");_assert(ledger2.export_state()==ledger.export_state(),"ledger roundtrip");_assert(warehouses2.export_state()==warehouses.export_state(),"warehouse roundtrip");_assert(is_equal_approx(ledger2.get_balance(F.BUYER),ledger.get_balance(F.BUYER)),"balance restored");_assert(coordinator2.get_generation()==coordinator.get_generation(),"coordinator generation restored")
 var order_id="procurement-order/c19:reusable-table/000";_assert(String(coordinator2.get_order(order_id).status)=="DELIVERED","delivered order restored")
func _ok(r:Dictionary,m:String)->void:_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r:Dictionary,c:String,m:String)->void:_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v:bool,m:String)->void:assertions+=1;if not v:failures.append(m)
func _finish()->void:
 if failures.is_empty():print("C20 logistics economy integration: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C20 logistics economy integration: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
