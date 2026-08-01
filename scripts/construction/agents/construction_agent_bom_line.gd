extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SCHEMA="planet_simulator.construction_agent_bom_line.v1"
const FIELDS:Array[String]=["schema","line_id","category","source_key","definition_id","required_quantity","required_components","available_bindings","fabrication_bindings","missing_quantity","acquisition_mode","estimated_cost","checksum"]
const CATEGORIES=["PART_SLOT","MATERIAL","FABRICATION_INPUT","REPAIR_PART"]
const MODES=["AVAILABLE","FABRICATE","PROCURE","BLOCKED"]
const BINDING_FIELDS:Array[String]=["item_instance_id","quantity","projection"]
const FAB_FIELDS:Array[String]=["recipe_id","recipe_version","recipe_checksum","product_key","output_item_id","output_quantity","input_requirements"]
static func create(line_id:String,category:String,source_key:String,definition_id:String,required_quantity:int,required_components:Dictionary,available_bindings:Array,fabrication_bindings:Array,missing_quantity:int,acquisition_mode:String,estimated_cost:float)->Dictionary:
 var v={"schema":SCHEMA,"line_id":line_id,"category":category,"source_key":source_key,"definition_id":definition_id,"required_quantity":required_quantity,"required_components":required_components.duplicate(true),"available_bindings":P.sorted_rows(available_bindings,"item_instance_id"),"fabrication_bindings":P.sorted_rows(fabrication_bindings,"output_item_id"),"missing_quantity":missing_quantity,"acquisition_mode":acquisition_mode,"estimated_cost":P.metric(estimated_cost),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var x=Utils.validate_exact_fields(v,FIELDS);if not bool(x.success):return x
 if v.get("schema")!=SCHEMA:return P.failure("UNSUPPORTED_CONSTRUCTION_AGENT_BOM_LINE_SCHEMA")
 if not P.path_id(String(v.get("line_id","")),"bom-line/") or not CATEGORIES.has(String(v.get("category",""))):return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_LINE_IDENTITY")
 if String(v.get("source_key","" )).is_empty() or String(v.get("definition_id","" )).is_empty():return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_LINE_SOURCE")
 if not Utils.is_json_integer(v.get("required_quantity")) or int(v.required_quantity)<1 or not Utils.is_json_integer(v.get("missing_quantity")) or int(v.missing_quantity)<0 or int(v.missing_quantity)>int(v.required_quantity):return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_LINE_QUANTITY")
 if typeof(v.get("required_components"))!=TYPE_DICTIONARY or not bool(Utils.canonicalize(v.required_components).get("success",false)):return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_LINE_COMPONENTS")
 var available_total:=0;var previous:="";var seen:={}
 if typeof(v.get("available_bindings"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_AVAILABLE_BINDINGS")
 for row in v.available_bindings:
  if typeof(row)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_AVAILABLE_BINDING")
  x=Utils.validate_exact_fields(row,BINDING_FIELDS);if not bool(x.success):return x
  var item_id:=String(row.get("item_instance_id",""));if not P.path_id(item_id,"item/") or seen.has(item_id) or (not previous.is_empty() and item_id<previous):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_BOM_AVAILABLE_BINDINGS")
  if not Utils.is_json_integer(row.get("quantity")) or int(row.quantity)<1:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_AVAILABLE_QUANTITY")
  if typeof(row.get("projection"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_AVAILABLE_PROJECTION")
  x=ProjectionScript.validate(row.projection);if not bool(x.success):return x
  if item_id!=String(row.projection.item_instance_id) or String(v.definition_id)!=String(row.projection.definition_id):return P.failure("CONSTRUCTION_AGENT_BOM_BINDING_PROJECTION_MISMATCH")
  available_total+=int(row.quantity);seen[item_id]=true;previous=item_id
 var fabricated_total:=0;previous="";seen={}
 if typeof(v.get("fabrication_bindings"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_FABRICATION_BINDINGS")
 for row in v.fabrication_bindings:
  if typeof(row)!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_FABRICATION_BINDING")
  x=Utils.validate_exact_fields(row,FAB_FIELDS);if not bool(x.success):return x
  var output_id:=String(row.get("output_item_id",""));if not P.path_id(output_id,"item/") or seen.has(output_id) or (not previous.is_empty() and output_id<previous):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_BOM_FABRICATION_BINDINGS")
  if not P.path_id(String(row.get("recipe_id","")),"fabrication-recipe/") or not Utils.is_json_integer(row.get("recipe_version")) or int(row.recipe_version)<1 or String(row.get("recipe_checksum","" )).length()!=64:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_RECIPE_BINDING")
  if not Utils.is_json_integer(row.get("output_quantity")) or int(row.output_quantity)<1 or typeof(row.get("input_requirements"))!=TYPE_ARRAY:return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_RECIPE_BINDING")
  fabricated_total+=int(row.output_quantity);seen[output_id]=true;previous=output_id
 if available_total+fabricated_total+int(v.missing_quantity)!=int(v.required_quantity):return P.failure("CONSTRUCTION_AGENT_BOM_LINE_QUANTITY_CONSERVATION_FAILED")
 if not MODES.has(String(v.get("acquisition_mode",""))):return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_ACQUISITION_MODE")
 if String(v.acquisition_mode)=="AVAILABLE" and (int(v.missing_quantity)!=0 or not v.fabrication_bindings.is_empty()):return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_BOM_ACQUISITION_MODE")
 if String(v.acquisition_mode)=="FABRICATE" and v.fabrication_bindings.is_empty():return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_BOM_ACQUISITION_MODE")
 if String(v.acquisition_mode) in ["PROCURE","BLOCKED"] and int(v.missing_quantity)<1:return P.failure("NON_CANONICAL_CONSTRUCTION_AGENT_BOM_ACQUISITION_MODE")
 if not P.non_negative_number(v.get("estimated_cost")):return P.failure("INVALID_CONSTRUCTION_AGENT_BOM_ESTIMATED_COST")
 if String(v.get("checksum",""))!=compute_checksum(v):return P.failure("CONSTRUCTION_AGENT_BOM_LINE_CHECKSUM_MISMATCH")
 return P.success()
static func compute_checksum(v:Dictionary)->String:var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
