extends "res://tests/research/fabric1/fabric_holdout_r4_probe.gd"

# Diagnostic of the existing public JSON save path, not a checksum repair.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("R4_DIAG_USAGE: normalized-input.json output.json")
		quit(2)
		return
	var input = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not input is Array or input.is_empty():
		push_error("R4_DIAG_INPUT")
		quit(2)
		return
	var sources := _sources(input[0])
	var authority := _authority(sources)
	var original = B.new()
	var initialized: Dictionary = original.initialize(sources, authority)
	if not initialized.success:
		push_error("R4_DIAG_INITIALIZATION")
		quit(2)
		return
	var document: Dictionary = original.export_replay()
	var store: Dictionary = original.canonical_state()
	var matter := {"mechanical_matter": sources.mechanical_matter, "electrical_matter": sources.electrical_matter}
	var warm = B.new()
	var warm_result: Dictionary = warm.replay(document, store, matter, authority, document.checksum)
	var wire := JSON.stringify(document, "", true, true)
	var restored: Dictionary = JSON.parse_string(wire)
	var after_json = B.new()
	var restored_result: Dictionary = after_json.replay(restored, store, matter, authority, document.checksum)
	var result := {"case_id": input[0].id, "source": sources, "live_checksum": U.validate_checksum(document), "warm_replay": warm_result.success, "json_checksum": U.validate_checksum(restored), "json_replay": restored_result, "wire_sha256": wire.sha256_text(), "differences": _differences(document, restored, ""), "subject_modified": false}
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		push_error("R4_DIAG_OUTPUT")
		quit(2)
		return
	file.store_string(JSON.stringify(result, "", true, true) + "\n")
	file.close()
	print("R4_SERIALIZATION_OBSERVATION=", JSON.stringify(result, "", true, true))
	quit(0) # The observation completed; json_replay can be a genuine FAIL.

func _differences(a: Variant, b: Variant, path: String) -> Array:
	var result: Array = []
	if a is Dictionary and b is Dictionary:
		for key in a:
			result.append_array(_differences(a[key], b[key], path + "/" + key))
	elif a is Array and b is Array:
		for index in range(a.size()):
			result.append_array(_differences(a[index], b[index], path + "/" + str(index)))
	elif (a is float or a is int) and (b is float or b is int):
		if float(a) != float(b):
			result.append({"path": path, "before": var_to_bytes(float(a)).hex_encode(), "after": var_to_bytes(float(b)).hex_encode()})
	elif a != b:
		result.append({"path": path, "before": a, "after": b})
	return result
