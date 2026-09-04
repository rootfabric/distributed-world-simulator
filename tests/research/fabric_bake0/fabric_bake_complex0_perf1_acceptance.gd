extends SceneTree

const Fixture = preload("res://tests/research/fabric_bake0/fabric_bake_complex0_fixture.gd")

const SCALE_COUNTS: Array[int] = [500, 2000]
const MAX_TRANSACTION_MS := {500: 10000, 2000: 60000}
const MAX_GROWTH_FACTOR := 8.0
const EXPECTED_TRANSACTION_CHECKSUMS := {
	500: "a606954658e0ab87eca2cb1b6ff2280b4ad7ebd56f125e3fbad3767e103ed828",
	2000: "b421928b2a5db9e700476d9d70e2be6b6ecde8bfe778b2511a1efaf85d082ebd",
}

var _checks := 0
var _failed := false
var _measurements: Dictionary = {}

func _initialize() -> void:
	for count in SCALE_COUNTS:
		if not _measure_scale(count):
			_finish()
			return
	var small_ms := float(_measurements[500]["transaction_ms"])
	var large_ms := float(_measurements[2000]["transaction_ms"])
	var growth := large_ms / maxf(1.0, small_ms)
	_require(growth <= MAX_GROWTH_FACTOR, "transaction growth factor", {
		"growth_factor": growth,
		"maximum": MAX_GROWTH_FACTOR,
		"part_growth": 4.0,
	})
	_measurements["transaction_growth_factor"] = growth
	_finish()

func _measure_scale(count: int) -> bool:
	var started := Time.get_ticks_msec()
	var subject := Fixture.build(count)
	var build_ms := Time.get_ticks_msec() - started
	if not _require(bool(subject.get("success", false)), "%d subject build" % count, subject):
		return false

	started = Time.get_ticks_msec()
	var structural := Fixture.compile_structural(subject)
	var structural_ms := Time.get_ticks_msec() - started
	if not _require(bool(structural.get("success", false)), "%d structural preparation" % count, structural):
		return false

	started = Time.get_ticks_msec()
	var break_bundle := Fixture.make_break(subject, structural)
	var break_ms := Time.get_ticks_msec() - started
	if not _require(bool(break_bundle.get("success", false)), "%d canonical break preparation" % count, break_bundle):
		return false

	started = Time.get_ticks_msec()
	var compiled := Fixture.compile_transaction(break_bundle)
	var transaction_ms := Time.get_ticks_msec() - started
	if not _require(bool(compiled.get("success", false)), "%d topology transaction compile" % count, compiled):
		return false
	if not _require(transaction_ms <= int(MAX_TRANSACTION_MS[count]), "%d topology transaction budget" % count, {
		"actual_ms": transaction_ms,
		"maximum_ms": MAX_TRANSACTION_MS[count],
	}):
		return false
	var transaction: Dictionary = compiled["transaction"]
	if not _require(String(transaction["checksum"]) == String(EXPECTED_TRANSACTION_CHECKSUMS[count]), "%d deterministic transaction checksum" % count, {
		"actual": transaction["checksum"],
		"expected": EXPECTED_TRANSACTION_CHECKSUMS[count],
	}):
		return false
	if not _require(transaction["rebaked_components"].size() == 2, "%d split component count" % count, transaction):
		return false
	for component in transaction["rebaked_components"]:
		if not _require(not Dictionary(component["physical_bake_artifact"]).is_empty(), "%d physical artifact emitted" % count, component):
			return false

	_measurements[count] = {
		"parts": count,
		"build_ms": build_ms,
		"structural_ms": structural_ms,
		"break_ms": break_ms,
		"transaction_ms": transaction_ms,
		"transaction_checksum": String(transaction["checksum"]),
		"component_count": transaction["rebaked_components"].size(),
	}
	return true

func _finish() -> void:
	if _failed:
		printerr("FABRIC-BAKE COMPLEX0-PERF1 Acceptance: FAIL (%d successful assertions) measurements=%s" % [_checks, str(_measurements)])
		quit(1)
		return
	print("FABRIC-BAKE COMPLEX0-PERF1 Acceptance: PASS (%d assertions) measurements=%s" % [_checks, str(_measurements)])
	quit(0)

func _require(condition: bool, label: String, details = null) -> bool:
	if condition:
		_checks += 1
		return true
	_failed = true
	printerr("FABRIC-BAKE COMPLEX0-PERF1 FAILURE: %s details=%s" % [label, str(details)])
	return false
