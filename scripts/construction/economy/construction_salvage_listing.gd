extends RefCounted
const U=preload("res://scripts/construction/economy/construction_economy_utils.gd")
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const P=preload("res://scripts/construction/parametric/construction_parametric_utils.gd")
const ProjectionScript=preload("res://scripts/construction/item_graph/construction_item_projection.gd")
const SCHEMA="planet_simulator.construction_salvage_listing.v1"
const FIELDS:Array[String]=["schema","listing_id","seller_id","warehouse_id","item_projection","sale_kind","ask_price","currency","minimum_bid","highest_bid","highest_bidder_id","expiry_tick","status","metadata","checksum"]
const SALE_KINDS=["FIXED","AUCTION"]
const STATUSES=["OPEN","SOLD","CANCELLED","EXPIRED"]
static func create(id:String,seller:String,warehouse:String,projection:Dictionary,sale_kind:String,ask:float,currency:String,min_bid:float,expiry:int,status:String="OPEN",highest:float=0.0,bidder:String="",metadata:Dictionary={})->Dictionary:
	var v={"schema":SCHEMA,"listing_id":id,"seller_id":seller,"warehouse_id":warehouse,"item_projection":projection.duplicate(true),"sale_kind":sale_kind,"ask_price":P.metric(ask),"currency":currency,"minimum_bid":P.metric(min_bid),"highest_bid":P.metric(highest),"highest_bidder_id":bidder,"expiry_tick":expiry,"status":status,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=U.checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
	var x=U.check_fields(v,FIELDS,SCHEMA,"UNSUPPORTED_CONSTRUCTION_SALVAGE_LISTING_SCHEMA");if not bool(x.success):return x
	for spec in [["listing_id","salvage-listing/"],["seller_id","supplier/"],["warehouse_id","warehouse/"]]:
		if not P.path_id(String(v.get(spec[0],"")),String(spec[1])):return P.failure("INVALID_CONSTRUCTION_SALVAGE_LISTING_IDENTITY")
	if typeof(v.get("item_projection"))!=TYPE_DICTIONARY:return P.failure("INVALID_CONSTRUCTION_SALVAGE_LISTING_ITEM")
	x=ProjectionScript.validate(v.item_projection);if not bool(x.success):return x
	if not SALE_KINDS.has(String(v.get("sale_kind",""))) or not STATUSES.has(String(v.get("status",""))):return P.failure("INVALID_CONSTRUCTION_SALVAGE_LISTING_KIND_OR_STATUS")
	for f in ["ask_price","minimum_bid","highest_bid"]:
		if not U.money(v.get(f)):return P.failure("INVALID_CONSTRUCTION_SALVAGE_LISTING_PRICE")
	if String(v.sale_kind)=="AUCTION" and float(v.minimum_bid)<=0.0:return P.failure("INVALID_CONSTRUCTION_SALVAGE_AUCTION_MINIMUM")
	if not String(v.highest_bidder_id).is_empty() and not P.path_id(String(v.highest_bidder_id),"agent/"):return P.failure("INVALID_CONSTRUCTION_SALVAGE_BIDDER")
	if not Utils.is_json_integer(v.get("expiry_tick")) or int(v.expiry_tick)<0:return P.failure("INVALID_CONSTRUCTION_SALVAGE_EXPIRY")
	if not U.canonical_dict(v.get("metadata")) or String(v.checksum)!=U.checksum(v):return P.failure("CONSTRUCTION_SALVAGE_LISTING_CHECKSUM_MISMATCH")
	return P.success()
