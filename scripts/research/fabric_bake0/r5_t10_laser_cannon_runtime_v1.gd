extends RefCounted
## Hierarchical T10 runtime. Persistent state is only the caller-owned T8 cooling state.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/laser_cannon_execution_artifact_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/laser_cannon_descriptor_v1.gd")
const PowerRuntime = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_runtime_v1.gd")
const EmitterRuntime = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_runtime_v1.gd")
const CoolingRuntime = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_runtime_v1.gd")

var _ready:=false
var _frontier_hash:=""
var _authority_checksum:=""
var _dependency_hash:=""
var _graph_hash:=""
var _interface_hash:=""
var _capsule_id:=""
var _descriptor:Dictionary={}
var _power_descriptor:Dictionary={}
var _power_live:Dictionary={}
var _emitter_live:Dictionary={}
var _cooling_live:Dictionary={}
var _power
var _emitter
var _cooling

func prepare(
	capsule:Dictionary,
	artifact:Dictionary,
	descriptor:Dictionary,
	live:Dictionary,
	power_bundle:Dictionary,
	emitter_bundle:Dictionary,
	cooling_bundle:Dictionary
)->Dictionary:
	_ready=false
	var checked:=Capsule.validate(capsule)
	if not checked.success:return checked
	checked=Artifact.verify_descriptor(artifact,descriptor)
	if not checked.success:return checked
	checked=Descriptor.validate(descriptor)
	if not checked.success:return checked
	if String(capsule.executable_artifact_kind)!="LASER_CANNON" or String(capsule.executable_artifact_checksum)!=String(artifact.checksum):
		return U.failure("LASER_CANNON_RUNTIME_CAPSULE_ARTIFACT_MISMATCH")
	checked=_full_live_gate(artifact,live)
	if not checked.success:return checked
	for pair in [
		["power",power_bundle],["emitter",emitter_bundle],["cooling",cooling_bundle]
	]:
		if typeof(pair[1])!=TYPE_DICTIONARY:
			return U.failure("LASER_CANNON_RUNTIME_SUBSYSTEM_BUNDLE_INVALID",{"bundle":String(pair[0])})
	if String(power_bundle.capsule.checksum)!=String(descriptor.power_stage_capsule_checksum):
		return U.failure("LASER_CANNON_RUNTIME_POWER_CAPSULE_MISMATCH")
	if String(emitter_bundle.capsule.checksum)!=String(descriptor.laser_emitter_capsule_checksum):
		return U.failure("LASER_CANNON_RUNTIME_EMITTER_CAPSULE_MISMATCH")
	if String(cooling_bundle.capsule.checksum)!=String(descriptor.cooling_capsule_checksum):
		return U.failure("LASER_CANNON_RUNTIME_COOLING_CAPSULE_MISMATCH")

	_power=PowerRuntime.new()
	checked=_power.prepare(power_bundle.capsule,power_bundle.artifact,power_bundle.descriptor,power_bundle.live)
	if not checked.success:return checked
	_emitter=EmitterRuntime.new()
	checked=_emitter.prepare(emitter_bundle.capsule,emitter_bundle.artifact,emitter_bundle.descriptor,emitter_bundle.live)
	if not checked.success:return checked
	_cooling=CoolingRuntime.new()
	checked=_cooling.prepare(cooling_bundle.capsule,cooling_bundle.artifact,cooling_bundle.descriptor,cooling_bundle.live)
	if not checked.success:return checked

	_capsule_id=String(capsule.capsule_id)
	_frontier_hash=String(artifact.canonical_source_frontier.frontier_hash)
	_authority_checksum=String(artifact.authority_envelope.checksum)
	_dependency_hash=String(artifact.dependency_set.dependency_hash)
	_graph_hash=String(artifact.graph_hash)
	_interface_hash=String(artifact.interface_contract.interface_hash)
	_descriptor=descriptor.duplicate(true)
	_power_descriptor=power_bundle.descriptor.duplicate(true)
	_power_live=power_bundle.live.duplicate(true)
	_emitter_live=emitter_bundle.live.duplicate(true)
	_cooling_live=cooling_bundle.live.duplicate(true)
	_ready=true
	return U.success({"capsule_id":_capsule_id,"state_scalar_count":4,"runtime_source_component_traversals":0})

func initial_state(temperature_k:float)->Dictionary:
	if not _ready:return {}
	return _cooling.initial_state(temperature_k)

func execute(
	live:Dictionary,
	state:Dictionary,
	bus_voltage_v:float,
	current_a:float,
	pwm_frequency_hz:float,
	mass_flow_kg_s:float,
	ambient_temperature_k:float,
	target_range_m:float,
	dt_s:float
)->Dictionary:
	if not _ready:return U.failure("LASER_CANNON_RUNTIME_NOT_READY")
	var checked:=_fast_live_gate(live)
	if not checked.success:return checked
	if not U.is_positive_number(bus_voltage_v) or not U.is_non_negative_number(current_a) or not U.is_non_negative_number(pwm_frequency_hz) or not U.is_non_negative_number(mass_flow_kg_s) or not U.is_positive_number(ambient_temperature_k) or not U.is_non_negative_number(target_range_m) or not U.is_positive_number(dt_s):
		return U.failure("LASER_CANNON_RUNTIME_STEP_INVALID")
	if not U.is_positive_number(state.get("plate_temperature_k")):
		return U.failure("LASER_CANNON_RUNTIME_STATE_INVALID")
	var junction_t:=float(state.plate_temperature_k)
	var emitter:=_emitter.execute(_emitter_live,current_a,junction_t,dt_s)
	if not emitter.success:return emitter

	var alpha:=float(_power_descriptor.resistance_temp_coefficient_per_k)
	var factor:=1.0+alpha*(junction_t-float(_power_descriptor.reference_temperature_k))
	var path_r:=float(_power_descriptor.positive_path_resistance_ref_ohm)*maxf(factor,0.05)
	var duty:=(float(emitter.details.terminal_voltage_v)+current_a*path_r)/bus_voltage_v
	if duty<0.0 or duty>1.0:
		return U.failure("LASER_CANNON_RUNTIME_BUS_HEADROOM_INSUFFICIENT",{"required_duty":duty})
	var stage:=_power.execute(_power_live,bus_voltage_v,duty,current_a,pwm_frequency_hz,junction_t,dt_s)
	if not stage.success:return stage
	if absf(float(stage.details.load_voltage_v)-float(emitter.details.terminal_voltage_v))>1.0e-9:
		return U.failure("LASER_CANNON_RUNTIME_ELECTRICAL_VOLTAGE_MISMATCH")
	if absf(float(stage.details.electrical_output_energy_j)-float(emitter.details.electrical_energy_j))>1.0e-9:
		return U.failure("LASER_CANNON_RUNTIME_ELECTRICAL_ENERGY_MISMATCH")

	var input_surface_fluence:=float(emitter.details.optical_energy_j)/float(_descriptor.emitter_aperture_area_m2)
	var output_surface_energy:=float(emitter.details.optical_energy_j)*pow(float(_descriptor.optics_surface_transmission_ratio),2.0)
	var output_surface_fluence:=output_surface_energy/float(_descriptor.output_clear_aperture_area_m2)
	var max_surface_fluence:=maxf(input_surface_fluence,output_surface_fluence)
	if max_surface_fluence>float(_descriptor.max_surface_fluence_j_m2):
		return U.failure("LASER_CANNON_RUNTIME_OPTICS_FLUENCE_LIMIT",{"fluence_j_m2":max_surface_fluence,"limit_j_m2":_descriptor.max_surface_fluence_j_m2})
	var muzzle_energy:=float(emitter.details.optical_energy_j)*float(_descriptor.optics_total_transmission_ratio)
	var optics_heat:=float(emitter.details.optical_energy_j)-muzzle_energy
	var output_divergence:=float(emitter.details.beam_divergence_half_angle_rad)/float(_descriptor.optical_expansion_ratio)
	var output_radius:=0.5*float(_descriptor.clear_aperture_diameter_m)
	var spot_radius:=sqrt(output_radius*output_radius+pow(target_range_m*output_divergence,2.0))
	var spot_area:=PI*spot_radius*spot_radius
	var spot_fluence:=muzzle_energy/spot_area if spot_area>0.0 else 0.0

	var stage_heat:=float(stage.details.conduction_heat_j)+float(stage.details.switching_heat_j)
	var total_heat:=stage_heat+float(emitter.details.waste_heat_j)+optics_heat
	var cooling:=_cooling.execute(_cooling_live,state,total_heat/dt_s,mass_flow_kg_s,ambient_temperature_k,dt_s)
	if not cooling.success:return cooling
	var total_residual:=(
		float(stage.details.electrical_input_energy_j)
		+float(cooling.details.pump_hydraulic_energy_j)
		-muzzle_energy
		-float(cooling.details.ambient_exchange_j)
		-float(cooling.details.state_energy_delta_j)
	)
	return U.success({
		"capsule_id":_capsule_id,
		"duty_ratio":duty,
		"bus_current_a":stage.details.bus_current_a,
		"bus_input_energy_j":stage.details.electrical_input_energy_j,
		"muzzle_optical_energy_j":muzzle_energy,
		"optics_absorbed_heat_j":optics_heat,
		"total_internal_heat_j":total_heat,
		"cooling_pump_hydraulic_energy_j":cooling.details.pump_hydraulic_energy_j,
		"beam_divergence_half_angle_rad":output_divergence,
		"spot_radius_m":spot_radius,
		"spot_fluence_j_m2":spot_fluence,
		"wavelength_m":emitter.details.wavelength_m,
		"energy_residual_j":total_residual,
		"next_state":cooling.details.next_state,
		"runtime_source_component_traversals":0,
		"subsystem_runtime_source_traversals":{
			"power_stage":stage.details.runtime_source_die_traversals,
			"laser_emitter":emitter.details.runtime_source_cell_traversals,
			"cooling":cooling.details.runtime_source_thermal_node_traversals,
		},
	})

func _full_live_gate(artifact:Dictionary,live:Dictionary)->Dictionary:
	if String(live.get("artifact_state",""))!="READY":return U.failure("LASER_CANNON_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations"))!=TYPE_ARRAY or not live.invalidations.is_empty():return U.failure("LASER_CANNON_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier"))!=TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash",""))!=String(artifact.canonical_source_frontier.frontier_hash):return U.failure("LASER_CANNON_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope"))!=TYPE_DICTIONARY or String(live.authority_envelope.get("checksum",""))!=String(artifact.authority_envelope.checksum):return U.failure("LASER_CANNON_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set"))!=TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash",""))!=String(artifact.dependency_set.dependency_hash):return U.failure("LASER_CANNON_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash",""))!=String(artifact.graph_hash):return U.failure("LASER_CANNON_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("interface_hash",""))!=String(artifact.interface_contract.interface_hash):return U.failure("LASER_CANNON_RUNTIME_INTERFACE_MISMATCH")
	return U.success()

func _fast_live_gate(live:Dictionary)->Dictionary:
	if String(live.get("artifact_state",""))!="READY":return U.failure("LASER_CANNON_RUNTIME_ARTIFACT_NOT_READY")
	if typeof(live.get("invalidations"))!=TYPE_ARRAY or not live.invalidations.is_empty():return U.failure("LASER_CANNON_RUNTIME_INVALIDATED")
	if typeof(live.get("canonical_source_frontier"))!=TYPE_DICTIONARY or String(live.canonical_source_frontier.get("frontier_hash",""))!=_frontier_hash:return U.failure("LASER_CANNON_RUNTIME_FRONTIER_MISMATCH")
	if typeof(live.get("authority_envelope"))!=TYPE_DICTIONARY or String(live.authority_envelope.get("checksum",""))!=_authority_checksum:return U.failure("LASER_CANNON_RUNTIME_AUTHORITY_MISMATCH")
	if typeof(live.get("dependency_set"))!=TYPE_DICTIONARY or String(live.dependency_set.get("dependency_hash",""))!=_dependency_hash:return U.failure("LASER_CANNON_RUNTIME_DEPENDENCY_MISMATCH")
	if String(live.get("graph_hash",""))!=_graph_hash:return U.failure("LASER_CANNON_RUNTIME_GRAPH_MISMATCH")
	if String(live.get("interface_hash",""))!=_interface_hash:return U.failure("LASER_CANNON_RUNTIME_INTERFACE_MISMATCH")
	return U.success()
