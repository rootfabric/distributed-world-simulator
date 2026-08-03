extends Node
const Resolver=preload("res://scripts/construction/interaction/construction_semantic_snap_resolver.gd")
const Ghost=preload("res://scripts/construction/interaction/construction_placement_ghost.gd")
const Gizmo=preload("res://scripts/construction/interaction/construction_geometry_gizmo.gd")
const Overlay=preload("res://scripts/construction/interaction/construction_interaction_overlay.gd")
const MODES:Array[String]=["IDLE","PLACE","EDIT","REPAIR","INSPECT"]
var mode="IDLE";var ghost;var gizmo;var overlay
func _init():ghost=Ghost.new();add_child(ghost);ghost.visible=false;gizmo=Gizmo.new();add_child(gizmo);gizmo.visible=false;overlay=Overlay.new();add_child(overlay)
func set_mode(value:String)->Dictionary:
 if not MODES.has(value):return {"success":false,"error_code":"INVALID_CONSTRUCTION_INTERACTION_MODE","message":"INVALID_CONSTRUCTION_INTERACTION_MODE"}
 mode=value;ghost.visible=value=="PLACE";gizmo.visible=value=="EDIT";return {"success":true,"error_code":"","message":""}
func update_placement(request:Dictionary,targets:Array,dimensions:Vector3=Vector3.ONE)->Dictionary:
 if mode!="PLACE":return {"success":false,"error_code":"CONSTRUCTION_INTERACTION_NOT_IN_PLACEMENT_MODE","message":"CONSTRUCTION_INTERACTION_NOT_IN_PLACEMENT_MODE"}
 var r=Resolver.resolve(request,targets);if not r.success:return r
 ghost.apply_solution(r.solution,dimensions);overlay.show_placement(r.solution);return r
