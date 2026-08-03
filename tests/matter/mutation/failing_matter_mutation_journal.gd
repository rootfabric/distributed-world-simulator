extends RefCounted

const MatterUtilsScript = preload("res://scripts/simulation/matter/matter_contract_utils.gd")


func resolve(_request: Dictionary) -> Dictionary:
	return MatterUtilsScript.success({"status": "MISS"})


func record(_request: Dictionary, _result: Dictionary) -> Dictionary:
	return MatterUtilsScript.failure("INJECTED_MATTER_JOURNAL_COMMIT_FAILURE")
