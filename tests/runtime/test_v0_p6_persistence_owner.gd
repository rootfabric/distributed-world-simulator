extends SceneTree

## P6 R3: P6 owns no persistence format. The adapter can only delegate to the
## existing authoritative recovery coordinator.

const AdapterScript = preload("res://scripts/runtime/networked_gameplay/p6/p6_persistence_owner.gd")
const OwnershipMap = preload("res://scripts/runtime/networked_gameplay/p6/p6_ownership_map.gd")

var assertions := 0
var failures: Array[String] = []


class FakeCoordinator extends RefCounted:
	var persists: int = 0
	var recovers: int = 0

	func persist_checkpoint(checkpoint_id: String, generation: int, previous_generation: int, operation_id: String = "") -> Dictionary:
		persists += 1
		return {
			"success": true,
			"details": {
				"checkpoint": {
					"checkpoint_id": checkpoint_id,
					"generation": generation,
					"previous_generation": previous_generation,
					"committed_operation_id": operation_id,
				},
				"repository": {"result": "COMMITTED"},
			},
		}

	func recover_latest() -> Dictionary:
		recovers += 1
		return {"success": true, "details": {"source": "ACTIVE", "checkpoint": {"generation": 1}}}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		print("[p6-r3-persistence][FAIL] %s" % message)


func _init() -> void:
	var adapter = AdapterScript.new()
	var before := adapter.get_report()
	_assert(not bool(before["configured"]), "adapter unexpectedly configured")
	_assert(not bool(before["private_filesystem"]), "P6 still declares a private filesystem")
	_assert(not bool(before["private_save_format"]), "P6 still declares a private save format")
	_assert(String(before["persistence_owner"]) == OwnershipMap.EXISTING_PERSISTENCE_OWNER_ID, "wrong canonical persistence owner")

	var invalid: Dictionary = adapter.configure(RefCounted.new())
	_assert(not bool(invalid.get("success", false)), "invalid persistence coordinator accepted")

	var coordinator = FakeCoordinator.new()
	var configured: Dictionary = adapter.configure(coordinator)
	_assert(bool(configured.get("success", false)), "canonical coordinator rejected")
	_assert(String(configured["details"]["persistence_owner"]) == OwnershipMap.EXISTING_PERSISTENCE_OWNER_ID, "configured owner mismatch")

	var persisted: Dictionary = adapter.persist_checkpoint("checkpoint/p6/r3/1", 1, 0, "operation/p6-r3-1")
	_assert(bool(persisted.get("success", false)), "delegated persist failed")
	_assert(coordinator.persists == 1, "adapter did not delegate exactly once")
	_assert(String(persisted["details"]["checkpoint"]["committed_operation_id"]) == "operation/p6-r3-1", "operation id not preserved")

	var recovered: Dictionary = adapter.recover_latest()
	_assert(bool(recovered.get("success", false)), "delegated recovery failed")
	_assert(coordinator.recovers == 1, "adapter did not delegate recovery exactly once")
	_assert(String(recovered["details"]["persistence_owner"]) == OwnershipMap.EXISTING_PERSISTENCE_OWNER_ID, "recovery owner mismatch")

	var report := adapter.get_report()
	_assert(int(report["persists"]) == 1 and int(report["recoveries"]) == 1, "adapter counters wrong")
	_assert(not bool(report["private_filesystem"]) and not bool(report["private_save_format"]), "private persistence reappeared")

	if failures.is_empty():
		print("[p6-r3-persistence] all %d assertions passed" % assertions)
		print("[p6-r3-persistence][stage] PRIVATE_PERSISTENCE_REMOVED_PASS")
		quit(0)
	else:
		print("[p6-r3-persistence] %d/%d ASSERTIONS FAILED" % [failures.size(), assertions])
		quit(1)
