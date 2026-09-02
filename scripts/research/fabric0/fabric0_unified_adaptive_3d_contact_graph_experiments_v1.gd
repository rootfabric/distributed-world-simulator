class_name Fabric0UnifiedAdaptive3DContactGraphExperimentsV1
extends RefCounted
const Fabric=preload("res://scripts/research/fabric0/fabric0_unified_adaptive_3d_contact_graph_v1.gd")
static func run(tol:float=1.0e-8,duration:float=0.7)->Dictionary:
 var w:=Fabric.new_world();var r:=Fabric.advance_adaptive(w,duration,{"atol":tol,"rtol":tol,"initial_step":0.08,"max_step":0.12,"min_step":1e-8});assert(bool(r["ok"]));return {"world":w,"result":r}
