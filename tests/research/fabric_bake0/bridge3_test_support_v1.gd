extends RefCounted
const F = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")
const C = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const H = preload("res://scripts/research/fabric_bake0/bridge3_rigid_handoff_v1.gd")
const AB = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const G = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")
const L = preload("res://scripts/research/fabric_bake0/structural_local_unbake_compiler_v1.gd")
const R = preload("res://scripts/research/fabric_bake0/structural_reconstruction_mapping_v1.gd")
const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")

static func build(count: int) -> Dictionary:
	var subject := F.build(count)
	if not subject.success:
		return subject
	var bundle := Lifecycle.compile(subject.view_request, F.lifecycle_options(subject))
	if not bundle.get("success", false):
		return bundle
	var ag: Dictionary = bundle.aggregate
	var capacities := F._capacity_specs(subject, ag.descriptor)
	var guard := G.compile({"field_id": "guard-field/bridge3-local", "source_frontier_hash": subject.frontier.frontier_hash,
		"structural_descriptor": ag.descriptor, "reconstruction_mapping": ag.reconstruction_mapping,
		"parts": subject.parts, "bonds": subject.bonds, "root_part_id": "part/b0-2-0000",
		"bond_capacity_specs": capacities, "capacity_certificate_hash": F._capacity_hash(subject.frontier.frontier_hash, capacities),
		"trigger_ratio": F.TRIGGER_RATIO, "required_refinement_level": 2,
		"residual_force_tolerance": 1.0e-8, "residual_moment_tolerance": 1.0e-8,
		"evaluator_version": "FABRIC_BRIDGE3_R1"})
	if not guard.success:
		return guard
	var local := L.compile({"plan_id": "unbake-plan/bridge3", "source_frontier_hash": subject.frontier.frontier_hash,
		"structural_descriptor": ag.descriptor, "reconstruction_mapping": ag.reconstruction_mapping,
		"guard_field": guard.guard_field, "parts": subject.parts, "bonds": subject.bonds,
		"boundary_anchors": subject.anchors, "target_region_id": subject.target_region_id,
		"max_full_parts": F.MAX_FULL_PARTS, "minimum_retained_component_parts": F.MINIMUM_RETAINED_PARTS,
		"continuity_tolerance": F.CONTINUITY_TOLERANCE, "conservation_tolerance": F.CONSERVATION_TOLERANCE,
		"transition_version": "FABRIC_BRIDGE3_R1"})
	if not local.success:
		return local
	var structural := {"success": true, "aggregate": ag, "guard": guard, "local": local, "capacities": capacities}
	var state := AB.reduced_state()
	var full := R.reconstruct(ag.reconstruction_mapping, state)
	if not full.success:
		return full
	return {"success": true, "subject": subject, "bundle": bundle, "structural": structural,
		"full": full.details.full_states, "state": state,
		"danger": context(subject, structural, state, true),
		"safe": context(subject, structural, state, false)}

static func context(subject: Dictionary, structural: Dictionary, state: Dictionary, danger: bool) -> Dictionary:
	var output := F.guard_context(subject, structural)
	var omega := H.q(state.orientation).inverse() * H.v(state.angular_velocity)
	output.angular_velocity_body = H.a(omega)
	var loads := C.rigid_inertial_wrenches(subject.parts, structural.aggregate.descriptor, Vector3.ZERO, omega, Vector3.ZERO)
	if danger:
		loads.append_array(output.external_wrenches)
	output.external_wrenches = loads
	return output
