extends SceneTree

## P6 R3: outpost state is a read-only composition projection, not canonical
## Item/Construction/player truth.

const ProjectionScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_outpost_state.gd")

var assertions := 0
var failures: Array[String] = []


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-projection][FAIL] %s" % message)


func _sources() -> Dictionary:
	return {
		"gameplay": {"schema": "fixture.gameplay.v1", "revision": 10, "players": [{"id": "player/a"}]},
		"item_graph": {"schema": "fixture.item_graph.v1", "revision": 20, "items": [{"item_id": "item/a"}]},
		"construction": {"schema": "fixture.construction.v1", "revision": 30, "constructs": [{"construct_id": "construct/a"}]},
		"resource_mining": {"schema": "fixture.resource.v1", "revision": 40},
	}


func _init() -> void:
	var projection = ProjectionScript.new()
	var configured: Dictionary = projection.configure_from_canonical_sources(_sources())
	_assert(bool(configured.get("success", false)), "projection configure failed")
	_assert(projection.is_configured(), "projection not configured")
	_assert(String(projection.get_report()["canonical_mutation_owner"]) == "EXTERNAL", "projection claims canonical mutation authority")
	_assert(not bool(projection.get_report()["private_canonical_truth"]), "projection claims private canonical truth")

	var item_source := projection.get_source("item_graph")
	item_source["revision"] = 999
	_assert(int(projection.get_source("item_graph")["revision"]) == 20, "defensive source copy leaked mutation")

	# Critical R3 boundary: legacy private delta API is fail-closed.
	var applied := projection.apply_delta({"op": "place_block", "pos": [1, 2, 3], "block_type": "stone"})
	_assert(not applied, "projection accepted private canonical mutation")
	_assert(String(projection.get_report()["last_error_code"]) == ProjectionScript.ERR_PRIVATE_MUTATION, "private mutation error mismatch")
	_assert(int(projection.get_report()["rejected_mutations"]) == 1, "rejected mutation counter mismatch")

	# Projection serialization is deterministic and reloadable without granting
	# mutation authority.
	var snapshot := projection.serialize()
	var checksum := String(snapshot.get("checksum", ""))
	_assert(checksum.length() == 64, "projection checksum missing")
	var restored = ProjectionScript.new()
	_assert(restored.deserialize(snapshot), "projection deserialize failed")
	_assert(restored.compute_checksum() == checksum, "projection checksum changed after restore")
	_assert(not restored.apply_delta({"op": "container_create"}), "restored projection became mutable")

	var missing = ProjectionScript.new()
	var bad: Dictionary = missing.configure_from_canonical_sources({"gameplay": {}, "item_graph": {}})
	_assert(not bool(bad.get("success", false)) and String(bad.get("error_code", "")) == "CANONICAL_SOURCE_REQUIRED", "missing canonical construction source accepted")

	if failures.is_empty():
		print("[p6-r3-projection] all %d assertions passed" % assertions)
		print("[p6-r3-projection][stage] NO_DUPLICATE_CANONICAL_OUTPOST_TRUTH_PASS")
		quit(0)
	else:
		print("[p6-r3-projection] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
