extends "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_seam.gd"

func success(result: Dictionary, description: String) -> bool:
	if not bool(result.get("success", false)):
		print("MVP6_C9_REMOVE_FAILURE label=%s payload=%s" % [description, JSON.stringify(result, "", true, true)])
	return super.success(result, description)
