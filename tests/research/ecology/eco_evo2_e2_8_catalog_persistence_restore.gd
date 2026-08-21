extends SceneTree
const Persistence = preload("res://scripts/research/ecology/plant_catalog_persistence_v1.gd")
func _init() -> void:
	var path := _arg("--artifact-path=")
	if path.is_empty() or not FileAccess.file_exists(path):
		push_error("E2.8 restore missing artifact")
		quit(1); return
	var bytes := FileAccess.get_file_as_bytes(path)
	var artifact := Persistence.restore(bytes)
	if artifact.is_empty():
		push_error("E2.8 restore rejected canonical artifact")
		quit(1); return
	var catalog: Dictionary = artifact["species_catalog"]
	var provenance: Dictionary = artifact["provenance"]
	print("ECO.EVO2 E2.8 restore: PASS")
	print("content_hash=" + String(artifact["content_hash"]))
	print("provenance_hash=" + String(artifact["provenance_hash"]))
	print("transport_sha256=" + Persistence.transport_sha256(bytes))
	print("catalog_hash=" + String(catalog["catalog_hash"]))
	print("entry_count=" + str(Array(catalog["entries"]).size()))
	print("parent_e2_7=" + String(provenance["e2_7_accepted_aggregate"]))
	quit(0)
func _arg(prefix: String) -> String:
	for value in OS.get_cmdline_user_args():
		var text := String(value)
		if text.begins_with(prefix): return text.substr(prefix.length())
	return ""
