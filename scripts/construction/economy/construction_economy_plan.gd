extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Order=preload("res://scripts/construction/economy/construction_procurement_order.gd")
const Route=preload("res://scripts/construction/economy/construction_logistics_route.gd")
const Contract=preload("res://scripts/construction/economy/construction_contractor_contract.gd")
const Chain=preload("res://scripts/construction/economy/construction_production_chain.gd")
const SCHEMA="planet_simulator.construction_economy_plan.v1"
const FIELDS:Array[String]=["schema","plan_id","goal_id","procurement_orders","routes","contractor_contracts","production_chains","salvage_listing_ids","goods_cost","transport_cost","labor_cost","energy_cost","total_cost","currency","deadline_tick","blocked_reasons","metadata","checksum"]
static func create(id:String,goal_id:String,orders:Array,routes:Array,contracts:Array,chains:Array,salvage_ids:Array,currency:String,deadline:int,blocked:Array=[],metadata:Dictionary={})->Dictionary:
	var goods=0.0;var transport=0.0;var labor=0.0;var energy=0.0
	for o in orders:goods+=float(o.get("goods_total",0.0));transport+=float(o.get("transport_cost",0.0));labor+=float(o.get("labor_cost",0.0));energy+=float(o.get("energy_cost",0.0))
	for c in contracts:labor+=float(c.get("bid",{}).get("fixed_price",0.0))
	for ch in chains:goods+=float(ch.get("material_cost",0.0));transport+=float(ch.get("transport_cost",0.0));labor+=float(ch.get("labor_cost",0.0));energy+=float(ch.get("energy_cost",0.0))
	var v={"schema":SCHEMA,"plan_id":id,"goal_id":goal_id,"procurement_orders":U.sorted_rows(orders,"order_id"),"routes":U.sorted_rows(routes,"route_id"),"contractor_contracts":U.sorted_rows(contracts,"contract_id"),"production_chains":U.sorted_rows(chains,"chain_id"),"salvage_listing_ids":P.sorted_strings(salvage_ids),"goods_cost":P.metric(goods),"transport_cost":P.metric(transport),"labor_cost":P.metric(labor),"energy_cost":P.metric(energy),"total_cost":P.metric(goods+transport+labor+energy),"currency":currency,"deadline_tick":deadline,"blocked_reasons":P.sorted_strings(blocked),"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_ECONOMY_PLAN_SCHEMA");if not bool(x.success):return x
	if not P.path_id(String(v.get("plan_id","")),"economy-plan/") or not P.path_id(String(v.get("goal_id","")),"agent-goal/"):return P.failure("INVALID_CONSTRUCTION_ECONOMY_PLAN_IDENTITY")
	var goods=0.0;var transport=0.0;var labor=0.0;var energy=0.0
	var specs=[["procurement_orders",Order,"order_id"],["routes",Route,"route_id"],["contractor_contracts",Contract,"contract_id"],["production_chains",Chain,"chain_id"]]
	for spec in specs:
		var rows=v.get(spec[0]);if typeof(rows)!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_ECONOMY_PLAN_COLLECTION")
		var previous=""
		for row in rows:
			x=spec[1].validate(row);if not bool(x.success):return x
			var id=String(row.get(spec[2],""));if not previous.is_empty() and id<=previous:return P.failure("NON_CANONICAL_CONSTRUCTION_ECONOMY_PLAN_COLLECTION")
			previous=id
	for o in v.procurement_orders:goods+=float(o.goods_total);transport+=float(o.transport_cost);labor+=float(o.labor_cost);energy+=float(o.energy_cost)
	for c in v.contractor_contracts:labor+=float(c.bid.fixed_price)
	for ch in v.production_chains:goods+=float(ch.material_cost);transport+=float(ch.transport_cost);labor+=float(ch.labor_cost);energy+=float(ch.energy_cost)
	if not is_equal_approx(P.metric(goods),float(v.goods_cost)) or not is_equal_approx(P.metric(transport),float(v.transport_cost)) or not is_equal_approx(P.metric(labor),float(v.labor_cost)) or not is_equal_approx(P.metric(energy),float(v.energy_cost)) or not is_equal_approx(P.metric(goods+transport+labor+energy),float(v.total_cost)):return P.failure("CONSTRUCTION_ECONOMY_PLAN_COST_MISMATCH")
	if not P.upper_kind(String(v.currency)) or not Utils.is_json_integer(v.deadline_tick) or int(v.deadline_tick)<0:return P.failure("INVALID_CONSTRUCTION_ECONOMY_PLAN_TERMS")
	if not U.sorted_unique_strings(v.salvage_listing_ids) or not U.sorted_unique_strings(v.blocked_reasons):return P.failure("NON_CANONICAL_CONSTRUCTION_ECONOMY_PLAN_LIST")
	if not U.canonical_dict(v.metadata) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_ECONOMY_PLAN_CHECKSUM_MISMATCH")
	return P.success()
