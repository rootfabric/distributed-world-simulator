extends RefCounted
## Coupled motor+gearbox servo solver. Persistent state remains caller-owned.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/smart_servo_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/smart_servo_descriptor_v1.gd")

var _ready:=false
var _capsule_id:=""
var _frontier_hash:=""
var _authority_checksum:=""
var _dependency_hash:=""
var _graph_hash:=""
var _interface_hash:=""
var _ratio:=0.0
var _r:=0.0
var _k:=0.0
var _j:=0.0
var _kp:=0.0
var _kd:=0.0
var _pos_tol:=0.0
var _vel_tol:=0.0
var _max_current:=0.0
var _max_motor_omega:=0.0

func prepare(capsule:Dictionary,artifact:Dictionary,descriptor:Dictionary,live:Dictionary)->Dictionary:
	_ready=false
	var checked:=Capsule.validate(capsule)
	if not checked.success:return checked
	checked=Artifact.verify_descriptor(artifact,descriptor)
	if not checked.success:return checked
	checked=Descriptor.validate(descriptor)
	if not checked.success:return checked
	if String(capsule.executable_artifact_kind)!="SMART_SERVO" or String(capsule.executable_artifact_checksum)!=String(artifact.checksum):
		return U.failure("SMART_SERVO_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	if String(capsule.executable_descriptor_hash)!=String(descriptor.checksum):
		return U.failure("SMART_SERVO_RUNTIME_CAPSULE_DESCRIPTOR_MISMATCH")
	if int(capsule.runtime_source_traversals_per_execute)!=0:
		return U.failure("SMART_SERVO_RUNTIME_SOURCE_TRAVERSAL_CONTRACT_INVALID")
	checked=_full_live_gate(artifact,live)
	if not checked.success:return checked
	_capsule_id=String(capsule.capsule_id)
	_frontier_hash=String(artifact.canonical_source_frontier.frontier_hash)
	_authority_checksum=String(artifact.authority_envelope.checksum)
	_dependency_hash=String(artifact.dependency_set.dependency_hash)
	_graph_hash=String(artifact.graph_hash)
	_interface_hash=String(artifact.interface_contract.interface_hash)
	_ratio=float(descriptor.gear_ratio)
	_r=float(descriptor.motor_resistance_ohm)
	_k=float(descriptor.torque_constant_nm_a)
	_j=float(descriptor.combined_input_inertia_kg_m2)
	_kp=float(descriptor.position_kp_nm_rad)
	_kd=float(descriptor.velocity_kd_nm_s_rad)
	_pos_tol=float(descriptor.position_tolerance_rad)
	_vel_tol=float(descriptor.velocity_tolerance_rad_s)
	_max_current=float(descriptor.max_abs_current_a)
	_max_motor_omega=float(descriptor.max_abs_motor_omega_rad_s)
	_ready=true
	return U.success({"capsule_id":_capsule_id,"state_scalar_count":2,"runtime_source_component_traversals":0})

func initial_state(output_position_rad:float=0.0,output_velocity_rad_s:float=0.0)->Dictionary:
	if not _ready or not U.is_finite_number(output_position_rad) or not U.is_finite_number(output_velocity_rad_s):
		return {}
	var motor_omega:=output_velocity_rad_s/_ratio
	if absf(motor_omega)>_max_motor_omega:return {}
	return {"output_position_rad":output_position_rad,"motor_angular_velocity_rad_s":motor_omega}

func execute(
	live:Dictionary,state:Dictionary,target_position_rad:float,target_velocity_rad_s:float,
	external_output_torque_nm:float,dt_s:float
)->Dictionary:
	if not _ready:return U.failure("SMART_SERVO_RUNTIME_NOT_READY")
	var checked:=_fast_live_gate(live)
	if not checked.success:return checked
	for value in [target_position_rad,target_velocity_rad_s,external_output_torque_nm]:
		if not U.is_finite_number(value):return U.failure("SMART_SERVO_RUNTIME_COMMAND_INVALID")
	if not U.is_positive_number(dt_s):return U.failure("SMART_SERVO_RUNTIME_STEP_INVALID")
	if not U.is_finite_number(state.get("output_position_rad")) or not U.is_finite_number(state.get("motor_angular_velocity_rad_s")):
		return U.failure("SMART_SERVO_RUNTIME_STATE_INVALID")
	var position:=float(state.output_position_rad)
	var motor_omega:=float(state.motor_angular_velocity_rad_s)
	if absf(motor_omega)>_max_motor_omega:return U.failure("SMART_SERVO_RUNTIME_SPEED_OUT_OF_DOMAIN")
	var output_omega:=motor_omega*_ratio
	var position_error:=target_position_rad-position
	var velocity_error:=target_velocity_rad_s-output_omega
	var requested_output_torque:=_kp*position_error+_kd*velocity_error
	var requested_input_torque:=requested_output_torque*_ratio
	var requested_current:=requested_input_torque/_k
	var current:=clampf(requested_current,-_max_current,_max_current)
	var saturated:=absf(requested_current)>_max_current+1.0e-12
	var electromagnetic_torque:=_k*current
	var reflected_external_torque:=external_output_torque_nm*_ratio
	var net_input_torque:=electromagnetic_torque+reflected_external_torque
	var next_motor_omega:=motor_omega+net_input_torque*dt_s/_j
	if not is_finite(next_motor_omega) or absf(next_motor_omega)>_max_motor_omega:
		return U.failure("SMART_SERVO_RUNTIME_NEXT_SPEED_OUT_OF_DOMAIN",{"motor_omega_rad_s":next_motor_omega})
	var midpoint_motor_omega:=0.5*(motor_omega+next_motor_omega)
	var midpoint_output_omega:=midpoint_motor_omega*_ratio
	var next_position:=position+midpoint_output_omega*dt_s
	var terminal_voltage:=current*_r+_k*midpoint_motor_omega
	var electrical_energy:=terminal_voltage*current*dt_s
	var resistive_heat:=current*current*_r*dt_s
	var output_boundary_energy:=external_output_torque_nm*midpoint_output_omega*dt_s
	var kinetic_delta:=0.5*_j*(next_motor_omega*next_motor_omega-motor_omega*motor_omega)
	var residual:=electrical_energy+output_boundary_energy-resistive_heat-kinetic_delta
	var next_output_omega:=next_motor_omega*_ratio
	var settled:=absf(target_position_rad-next_position)<=_pos_tol and absf(target_velocity_rad_s-next_output_omega)<=_vel_tol
	return U.success({
		"capsule_id":_capsule_id,
		"current_command_a":current,
		"requested_current_a":requested_current,
		"current_command_saturated":saturated,
		"output_torque_command_nm":current*_k/_ratio,
		"terminal_voltage_v":terminal_voltage,
		"electrical_energy_j":electrical_energy,
		"resistive_heat_j":resistive_heat,
		"output_boundary_energy_j":output_boundary_energy,
		"kinetic_energy_delta_j":kinetic_delta,
		"energy_residual_j":residual,
		"output_position_rad":next_position,
		"output_velocity_rad_s":next_output_omega,
		"settled":settled,
		"next_state":{"output_position_rad":next_position,"motor_angular_velocity_rad_s":next_motor_omega},
		"runtime_source_component_traversals":0,
	})

func _full_live_gate(artifact:Dictionary,live:Dictionary)->Dictionary:
	if String(live.get("artifact_state",""))!="READY":return U.failure("SMART_SERVO_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations"))!=TYPE_ARRAY or not live.invalidations.is_empty():return U.failure("SMART_SERVO_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier"))!=TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash",""))!=String(artifact.canonical_source_frontier.frontier_hash):return U.failure("SMART_SERVO_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope"))!=TYPE_DICTIONARY or String(live.authority_envelope.get("checksum",""))!=String(artifact.authority_envelope.checksum):return U.failure("SMART_SERVO_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set"))!=TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash",""))!=String(artifact.dependency_set.dependency_hash):return U.failure("SMART_SERVO_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash",""))!=String(artifact.graph_hash):return U.failure("SMART_SERVO_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("interface_hash",""))!=String(artifact.interface_contract.interface_hash):return U.failure("SMART_SERVO_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live:Dictionary)->Dictionary:
	if String(live.get("artifact_state",""))!="READY":return U.failure("SMART_SERVO_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations"))!=TYPE_ARRAY or not live.invalidations.is_empty():return U.failure("SMART_SERVO_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier"))!=TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash",""))!=_frontier_hash:return U.failure("SMART_SERVO_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope"))!=TYPE_DICTIONARY or String(live.authority_envelope.get("checksum",""))!=_authority_checksum:return U.failure("SMART_SERVO_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set"))!=TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash",""))!=_dependency_hash:return U.failure("SMART_SERVO_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash",""))!=_graph_hash:return U.failure("SMART_SERVO_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("interface_hash",""))!=_interface_hash:return U.failure("SMART_SERVO_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
