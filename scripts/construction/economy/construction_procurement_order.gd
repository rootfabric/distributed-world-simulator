extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_procurement_order.v1"
const FIELDS:Array[String]=["schema","order_id","buyer_agent_id","goal_id","bom_line_id","offer_id","offer_checksum","definition_id","quantity","unit_price","goods_total","transport_cost","labor_cost","energy_cost","total_price","currency","delivery_relation","deadline_tick","status","escrow_id","shipment_id","metadata","checksum"]
const STATUSES=["DRAFT","PLACED","IN_TRANSIT","DELIVERED","CANCELLED","FAILED"]
static func create(order_id:String,buyer:String,goal_id:String,line_id:String,offer:Dictionary,quantity:int,transport:float,labor:float,energy:float,relation:Dictionary,deadline:int,status:String="DRAFT",escrow_id:String="",shipment_id:String="",metadata:Dictionary={})->Dictionary:
	var goods=P.metric(float(offer.get("unit_price",0.0))*quantity);var total=P.metric(goods+transport+labor+energy)
	var v={"schema":SCHEMA,"order_id":order_id,"buyer_agent_id":buyer,"goal_id":goal_id,"bom_line_id":line_id,"offer_id":String(offer.get("offer_id","")),"offer_checksum":String(offer.get("checksum","")),"definition_id":String(offer.get("definition_id","")),"quantity":quantity,"unit_price":P.metric(float(offer.get("unit_price",0.0))),"goods_total":goods,"transport_cost":P.metric(transport),"labor_cost":P.metric(labor),"energy_cost":P.metric(energy),"total_price":total,"currency":String(offer.get("currency","")),"delivery_relation":relation.duplicate(true),"deadline_tick":deadline,"status":status,"escrow_id":escrow_id,"shipment_id":shipment_id,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func with_status(v:Dictionary,status:String,escrow_id:String,shipment_id:String)->Dictionary:
	var n=v.duplicate(true);n.status=status;n.escrow_id=escrow_id;n.shipment_id=shipment_id;n.checksum=U.checksum(n);return n
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_PROCUREMENT_ORDER_SCHEMA");if not bool(x.success):return x
	for spec in [["order_id","procurement-order/"],["buyer_agent_id","agent/"],["goal_id","agent-goal/"],["bom_line_id","bom-line/"],["offer_id","procurement-offer/"]]:
		if not P.path_id(String(v.get(spec[0],"")),String(spec[1])):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_IDENTITY")
	if String(v.get("offer_checksum","")).length()!=64 or not P.token(String(v.get("definition_id",""))):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_PRODUCT")
	if not Utils.is_json_integer(v.get("quantity")) or int(v.quantity)<1:return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_QUANTITY")
	for f in ["unit_price","goods_total","transport_cost","labor_cost","energy_cost","total_price"]:
		if not U.money(v.get(f)):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_COST")
	var expected=P.metric(float(v.goods_total)+float(v.transport_cost)+float(v.labor_cost)+float(v.energy_cost))
	if not is_equal_approx(expected,float(v.total_price)) or not is_equal_approx(P.metric(float(v.unit_price)*int(v.quantity)),float(v.goods_total)):return P.failure("CONSTRUCTION_PROCUREMENT_ORDER_COST_MISMATCH")
	if not P.upper_kind(String(v.get("currency",""))) or not Utils.is_json_integer(v.get("deadline_tick")) or int(v.deadline_tick)<0:return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_TERMS")
	if not STATUSES.has(String(v.get("status",""))):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_STATUS")
	if not U.canonical_dict(v.get("delivery_relation")) or not U.canonical_dict(v.get("metadata")):return P.failure("NON_CANONICAL_CONSTRUCTION_PROCUREMENT_ORDER_PAYLOAD")
	if not String(v.escrow_id).is_empty() and not P.path_id(String(v.escrow_id),"escrow/"):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_ESCROW")
	if not String(v.shipment_id).is_empty() and not P.path_id(String(v.shipment_id),"shipment/"):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_ORDER_SHIPMENT")
	if String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_PROCUREMENT_ORDER_CHECKSUM_MISMATCH")
	return P.success()
