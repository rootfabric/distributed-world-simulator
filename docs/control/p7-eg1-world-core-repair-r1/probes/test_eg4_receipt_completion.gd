extends "res://tools/network/eg4_client_worker.gd"

## Invoke the REAL inherited _drive() with a recording boundary, not a copy.
## Baseline must fail the incomplete-receipt cases; the patched worker must pass.
## This deterministic lifecycle test is not the real-process EG4 acceptance.

class RecordingBoundary:
	extends RefCounted
	var sent: Array = []
	func send_to_peer(_peer: String, frame: Dictionary) -> Dictionary:
		sent.append(frame.duplicate(true))
		return {"success": true}

const SESSION := "gateway-session/eg2/eg4-alpha-2cc76f0289/1"
const EXPECTED_IDS := [
	"operation/eg4/l2/alpha-w1-0000",
	"operation/eg4/l2/alpha-w1-0001",
	"operation/eg4/l2/move-ack/gateway-session-eg2-eg4-alpha-2cc76f0289-1/100",
	"operation/eg4/l2/move-ack/gateway-session-eg2-eg4-alpha-2cc76f0289-1/101",
	"operation/eg4/l2/move-ack/gateway-session-eg2-eg4-alpha-2cc76f0289-1/102",
	"operation/eg4/l2/move-ack/gateway-session-eg2-eg4-alpha-2cc76f0289-1/103",
]
var checks := 0
var errors: Array[String] = []


func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		errors.append(label)
		print("[eg4-completion][FAIL] %s" % label)


func _reset_case(receipts: Array) -> void:
	_options.clear()
	for key in OPTION_SPEC:
		_options[key] = OPTION_SPEC[key]["default"]
	_options["client-session-id"] = "client-session/eg4/alpha"
	_options["demand-worlds"] = ",".join(Support.demand_projection_worlds(4))
	_boundary = RecordingBoundary.new()
	_connected = true
	_placed = true
	_finished = false
	_world_ready = {"gateway_session_id": SESSION}
	_wave = 2
	_ops_expected = 2
	_movements_sent_this_wave = 2
	_movement_seq = 104
	_demand_withdrawn = false
	_withdraw_ack = false
	_detach_sent = false
	_detached_ack = false
	_withdraw_sent_at_ms = 0
	_receipts = receipts.duplicate(true)


func _initialize() -> void:
	var complete: Array = []
	for operation_id in EXPECTED_IDS:
		complete.append({"operation_id": operation_id})
	var missing: Array = complete.slice(0, 5)
	var duplicate: Array = missing.duplicate(true)
	duplicate.append(complete[0].duplicate(true))
	var injected: Array = missing.duplicate(true)
	injected.append({"operation_id": "operation/eg4/inj-000001"})
	var foreign: Array = missing.duplicate(true)
	foreign.append({"operation_id": String(EXPECTED_IDS[5]).replace("alpha", "beta")})
	var extra: Array = complete.duplicate(true)
	extra.append(complete[0].duplicate(true))
	var malformed: Array = missing.duplicate(true)
	malformed.append("not-a-receipt")
	var negatives := {
		"empty": [], "missing-last": missing, "duplicate": duplicate,
		"injected": injected, "foreign-session": foreign,
		"extra": extra, "malformed": malformed,
	}
	for label in negatives:
		_reset_case(negatives[label])
		_drive()
		_check(not _demand_withdrawn, "%s:withdrawal-must-wait" % label)
		_check(_boundary.sent.is_empty(), "%s:no-outbound-withdrawal" % label)
	var reversed: Array = complete.duplicate(true)
	reversed.reverse()
	for ordered in [complete, reversed]:
		_reset_case(ordered)
		_drive()
		_check(_demand_withdrawn, "complete:withdrawal-permitted")
		_check(_boundary.sent.size() == 1, "complete:one-withdrawal")
		_check(not _detach_sent, "complete:no-premature-detach")
	_reset_case(missing)
	_drive()
	_check(not _demand_withdrawn, "late-receipt:wait")
	_receipts.append(complete[5].duplicate(true))
	_drive()
	_check(_demand_withdrawn, "late-receipt:release")
	_check(_boundary.sent.size() == 1, "late-receipt:one-withdrawal-no-resend")
	print(JSON.stringify({"test": "eg4_receipt_completion", "assertions": checks,
		"verdict": "PASS" if errors.is_empty() else "FAIL", "failures": errors}))
	_finished = true
	quit(0 if errors.is_empty() else 1)


func _process(_delta: float) -> bool:
	return false
