extends RefCounted

static func write(path: String, summary: Dictionary) -> Dictionary:
	if path.strip_edges().is_empty(): return {"success": false, "error_code": "JUNIT_PATH_INVALID"}
	var scenarios: Array = summary.get("scenarios", [])
	var failures := int(summary.get("failed_count", 0))
	var lines: Array[String] = ['<?xml version="1.0" encoding="UTF-8"?>']
	lines.append('<testsuite name="PlanetSimulator.NetworkProcessHarness" tests="%d" failures="%d" time="%.3f">' % [scenarios.size(), failures, float(summary.get("duration_seconds", 0.0))])
	for scenario_value in scenarios:
		var scenario: Dictionary = scenario_value
		lines.append('  <testcase classname="network.process" name="%s" time="%.3f">' % [_escape(String(scenario.get("id", "unknown"))), float(scenario.get("duration_seconds", 0.0))])
		if not bool(scenario.get("passed", false)):
			var code := String(scenario.get("failure_code", "HARNESS_FAILED"))
			var message := String(scenario.get("message", code))
			lines.append('    <failure type="%s" message="%s">%s</failure>' % [_escape(code), _escape(message), _escape(JSON.stringify(scenario))])
		lines.append("  </testcase>")
	lines.append("</testsuite>")
	var directory := path.get_base_dir()
	if not directory.is_empty(): DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return {"success": false, "error_code": "JUNIT_WRITE_FAILED"}
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return {"success": true}

static func _escape(value: String) -> String:
	return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;")
