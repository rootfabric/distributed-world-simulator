extends SceneTree

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")

func _init() -> void:
	var dependency_hash := Utils.canonical_hash({"dependency": "playground"})
	var construction := SourceRevision.create(
		"CONSTRUCTION", "construct/playground", 1, 1,
		Utils.canonical_hash({"source": "construction"}),
		dependency_hash
	)
	var matter := SourceRevision.create(
		"MATTER", "matter/playground", 1, 1,
		Utils.canonical_hash({"source": "matter"}),
		dependency_hash
	)
	var frontier := Frontier.create([matter, construction])
	print("FABRIC-BAKE B0.0 Playground")
	print("canonical_sources=", frontier["sources"].size())
	print("frontier_hash=", frontier["frontier_hash"])
	print("truth_hierarchy=CANONICAL(CONSTRUCTION|MATTER)->FABRIC->PHYSICAL_BAKE")
	print("stale_rule=EXECUTION_FORBIDDEN")
	print("unsafe_cross_authority=NO_SAFE_BAKE")
	quit(0)
