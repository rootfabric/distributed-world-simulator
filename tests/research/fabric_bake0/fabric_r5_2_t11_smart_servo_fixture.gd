extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const ServoControl = preload("res://scripts/research/fabric_bake0/smart_servo_control_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/smart_servo_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const MotorCompiler = preload("res://scripts/research/fabric_bake0/r5_t5_motor_generator_compiler_v1.gd")
const MotorFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t5_motor_generator_fixture.gd")
const GearCompiler = preload("res://scripts/research/fabric_bake0/r5_t7_gearbox_compiler_v1.gd")
const GearFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t7_gearbox_fixture.gd")

const COMPILER_VERSION := "FABRIC_R5_2_T11_SMART_SERVO_COMPILER_R1"

static func compile_subsystems(
	motor_quality_scale:float=1.0,
	gear_material_kind:String="STEEL"
)->Dictionary:
	var motor_graph:=MotorFixture.make_graph(motor_quality_scale)
	var motor:=MotorCompiler.compile(motor_graph,MotorFixture.build_request(motor_graph),"capsule/r5-t11-motor")
	if not motor.success:return motor
	var gear_graph:=GearFixture.make_graph(gear_material_kind)
	var gear:=GearCompiler.compile(gear_graph,GearFixture.build_request(gear_graph),"capsule/r5-t11-gearbox")
	if not gear.success:return gear
	return U.success({"motor":motor.details,"gearbox":gear.details})

static func control_profile(kp:float=100.0,kd:float=60.0)->Dictionary:
	return ServoControl.create("profile/r5-t11-servo-pd",kp,kd,0.002,0.01)

static func make_graph(subsystems:Dictionary,kp:float=100.0,kd:float=60.0)->Dictionary:
	return Graph.create(
		"graph/r5-t11-smart-servo",
		subsystems.motor.capsule,
		subsystems.gearbox.capsule,
		control_profile(kp,kd)
	)

static func build_request(graph:Dictionary,subsystems:Dictionary,revision:int=0)->Dictionary:
	var dependency_hash:=U.canonical_hash({"dependency":"r5-t11-smart-servo"})
	var construction:=SourceRevision.create(
		"CONSTRUCTION","construct/r5-t11-smart-servo",24,1100+revision,
		String(graph.graph_hash),dependency_hash
	)
	var frontier:=Frontier.create([construction])
	var authority:=Authority.create(
		"server/fabric-r5",
		[
			{"source_domain":"CONSTRUCTION","source_id":"construct/r5-t11-smart-servo","authority_epoch":24,"owner_id":"server/fabric-r5"},
		],
		[U.source_key("CONSTRUCTION","construct/r5-t11-smart-servo")]
	)
	var dependencies:=Dependencies.create([
		{"dependency_id":"dependency/r5-t11-compiler","dependency_hash":U.canonical_hash({"version":COMPILER_VERSION})},
		{"dependency_id":"dependency/r5-t11-motor","dependency_hash":String(subsystems.motor.capsule.checksum)},
		{"dependency_id":"dependency/r5-t11-gearbox","dependency_hash":String(subsystems.gearbox.capsule.checksum)},
	])
	return {
		"artifact_id":"artifact/r5-t11-smart-servo",
		"canonical_source_frontier":frontier,
		"authority_envelope":authority,
		"dependency_set":dependencies,
		"build_generation":1+revision,
	}

static func live_from(artifact:Dictionary)->Dictionary:
	return {
		"artifact_state":"READY",
		"invalidations":[],
		"canonical_source_frontier":artifact.canonical_source_frontier.duplicate(true),
		"authority_envelope":artifact.authority_envelope.duplicate(true),
		"dependency_set":artifact.dependency_set.duplicate(true),
		"graph_hash":String(artifact.graph_hash),
		"interface_hash":String(artifact.interface_contract.interface_hash),
	}
