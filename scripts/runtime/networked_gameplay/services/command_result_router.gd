extends RefCounted

const ResultContract = preload("res://scripts/runtime/networked_gameplay/contracts/command_result.gd")
const SCHEMA := "planet_simulator.command_result_router.v1"
var _routed := 0

func route(message_id: String, operation_id: String, authority_epoch: int, result_revision: int, result: Dictionary) -> Dictionary:
	_routed += 1
	var succeeded := bool(result.get("success", false))
	return ResultContract.create(message_id, operation_id, "SUCCEEDED" if succeeded else "REJECTED", "" if succeeded else String(result.get("error_code", "COMMAND_REJECTED")), authority_epoch, maxi(result_revision, 0), result.get("details", {}).duplicate(true))

func get_report() -> Dictionary: return {"schema": SCHEMA, "routed": _routed}
