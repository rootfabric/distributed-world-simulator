extends SceneTree
const Fixture=preload("res://tests/construction/fixtures/c16_interaction_fixture.gd")
const Controller=preload("res://scripts/construction/interaction/construction_interaction_controller.gd")
const Gizmo=preload("res://scripts/construction/interaction/construction_geometry_gizmo.gd")
const Materials=preload("res://scripts/construction/interaction/construction_material_overlay_model.gd")
const Adapter=preload("res://scripts/construction/interaction/construction_interaction_command_adapter.gd")
const Command=preload("res://scripts/construction/multiplayer/construction_multiplayer_command.gd")
const Op=preload("res://scripts/construction/geometry_edit/construction_geometry_edit_operation.gd")
const C3=preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
class FakeGateway:
 extends RefCounted
 var commands:Array=[]
 func submit(command:Dictionary)->Dictionary:
  commands.append(command.duplicate(true));return {"success":true,"error_code":"","message":"","accepted":true,"event_index":commands.size()-1}
var assertions=0;var failures:Array[String]=[]
func _init():call_deferred("_run")
func _run():
 _test_controller_and_ghost();_test_gizmo();_test_overlay();_test_command_boundary();_finish()
func _test_controller_and_ghost():
 var c=Controller.new();root.add_child(c);_ok(c.set_mode("PLACE"),"place mode");_assert(c.ghost.visible,"ghost visible");_assert(not c.gizmo.visible,"gizmo hidden")
 var result=c.update_placement(Fixture.placement(),[Fixture.target()],Vector3(2,1,3));_ok(result,"placement update");_assert(c.ghost.is_valid_placement(),"ghost valid");_assert(c.ghost.position.is_equal_approx(Vector3(2,0,3)),"ghost position");_assert(c.ghost.get_child_count()==1,"ghost mesh count");_assert(c.ghost.get_child(0) is MeshInstance3D,"ghost mesh type");_assert((c.ghost.get_child(0).mesh as BoxMesh).size==Vector3(2,1,3),"ghost dimensions");_assert(c.overlay.status_label.text=="Допустимо","placement status")
 _ok(c.set_mode("EDIT"),"edit mode");_assert(not c.ghost.visible and c.gizmo.visible,"mode visibility");_err(c.update_placement(Fixture.placement(),[Fixture.target()]),"CONSTRUCTION_INTERACTION_NOT_IN_PLACEMENT_MODE","mode guard");c.free()
func _test_gizmo():
 var g=Gizmo.new();root.add_child(g);var state=Fixture.local_state();_ok(g.configure(state,[true,false,false],0.5),"gizmo configure");_assert(g.get_child_count()==state.control_points.size(),"handle count")
 var end_id=String(state.control_points[-1].point_id);_ok(g.select_point(end_id),"select point");var drafted=g.draft_move(Vector3(7.2,4,3),0);_ok(drafted,"draft move");_ok(Op.validate(drafted.operation),"operation validate");_assert(absf(float(drafted.operation.payload.position_m[0])-7.0)<0.000001 and absf(float(drafted.operation.payload.position_m[1]))<0.000001 and absf(float(drafted.operation.payload.position_m[2]))<0.000001,"axis lock and grid");_assert(g.get_handle(end_id) is Marker3D,"handle type");_err(g.select_point("geometry-point/missing"),"CONSTRUCTION_GEOMETRY_GIZMO_POINT_NOT_FOUND","missing point");g.free()
func _test_overlay():
 var c=Controller.new();root.add_child(c);var plan=C3.build_plan();var ids=[];for p in plan.source_item_projections:ids.append(String(p.item_instance_id));ids.erase(String(plan.stages[0].material_allocations[0].item_instance_id))
 var model=Materials.from_build_plan(plan,ids).overlay;c.overlay.show_materials(model);_assert(c.overlay.material_label.text.contains("отсутствует"),"material text");_assert(c.overlay.progress.value<1.0,"material progress");c.overlay.show_command_result({"success":false,"error_code":"DENIED"});_assert(c.overlay.status_label.text.contains("DENIED"),"error surfaced");c.free()
func _test_command_boundary():
 var gateway=FakeGateway.new();var a=Adapter.new();_ok(a.setup(gateway),"adapter setup");var s=Fixture.session();var plan=C3.build_plan()
 var result=a.build_stage(s,"multiplayer-command/c16/build",String(plan.construct_id),"b".repeat(64),0,String(plan.build_plan_id),0,"operation/c16/build",["USE_TOOL"],{});_ok(result,"build submit");_assert(gateway.commands.size()==1,"one command");_ok(Command.validate(gateway.commands[0]),"command contract");_assert(gateway.commands[0].action=="BUILD_STAGE","build action");_assert(gateway.commands[0].payload.build_plan_id==plan.build_plan_id,"plan forwarded");_assert(result.has("command"),"command returned to UI")
 var bad=Adapter.new();_err(bad.setup(null),"CONSTRUCTION_INTERACTION_GATEWAY_REQUIRED","gateway required")
func _ok(r,m):_assert(bool(r.get("success",false)),"%s: %s"%[m,r])
func _err(r,c,m):_assert(not bool(r.get("success",false)) and String(r.get("error_code",""))==c,"%s: %s"%[m,r])
func _assert(v,m):assertions+=1;if not v:failures.append(m)
func _finish():
 if failures.is_empty():print("C16 interaction UX integration: PASS (%d assertions)"%assertions);quit(0);return
 for f in failures:push_error(f)
 print("C16 interaction UX integration: FAIL (%d failures, %d assertions)"%[failures.size(),assertions]);quit(1)
