extends "res://scripts/persistence/lunar_world_repository_base.gd"

# JSON.parse_string() represents JSON numbers as floats, even when the source
# value was an integer. Manifest identity must therefore compare numeric
# Variants numerically instead of comparing their string representations.
# String-vs-number remains a hard mismatch so malformed identity data is not
# silently coerced.
func _identity_value_matches(saved_value, expected_value) -> bool:
	var saved_type: int = typeof(saved_value)
	var expected_type: int = typeof(expected_value)
	var saved_numeric: bool = saved_type == TYPE_INT or saved_type == TYPE_FLOAT
	var expected_numeric: bool = expected_type == TYPE_INT or expected_type == TYPE_FLOAT
	if saved_numeric or expected_numeric:
		return (
			saved_numeric
			and expected_numeric
			and is_equal_approx(float(saved_value), float(expected_value))
		)
	return str(saved_value) == str(expected_value)


func _validate_or_migrate_manifest_identity(manifest: Dictionary) -> bool:
	var migrated_fields := PackedStringArray()
	var legacy_scheme: String = "%s_v%d" % [
		partition_scheme,
		partition_scheme_revision,
	]
	if String(manifest.get("partition_scheme", "")) == legacy_scheme:
		manifest["partition_scheme"] = partition_scheme
		manifest["partition_scheme_revision"] = partition_scheme_revision
		migrated_fields.append("partition_scheme")
		migrated_fields.append("partition_scheme_revision")
	var identity_fields: Dictionary = {
		"universe_id": universe_id,
		"instance_id": instance_id,
		"partition_space_id": partition_space_id,
		"partition_scheme": partition_scheme,
		"partition_scheme_revision": partition_scheme_revision,
	}
	var mismatches := PackedStringArray()
	for field_value in identity_fields.keys():
		var field_name: String = String(field_value)
		var expected_value = identity_fields[field_name]
		if not manifest.has(field_name):
			manifest[field_name] = expected_value
			migrated_fields.append(field_name)
		elif not _identity_value_matches(manifest.get(field_name), expected_value):
			mismatches.append(field_name)
	if not partition_grid_descriptor.is_empty():
		if not manifest.has("partition_grid"):
			manifest["partition_grid"] = partition_grid_descriptor.duplicate(true)
			migrated_fields.append("partition_grid")
		elif not _partition_grid_identity_matches(
			manifest.get("partition_grid", {}),
			partition_grid_descriptor
		):
			mismatches.append("partition_grid")
	if not mismatches.is_empty():
		_emit_error(
			"World manifest identity mismatch (%s): %s" % [
				", ".join(mismatches),
				manifest_path,
			]
		)
		return false
	if not migrated_fields.is_empty():
		_write_json_atomic(manifest_path, manifest)
		_log("INFO", "world_manifest_identity_migrated", {
			"fields": Array(migrated_fields),
			"universe_id": universe_id,
			"instance_id": instance_id,
			"partition_space_id": partition_space_id,
		})
	return true


func _partition_grid_identity_matches(saved_value, expected: Dictionary) -> bool:
	if not saved_value is Dictionary:
		return false
	var saved: Dictionary = saved_value
	for field_name in [
		"schema",
		"scheme_id",
		"scheme_revision",
		"body_frame_id",
		"zones_per_face",
		"chunks_per_zone",
	]:
		if not _identity_value_matches(
			saved.get(field_name),
			expected.get(field_name)
		):
			return false
	return is_equal_approx(
		float(saved.get("body_radius_m", 0.0)),
		float(expected.get("body_radius_m", -1.0))
	)
