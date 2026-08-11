extends "res://scripts/world/testing/playground_view_relative_runtime_fix8.gd"

# FIX10 item projection consistency.
#
# NX6 optimistic item operations intentionally keep the authoritative Item Graph
# revision/checksum while adding/removing a local prediction overlay. A server
# rejection can therefore roll presentation back to the exact same authoritative
# revision that existed before prediction. The older playground callback skipped
# every same-revision event, leaving ItemGameplayController on a stale optimistic
# graph even after PredictedItemInteractionJournal had correctly rolled back.
#
# Item Graph update events are low-frequency and semantic. Apply every projected
# event delivered by M7NetworkItemCommandBridge; do not use authority revision as
# presentation identity. The ItemGameplayController remains a replica and never
# authors canonical Item Graph state.
const FIX10_ITEM_PROJECTION_POLICY: String = \
	"APPLY_EVERY_PROJECTED_ITEM_GRAPH_EVENT_SAME_REVISION_ROLLBACK_SAFE_V1"

var _fix10_item_projection_applies: int = 0
var _fix10_item_same_revision_reapplies: int = 0
var _fix10_item_projection_failures: int = 0


func _on_m4_item_graph_updated(snapshot: Dictionary) -> void:
	if snapshot.is_empty():
		return
	_m4_item_graph_snapshot = snapshot.duplicate(true)
	_m4_item_snapshot_updates += 1
	if not _network_playground_enabled or item_gameplay == null or _m7_item_adapter == null:
		return

	var revision := int(snapshot.get("revision", -1))
	var same_revision := revision == _m7_last_item_revision
	var converted: Dictionary = _m7_item_adapter.convert(snapshot)
	if not bool(converted.get("success", false)):
		_fix10_item_projection_failures += 1
		_m7_last_sync_error = String(
			converted.get("error_code", "M7_ITEM_REPLICA_CONVERSION_FAILED")
		)
		return
	var details: Dictionary = Dictionary(converted.get("details", {}))
	var apply_result: Dictionary = item_gameplay.apply_network_graph_snapshot(
		Dictionary(details.get("graph_snapshot", {})),
		revision,
		String(snapshot.get("checksum", ""))
	)
	if bool(apply_result.get("success", false)):
		_fix10_item_projection_applies += 1
		if same_revision:
			_fix10_item_same_revision_reapplies += 1
		_m7_last_item_revision = revision
		_m7_last_sync_error = ""
	else:
		_fix10_item_projection_failures += 1
		_m7_last_sync_error = String(
			apply_result.get("error_code", "M7_ITEM_REPLICA_APPLY_FAILED")
		)


func create_m3_graphical_client_report() -> Dictionary:
	var report: Dictionary = super.create_m3_graphical_client_report()
	report["fix10_item_projection_consistency"] = {
		"policy": FIX10_ITEM_PROJECTION_POLICY,
		"applies": _fix10_item_projection_applies,
		"same_revision_reapplies": _fix10_item_same_revision_reapplies,
		"failures": _fix10_item_projection_failures,
	}
	return report
