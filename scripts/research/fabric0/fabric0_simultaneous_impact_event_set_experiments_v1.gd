class_name Fabric0SimultaneousImpactEventSetExperimentsV1
extends RefCounted

const F = preload("res://scripts/research/fabric0/fabric0_general_convex_multipoint_mcp_v1.gd")
const EventSet = preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_v1.gd")

static func five_body_probe(tolerance:float,reverse_order:bool=false)->Dictionary:
	var bodies:=_five_body_world()
	if reverse_order:
		bodies.reverse()
	return EventSet.next_appearance_event_set(bodies,0.0,0.6,tolerance,tolerance,192,64)

static func exact_three_body_probe(tolerance:float)->Dictionary:
	var shape:=F.box_shape("exact_box",Vector3(0.5,0.5,0.5))
	var bodies:Array=[
		F.new_body("L",shape,Vector3(-2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("C",shape,Vector3.ZERO),
		F.new_body("R",shape,Vector3(2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-2,0,0)),
	]
	return EventSet.next_appearance_event_set(bodies,0.0,0.6,tolerance,tolerance,192,16)

static func no_event_probe()->Dictionary:
	var shape:=F.box_shape("quiet_box",Vector3(0.5,0.5,0.5))
	var bodies:Array=[
		F.new_body("A",shape,Vector3(-4,0,0)),
		F.new_body("B",shape,Vector3(4,0,0)),
	]
	return EventSet.next_appearance_event_set(bodies,0.0,0.6,1.0e-8,1.0e-8,128,8)

static func _five_body_world()->Array:
	var shape:=F.box_shape("impact_box",Vector3(0.5,0.5,0.5))
	return [
		F.new_body("L",shape,Vector3(-2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("C",shape,Vector3.ZERO),
		F.new_body("R",shape,Vector3(2,0,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(-2,0,0)),
		F.new_body("P",shape,Vector3(-2.0004,4,0),Quaternion.IDENTITY,1.0,Vector3(0.2,0.2,0.2),Vector3(2,0,0)),
		F.new_body("Q",shape,Vector3(0,4,0)),
	]
