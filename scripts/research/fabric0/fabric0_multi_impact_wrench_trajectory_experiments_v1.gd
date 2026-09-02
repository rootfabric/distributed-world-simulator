class_name Fabric0MultiImpactWrenchTrajectoryExperimentsV1
extends RefCounted

const EventSet=preload("res://scripts/research/fabric0/fabric0_simultaneous_impact_event_set_v1.gd")
const FixedPoint=preload("res://scripts/research/fabric0/fabric0_impact_wrench_fixed_point_v1.gd")
const Trajectory=preload("res://scripts/research/fabric0/fabric0_multi_impact_wrench_trajectory_v1.gd")

static func refinement_probe()->Dictionary:
	var coarse:=Trajectory.run(1.0e-5)
	var medium:=Trajectory.run(1.0e-7)
	var fine:=Trajectory.run(1.0e-9)
	var reference:=Trajectory.run(1.0e-11)
	if not (bool(coarse.get("ok",false)) and bool(medium.get("ok",false)) and bool(fine.get("ok",false)) and bool(reference.get("ok",false))):
		return {"ok":false,"code":"REFINEMENT_RUN_FAILED","runs":[coarse,medium,fine,reference]}
	return {
		"ok":true,"coarse":coarse,"medium":medium,"fine":fine,"reference":reference,
		"state_errors":[Trajectory.state_error(coarse,reference),Trajectory.state_error(medium,reference),Trajectory.state_error(fine,reference)],
		"event_errors":[Trajectory.event_time_error(coarse,reference),Trajectory.event_time_error(medium,reference),Trajectory.event_time_error(fine,reference)],
	}

static func determinism_probe(tolerance:float=1.0e-9)->Dictionary:
	var forward:=Trajectory.run(tolerance)
	var replay:=Trajectory.run(tolerance)
	var reverse_bodies:=Trajectory.run(tolerance,true,false)
	var reverse_members:=Trajectory.run(tolerance,false,true)
	if not (bool(forward.get("ok",false)) and bool(replay.get("ok",false)) and bool(reverse_bodies.get("ok",false)) and bool(reverse_members.get("ok",false))):
		return {"ok":false,"code":"DETERMINISM_RUN_FAILED","runs":[forward,replay,reverse_bodies,reverse_members]}
	return {
		"ok":true,"forward":forward,"replay":replay,"reverse_bodies":reverse_bodies,"reverse_members":reverse_members,
		"replay_state_error":Trajectory.state_error(forward,replay),
		"reverse_body_state_error":Trajectory.state_error(forward,reverse_bodies),
		"reverse_member_state_error":Trajectory.state_error(forward,reverse_members),
		"replay_event_error":Trajectory.event_time_error(forward,replay),
		"reverse_body_event_error":Trajectory.event_time_error(forward,reverse_bodies),
		"reverse_member_event_error":Trajectory.event_time_error(forward,reverse_members),
	}

static func under_refined_probe()->Dictionary:
	return Trajectory.run(1.0e-3)

static func fixed_point_bad_option_probe(code:String)->Dictionary:
	var bodies:=Trajectory._world()
	var event_set:=EventSet.next_appearance_event_set(bodies,0.0,0.55,1.0e-9,1.0e-9,256,64)
	if not bool(event_set.get("ok",false)):return event_set
	var options:Dictionary={"impact_options":{"max_event_uncertainty":1.0e-6,"max_boundary_gap":5.0e-6}}
	if code=="BAD_OUTER_TOLERANCE":options["outer_tolerance"]=0.0
	elif code=="BAD_OUTER_ITERATION_BUDGET":options["outer_iterations"]=0
	elif code=="BAD_OUTER_RELAXATION":options["outer_relaxation"]=1.5
	return FixedPoint.solve_event_set(bodies,event_set,0.3,{"mu_tangent":0.15,"mu_rolling":0.04,"mu_torsion":0.03},options)
