extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Recipe=preload("res://scripts/construction/fabrication/construction_fabrication_recipe.gd")
const SCHEMA="planet_simulator.construction_production_chain.v1"
const FIELDS:Array[String]=["schema","chain_id","goal_id","target_definition_id","stages","total_work_units","material_cost","energy_cost","labor_cost","transport_cost","total_cost","currency","metadata","checksum"]
const STAGE_FIELDS:Array[String]=["stage_id","sequence","recipe","machine_construct_id","input_warehouse_id","output_warehouse_id","depends_on_stage_ids","output_item_ids","estimated_energy_cost","estimated_labor_cost","estimated_transport_cost"]
static func stage(id:String,sequence:int,recipe:Dictionary,machine:String,input_wh:String,output_wh:String,depends:Array,output_ids:Array,energy:float,labor:float,transport:float)->Dictionary:return {"stage_id":id,"sequence":sequence,"recipe":recipe.duplicate(true),"machine_construct_id":machine,"input_warehouse_id":input_wh,"output_warehouse_id":output_wh,"depends_on_stage_ids":P.sorted_strings(depends),"output_item_ids":P.sorted_strings(output_ids),"estimated_energy_cost":P.metric(energy),"estimated_labor_cost":P.metric(labor),"estimated_transport_cost":P.metric(transport)}
static func create(id:String,goal_id:String,target:String,stages:Array,material:float,currency:String,metadata:Dictionary={})->Dictionary:
	var rows=stages.duplicate(true);rows.sort_custom(func(a,b):return int(a.get("sequence",0))<int(b.get("sequence",0)))
	var work=0;var energy=0.0;var labor=0.0;var transport=0.0
	for s in rows:work+=int(s.get("recipe",{}).get("work_units",0));energy+=float(s.get("estimated_energy_cost",0.0));labor+=float(s.get("estimated_labor_cost",0.0));transport+=float(s.get("estimated_transport_cost",0.0))
	var total=P.metric(material+energy+labor+transport);var v={"schema":SCHEMA,"chain_id":id,"goal_id":goal_id,"target_definition_id":target,"stages":rows,"total_work_units":work,"material_cost":P.metric(material),"energy_cost":P.metric(energy),"labor_cost":P.metric(labor),"transport_cost":P.metric(transport),"total_cost":total,"currency":currency,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_PRODUCTION_CHAIN_SCHEMA");if not bool(x.success):return x
	if not P.path_id(String(v.get("chain_id","")),"production-chain/") or not P.path_id(String(v.get("goal_id","")),"agent-goal/") or not P.token(String(v.get("target_definition_id",""))):return P.failure("INVALID_CONSTRUCTION_PRODUCTION_CHAIN_IDENTITY")
	if typeof(v.get("stages"))!=TYPE_ARRAY or v.stages.is_empty():return P.failure("CONSTRUCTION_PRODUCTION_CHAIN_STAGES_REQUIRED")
	var prev=-1;var ids:Array=[];var outputs:Dictionary={};var work=0;var energy=0.0;var labor=0.0;var transport=0.0
	for s in v.stages:
		x=Utils.validate_exact_fields(s,STAGE_FIELDS);if not bool(x.success):return x
		if not P.path_id(String(s.get("stage_id","")),"production-stage/") or not Utils.is_json_integer(s.get("sequence")) or int(s.sequence)<=prev:return P.failure("NON_CANONICAL_CONSTRUCTION_PRODUCTION_CHAIN_STAGE")
		x=Recipe.validate(s.recipe);if not bool(x.success):return x
		for f in ["machine_construct_id","input_warehouse_id","output_warehouse_id"]:
			var prefix="construct/" if f=="machine_construct_id" else "warehouse/"
			if not P.path_id(String(s.get(f,"")),prefix):return P.failure("INVALID_CONSTRUCTION_PRODUCTION_CHAIN_RESOURCE")
		if not U.sorted_unique_strings(s.get("depends_on_stage_ids")) or not U.sorted_unique_strings(s.get("output_item_ids"),"item/"):return P.failure("NON_CANONICAL_CONSTRUCTION_PRODUCTION_CHAIN_BINDING")
		for dep in s.depends_on_stage_ids:
			if not ids.has(String(dep)):return P.failure("CONSTRUCTION_PRODUCTION_CHAIN_FORWARD_DEPENDENCY")
		for item_id in s.output_item_ids:
			if outputs.has(String(item_id)):return P.failure("CONSTRUCTION_PRODUCTION_CHAIN_DUPLICATE_OUTPUT")
			outputs[String(item_id)]=true
		for f in ["estimated_energy_cost","estimated_labor_cost","estimated_transport_cost"]:
			if not U.money(s.get(f)):return P.failure("INVALID_CONSTRUCTION_PRODUCTION_CHAIN_COST")
		ids.append(String(s.stage_id));prev=int(s.sequence);work+=int(s.recipe.work_units);energy+=float(s.estimated_energy_cost);labor+=float(s.estimated_labor_cost);transport+=float(s.estimated_transport_cost)
	if work!=int(v.total_work_units):return P.failure("CONSTRUCTION_PRODUCTION_CHAIN_WORK_MISMATCH")
	var expected=P.metric(float(v.material_cost)+energy+labor+transport)
	if not U.money(v.material_cost) or not is_equal_approx(P.metric(energy),float(v.energy_cost)) or not is_equal_approx(P.metric(labor),float(v.labor_cost)) or not is_equal_approx(P.metric(transport),float(v.transport_cost)) or not is_equal_approx(expected,float(v.total_cost)):return P.failure("CONSTRUCTION_PRODUCTION_CHAIN_COST_MISMATCH")
	if not P.upper_kind(String(v.currency)) or not U.canonical_dict(v.metadata) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_PRODUCTION_CHAIN_CHECKSUM_MISMATCH")
	return P.success()
