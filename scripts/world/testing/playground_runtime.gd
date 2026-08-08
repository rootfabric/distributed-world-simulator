extends "res://scripts/world/testing/playground_runtime_base.gd"

# FIX5: Item Graph revision is an authority revision, not a presentation
# generation. Optimistic prediction and rollback can legitimately produce two
# different presentation graphs at the same authority revision. Therefore only
# strictly stale revisions are suppressed; same-revision projections are
# always applied so a rejected pickup can restore the WORLD representation.
const FIX5_ITEM_PROJECTION_POLICY := "APPLY_ALL_NONSTALE_SAME_REVISION_PROJECTIONS_V1"

var _fix5_same_revision_item_projection_applies: int = 0
var _fix5_stale_item_projection_suppressions: int = 0


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_m4_item_graph_snapshot = snapshot.duplicate(true)
	_m4_item_snapshot_updates += 1
	if not _network_playground_enabled or item_gameplay == null or _m7_item_adapter == null:
		return
	var revision := int(snapshot.get("revision", -1))
	if revision < _m7_last_item_revision:
		_fix5_stale_item_projection_suppressions += 1
		return
	var converted: Dictionary = _m7_item_adapter.convert(snapshot)
	if not bool(converted.get("success", false)):
		_m7_last_sync_error = String(converted.get("error_code", "M7_ITEM_REPLICA_CONVERSION_FAILED"))
		return
	var details: Dictionary = Dictionary(converted.get("details", {}))
	var apply_result: Dictionary = item_gameplay.apply_network_graph_snapshot(
		Dictionary(details.get("graph_snapshot", {})),
		revision,
		String(snapshot.get("checksum", ""))
	)
	if bool(apply_result.get("success", false)):
		if revision == _m7_last_item_revision:
			_fix5_same_revision_item_projection_applies += 1
		_m7_last_item_revision = revision
		_m7_last_sync_error = ""
	else:
		_m7_last_sync_error = String(apply_result.get("error_code", "M7_ITEM_REPLICA_APPLY_FAILED"))


func get_fix5_item_consistency_report() -> Dictionary:
	return {
		"projection_policy": FIX5_ITEM_PROJECTION_POLICY,
		"last_item_revision": _m7_last_item_revision,
		"same_revision_projection_applies": _fix5_same_revision_item_projection_applies,
		"stale_projection_suppressions": _fix5_stale_item_projection_suppressions,
		"last_sync_error": _m7_last_sync_error,
	}
