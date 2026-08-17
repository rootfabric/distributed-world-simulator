extends RefCounted

const SCHEMA := "distributed_world_simulator.mrpf_h0_projection.v1"
const LEVELS := {
	"SPACE": 0,
	"EARTH": 1,
	"SURFACE": 2,
	"BASE": 3,
}

static func create_representation(
	representation_id: String,
	canonical_subject_id: String,
	source_domain_id: String,
	source_authority_id: String,
	publisher_id: String,
	source_revision: int,
	representation_class: String,
	lod_level: int,
	coverage_scope: String,
	reference_frame_id: String,
	content_hash: String,
	valid_from_revision: int,
	replacement_group_id: String,
	domain_level: String
) -> Dictionary:
	var value := {
		"schema": SCHEMA,
		"representation_id": representation_id.strip_edges(),
		"canonical_subject_id": canonical_subject_id.strip_edges(),
		"source_domain_id": source_domain_id.strip_edges(),
		"source_authority_id": source_authority_id.strip_edges(),
		"publisher_id": publisher_id.strip_edges(),
		"source_revision": source_revision,
		"representation_class": representation_class.strip_edges(),
		"lod_level": lod_level,
		"coverage_scope": coverage_scope.strip_edges(),
		"reference_frame_id": reference_frame_id.strip_edges(),
		"content_hash": content_hash.strip_edges(),
		"valid_from_revision": valid_from_revision,
		"replacement_group_id": replacement_group_id.strip_edges(),
		"domain_level": domain_level.strip_edges(),
		"presentation_only": true,
		"canonical_write_allowed": false,
	}
	value["checksum"] = checksum(value)
	return value

static func validate(value: Dictionary) -> Dictionary:
	if String(value.get("schema", "")) != SCHEMA:
		return _failure("MRPF_H0_SCHEMA_INVALID")
	for key in [
		"representation_id", "canonical_subject_id", "source_domain_id",
		"source_authority_id", "publisher_id", "representation_class",
		"coverage_scope", "reference_frame_id", "content_hash",
		"replacement_group_id", "domain_level"
	]:
		if String(value.get(key, "")).strip_edges().is_empty():
			return _failure("MRPF_H0_FIELD_REQUIRED", {"field": key})
	if int(value.get("source_revision", 0)) < 1:
		return _failure("MRPF_H0_SOURCE_REVISION_INVALID")
	if int(value.get("valid_from_revision", 0)) < 0:
		return _failure("MRPF_H0_VALID_FROM_REVISION_INVALID")
	if int(value.get("lod_level", -1)) < 0:
		return _failure("MRPF_H0_LOD_INVALID")
	var level := String(value.get("domain_level", ""))
	if not LEVELS.has(level):
		return _failure("MRPF_H0_DOMAIN_LEVEL_INVALID")
	if value.get("presentation_only") != true or value.get("canonical_write_allowed") != false:
		return _failure("MRPF_H0_PRESENTATION_FLAGS_INVALID")
	if String(value.get("checksum", "")) != checksum(value):
		return _failure("MRPF_H0_CHECKSUM_MISMATCH")
	return _success()

static func specificity(value: Dictionary) -> int:
	return int(LEVELS.get(String(value.get("domain_level", "")), -1))

static func checksum(value: Dictionary) -> String:
	var fields := [
		String(value.get("schema", "")),
		String(value.get("representation_id", "")),
		String(value.get("canonical_subject_id", "")),
		String(value.get("source_domain_id", "")),
		String(value.get("source_authority_id", "")),
		String(value.get("publisher_id", "")),
		str(int(value.get("source_revision", 0))),
		String(value.get("representation_class", "")),
		str(int(value.get("lod_level", -1))),
		String(value.get("coverage_scope", "")),
		String(value.get("reference_frame_id", "")),
		String(value.get("content_hash", "")),
		str(int(value.get("valid_from_revision", 0))),
		String(value.get("replacement_group_id", "")),
		String(value.get("domain_level", "")),
		"1" if bool(value.get("presentation_only", false)) else "0",
		"1" if bool(value.get("canonical_write_allowed", true)) else "0",
	]
	return "|".join(fields).sha256_text()

static func _success(details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "details": details}

static func _failure(error_code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": error_code, "details": details}
