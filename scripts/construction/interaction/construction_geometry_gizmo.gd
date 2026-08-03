extends Node3D
const Op=preload("res://scripts/construction/geometry_edit/construction_geometry_edit_operation.gd")
var _state:Dictionary={};var _handles:Dictionary={};var _selected="";var _axis_mask=[true,true,true];var _grid=0.0
func configure(local_geometry_state:Dictionary,axis_mask:Array=[true,true,true],grid_step:float=0.0)->Dictionary:
 if typeof(local_geometry_state)!=TYPE_DICTIONARY or typeof(local_geometry_state.get("control_points"))!=TYPE_ARRAY:return _f("INVALID_CONSTRUCTION_GEOMETRY_GIZMO_STATE")
 _state=local_geometry_state.duplicate(true);_axis_mask=axis_mask.duplicate();_grid=grid_step
 for c in get_children():c.queue_free()
 _handles={}
 for p in _state.control_points:
  var m=Marker3D.new();m.name=String(p.point_id).replace("/","_");m.position=_v(p.position_m);m.set_meta("point_id",p.point_id);add_child(m);_handles[p.point_id]=m
 return _ok({"handle_count":_handles.size()})
func select_point(point_id:String)->Dictionary:
 if not _handles.has(point_id):return _f("CONSTRUCTION_GEOMETRY_GIZMO_POINT_NOT_FOUND")
 _selected=point_id;return _ok()
func draft_move(position:Vector3,sequence:int=0)->Dictionary:
 if _selected.is_empty():return _f("CONSTRUCTION_GEOMETRY_GIZMO_SELECTION_REQUIRED")
 var old:Vector3=_handles[_selected].position;var p=position
 if not _axis_mask[0]:p.x=old.x
 if not _axis_mask[1]:p.y=old.y
 if not _axis_mask[2]:p.z=old.z
 if _grid>0:p=Vector3(snapped(p.x,_grid),snapped(p.y,_grid),snapped(p.z,_grid))
 return _ok({"operation":Op.create("geometry-operation/ui/%s/%d"%[_selected.trim_prefix("geometry-point/").replace("/","-"),sequence],sequence,"MOVE_CONTROL_POINT",_selected,{"position_m":[p.x,p.y,p.z]})})
func get_handle(point_id:String):return _handles.get(point_id,null)
static func _v(a):return Vector3(float(a[0]),float(a[1]),float(a[2]))
static func _ok(d: Dictionary = {}) -> Dictionary:
 var r := {"success":true,"error_code":"","message":""}
 for k in d:
  r[k] = d[k]
 return r
static func _f(c):return {"success":false,"error_code":c,"message":c}
