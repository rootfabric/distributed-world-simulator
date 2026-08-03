extends SceneTree
const F=preload("res://tests/construction/fixtures/c20_logistics_economy_fixture.gd")
const Offer=preload("res://scripts/construction/economy/construction_procurement_offer.gd")
const Order=preload("res://scripts/construction/economy/construction_procurement_order.gd")
const Route=preload("res://scripts/construction/economy/construction_logistics_route.gd")
const Shipment=preload("res://scripts/construction/economy/construction_shipment.gd")
const Warehouse=preload("res://scripts/construction/economy/construction_warehouse_state.gd")
const Bid=preload("res://scripts/construction/economy/construction_contractor_bid.gd")
const Contract=preload("res://scripts/construction/economy/construction_contractor_contract.gd")
const Listing=preload("res://scripts/construction/economy/construction_salvage_listing.gd")
const Chain=preload("res://scripts/construction/economy/construction_production_chain.gd")
const Plan=preload("res://scripts/construction/economy/construction_economy_plan.gd")
const Planner=preload("res://scripts/construction/economy/construction_economy_planner.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
var assertions:=0;var failures:Array[String]=[]
func _init()->void:
 _test_dtos();_test_negative_contracts();_test_planner();_finish()
func _test_dtos()->void:
 var offer=F.remote_offer();_ok(Offer.validate(offer),"offer");_tamper(offer,Offer,"unit_price",99.0,"CONSTRUCTION_PROCUREMENT_OFFER_CHECKSUM_MISMATCH")
 var route=F.remote_route();_ok(Route.validate(route),"route");var route_bad=route.duplicate(true);route_bad.total_travel_ticks=999;_assert(not bool(Route.validate(route_bad).success),"route summary tamper")
 for state in F.warehouses():_ok(Warehouse.validate(state),"warehouse")
 var order=Order.create("procurement-order/c20/test",F.BUYER,String(F.goal().goal_id),"bom-line/c20/beam",offer,1,3.0,0.0,0.0,ProjectionScript.container_relation("container/c20/site"),100);_ok(Order.validate(order),"order");_assert(is_equal_approx(float(order.total_price),13.0),"order total")
 var shipment=Shipment.create("shipment/c20/test",String(order.order_id),route,[F.remote_item()],1.0);_ok(Shipment.validate(shipment),"shipment")
 for bid in F.bids():_ok(Bid.validate(bid),"bid")
 var chosen=F.bids()[0];var milestones=[Contract.milestone("milestone/c20/0",0,5.0,"MATERIALS_READY"),Contract.milestone("milestone/c20/1",1,15.0,"GOAL_COMPLETE")];var contract=Contract.create("contract/c20/test",String(F.goal().goal_id),F.BUYER,chosen,"AWARDED",0,20,"escrow/contract/c20/test",milestones);_ok(Contract.validate(contract),"contract")
 var listing=F.salvage_listing();_ok(Listing.validate(listing),"listing");var bad_listing=listing.duplicate(true);bad_listing.item_projection.item_instance_id="item/c20/other";_assert(not bool(Listing.validate(bad_listing).success),"listing nested tamper")
 var chain=F.chain();_ok(Chain.validate(chain),"chain");_assert(int(chain.total_work_units)==10,"chain work");_assert(is_equal_approx(float(chain.total_cost),20.0),"chain cost")

func _test_negative_contracts()->void:
 var offer=F.remote_offer()
 var unknown=offer.duplicate(true);unknown["unknown_field"]=true;_err(Offer.validate(unknown),"UNEXPECTED_FIELD","offer unknown field")
 var bad_qty=offer.duplicate(true);bad_qty.quantity_available=0;_assert(not bool(Offer.validate(bad_qty).success),"offer zero quantity")
 var bad_currency=offer.duplicate(true);bad_currency.currency="credits";_assert(not bool(Offer.validate(bad_currency).success),"offer currency uppercase")
 var route=F.remote_route();var unsorted=route.duplicate(true);unsorted.legs.reverse();_assert(not bool(Route.validate(unsorted).success),"route leg order")
 var disconnected=route.duplicate(true);disconnected.legs[1].from_cell_id="cell/c20/other";_assert(not bool(Route.validate(disconnected).success),"route endpoint payload changes checksum")
 var state=F.warehouses()[0];var over=state.duplicate(true);over.capacity_units=0.5;_assert(not bool(Warehouse.validate(over).success),"warehouse capacity")
 var bad_reserved=state.duplicate(true);bad_reserved.reserved_quantities={String(F.local_item().item_instance_id):2.0};_assert(not bool(Warehouse.validate(bad_reserved).success),"warehouse over reservation")
 var bid=F.bids()[0];var bad_bid=bid.duplicate(true);bad_bid.quality_score=1.5;_assert(not bool(Bid.validate(bad_bid).success),"bid quality range")
 var milestones=[Contract.milestone("milestone/c20/a",0,10.0,"MATERIALS_READY"),Contract.milestone("milestone/c20/b",1,5.0,"GOAL_COMPLETE")];var bad_contract=Contract.create("contract/c20/bad",String(F.goal().goal_id),F.BUYER,bid,"AWARDED",0,20,"escrow/contract/c20/bad",milestones);_assert(not bool(Contract.validate(bad_contract).success),"contract milestone total")
 var auction=F.salvage_listing();auction.sale_kind="AUCTION";auction.minimum_bid=0.0;_assert(not bool(Listing.validate(auction).success),"auction minimum")
 var chain=F.chain();var forward=chain.duplicate(true);forward.stages[0].depends_on_stage_ids=["production-stage/c20/01-beam"];_assert(not bool(Chain.validate(forward).success),"chain forward dependency")
 var duplicate=chain.duplicate(true);duplicate.stages[1].output_item_ids=["item/c20/chain-ingot"];_assert(not bool(Chain.validate(duplicate).success),"chain duplicate output")

func _test_planner()->void:
 var result=Planner.compile(F.goal(),F.bom(),[F.local_offer(),F.remote_offer()],[F.local_route(),F.remote_route()],F.bids(),[F.chain()],{"currency":"CREDITS","current_tick":0,"hire_contractor":true});_ok(result,"planner");var plan=result.plan;_ok(Plan.validate(plan),"plan");_assert(plan.procurement_orders.size()==1,"one order");_assert(String(plan.procurement_orders[0].offer_id)=="procurement-offer/c20/remote","landed cost selected");_assert(plan.contractor_contracts.size()==1,"one contract");_assert(String(plan.contractor_contracts[0].bid.bid_id)=="contractor-bid/c20/cheap","feasible contractor selected");_assert(float(plan.total_cost)<=100.0,"within budget")
 var no_routes=Planner.compile(F.goal(),F.bom(),[F.remote_offer()],[],[],[],{"currency":"CREDITS","current_tick":0});_ok(no_routes,"blocked planner valid");_assert(bool(no_routes.blocked),"blocked without route")
func _tamper(value:Dictionary,script,field:String,replacement,expected:String)->void:
 var t=value.duplicate(true);t[field]=replacement;var r=script.validate(t);_err(r,expected,"tamper %s"%field)
func _ok(r:Dictionary,m:String)->void:_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r:Dictionary,c:String,m:String)->void:_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v:bool,m:String)->void:assertions+=1;if not v:failures.append(m)
func _finish()->void:
 if failures.is_empty():print("C20 logistics economy contracts: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C20 logistics economy contracts: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
