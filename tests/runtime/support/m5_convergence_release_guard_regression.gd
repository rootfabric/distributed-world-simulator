extends SceneTree

const Barrier = preload("res://scripts/runtime/networked_gameplay/m5/m5_convergence_barrier.gd")

const PLAYER_G1 := "1111111111111111111111111111111111111111111111111111111111111111"
const PLAYER_G2 := "2222222222222222222222222222222222222222222222222222222222222222"
const PLAYER_MISMATCH := "3333333333333333333333333333333333333333333333333333333333333333"
const ITEM_G1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const ITEM_G2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var g1 := Barrier.generation_id(1, PLAYER_G1, ITEM_G1)
	var prepare_g1 := {
		"id": g1,
		"player_checksum": PLAYER_G1,
		"item_checksum": ITEM_G1,
	}
	var a_g1 := _prepared_report(g1, PLAYER_G1, ITEM_G1)
	var b_g1 := _prepared_report(g1, PLAYER_G1, ITEM_G1)
	var initial := Barrier.evaluate_coordinator_generation(
		g1, PLAYER_G1, ITEM_G1, false, a_g1, b_g1
	)
	_assert(String(initial.get("action", "")) == Barrier.COORDINATOR_RELEASE, "both prepared G1 allow release attempt")

	# Deterministic critical ordering: both clients have acknowledged G1, then
	# authoritative state advances on A before A consumes release G1.
	var stale_player_release := Barrier.evaluate_prepared_release(
		g1,
		PLAYER_G1,
		ITEM_G1,
		prepare_g1,
		g1,
		PLAYER_G2,
		ITEM_G1
	)
	_assert(String(stale_player_release.get("action", "")) == Barrier.CLIENT_REVOKE, "player checksum advance revokes prepared G1 before release consumption")
	_assert(String(stale_player_release.get("current_player_checksum", "")) == PLAYER_G2, "changed current player checksum is exposed by the guard")
	_assert(String(stale_player_release.get("action", "")) != Barrier.CLIENT_CONSUME_RELEASE, "stale G1 release is never consumed after player advance")

	var stale_item_release := Barrier.evaluate_prepared_release(
		g1,
		PLAYER_G1,
		ITEM_G1,
		prepare_g1,
		g1,
		PLAYER_G1,
		ITEM_G2
	)
	_assert(String(stale_item_release.get("action", "")) == Barrier.CLIENT_REVOKE, "Item Graph checksum advance revokes prepared G1 before release consumption")
	_assert(String(stale_item_release.get("current_item_checksum", "")) == ITEM_G2, "changed current Item Graph checksum is exposed by the guard")

	var a_revoked := _ready_report(PLAYER_G2, ITEM_G1)
	_assert(not bool(a_revoked.get("convergence_prepared", true)), "revoked client no longer advertises prepared acknowledgement for G1")
	_assert(String(a_revoked.get("convergence_prepare_id", "stale")) == "", "revoked client clears stale prepared generation G1")
	_assert(String(a_revoked.get("player_checksum", "")) == PLAYER_G2, "revoked client publishes the changed current player checksum")
	var stale_coordinator := Barrier.evaluate_coordinator_generation(
		g1, PLAYER_G1, ITEM_G1, true, a_revoked, b_g1
	)
	_assert(String(stale_coordinator.get("action", "")) == Barrier.COORDINATOR_ABANDON, "coordinator abandons G1 after prepared acknowledgement is revoked")
	_assert(String(stale_coordinator.get("action", "")) != Barrier.COORDINATOR_COMPLETE, "stale G1 cannot become coordinator COMPLETE")

	# A genuine mismatch can never be promoted to release or completion.
	var mismatch := Barrier.evaluate_coordinator_generation(
		g1,
		PLAYER_G1,
		ITEM_G1,
		false,
		_ready_report(PLAYER_G1, ITEM_G1),
		_ready_report(PLAYER_MISMATCH, ITEM_G1)
	)
	_assert(String(mismatch.get("action", "")) == Barrier.COORDINATOR_ABANDON, "genuine mismatched player checksums fail closed")

	# After G1 is abandoned, both clients converge on the new canonical pair.
	var g2 := Barrier.generation_id(2, PLAYER_G2, ITEM_G1)
	_assert(g2 != g1, "replacement convergence uses a new generation identity")
	var prepare_g2 := {
		"id": g2,
		"player_checksum": PLAYER_G2,
		"item_checksum": ITEM_G1,
	}
	var a_g2 := _prepared_report(g2, PLAYER_G2, ITEM_G1)
	var b_g2 := _prepared_report(g2, PLAYER_G2, ITEM_G1)
	var replacement_prepare := Barrier.evaluate_coordinator_generation(
		g2, PLAYER_G2, ITEM_G1, false, a_g2, b_g2
	)
	_assert(String(replacement_prepare.get("action", "")) == Barrier.COORDINATOR_RELEASE, "new canonical pair G2 can be released after both prepare it")

	var a_release_g2 := Barrier.evaluate_prepared_release(
		g2,
		PLAYER_G2,
		ITEM_G1,
		prepare_g2,
		g2,
		PLAYER_G2,
		ITEM_G1
	)
	var b_release_g2 := Barrier.evaluate_prepared_release(
		g2,
		PLAYER_G2,
		ITEM_G1,
		prepare_g2,
		g2,
		PLAYER_G2,
		ITEM_G1
	)
	_assert(String(a_release_g2.get("action", "")) == Barrier.CLIENT_CONSUME_RELEASE, "A consumes release only while exact G2 target is current")
	_assert(String(b_release_g2.get("action", "")) == Barrier.CLIENT_CONSUME_RELEASE, "B consumes release only while exact G2 target is current")

	var a_released := _released_report(g2, PLAYER_G2, ITEM_G1)
	var before_b_release := Barrier.evaluate_coordinator_generation(
		g2, PLAYER_G2, ITEM_G1, true, a_released, b_g2
	)
	_assert(String(before_b_release.get("action", "")) == Barrier.COORDINATOR_WAIT, "one consumed release cannot complete generation")
	var b_released := _released_report(g2, PLAYER_G2, ITEM_G1)
	var valid_complete := Barrier.evaluate_coordinator_generation(
		g2, PLAYER_G2, ITEM_G1, true, a_released, b_released
	)
	_assert(String(valid_complete.get("action", "")) == Barrier.COORDINATOR_COMPLETE, "both exact G2 releases are required before terminal completion")

	# Once a release is consumed, that acknowledgement is monotonic for the
	# generation. Later drift is an explicit fail-closed error, never a hidden
	# transition back to READY_TO_CONVERGE.
	var hold_g2 := Barrier.evaluate_consumed_release_integrity(
		g2,
		PLAYER_G2,
		ITEM_G1,
		prepare_g2,
		g2,
		"",
		PLAYER_G2,
		ITEM_G1
	)
	_assert(String(hold_g2.get("action", "")) == Barrier.CLIENT_HOLD_RELEASE, "consumed G2 remains durably held while coordinator completion is pending")

	var complete_g2 := Barrier.evaluate_consumed_release_integrity(
		g2,
		PLAYER_G2,
		ITEM_G1,
		prepare_g2,
		g2,
		g2,
		PLAYER_G2,
		ITEM_G1
	)
	_assert(String(complete_g2.get("action", "")) == Barrier.CLIENT_COMPLETE_RELEASE, "exact consumed G2 completes only when coordinator completes the same generation")

	var drift_after_release := Barrier.evaluate_consumed_release_integrity(
		g2,
		PLAYER_G2,
		ITEM_G1,
		prepare_g2,
		g2,
		"",
		PLAYER_MISMATCH,
		ITEM_G1
	)
	_assert(String(drift_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "authoritative drift after consumed release fails closed instead of revoking")

	var cleared_control_after_release := Barrier.evaluate_consumed_release_integrity(
		g2,
		PLAYER_G2,
		ITEM_G1,
		{},
		"",
		"",
		PLAYER_G2,
		ITEM_G1
	)
	_assert(String(cleared_control_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "control regression after consumed release fails closed instead of recycling generation")

	# Mutating the prepare payload under the same generation id is also fail-closed.
	var mutated_prepare := prepare_g2.duplicate(true)
	mutated_prepare["player_checksum"] = PLAYER_MISMATCH
	var mutated_target_decision := Barrier.evaluate_prepared_release(
		g2,
		PLAYER_G2,
		ITEM_G1,
		mutated_prepare,
		g2,
		PLAYER_G2,
		ITEM_G1
	)
	_assert(String(mutated_target_decision.get("action", "")) == Barrier.CLIENT_REVOKE, "same generation id with changed prepared target is rejected")

	print("M5 convergence release guard regression: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _prepared_report(generation: String, player_checksum: String, item_checksum: String) -> Dictionary:
	return {
		"state": "CONVERGENCE_PREPARED",
		"player_checksum": player_checksum,
		"item_checksum": item_checksum,
		"convergence_prepare_id": generation,
		"convergence_prepared": true,
		"convergence_release_id": "",
		"convergence_release_consumed": false,
	}


func _released_report(generation: String, player_checksum: String, item_checksum: String) -> Dictionary:
	return {
		"state": "CONVERGENCE_RELEASED",
		"player_checksum": player_checksum,
		"item_checksum": item_checksum,
		"convergence_prepare_id": generation,
		"convergence_prepared": true,
		"convergence_release_id": generation,
		"convergence_release_consumed": true,
	}


func _ready_report(player_checksum: String, item_checksum: String) -> Dictionary:
	return {
		"state": "READY_TO_CONVERGE",
		"player_checksum": player_checksum,
		"item_checksum": item_checksum,
		"convergence_prepare_id": "",
		"convergence_prepared": false,
		"convergence_release_id": "",
		"convergence_release_consumed": false,
	}


func _assert(condition: bool, message: String) -> void:
	assertions += 1
	if condition:
		print("PASS: %s" % message)
	else:
		failures.append(message)
		push_error("FAIL: %s" % message)
