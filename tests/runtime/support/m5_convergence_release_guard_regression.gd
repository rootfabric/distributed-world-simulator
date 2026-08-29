extends SceneTree

const Barrier = preload("res://scripts/runtime/networked_gameplay/m5/m5_convergence_barrier.gd")

const PLAYER_G1 := "1111111111111111111111111111111111111111111111111111111111111111"
const PLAYER_G2 := "2222222222222222222222222222222222222222222222222222222222222222"
const PLAYER_G3 := "3333333333333333333333333333333333333333333333333333333333333333"
const ITEM_G1 := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const ITEM_G2 := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const OWNER_A := "authority/m5"
const OWNER_B := "authority/other"

var failures: Array[String] = []
var assertions := 0


func _init() -> void:
	var observed_g1 := _observation(PLAYER_G1, 10, 100, OWNER_A, 1)
	var forward_g2 := _observation(PLAYER_G2, 11, 101, OWNER_A, 1)
	var forward_g3 := _observation(PLAYER_G3, 12, 102, OWNER_A, 1)
	var g1 := Barrier.generation_id(1, PLAYER_G1, ITEM_G1)
	var prepare_g1 := _prepare(g1, observed_g1, ITEM_G1)

	_assert(Barrier.observations_identical(observed_g1, observed_g1.duplicate(true)), "identical observed-state identities compare equal")
	_assert(not Barrier.observations_identical(observed_g1, forward_g2), "different authoritative snapshots are distinct observed-state identities")

	var initial := Barrier.evaluate_coordinator_generation(
		g1,
		PLAYER_G1,
		ITEM_G1,
		false,
		_prepared_report(g1, observed_g1, ITEM_G1),
		_prepared_report(g1, observed_g1, ITEM_G1)
	)
	_assert(String(initial.get("action", "")) == Barrier.COORDINATOR_RELEASE, "both clients pinned to exact G1 allow coordinator release")

	# After exact PREPARE acknowledgement, live player state may advance normally.
	# Release is still for the pinned observed-state identity, not for an immutable world.
	var forward_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		forward_g2,
		ITEM_G1
	)
	_assert(String(forward_release.get("action", "")) == Barrier.CLIENT_CONSUME_RELEASE, "forward player revision/tick after PREPARE may consume pinned release")
	_assert(String(forward_release.get("current_player_checksum", "")) == PLAYER_G2, "forward live checksum remains observable in release decision")

	var same_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		observed_g1,
		ITEM_G1
	)
	_assert(String(same_release.get("action", "")) == Barrier.CLIENT_CONSUME_RELEASE, "exact unchanged observation may also consume release")

	var item_drift_before_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		forward_g2,
		ITEM_G2
	)
	_assert(String(item_drift_before_release.get("action", "")) == Barrier.CLIENT_REVOKE, "Item Graph drift before release remains fail-closed")

	var revision_regression_before_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		_observation(PLAYER_G2, 9, 101, OWNER_A, 1),
		ITEM_G1
	)
	_assert(String(revision_regression_before_release.get("action", "")) == Barrier.CLIENT_REVOKE, "player revision regression before release is rejected")
	_assert(String(revision_regression_before_release.get("reason", "")) == "PLAYER_REVISION_REGRESSED_AFTER_OBSERVATION", "revision regression has explicit reason")

	var tick_regression_before_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		_observation(PLAYER_G2, 11, 99, OWNER_A, 1),
		ITEM_G1
	)
	_assert(String(tick_regression_before_release.get("action", "")) == Barrier.CLIENT_REVOKE, "server tick regression before release is rejected")
	_assert(String(tick_regression_before_release.get("reason", "")) == "PLAYER_SERVER_TICK_REGRESSED_AFTER_OBSERVATION", "tick regression has explicit reason")

	var owner_change_before_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		_observation(PLAYER_G2, 11, 101, OWNER_B, 1),
		ITEM_G1
	)
	_assert(String(owner_change_before_release.get("action", "")) == Barrier.CLIENT_REVOKE, "authority owner change before release is rejected")

	var epoch_change_before_release := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		_observation(PLAYER_G2, 11, 101, OWNER_A, 2),
		ITEM_G1
	)
	_assert(String(epoch_change_before_release.get("action", "")) == Barrier.CLIENT_REVOKE, "authority epoch change before release is rejected")

	var checksum_only_mutation := prepare_g1.duplicate(true)
	checksum_only_mutation["player_checksum"] = PLAYER_G2
	var checksum_only_mutation_decision := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		checksum_only_mutation,
		g1,
		forward_g2,
		ITEM_G1
	)
	_assert(String(checksum_only_mutation_decision.get("action", "")) == Barrier.CLIENT_REVOKE, "control checksum cannot disagree with pinned player observation")

	var mutated_prepare := prepare_g1.duplicate(true)
	mutated_prepare["player_observation"] = forward_g2
	var mutated_prepare_decision := Barrier.evaluate_prepared_release(
		g1,
		observed_g1,
		ITEM_G1,
		mutated_prepare,
		g1,
		forward_g2,
		ITEM_G1
	)
	_assert(String(mutated_prepare_decision.get("action", "")) == Barrier.CLIENT_REVOKE, "mutated pinned observation under same generation is rejected")

	var a_released := _released_report(g1, observed_g1, ITEM_G1)
	var b_prepared := _prepared_report(g1, observed_g1, ITEM_G1)
	var one_release := Barrier.evaluate_coordinator_generation(
		g1, PLAYER_G1, ITEM_G1, true, a_released, b_prepared
	)
	_assert(String(one_release.get("action", "")) == Barrier.COORDINATOR_WAIT, "one durable release acknowledgement cannot complete generation")

	var b_released := _released_report(g1, observed_g1, ITEM_G1)
	var both_released := Barrier.evaluate_coordinator_generation(
		g1, PLAYER_G1, ITEM_G1, true, a_released, b_released
	)
	_assert(String(both_released.get("action", "")) == Barrier.COORDINATOR_COMPLETE, "both durable releases for pinned G1 complete coordinator")

	var hold_forward := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		"",
		forward_g3,
		ITEM_G1
	)
	_assert(String(hold_forward.get("action", "")) == Barrier.CLIENT_HOLD_RELEASE, "forward live player progression after release remains a valid held acknowledgement")
	_assert(String(hold_forward.get("current_player_checksum", "")) == PLAYER_G3, "post-release forward checksum is exposed without invalidating pinned generation")

	var revision_regression_after_release := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		"",
		_observation(PLAYER_G2, 9, 101, OWNER_A, 1),
		ITEM_G1
	)
	_assert(String(revision_regression_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "revision regression after consumed release fails closed")
	_assert(String(revision_regression_after_release.get("reason", "")) == "PLAYER_REVISION_REGRESSED_AFTER_OBSERVATION", "post-release revision regression remains named")

	var tick_regression_after_release := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		"",
		_observation(PLAYER_G2, 11, 99, OWNER_A, 1),
		ITEM_G1
	)
	_assert(String(tick_regression_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "server tick regression after consumed release fails closed")

	var owner_change_after_release := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		"",
		_observation(PLAYER_G2, 11, 101, OWNER_B, 1),
		ITEM_G1
	)
	_assert(String(owner_change_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "authority owner change after consumed release fails closed")

	var epoch_change_after_release := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		"",
		_observation(PLAYER_G2, 11, 101, OWNER_A, 2),
		ITEM_G1
	)
	_assert(String(epoch_change_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "authority epoch change after consumed release fails closed")

	var item_drift_after_release := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		"",
		forward_g2,
		ITEM_G2
	)
	_assert(String(item_drift_after_release.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "Item Graph drift after consumed release fails closed")
	_assert(String(item_drift_after_release.get("reason", "")) == "ITEM_GRAPH_ADVANCED_AFTER_RELEASE", "post-release Item Graph drift has explicit reason")

	var cleared_control := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		{},
		"",
		"",
		forward_g2,
		ITEM_G1
	)
	_assert(String(cleared_control.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "control generation regression after release fails closed")

	var complete_forward := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		g1,
		forward_g3,
		ITEM_G1
	)
	_assert(String(complete_forward.get("action", "")) == Barrier.CLIENT_COMPLETE_RELEASE, "coordinator COMPLETE accepts monotonic descendant of pinned observation")

	var complete_owner_change := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		g1,
		_observation(PLAYER_G3, 12, 102, OWNER_B, 1),
		ITEM_G1
	)
	_assert(String(complete_owner_change.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "COMPLETE cannot hide authority owner change")

	var complete_item_drift := Barrier.evaluate_consumed_release_integrity(
		g1,
		observed_g1,
		ITEM_G1,
		prepare_g1,
		g1,
		g1,
		forward_g3,
		ITEM_G2
	)
	_assert(String(complete_item_drift.get("action", "")) == Barrier.CLIENT_FAIL_RELEASE, "COMPLETE cannot hide Item Graph drift")

	var genuine_mismatch := Barrier.evaluate_coordinator_generation(
		g1,
		PLAYER_G1,
		ITEM_G1,
		false,
		_ready_report(observed_g1, ITEM_G1),
		_ready_report(forward_g2, ITEM_G1)
	)
	_assert(String(genuine_mismatch.get("action", "")) == Barrier.COORDINATOR_ABANDON, "coordinator still rejects mismatched current player observations")

	print("M5 convergence release guard regression: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _observation(
	checksum: String,
	revision: int,
	server_tick: int,
	authority_owner_id: String,
	authority_epoch: int
) -> Dictionary:
	return {
		"checksum": checksum,
		"revision": revision,
		"server_tick": server_tick,
		"authority_owner_id": authority_owner_id,
		"authority_epoch": authority_epoch,
	}


func _prepare(generation: String, observation: Dictionary, item_checksum: String) -> Dictionary:
	return {
		"id": generation,
		"player_checksum": String(observation.get("checksum", "")),
		"player_observation": observation.duplicate(true),
		"item_checksum": item_checksum,
	}


func _prepared_report(generation: String, observation: Dictionary, item_checksum: String) -> Dictionary:
	return {
		"state": "CONVERGENCE_PREPARED",
		"player_checksum": String(observation.get("checksum", "")),
		"player_observation": observation.duplicate(true),
		"prepared_player_observation": observation.duplicate(true),
		"item_checksum": item_checksum,
		"convergence_prepare_id": generation,
		"convergence_prepared": true,
		"convergence_release_id": "",
		"convergence_release_consumed": false,
	}


func _released_report(generation: String, observation: Dictionary, item_checksum: String) -> Dictionary:
	return {
		"state": "CONVERGENCE_RELEASED",
		"player_checksum": String(observation.get("checksum", "")),
		"player_observation": observation.duplicate(true),
		"prepared_player_observation": observation.duplicate(true),
		"item_checksum": item_checksum,
		"convergence_prepare_id": generation,
		"convergence_prepared": true,
		"convergence_release_id": generation,
		"convergence_release_consumed": true,
	}


func _ready_report(observation: Dictionary, item_checksum: String) -> Dictionary:
	return {
		"state": "READY_TO_CONVERGE",
		"player_checksum": String(observation.get("checksum", "")),
		"player_observation": observation.duplicate(true),
		"prepared_player_observation": {},
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
