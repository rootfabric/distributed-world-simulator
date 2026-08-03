extends RefCounted
const Req=preload("res://scripts/construction/interaction/construction_placement_request.gd")
const Target=preload("res://scripts/construction/interaction/construction_snap_target.gd")
const Sol=preload("res://scripts/construction/interaction/construction_placement_solution.gd")
static func resolve(request:Dictionary,targets:Array)->Dictionary:
 var e=Req.validate(request);if not e.success:return e
 var candidates=[]
 for raw in targets:
  if typeof(raw)!=TYPE_DICTIONARY:return _f("INVALID_CONSTRUCTION_SNAP_TARGET")
  e=Target.validate(raw);if not e.success:return e
  if not request.allowed_target_kinds.has(raw.target_kind):continue
  if not raw.compatible_placement_kinds.is_empty() and not raw.compatible_placement_kinds.has(request.placement_kind):continue
  var d=_distance(request.desired_position_m,raw.position_m)
  if d>float(request.snap_radius_m):continue
  candidates.append({"target":raw,"distance":d,"score":float(raw.priority)*1000.0-d})
 candidates.sort_custom(func(a,b):return a.score>b.score if a.score!=b.score else String(a.target.target_id)<String(b.target.target_id))
 if candidates.is_empty():
  var invalid=Sol.create(request.placement_id,request.checksum,false,"","",_grid(request.desired_position_m,float(request.grid_step_m)),[0.0,0.0,0.0,1.0],0.0,{"reason":"NO_COMPATIBLE_TARGET"});return {"success":true,"solution":invalid}
 var c=candidates[0];var t:Dictionary=c.target;var p=_grid(t.position_m,float(request.grid_step_m));var q=_orientation(t.normal,t.up)
 var solution=Sol.create(request.placement_id,request.checksum,true,t.target_id,t.checksum,p,q,c.score,{"distance_m":c.distance,"target_kind":t.target_kind,"part_id":t.part_id,"port_id":t.port_id})
 return {"success":true,"solution":solution}
static func _orientation(normal:Array,up:Array)->Array:
 var y=Vector3(normal[0],normal[1],normal[2]).normalized();var z=Vector3(up[0],up[1],up[2]).normalized();var x=z.cross(y).normalized();z=y.cross(x).normalized();var q=Basis(x,y,z).get_rotation_quaternion().normalized();return [q.x,q.y,q.z,q.w]
static func _grid(a:Array,s:float)->Array:
 if s<=0:return a.duplicate(true)
 return [snapped(float(a[0]),s),snapped(float(a[1]),s),snapped(float(a[2]),s)]
static func _distance(a,b)->float:return sqrt(pow(float(a[0])-float(b[0]),2)+pow(float(a[1])-float(b[1]),2)+pow(float(a[2])-float(b[2]),2))
static func _f(c):return {"success":false,"error_code":c,"message":c}
