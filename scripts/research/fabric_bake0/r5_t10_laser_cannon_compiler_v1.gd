extends RefCounted
## Hierarchical T10 compiler: compiled power/emitter/cooling capsules + optical train.

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_cannon_graph_v1.gd")
const Interface = preload("res://scripts/research/fabric_bake0/laser_cannon_interface_contract_v1.gd")
const Descriptor = preload("res://scripts/research/fabric_bake0/laser_cannon_descriptor_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/laser_cannon_execution_artifact_v1.gd")
const Capsule = preload("res://scripts/research/fabric_bake0/behavior_capsule_contract_v2.gd")
const PowerDescriptor = preload("res://scripts/research/fabric_bake0/power_stage_descriptor_v1.gd")
const EmitterDescriptor = preload("res://scripts/research/fabric_bake0/laser_emitter_descriptor_v1.gd")
const CoolingDescriptor = preload("res://scripts/research/fabric_bake0/cooling_loop_descriptor_v1.gd")

const VERSION := "FABRIC_R5_2_T10_LASER_CANNON_COMPILER_R1"

static func compile(
	graph:Dictionary,
	request:Dictionary,
	capsule_id:String,
	power_descriptor:Dictionary,
	emitter_descriptor:Dictionary,
	cooling_descriptor:Dictionary
)->Dictionary:
	var checked:=Graph.validate(graph)
	if not checked.success:return checked
	checked=PowerDescriptor.validate(power_descriptor)
	if not checked.success:return checked
	checked=EmitterDescriptor.validate(emitter_descriptor)
	if not checked.success:return checked
	checked=CoolingDescriptor.validate(cooling_descriptor)
	if not checked.success:return checked
	if String(graph.power_stage_capsule.executable_descriptor_hash)!=String(power_descriptor.checksum):
		return U.failure("LASER_CANNON_POWER_DESCRIPTOR_BINDING_MISMATCH")
	if String(graph.laser_emitter_capsule.executable_descriptor_hash)!=String(emitter_descriptor.checksum):
		return U.failure("LASER_CANNON_EMITTER_DESCRIPTOR_BINDING_MISMATCH")
	if String(graph.cooling_capsule.executable_descriptor_hash)!=String(cooling_descriptor.checksum):
		return U.failure("LASER_CANNON_COOLING_DESCRIPTOR_BINDING_MISMATCH")
	if typeof(request.get("canonical_source_frontier"))!=TYPE_DICTIONARY:
		return U.failure("LASER_CANNON_CANONICAL_FRONTIER_REQUIRED")
	var graph_bound:=false
	var matter_bound:=false
	for source in request.canonical_source_frontier.get("sources",[]):
		if String(source.get("source_domain",""))=="CONSTRUCTION" and String(source.get("source_hash",""))==String(graph.graph_hash):
			graph_bound=true
		if String(source.get("source_domain",""))=="MATTER" and String(source.get("source_hash",""))==String(graph.material_catalog.catalog_hash):
			matter_bound=true
	if not graph_bound:return U.failure("LASER_CANNON_CANONICAL_GRAPH_SOURCE_MISMATCH")
	if not matter_bound:return U.failure("LASER_CANNON_CANONICAL_MATERIAL_SOURCE_MISMATCH")

	var expansion:=float(graph.output_focal_length_m)/float(graph.input_focal_length_m)
	var output_area:=PI*pow(float(graph.clear_aperture_diameter_m)*0.5,2.0)
	var input_area:=output_area/pow(expansion,2.0)
	var emitter_area:=float(emitter_descriptor.effective_aperture_area_m2)
	if input_area+1.0e-18<emitter_area:
		return U.failure("LASER_CANNON_INPUT_APERTURE_CLIPS_EMITTER",{"input_area_m2":input_area,"emitter_area_m2":emitter_area})
	var interface:=Interface.create()
	if interface.is_empty():return U.failure("LASER_CANNON_INTERFACE_CREATE_FAILED")
	var surface_t:=float(graph.optics_profile.surface_transmission_ratio)
	var total_t:=pow(surface_t,4.0)
	var source_components:=5
	var source_operations:=(
		int(graph.power_stage_capsule.executable_operation_count)
		+int(graph.laser_emitter_capsule.executable_operation_count)
		+int(graph.cooling_capsule.executable_operation_count)
		+8
	)
	var compiled_operations:=24
	var descriptor:=Descriptor.create({
		"graph_hash":graph.graph_hash,
		"interface_contract":interface,
		"power_stage_capsule_checksum":graph.power_stage_capsule.checksum,
		"laser_emitter_capsule_checksum":graph.laser_emitter_capsule.checksum,
		"cooling_capsule_checksum":graph.cooling_capsule.checksum,
		"optics_surface_transmission_ratio":surface_t,
		"optics_total_transmission_ratio":total_t,
		"optical_expansion_ratio":expansion,
		"emitter_aperture_area_m2":emitter_area,
		"input_clear_aperture_area_m2":input_area,
		"output_clear_aperture_area_m2":output_area,
		"clear_aperture_diameter_m":graph.clear_aperture_diameter_m,
		"max_surface_fluence_j_m2":graph.optics_profile.max_surface_fluence_j_m2,
		"source_component_count":source_components,
		"source_operation_count":source_operations,
		"compiled_operation_count":compiled_operations,
	})
	if descriptor.is_empty():return U.failure("LASER_CANNON_DESCRIPTOR_CREATE_FAILED")
	var artifact:=Artifact.create(
		String(request.get("artifact_id","")),
		request.canonical_source_frontier,
		request.authority_envelope,
		request.dependency_set,
		String(graph.graph_hash),
		String(graph.material_catalog.catalog_hash),
		interface,
		descriptor,
		int(request.get("build_generation",1))
	)
	if artifact.is_empty():return U.failure("LASER_CANNON_ARTIFACT_CREATE_FAILED")
	var provenance:=U.canonical_hash({
		"compiler_version":VERSION,
		"graph_hash":graph.graph_hash,
		"power":graph.power_stage_capsule.checksum,
		"emitter":graph.laser_emitter_capsule.checksum,
		"cooling":graph.cooling_capsule.checksum,
		"descriptor":descriptor.descriptor_hash,
	})
	var capsule:=Capsule.create(
		capsule_id,
		"LASER_CANNON",
		"HIERARCHICAL_POWER_EMITTER_COOLING_OPTICS",
		String(artifact.canonical_source_frontier.frontier_hash),
		String(graph.graph_hash),
		String(interface.interface_hash),
		"LASER_CANNON",
		String(artifact.checksum),
		String(descriptor.checksum),
		String(artifact.state_schema_hash),
		source_components,
		source_operations,
		compiled_operations,
		0,
		int(artifact.build_generation),
		["HIERARCHICAL","OPTICAL","POWERED","STATEFUL","THERMAL"],
		provenance
	)
	if capsule.is_empty():return U.failure("LASER_CANNON_CAPSULE_CREATE_FAILED")
	return U.success({"descriptor":descriptor,"artifact":artifact,"capsule":capsule})

