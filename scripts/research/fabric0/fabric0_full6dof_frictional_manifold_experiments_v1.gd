class_name Fabric0Full6DOFFrictionalManifoldExperimentsV1
extends RefCounted

const F=preload("res://scripts/research/fabric0/fabric0_full6dof_frictional_manifold_v1.gd")
const M=preload("res://scripts/research/fabric0/fabric0_full6dof_model_v1.gd")

static func impact_run(tol:float=1e-8,duration:float=0.33)->Dictionary:
	var w:=F.new_world()
	w["mu"]=0.42
	var r:=F.advance(w,duration,{"atol":tol,"rtol":tol,"initial_step":0.03,"max_step":0.06,"min_step":1e-9})
	return {"world":w,"result":r}

static func sliding_world()->Dictionary:
	var w:=F.new_world()
	w["mu"]=0.30
	w["contact_active"]=true
	w["contact_mode"]="slide"
	w["support_signs"]=M.support_signs_from_q(M.quat(w["state"]))
	var s:Array=w["state"]
	s=M.with_parts(s,M.pos(s),M.quat(s),Vector3(1.8,-0.8,0.0),Vector3(0.5,-0.3,0.7))
	w["state"]=M.project_contact(w,s)
	w["initial_energy"]=M._energy(w,w["state"])
	w["final_energy"]=w["initial_energy"]
	return w

static func sliding_run(tol:float=1e-8,duration:float=0.315)->Dictionary:
	var w:=sliding_world()
	var r:=F.advance(w,duration,{"atol":tol,"rtol":tol,"initial_step":0.03,"max_step":0.05,"min_step":1e-9})
	return {"world":w,"result":r}

static func free_rotation_run(tol:float=1e-10,duration:float=0.6)->Dictionary:
	var w:=F.new_world()
	w["gravity"]=Vector3.ZERO
	w["external_force"]=Vector3.ZERO
	w["external_torque"]=Vector3.ZERO
	var s:Array=w["state"]
	s=M.with_parts(s,Vector3(0.2,-0.1,5.0),M.quat(s),Vector3(0.4,-0.2,0.3),Vector3(1.1,-0.9,1.4))
	w["state"]=s
	w["initial_energy"]=M._energy(w,s);w["final_energy"]=w["initial_energy"]
	var p0:=M.linear_momentum(w,s);var l0:=M.angular_momentum(w,s);var e0:=M.rotational_energy(w,s)
	var r:=F.advance(w,duration,{"atol":tol,"rtol":tol,"initial_step":0.04,"max_step":0.08,"min_step":1e-10})
	return {"world":w,"result":r,"p0":p0,"l0":l0,"e0":e0,"p1":M.linear_momentum(w,w["state"]),"l1":M.angular_momentum(w,w["state"]),"e1":M.rotational_energy(w,w["state"])}

static func stick_probe()->Dictionary:
	var w:=sliding_world();w["mu"]=1.2
	var s:Array=w["state"];var f:=M.current_feature(w);var g:=M.contact_geometry(w,s,f);var v:=M.vel(s);var om:=M.omega(s);var vc:Vector3=g["vc"]
	v.x-=vc.x;v.y-=vc.y
	w["state"]=M.with_parts(s,M.pos(s),M.quat(s),v,om)
	w["state"]=M.project_contact(w,w["state"])
	return F.force_probe(w,w["state"],"stick")

static func separation_probe()->Dictionary:
	var w:=sliding_world();w["external_force"]=Vector3(0,0,30.0)
	return F.force_probe(w,w["state"],"slide")

static func feature_chain_probe()->Dictionary:
	var w:=F.new_world()
	var vertex:=M.feature_from_signs(w,Vector3(-1,-1,-1))
	var edge:=F.support_feature_from_orientation(w,Quaternion(Vector3.RIGHT,0.4),1e-12)
	var face:=F.support_feature_from_orientation(w,Quaternion.IDENTITY,1e-12)
	var value:=Vector3(1.25,-0.5,2.0)
	var edge_value=F.lineage_remap(vertex,value,edge)
	var face_value=F.lineage_remap(edge,edge_value,face)
	return {"vertex":vertex,"edge":edge,"face":face,"value":value,"edge_value":edge_value,"face_value":face_value}
