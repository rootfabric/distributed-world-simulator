extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Bid=preload("res://scripts/construction/economy/construction_contractor_bid.gd")
const SCHEMA="planet_simulator.construction_contractor_contract.v1"
const FIELDS:Array[String]=["schema","contract_id","goal_id","buyer_agent_id","bid","status","start_tick","due_tick","escrow_id","milestones","completed_milestone_ids","metadata","checksum"]
const STATUSES=["AWARDED","ACTIVE","COMPLETE","CANCELLED","FAILED"]
const MILESTONE_FIELDS:Array[String]=["milestone_id","sequence","amount","required_outcome"]
static func milestone(id:String,sequence:int,amount:float,outcome:String)->Dictionary:return {"milestone_id":id,"sequence":sequence,"amount":P.metric(amount),"required_outcome":outcome}
static func create(id:String,goal_id:String,buyer:String,bid:Dictionary,status:String,start:int,due:int,escrow:String,milestones:Array,completed:Array=[],metadata:Dictionary={})->Dictionary:
	var rows=milestones.duplicate(true);rows.sort_custom(func(a,b):return int(a.get("sequence",0))<int(b.get("sequence",0)))
	var done=P.sorted_strings(completed);var v={"schema":SCHEMA,"contract_id":id,"goal_id":goal_id,"buyer_agent_id":buyer,"bid":bid.duplicate(true),"status":status,"start_tick":start,"due_tick":due,"escrow_id":escrow,"milestones":rows,"completed_milestone_ids":done,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_CONTRACTOR_CONTRACT_SCHEMA");if not bool(x.success):return x
	for spec in [["contract_id","contract/"],["goal_id","agent-goal/"],["buyer_agent_id","agent/"],["escrow_id","escrow/"]]:
		if not P.path_id(String(v.get(spec[0],"")),String(spec[1])):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_CONTRACT_IDENTITY")
	if typeof(v.get("bid"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_CONTRACT_BID")
	x=Bid.validate(v.bid);if not bool(x.success):return x
	if not STATUSES.has(String(v.get("status",""))):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_CONTRACT_STATUS")
	for f in ["start_tick","due_tick"]:
		if not Utils.is_json_integer(v.get(f)) or int(v[f])<0:return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_CONTRACT_TICK")
	if int(v.due_tick)<int(v.start_tick):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_CONTRACT_WINDOW")
	if typeof(v.get("milestones"))!=TYPE_ARRAY or v.milestones.is_empty():return P.failure("CONSTRUCTION_CONTRACTOR_MILESTONES_REQUIRED")
	var prev=-1;var ids:Array=[];var total=0.0
	for m in v.milestones:
		x=Utils.validate_exact_fields(m,MILESTONE_FIELDS);if not bool(x.success):return x
		if not P.path_id(String(m.get("milestone_id","")),"milestone/") or not Utils.is_json_integer(m.get("sequence")) or int(m.sequence)<=prev or not U.money(m.get("amount")) or not P.upper_kind(String(m.get("required_outcome",""))):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_MILESTONE")
		prev=int(m.sequence);ids.append(String(m.milestone_id));total+=float(m.amount)
	if not is_equal_approx(P.metric(total),P.metric(float(v.bid.fixed_price))):return P.failure("CONSTRUCTION_CONTRACTOR_MILESTONE_TOTAL_MISMATCH")
	if not U.sorted_unique_strings(v.get("completed_milestone_ids")):
		return P.failure("NON_CANONICAL_CONSTRUCTION_CONTRACTOR_COMPLETIONS")
	for id in v.completed_milestone_ids:
		if not ids.has(String(id)):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_COMPLETION")
	if not U.canonical_dict(v.get("metadata")) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_CONTRACTOR_CONTRACT_CHECKSUM_MISMATCH")
	return P.success()
