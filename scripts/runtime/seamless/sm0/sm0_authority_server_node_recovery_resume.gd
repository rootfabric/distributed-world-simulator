extends "res://scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd"

# Healthy recovery should resume a persisted retired-source transaction before
# the first process-frame socket poll. Otherwise an already queued stale client
# move can be answered before the restored COMMIT/redirect is re-issued.
# Lost packets remain covered by the normal 200 ms source retry loop.


func setup(config: Dictionary) -> Dictionary:
	var result: Dictionary = super.setup(config)
	if not bool(result.get("success", false)):
		return result
	if (
		_recovery_restored
		and _recovery_last_phase == "SOURCE_RETIRED"
		and not _source_transfer.is_empty()
		and String(_source_transfer.get("stage", "")) == "COMMIT_SENT"
	):
		_event("SM0_RECOVERY_SOURCE_IMMEDIATE_RESUME", {
			"generation": _recovery_generation,
			"transfer_id": String(_source_transfer.get("transfer_id", "")),
			"directory": _directory,
		})
		_send_source_commit()
		_send_client_redirect()
	return result
