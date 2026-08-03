extends RefCounted
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Offer=preload("res://scripts/construction/economy/construction_procurement_offer.gd")
const Order=preload("res://scripts/construction/economy/construction_procurement_order.gd")
const Route=preload("res://scripts/construction/economy/construction_logistics_route.gd")
const Bid=preload("res://scripts/construction/economy/construction_contractor_bid.gd")
const Contract=preload("res://scripts/construction/economy/construction_contractor_contract.gd")
const Plan=preload("res://scripts/construction/economy/construction_economy_plan.gd")
static func compile(goal:Dictionary,bom:Dictionary,offers:Array,routes:Array,bids:Array,chains:Array,options:Dictionary={})->Dictionary:
	var goal_id=String(goal.get("goal_id",""));var currency=String(options.get("currency","CREDITS"));var deadline=int(goal.get("deadline_tick",options.get("deadline_tick",100000)));if deadline<0:deadline=int(options.get("deadline_tick",100000))
	var offer_rows:Array=[];for o in offers:
		var x=Offer.validate(o);if not bool(x.success):return x
		offer_rows.append(o.duplicate(true))
	var route_map:Dictionary={};for r in routes:
		var x=Route.validate(r);if not bool(x.success):return x
		route_map[String(r.source_warehouse_id)]=r.duplicate(true)
	var selected_orders:Array=[];var selected_routes:Array=[];var blocked:Array=[];var key=goal_id.trim_prefix("agent-goal/").replace("/",":")
	for line in bom.get("lines",[]):
		if String(line.get("acquisition_mode",""))!="PROCURE":continue
		var best:Dictionary={};var best_route:Dictionary={};var best_cost=INF
		for o in offer_rows:
			if String(o.definition_id)!=String(line.get("definition_id","")) or int(o.quantity_available)<int(line.get("missing_quantity",0)) or String(o.currency)!=currency:continue
			if not route_map.has(String(o.warehouse_id)):continue
			var r:Dictionary=route_map[String(o.warehouse_id)];var arrival=maxi(int(o.earliest_tick),int(options.get("current_tick",0)))+int(r.total_travel_ticks)
			if arrival>deadline or int(o.expiry_tick)<int(options.get("current_tick",0)):continue
			var q=maxi(1,int(line.get("missing_quantity",1)));var landed=float(o.unit_price)*q+float(r.cost_per_unit)*q
			if landed<best_cost or (is_equal_approx(landed,best_cost) and String(o.offer_id)<String(best.get("offer_id","~"))):best=o;best_route=r;best_cost=landed
		if best.is_empty():blocked.append("NO_FEASIBLE_OFFER:%s"%String(line.get("line_id","")));continue
		var order=Order.create("procurement-order/%s/%03d"%[key,selected_orders.size()],String(goal.get("agent_id","")),goal_id,String(line.get("line_id","")),best,maxi(1,int(line.get("missing_quantity",1))),float(best_route.cost_per_unit)*maxi(1,int(line.get("missing_quantity",1))),0.0,0.0,Dictionary(goal.get("placement_relation",{})),deadline,"DRAFT","","",{"route_id":String(best_route.route_id)})
		selected_orders.append(order);if not selected_routes.any(func(x):return String(x.route_id)==String(best_route.route_id)):selected_routes.append(best_route)
	var contracts:Array=[]
	if bool(options.get("hire_contractor",false)):
		var required=Array(goal.get("required_agent_capabilities",[]));var best_bid:Dictionary={};var best_score=INF
		for b in bids:
			var x=Bid.validate(b);if not bool(x.success):return x
			if not b.goal_kinds.has(String(goal.get("goal_kind",""))):continue
			var capable=true;for cap in required:if not b.capabilities.has(cap):capable=false
			if not capable or int(b.earliest_start_tick)+int(b.duration_ticks)>deadline:continue
			var score=float(b.fixed_price)-float(b.quality_score)*0.001
			if score<best_score:best_bid=b;best_score=score
		if best_bid.is_empty():blocked.append("NO_FEASIBLE_CONTRACTOR")
		else:
			var amount=float(best_bid.fixed_price);var milestones=[Contract.milestone("milestone/%s/accept"%key,0,P.metric(amount*0.25),"MATERIALS_READY"),Contract.milestone("milestone/%s/complete"%key,1,P.metric(amount-P.metric(amount*0.25)),"GOAL_COMPLETE")]
			contracts.append(Contract.create("contract/%s"%key,goal_id,String(goal.agent_id),best_bid,"AWARDED",int(best_bid.earliest_start_tick),int(best_bid.earliest_start_tick)+int(best_bid.duration_ticks),"escrow/contract/%s"%key,milestones,[],{"planner":"C20"}))
	var plan=Plan.create("economy-plan/%s"%key,goal_id,selected_orders,selected_routes,contracts,chains,[],currency,deadline,blocked,{"source_bom_checksum":String(bom.get("checksum",""))})
	var checked=Plan.validate(plan);if not bool(checked.success):return checked
	var budget=float(goal.get("budget_limit",0.0));if budget>0.0 and float(plan.total_cost)>budget:return P.failure("CONSTRUCTION_ECONOMY_BUDGET_EXCEEDED",{"plan":plan,"budget":budget})
	return P.success({"plan":plan,"blocked":not blocked.is_empty()})
