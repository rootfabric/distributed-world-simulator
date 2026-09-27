extends SceneTree

# R13 continuation regression: the gateway operation ledger capacity must
# cover the full interactive session envelope (2 players x 60 fixed ticks/s
# x gateway timeout 120 s = 14400 distinct held-input operations) while the
# P6 guard itself must stay fail-closed beyond its configured capacity.

const Protocol = preload("res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_process_protocol.gd")
const Ledger = preload("res://scripts/runtime/networked_gameplay/p6/p6_operation_ledger.gd")

var assertions := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, description: String) -> bool:
	assertions += 1
	if not ok:
		failures.append(description)
		push_error(description)
	return ok


func run() -> void:
	var cap: int = Protocol.MAX_INTERACTIVE_LEDGER_OPERATIONS
	check(cap >= 2 * 60 * 120, "capacity covers the two-player fixed-tick session envelope (14400)")
	var ledger = Ledger.new()
	check(bool(ledger.configure(cap).get("success", false)), "ledger accepts the interactive capacity")
	# Worst-case held-input envelope: every fixed tick of a full-length
	# session is a distinct applied operation for both players, plus the
	# configured headroom up to the exact capacity bound.
	var envelope: int = 2 * 60 * 120
	var rejected_at := -1
	for index in range(cap):
		var result: Dictionary = ledger.record_applied("player/mvp3/a", "operation/mvp3/budget/a/%d" % index) if index % 2 == 0 else ledger.record_applied("player/mvp3/b", "operation/mvp3/budget/b/%d" % index)
		if not bool(result.get("success", false)):
			rejected_at = index
			break
	check(rejected_at < 0 or rejected_at >= envelope, "no legitimate envelope operation is rejected by capacity (first rejection index: %d)" % rejected_at)
	# The guard itself stays fail-closed beyond the configured capacity.
	var beyond: Dictionary = ledger.record_applied("player/mvp3/a", "operation/mvp3/budget/overflow")
	check(String(beyond.get("error_code", "")) == "LEDGER_CAPACITY_EXCEEDED", "capacity enforcement beyond the bound still fails closed")
	check(bool(ledger.is_applied("player/mvp3/a", "operation/mvp3/budget/a/0")), "applied operations remain queryable")
	var report: Dictionary = ledger.get_report()
	check(int(report.get("tracked_count", 0)) == cap, "tracked count equals the configured capacity after saturation")
	var replay: Dictionary = ledger.record_applied("player/mvp3/a", "operation/mvp3/budget/a/0")
	check(bool(replay.get("success", false)) and not bool(replay.get("details", {}).get("applied_now", true)), "exact replay of an applied operation consumes no new slot")
	var passed := failures.is_empty()
	print("MVP3_LEDGER_BUDGET assertions=%d failures=%d passed=%s" % [assertions, failures.size(), passed])
	quit(0 if passed else 1)
