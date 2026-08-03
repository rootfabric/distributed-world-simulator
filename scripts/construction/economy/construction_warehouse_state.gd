extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SCHEMA="planet_simulator.construction_warehouse_state.v1"
const FIELDS:Array[String]=["schema","warehouse_id","owner_id","server_id","cell_id","capacity_units","item_projections","reserved_quantities","revision","metadata","checksum"]
static func create(id:String,owner:String,server:String,cell:String,capacity:float,items:Array,reserved:Dictionary={},revision:int=0,metadata:Dictionary={})->Dictionary:
	var sorted=items.duplicate(true);sorted.sort_custom(func(a,b):return String(a.get("item_instance_id",""))<String(b.get("item_instance_id","")))
	var v={"schema":SCHEMA,"warehouse_id":id,"owner_id":owner,"server_id":server,"cell_id":cell,"capacity_units":P.metric(capacity),"item_projections":sorted,"reserved_quantities":reserved.duplicate(true),"revision":revision,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_WAREHOUSE_STATE_SCHEMA");if not bool(x.success):return x
	for spec in [["warehouse_id","warehouse/"],["owner_id","supplier/"],["server_id","server/"],["cell_id","cell/"]]:
		if not P.path_id(String(v.get(spec[0],"")),String(spec[1])):return P.failure("INVALID_CONSTRUCTION_WAREHOUSE_IDENTITY")
	if not U.positive(v.get("capacity_units")) or not Utils.is_json_integer(v.get("revision")) or int(v.revision)<0:return P.failure("INVALID_CONSTRUCTION_WAREHOUSE_CAPACITY_OR_REVISION")
	if typeof(v.get("item_projections"))!=TYPE_ARRAY or typeof(v.get("reserved_quantities"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_WAREHOUSE_INVENTORY")
	var previous="";var total=0.0;var items:Dictionary={}
	for projection in v.item_projections:
		x=ProjectionScript.validate(projection);if not bool(x.success):return x
		var id=String(projection.item_instance_id);if not previous.is_empty() and id<=previous:return P.failure("NON_CANONICAL_CONSTRUCTION_WAREHOUSE_ITEMS")
		total+=float(projection.quantity);items[id]=float(projection.quantity);previous=id
	if total>float(v.capacity_units)+0.000001:return P.failure("CONSTRUCTION_WAREHOUSE_CAPACITY_EXCEEDED")
	for raw in v.reserved_quantities.keys():
		if typeof(raw)!=TYPE_STRING or not items.has(String(raw)) or not U.money(v.reserved_quantities[raw]) or float(v.reserved_quantities[raw])>float(items[String(raw)]):return P.failure("INVALID_CONSTRUCTION_WAREHOUSE_RESERVATION")
	if not U.canonical_dict(v.get("metadata")) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_WAREHOUSE_STATE_CHECKSUM_MISMATCH")
	return P.success()
static func available_quantity(v:Dictionary,item_id:String)->float:
	for projection in v.get("item_projections",[]):
		if String(projection.get("item_instance_id",""))==item_id:return maxf(0.0,float(projection.get("quantity",0.0))-float(v.get("reserved_quantities",{}).get(item_id,0.0)))
	return 0.0
