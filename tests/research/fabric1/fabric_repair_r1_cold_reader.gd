extends SceneTree

const U = preload("res://scripts/research/fabric_bake0/fabric_bake_contract_utils_v1.gd")
const Runtime = preload("res://scripts/research/fabric_bake0/bridge4_canonical_world_runtime_v1.gd")

func _init() -> void:
	var path := OS.get_environment("FABRIC_R1_COLD_STATE")
	if path.is_empty() or not FileAccess.file_exists(path):
		_fail("cold state missing")
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("cold state parse failed")
		return
	var payload: Dictionary = parsed
	if not U.validate_checksum(payload).success:
		_fail("cold state checksum invalid")
		return
	var snapshot: Dictionary = payload.snapshot
	var matter: Dictionary = payload.matter
	var authority: Dictionary = payload.authority
	var events: Array = payload.events
	var runtime := Runtime.new()
	var recovered := runtime.recover(snapshot, matter, authority, events, {}, 0)
	if not recovered.success or recovered.details.recovery_kind != "COLD":
		_fail("cold rebuild without derived capsule failed: %s" % recovered)
		return
	var executed := runtime.execute(snapshot, matter, [1.0, 0.0], authority)
	if not executed.success:
		_fail("cold rebuilt execution failed")
		return
	if _max_error(executed.details.boundary_flow, payload.expected_boundary_flow) > 2.0e-8:
		_fail("cold boundary flow mismatch")
		return
	if absf(float(executed.details.boundary_power) - float(payload.expected_boundary_power)) > 2.0e-8:
		_fail("cold boundary power mismatch")
		return
	var status := runtime.status()
	if int(status.construct_revision) != int(payload.expected_revision) or status.event_ledger != events:
		_fail("cold canonical revision/event history mismatch")
		return
	if status.frontier_hash != payload.expected_frontier or int(status.canonical_writes) != 0:
		_fail("cold source binding/authority boundary mismatch")
		return
	var corrupt := {"schema": "corrupt", "checksum": "bad"}
	var discard_runtime := Runtime.new()
	var discarded := discard_runtime.recover(snapshot, matter, authority, events, corrupt, 0)
	if not discarded.success or discarded.details.recovery_kind != "COLD":
		_fail("corrupt derived capsule was not safely discarded")
		return
	print("FABRIC_REPAIR_R1_COLD_READER_HASH=%s" % U.canonical_hash({
		"payload": payload.checksum,
		"flow": executed.details.boundary_flow,
		"power": executed.details.boundary_power,
		"frontier": status.frontier_hash,
		"events": status.event_ledger,
	}))
	print("FABRIC-REPAIR-R1 COLD READER: PASS")
	quit(0)

func _max_error(left: Array, right: Array) -> float:
	var result := 0.0
	for index in range(mini(left.size(), right.size())):
		result = maxf(result, absf(float(left[index]) - float(right[index])))
	return result

func _fail(message: String) -> void:
	push_error(message)
	print("FABRIC-REPAIR-R1 COLD READER: FAIL")
	quit(1)
