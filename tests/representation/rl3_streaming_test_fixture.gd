extends RefCounted

const BusUtils = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const SourceRevision = preload("res://scripts/simulation/representation/contracts/representation_source_revision.gd")
const RepresentationKey = preload("res://scripts/simulation/representation/contracts/representation_key.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")
const InterestRequest = preload("res://scripts/simulation/representation/contracts/representation_interest_request.gd")
const StreamRequest = preload("res://scripts/simulation/representation/network/contracts/representation_stream_request.gd")
const ScopeBinding = preload("res://scripts/simulation/representation/network/contracts/representation_stream_scope_binding.gd")


static func build() -> Dictionary:
	var source: Dictionary = SourceRevision.create(
		"MATTER", "body/asteroid-rl3-process", 9, 31,
		_hash("rl3-process-source"), _hash("rl3-process-dependencies")
	)
	var manifests: Array = []
	var artifacts: Array = []
	var fixtures: Array = [
		{"scope": "region/rl3-process-macro", "lod": 2, "kind": "MACRO_PROXY", "error": 1.0, "size": 128, "fill": "P"},
		{"scope": "region/rl3-process-regional", "lod": 1, "kind": "SIMPLIFIED_MESH", "error": 0.2, "size": 224, "fill": "R"},
		{"scope": "region/rl3-process-detail", "lod": 0, "kind": "DETAIL", "error": 0.0, "size": 384, "fill": "F"},
	]
	for fixture in fixtures:
		var content: PackedByteArray = String(fixture["fill"]).repeat(int(fixture["size"])).to_utf8_buffer()
		var artifact_hash: String = BusUtils.content_hash_from_bytes(content)
		var key: Dictionary = RepresentationKey.create(
			source, String(fixture["scope"]), int(fixture["lod"]), String(fixture["kind"]),
			"representation-variant/process-surface"
		)
		var manifest: Dictionary = ArtifactManifest.create(
			key, artifact_hash, content.size(), "RAW", "application/vnd.planet-simulator.matter-mesh",
			float(fixture["error"]), [-32.0, -32.0, -32.0, 32.0, 32.0, 32.0],
			int(fixture["lod"]) == 0, int(fixture["lod"]) <= 1, 7
		)
		manifests.append(manifest)
		artifacts.append({"manifest": manifest, "content_base64": Marshalls.raw_to_base64(content)})
	return {"source": source, "manifests": manifests, "artifacts": artifacts}


static func request(source: Dictionary, revision: int, cached_hashes: Array = []) -> Dictionary:
	var hashes: Array = cached_hashes.duplicate()
	hashes.sort()
	var interest: Dictionary = InterestRequest.create(
		"interest/rl3-process-%d" % revision, "observer/rl3-process", source,
		100.0, 1000.0, 3.0, 0.5, false, false, 1024,
		["DETAIL", "MACRO_PROXY", "SIMPLIFIED_MESH"], revision
	)
	return StreamRequest.create(
		"stream-request/rl3-process-%d" % revision, interest, _scope_chain(), hashes, ["RAW"],
		true, 12.0, 3, 64, 128, 160, 0
	)


static func _scope_chain() -> Array:
	return [
		ScopeBinding.create(2, "region/rl3-process-macro"),
		ScopeBinding.create(1, "region/rl3-process-regional"),
		ScopeBinding.create(0, "region/rl3-process-detail"),
	]


static func _hash(value: String) -> String:
	return BusUtils.content_hash_from_bytes(value.to_utf8_buffer())
