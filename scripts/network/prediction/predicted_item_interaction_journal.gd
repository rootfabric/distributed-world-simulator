extends "res://scripts/network/prediction/predicted_item_interaction_journal_base.gd"

# FIX5: a rejected optimistic operation may be resolved with the exact same
# authoritative Item Graph revision/checksum that existed before prediction.
# The base journal correctly removes the pending entry, but its duplicate
# authoritative fast-path historically returned the stale projected snapshot.
# Rebuild presentation from the unchanged authority plus the remaining pending
# predictions whenever an authoritative duplicate is adopted.
const FIX5_DUPLICATE_AUTHORITY_POLICY := "REPROJECT_SAME_REVISION_AFTER_PENDING_CHANGE_V1"

var _fix5_same_revision_reprojections: int = 0


func adopt_authoritative(snapshot: Dictionary, now_ms: int = -1) -> Dictionary:
	var result: Dictionary = super.adopt_authoritative(snapshot, now_ms)
	if not bool(result.get("success", false)):
		return result
	var details: Dictionary = Dictionary(result.get("details", {})).duplicate(true)
	if not bool(details.get("duplicate", false)):
		return result
	var rebuilt: Dictionary = _rebuild_projection(false)
	if not bool(rebuilt.get("success", false)):
		_last_error_code = String(rebuilt.get("error_code", "ITEM_PREDICTION_REPROJECT_FAILED"))
		return rebuilt
	_fix5_same_revision_reprojections += 1
	_last_error_code = ""
	details["presentation_snapshot"] = _decorate_projection(_presentation_snapshot)
	details["pending_count"] = _pending.size()
	details["same_revision_reprojected"] = true
	result["details"] = details
	return result


func get_report() -> Dictionary:
	var report: Dictionary = super.get_report()
	report["duplicate_authority_policy"] = FIX5_DUPLICATE_AUTHORITY_POLICY
	report["same_revision_reprojections"] = _fix5_same_revision_reprojections
	return report
