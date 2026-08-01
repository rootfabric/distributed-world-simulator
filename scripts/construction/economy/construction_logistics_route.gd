extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_logistics_route.v1"
const FIELDS:Array[String]=["schema","route_id","source_warehouse_id","target_relation","legs","total_distance_km","total_travel_ticks","cost_per_unit","carrier_ids","metadata","checksum"]
const LEG_FIELDS:Array[String]=["leg_id","from_cell_id","to_cell_id","carrier_id","distance_km","travel_ticks","cost_per_unit","capacity_units"]
static func leg(id:String,from_cell:String,to_cell:String,carrier:String,distance:float,ticks:int,cost:float,capacity:float)->Dictionary:return {"leg_id":id,"from_cell_id":from_cell,"to_cell_id":to_cell,"carrier_id":carrier,"distance_km":P.metric(distance),"travel_ticks":ticks,"cost_per_unit":P.metric(cost),"capacity_units":P.metric(capacity)}
static func create(route_id:String,warehouse_id:String,target_relation:Dictionary,legs:Array,metadata:Dictionary={})->Dictionary:
	var distance=0.0;var ticks=0;var cost=0.0;var carriers:Array=[]
	for raw in legs:
		distance+=float(raw.get("distance_km",0.0));ticks+=int(raw.get("travel_ticks",0));cost+=float(raw.get("cost_per_unit",0.0));carriers.append(String(raw.get("carrier_id","")))
	carriers.sort();var unique:Array=[]
	for c in carriers:
		if not unique.has(c):unique.append(c)
	var v={"schema":SCHEMA,"route_id":route_id,"source_warehouse_id":warehouse_id,"target_relation":target_relation.duplicate(true),"legs":legs.duplicate(true),"total_distance_km":P.metric(distance),"total_travel_ticks":ticks,"cost_per_unit":P.metric(cost),"carrier_ids":unique,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_LOGISTICS_ROUTE_SCHEMA");if not bool(x.success):return x
	if not P.path_id(String(v.get("route_id","")),"logistics-route/") or not P.path_id(String(v.get("source_warehouse_id","")),"warehouse/"):return P.failure("INVALID_CONSTRUCTION_LOGISTICS_ROUTE_IDENTITY")
	if not U.canonical_dict(v.get("target_relation")) or typeof(v.get("legs"))!=TYPE_ARRAY or v.legs.is_empty():return P.failure("INVALID_CONSTRUCTION_LOGISTICS_ROUTE_PAYLOAD")
	var distance=0.0;var ticks=0;var cost=0.0;var carriers:Array=[];var previous=""
	for raw in v.legs:
		if typeof(raw)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_LOGISTICS_ROUTE_LEG")
		x=Utils.validate_exact_fields(raw,LEG_FIELDS);if not bool(x.success):return x
		var id=String(raw.get("leg_id",""));if not P.path_id(id,"route-leg/") or (not previous.is_empty() and id<=previous):return P.failure("NON_CANONICAL_CONSTRUCTION_LOGISTICS_ROUTE_LEGS")
		for f in ["from_cell_id","to_cell_id"]:
			if not P.path_id(String(raw.get(f,"")),"cell/"):return P.failure("INVALID_CONSTRUCTION_LOGISTICS_ROUTE_CELL")
		if String(raw.from_cell_id)==String(raw.to_cell_id) or not P.path_id(String(raw.get("carrier_id","")),"carrier/"):return P.failure("INVALID_CONSTRUCTION_LOGISTICS_ROUTE_ENDPOINT")
		if not U.positive(raw.get("distance_km")) or not Utils.is_json_integer(raw.get("travel_ticks")) or int(raw.travel_ticks)<1 or not U.money(raw.get("cost_per_unit")) or not U.positive(raw.get("capacity_units")):return P.failure("INVALID_CONSTRUCTION_LOGISTICS_ROUTE_METRIC")
		distance+=float(raw.distance_km);ticks+=int(raw.travel_ticks);cost+=float(raw.cost_per_unit);carriers.append(String(raw.carrier_id));previous=id
	carriers.sort();var unique:Array=[];for c in carriers:if not unique.has(c):unique.append(c)
	if not is_equal_approx(P.metric(distance),float(v.total_distance_km)) or ticks!=int(v.total_travel_ticks) or not is_equal_approx(P.metric(cost),float(v.cost_per_unit)) or unique!=v.carrier_ids:return P.failure("CONSTRUCTION_LOGISTICS_ROUTE_SUMMARY_MISMATCH")
	if not U.canonical_dict(v.get("metadata")) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_LOGISTICS_ROUTE_CHECKSUM_MISMATCH")
	return P.success()
