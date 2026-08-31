extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const DependencySet = preload("res://scripts/research/fabric_bake0/bake_dependency_set_v1.gd")
const CFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_c_fixture.gd")
const DFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_d_fixture.gd")
const DCompiler = preload("res://scripts/research/fabric_bake0/structural_local_unbake_compiler_v1.gd")

const TRANSACTION_ID := "topology-transaction/b0-2-e"
const EVENT_ID := "topology-event/b0-2-e-break-0257"
const BREAK_BOND_ID := CFixture.WEAK_BOND_ID
const TARGET_REGION_ID := CFixture.WEAK_REGION_ID
const EVENT_TICK := 100
const EVENT_SEQUENCE := 1
const MIN_REBAKE_COMPONENT_PARTS := 100
const CONTINUITY_TOLERANCE := 1.0e-9
const CONSERVATION_TOLERANCE := 1.0e-8
const TRANSITION_VERSION := "FABRIC_BAKE_B0_2_E_R1"
const FABRIC_COMPILER_VERSION := "FABRIC-BAKE/B0.2-E-R1"

static func h(value) -> String:
	return Utils.canonical_hash(value)

static func build(reverse_input: bool = false) -> Dictionary:
	var d_fixture := DFixture.build(reverse_input)
	if not bool(d_fixture.get("success", false)):
		return {"success": false, "d_fixture": d_fixture}
	var d_compiled := DCompiler.compile(d_fixture["request"])
	if not bool(d_compiled.get("success", false)):
		return {"success": false, "d_fixture": d_fixture, "d_compiled": d_compiled}
	var c_fixture: Dictionary = d_fixture["c_fixture"]
	var previous_frontier: Dictionary = c_fixture["ab"]["frontier"]
	var previous_construction: Dictionary = c_fixture["ab"]["construction"]
	var matter: Dictionary = c_fixture["ab"]["matter"]
	var current_construction := SourceRevision.create(
		"CONSTRUCTION", String(previous_construction["source_id"]),
		int(previous_construction["authority_epoch"]), int(previous_construction["source_revision"]) + 1,
		h({
			"construction": "b0.2-structural",
			"topology_event": EVENT_ID,
			"broken_bond": BREAK_BOND_ID,
			"event_sequence": EVENT_SEQUENCE,
		}),
		String(previous_construction["dependency_hash"])
	)
	var current_frontier := Frontier.create([matter, current_construction])
	var current_bonds: Array = []
	for bond in c_fixture["ab"]["bonds"]:
		if String(bond["bond_id"]) != BREAK_BOND_ID:
			current_bonds.append(bond.duplicate(true))
	var authority_records: Array = []
	var mutable_ids: Array = []
	for source in current_frontier["sources"]:
		authority_records.append({
			"source_domain": String(source["source_domain"]),
			"source_id": String(source["source_id"]),
			"authority_epoch": int(source["authority_epoch"]),
			"owner_id": "server/bake-b0-2",
		})
		mutable_ids.append(Utils.source_key(String(source["source_domain"]), String(source["source_id"])))
	var authority := AuthorityEnvelope.create("server/bake-b0-2", authority_records, mutable_ids)
	var dependencies := DependencySet.create([
		{"dependency_id": "dependency/fabric-bake-structural-core", "dependency_hash": h({"structural_core": "b0.2-e-r1"})},
		{"dependency_id": "dependency/fabric-bake-topology-lifecycle", "dependency_hash": h({"topology_lifecycle": "split-rebake-r1"})},
	])
	var topology_event := {
		"event_id": EVENT_ID,
		"event_type": "BOND_BREAK",
		"bond_id": BREAK_BOND_ID,
		"target_region_id": TARGET_REGION_ID,
		"event_tick": EVENT_TICK,
		"event_sequence": EVENT_SEQUENCE,
	}
	return {
		"success": true,
		"d_fixture": d_fixture,
		"d_compiled": d_compiled,
		"previous_frontier": previous_frontier,
		"current_frontier": current_frontier,
		"current_construction": current_construction,
		"authority": authority,
		"dependencies": dependencies,
		"current_bonds": current_bonds,
		"topology_event": topology_event,
		"request": make_request(d_fixture, d_compiled, previous_frontier, current_frontier, authority, dependencies, current_bonds, topology_event),
	}

static func make_request(
	d_fixture: Dictionary, d_compiled: Dictionary, previous_frontier: Dictionary,
	current_frontier: Dictionary, authority: Dictionary, dependencies: Dictionary,
	current_bonds: Array, topology_event: Dictionary
) -> Dictionary:
	var c_fixture: Dictionary = d_fixture["c_fixture"]
	return {
		"transaction_id": TRANSACTION_ID,
		"previous_source_frontier": previous_frontier,
		"current_source_frontier": current_frontier,
		"parent_structural_descriptor": c_fixture["aggregate"]["descriptor"],
		"parent_reconstruction_mapping": c_fixture["aggregate"]["reconstruction_mapping"],
		"parent_guard_field": d_fixture["c_compiled"]["guard_field"],
		"local_unbake_plan": d_compiled["plan"],
		"previous_parts": c_fixture["ab"]["parts"].duplicate(true),
		"previous_bonds": c_fixture["ab"]["bonds"].duplicate(true),
		"boundary_anchors": c_fixture["ab"]["anchors"].duplicate(true),
		"current_parts": c_fixture["ab"]["parts"].duplicate(true),
		"current_bonds": current_bonds.duplicate(true),
		"topology_event": topology_event.duplicate(true),
		"bond_capacity_specs": c_fixture["capacities"].duplicate(true),
		"authority_envelope": authority,
		"dependency_set": dependencies,
		"bake_policy_hash": h({"policy": "b0.2-e-structural-rebake-r1"}),
		"fabric_compiler_version": FABRIC_COMPILER_VERSION,
		"build_generation": 2,
		"minimum_rebake_component_parts": MIN_REBAKE_COMPONENT_PARTS,
		"continuity_tolerance": CONTINUITY_TOLERANCE,
		"conservation_tolerance": CONSERVATION_TOLERANCE,
		"transition_version": TRANSITION_VERSION,
	}
