extends RefCounted
const Utils = preload("res://scripts/network/contracts/network_contract_utils.gd")
const SCHEMA := "planet_simulator.construction_snap_target.v1"
const KINDS: Array[String] = ["SURFACE", "PORT", "GRID", "FREE"]
const FIELDS: Array[String] = ["schema","target_id","construct_id","part_id","port_id","target_kind","position_m","normal","up","compatible_placement_kinds","priority","properties","checksum"]
static func create(target_id:String, construct_id:String, part_id:String, port_id:String, target_kind:String, position_m:Array, normal:Array, up:Array, compatible:Array, priority:int=100, properties:Dictionary={}) -> Dictionary:
 var v={"schema":SCHEMA,"target_id":target_id,"construct_id":construct_id,"part_id":part_id,"port_id":port_id,"target_kind":target_kind,"position_m":position_m.duplicate(true),"normal":normal.duplicate(true),"up":up.duplicate(true),"compatible_placement_kinds":_sorted(compatible),"priority":priority,"properties":properties.duplicate(true),"checksum":""}; v.checksum=compute_checksum(v); return v
static func validate(v:Dictionary)->Dictionary:
 var e=Utils.validate_exact_fields(v,FIELDS); if not e.success:return e
 if v.schema!=SCHEMA:return _f("UNSUPPORTED_CONSTRUCTION_SNAP_TARGET_SCHEMA")
 if not _id(v.target_id,"snap-target/") or (not v.construct_id.is_empty() and not _id(v.construct_id,"construct/")):return _f("INVALID_CONSTRUCTION_SNAP_TARGET_IDENTITY")
 if not v.part_id.is_empty() and not _id(v.part_id,"part/"):return _f("INVALID_CONSTRUCTION_SNAP_TARGET_PART")
 if not v.port_id.is_empty() and not _id(v.port_id,"port/"):return _f("INVALID_CONSTRUCTION_SNAP_TARGET_PORT")
 if not KINDS.has(v.target_kind) or not _vec(v.position_m) or not _unit(v.normal) or not _unit(v.up):return _f("INVALID_CONSTRUCTION_SNAP_TARGET_GEOMETRY")
 if absf(_dot(v.normal,v.up))>0.001:return _f("CONSTRUCTION_SNAP_TARGET_AXES_NOT_ORTHOGONAL")
 if typeof(v.compatible_placement_kinds)!=TYPE_ARRAY or v.compatible_placement_kinds!=_sorted(v.compatible_placement_kinds):return _f("NON_CANONICAL_CONSTRUCTION_SNAP_TARGET_COMPATIBILITY")
 for k in v.compatible_placement_kinds:
  if not _kind(k):return _f("INVALID_CONSTRUCTION_SNAP_TARGET_COMPATIBILITY")
 if not Utils.is_json_integer(v.priority) or v.priority<0 or v.priority>1000 or typeof(v.properties)!=TYPE_DICTIONARY:return _f("INVALID_CONSTRUCTION_SNAP_TARGET_PROPERTIES")
 if v.checksum!=compute_checksum(v):return _f("CONSTRUCTION_SNAP_TARGET_CHECKSUM_MISMATCH")
 return Utils.validation_success()
static func compute_checksum(v):var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
static func _sorted(a: Array) -> Array:
 var r: Array = []
 for x in a:
  r.append(String(x))
 r.sort()
 return r
static func _vec(a)->bool:return typeof(a)==TYPE_ARRAY and a.size()==3 and a.all(func(x):return typeof(x) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(x)))
static func _unit(a)->bool:return _vec(a) and absf(sqrt(_dot(a,a))-1.0)<0.001
static func _dot(a,b)->float:return float(a[0])*float(b[0])+float(a[1])*float(b[1])+float(a[2])*float(b[2])
static func _id(s:String,p:String)->bool:return s.begins_with(p) and s.length()>p.length() and s==s.strip_edges()
static func _kind(s:String)->bool:return not s.is_empty() and s==s.to_upper()
static func _f(c):return Utils.validation_failure(c,c)
