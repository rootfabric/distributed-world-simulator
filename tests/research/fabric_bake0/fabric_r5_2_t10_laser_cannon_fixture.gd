extends RefCounted

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const MatterMaterial = preload("res://scripts/simulation/matter/contracts/matter_material_definition.gd")
const MatterCatalog = preload("res://scripts/simulation/matter/catalog/matter_material_catalog.gd")
const OpticsProfile = preload("res://scripts/research/fabric_bake0/laser_cannon_optics_profile_v1.gd")
const Graph = preload("res://scripts/research/fabric_bake0/laser_cannon_graph_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const Authority = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const Dependencies = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")

const PowerCompiler = preload("res://scripts/research/fabric_bake0/r5_t6_power_stage_compiler_v1.gd")
const PowerFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t6_power_stage_fixture.gd")
const EmitterCompiler = preload("res://scripts/research/fabric_bake0/r5_t9_laser_emitter_compiler_v1.gd")
const EmitterFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t9_laser_emitter_fixture.gd")
const CoolingCompiler = preload("res://scripts/research/fabric_bake0/r5_t8_cooling_loop_compiler_v1.gd")
const CoolingFixture = preload("res://tests/research/fabric_bake0/fabric_r5_2_t8_cooling_fixture.gd")

const COMPILER_VERSION := "FABRIC_R5_2_T10_LASER_CANNON_COMPILER_R1"

static func optics_material_catalog() -> Dictionary:
	var material := MatterMaterial.create({
		"material_id":"matter/laser-optics-silica",
		"display_name":"Silica-like laser optics",
		"family":"matter-family/optical-glass",
		"phase":"SOLID",
		"density_kg_m3":2200.0,
		"hardness_pa":6.0e9,
		"compressive_strength_pa":1.0e9,
		"tensile_strength_pa":5.0e7,
		"fracture_toughness_pa_m_sqrt":8.0e5,
		"cohesion_pa":1.0e8,
		"abrasiveness_ratio":0.1,
		"porosity_ratio":0.0001,
		"permeability_m2":1.0e-24,
		"heat_capacity_j_kg_k":740.0,
		"thermal_conductivity_w_m_k":1.4,
		"melting_temperature_k":1900.0,
		"vaporization_temperature_k":3000.0,
		"mining_energy_j_kg":9.0e5,
		"tags":["matter-tag/optical","matter-tag/structural"],
	})
	return MatterCatalog.create([material],"matter-catalog/r5-t10-optics","1.0.0")

static func compile_subsystems() -> Dictionary:
	var power_graph:=PowerFixture.make_graph()
	var power:=PowerCompiler.compile(power_graph,PowerFixture.build_request(power_graph),"capsule/r5-t10-power")
	if not power.success:return power
	var emitter_graph:=EmitterFixture.make_graph()
	var emitter:=EmitterCompiler.compile(emitter_graph,EmitterFixture.build_request(emitter_graph),"capsule/r5-t10-emitter")
	if not emitter.success:return emitter
	var cooling_graph:=CoolingFixture.make_graph()
	var cooling:=CoolingCompiler.compile(cooling_graph,CoolingFixture.build_request(cooling_graph),"capsule/r5-t10-cooling")
	if not cooling.success:return cooling
	return U.success({
		"power":power.details,
		"emitter":emitter.details,
		"cooling":cooling.details,
	})

static func make_graph(
	subsystems:Dictionary,
	surface_transmission:float=0.995,
	max_surface_fluence_j_m2:float=50000.0,
	output_aperture_diameter_m:float=0.12,
	input_focal_length_m:float=0.05,
	output_focal_length_m:float=0.20
)->Dictionary:
	var catalog:=optics_material_catalog()
	var material:=MatterCatalog.material_by_id(catalog,"matter/laser-optics-silica")
	var profile:=OpticsProfile.create(
		"profile/laser-cannon-silica-ar",
		material,
		surface_transmission,
		max_surface_fluence_j_m2,
		250.0,
		600.0
	)
	return Graph.create({
		"graph_id":"graph/r5-t10-laser-cannon",
		"material_catalog":catalog,
		"optics_profile":profile,
		"power_stage_capsule":subsystems.power.capsule,
		"laser_emitter_capsule":subsystems.emitter.capsule,
		"cooling_capsule":subsystems.cooling.capsule,
		"input_focal_length_m":input_focal_length_m,
		"output_focal_length_m":output_focal_length_m,
		"clear_aperture_diameter_m":output_aperture_diameter_m,
		"optics_temperature_k":300.0,
	})

static func build_request(graph:Dictionary,subsystems:Dictionary,revision:int=0)->Dictionary:
	var dependency_hash:=U.canonical_hash({"dependency":"r5-t10-laser-cannon"})
	var construction:=SourceRevision.create(
		"CONSTRUCTION","construct/r5-t10-laser-cannon",23,1000+revision,
		String(graph.graph_hash),dependency_hash
	)
	var matter:=SourceRevision.create(
		"MATTER","matter/r5-t10-optics",23,1,
		String(graph.material_catalog.catalog_hash),dependency_hash
	)
	var frontier:=Frontier.create([construction,matter])
	var authority:=Authority.create(
		"server/fabric-r5",
		[
			{"source_domain":"CONSTRUCTION","source_id":"construct/r5-t10-laser-cannon","authority_epoch":23,"owner_id":"server/fabric-r5"},
			{"source_domain":"MATTER","source_id":"matter/r5-t10-optics","authority_epoch":23,"owner_id":"server/fabric-r5"},
		],
		[
			U.source_key("CONSTRUCTION","construct/r5-t10-laser-cannon"),
			U.source_key("MATTER","matter/r5-t10-optics"),
		]
	)
	var dependencies:=Dependencies.create([
		{"dependency_id":"dependency/r5-t10-compiler","dependency_hash":U.canonical_hash({"version":COMPILER_VERSION})},
		{"dependency_id":"dependency/r5-t10-power","dependency_hash":String(subsystems.power.capsule.checksum)},
		{"dependency_id":"dependency/r5-t10-emitter","dependency_hash":String(subsystems.emitter.capsule.checksum)},
		{"dependency_id":"dependency/r5-t10-cooling","dependency_hash":String(subsystems.cooling.capsule.checksum)},
	])
	return {
		"artifact_id":"artifact/r5-t10-laser-cannon",
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

static func subsystem_bundle(details:Dictionary,kind:String)->Dictionary:
	var live:Dictionary
	if kind=="power":
		live=PowerFixture.live_from(details.artifact)
	elif kind=="emitter":
		live=EmitterFixture.live_from(details.artifact)
	else:
		live=CoolingFixture.live_from(details.artifact)
	return {
		"capsule":details.capsule,
		"artifact":details.artifact,
		"descriptor":details.descriptor,
		"live":live,
	}
