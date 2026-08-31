extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const AuthorityEnvelope = preload("res://scripts/research/fabric_bake0/authority_envelope_v1.gd")
const ABFixture = preload("res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_fixture.gd")

const CONSTRUCTION_ID := "construct/bridge1-structural"
const MATTER_ID := "matter/bridge1-structural"
const OWNER_ID := "server/bridge1"
const DEPENDENCY_HASH := "7f9b4ba3ba6a2d8f8bac1ee6c0b0110af286699653c363545bceca3d8b6805cf"

static func h(value) -> String:
	return Utils.canonical_hash(value)

static func build(revision: int = 0, reverse_input: bool = false, topology_change: bool = false, cross_authority: bool = false) -> Dictionary:
	var parts := ABFixture.make_parts(ABFixture.PART_COUNT, revision)
	var bonds := ABFixture.make_bonds(ABFixture.PART_COUNT)
	var anchors := ABFixture.make_anchors(ABFixture.PART_COUNT)
	if topology_change:
		bonds.remove_at(256)
	var construction_payload := {
		"construct_id": CONSTRUCTION_ID,
		"parts": parts,
		"bonds": bonds,
		"boundary_anchors": anchors,
	}
	var matter_payload := {
		"matter_id": MATTER_ID,
		"material_family": "RIGID_TEST_MATTER",
		"material_revision": 0,
	}
	var construction := SourceRevision.create(
		"CONSTRUCTION", CONSTRUCTION_ID, 9, 100 + revision,
		h(construction_payload), DEPENDENCY_HASH
	)
	var matter := SourceRevision.create(
		"MATTER", MATTER_ID, 9, 10,
		h(matter_payload), DEPENDENCY_HASH
	)
	var frontier := Frontier.create([matter, construction])
	var authority_records: Array = []
	var mutable_ids: Array = []
	for source in frontier["sources"]:
		var key := Utils.source_key(String(source["source_domain"]), String(source["source_id"]))
		authority_records.append({
			"source_domain": source["source_domain"],
			"source_id": source["source_id"],
			"authority_epoch": source["authority_epoch"],
			"owner_id": "server/foreign" if cross_authority and String(source["source_domain"]) == "CONSTRUCTION" else OWNER_ID,
		})
		mutable_ids.append(key)
	var authority := AuthorityEnvelope.create(OWNER_ID, authority_records, mutable_ids)
	var payloads: Array = [
		{"source_domain": "CONSTRUCTION", "source_id": CONSTRUCTION_ID, "payload": construction_payload},
		{"source_domain": "MATTER", "source_id": MATTER_ID, "payload": matter_payload},
	]
	if reverse_input:
		payloads.reverse()
	return {
		"construction": construction,
		"matter": matter,
		"frontier": frontier,
		"authority": authority,
		"construction_payload": construction_payload,
		"matter_payload": matter_payload,
		"view_request": {
			"canonical_source_frontier": frontier,
			"authority_envelope": authority,
			"payloads": payloads,
		},
	}

static func invalidation(previous: Dictionary, current: Dictionary, invalidation_id: String = "invalidation/bridge1-mass-change") -> Dictionary:
	return RepresentationInvalidation.create(
		invalidation_id,
		previous["construction"], current["construction"],
		[-100.0, -100.0, -100.0, 100.0, 100.0, 100.0],
		"MUTATION", [CONSTRUCTION_ID], 200
	)

static func reduced_state() -> Dictionary:
	return ABFixture.reduced_state()
