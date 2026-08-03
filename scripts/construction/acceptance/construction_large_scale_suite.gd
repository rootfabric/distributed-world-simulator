extends RefCounted

const Harness = preload("res://scripts/construction/acceptance/construction_large_scale_harness.gd")
const Profile = preload("res://scripts/construction/acceptance/construction_scale_profile.gd")
const Report = preload("res://scripts/construction/acceptance/construction_scale_report.gd")

static func run(profile: Dictionary) -> Dictionary:
	var harness := Harness.new()
	var setup_result := harness.setup(profile)
	if not bool(setup_result.get("success", false)):
		return setup_result
	var result := harness.finish()
	if not bool(result.get("success", false)):
		return result
	var report: Dictionary = result.report
	var validation := Report.validate(report)
	if not bool(validation.get("success", false)):
		return {"success": false, "error_code": "CONSTRUCTION_SCALE_SUITE_REPORT_INVALID", "message": "CONSTRUCTION_SCALE_SUITE_REPORT_INVALID", "details": {"cause": validation}}
	return {"success": true, "error_code": "", "message": "", "report": report, "state": result.state}

static func profile_from_config(profile_id: String, values: Dictionary) -> Dictionary:
	return Profile.create(profile_id, values)
