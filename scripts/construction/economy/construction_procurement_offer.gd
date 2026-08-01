extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const SCHEMA="planet_simulator.construction_procurement_offer.v1"
const FIELDS:Array[String]=["schema","offer_id","supplier_id","warehouse_id","definition_id","components_exact","quantity_available","unit_price","currency","earliest_tick","expiry_tick","source_cell_id","source_server_id","metadata","checksum"]
static func create(offer_id:String,supplier_id:String,warehouse_id:String,definition_id:String,components:Dictionary,quantity:int,unit_price:float,currency:String,earliest_tick:int,expiry_tick:int,cell_id:String,server_id:String,metadata:Dictionary={})->Dictionary:
	var v={"schema":SCHEMA,"offer_id":offer_id,"supplier_id":supplier_id,"warehouse_id":warehouse_id,"definition_id":definition_id,"components_exact":components.duplicate(true),"quantity_available":quantity,"unit_price":P.metric(unit_price),"currency":currency,"earliest_tick":earliest_tick,"expiry_tick":expiry_tick,"source_cell_id":cell_id,"source_server_id":server_id,"metadata":metadata.duplicate(true),"checksum":""}
	v["unit_price"]=P.metric(unit_price);v["checksum"]=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_PROCUREMENT_OFFER_SCHEMA");if not bool(x.success):return x
	for spec in [["offer_id","procurement-offer/"],["supplier_id","supplier/"],["warehouse_id","warehouse/"],["source_cell_id","cell/"],["source_server_id","server/"]]:
		if not P.path_id(String(v.get(spec[0],"")),String(spec[1])):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_IDENTITY")
	if not P.token(String(v.get("definition_id",""))) or not U.canonical_dict(v.get("components_exact")):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_PRODUCT")
	if not Utils.is_json_integer(v.get("quantity_available")) or int(v.quantity_available)<1:return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_QUANTITY")
	if not U.money(v.get("unit_price")) or float(v.unit_price)<=0.0:return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_PRICE")
	if not P.upper_kind(String(v.get("currency",""))):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_CURRENCY")
	for f in ["earliest_tick","expiry_tick"]:
		if not Utils.is_json_integer(v.get(f)) or int(v[f])<0:return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_TICK")
	if int(v.expiry_tick)<int(v.earliest_tick):return P.failure("INVALID_CONSTRUCTION_PROCUREMENT_OFFER_WINDOW")
	if not U.canonical_dict(v.get("metadata")):return P.failure("NON_CANONICAL_CONSTRUCTION_PROCUREMENT_OFFER_METADATA")
	if String(v.get("checksum",""))!=U.checksum(v):return P.failure("CONSTRUCTION_PROCUREMENT_OFFER_CHECKSUM_MISMATCH")
	return P.success()
