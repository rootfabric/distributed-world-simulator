class_name Fabric0MultibodyComplementarityV1
extends RefCounted

const Model=preload("res://scripts/research/fabric0/fabric0_multibody_convex_model_v1.gd")
const EPS:=1.0e-12

static func solve(world:Dictionary,contacts:Array,dt:float,reverse_order:bool=false)->Dictionary:
	var work:=contacts.duplicate(true)
	if reverse_order:work.reverse()
	var blocks:={}
	for c in contacts:
		var basis:=Model.tangent_basis(Vector3(c["normal"]))
		blocks[String(c["id"])]= {"pn":0.0,"pt":Vector2.ZERO,"t1":basis[0],"t2":basis[1],"mode":"stick","vn_before":Model.contact_velocity(world,c).dot(Vector3(c["normal"]))}
	var k_before:=Model.total_kinetic(world)
	var p_before:=Model.total_linear_momentum(world);var l_before:=Model.total_angular_momentum_origin(world)
	var max_pair_dp:=0.0;var max_pair_dl:=0.0
	var iterations:=int(world["solver_iterations"])
	for _it in range(iterations):
		for c in work:
			var id:=String(c["id"]);var block:Dictionary=blocks[id];var n:Vector3=c["normal"]
			var rv:=Model.contact_velocity(world,c);var vn:=rv.dot(n);var kn:=Model.effective_scalar(world,c,n)
			var penetration:=minf(float(c["gap"]),0.0);var desired:=maxf(-float(world["beta"])*penetration/dt,0.0)
			if bool(c["is_new"]) and float(block["vn_before"]) < -0.4:
				desired=maxf(desired,-float(c["restitution"])*float(block["vn_before"]))
			var delta_n:=(desired-vn)/maxf(kn,EPS);var old_n:=float(block["pn"]);var new_n:=maxf(0.0,old_n+delta_n);delta_n=new_n-old_n;block["pn"]=new_n
			if absf(delta_n)>EPS:
				var pb:=Model.total_linear_momentum(world);var lb:=Model.total_angular_momentum_origin(world)
				Model.apply_impulse(world,c,n*delta_n)
				if int(c["a"])>=0:
					max_pair_dp=maxf(max_pair_dp,(Model.total_linear_momentum(world)-pb).length())
					max_pair_dl=maxf(max_pair_dl,(Model.total_angular_momentum_origin(world)-lb).length())
			rv=Model.contact_velocity(world,c)
			var t1:Vector3=block["t1"];var t2:Vector3=block["t2"];var vt:=Vector2(rv.dot(t1),rv.dot(t2));var kt:=Model.effective_tangent2(world,c,t1,t2)
			var delta_t:=Model.solve2(kt,-vt);var old_t:Vector2=block["pt"];var trial:=old_t+delta_t;var limit:=float(c["mu"])*float(block["pn"])
			var new_t:=trial
			if trial.length()>limit and trial.length()>EPS:new_t=trial*(limit/trial.length())
			var diff:=new_t-old_t;block["pt"]=new_t
			if diff.length()>EPS:
				var pb2:=Model.total_linear_momentum(world);var lb2:=Model.total_angular_momentum_origin(world)
				Model.apply_impulse(world,c,t1*diff.x+t2*diff.y)
				if int(c["a"])>=0:
					max_pair_dp=maxf(max_pair_dp,(Model.total_linear_momentum(world)-pb2).length())
					max_pair_dl=maxf(max_pair_dl,(Model.total_angular_momentum_origin(world)-lb2).length())
			block["mode"]="slide" if limit>EPS and new_t.length()>=limit-1.0e-8 else "stick"
	var max_nv:=0.0;var max_cone:=0.0;var min_pn:=INF
	for c in contacts:
		var id:=String(c["id"]);var block:Dictionary=blocks[id];var rv:=Model.contact_velocity(world,c);var vn:=rv.dot(Vector3(c["normal"]));max_nv=maxf(max_nv,maxf(0.0,-vn));var limit:=float(c["mu"])*float(block["pn"]);max_cone=maxf(max_cone,maxf(0.0,Vector2(block["pt"]).length()-limit));min_pn=minf(min_pn,float(block["pn"]));block["vn_after"]=vn
	var k_after:=Model.total_kinetic(world);var loss:=k_before-k_after
	world["max_internal_linear_momentum_error"]=maxf(float(world["max_internal_linear_momentum_error"]),max_pair_dp)
	world["max_internal_angular_momentum_error"]=maxf(float(world["max_internal_angular_momentum_error"]),max_pair_dl)
	world["max_normal_violation"]=maxf(float(world["max_normal_violation"]),max_nv)
	world["max_cone_violation"]=maxf(float(world["max_cone_violation"]),max_cone)
	world["min_normal_impulse"]=minf(float(world["min_normal_impulse"]),min_pn)
	world["contact_iterations"]=int(world["contact_iterations"])+iterations;world["contact_solves"]=int(world["contact_solves"])+1
	if loss>=0.0:world["contact_dissipation"]=float(world["contact_dissipation"])+loss
	else:world["contact_gain"]=float(world["contact_gain"])-loss
	return {"ok":true,"blocks":blocks,"iterations":iterations,"max_normal_violation":max_nv,"max_cone_violation":max_cone,"kinetic_loss":loss,"p_before":p_before,"p_after":Model.total_linear_momentum(world),"l_before":l_before,"l_after":Model.total_angular_momentum_origin(world)}
