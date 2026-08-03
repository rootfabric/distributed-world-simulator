extends Node3D
var _mesh:MeshInstance3D;var _valid=false;var _solution:Dictionary={}
func _init():
 _mesh=MeshInstance3D.new();_mesh.name="PlacementGhostMesh";var box=BoxMesh.new();box.size=Vector3(1,1,1);_mesh.mesh=box;var mat=StandardMaterial3D.new();mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;mat.albedo_color=Color(0.2,0.8,1.0,0.35);_mesh.material_override=mat;add_child(_mesh)
func apply_solution(solution:Dictionary,dimensions:Vector3=Vector3.ONE)->Dictionary:
 var checked=preload("res://scripts/construction/interaction/construction_placement_solution.gd").validate(solution);if not checked.success:return checked
 _solution=solution.duplicate(true);_valid=solution.valid;visible=true;position=_v(solution.position_m);quaternion=Quaternion(float(solution.rotation_quat[0]),float(solution.rotation_quat[1]),float(solution.rotation_quat[2]),float(solution.rotation_quat[3]));(_mesh.mesh as BoxMesh).size=dimensions
 var mat=_mesh.material_override as StandardMaterial3D;mat.albedo_color=Color(0.2,0.8,1.0,0.35) if _valid else Color(1.0,0.2,0.2,0.35)
 return {"success":true,"valid":_valid}
func is_valid_placement()->bool:return _valid
func get_solution()->Dictionary:return _solution.duplicate(true)
static func _v(a):return Vector3(float(a[0]),float(a[1]),float(a[2]))
