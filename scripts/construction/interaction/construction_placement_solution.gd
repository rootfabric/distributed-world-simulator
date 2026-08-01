extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const Target=preload("res://scripts/construction/interaction/construction_snap_target.gd")
const SCHEMA="planet_simulator.construction_placement_solution.v1"
const FIELDS:Array[String]=["schema","placement_id","request_checksum","valid","target_id","target_checksum","position_m","rotation_quat","score","diagnostics","checksum"]
static func create(id:String,req:String,valid:bool,target_id:String,target_checksum:String,pos:Array,quat:Array,score:float,diag:Dictionary={})->Dictionary:
 var v={"schema":SCHEMA,"placement_id":id,"request_checksum":req,"valid":valid,"target_id":target_id,"target_checksum":target_checksum,"position_m":pos.duplicate(true),"rotation_quat":quat.duplicate(true),"score":score,"diagnostics":diag.duplicate(true),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var e=Utils.validate_exact_fields(v,FIELDS);if not e.success:return e
 if v.schema!=SCHEMA or not String(v.placement_id).begins_with("placement/") or String(v.request_checksum).length()!=64:return _f("INVALID_CONSTRUCTION_PLACEMENT_SOLUTION_IDENTITY")
 if typeof(v.valid)!=TYPE_BOOL or not Target._vec(v.position_m) or typeof(v.rotation_quat)!=TYPE_ARRAY or v.rotation_quat.size()!=4:return _f("INVALID_CONSTRUCTION_PLACEMENT_SOLUTION_GEOMETRY")
 var q=0.0;for x in v.rotation_quat:
  if typeof(x) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(x)):return _f("INVALID_CONSTRUCTION_PLACEMENT_SOLUTION_GEOMETRY")
  q+=float(x)*float(x)
 if absf(sqrt(q)-1.0)>0.001:return _f("INVALID_CONSTRUCTION_PLACEMENT_SOLUTION_ROTATION")
 if v.valid and (String(v.target_id).is_empty() or String(v.target_checksum).length()!=64):return _f("CONSTRUCTION_PLACEMENT_SOLUTION_TARGET_REQUIRED")
 if not v.valid and (not String(v.target_id).is_empty() or not String(v.target_checksum).is_empty()):return _f("INVALID_CONSTRUCTION_PLACEMENT_SOLUTION_INVALID_TARGET")
 if typeof(v.diagnostics)!=TYPE_DICTIONARY or v.checksum!=compute_checksum(v):return _f("CONSTRUCTION_PLACEMENT_SOLUTION_CHECKSUM_MISMATCH")
 return Utils.validation_success()
static func compute_checksum(v):var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
static func _f(c):return Utils.validation_failure(c,c)
