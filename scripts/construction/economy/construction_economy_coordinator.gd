extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Offer=preload("res://scripts/construction/economy/construction_procurement_offer.gd")
const Order=preload("res://scripts/construction/economy/construction_procurement_order.gd")
const Route=preload("res://scripts/construction/economy/construction_logistics_route.gd")
const Shipment=preload("res://scripts/construction/economy/construction_shipment.gd")
const Contract=preload("res://scripts/construction/economy/construction_contractor_contract.gd")
const Listing=preload("res://scripts/construction/economy/construction_salvage_listing.gd")
const Chain=preload("res://scripts/construction/economy/construction_production_chain.gd")
var _ledger;var _warehouses;var _services:Dictionary={};var _offers:Dictionary={};var _orders:Dictionary={};var _shipments:Dictionary={};var _contracts:Dictionary={};var _listings:Dictionary={};var _chains:Dictionary={};var _operations:Dictionary={};var _generation:=0
func setup(ledger,warehouses,services:Dictionary)->Dictionary:
	if ledger==null or not ledger.has_method("hold") or warehouses==null or not warehouses.has_method("reserve"):return P.failure("CONSTRUCTION_ECONOMY_STORES_REQUIRED")
	for name in ["transfer","fabrication","agent_bridge","contract_verifier"]:
		if not services.has(name) or services[name]==null:return P.failure("CONSTRUCTION_ECONOMY_SERVICE_REQUIRED",{"service":name})
	_ledger=ledger;_warehouses=warehouses;_services=services.duplicate();return P.success()
func publish_offer(operation_id:String,offer:Dictionary)->Dictionary:
	var x=Offer.validate(offer);if not bool(x.success):return x
	var payload={"kind":"PUBLISH_OFFER","offer":offer};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	var id=String(offer.offer_id)
	if _offers.has(id) and String(_offers[id].checksum)!=String(offer.checksum):return _store_failure(operation_id,payload,"CONSTRUCTION_PROCUREMENT_OFFER_IMMUTABLE_CONFLICT")
	_offers[id]=offer.duplicate(true);_generation+=1;return _store(operation_id,payload,P.success({"offer":offer.duplicate(true),"generation":_generation,"replay":false}))
func place_order(operation_id:String,order:Dictionary,item_ids:Array,current_tick:int)->Dictionary:
	var x=Order.validate(order);if not bool(x.success):return x
	var payload={"kind":"PLACE_ORDER","order":order,"item_ids":P.sorted_strings(item_ids),"current_tick":current_tick};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if String(order.status)!="DRAFT" or not _offers.has(String(order.offer_id)):return _store_failure(operation_id,payload,"CONSTRUCTION_PROCUREMENT_ORDER_NOT_PLACEABLE")
	var offer:Dictionary=_offers[String(order.offer_id)];if String(offer.checksum)!=String(order.offer_checksum) or current_tick<int(offer.earliest_tick) or current_tick>int(offer.expiry_tick):return _store_failure(operation_id,payload,"CONSTRUCTION_PROCUREMENT_OFFER_PRECONDITION_MISMATCH")
	if item_ids.size()!=int(order.quantity):return _store_failure(operation_id,payload,"CONSTRUCTION_PROCUREMENT_ITEM_BINDING_MISMATCH")
	var escrow="escrow/order/%s"%String(order.order_id).trim_prefix("procurement-order/")
	var held=_ledger.hold("%s/escrow"%operation_id,escrow,String(order.buyer_agent_id),String(offer.supplier_id),float(order.total_price),String(order.currency),{"order_id":String(order.order_id)})
	if not bool(held.success):return _store_failure(operation_id,payload,String(held.error_code))
	var reserved=_warehouses.reserve("%s/stock"%operation_id,String(offer.warehouse_id),item_ids)
	if not bool(reserved.success):
		_ledger.refund("%s/refund"%operation_id,escrow)
		return _store_failure(operation_id,payload,String(reserved.error_code))
	var placed=Order.with_status(order,"PLACED",escrow,"");_orders[String(placed.order_id)]=placed;_generation+=1
	return _store(operation_id,payload,P.success({"order":placed.duplicate(true),"escrow":held.escrow,"warehouse":reserved.warehouse,"generation":_generation,"replay":false}))
func dispatch_order(operation_id:String,order_id:String,route:Dictionary,item_ids:Array,current_tick:int)->Dictionary:
	var x=Route.validate(route);if not bool(x.success):return x
	var payload={"kind":"DISPATCH_ORDER","order_id":order_id,"route":route,"item_ids":P.sorted_strings(item_ids),"current_tick":current_tick};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _orders.has(order_id) or String(_orders[order_id].status)!="PLACED":return _store_failure(operation_id,payload,"CONSTRUCTION_PROCUREMENT_ORDER_NOT_DISPATCHABLE")
	var order:Dictionary=_orders[order_id];var offer:Dictionary=_offers[String(order.offer_id)]
	if String(route.source_warehouse_id)!=String(offer.warehouse_id):return _store_failure(operation_id,payload,"CONSTRUCTION_LOGISTICS_ROUTE_WAREHOUSE_MISMATCH")
	var dispatched=_warehouses.dispatch("%s/warehouse"%operation_id,String(offer.warehouse_id),item_ids);if not bool(dispatched.success):return _store_failure(operation_id,payload,String(dispatched.error_code))
	var shipment_id="shipment/%s"%order_id.trim_prefix("procurement-order/");var shipment=Shipment.create(shipment_id,order_id,route,Array(dispatched.item_projections),float(order.quantity),"IN_TRANSIT",0,current_tick,current_tick+int(route.legs[0].travel_ticks),-1,[],{"goal_id":String(order.goal_id),"bom_line_id":String(order.bom_line_id)})
	x=Shipment.validate(shipment);if not bool(x.success):return _store_failure(operation_id,payload,String(x.error_code))
	order=Order.with_status(order,"IN_TRANSIT",String(order.escrow_id),shipment_id);_orders[order_id]=order;_shipments[shipment_id]=shipment;_generation+=1
	return _store(operation_id,payload,P.success({"order":order.duplicate(true),"shipment":shipment.duplicate(true),"generation":_generation,"replay":false}))
func advance_shipment(operation_id:String,shipment_id:String,current_tick:int)->Dictionary:
	var payload={"kind":"ADVANCE_SHIPMENT","shipment_id":shipment_id,"current_tick":current_tick};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _shipments.has(shipment_id):return _store_failure(operation_id,payload,"CONSTRUCTION_SHIPMENT_NOT_FOUND")
	var shipment:Dictionary=_shipments[shipment_id].duplicate(true);if String(shipment.status)=="DELIVERED":return _store(operation_id,payload,P.success({"shipment":shipment,"delivered":true,"replay":true}))
	if current_tick<int(shipment.available_tick):return _store_failure(operation_id,payload,"CONSTRUCTION_SHIPMENT_NOT_READY")
	var next=int(shipment.current_leg_index)+1;var receipts:Array=shipment.receipts.duplicate(true);receipts.append({"leg_id":String(shipment.route.legs[int(shipment.current_leg_index)].leg_id),"completed_tick":current_tick})
	if next<shipment.route.legs.size():
		shipment.current_leg_index=next;shipment.available_tick=current_tick+int(shipment.route.legs[next].travel_ticks);shipment.receipts=receipts;shipment.checksum=U.checksum(shipment);_shipments[shipment_id]=shipment;_generation+=1
		return _store(operation_id,payload,P.success({"shipment":shipment.duplicate(true),"delivered":false,"generation":_generation,"replay":false}))
	var order:Dictionary=_orders[String(shipment.order_id)];var transfer=_services.transfer.transfer({"shipment_id":shipment_id,"item_projections":shipment.item_projections,"target_relation":order.delivery_relation,"route_checksum":String(shipment.route.checksum)},"%s/transfer"%operation_id)
	if not bool(transfer.success):return _store_failure(operation_id,payload,String(transfer.error_code))
	var settled=_ledger.settle("%s/settle"%operation_id,String(order.escrow_id));if not bool(settled.success):return _store_failure(operation_id,payload,String(settled.error_code))
	var fulfilled=_services.agent_bridge.fulfill(String(order.goal_id),String(order.bom_line_id),Array(transfer.item_projections),"%s/agent"%operation_id);if not bool(fulfilled.success):return _store_failure(operation_id,payload,String(fulfilled.error_code))
	shipment.current_leg_index=next;shipment.status="DELIVERED";shipment.delivery_tick=current_tick;shipment.available_tick=current_tick;shipment.receipts=receipts;shipment.checksum=U.checksum(shipment);order=Order.with_status(order,"DELIVERED",String(order.escrow_id),shipment_id);_shipments[shipment_id]=shipment;_orders[String(order.order_id)]=order;_generation+=1
	return _store(operation_id,payload,P.success({"shipment":shipment.duplicate(true),"order":order.duplicate(true),"settlement":settled.escrow,"agent_result":fulfilled,"delivered":true,"generation":_generation,"replay":false}))
func award_contract(operation_id:String,contract:Dictionary)->Dictionary:
	var x=Contract.validate(contract);if not bool(x.success):return x
	var payload={"kind":"AWARD_CONTRACT","contract":contract};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	var hold=_ledger.hold("%s/escrow"%operation_id,String(contract.escrow_id),String(contract.buyer_agent_id),String(contract.bid.contractor_id),float(contract.bid.fixed_price),String(contract.bid.currency),{"contract_id":String(contract.contract_id)})
	if not bool(hold.success):return _store_failure(operation_id,payload,String(hold.error_code))
	_contracts[String(contract.contract_id)]=contract.duplicate(true);_generation+=1;return _store(operation_id,payload,P.success({"contract":contract.duplicate(true),"escrow":hold.escrow,"generation":_generation,"replay":false}))
func complete_contract(operation_id:String,contract_id:String,current_tick:int)->Dictionary:
	var payload={"kind":"COMPLETE_CONTRACT","contract_id":contract_id,"current_tick":current_tick};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _contracts.has(contract_id):return _store_failure(operation_id,payload,"CONSTRUCTION_CONTRACT_NOT_FOUND")
	var contract:Dictionary=_contracts[contract_id];var verified=_services.contract_verifier.verify(contract,"%s/verify"%operation_id);if not bool(verified.success):return _store_failure(operation_id,payload,String(verified.error_code))
	var settled=_ledger.settle("%s/settle"%operation_id,String(contract.escrow_id));if not bool(settled.success):return _store_failure(operation_id,payload,String(settled.error_code))
	var done:Array=[];for m in contract.milestones:done.append(String(m.milestone_id));contract=Contract.create(String(contract.contract_id),String(contract.goal_id),String(contract.buyer_agent_id),contract.bid,"COMPLETE",int(contract.start_tick),int(contract.due_tick),String(contract.escrow_id),contract.milestones,done,contract.metadata);_contracts[contract_id]=contract;_generation+=1
	return _store(operation_id,payload,P.success({"contract":contract.duplicate(true),"settlement":settled.escrow,"generation":_generation,"replay":false}))
func publish_salvage(operation_id:String,listing:Dictionary)->Dictionary:
	var x=Listing.validate(listing);if not bool(x.success):return x
	var payload={"kind":"PUBLISH_SALVAGE","listing":listing};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	_listings[String(listing.listing_id)]=listing.duplicate(true);_generation+=1;return _store(operation_id,payload,P.success({"listing":listing.duplicate(true),"generation":_generation,"replay":false}))
func buy_salvage(operation_id:String,listing_id:String,buyer_id:String,delivery_relation:Dictionary,current_tick:int)->Dictionary:
	var payload={"kind":"BUY_SALVAGE","listing_id":listing_id,"buyer_id":buyer_id,"delivery_relation":delivery_relation,"current_tick":current_tick};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	if not _listings.has(listing_id):return _store_failure(operation_id,payload,"CONSTRUCTION_SALVAGE_LISTING_NOT_FOUND")
	var listing:Dictionary=_listings[listing_id];if String(listing.status)!="OPEN" or current_tick>int(listing.expiry_tick):return _store_failure(operation_id,payload,"CONSTRUCTION_SALVAGE_LISTING_NOT_OPEN")
	var amount=float(listing.ask_price) if String(listing.sale_kind)=="FIXED" else maxf(float(listing.minimum_bid),float(listing.highest_bid));var escrow="escrow/salvage/%s"%listing_id.trim_prefix("salvage-listing/");var held=_ledger.hold("%s/escrow"%operation_id,escrow,buyer_id,String(listing.seller_id),amount,String(listing.currency),{"listing_id":listing_id});if not bool(held.success):return _store_failure(operation_id,payload,String(held.error_code))
	var transfer=_services.transfer.transfer({"shipment_id":"shipment/salvage/%s"%listing_id.trim_prefix("salvage-listing/"),"item_projections":[listing.item_projection],"target_relation":delivery_relation,"route_checksum":"salvage-direct"},"%s/transfer"%operation_id);if not bool(transfer.success):_ledger.refund("%s/refund"%operation_id,escrow);return _store_failure(operation_id,payload,String(transfer.error_code))
	var settled=_ledger.settle("%s/settle"%operation_id,escrow);listing.status="SOLD";listing.highest_bid=amount;listing.highest_bidder_id=buyer_id;listing.checksum=U.checksum(listing);_listings[listing_id]=listing;_generation+=1
	return _store(operation_id,payload,P.success({"listing":listing.duplicate(true),"item_projections":transfer.item_projections,"settlement":settled.escrow,"generation":_generation,"replay":false}))
func execute_chain(operation_id:String,chain:Dictionary)->Dictionary:
	var x=Chain.validate(chain);if not bool(x.success):return x
	var payload={"kind":"EXECUTE_CHAIN","chain":chain};var replay=_replay(operation_id,payload);if not replay.is_empty():return replay
	var outputs:Array=[];var receipts:Array=[]
	for stage in chain.stages:
		var result=_services.fabrication.fabricate(stage,"%s/%s"%[operation_id,String(stage.stage_id).trim_prefix("production-stage/")]);if not bool(result.success):return _store_failure(operation_id,payload,String(result.error_code))
		for projection in result.get("output_projections",[]):outputs.append(projection.duplicate(true))
		receipts.append({"stage_id":String(stage.stage_id),"result_checksum":Utils.payload_hash(result)})
	_chains[String(chain.chain_id)]={"chain":chain.duplicate(true),"status":"COMPLETE","receipts":receipts,"outputs":outputs};_generation+=1
	return _store(operation_id,payload,P.success({"chain_id":String(chain.chain_id),"outputs":outputs,"receipts":receipts,"generation":_generation,"replay":false}))
func get_order(id:String)->Dictionary:return Dictionary(_orders.get(id,{})).duplicate(true)
func get_shipment(id:String)->Dictionary:return Dictionary(_shipments.get(id,{})).duplicate(true)
func get_contract(id:String)->Dictionary:return Dictionary(_contracts.get(id,{})).duplicate(true)
func get_listing(id:String)->Dictionary:return Dictionary(_listings.get(id,{})).duplicate(true)
func get_generation()->int:return _generation
func export_state()->Dictionary:
	var v={"offers":_offers.duplicate(true),"orders":_orders.duplicate(true),"shipments":_shipments.duplicate(true),"contracts":_contracts.duplicate(true),"listings":_listings.duplicate(true),"chains":_chains.duplicate(true),"operations":_operations.duplicate(true),"generation":_generation,"checksum":""};v.checksum=U.checksum(v);return v
func load_state(v:Dictionary)->Dictionary:
	for f in ["offers","orders","shipments","contracts","listings","chains","operations"]:
		if typeof(v.get(f))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_ECONOMY_COORDINATOR_STATE")
	if not Utils.is_json_integer(v.get("generation")) or String(v.get("checksum",""))!=U.checksum(v):return P.failure("CONSTRUCTION_ECONOMY_COORDINATOR_STATE_CHECKSUM_MISMATCH")
	_offers=Dictionary(v.offers).duplicate(true);_orders=Dictionary(v.orders).duplicate(true);_shipments=Dictionary(v.shipments).duplicate(true);_contracts=Dictionary(v.contracts).duplicate(true);_listings=Dictionary(v.listings).duplicate(true);_chains=Dictionary(v.chains).duplicate(true);_operations=Dictionary(v.operations).duplicate(true);_generation=int(v.generation);return P.success()
func _replay(id:String,payload:Dictionary)->Dictionary:
	if not _operations.has(id):return {}
	var stored:Dictionary=_operations[id];if String(stored.payload_checksum)!=Utils.payload_hash(payload):return P.failure("CONSTRUCTION_ECONOMY_OPERATION_ID_CONFLICT")
	var r=Dictionary(stored.result).duplicate(true);r.replay=true;return r
func _store(id:String,payload:Dictionary,result:Dictionary)->Dictionary:_operations[id]={"payload_checksum":Utils.payload_hash(payload),"result":result.duplicate(true)};return result
func _store_failure(id:String,payload:Dictionary,code:String)->Dictionary:return _store(id,payload,P.failure(code,{"replay":false}))
