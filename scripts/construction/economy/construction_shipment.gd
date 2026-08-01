extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const Route=preload("res://scripts/construction/economy/construction_logistics_route.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SCHEMA="planet_simulator.construction_shipment.v1"
const FIELDS:Array[String]=["schema","shipment_id","order_id","route","item_projections","quantity_units","current_leg_index","status","departed_tick","available_tick","delivery_tick","receipts","metadata","checksum"]
const STATUSES=["READY","IN_TRANSIT","DELIVERED","CANCELLED","FAILED"]
static func create(id:String,order_id:String,route:Dictionary,items:Array,quantity:float,status:String="READY",current_leg:int=0,departed:int=-1,available:int=-1,delivery:int=-1,receipts:Array=[],metadata:Dictionary={})->Dictionary:
	var v={"schema":SCHEMA,"shipment_id":id,"order_id":order_id,"route":route.duplicate(true),"item_projections":items.duplicate(true),"quantity_units":P.metric(quantity),"current_leg_index":current_leg,"status":status,"departed_tick":departed,"available_tick":available,"delivery_tick":delivery,"receipts":receipts.duplicate(true),"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_SHIPMENT_SCHEMA");if not bool(x.success):return x
	if not P.path_id(String(v.get("shipment_id","")),"shipment/") or not P.path_id(String(v.get("order_id","")),"procurement-order/"):return P.failure("INVALID_CONSTRUCTION_SHIPMENT_IDENTITY")
	if typeof(v.get("route"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_SHIPMENT_ROUTE")
	x=Route.validate(v.route);if not bool(x.success):return x
	if typeof(v.get("item_projections"))!=TYPE_ARRAY or v.item_projections.is_empty():return P.failure("CONSTRUCTION_SHIPMENT_ITEMS_REQUIRED")
	var previous="";var total=0.0
	for projection in v.item_projections:
		x=ProjectionScript.validate(projection);if not bool(x.success):return x
		var id=String(projection.item_instance_id);if not previous.is_empty() and id<=previous:return P.failure("NON_CANONICAL_CONSTRUCTION_SHIPMENT_ITEMS")
		total+=float(projection.quantity);previous=id
	if not is_equal_approx(P.metric(total),float(v.quantity_units)) or not U.positive(v.quantity_units):return P.failure("CONSTRUCTION_SHIPMENT_QUANTITY_MISMATCH")
	if not Utils.is_json_integer(v.get("current_leg_index")) or int(v.current_leg_index)<0 or int(v.current_leg_index)>v.route.legs.size():return P.failure("INVALID_CONSTRUCTION_SHIPMENT_LEG_INDEX")
	if not STATUSES.has(String(v.get("status",""))):return P.failure("INVALID_CONSTRUCTION_SHIPMENT_STATUS")
	for f in ["departed_tick","available_tick","delivery_tick"]:
		if not Utils.is_json_integer(v.get(f)) or int(v[f])<-1:return P.failure("INVALID_CONSTRUCTION_SHIPMENT_TICK")
	if typeof(v.get("receipts"))!=TYPE_ARRAY or not bool(Utils.canonicalize(v.receipts).get("success",false)) or not U.canonical_dict(v.get("metadata")):return P.failure("NON_CANONICAL_CONSTRUCTION_SHIPMENT_PAYLOAD")
	if String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_SHIPMENT_CHECKSUM_MISMATCH")
	return P.success()
