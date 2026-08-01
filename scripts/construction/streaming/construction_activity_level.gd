extends RefCounted

const DORMANT := "DORMANT"
const SUMMARY := "SUMMARY"
const SIMULATED := "SIMULATED"
const PRESENTED := "PRESENTED"
const VALUES: Array[String] = [DORMANT, SUMMARY, SIMULATED, PRESENTED]

static func is_valid(value) -> bool:
	return typeof(value) == TYPE_STRING and VALUES.has(String(value))

static func rank(value: String) -> int:
	return VALUES.find(value)

static func max_level(left: String, right: String) -> String:
	return left if rank(left) >= rank(right) else right

static func min_level(left: String, right: String) -> String:
	return left if rank(left) <= rank(right) else right
