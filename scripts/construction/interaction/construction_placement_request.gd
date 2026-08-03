extends RefCounted
const Utils=preload("res://scripts/network/contracts/network_contract_utils.gd")
const Target=preload("res://scripts/construction/interaction/construction_snap_target.gd")
const SCHEMA="planet_simulator.construction_placement_request.v1"
const FIELDS:Array[String]=["schema","placement_id","build_plan_id","build_plan_checksum","ghost_id","placement_kind","desired_position_m","desired_normal","ghost_up","snap_radius_m","allowed_target_kinds","grid_step_m","metadata","checksum"]
static func create(id:String,plan_id:String,plan_checksum:String,ghost_id:String,kind:String,pos:Array,normal:Array,up:Array,radius:float,allowed:Array,grid:float=0.0,metadata:Dictionary={})->Dictionary:
 var v={"schema":SCHEMA,"placement_id":id,"build_plan_id":plan_id,"build_plan_checksum":plan_checksum,"ghost_id":ghost_id,"placement_kind":kind,"desired_position_m":pos.duplicate(true),"desired_normal":normal.duplicate(true),"ghost_up":up.duplicate(true),"snap_radius_m":radius,"allowed_target_kinds":_sorted(allowed),"grid_step_m":grid,"metadata":metadata.duplicate(true),"checksum":""};v.checksum=compute_checksum(v);return v
static func validate(v:Dictionary)->Dictionary:
 var e=Utils.validate_exact_fields(v,FIELDS);if not e.success:return e
 if v.schema!=SCHEMA or not _id(v.placement_id,"placement/") or not _id(v.build_plan_id,"build-plan/") or not _id(v.ghost_id,"ghost/"):return _f("INVALID_CONSTRUCTION_PLACEMENT_REQUEST_IDENTITY")
 if typeof(v.build_plan_checksum)!=TYPE_STRING or v.build_plan_checksum.length()!=64 or v.placement_kind.is_empty() or v.placement_kind!=v.placement_kind.to_upper():return _f("INVALID_CONSTRUCTION_PLACEMENT_REQUEST_PROVENANCE")
 if not Target._vec(v.desired_position_m) or not Target._unit(v.desired_normal) or not Target._unit(v.ghost_up):return _f("INVALID_CONSTRUCTION_PLACEMENT_REQUEST_GEOMETRY")
 if float(v.snap_radius_m)<=0.0 or float(v.grid_step_m)<0.0:return _f("INVALID_CONSTRUCTION_PLACEMENT_REQUEST_DISTANCE")
 if typeof(v.allowed_target_kinds)!=TYPE_ARRAY or v.allowed_target_kinds!=_sorted(v.allowed_target_kinds) or v.allowed_target_kinds.is_empty():return _f("NON_CANONICAL_CONSTRUCTION_PLACEMENT_TARGET_KINDS")
 for k in v.allowed_target_kinds:
  if not Target.KINDS.has(k):return _f("INVALID_CONSTRUCTION_PLACEMENT_TARGET_KIND")
 if typeof(v.metadata)!=TYPE_DICTIONARY or v.checksum!=compute_checksum(v):return _f("CONSTRUCTION_PLACEMENT_REQUEST_CHECKSUM_MISMATCH")
 return Utils.validation_success()
static func compute_checksum(v):var p=v.duplicate(true);p.checksum="";return Utils.payload_hash(p)
static func _sorted(a: Array) -> Array:
 var r: Array = []
 for x in a:
  r.append(String(x))
 r.sort()
 return r
static func _id(s:String,p:String)->bool:return s.begins_with(p) and s.length()>p.length()
static func _f(c):return Utils.validation_failure(c,c)
