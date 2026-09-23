extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/smart_servo_graph_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/smart_servo_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/smart_servo_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/smart_servo_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const MotorDescriptor = preload("res://scripts/research/fabric_bake0/motor_generator_descriptor_v1.gd")
const GearDescriptor = preload("res://scripts/research/fabric_bake0/gearbox_descriptor_v1.gd")

const VERSION := "FABRIC_R5_2_T11_SMART_SERVO_COMPILER_R1"

static func compile(
	graph:Dictionary,request:Dictionary,capsule_id:String,
	motor_descriptor:Dictionary,gearbox_descriptor:Dictionary
)->Dictionary:
	var checked:=Graph.validate(graph)
	if not checked.success:return checked
	checked=MotorDescriptor.validate(motor_descriptor)
	if not checked.success:return checked
	checked=GearDescriptor.validate(gearbox_descriptor)
	if not checked.success:return checked
	if String(graph.motor_capsule.executable_descriptor_hash)!=String(motor_descriptor.checksum):
		return U.failure("SMART_SERVO_MOTOR_DESCRIPTOR_BINDING_MISMATCH")
	if String(graph.gearbox_capsule.executable_descriptor_hash)!=String(gearbox_descriptor.checksum):
		return U.failure("SMART_SERVO_GEARBOX_DESCRIPTOR_BINDING_MISMATCH")
	if typeof(request.get("canonical_source_frontier"))!=TYPE_DICTIONARY:
		return U.failure("SMART_SERVO_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound:=false
	for source in request.canonical_source_frontier.get("sources",[]):
		if String(source.get("source_domain",""))=="CONSTRUCTION" and String(source.get("source_hash",""))==String(graph.graph_hash):
			graph_bound=true
	if not graph_bound:return U.failure("SMART_SERVO_CANONICAL_GRAPH_SOURCE_MISMATCH")

	var ratio:=float(gearbox_descriptor.total_speed_ratio)
	var k:=float(motor_descriptor.torque_constant_nm_a)
	var max_current_from_gear:=float(gearbox_descriptor.max_abs_input_torque_nm)/k
	var max_current:=minf(float(motor_descriptor.max_abs_current_a),max_current_from_gear)
	var max_motor_omega:=minf(float(motor_descriptor.max_abs_angular_velocity_rad_s),float(gearbox_descriptor.max_abs_input_omega_rad_s))
	var interface:=Interface.create()
	if interface.is_empty():return U.failure("SMART_SERVO_INTERFACE_CREATE_FAILED")
	var source_components:=int(graph.motor_capsule.source_component_count)+int(graph.gearbox_capsule.source_component_count)+1
	var source_operations:=int(graph.motor_capsule.full_operation_count)+int(graph.gearbox_capsule.full_operation_count)+10
	var compiled_operations:=24
	var descriptor:=Descriptor.create({
		"graph_hash":graph.graph_hash,
		"interface_contract":interface,
		"motor_capsule_checksum":graph.motor_capsule.checksum,
		"gearbox_capsule_checksum":graph.gearbox_capsule.checksum,
		"gear_ratio":ratio,
		"motor_resistance_ohm":motor_descriptor.total_resistance_ohm,
		"torque_constant_nm_a":k,
		"motor_rotor_inertia_kg_m2":motor_descriptor.rotor_inertia_kg_m2,
		"gearbox_reflected_inertia_kg_m2":gearbox_descriptor.equivalent_input_inertia_kg_m2,
		"combined_input_inertia_kg_m2":float(motor_descriptor.rotor_inertia_kg_m2)+float(gearbox_descriptor.equivalent_input_inertia_kg_m2),
		"motor_child_max_abs_current_a":motor_descriptor.max_abs_current_a,
		"motor_child_max_abs_omega_rad_s":motor_descriptor.max_abs_angular_velocity_rad_s,
		"gearbox_child_max_abs_input_torque_nm":gearbox_descriptor.max_abs_input_torque_nm,
		"gearbox_child_max_abs_input_omega_rad_s":gearbox_descriptor.max_abs_input_omega_rad_s,
		"position_kp_nm_rad":graph.control_profile.position_kp_nm_rad,
		"velocity_kd_nm_s_rad":graph.control_profile.velocity_kd_nm_s_rad,
		"position_tolerance_rad":graph.control_profile.position_tolerance_rad,
		"velocity_tolerance_rad_s":graph.control_profile.velocity_tolerance_rad_s,
		"max_abs_current_a":max_current,
		"max_abs_motor_omega_rad_s":max_motor_omega,
		"max_abs_output_omega_rad_s":max_motor_omega*absf(ratio),
		"max_abs_output_torque_nm":k*max_current/absf(ratio),
		"source_component_count":source_components,
		"source_operation_count":source_operations,
		"compiled_operation_count":compiled_operations,
	})
	if descriptor.is_empty():return U.failure("SMART_SERVO_DESCRIPTOR_CREATE_FAILED")
	var artifact:=Artifact.create(
		String(request.get("artifact_id","")),request.canonical_source_frontier,
		request.authority_envelope,request.dependency_set,String(graph.graph_hash),
		interface,descriptor,int(request.get("build_generation",1))
	)
	if artifact.is_empty():return U.failure("SMART_SERVO_ARTIFACT_CREATE_FAILED")
	var provenance:=U.canonical_hash({
		"compiler_version":VERSION,"graph_hash":graph.graph_hash,
		"motor":graph.motor_capsule.checksum,"gearbox":graph.gearbox_capsule.checksum,
		"descriptor":descriptor.descriptor_hash,
	})
	var capsule:=Capsule.create(
		capsule_id,"SMART_SERVO","COUPLED_PD_MOTOR_GEARBOX",
		String(artifact.canonical_source_frontier.frontier_hash),String(graph.graph_hash),
		String(interface.interface_hash),"SMART_SERVO",String(artifact.checksum),
		String(descriptor.checksum),String(artifact.state_schema_hash),
		source_components,source_operations,compiled_operations,0,int(artifact.build_generation),
		["CLOSED_LOOP","HIERARCHICAL","MECHANICAL","STATEFUL"],provenance
	)
	if capsule.is_empty():return U.failure("SMART_SERVO_CAPSULE_CREATE_FAILED")
	return U.success({"descriptor":descriptor,"artifact":artifact,"capsule":capsule})
