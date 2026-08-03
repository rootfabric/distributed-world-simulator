extends RefCounted

const Utils = preload("res://scripts/simulation/representation/representation_contract_utils.gd")
const BusUtils = preload("res://scripts/network/bus/message_bus_contract_utils.gd")
const ArtifactManifest = preload("res://scripts/simulation/representation/contracts/representation_artifact_manifest.gd")

var _manifests: Dictionary = {}
var _contents: Dictionary = {}
var _total_bytes: int = 0
var _maximum_bytes: int = 268435456


func configure(maximum_bytes: int) -> Dictionary:
	if maximum_bytes < 1 or maximum_bytes > 1073741824:
		return Utils.failure("INVALID_REPRESENTATION_ARTIFACT_STORE_CAPACITY")
	if maximum_bytes < _total_bytes:
		return Utils.failure("REPRESENTATION_ARTIFACT_STORE_CAPACITY_BELOW_RESIDENT")
	_maximum_bytes = maximum_bytes
	return Utils.success({"maximum_bytes": _maximum_bytes})


func register(manifest: Dictionary, content: PackedByteArray) -> Dictionary:
	var checked: Dictionary = ArtifactManifest.validate(manifest)
	if not bool(checked.get("success", false)):
		return checked
	if content.size() != int(manifest["byte_size"]):
		return Utils.failure("REPRESENTATION_ARTIFACT_CONTENT_SIZE_MISMATCH")
	var artifact_hash: String = String(manifest["artifact_hash"])
	if BusUtils.content_hash_from_bytes(content) != artifact_hash:
		return Utils.failure("REPRESENTATION_ARTIFACT_CONTENT_HASH_MISMATCH")
	if _manifests.has(artifact_hash):
		if _manifests[artifact_hash] == manifest and _contents[artifact_hash] == content:
			return Utils.success({"duplicate": true, "total_bytes": _total_bytes})
		return Utils.failure("REPRESENTATION_ARTIFACT_HASH_CONFLICT")
	if _total_bytes + content.size() > _maximum_bytes:
		return Utils.failure("REPRESENTATION_ARTIFACT_STORE_BACKPRESSURE", {
			"retryable": true,
			"resident_bytes": _total_bytes,
			"requested_bytes": content.size(),
		})
	_manifests[artifact_hash] = manifest.duplicate(true)
	_contents[artifact_hash] = content.duplicate()
	_total_bytes += content.size()
	return Utils.success({"duplicate": false, "total_bytes": _total_bytes})


func has(artifact_hash: String) -> bool:
	return _manifests.has(artifact_hash) and _contents.has(artifact_hash)


func manifest(artifact_hash: String) -> Dictionary:
	return _manifests[artifact_hash].duplicate(true) if _manifests.has(artifact_hash) else {}


func content(artifact_hash: String) -> PackedByteArray:
	return _contents[artifact_hash].duplicate() if _contents.has(artifact_hash) else PackedByteArray()


func remove(artifact_hash: String) -> Dictionary:
	if not _manifests.has(artifact_hash):
		return Utils.failure("REPRESENTATION_ARTIFACT_NOT_FOUND")
	_total_bytes -= int(_manifests[artifact_hash]["byte_size"])
	_manifests.erase(artifact_hash)
	_contents.erase(artifact_hash)
	return Utils.success({"total_bytes": _total_bytes})


func manifests() -> Array:
	var hashes: Array = _manifests.keys()
	hashes.sort()
	var result: Array = []
	for artifact_hash in hashes:
		result.append(_manifests[artifact_hash].duplicate(true))
	return result


func total_bytes() -> int:
	return _total_bytes
