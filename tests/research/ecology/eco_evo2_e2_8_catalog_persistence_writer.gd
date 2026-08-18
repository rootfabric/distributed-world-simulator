extends SceneTree
const Persistence = preload("res://scripts/research/ecology/plant_catalog_persistence_v1.gd")
func _init() -> void:
	var path := _arg("--artifact-path=")
	if path.is_empty():
		push_error("E2.8 writer missing --artifact-path")
		quit(1); return
	var artifact := Persistence.build_artifact()
	var bytes := Persistence.serialize(artifact)
	if artifact.is_empty() or bytes.is_empty():
		push_error("E2.8 writer failed to build canonical artifact")
		quit(1); return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("E2.8 writer failed to open artifact path")
		quit(1); return
	file.store_buffer(bytes)
	file.close()
	print("ECO.EVO2 E2.8 writer: PASS")
	print("content_hash=" + String(artifact["content_hash"]))
	print("provenance_hash=" + String(artifact["provenance_hash"]))
	print("transport_sha256=" + Persistence.transport_sha256(bytes))
	print("catalog_hash=" + String(Dictionary(artifact["species_catalog"])["catalog_hash"]))
	print("artifact_bytes=" + str(bytes.size()))
	quit(0)
func _arg(prefix: String) -> String:
	for value in OS.get_cmdline_user_args():
		var text := String(value)
		if text.begins_with(prefix): return text.substr(prefix.length())
	return ""
