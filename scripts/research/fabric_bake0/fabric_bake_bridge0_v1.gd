extends RefCounted

const Utils = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Artifact = preload("res://scripts/research/fabric_bake0/physical_bake_artifact_v1.gd")
const Frontier = preload("res://scripts/research/fabric_bake0/canonical_source_frontier_v1.gd")
const RepresentationInvalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const BakeInvalidation = preload("res://scripts/research/fabric_bake0/bake_invalidation_v1.gd")

static func invalidate_from_source_mutation(
	artifact: Dictionary,
	source_invalidation: Dictionary,
	current_frontier: Dictionary,
	created_tick: int
) -> Dictionary:
	var checked := Artifact.validate(artifact)
	if not bool(checked.get("success", false)):
		return checked
	checked = RepresentationInvalidation.validate(source_invalidation)
	if not bool(checked.get("success", false)):
		return checked
	checked = Frontier.validate(current_frontier)
	if not bool(checked.get("success", false)):
		return checked
	if not Utils.is_json_integer(created_tick) or created_tick < 0:
		return Utils.failure("INVALID_BAKE_BRIDGE_TICK")

	var previous: Dictionary = source_invalidation["previous_source_revision"]
	var current: Dictionary = source_invalidation["new_source_revision"]
	var bound_previous := _find_source(
		artifact["source_binding"]["canonical_source_frontier"],
		String(previous["source_domain"]),
		String(previous["source_id"])
	)
	if bound_previous.is_empty() or String(bound_previous["checksum"]) != String(previous["checksum"]):
		return Utils.failure("BAKE_BRIDGE_PREVIOUS_SOURCE_MISMATCH")

	var live_current := _find_source(
		current_frontier,
		String(current["source_domain"]),
		String(current["source_id"])
	)
	if live_current.is_empty() or String(live_current["checksum"]) != String(current["checksum"]):
		return Utils.failure("BAKE_BRIDGE_CURRENT_SOURCE_MISMATCH")
	if String(current_frontier["frontier_hash"]) == String(artifact["source_binding"]["frontier_hash"]):
		return Utils.failure("BAKE_BRIDGE_FRONTIER_NOT_ADVANCED")

	return BakeInvalidation.create(
		"bake-invalidation/source-%s" % String(source_invalidation["invalidation_id"]).replace("/", "-"),
		String(artifact["artifact_id"]),
		"SOURCE_REVISION",
		String(artifact["source_binding"]["frontier_hash"]),
		String(current_frontier["frontier_hash"]),
		created_tick
	)

static func _find_source(frontier: Dictionary, source_domain: String, source_id: String) -> Dictionary:
	for source in frontier.get("sources", []):
		if String(source.get("source_domain", "")) == source_domain and String(source.get("source_id", "")) == source_id:
			return Dictionary(source).duplicate(true)
	return {}
