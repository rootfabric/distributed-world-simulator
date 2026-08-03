extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_contractor_bid.v1"
const FIELDS:Array[String]=["schema","bid_id","contractor_id","goal_kinds","capabilities","labor_rate","fixed_price","currency","earliest_start_tick","duration_ticks","maximum_parallel_jobs","quality_score","metadata","checksum"]
static func create(id:String,contractor:String,goal_kinds:Array,capabilities:Array,labor_rate:float,fixed_price:float,currency:String,earliest:int,duration:int,max_jobs:int,quality:float,metadata:Dictionary={})->Dictionary:
	var v={"schema":SCHEMA,"bid_id":id,"contractor_id":contractor,"goal_kinds":P.sorted_strings(goal_kinds),"capabilities":P.sorted_strings(capabilities),"labor_rate":P.metric(labor_rate),"fixed_price":P.metric(fixed_price),"currency":currency,"earliest_start_tick":earliest,"duration_ticks":duration,"maximum_parallel_jobs":max_jobs,"quality_score":P.metric(quality),"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_CONTRACTOR_BID_SCHEMA");if not bool(x.success):return x
	if not P.path_id(String(v.get("bid_id","")),"contractor-bid/") or not P.path_id(String(v.get("contractor_id","")),"contractor/"):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_BID_IDENTITY")
	if not U.sorted_unique_strings(v.get("goal_kinds")) or not U.sorted_unique_strings(v.get("capabilities")):return P.failure("NON_CANONICAL_CONSTRUCTION_CONTRACTOR_BID_REQUIREMENTS")
	for raw in v.goal_kinds:
		if not P.upper_kind(String(raw)):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_BID_GOAL_KIND")
	for raw in v.capabilities:
		if not P.upper_kind(String(raw)):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_BID_CAPABILITY")
	if not U.money(v.get("labor_rate")) or not U.money(v.get("fixed_price")) or not P.upper_kind(String(v.get("currency",""))):return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_BID_PRICE")
	for f in ["earliest_start_tick","duration_ticks","maximum_parallel_jobs"]:
		if not Utils.is_json_integer(v.get(f)) or int(v[f])<0:return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_BID_SCHEDULE")
	if int(v.duration_ticks)<1 or int(v.maximum_parallel_jobs)<1 or not U.money(v.get("quality_score")) or float(v.quality_score)>1.0:return P.failure("INVALID_CONSTRUCTION_CONTRACTOR_BID_LIMIT")
	if not U.canonical_dict(v.get("metadata")) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_CONTRACTOR_BID_CHECKSUM_MISMATCH")
	return P.success()
