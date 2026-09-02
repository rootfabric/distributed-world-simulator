class_name Fabric0GeneralizedContactWrenchExperimentsV1
extends RefCounted

const F=preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const W=preload("res://scripts/research/fabric0/fabric0_generalized_contact_wrench_v1.gd")

static func stick_probe(reverse_bodies:bool=false,reverse_pair:bool=false)->Dictionary:
	var fixture:=_fixture(Vector3(0,0.15,0.08),Vector3(0.12,0.08,0.10))
	var bodies:Array=fixture["bodies"]
	if reverse_bodies:bodies.reverse()
	var a_id:="A";var b_id:="B"
	if reverse_pair:
		a_id="B";b_id="A"
	return W.solve_patch(bodies,a_id,b_id,fixture["manifold"],2.0,{"mu_tangent":2.0,"mu_rolling":1.5,"mu_torsion":1.5,"tolerance":1.0e-12,"iterations":10000})

static func saturated_probe(reverse_bodies:bool=false,reverse_pair:bool=false)->Dictionary:
	var fixture:=_fixture(Vector3(0,4.0,-3.0),Vector3(5.0,-4.0,6.0))
	var bodies:Array=fixture["bodies"]
	if reverse_bodies:bodies.reverse()
	var a_id:="A";var b_id:="B"
	if reverse_pair:
		a_id="B";b_id="A"
	return W.solve_patch(bodies,a_id,b_id,fixture["manifold"],2.0,{"mu_tangent":0.25,"mu_rolling":0.08,"mu_torsion":0.05,"tolerance":1.0e-12,"iterations":10000})

static func zero_budget_probe()->Dictionary:
	var fixture:=_fixture(Vector3(0,1,0),Vector3(1,1,1))
	return W.solve_patch(fixture["bodies"],"A","B",fixture["manifold"],0.0,{"mu_tangent":0.5,"mu_rolling":0.1,"mu_torsion":0.1})

static func _fixture(v_b:Vector3,w_b:Vector3)->Dictionary:
	var shape:=F.box_shape("wrench_box",Vector3(0.5,0.5,0.5))
	var a:=F.new_body("A",shape,Vector3.ZERO,Quaternion.IDENTITY,2.0,Vector3(0.3,0.4,0.5),Vector3.ZERO,Vector3.ZERO)
	var b:=F.new_body("B",shape,Vector3(0.99,0,0),Quaternion.IDENTITY,1.5,Vector3(0.22,0.28,0.35),v_b,w_b)
	var collision:=F.collide(a,b)
	assert(bool(collision.get("ok",false)) and bool(collision.get("intersect",false)))
	var manifold:=F.build_manifold(a,b,collision,{},4)
	assert(bool(manifold.get("ok",false)) and manifold["points"].size()==4)
	return {"bodies":[a,b],"manifold":manifold}

static func state_error(a:Array,b:Array)->float:
	if a.size()!=b.size():return INF
	var maximum:=0.0
	for i in range(a.size()):
		if String(a[i][0])!=String(b[i][0]):return INF
		for j in range(1,a[i].size()):maximum=maxf(maximum,absf(float(a[i][j])-float(b[i][j])))
	return maximum

static func pure_moment_probe()->Dictionary:
	var fixture:=_fixture(Vector3.ZERO,Vector3(3.0,-2.0,4.0))
	return W.solve_patch(fixture["bodies"],"A","B",fixture["manifold"],2.0,{"mu_tangent":0.0,"mu_rolling":0.12,"mu_torsion":0.09,"tolerance":1.0e-12,"iterations":10000})

static func pure_tangent_probe()->Dictionary:
	var fixture:=_fixture(Vector3(0,3.0,-2.0),Vector3.ZERO)
	return W.solve_patch(fixture["bodies"],"A","B",fixture["manifold"],2.0,{"mu_tangent":0.3,"mu_rolling":0.0,"mu_torsion":0.0,"tolerance":1.0e-12,"iterations":10000})
