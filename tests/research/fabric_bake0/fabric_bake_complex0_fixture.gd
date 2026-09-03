extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const AggregateCompiler = preload("res://scripts/research/fabric_bake0/structural_aggregate_compiler_v1.gd")
const GuardCompiler = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_compiler_v1.gd")
const GuardRuntime = preload("res://scripts/research/fabric_bake0/structural_refinement_guard_runtime_v1.gd")
const LocalCompiler = preload("res://scripts/research/fabric_bake0/structural_local_unbake_compiler_v1.gd")
const TopologyCompiler = preload("res://scripts/research/fabric_bake0/structural_topology_rebake_compiler_v1.gd")
const Lifecycle = preload("res://scripts/research/fabric_bake0/physical_source_lifecycle_v1.gd")
const Bridge0 = preload("res://scripts/research/fabric_bake0/fabric_bake_bridge0_v1.gd")
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

const REGION_SIZE := 20
const MINIMUM_BAKE_PARTS := 100
const MAX_FULL_PARTS := 32
const MINIMUM_RETAINED_PARTS := 100
const CONTINUITY_TOLERANCE := 1.0e-9
const CONSERVATION_TOLERANCE := 1.0e-8
const TRIGGER_RATIO := 0.80
const WEAK_FORCE_CAPACITY := 40.0
const DEFAULT_FORCE_CAPACITY := 1000.0
const MOMENT_CAPACITY := 1.0e9
const WEAK_UNCERTAINTY := 0.05
const DEFAULT_UNCERTAINTY := 0.02
const IMPACT_LOAD := 36.0
const OWNER_ID := "server/complex0"
const DEPENDENCY_HASH := "5fffb94d5a67af97b0c91501dd4971ad0a95198f895915fe75c21aed012bb20a"

static func h(value) -> String:
	return Utils.canonical_hash(value)

static func build(count: int) -> Dictionary:
	if count < 2:
		return Utils.failure("COMPLEX0_INVALID_PART_COUNT")
	var parts := ABFixture.make_parts(count, 0)
	var bonds := ABFixture.make_bonds(count)
	var anchors := ABFixture.make_anchors(count)
	var break_index := count / 2 + 7
	if break_index >= count:
		break_index = count / 2
	var break_bond_id := "bond/b0-2-%04d" % break_index
	var target_region_id := "region/b0-2-%03d" % (break_index / REGION_SIZE)
	var construct_id := "construct/complex0-%04d" % count
	var matter_id := "matter/complex0-%04d" % count
	var construction_payload := {
		"construct_id": construct_id,
		"parts": parts.duplicate(true),
		"bonds": bonds.duplicate(true),
		"boundary_anchors": anchors.duplicate(true),
	}
	var matter_payload := {
		"matter_id": matter_id,
		"material_family": "RIGID_COMPLEX0_TEST_MATTER",
		"material_revision": 0,
	}
	var construction := SourceRevision.create(
		"CONSTRUCTION", construct_id, 9, 1000 + count,
		h(construction_payload), DEPENDENCY_HASH
	)
	var matter := SourceRevision.create(
		"MATTER", matter_id, 9, 10,
		h(matter_payload), DEPENDENCY_HASH
	)
	var frontier := Frontier.create([matter, construction])
	var authority := _authority(frontier)
	return {
		"success": true,
		"count": count,
		"parts": parts,
		"bonds": bonds,
		"anchors": anchors,
		"break_index": break_index,
		"break_bond_id": break_bond_id,
		"target_region_id": target_region_id,
		"construct_id": construct_id,
		"matter_id": matter_id,
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"construction_payload": construction_payload,
		"matter_payload": matter_payload,
		"view_request": {
			"canonical_source_frontier": frontier,
			"authority_envelope": authority,
			"payloads": [
				{"source_domain": "CONSTRUCTION", "source_id": construct_id, "payload": construction_payload},
				{"source_domain": "MATTER", "source_id": matter_id, "payload": matter_payload},
			],
		},
	}

static func lifecycle_options(subject: Dictionary) -> Dictionary:
	var suffix := "%04d" % int(subject["count"])
	return {
		"minimum_part_count": MINIMUM_BAKE_PARTS,
		"root_part_id": "part/b0-2-0000",
		"descriptor_id": "aggregate/complex0-parent-%s" % suffix,
		"mapping_id": "mapping/complex0-parent-%s" % suffix,
		"guard_field_id": "guard-field/complex0-parent-%s" % suffix,
		"artifact_id": "bake/complex0-parent-%s" % suffix,
		"reconstruction_descriptor_id": "reconstruction/complex0-parent-%s" % suffix,
		"state_mapping_id": "state-mapping/complex0-parent-%s" % suffix,
		"build_generation": 1,
	}

static func compile_structural(subject: Dictionary) -> Dictionary:
	var count := int(subject["count"])
	var suffix := "%04d" % count
	var aggregate := AggregateCompiler.compile({
		"descriptor_id": "aggregate/complex0-event-%s" % suffix,
		"mapping_id": "mapping/complex0-event-%s" % suffix,
		"source_frontier_hash": String(subject["frontier"]["frontier_hash"]),
		"construct_id": String(subject["construct_id"]),
		"parts": subject["parts"].duplicate(true),
		"bonds": subject["bonds"].duplicate(true),
		"boundary_anchors": subject["anchors"].duplicate(true),
		"reconstruction_version": "FABRIC_BAKE_COMPLEX0_R1",
		"minimum_part_count": MINIMUM_BAKE_PARTS,
	})
	if not bool(aggregate.get("success", false)):
		return aggregate
	var capacities := _capacity_specs(subject, aggregate["descriptor"])
	var guard := GuardCompiler.compile({
		"field_id": "guard-field/complex0-event-%s" % suffix,
		"source_frontier_hash": String(subject["frontier"]["frontier_hash"]),
		"structural_descriptor": aggregate["descriptor"],
		"reconstruction_mapping": aggregate["reconstruction_mapping"],
		"parts": subject["parts"].duplicate(true),
		"bonds": subject["bonds"].duplicate(true),
		"root_part_id": "part/b0-2-0000",
		"bond_capacity_specs": capacities,
		"capacity_certificate_hash": _capacity_hash(String(subject["frontier"]["frontier_hash"]), capacities),
		"trigger_ratio": TRIGGER_RATIO,
		"required_refinement_level": 2,
		"residual_force_tolerance": 1.0e-8,
		"residual_moment_tolerance": 1.0e-8,
		"evaluator_version": "FABRIC_BAKE_COMPLEX0_R1",
	})
	if not bool(guard.get("success", false)):
		return guard
	var local := LocalCompiler.compile({
		"plan_id": "unbake-plan/complex0-%s" % suffix,
		"source_frontier_hash": String(subject["frontier"]["frontier_hash"]),
		"structural_descriptor": aggregate["descriptor"],
		"reconstruction_mapping": aggregate["reconstruction_mapping"],
		"guard_field": guard["guard_field"],
		"parts": subject["parts"].duplicate(true),
		"bonds": subject["bonds"].duplicate(true),
		"boundary_anchors": subject["anchors"].duplicate(true),
		"target_region_id": String(subject["target_region_id"]),
		"max_full_parts": MAX_FULL_PARTS,
		"minimum_retained_component_parts": MINIMUM_RETAINED_PARTS,
		"continuity_tolerance": CONTINUITY_TOLERANCE,
		"conservation_tolerance": CONSERVATION_TOLERANCE,
		"transition_version": "FABRIC_BAKE_COMPLEX0_R1",
	})
	return {
		"success": bool(local.get("success", false)),
		"aggregate": aggregate,
		"guard": guard,
		"capacities": capacities,
		"local": local,
		"error_code": String(local.get("error_code", "")),
	}

static func make_break(subject: Dictionary, structural: Dictionary) -> Dictionary:
	if not bool(structural.get("success", false)):
		return Utils.failure("COMPLEX0_STRUCTURAL_PIPELINE_NOT_READY")
	var count := int(subject["count"])
	var suffix := "%04d" % count
	var current_bonds: Array = []
	for bond in subject["bonds"]:
		if String(bond["bond_id"]) != String(subject["break_bond_id"]):
			current_bonds.append(bond.duplicate(true))
	var current_payload := {
		"construct_id": String(subject["construct_id"]),
		"parts": subject["parts"].duplicate(true),
		"bonds": current_bonds.duplicate(true),
		"boundary_anchors": subject["anchors"].duplicate(true),
	}
	var previous_construction: Dictionary = subject["construction"]
	var current_construction := SourceRevision.create(
		"CONSTRUCTION", String(subject["construct_id"]),
		int(previous_construction["authority_epoch"]), int(previous_construction["source_revision"]) + 1,
		h(current_payload), String(previous_construction["dependency_hash"])
	)
	var current_frontier := Frontier.create([subject["matter"], current_construction])
	var current_authority := _authority(current_frontier)
	var event_tick := 2000 + count
	var event := {
		"event_id": "topology-event/complex0-%s-break" % suffix,
		"event_type": "BOND_BREAK",
		"bond_id": String(subject["break_bond_id"]),
		"target_region_id": String(subject["target_region_id"]),
		"event_tick": event_tick,
		"event_sequence": 1,
	}
	var dependencies := DependencySet.create([
		{"dependency_id": "dependency/complex0-structural", "dependency_hash": h({"pipeline": "b0.2-cde"})},
		{"dependency_id": "dependency/complex0-bake-lifecycle", "dependency_hash": h({"pipeline": "bridge0-bake-invalidation"})},
	])
	var source_invalidation := RepresentationInvalidation.create(
		"invalidation/complex0-%s-break" % suffix,
		previous_construction, current_construction,
		[-10000.0, -10000.0, -10000.0, 10000.0, 10000.0, 10000.0],
		"MUTATION", [String(subject["construct_id"])], event_tick
	)
	var request := {
		"transaction_id": "topology-transaction/complex0-%s" % suffix,
		"previous_source_frontier": subject["frontier"],
		"current_source_frontier": current_frontier,
		"parent_structural_descriptor": structural["aggregate"]["descriptor"],
		"parent_reconstruction_mapping": structural["aggregate"]["reconstruction_mapping"],
		"parent_guard_field": structural["guard"]["guard_field"],
		"local_unbake_plan": structural["local"]["plan"],
		"previous_parts": subject["parts"].duplicate(true),
		"previous_bonds": subject["bonds"].duplicate(true),
		"boundary_anchors": subject["anchors"].duplicate(true),
		"current_parts": subject["parts"].duplicate(true),
		"current_bonds": current_bonds,
		"topology_event": event,
		"bond_capacity_specs": structural["capacities"].duplicate(true),
		"authority_envelope": current_authority,
		"dependency_set": dependencies,
		"bake_policy_hash": h({"policy": "complex0-topology-rebake-r1", "count": count}),
		"fabric_compiler_version": "FABRIC-BAKE/COMPLEX0-R1",
		"build_generation": 2,
		"minimum_rebake_component_parts": MINIMUM_RETAINED_PARTS,
		"continuity_tolerance": CONTINUITY_TOLERANCE,
		"conservation_tolerance": CONSERVATION_TOLERANCE,
		"transition_version": "FABRIC_BAKE_COMPLEX0_R1",
	}
	return {
		"success": true,
		"current_construction": current_construction,
		"current_frontier": current_frontier,
		"current_authority": current_authority,
		"current_bonds": current_bonds,
		"dependencies": dependencies,
		"event": event,
		"source_invalidation": source_invalidation,
		"request": request,
	}

static func compile_transaction(break_bundle: Dictionary) -> Dictionary:
	return TopologyCompiler.compile(break_bundle["request"])

static func make_bake_invalidation(parent_lifecycle: Dictionary, break_bundle: Dictionary) -> Dictionary:
	return Bridge0.invalidate_from_source_mutation(
		parent_lifecycle["artifact"], break_bundle["source_invalidation"],
		break_bundle["current_frontier"], int(break_bundle["event"]["event_tick"])
	)

static func guard_context(subject: Dictionary, structural: Dictionary) -> Dictionary:
	var mapping: Dictionary = structural["aggregate"]["reconstruction_mapping"]
	var positions: Dictionary = {}
	for part in mapping["part_mappings"]:
		positions[String(part["part_id"])] = _vec3(part["position_from_com"])
	var break_index := int(subject["break_index"])
	var left_index := maxi(1, break_index - 17)
	var right_index := mini(int(subject["count"]) - 1, break_index + 23)
	var left_id := "part/b0-2-%04d" % left_index
	var right_id := "part/b0-2-%04d" % right_index
	var point_left: Vector3 = positions[left_id]
	var point_right: Vector3 = positions[right_id]
	var force := Vector3(IMPACT_LOAD, 0.0, 0.0)
	var balancing_torque := -(point_right - point_left).cross(force)
	return {
		"source_frontier_hash": String(subject["frontier"]["frontier_hash"]),
		"structural_descriptor_hash": String(structural["aggregate"]["descriptor"]["checksum"]),
		"reconstruction_mapping_hash": String(mapping["checksum"]),
		"complete_external_wrench_set": true,
		"linear_acceleration_body": [0.0, 0.0, 0.0],
		"angular_velocity_body": [0.0, 0.0, 0.0],
		"angular_acceleration_body": [0.0, 0.0, 0.0],
		"external_wrenches": [
			{
				"wrench_id": "wrench/complex0-impact-left",
				"part_id": left_id,
				"point_from_com": _arr3(point_left),
				"force_body": _arr3(-force),
				"torque_body_about_point": _arr3(balancing_torque),
			},
			{
				"wrench_id": "wrench/complex0-impact-right",
				"part_id": right_id,
				"point_from_com": _arr3(point_right),
				"force_body": _arr3(force),
				"torque_body_about_point": [0.0, 0.0, 0.0],
			},
		],
	}

static func evaluate_guard(subject: Dictionary, structural: Dictionary) -> Dictionary:
	return GuardRuntime.evaluate(structural["guard"]["guard_field"], guard_context(subject, structural))

static func reduced_state() -> Dictionary:
	return ABFixture.reduced_state()

static func _authority(frontier: Dictionary) -> Dictionary:
	var authority_records: Array = []
	var mutable_ids: Array = []
	for source in frontier["sources"]:
		authority_records.append({
			"source_domain": String(source["source_domain"]),
			"source_id": String(source["source_id"]),
			"authority_epoch": int(source["authority_epoch"]),
			"owner_id": OWNER_ID,
		})
		mutable_ids.append(Utils.source_key(String(source["source_domain"]), String(source["source_id"])))
	return AuthorityEnvelope.create(OWNER_ID, authority_records, mutable_ids)

static func _capacity_specs(subject: Dictionary, descriptor: Dictionary) -> Array:
	var part_position: Dictionary = {}
	var com := _vec3(descriptor["center_of_mass"])
	for part in subject["parts"]:
		part_position[String(part["part_id"])] = _vec3(part["position"]) - com
	var specs: Array = []
	for bond in Utils.sorted_dicts(subject["bonds"], "bond_id"):
		var bond_id := String(bond["bond_id"])
		var a: Vector3 = part_position[String(bond["part_a"])]
		var b: Vector3 = part_position[String(bond["part_b"])]
		var weak := bond_id == String(subject["break_bond_id"])
		specs.append({
			"bond_id": bond_id,
			"point_from_com": _arr3((a + b) * 0.5),
			"certified_force_capacity": WEAK_FORCE_CAPACITY if weak else DEFAULT_FORCE_CAPACITY,
			"certified_moment_capacity": MOMENT_CAPACITY,
			"uncertainty_ratio": WEAK_UNCERTAINTY if weak else DEFAULT_UNCERTAINTY,
		})
	return specs

static func _capacity_hash(source_frontier_hash: String, capacities: Array) -> String:
	return h({
		"schema": "planet_simulator.fabric_bake_structural_capacity_set.v1",
		"source_frontier_hash": source_frontier_hash,
		"bond_capacity_specs": Utils.sorted_dicts(capacities, "bond_id"),
	})

static func _vec3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

static func _arr3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
