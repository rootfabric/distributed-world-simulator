class_name QuaterniusFpeOptimizedLab
extends "res://scripts/characters/lab/quaternius_first_person_embodiment_lab.gd"

# Fix6 keeps the accepted CH9.6 runtime behind QuaterniusFpeCh9_6Host. The host
# classifies canonical Item Graph projections before applying them. Hotbar-only
# metadata changes therefore dirty only hand/hotbar presentation; structural
# graph changes still dirty equipment and hotbar presentation together.


func _bind_network_projection_signal() -> void:
	if _network_projection_signal_bound or base_lab == null:
		return
	if base_lab.has_signal("fpe_canonical_projection_applied"):
		var callback := Callable(self, "_on_fpe_host_projection_applied")
		if not base_lab.is_connected("fpe_canonical_projection_applied", callback):
			base_lab.connect("fpe_canonical_projection_applied", callback)
		_network_projection_signal_bound = true
		_equipment_sync_dirty = true
		_hotbar_presentation_dirty = true
		return
	# Preserve the original research fallback if the optimized host is replaced
	# during isolated tests.
	super._bind_network_projection_signal()


func _on_fpe_host_projection_applied(classification: String, _snapshot: Dictionary) -> void:
	_hotbar_presentation_dirty = true
	if classification != "HOTBAR_METADATA_ONLY":
		_equipment_sync_dirty = true


func _refresh_status() -> void:
	super._refresh_status()
	if fpe_status_label == null or base_lab == null or not base_lab.has_method("get_fpe_status_performance_report"):
		return
	var report: Dictionary = base_lab.get_fpe_status_performance_report()
	var suffix := (
		"\nprojection fast/full: %d / %d | fast max %.3f ms | auto heavy HUD: %s"
		% [
			int(report.get("projection_hotbar_fast", 0)),
			int(report.get("projection_full", 0)),
			float(report.get("projection_fast_max_us", 0)) / 1000.0,
			"OFF" if not bool(report.get("automatic_heavy_status", true)) else "ON",
		]
	)
	if not fpe_status_label.text.ends_with(suffix):
		fpe_status_label.text += suffix
