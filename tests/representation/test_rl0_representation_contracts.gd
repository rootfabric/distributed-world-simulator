extends SceneTree

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const Descriptor = preload("res://scripts/simulation/representation/contracts/representation_descriptor.gd")
const InterestRequest = preload("res://scripts/simulation/representation/contracts/representation_interest_request.gd")
const Candidate = preload("res://scripts/simulation/representation/contracts/representation_candidate.gd")
const DependencySet = preload("res://scripts/simulation/representation/contracts/representation_dependency_set.gd")
const Invalidation = preload("res://scripts/simulation/representation/contracts/representation_invalidation.gd")
const CacheEntry = preload("res://scripts/simulation/representation/contracts/representation_cache_entry.gd")
const Selector = preload("res://scripts/simulation/representation/selection/representation_selector.gd")

var failures: Array[String] = []
var assertions: int = 0


func _init() -> void:
	_test_manifest()
	_test_utils()
	_test_source_revisions()
	_test_keys_and_artifacts()
	_test_descriptors()
	_test_dependency_sets()
	_test_interest_and_selection()
	_test_invalidation()
	_test_cache_entries()
	_test_runtime_object_rejection()
	_finish()


func _test_manifest() -> void:
	var path: String = "res://config/representation/representation-lod.v1.json"
	_assert(FileAccess.file_exists(path), "RL0 config is missing")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	_assert(file != null, "RL0 config could not be opened")
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	_assert(typeof(parsed) == TYPE_DICTIONARY, "RL0 config is not a JSON object")
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var config: Dictionary = parsed
	_assert(String(config.get("schema", "")) == "planet_simulator.representation_lod_config.v1", "RL0 config schema changed")
	_assert(String(config.get("checkpoint", "")) == "v17.9.0-simulation-rl0-representation-contracts", "RL0 checkpoint changed")
	_assert(String(config.get("accepted_base", "")) == "v17.8.0-simulation-mw8-regional-authority-handoff", "RL0 base changed")
	_assert(String(config.get("recommended_branch", "")) == "feature/rl0-representation-contracts", "RL0 branch changed")
	_assert(Array(config.get("source_domains", [])) == ["CONSTRUCTION", "MATTER"], "RL0 source domains changed")
	_assert(not bool(Dictionary(config.get("boundaries", {})).get("canonical_state_contains_mesh", true)), "RL0 config makes mesh canonical")
	_assert(not bool(Dictionary(config.get("boundaries", {})).get("production_worlds_changed", true)), "RL0 changes production worlds")


func _test_utils() -> void:
	_assert(Utils.is_source_domain("MATTER"), "MATTER source domain rejected")
	_assert(Utils.is_source_domain("CONSTRUCTION"), "CONSTRUCTION source domain rejected")
	_assert(not Utils.is_source_domain("ITEM"), "Unknown source domain accepted")
	_assert(Utils.is_artifact_kind("MACRO_PROXY"), "MACRO_PROXY kind rejected")
	_assert(not Utils.is_artifact_kind("FULL_MESH"), "Unknown artifact kind accepted")
	_assert_ok(Utils.validate_bounds_m([-1.0, -2.0, -3.0, 1.0, 2.0, 3.0]), "Valid bounds rejected")
	_assert_fail(Utils.validate_bounds_m([1.0, 0.0, 0.0, -1.0, 1.0, 1.0]), "Reversed bounds accepted")
	_assert_fail(Utils.validate_bounds_m([0.0, 0.0, 0.0]), "Short bounds accepted")
	_assert(absf(Utils.screen_error_px(2.0, 1000.0, 1000.0) - 2.0) < 0.000000001, "Screen error calculation changed")
	_assert(is_inf(Utils.screen_error_px(1.0, 0.0, 1000.0)), "Zero-distance screen error accepted")
	_assert_ok(Utils.validate_sorted_unique_kinds(["DETAIL", "MACRO_PROXY"], false), "Sorted artifact kinds rejected")
	_assert_fail(Utils.validate_sorted_unique_kinds(["MACRO_PROXY", "DETAIL"], false), "Unsorted artifact kinds accepted")


func _test_source_revisions() -> void:
	var matter: Dictionary = _matter_source(7)
	var construction: Dictionary = _construction_source(11)
	_assert_ok(SourceRevision.validate(matter), "Matter source revision rejected")
	_assert_ok(SourceRevision.validate(construction), "Construction source revision rejected")
	_assert(String(matter["source_domain"]) == "MATTER", "Matter source domain changed")
	_assert(String(construction["source_domain"]) == "CONSTRUCTION", "Construction source domain changed")
	var extra: Dictionary = matter.duplicate(true)
	extra["mesh"] = "forbidden"
	_assert_fail(SourceRevision.validate(extra), "Source revision accepted presentation field")
	var bad_hash: Dictionary = matter.duplicate(true)
	bad_hash["source_hash"] = "bad"
	bad_hash["checksum"] = Utils.compute_checksum(bad_hash)
	_assert_fail(SourceRevision.validate(bad_hash), "Invalid source hash accepted")
	var stale_checksum: Dictionary = matter.duplicate(true)
	stale_checksum["source_revision"] = 8
	_assert_fail(SourceRevision.validate(stale_checksum), "Stale source checksum accepted")
	_assert(not Utils.canonical_json(matter).is_empty(), "Matter source is not JSON-safe")


func _test_keys_and_artifacts() -> void:
	var source: Dictionary = _matter_source(7)
	var detail_key: Dictionary = _key(source, 0, "DETAIL", "representation-scope/matter/local")
	var macro_key: Dictionary = _key(source, 2, "MACRO_PROXY", "representation-scope/matter/body")
	_assert_ok(RepresentationKey.validate(detail_key), "Detail key rejected")
	_assert_ok(RepresentationKey.validate(macro_key), "Macro key rejected")
	_assert(int(detail_key["lod_level"]) == 0, "Detail LOD changed")
	_assert(int(macro_key["lod_level"]) == 2, "Macro LOD changed")
	var invalid_level: Dictionary = detail_key.duplicate(true)
	invalid_level["lod_level"] = 33
	invalid_level["checksum"] = Utils.compute_checksum(invalid_level)
	_assert_fail(RepresentationKey.validate(invalid_level), "LOD above maximum accepted")
	var artifact_hash: String = _hash("matter macro artifact bytes")
	var manifest: Dictionary = ArtifactManifest.create(
		macro_key,
		artifact_hash,
		24576,
		"MESHOPT",
		"application/vnd.planetsimulator.mesh",
		8.0,
		[-1000.0, -1000.0, -1000.0, 1000.0, 1000.0, 1000.0],
		false,
		false,
		4
	)
	_assert_ok(ArtifactManifest.validate(manifest), "Artifact manifest rejected")
	_assert(String(manifest["artifact_hash"]) == artifact_hash, "Artifact content hash changed")
	_assert(int(manifest["byte_size"]) == 24576, "Artifact size changed")
	var wrong_media: Dictionary = manifest.duplicate(true)
	wrong_media["media_type"] = "Application/Mesh"
	wrong_media["checksum"] = Utils.compute_checksum(wrong_media)
	_assert_fail(ArtifactManifest.validate(wrong_media), "Non-canonical media type accepted")
	var none_key: Dictionary = _key(source, 4, "NONE", "representation-scope/matter/body")
	var none_manifest: Dictionary = manifest.duplicate(true)
	none_manifest["representation_key"] = none_key
	none_manifest["checksum"] = Utils.compute_checksum(none_manifest)
	_assert_fail(ArtifactManifest.validate(none_manifest), "NONE artifact manifest accepted")


func _test_descriptors() -> void:
	var source: Dictionary = _construction_source(11)
	var key: Dictionary = _key(source, 2, "MACRO_PROXY", "representation-scope/construction/station")
	var manifest: Dictionary = ArtifactManifest.create(
		key,
		_hash("station proxy artifact"),
		12000,
		"MESHOPT",
		"application/vnd.planetsimulator.mesh",
		5.0,
		[-200.0, -100.0, -50.0, 200.0, 100.0, 50.0],
		false,
		false,
		3
	)
	var ready: Dictionary = Descriptor.from_manifest(manifest)
	_assert_ok(Descriptor.validate(ready), "READY descriptor rejected")
	_assert(String(ready["availability"]) == "READY", "Descriptor availability changed")
	var candidate: Dictionary = Descriptor.to_candidate(ready)
	_assert_ok(Candidate.validate(candidate), "Descriptor candidate projection rejected")
	_assert(bool(candidate["ready"]), "READY descriptor produced unready candidate")
	var building: Dictionary = Descriptor.create(key, "BUILDING", 5.0, 12000, false, false, "")
	_assert_ok(Descriptor.validate(building), "BUILDING descriptor rejected")
	var building_candidate: Dictionary = Descriptor.to_candidate(building)
	_assert_ok(Candidate.validate(building_candidate), "BUILDING descriptor candidate rejected")
	_assert(not bool(building_candidate["ready"]), "BUILDING descriptor produced ready candidate")
	var invalid: Dictionary = building.duplicate(true)
	invalid["artifact_hash"] = _hash("premature")
	invalid["checksum"] = Utils.compute_checksum(invalid)
	_assert_fail(Descriptor.validate(invalid), "BUILDING descriptor with artifact accepted")


func _test_dependency_sets() -> void:
	var child_a: Dictionary = _dependency_child("MATTER", "matter-brick/alpha", 4, 12, "brick-a")
	var child_b: Dictionary = _dependency_child("MATTER", "matter-brick/beta", 4, 9, "brick-b")
	var first: Dictionary = DependencySet.create(
		"MATTER",
		"body/asteroid-mw0",
		"representation-scope/matter/cluster-7",
		[child_b, child_a]
	)
	var second: Dictionary = DependencySet.create(
		"MATTER",
		"body/asteroid-mw0",
		"representation-scope/matter/cluster-7",
		[child_a, child_b]
	)
	_assert_ok(DependencySet.validate(first), "Dependency set rejected")
	_assert(first == second, "Dependency set depends on input order")
	_assert(String(first["child_revisions"][0]["source_id"]) == "matter-brick/alpha", "Dependency sorting changed")
	_assert(String(first["dependency_hash"]) == Utils.payload_hash(first["child_revisions"]), "Dependency hash changed")
	var duplicate: Dictionary = DependencySet.create(
		"MATTER",
		"body/asteroid-mw0",
		"representation-scope/matter/cluster-7",
		[child_a, child_a]
	)
	_assert(duplicate.is_empty(), "Duplicate dependency accepted")
	var tampered: Dictionary = first.duplicate(true)
	tampered["child_revisions"][0]["source_revision"] = 13
	tampered["checksum"] = Utils.compute_checksum(tampered)
	_assert_fail(DependencySet.validate(tampered), "Stale dependency hash accepted")


func _test_interest_and_selection() -> void:
	var source: Dictionary = _matter_source(7)
	var detail: Dictionary = _candidate(source, 0, "DETAIL", "representation-scope/matter/local", 0.05, 500000, true, true, true)
	var simplified: Dictionary = _candidate(source, 1, "SIMPLIFIED_MESH", "representation-scope/matter/region", 1.0, 100000, true, false, true)
	var macro: Dictionary = _candidate(source, 2, "MACRO_PROXY", "representation-scope/matter/body", 8.0, 20000, false, false, true)
	var impostor: Dictionary = _candidate(source, 3, "IMPOSTOR", "representation-scope/matter/body", 50.0, 5000, false, false, true)
	var near_request: Dictionary = _request(source, 1000.0, 2.0, 2.0, false, false, 500000, [])
	_assert_ok(InterestRequest.validate(near_request), "Near interest request rejected")
	var near_result: Dictionary = Selector.select(near_request, [macro, detail, simplified])
	_assert_ok(near_result, "Near selection failed")
	_assert(int(_selected_key(near_result).get("lod_level", -1)) == 1, "Near selection did not choose coarsest acceptable LOD")
	_assert(String(_selected_key(near_result).get("artifact_kind", "")) == "SIMPLIFIED_MESH", "Near selection kind changed")
	_assert(absf(float(near_result["details"]["screen_error_px"]) - 1.0) < 0.000000001, "Near selected screen error changed")
	_assert(int(near_result["details"]["eligible_count"]) == 2, "Near eligible count changed")

	var interior_request: Dictionary = _request(source, 1000.0, 2.0, 2.0, true, true, 600000, [])
	var interior_result: Dictionary = Selector.select(interior_request, [macro, simplified, detail])
	_assert_ok(interior_result, "Interior selection failed")
	_assert(String(_selected_key(interior_result).get("artifact_kind", "")) == "DETAIL", "Interior request did not force detail")

	var far_request: Dictionary = _request(source, 10000.0, 2.0, 20.0, false, false, 30000, [])
	var far_result: Dictionary = Selector.select(far_request, [detail, macro, simplified])
	_assert_ok(far_result, "Far selection failed")
	_assert(String(_selected_key(far_result).get("artifact_kind", "")) == "MACRO_PROXY", "Far selection did not choose macro proxy")

	var orbit_request: Dictionary = _request(source, 100000.0, 1.0, 100.0, false, false, 6000, ["IMPOSTOR"])
	var orbit_result: Dictionary = Selector.select(orbit_request, [macro, impostor])
	_assert_ok(orbit_result, "Orbit selection failed")
	_assert(String(_selected_key(orbit_result).get("artifact_kind", "")) == "IMPOSTOR", "Preferred impostor was not selected")

	var stale_source: Dictionary = _matter_source(6)
	var stale_candidate: Dictionary = _candidate(stale_source, 0, "DETAIL", "representation-scope/matter/local", 0.01, 1000, true, true, true)
	_assert_fail(Selector.select(near_request, [stale_candidate]), "Stale source candidate accepted")
	var unready: Dictionary = _candidate(source, 0, "DETAIL", "representation-scope/matter/local", 0.01, 1000, true, true, false)
	_assert_fail(Selector.select(near_request, [unready]), "Unready candidate accepted")
	var tiny_budget: Dictionary = _request(source, 1000.0, 2.0, 2.0, false, false, 999, [])
	_assert_fail(Selector.select(tiny_budget, [detail, simplified, macro]), "Candidate above bandwidth budget accepted")

	var construction_source: Dictionary = _construction_source(11)
	var construction_candidate: Dictionary = _candidate(
		construction_source,
		2,
		"MACRO_PROXY",
		"representation-scope/construction/station",
		5.0,
		12000,
		false,
		false,
		true
	)
	var construction_request: Dictionary = _request(construction_source, 5000.0, 2.0, 10.0, false, false, 20000, [])
	var construction_result: Dictionary = Selector.select(construction_request, [macro, construction_candidate])
	_assert_ok(construction_result, "Construction selection failed")
	_assert(String(_selected_key(construction_result)["source_revision"]["source_domain"]) == "CONSTRUCTION", "Matter candidate leaked into construction selection")

	var unsorted_preference: Dictionary = near_request.duplicate(true)
	unsorted_preference["preferred_artifact_kinds"] = ["SIMPLIFIED_MESH", "DETAIL"]
	unsorted_preference["checksum"] = Utils.compute_checksum(unsorted_preference)
	_assert_fail(InterestRequest.validate(unsorted_preference), "Unsorted preferred kinds accepted")


func _test_invalidation() -> void:
	var previous: Dictionary = _matter_source(7)
	var current: Dictionary = _matter_source(8)
	var invalidation: Dictionary = Invalidation.create(
		"representation-invalidation/matter/operation-8",
		previous,
		current,
		[-10.0, -10.0, -10.0, 10.0, 10.0, 10.0],
		"MUTATION",
		["representation-scope/matter/body", "representation-scope/matter/cluster-7"],
		900
	)
	_assert_ok(Invalidation.validate(invalidation), "Mutation invalidation rejected")
	_assert(Array(invalidation["affected_scope_ids"]).size() == 2, "Invalidation scopes changed")
	var no_advance: Dictionary = Invalidation.create(
		"representation-invalidation/matter/no-advance",
		previous,
		previous,
		[-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
		"MUTATION",
		["representation-scope/matter/body"],
		901
	)
	_assert(no_advance.is_empty(), "Non-advancing invalidation accepted")
	var handoff_source: Dictionary = SourceRevision.create(
		"MATTER", "body/asteroid-mw0", 5, 7, previous["source_hash"], previous["dependency_hash"]
	)
	var handoff: Dictionary = Invalidation.create(
		"representation-invalidation/matter/handoff",
		previous,
		handoff_source,
		[-1000.0, -1000.0, -1000.0, 1000.0, 1000.0, 1000.0],
		"HANDOFF",
		["representation-scope/matter/body"],
		902
	)
	_assert_ok(Invalidation.validate(handoff), "Authority handoff invalidation rejected")
	var rollback_source: Dictionary = SourceRevision.create(
		"MATTER", "body/asteroid-mw0", 3, 8, _hash("rollback"), _hash("deps-rollback")
	)
	var rollback: Dictionary = invalidation.duplicate(true)
	rollback["new_source_revision"] = rollback_source
	rollback["checksum"] = Utils.compute_checksum(rollback)
	_assert_fail(Invalidation.validate(rollback), "Authority rollback invalidation accepted")


func _test_cache_entries() -> void:
	var source: Dictionary = _matter_source(7)
	var key: Dictionary = _key(source, 2, "MACRO_PROXY", "representation-scope/matter/body")
	var manifest: Dictionary = ArtifactManifest.create(
		key,
		_hash("cached macro"),
		20000,
		"MESHOPT",
		"application/vnd.planetsimulator.mesh",
		8.0,
		[-1000.0, -1000.0, -1000.0, 1000.0, 1000.0, 1000.0],
		false,
		false,
		2
	)
	var building: Dictionary = CacheEntry.create(key, {}, "BUILDING", 100, 0)
	var ready: Dictionary = CacheEntry.create(key, manifest, "READY", 101, 20000)
	var stale: Dictionary = CacheEntry.create(key, manifest, "STALE", 102, 20000)
	var evicted: Dictionary = CacheEntry.create(key, manifest, "EVICTED", 103, 0)
	var failed: Dictionary = CacheEntry.create(key, {}, "FAILED", 104, 0, "REPRESENTATION_BUILD_FAILED")
	_assert_ok(CacheEntry.validate(building), "BUILDING cache entry rejected")
	_assert_ok(CacheEntry.validate(ready), "READY cache entry rejected")
	_assert_ok(CacheEntry.validate(stale), "STALE cache entry rejected")
	_assert_ok(CacheEntry.validate(evicted), "EVICTED cache entry rejected")
	_assert_ok(CacheEntry.validate(failed), "FAILED cache entry rejected")
	_assert(CacheEntry.can_transition("BUILDING", "READY"), "BUILDING to READY transition rejected")
	_assert(CacheEntry.can_transition("READY", "STALE"), "READY to STALE transition rejected")
	_assert(CacheEntry.can_transition("STALE", "BUILDING"), "STALE to BUILDING transition rejected")
	_assert(not CacheEntry.can_transition("READY", "BUILDING"), "READY to BUILDING transition accepted without stale fence")
	_assert(not CacheEntry.can_transition("EVICTED", "READY"), "EVICTED to READY transition accepted without rebuild")
	var wrong_size: Dictionary = ready.duplicate(true)
	wrong_size["resident_bytes"] = 19999
	wrong_size["checksum"] = Utils.compute_checksum(wrong_size)
	_assert_fail(CacheEntry.validate(wrong_size), "READY cache size mismatch accepted")
	var wrong_key: Dictionary = ready.duplicate(true)
	wrong_key["representation_key"] = _key(source, 1, "SIMPLIFIED_MESH", "representation-scope/matter/region")
	wrong_key["checksum"] = Utils.compute_checksum(wrong_key)
	_assert_fail(CacheEntry.validate(wrong_key), "Cache artifact with another key accepted")


func _test_runtime_object_rejection() -> void:
	var node: Node3D = Node3D.new()
	_assert(Utils.canonical_json({"runtime_node": node}).is_empty(), "Runtime Node3D accepted in representation DTO")
	node.free()
	var source: Dictionary = _matter_source(7)
	var json: String = Utils.canonical_json({
		"source": source,
		"bounds": [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
	})
	_assert(not json.is_empty(), "Valid representation payload is not JSON-safe")
	_assert(JSON.parse_string(json) != null, "Canonical representation JSON cannot be decoded")


func _matter_source(revision: int) -> Dictionary:
	return SourceRevision.create(
		"MATTER",
		"body/asteroid-mw0",
		4,
		revision,
		_hash("matter-source-%d" % revision),
		_hash("matter-dependencies-%d" % revision)
	)


func _construction_source(revision: int) -> Dictionary:
	return SourceRevision.create(
		"CONSTRUCTION",
		"construct/station-alpha",
		9,
		revision,
		_hash("construction-source-%d" % revision),
		_hash("construction-dependencies-%d" % revision)
	)


func _key(source: Dictionary, lod_level: int, artifact_kind: String, scope_id: String) -> Dictionary:
	return RepresentationKey.create(source, scope_id, lod_level, artifact_kind)


func _candidate(
	source: Dictionary,
	lod_level: int,
	artifact_kind: String,
	scope_id: String,
	geometric_error_m: float,
	estimated_bytes: int,
	collision_capable: bool,
	interior_capable: bool,
	ready: bool
) -> Dictionary:
	return Candidate.create(
		_key(source, lod_level, artifact_kind, scope_id),
		geometric_error_m,
		estimated_bytes,
		collision_capable,
		interior_capable,
		ready,
		_hash("%s-%s-%d" % [source["source_id"], artifact_kind, lod_level]) if ready else ""
	)


func _request(
	source: Dictionary,
	distance_m: float,
	maximum_screen_error_px: float,
	maximum_geometric_error_m: float,
	collision_required: bool,
	interior_required: bool,
	bandwidth_budget_bytes: int,
	preferred_artifact_kinds: Array
) -> Dictionary:
	return InterestRequest.create(
		"representation-request/test/1",
		"observer/test/1",
		source,
		distance_m,
		1000.0,
		maximum_screen_error_px,
		maximum_geometric_error_m,
		collision_required,
		interior_required,
		bandwidth_budget_bytes,
		preferred_artifact_kinds,
		1
	)


func _dependency_child(
	source_domain: String,
	source_id: String,
	authority_epoch: int,
	source_revision: int,
	hash_seed: String
) -> Dictionary:
	return {
		"source_domain": source_domain,
		"source_id": source_id,
		"authority_epoch": authority_epoch,
		"source_revision": source_revision,
		"source_hash": _hash(hash_seed),
	}


func _selected_key(result: Dictionary) -> Dictionary:
	var details: Dictionary = result.get("details", {})
	var candidate: Dictionary = details.get("candidate", {})
	var raw_key = candidate.get("representation_key", {})
	return raw_key if typeof(raw_key) == TYPE_DICTIONARY else {}


func _hash(text: String) -> String:
	return text.sha256_text()


func _assert_ok(result: Dictionary, message: String) -> void:
	_assert(bool(result.get("success", false)), "%s: %s" % [message, result.get("error_code", "")])


func _assert_fail(result: Dictionary, message: String) -> void:
	_assert(not bool(result.get("success", false)), message)


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("RL0 representation contracts: PASS (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("RL0 representation contracts: FAIL (%d failures, %d assertions)" % [failures.size(), assertions])
	quit(1)
