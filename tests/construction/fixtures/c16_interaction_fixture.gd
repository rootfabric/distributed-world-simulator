extends RefCounted
const Target=preload("res://scripts/construction/interaction/construction_snap_target.gd")
const Request=preload("res://scripts/construction/interaction/construction_placement_request.gd")
const C3=preload("res://tests/construction/fixtures/c3_table_build_fixture.gd")
const C11=preload("res://tests/construction/fixtures/c11_local_geometry_editing_fixture.gd")
static func target(id:String="table",position:Array=[2.0,0.0,3.0],priority:int=100,kind:String="SURFACE")->Dictionary:
 return Target.create("snap-target/c16/%s"%id,"construct/c16/support","part/c16/support/top","port/c16/support/top",kind,position,[0.0,1.0,0.0],[0.0,0.0,1.0],["FURNITURE","STRUCTURAL"],priority,{"capability_kind":"SUPPORT_SURFACE"})
static func placement()->Dictionary:
 var plan=C3.build_plan();return Request.create("placement/c16/table",String(plan.build_plan_id),String(plan.checksum),"ghost/c16/table","FURNITURE",[2.1,0.1,3.0],[0.0,1.0,0.0],[0.0,0.0,1.0],1.0,["PORT","SURFACE"],0.5,{"actor":"client/c16/ui"})
static func local_state()->Dictionary:
 var graph=C11.graph("c16",4.0);return preload("res://scripts/construction/geometry_edit/construction_local_geometry_state.gd").bootstrap(graph.instance)
static func session()->Dictionary:return {"client_id":"client/c16/ui","session_id":"session/c16/ui","session_epoch":1,"next_sequence":0,"permission_epoch":1}
static func repair_ghost()->Dictionary:
 var v={"schema":"planet_simulator.construction_repair_ghost_state.v1","repair_id":"repair/c16/fixture","repair_plan_checksum":"a".repeat(64),"target_construct_id":"construct/c16/repair","part_states":[{"item_instance_id":"item/c16/part-a","status":"AVAILABLE"},{"item_instance_id":"item/c16/part-b","status":"MISSING"}],"ready":false,"checksum":""}
 v.checksum=preload("res://scripts/construction/damage/construction_repair_ghost_state.gd").compute_checksum(v);return v
